# 세션 컨텍스트: Moderated Floor Control v2 구현

> 2026-04-10 | Phase 47 | author: kodeholic (powered by Claude)

---

## 작업 요약

Moderated Floor Control 설계 v1 → v2 전면 재설계 + 구현.
**Hub = 발언 자격 관리, sfud = 기존 PTT 그대로, sfud 연동 제로.**

### v1 → v2 전환 경위
1. v1 설계(20260409) 기반 구현 완료 + 빌드 성공
2. 부장님 피드백: "청중이 무전세션 갖고 시작?" → audio=off 입장, grant 시 트랙 생성으로 전환
3. "grant = 즉시 발언?" → 2단계(Authorized→speak_start) 검토
4. "타이머 동기화 문제" → 타이머 자체 제거, sfud max_burst_ms만
5. "audio=full publish면 줌과 다를 바 없다" → audio=half로 복귀, 서버 레벨 gating이 차별점
6. "역할 지정 + 웨비나 줄서기 둘 다 대응" → authorized_speakers + hand_queue 구조 확정
7. **최종 모델: grant = 발언 자격 부여 → SDK 자동 audio=half 생성 → PTT로 발언**

## 변경 파일

### v1에서 추가된 파일 (유지)
- `common/signaling/opcode.rs` — MODERATE=70, MODERATE_EVENT=170
- `common/signaling/mod.rs` — priority, intent 매핑
- `oxsfud/signaling/message.rs` — FloorRequestMsg.duration_sec
- `oxsfud/room/floor.rs` — per-speaker max_burst_ms, request() 시그니처
- `oxsfud/signaling/handler/floor_ops.rs` — duration_sec 전달
- `oxsfud/transport/udp/ingress_mbcp.rs` — None 전달
- `oxhubd/lib.rs` — pub mod moderate
- `oxhubd/state.rs` — moderate 필드

### v2에서 재작성 (3파일)
- `oxhubd/moderate/session.rs` — speaker/SpeakingInfo/duration 전부 제거, authorized_speakers: HashMap<String, Vec<String>> (user→kinds), Phase 3단계(Announcement/Collecting/Open)
- `oxhubd/moderate/handler.rs` — sfud 연동 제거(async→sync), grant에 kinds 매개변수 추가, parse_kinds 헬퍼, 액션 6개
- `oxhubd/ws/mod.rs` — sfu 파라미터+await 제거

### 클라이언트 (oxlens-home, 4파일 수정 + 1파일 신규)
- `core/constants.js` — MODERATE=70, MODERATE_EVENT=170 추가
- **신규** `core/moderate.js` — ModerateController (authorized→자동 트랙 생성, unauthorized→전체 트랙 제거, kinds 지원)
- `core/signaling.js` — op=170 디스패치 → moderate.onModerateEvent()
- `core/client.js` — ModerateController import+생성, disconnect/leaveRoom에 detach
- `core/media-session.js` — publishAudioTrack()/removeAudioTrack() 신규 (addCameraTrack 패턴 동일)

### v2에서 제거
- `oxhubd/events/mod.rs` — sfud tap 훅 제거 (선택적, 고도화 범위)

## 핵심 설계 결정

### grant에 kinds 지정
- `{action: "grant", targets: ["A","B"], kinds: ["audio","video"]}` — 영상무전
- kinds 미지정 시 기본값 `["audio"]` — 음성만
- revoke는 kinds 무관 — 해당 사용자의 모든 트랙(audio+video) 전부 제거
- authorized_speakers: HashMap<String, Vec<String>> (user→kinds 매핑)

### revoke 시 보안
- revoke → SDK unauthorized → FloorRelease + 트랙 제거 → sfud에 half-duplex 트랙 없음
- 클라이언트가 PTT 막 눌러도 트랙 자체가 없으니 gating 대상 없음
- 레이스 컨디션: unauthorized→트랙 제거 틈에 FloorRequest 도착해도 직후 트랙 제거 시 sfud on_participant_leave로 floor 자동 해제

### 줌과의 차별점
- 줌: 클라이언트 mute 신뢰 (우회 가능)
- OxLens: 서버 레벨 gating (트랙 없으면 소리 안 나감)

## 오늘의 기각 후보
| 기각 | 이유 |
|---|---|
| Hub에서 sfud FloorRequest 중계 (v1) | 이중 제어. 참가자가 직접 PTT로 sfud 통신이 단순 |
| Hub 타이머/duration | sfud max_burst_ms로 충분. 이중 타이머 불일치 위험 |
| audio=full publish/unpublish | 줌 mute/unmute와 차이 없음. half-duplex gating이 차별점 |
| Grant = 즉시 발언 시작 | 참가자 준비 시간 필요 |
| speak_start 2단계 | 타이머 기준점 동기화 문제 해결용이었으나, 타이머 제거로 불필요 |

## 오늘의 지침 후보
- **MODERATE=70은 Hub 전용, sync** — sfud 연동 없음, async 불필요
- **Grant ≠ 발언 시작** — Grant = 트랙 생성 + PTT 버튼 활성화. 발언은 PTT(op=40)
- **Revoke = 마이크 뺏기** — sfud FLOOR_REVOKE(op=143)와 레이어 다름. 143은 한 턴 끊기, revoke는 자격 자체 회수
- **authorized_speakers + hand_queue** — 역할 지정(법정) + 줄서기(웨비나) 두 패턴 모두 대응

## SDK 이벤트 (앱 UI 연동용)

| 이벤트 | 용도 | 앱 UI 예시 |
|---|---|---|
| `moderate:authorized` | 내가 발언 자격 받음 (d.kinds 포함) | 토스트 + PTT 버튼 표시 |
| `moderate:unauthorized` | 내 발언 자격 회수됨 | 토스트 + PTT 버튼 숨김 |
| `moderate:speakers` | 발언 자격자 목록 변경 (d.speakers: [{user_id, kinds}]) | 진행자 자격자 패널 |
| `moderate:queue` | 손들기 큐 변경 (d.queue) | 진행자 큐 목록 |
| `moderate:phase` | Phase 변경 (d.phase) | 배너/토스트 |

## 미구현 (고도화)
- **role: u8 숫자 기반 역할 체계** (priority 패턴, 다음 세션 최우선)
  - ROOM_JOIN에 `role: u8` 전달, Hub WsSession에 저장
  - sfud는 role 무시 (빈깡통 원칙 유지)
  - moderate 세션: `moderator_threshold: u8` — role <= threshold이면 진행자 권한
  - 앱이 숫자의 의미 정의 (1=진행자, 2=청중, 3=패널...)
  - 문자열("moderator") 금지 — 시나리오 종속 방지
  - init 액션 제거 → 첫 moderator 입장 시 세션 자동 생성
- moderator 목록 클라이언트 전달 → 참가자 목록에서 진행자 필터링
- grant 후 SDK 자동 audio=half publish → PTT 발언 E2E 검증
- sfud floor 이벤트 tap (진행자 UI "현재 발언 중" 표시)
- 방별 policy (room-level max_burst_ms)
- JWT 기반 moderator 인증

---

## SKILL_OXLENS.md 업데이트 대기 항목

### 시그널링 프로토콜 테이블 추가
- Client→Server: `| 70 | MODERATE | Moderated Floor Control (action 6종: init/hand_raise/hand_lower/grant/revoke/set_phase, Hub 전용, sync) |`
- Server→Client: `| 170 | MODERATE_EVENT | Moderated Floor 이벤트 (authorized/unauthorized/speakers_updated/queue_update/phase_changed) |`

### 서버 소스 구조 oxhubd 섹션 추가
```
        ├── moderate/
        │   ├── mod.rs       — ModerateManager (room→session 맵, 생명주기)
        │   ├── session.rs   — ModerateSession (authorized_speakers, hand_queue, Phase 3단계)
        │   └── handler.rs   — op=70 디스패치 + 브로드캐스트 (sfud 연동 없음)
```

### 완료된 핵심 기능 추가
- **Moderated Floor Control v2** (Hub+SDK 구현): op=70/170, 발언 자격 관리(authorized_speakers+hand_queue), grant(kinds)/revoke 시 SDK 자동 audio/video half 생성/제거, 실제 발언은 기존 PTT 그대로, sfud 변경 최소(duration_sec만)

### 웹 클라이언트 구조 추가
```
oxlens-home/core/
├── moderate.js     — ModerateController (authorized/unauthorized → 자동 트랙 생성/제거, kinds 지원)
```

### 구현 예정 수정
- 기존 "Moderated Floor Control (2026-04-09 설계 완료, hub 구현 대기)" → "**Moderated Floor Control 시나리오 페이지** (Hub+SDK 구현 완료, demo/scenarios/moderate/ 미구현)"

### 아키텍처 원칙 추가
- **MODERATE=70은 Hub 전용 sync** — sfud passthrough 아님, async 불필요
- **Grant ≠ 발언** — Grant = 자격(트랙 생성). 발언 = PTT(op=40). 레이어 분리
- **Revoke ≠ FLOOR_REVOKE** — Revoke = 자격 회수(트랙 제거). FLOOR_REVOKE(143) = PTT 한 턴 끊기
- **authorized_speakers + hand_queue** — 역할 지정 + 줄서기 두 패턴 통합
- **role은 u8 숫자** — priority 패턴. 문자열("moderator") 금지. 앱이 의미 정의. sfud는 role 무시

### 기각 사항 추가
- Hub에서 sfud FloorRequest 중계 — 이중 제어, 참가자 직접 PTT가 단순
- audio=full publish/unpublish — 줌 mute/unmute와 차이 없음, half-duplex gating이 차별점
- role 문자열("moderator"/"viewer") — 시나리오 종속. u8 숫자가 정답 (priority 패턴)

---

*v2.0 — 2026-04-10*
