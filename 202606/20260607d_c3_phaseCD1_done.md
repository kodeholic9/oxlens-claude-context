// author: kodeholic (powered by Claude)
# 완료보고 20260607d — C3(수신) Phase C + D-1 (대역폭 통제 본체)

> 작업지침: `design/20260607_client_api_c3_work_order.md` Phase C·D-1. 설계: `20260606_client_api_c3_recv.md`.
> 직전: 0607c(Phase A+B 핸들 표면, `4215087`).

---

## 결론

C3 **수신 대역폭 통제 본체 완결** — Phase C(수동 SUBSCRIBE_LAYER) + D-1(adaptiveStream 5교정). mock 7종 ALL PASS(기존 6 + 신규 _c3d_check). cross-sfu 투명(room_id 동봉). **★ 데모 video-grid.js IntersectionObserver 제거는 보류** — 데모가 아직 `core/` 의존(sdk/ 미배선)이라 제거 시 데모 adaptiveStream 유실(발견_사항). **커밋 안 함**(검토 후 GO).

변경: home 4파일 수정 +65/−6, 신규 2(media/adaptive-stream.js, _c3d_check.mjs).

---

## 구현

| Phase | 항목 | 파일 | 한 일 |
|---|---|---|---|
| C | SUBSCRIBE_LAYER 송신 경로 | `engine.js`+`room.js`+`remote-stream.js` | Room 에 `sig` 주입(engine assembleRoom). addParticipant 가 `ep.sig`/`ep.roomId` 주입. RemoteStream → `ep.sig.subscribeLayer(roomId, [{user_id, rid}])` (실 wire `{room_id, targets:[{user_id,rid}]}` 확인). **room_id 동봉=hub 라우팅(§0.5)** |
| C | setEnabled/setQuality/setDimensions | `remote-stream.js` | #4 setEnabled(false→`pause`) / #6 setQuality(`h`/`l`) / setDimensions(width<320→`l`). rid 어휘 = 서버 `Layer::from_rid`(h/l/pause) |
| C | effective rid + 중복 차단 | `remote-stream.js` | `_effectiveRid` = !enabled→pause / 후보(manual·adaptive) **최소(낮은 화질 우선)** / 없으면 h. `_lastSentRid` 중복 송신 차단 |
| D-1 | adaptiveStream ElementInfo | `media/adaptive-stream.js`(신) | livekit 5.2 이식 + **결함 5교정**: ①탭 backgroundPause(document.hidden) ②IO root=뷰포트 ③ResizeObserver 크기 ④hidden 100ms 지연/visible 즉시 ⑥attach 직후 강제 1회 |
| D-1 | attach 연동 | `remote-stream.js` | `attach(el)` → mount + ElementInfo observe(video full 한정, PTT half/비브라우저 skip) → onChange rid → `_applyLayer`(min). detach → stop |

---

## ★ 발견_사항 — 데모 IntersectionObserver 제거 보류

- 작업지침 Phase D-1 = "데모 `video-grid.js` IntersectionObserver 제거". 그러나 실측: **데모 6 시나리오 전부 `core/index.js` 의 Engine 사용**(`demo/scenarios/*/app.js` import). 신 `sdk/` 미배선.
- 데모 video-grid 의 `_ensureThumbObserver`(IntersectionObserver)+`_redistributeTiles`(`sdk.subscribeLayer`, rid h/l/pause)는 **core/ 엔진** 위에서 돈다. 지금 제거하면 **core/ 데모가 adaptiveStream 유실**(sdk/ RemoteStream.attach 대체가 데모에 안 붙음).
- → **SDK adaptiveStream(sdk/)은 구현 완료**(데모가 sdk/ 로 전환되면 attach 만으로 작동). **데모 IO 제거는 데모→sdk/ 전환(0605c) 후**로 보류. (0606b done 의 "demo/ 는 여전히 core/ import" 정합.)

---

## cross-sfu / 불변 (준수)

- SUBSCRIBE_LAYER = `ep.sig.subscribeLayer(roomId, ...)` **room_id 항상 동봉** → hub 가 sfu 라우팅(§0.5). 클라 sfu 직접 지정 0.
- adaptiveStream = **DOM 관측(element 사실) 직접 판단** — 텔레메트리 경유 0(불변원칙).
- PTT half(freeze)·audio = adaptiveStream 비대상(video full 한정). RemotePipe/`_onTrackReceived` 본문 0 변경.
- 비브라우저(IntersectionObserver/ResizeObserver 부재) = adaptive skip(node mock 안전).

---

## 검증

- `node --check` 5파일 PASS.
- **mock 7종 ALL PASS**: 기존 6(회귀 0) + **신규 `_c3d_check`**.
- `_c3_check` Phase C 추가: setQuality(LOW)→SUBSCRIBE_LAYER{room_id,user_id,rid:l} / setEnabled(false)→pause / 중복 effective→송신 차단 / setEnabled(true)→manual(l) 복원.
- `_c3d_check`(adaptiveStream, observer mock 구동): ⑥초기강제 / ③작은 element→l / **④hidden 즉시 pause 아님(100ms 지연)** / ②④뷰포트밖 100ms→pause / ④visible 즉시 복귀 / **①탭 backgroundPause→pause(데모 누락분)** / 탭 복귀→즉시.

---

## 미착수 (후순위)

- **D-2** PiP(⑤) + pixelDensity(③ 정밀) — ★5.
- **E** setSubscribed(#3, SDP 변경 → _renegotiateSubscribe 합집합) / 구독 권한(#11) — 자리만.
- **데모 IO 제거** — 데모 sdk/ 전환 후(위 발견_사항).

---

## ★ 종결

- **[결재]** home 4파일+신규2 diff 검토 후 GO → 한 커밋(+ context done). _c3_check/_c3d_check 포함 권장.
- **[질문]** 데모 IO 제거 = **데모 sdk/ 전환(별 작업) 후**로 보류했습니다. 지금 데모를 sdk/ 로 전환할지(별 토픽), core/ 유지로 둘지 — 판단 주시면 그때 IO 제거 동반.
- **[보고]** C3 본체(대역폭 통제) 종결. 남은 C3 = D-2/E 후순위. 다음 후보 = C5(데이터/제어) 또는 C1 §7 서버작업.

---

*author: kodeholic (powered by Claude)*
