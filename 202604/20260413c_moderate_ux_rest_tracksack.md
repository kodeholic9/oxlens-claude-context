# 20260413c — Moderate UX 완성 + REST authorized API + TRACKS_ACK 단순화

## 요약

Moderate 시나리오 UX 다수 수정: pub 통일(transceiver 퇴역), 내 카메라 영상무전 패턴 적용, 발언자격 REST 동기화 API 추가, TRACKS_ACK SSRC 데이터 제거(클라이언트 완료/서버 미완).

---

## 완료 항목

### 1. `_onUnauthorized` pub 통일 (moderate.js)
- full/half duplex 분기 제거 → 둘 다 transceiver 퇴역(direction='inactive' + removePipe)
- re-grant 시 새 transceiver → 새 SSRC 보장
- half-duplex 차이는 서버가 처리(track_ops.rs broadcast 생략, 이전 세션 완료)

### 2. 내 카메라 영상무전 패턴 (moderate/app.js)
- `_localCamEl` 고정 element — moderate:authorized에서 한 번 생성, srcObject on/off
- 이전: floor:taken마다 `document.createElement("video")` → 2차 PTT에서 미표시
- 수정: 영상무전과 동일 패턴(고정 element + srcObject 재할당)

### 3. floor:state로 내 카메라 제어 (moderate/app.js)
- **핵심**: 내 카메라(송신)는 `floor:state`, 타인 영상(수신)은 `floor:taken`
- floor:state handler 추가: talking → srcObject 설정 + 아바타 숨김, 그 외 → srcObject 해제 + 아바타 표시
- floor:taken에서 `d.speaker === s.userId` 분기 제거 → 타인 발화자만 처리
- floor:idle/revoke에서 `aud-slide-me` 제외 (floor:state가 전담)
- **2차 PTT 내 카메라 미표시 미해결 이슈 → 자연 해결됨**

### 4. REST authorized API (서버 + 클라이언트)
- `GET /media/rooms/:room_id/moderate/authorized` — hub-only, gRPC 불필요
- hub `ModerateSession.speakers_list()` 직접 반환: `{ authorized: [{ user_id, kinds, duplex }] }`
- 서버: `rest/rooms.rs`에 `get_authorized` 핸들러 + Path import 추가
- 클라이언트: `fetchAuthorized()` 헬퍼 + room:joined 후 REST fetch → authorizedUsers 초기화 + 슬라이드 생성
- **Axum 0.7 경로 문법**: `/{param}` → `/:param` (404 원인)

### 5. TRACKS_ACK SSRC 데이터 제거 (클라이언트 완료)
- `sdp-negotiator.js`: `sendTracksAck(recvPipes)` → `sendTracksAck()` (room_id만 전송)
- `engine.js`: 2곳 호출부 recvPipes 인자 제거
- 근거: RESYNC 영구 제거 후 synced/mismatch 두 경로가 동일 동작(gate.resume_all + PLI + stalled snapshot)
- 효과: premature SSRC race 조건 소멸, 1000명 방 SSRC 배열 직렬화 제거

### 6. ACTIVE_SPEAKERS 콘솔 로그 제거 (signaling.js)

---

## 미완료: TRACKS_ACK 서버 단순화

### 현황
- 클라이언트: SSRC 안 보냄 (완료)
- 서버: `do_tracks_ack` 190줄 → 아직 SSRC 비교 로직 잔존 (ssrcs 필드가 빈 배열로 오면 mismatch 경로)

### 다음 세션 작업
- `TracksAckRequest` 구조체 위치 확인 → `ssrcs` 필드 `Option` 또는 제거
- `do_tracks_ack` 단순화 (~40줄):
  - expected 집합 구축 제거
  - SSRC 비교 + mismatch 경로 제거
  - `ack_mismatch` 메트릭/agg-log 제거
  - 남기는 것: gate.resume_all() + PLI burst + record_stalled_snapshot() + { synced: true }

---

## 수정 파일 목록

| 파일 | 변경 | 상태 |
|------|------|------|
| `core/moderate.js` | _onUnauthorized duplex 분기 제거, full/half 통일 | ✅ |
| `core/signaling.js` | ACTIVE_SPEAKERS console.log 제거 | ✅ |
| `core/sdp-negotiator.js` | sendTracksAck() SSRC 제거, room_id만 전송 | ✅ |
| `core/engine.js` | sendTracksAck(recvPipes) → sendTracksAck() 2곳 | ✅ |
| `demo/scenarios/moderate/app.js` | _localCamEl 패턴 + floor:state 제어 + fetchAuthorized REST | ✅ |
| `crates/oxhubd/src/rest/rooms.rs` | GET /:room_id/moderate/authorized + Path import | ✅ |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | do_tracks_ack 단순화 | ❌ 다음 세션 |

---

## 교훈

- **영상무전 패턴 = 정답**: 내 카메라는 floor:state(talking/else)로 제어. floor:taken은 서버 broadcast라 타인용. 송신/수신 제어점 분리가 핵심
- **고정 element + srcObject on/off**: 매번 createElement하면 2차 사용에서 깨짐. 한 번 생성 + srcObject 재할당이 안정적
- **Axum 0.7 경로 문법**: `/{param}`은 0.8 문법. 0.7은 `/:param`. 빌드는 성공하지만 런타임 404
- **TRACKS_ACK SSRC는 레거시**: RESYNC 제거 후 두 경로(synced/mismatch)가 동일 동작 → SSRC 비교 자체가 불필요

---

## 기각된 접근법

- **display:none으로 아바타 숨김** — Tailwind hidden + flex 충돌 가능성 검토했으나 실제로는 hidden이 정상 동작. 문제는 showSlideAvatar 호출 타이밍이었음
- **floor:taken에서 내 카메라 제어** — 서버 broadcast(네트워크 왕복) 의존. floor:state(로컬 상태 전이)가 더 빠르고 정확
- **role 기반 발언자격 판별** — role은 진행자/청중 구분만. 발언자격(authorized)은 별도 상태. REST API로 동기화가 정답

---

*author: kodeholic (powered by Claude)*
