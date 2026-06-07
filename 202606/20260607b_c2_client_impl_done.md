// author: kodeholic (powered by Claude)
# 완료보고 20260607b — C2(송신/발행) 클라단독 구현 (§1~§4 + 잎)

> 지침: `design/20260607_client_api_c2_impl_guide.md`(결재 3건 반영본, 커밋 `b43b313`). 설계: `20260606_client_api_c2_send.md`(정정본).
> 결재 확정: 9-1 sugar 유지(+함의) / 9-2 통로만+상수 h/l만 / **9-3 정정 — suspend 불변, pauseUpstream 전용 게이트**.

---

## 결론

C2 **클라단독(★1 줄기 + 잎) 완결.** 발행 배치(협상 1회) + LocalStream 핸들 + source/publish 2축 + 잎(A/#9/B/C/동적조정). 기존 회귀 0(PTT/T3c/T3d/T3e ALL PASS) + **신규 배치 검증(_c2_check) ALL PASS**. #10 재발행=C1 §7 의존 격리(자리만), D/E/F 미진입. **커밋 안 함**(검토 후 GO).

변경: home 6파일 수정 +250/−52, 신규 2(local-stream.js, _c2_check.mjs).

---

## 구현 (guide §7 순서)

| § | 항목 | 파일 | 한 일 |
|---|---|---|---|
| §1 | 상수 | `constants.js`+`index.js` | `VideoPresets`(h/l만), `Degradation`, `StreamEvent`, `MuteCause` 신설 + 1급 export. `LocalStream` export |
| §1 | 배치 발행(#1·2·13) | `transport.js`+`local-endpoint.js` | `addPublishTrack(track,pipe,{renego})` 옵션 + `renegoPublish()` 신설(배치 1회). `_publishMany(items[])` = addTransceiver N → **renego 1회 → mid 확정 → PUBLISH_TRACKS 1 request → learn ×N → setTrack ×N**. `_publishOne=_publishMany([one])` 위임(결함1·2 가드 _rollbackPublish 흡수) |
| §2 | LocalStream + source/publish | `local-stream.js`(신)+`engine.js` | `LocalStream`(trackId 위임, `_sender` 비노출). `engine.source.{mic,camera,screen}`(준비=acquire, 캡처옵션 통로 #7) ⊥ `engine.publish(items[])→LocalStream[]` / `engine.unpublish(streams[])` |
| §3 | encodings 인자(#6) | `transport.js` | `addPublishTrack` 하드코딩 `[h,l]` → `pipe.encodings` 우선(미지정=default 폴백) |
| §4 잎 | A device-mute | `local-endpoint.js` | `_attachTrackLifecycle`: native `track.onmute`(5s debounce)→`pauseUpstream`+`StreamEvent.MUTED{cause:DEVICE}`. 앱 mute=`{cause:USER}` emit |
| §4 잎 | #9 ended 복구 | `local-endpoint.js`+`local-stream.js` | onended→`StreamEvent.ENDED`(screen 자동 unpublish 유지). `LocalStream.restart({deviceId})`=재획득+`swapTrack`(협상 0) |
| §4 잎 | **B pauseUpstream(★9-3 정정)** | `local-pipe.js`+`local-stream.js` | **suspend 손 안 댐.** `pauseUpstream/resumeUpstream` 전용 게이트 신설 — `this.track` 유지(프리뷰)+`replaceTrack(null)`+ACTIVE 유지. `_upstreamPaused` 플래그 |
| §4 잎 | C setProcessor | `local-endpoint.js`+`local-stream.js` | `setProcessor(proc)`/`stopProcessor()` — track 가공→`swapTrack`, 원본 보관 복원 |
| §4 잎 | 동적조정/setMaxLayer | `local-pipe.js`+`local-stream.js` | `LocalStream.setBitrate/setFramerate/setDegradation/setMaxLayer` 위임. setMaxLayer=encoding active 토글(h=전부/l=l만) |

---

## ★ 9-3 정정 반영 확인 (PTT 안 깸)

- **`LocalPipe.suspend/resume` 본문 0 변경** — PTT Power FSM(② 훅)의 STANDBY 전력관리(track 비움·장치 해제) 그대로.
- `pauseUpstream`(B)은 **별 메서드**(track 유지+sender null+ACTIVE) — suspend 와 분리. device-mute(A, track 죽음)=suspend / pauseUpstream(B, 프리뷰)=신설 게이트. **A·B 같은 suspend 매핑 안 함**(guide §9-3).
- `_ptt_check` ALL PASS — suspend/resume 경로 무변경 실증.

## blast radius (guide §8 불변 — 실증)

- `_publishOne→_publishMany([one])` 위임 + 본문 보존 → **단일 발행 동작 동일.** PTT half-duplex publish(`publishAudio/Video(duplex:'half')`)도 위임이라 무변경 → `_ptt_check` PASS.
- `addPublishTrack` renego 분리 = **옵션**(default true) — 직접 호출 경로 무변경.
- `enrichPublishIntent`/서버 PUBLISH_TRACKS 무변경(이미 배열). 결함1(tx.mid null)·결함2(reject 정리) 보존.

---

## 검증

- `node --check` 8파일(수정6+신규2) PASS.
- **mock 5종 ALL PASS**: `_ptt_check`/`_t3c_check`/`_t3d_check`/`_t3e_check`(회귀 0) + **`_c2_check`(신규)**.
- `_c2_check` 핵심 검증: publish([mic,cam]) → **addPublishTrack 2회 + renegoPublish 1회 + PUBLISH_TRACKS 1 request**(★배치=협상 1회) + LocalStream[2] + track_id 학습(alice_1/2) + setMuted→MUTE_UPDATE+MUTED{USER} + pauseUpstream(ACTIVE 유지) + **sugar(enableScreen)=publish([1])=협상 1회**(§9-1 함의 실증).

---

## 미착수 (의도적)

- **★3 #10 재연결 재발행** = C1 §7(미디어PC 재연결, 미구현) 의존 → `StreamEvent.REPUBLISHED` 자리만(발화 소스 없음). C1 서버작업 뒤.
- **D 동시성 락 / E stopTrackOnMute / F 모바일 재획득** = YAGNI 보류(설계·guide 강등). 미진입.
- **VideoPresets 전량(h90~h2160)** = 실수요 시(현 h/l만). encodings 통로는 깔림.

---

## ★ 종결

- **[결재]** home 6파일+신규2 diff 검토 후 GO → 한 커밋(+ context done 보고). _c2_check 포함 여부 알려주시면 그대로(권장: 포함 — 배치 회귀 안전망).
- **[보고]** #10/D/E/F 격리·보류는 설계대로. C2 클라단독 종결, 다음 = C3(수신 — RemoteStream + adaptiveStream + cross-sfu 수신) 또는 C1 §7 서버작업.

---

*author: kodeholic (powered by Claude)*
