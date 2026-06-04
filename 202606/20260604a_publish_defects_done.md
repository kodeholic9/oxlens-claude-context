// author: kodeholic (powered by Claude)
# 20260604a — publish 결함 2건 수정 완료 보고 (소형 패치)

> 지침: `claudecode/202606/20260604a_publish_defects.md`. 직전 3b(`20260603s`) A~F 위 패치.
> 대상: `sdk/domain/local-endpoint.js` (`_publishOne`) **단일 파일**. **커밋 전** — 검토 후 GO.

---

## §1 결함 1 (다중 video mid 매칭) — webrtc 실증 후 (a) 가드만

**검증 (코드 단정 금지, 헤드리스 Chrome 148 `_t3b2_pubseq.html` D/E 블록 + `_t3b2_cdp.mjs`)**:

| 측정 | 결과 |
|---|---|
| `tx.mid` addTransceiver 직후 | **null** |
| `tx.mid` createOffer 후(setLocalDescription 전) | **null** |
| `tx.mid` **setLocalDescription 후** | **"0"** (채워짐) |
| 다중(audio+video+video) setLocalDescription 후 | `["0","1","2"]` **모두 non-null + distinct** |

**결론**: `tx.mid` 는 **setLocalDescription 후 확정**. `addPublishTrack` 은 내부에서 `_reNegoPublish`(createOffer+**setLocalDescription**+setRemoteDescription)를 await 한 뒤 `tx` 반환 → `_publishOne` 이 `tx.mid` 읽는 시점엔 **항상 채워져 있음**. 다중 video(camera+screen)도 distinct mid 보장.

**수정 = (a) 방어 가드만** (코드 변경 최소):
- `_publishOne` 에 `const mid = tx.mid; if (mid == null) throw new Error("addPublishTrack: tx.mid null after reNego (mid 매칭 불가)")`.
- 근거: mid 채워짐이 확인됐으므로 보장 로직 불요. null 이 흘러 `enrich._parseSsrcPair` 의 `if(mid!=null)` 가드가 빠져 **첫 video ssrc 오집(camera↔screen 충돌)** 하는 사고만 원천 차단.
- **`_parseSsrcPair` 무수정**(지침 §1) — mid 정상이면 이미 옳음. 책임 위치 = mid 보장(가드).
- **`addPublishTrack`(transport.js) 무수정** — mid 보장 로직 불요(setLocalDescription 후 반환). 이 패치는 local-endpoint.js 단일 파일.

---

## §2 결함 2 (에러 경로 누수) — try/catch 정리 + rethrow

**현상**: `sig.request(PUBLISH_TRACKS)` reject(타임아웃/ACK_FAIL) 시 임시 키 `m:${mid}` + 생성된 transceiver 잔존(정리 없음). 반복 실패 시 누수 + 죽은 transceiver 가 다음 reNego SDP 에 낌.

**수정**: `_publishOne` 의 addPublishTrack ~ setTrack 을 `try` 로 감싸고 `catch`:
1. `if (mid != null) this.pipes.delete(\`m:${mid}\`)` — 임시 키 제거.
2. `await this.transport.deactivatePublishTrack(pipe)` (best-effort try) — transceiver `direction='inactive'` + reNego 로 m-line 정리. **setTrack 전이라 RTP 미흐름(replaceTrack(null) 상태) → 송출 중단 불요, m-line inactive 만**.
3. `this.bus?.emit("publish:fail", { kind, source, error })`.
4. `throw e` — **삼키기 금지**, 호출자(publishAudio/Video)로 전파.
- `mid` 를 try 밖 `let mid=null` 로 선언 → catch 에서 임시 키 존재 여부 판단(가드 실패=mid null=키 미등록 → delete skip).

---

## §3 검증 (`_t3b2_check.mjs` 확장)

`node sdk/domain/_t3b2_check.mjs` → **ALL PASS**:
```
[정상 회귀] 직렬화 순서 race-free / track_id 학습 / Map 재키잉 / camera CAMERA_READY / unpublish (그대로)
[결함1] tx.mid=null 주입 → throw(enrich 차단) + 임시 키 잔존 없음
[결함2] request reject → rethrow(code 4003 전파, 삼키기 금지) / 임시 키 m:7 제거 / deactivatePublishTrack 호출 / publish:fail emit
```
+ 회귀 T3b1 / T3a / 2b ALL PASS, index exports 40. 헤드리스 webrtc(D/E mid 타이밍) 실측 동반.

---

## §4 발견_사항 / 변경

**변경**: `sdk/domain/local-endpoint.js`(`_publishOne` mid 가드 + try/catch) 단일. `_t3b2_check.mjs`(검증 확장) + `_t3b2_pubseq.html`(mid 타이밍 D/E 블록 추가).
**불변**: transport.js(`_parseSsrcPair`/`addPublishTrack` 무수정) / signaling / pipe / endpoint 타입 / media-acquire / engine / core 전부.

**발견_사항**:
1. **mid 확정 = setLocalDescription 후**(§1 실증) — enrich 가 `localDescription.sdp` 읽으므로 정합. 향후 enrich 를 createOffer 직후·setLocalDescription 전 호출하면 ssrc/mid 둘 다 깨짐(주의 — 현 흐름은 안전).
2. **다중 video 실측은 Phase G 이월**(지침 §4): 가드/정리는 mock 으로 닿는 데까지 완료. 실제 camera+screen 2 video 동시 publish + ssrc 분리 일치는 라이브 E2E 에서 최종 확인.

- **다음**: Phase G 라이브 E2E 또는 3d join orchestration(부장님 선택 — 정지점 2 미결).

---

*author: kodeholic (powered by Claude)*
