# 세션 컨텍스트: Moderated Floor — role 체계 + 영상무전 레이아웃

> 2026-04-10 | Phase 47 (continued) | author: kodeholic (powered by Claude)

---

## 작업 요약

Moderated Floor Control에 **role: u8 숫자 기반 역할 체계** + **영상무전(audio+video half)** 기능 추가 시도.
sfud role 저장/릴레이 완료, 클라이언트 프리셋/참가자 파싱 완료.
영상 레이아웃 및 duplex 버그 수정 과정에서 **코드 혼란** 발생 — 정리 필요.

## 완료된 변경 (확정)

### sfud (빌드 성공 확인)
1. **participant.rs** — `role: u8` 필드 + `new()` 파라미터 추가
2. **message.rs** — `RoomJoinRequest.role` (기본 255, `default_role()`) + `RoomEventPayload.role: Option<u8>`
3. **room.rs** — `member_infos()` 추가 (`Vec<{user_id, role}>`)
4. **room_ops.rs** — ROOM_JOIN(role 전달 + `member_infos()` + event role), ROOM_SYNC(`member_infos()`), ROOM_LEAVE(`role: None`)
5. **admin.rs** — 스냅샷에 role 포함

### 클라이언트 (확정)
1. **client.js** — `_role` 프로퍼티, `ROOM_JOIN`에 `role: this._role ?? 255` 전송
2. **presets.js** — `moderator(role:1)`, `audience(role:10)` 프리셋 추가, `resolvePreset()`에 `role` 포함
3. **video-grid.js** — `renderGrid` 호환성 (`string | {user_id, role}`)

### power-fsm.js (확정)
- `hotStandbyMs: 10_000 → 1_000` (1초로 변경)

### moderate.js — `_onAuthorized` duplex 순서 수정 (확정)
- duplex 설정을 트랙 생성 전에 모두 선행

## 불안정한 변경 (정리 필요)

### moderate/app.js — 다수 변경이 엉켜있음
- participants 객체 파싱 (`typeof p === "string" ? p : p.user_id`) ✅
- role 기반 참가자 목록 (진행자 배지 + Grant 필터링) ✅
- `s._role = preset.role` 설정 ✅
- grant를 `["audio", "video"]`로 변경 ✅
- **영상 관련 — 혼란 상태:**
  - `media:track` → 바로 표시 vs `floor:taken` 게이팅 → 여러 번 왔다갔다
  - `floor:taken` / `floor:idle` vs `_floor:taken_raw` / `_floor:idle_raw` → 변경 반복
  - 진행자 PttController 없어서 `floor:taken` 이벤트 안 옴 (발견)
  - 청중 PTT/대기 화면 복원 로직 추가
  - Power State 토스트 추가
  - unauthorized/returnToRoleSelect 영상 정리 추가
- **현재 상태:** 엉킨 코드. 다음 세션에서 깔끔하게 재작성 필요

### moderate/index.html
- 진행자 뷰: `mod-video-area` (발언자 영상 + 이름 배지) 추가
- 청중 뷰: `aud-remote-video` (원격 영상) + `aud-local-preview` (로컬 PIP) 추가

## 발견된 버그 (근본 원인 확인, 수정 완료)

### `_onAuthorized` duplex 순서 버그
- **증상:** revoke → re-grant 시 video가 `duplex=full`로 서버에 등록
- **원인:** `_onAuthorized`에서 audio 먼저 생성 → `publishAudioTrack()._sendPublishIntent()`가 전체 트랙 re-publish → 이 시점 `_videoDuplex`는 아직 `"full"` (`_onUnauthorized`의 리셋값)
- **수정:** duplex 설정을 트랙 생성 전에 모두 선행 (moderate.js에 적용 완료)

## 발견된 설계 이슈

### 진행자 PttController 부재
- 진행자(moderator 프리셋)는 PttController를 생성하지 않음
- `floor:taken`/`floor:idle` 이벤트는 FloorFsm(PttController 내부)이 raw→가공 변환
- 진행자가 floor 이벤트를 받으려면: (a) `_floor:taken_raw` 직접 수신, (b) signaling.js에서 변환 추가
- **PttPanel 패턴 참조 필수:** `track.onunmute` + `_waitForNewFrame` (freeze masking)

### `_sendPublishIntent()`가 전체 트랙을 re-publish
- `publishAudioTrack()`이 내부에서 `_sendPublishIntent()` 호출
- `_sendPublishIntent()`는 audio+video+screen 모든 트랙의 intent를 전송
- 따라서 개별 트랙 생성 전에 모든 duplex 값이 설정되어 있어야 함

## 오늘의 기각 후보
| 기각 | 이유 |
|---|---|
| `_trackDuplex` 맵 (per-source duplex 저장) | 근본 원인이 실행 순서 버그였음. 상상력 코딩 |
| Hub WsConn에 role 저장 | init 액션 유지하면 불필요 |
| `floor:taken` → 영상 표시 게이팅 (단독) | 진행자에게 PttController 없어서 이벤트 안 옴 |

## 오늘의 지침 후보
- **duplex 설정 선행 원칙** — `_sendPublishIntent()`가 전체 트랙을 re-publish하므로, 모든 duplex 값을 트랙 생성 전에 설정해야 함
- **진행자 floor 이벤트** — PttController 없으면 `floor:taken` 안 옴. `_floor:taken_raw` 사용 필요
- **영상 표시 = PttPanel 패턴** — `track.onunmute` + `_waitForNewFrame`이 정석. `floor:taken`만으로는 freeze frame 문제

## 다음 세션 우선순위
1. **moderate/app.js 영상 레이아웃 재작성** — 현재 엉킨 코드 정리
   - 진행자: `_floor:taken_raw`로 발언자 이름, `media:track`에서 stream 저장, `track.onunmute`로 표시
   - 청중: PttPanel 패턴 (granted 시 PttController 있으므로 `floor:taken` 사용 가능)
   - idle 시 video 숨김 처리
2. **audio 트랙 소실 원인 추적** — revoke→re-grant→COLD 경유 시 audio 재등록 실패
3. **E2E 검증** — grant(audio+video) → PTT → 영상 표시 → idle → 영상 숨김 → revoke → 정리
4. **SKILL_OXLENS.md 업데이트** — role 체계, audience 프리셋, duplex 선행 원칙

---

## 변경 파일 목록

### sfud (확정, 빌드 성공)
- `crates/oxsfud/src/room/participant.rs` — role: u8 필드
- `crates/oxsfud/src/signaling/message.rs` — RoomJoinRequest.role, RoomEventPayload.role
- `crates/oxsfud/src/room/room.rs` — member_infos()
- `crates/oxsfud/src/signaling/handler/room_ops.rs` — role 전달/포함
- `crates/oxsfud/src/signaling/handler/admin.rs` — 스냅샷 role

### 클라이언트 (확정 + 혼란)
- `core/client.js` — _role, ROOM_JOIN role 전송 ✅
- `core/moderate.js` — _onAuthorized duplex 순서 수정 ✅
- `core/media-session.js` — _trackDuplex 추가 후 되돌림 (원상복구) ✅
- `core/ptt/power-fsm.js` — hotStandbyMs 1초 ✅
- `demo/presets.js` — moderator(role:1), audience(role:10) ✅
- `demo/components/video-grid.js` — renderGrid 호환성 ✅
- `demo/scenarios/moderate/app.js` — 다수 변경 (혼란, 정리 필요) ⚠️
- `demo/scenarios/moderate/index.html` — 영상 요소 추가 ✅

---

*v1.0 — 2026-04-10*
