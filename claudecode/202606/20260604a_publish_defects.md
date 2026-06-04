# 작업 지침 — Phase 3b 후속: publish 결함 2건 수정 (소형 패치)

> 작성: 김대리 (claude.ai) / 수행: 김과장 (Claude Code) / 결재: 부장님(kodeholic, GO 2026-06-04)
> 토픽: 3b ★정지점 2 코드 검토(김대리 직접 정독)에서 발견한 결함 2건. **소형 패치 — 새 기능 없음.**
> 대상: `sdk/domain/local-endpoint.js` (`_publishOne`) + `sdk/transport/transport.js`(`enrichPublishIntent`/`_parseSsrcPair` — 필요 시).
> 직전: `20260603s` Phase 3b A~F 완료(미커밋). 본 패치 후 3d join orchestration 으로 진행.

---

## §0 의무 점검
1. `sdk/domain/local-endpoint.js` `_publishOne` / `_learnTrackId` 정독.
2. `sdk/transport/transport.js` `addPublishTrack` / `enrichPublishIntent` / `_parseSsrcPair` 정독.
3. **core/ 무수정.** 두 파일만 수정. 다른 변경 금지.
4. 두 번 실패하면 중단·보고(원칙).

---

## §1 결함 1 (중간) — 다중 video 트랙 mid 매칭 미확정

**현상**: `_publishOne` 이 `enrichPublishIntent([intentTrack])` 에 `intentTrack.mid = tx.mid` 를 넘긴다. `enrichPublishIntent` 의 `_parseSsrcPair(kind, mid)` 가 그 mid 로 m-line 을 구분해 ssrc 를 집는다.

**위험**: camera + screen 처럼 **video m-line 이 2개**일 때, `tx.mid` 가 정확히 채워져 있어야 각자 ssrc 를 집는다. 만약 mid 가 `null` 로 넘어가면 `_parseSsrcPair` 의 `if (mid != null)` 가드가 빠지면서 **첫 video 섹션의 ssrc 를 무조건 집는다** — 둘째 video(screen)도 첫 video(camera) ssrc 를 받아 충돌.

**확인 먼저 (코드만으로 단정 금지)**:
- `addPublishTrack` 은 내부에서 `_reNegoPublish`(= `setLocalDescription`)를 await 한 뒤 `tx` 반환. 즉 `_publishOne` 이 `tx.mid` 읽는 시점엔 `setLocalDescription` 이 끝나 **mid 가 채워져 있을 가능성이 높다.** 하지만 이건 webrtc 구현 의존 — **단정하지 말고 검증.**
- **검증 방법**: `addPublishTrack` 반환 직후 `tx.mid` 가 non-null 인지 assert/로그. 단일 트랙 + (가능하면) camera 후 screen 2개 트랜시버 상태에서 각 `tx.mid` 가 서로 다른 값인지 확인.

**수정 (검증 결과별)**:
- **mid 가 반환 시점에 항상 채워짐이 확인되면**: 코드 변경 불요. `_publishOne` 에 **방어 가드만 추가** — `if (mid == null) throw new Error("addPublishTrack: tx.mid null after reNego (mid 매칭 불가)")`. enrich 에 null mid 가 흘러들어 첫 ssrc 오집되는 사고를 원천 차단.
- **mid 가 간혹 null 이면(webrtc 타이밍)**: `addPublishTrack` 이 mid 확정을 보장하도록 — `_reNegoPublish` 후 `tx.mid` 가 null 이면 한 틱 양보(`await Promise.resolve()`) 또는 `pubPc.getTransceivers()` 로 mid 재확인. 확정 못 하면 throw(위 가드).
- **`_parseSsrcPair` 자체는 손대지 말 것** — mid 가 정상이면 이미 옳다. mid 보장이 책임 위치.

**판단 후 보고**: 검증 결과(mid 채워지는 타이밍) + 택한 수정.

---

## §2 결함 2 (작음, 실재) — `_publishOne` 에러 경로 누수

**현상**: `_publishOne` 에서 `await this.sig.request(OP.PUBLISH_TRACKS, body)` 가 reject(타임아웃/ACK_FAIL)되면, 그 앞에서 등록한 임시 키 `this.pipes.set(\`m:${mid}\`, pipe)` + 생성된 transceiver 가 **잔존**한다. try/catch 정리 없음. publish 실패 반복 시 누수 + 죽은 transceiver 가 다음 reNego SDP 에 낌.

**수정**:
- `_publishOne` 의 2단계(addPublishTrack) ~ 5단계(_learnTrackId) 를 try 로 감싸고, catch 에서:
  1. `this.pipes.delete(\`m:${mid}\`)` (임시 키 제거)
  2. transceiver 정리: `transport.deactivatePublishTrack(pipe)` 호출(이미 inactive 전환 + reNego 보유) 또는 동급 정리 경로. **단 setTrack 전이라 RTP 는 안 흐르므로**(replaceTrack(null) 상태) 송출 중단은 불요 — m-line 정리(inactive)만.
  3. `this.bus?.emit("publish:fail", { kind: spec.kind, source: spec.source, error: e?.message })`
  4. `throw e` (호출자에게 전파 — publishAudio/Video 가 상위로 올림)
- **mid 미확정으로 deactivate 가 어려우면**(transceiver 는 있으나 pipe 정리 경로 모호) — 최소 임시 키 제거 + transceiver.direction='inactive' + reNego. 판단 후 보고.

**주의**: catch 가 새 에러를 먹지 않도록(삼키기 금지) — 정리 후 반드시 rethrow. 호출자(publishAudio 등)는 이미 async 라 상위 await 가 받는다.

---

## §3 변경 영향 / 비변경
- **수정**: `sdk/domain/local-endpoint.js`(`_publishOne` try/catch + mid 가드), 필요 시 `sdk/transport/transport.js`(`addPublishTrack` mid 보장 — §1 검증 결과 의존).
- **불변**: signaling / pipe / endpoint 타입 / media-acquire / engine / sdp-builder / core 전부.
- `_parseSsrcPair` 손대지 말 것(§1).
- §3 밖 변경 금지. 발견은 *발견_사항* 으로만.

---

## §4 검증
- node 단위(mock): `_publishOne` reject 주입 시 `m:${mid}` 키 제거 + transceiver inactive 확인 / 정상 경로 회귀(track_id 학습 그대로).
- mid 가드: mid=null 주입 시 throw 확인.
- 기존 회귀(_t3b2_check.mjs / T3b1 / T3a / 2b) ALL PASS 유지.
- **다중 video(camera+screen) mid 매칭 실측은 Phase G(라이브)로 이월** — 본 패치는 가드/정리까지. mock 으로 닿는 데까지만.

---

## §5 산출물
- 수정 2파일(또는 1파일).
- 완료 보고: `context/202606/20260604a_publish_defects_done.md` —
  - §1 mid 타이밍 검증 결과 + 택한 수정
  - §2 에러 경로 정리 구조
  - 회귀 결과 / 발견_사항

---

*author: kodeholic (powered by Claude)*
