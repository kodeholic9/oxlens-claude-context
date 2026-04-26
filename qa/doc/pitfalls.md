# pitfalls.md — 수치 해석 함정

> **카테고리**: 함정
> **마지막 갱신**: 2026-04-26
> **관련 checks**: 99_invariants.md
> **출처**: 4/25 까지 누적 시험 + 22.5% 오진 사례 (`localhost_loss_lesson.md`)

---

## 핵심

`getStats` / `admin.sfu()` 의 숫자는 **그대로 해석하면 안 된다**. 같은 숫자라도 시나리오에 따라 의미가 정반대일 수 있고, 일부 메트릭은 "정상 패턴" 화이트리스트에 들어간다.

## 함정 7개

### 1. `packetsLost > 0` = 물리 유실?

**오진**: localhost 에서 inbound-rtp.packetsLost = 22.5% → "네트워크 손실 22%"
**진실**: localhost 의 packetsLost 는 **seq 갭 해석**. 원인은 논리(SimulcastRewriter / ptt rewrite / publisher self-skip / switch transition).
→ 항상 admin sfu_metrics `relay.egress_drop` / `srtp.decrypt_fail` 로 교차. 둘 다 0 이면 SDK 내 갭 해석 문제.

### 2. `audio_concealment` 발생 = 오디오 끊김?

**진실**: PTT 전환 시 `audio_concealment` 는 **정상 패턴**. NetEQ 가 RTX storm 방어로 plc 적용. 화이트리스트에 들어감.
→ "정상 패턴 라벨" 이라도 사용자 체감 저하면 개선 대상 (UX vs 메트릭).

### 3. `video_freeze count > 0` = 비디오 끊김?

**진실**: PTT half-duplex 전환 시 `video_freeze` 는 **정상 패턴** (idle → talking 전환 시 첫 키프레임까지 freeze). 매트릭스 화이트리스트.
→ Conference (full-duplex) 에서 freeze count 증가 시는 fail.

### 4. `fps == 0` = 인코더 정지?

**진실**: PTT idle 상태에서 fps = 0 은 정상. half-duplex 가 발화 안 하면 RTP 미전송.
→ 발화 중(`floor:state=='talking'`) fps == 0 시만 fail.

### 5. `sr_relay == 0` = SR 미전달?

**진실**: PTT 모드는 SR 자체생성 금지 + relay 중단 (NTP↔RTP drift 방지). sr_relay = 0 은 정상.
→ Conference 모드에서만 sr_relay > 0 검증.

### 6. `_pttPipes` 가 2개 초과?

**진실**: PTT virtual pipe 는 user × sub PC pair 단위 1쌍 (kind 별 1, 총 2). 초과 시 cross-room SDP duplicate 회귀 (i 세션 별건).
→ INV-09 위반 시 즉시 fail.

### 7. `_pendingTracks` 가 비지 않음?

**진실**: ROOM_JOIN 이전 ontrack 도착 시 임시 큐에 들어가야 함. `_onJoinOk` 후 drain. 길게 남아있으면 hydrate 누락.
→ scenarios 종료 시 0 이어야 함.

### 8. `scope.panRequest` MUTEX 가 시그니처로 차단되는가?

**오진**: `engine.scope.panRequest({priority, dests?, pubSetId?})` 객체 시그니처를 보고 "한 인자만 채우면 MUTEX 자동 만족" 으로 가정.
**진실**: 객체 시그니처라 **dests 와 pubSetId 동시 주입이 형식적으로 가능**. MUTEX 는 **클라이언트 인자 가드 (`pan:denied` cause=4032 + return null) 로만 강제** — throw 가 아닌 emit/null 리턴 패턴, 시그니처적 차단 아님. 외부 API 자체가 실수를 부르는 패턴.
→ 시험 logic 작성 시 `engine.floorRequest({roomId})` 의 단일 인자 패턴이 시그니처 자체로 단일성을 보장하는 것과 혼동 금지. 향후 positional 분리 권장 (`panRequest(rooms, priority)` ad-hoc / `panRequestScope(priority)` 자기 pub_set_id 자동) — **현재 미진행, 기록만** (Phase 61 PAN-06 재판정 결과, 2026-04-26).

## 체크리스트 (시험 짤 때)

- [ ] 시험할 메트릭이 "정상 패턴 화이트리스트" 에 있는가? (audio_concealment, video_freeze during transitions, fps=0 idle, sr_relay=0 PTT)
- [ ] localhost 에서 측정하는가? (물리 유실 가정 금지)
- [ ] admin 카운터로 교차 가능한가? (relay.egress_drop, srtp.decrypt_fail)
- [ ] 시나리오 종료 시 INV-* 모두 통과하는가?

---

> ⚠️ "정상 패턴 라벨" ≠ UX 면죄부. 화이트리스트 항목이라도 사용자 체감 저하면 개선 대상.
