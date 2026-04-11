# Core SDK v2 — 아키텍처 리팩터 (처음부터 다시 만들기)

> 2026-04-11 | 부장님 × 김대리 설계+구현 세션
> author: kodeholic (powered by Claude)

---

## 1. 세션 요약

core/ SDK를 처음부터 다시 만드는 작업. 설계 → 검토 2회 → 구현 Step 1~7 완료.

### 설계 (rev.3 확정)

**Engine → Room → Endpoint → Pipe** 4계층 구조. PC를 Engine이 소유 (서버 단위 물리 연결).
PttController 제거 → FloorFsm은 Room 소유, PowerFsm은 PowerManager로 Engine 이관.
media-session.js 700줄 God Object 해체 → SdpNegotiator + Pipe + Room으로 분리.
공개 API 100% 하위호환. 앱(demo/) 코드 변경 제로.

설계 문서: `context/design/20260411_core_v2_architecture.md`

### 업계 조사

| | LiveKit | mediasoup-client | OxLens v2 |
|---|---------|------------------|-----------|
| 최상위 | Room | Device | Engine |
| PC 위치 | Room.engine.pcManager | Device.transport | Engine.pubPc/subPc |
| 참가자 | Participant | 없음 | Endpoint |
| 트랙 | TrackPublication→Track | Producer/Consumer | Pipe |
| cross-room | 없음 | pipeToRouter(서버) | Phase 2 (클라이언트 제어) |

### 구현 완료 (Step 1~7)

| Step | 파일 | 크기 | 내용 |
|------|------|------|------|
| 1 | pipe.js | 2KB | 순수 데이터 모델, 트랙 속성 SSOT |
| 1 | endpoint.js | 3KB | Pipe 컬렉션, 조회 API |
| 1 | room.js | 5KB | Endpoint 컨테이너, Floor 슬롯, Pipe mid 매칭 |
| 2 | sdp-negotiator.js | 30KB | media-session에서 PC/SDP/파싱/intent 추출 |
| 3 | power-manager.js | 20KB | PowerFsm 이관, sender→Pipe 경유 |
| 4 | engine.js | 53KB | 전체 재작성, Room/Pipe 위임 |
| 6 | moderate.js | - | PttController→room.floor+engine.power |
| 7 | engine.js (media getter) | - | Telemetry/Device 호환 프록시 |

---

## 2. 핵심 설계 판단

### PC 소유: Engine
- PC = "나 ↔ 서버" 물리 연결, Room(논리) 단위가 아닌 서버 단위
- cross-room 시 same sfud → sub PC 공유 (설계 문서 §2)
- LiveKit은 Room.engine으로 숨기지만 실질은 동일

### PttController 제거
- "PTT 모드" 개념 삭제 → `if (pipe.duplex === 'half')` 자연 분기
- FloorFsm → Room.floor (방 단위 자원)
- PowerFsm → PowerManager(Engine) (타이머/async/getUserMedia 로직 보존)
- PowerFsm을 Pipe.transitionPower() 한 줄로 대체하려 했으나, 검토에서 기각 (300줄 async 로직은 Pipe에 넣으면 God Object)

### SdpNegotiator 분리
- Pipe → subscribeTracks 형식 변환은 SdpNegotiator._pipesToSubscribeTracks() 담당
- Pipe가 sdp-builder 내부 형식을 모름 (계층 결합 방지)
- nego가 localPipes를 받아 pipe.transceiver/sender 직접 설정
- ontrack은 SdpNegotiator가 아닌 Engine이 등록 → Room.matchPipeByMid() 경유

### media 호환 프록시
- Telemetry(500줄), DeviceManager, HealthMonitor가 sdk.media.* 접근
- Engine에 `get media()` 프록시 추가 → Pipe 경유로 매핑
- 이 모듈들을 전부 다시 쓰는 것보다 안전, 향후 v2 인터페이스 전환 시 제거

---

## 3. 검토에서 수정된 항목

| 원안 | 수정 | 이유 |
|------|------|------|
| PowerFsm 삭제→Pipe.transitionPower() | PowerManager로 Engine 이관 | 타이머/async/getUserMedia → Pipe가 God Object |
| Pipe.toSubscribeTrack() | 삭제, Nego가 변환 | Pipe가 sdp-builder 형식 의존 |
| rooms Map Phase 1 선언 | _currentRoom만 | YAGNI |
| FilterManager 추출 필수 | optional | 80줄, sender 직접 접근 필요 |
| Floor room_id 필터링 누락 | Room.onFloorEvent() 추가 | multi-room 대비 |
| moderate 연동 경로 누락 | §6 보완 | PttController→room.floor+engine.power |
| PowerManager multi-room | Phase 2 주석 | per-room 검토 필요 |
| FloorFsm engine 참조 | TODO 주석 | 재활용 우선, callbacks 주입 향후 |

---

## 4. 삭제 대상 (수동 작업)

- `core/media-session.js` → SdpNegotiator + Engine으로 해체 완료
- `core/ptt/ptt-controller.js` → Room.floor + Engine.power로 대체
- `core/ptt/power-fsm.js` → power-manager.js로 이관
- `core/client.js` (re-export shim) → engine.js 직접 export

---

## 5. 미완료 / 다음 세션

- **Step 8: E2E 검증** — conference, voice_radio, video_radio, dispatch, support 5종 시나리오
- demo/ 파일이 새 engine.js를 import하도록 확인
- 삭제 대상 파일 실제 삭제
- Signaling에서 `sdk.ptt?.wake()` 등 v1 잔재 확인 (media 프록시가 커버하지 않는 것)
- Telemetry v2 인터페이스 전환 (media 프록시 제거) — optional, 안정화 후

---

## 6. 기각 후보 (이 세션)

| 기각 | 이유 |
|------|------|
| Room이 PC 소유 | cross-room PC 공유 불가 |
| Endpoint가 PC 소유 | remote EP에 PC 없음 |
| PowerFsm → Pipe.transitionPower() | async/타이머 로직이 Pipe에 들어가면 God Object |
| Pipe.toSubscribeTrack() | sdp-builder 형식 의존 |
| rooms Map Phase 1 선언 | YAGNI |
| FilterManager 필수 추출 | 80줄, 추출 시 참조 역류 |
| Transport 클래스 (mediasoup식) | 2PC 고정, 추상화 과잉 |
| Telemetry 전체 재작성 | media 프록시로 무변경 동작, 안전 |

---

*author: kodeholic (powered by Claude)*
