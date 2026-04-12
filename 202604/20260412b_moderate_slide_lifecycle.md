# 세션 컨텍스트: Moderate 슬라이드 생명주기 + Full Duplex Video 버그

> 날짜: 2026-04-12
> 영역: oxlens-home (core SDK + demo/moderate)
> 서버 변경: 없음

---

## 완료 사항

### 1. Moderate 슬라이드 생명주기 재설계 (app.js)

**설계 원칙 확정:**
- 슬라이드 생명주기 = authorized/unauthorized (트랙 기반 아님)
- authorized 시 아바타 슬라이드 즉시 생성 (floor 상태 무관)
- unauthorized 또는 leave 시만 슬라이드 제거
- half duplex: 발언 중 → 비디오+glow, 미발언 → 아바타
- full duplex: grant 즉시 비디오 표시

**구현 (moderate/app.js):**
- 상태 추가: `authorizedUsers` Map, `pttVideoPipe`, `currentGlowSlideId`
- 헬퍼 함수 4개: `addAuthorizedSlide`, `setSlideGlow`, `clearAllGlow`, `showSlideAvatar`
- `moderate:authorized` → 본인 슬라이드 생성 (아바타)
- `moderate:speakers` → diff 기반 타인 슬라이드 생성/제거
- `media:track` isPtt → PTT 슬라이드 생성 안 함, pipe 저장만
- `media:track` regular → authorized 슬라이드에 mount + duplex별 아바타 분기
- `tracks:update(remove)` → authorized 슬라이드 보호 (비디오만 숨김)
- `_floor:taken_raw` → PTT video를 speaker 슬라이드에 mount + glow
- `_floor:idle_raw` / `revoke` → glow 해제 + 아바타 복원
- cleanup → 새 상태 초기화

### 2. Full Duplex Video Gating 버그 수정 (endpoint.js)

**문제:** 첫 authorized(half) → unauthorized → 재 authorized(full) 시 서버가 video를 여전히 half로 알고 gate 처리
**원인:** `_publishCamera` resume 분기에서 `publishTracks`를 안 보냄 → 서버 duplex 미갱신
**증거:** 스냅샷 `gated=289`, `TRACKS:U532 video duplex=half`
**수정:** resume 분기에서 항상 `publishTracks` 재전송

### 3. Unauthorized 시 서버 트랙 완전 제거 (moderate.js)

**문제:** unauthorized에서 video를 mute 패턴(replaceTrack null)으로 처리 → 서버 트랙 잔존 → 재부여 시 subscriber에 ontrack 미발생
**수정:** `_onUnauthorized`에서 `removeVideoTrack` 후 `unpublishTracks` 추가 호출 → 서버에서 트랙 완전 제거 → subscriber m-line inactive

---

## 미해결 사항 (★다음 세션)

### 1. 두 번째 full authorize 시 video freeze
- 미디어는 정상 흐름 (recv_delta=249, fps=24, gated=0)
- **subscribe m-line 누적 문제**: authorize/unauthorize 반복 시 m-line이 계속 추가됨 (mid=2, mid=3, mid=4...)
- `track:ack_mismatch` 반복 (stale PTT SSRC 잔존: extra=[4191871751, 1293099912])
- 새 video가 새 mid에 ontrack → 앱이 기존 slide에 mount 안 됨 또는 이전 element가 남아 freeze
- **근본 원인**: 클라이언트가 mid를 자체 할당하는 구조 (assignMids) — 업계 정석은 서버가 mid 할당
- **설계 문서**: `context/design/20260412_subscribe_mid_design.md`
- mediasoup/LiveKit 조사 완료: 양 메이저 SFU 모두 서버가 subscribe mid 관리
- **해결 방향**: collect_subscribe_tracks에서 mid 필드 추가, Participant별 MidPool 관리, 클라이언트 assignMids는 passthrough로 단순화

### 2. `_floor:*_raw` SDK 경계 위반
- 진행자/미인증 청중은 FloorFsm 없음 → 공개 이벤트(`floor:taken/idle`) 안 옴
- 현재 `_floor:*_raw` 직접 구독으로 우회
- **해결 방향**: Engine이 FloorFsm 유무와 관계없이 `floor:taken/idle/revoke` 공개 emit (signaling에서 수신 시 passthrough)

### 3. Moderate 앱 슬라이드 로직 미검증
- 슬라이드 생명주기 코드 작성 완료, E2E 미검증 (video freeze 문제와 엮여 있음)
- video freeze 해결 후 통합 검증 필요

### 이전 이월
- MUTE_UPDATE track_id 기반 전환 (서버 수정 필요)
- support 시나리오 v2 전환

---

## 오늘의 지침 후보

- **슬라이드 생명주기 = authorized/unauthorized** — tracks:update로 authorized 슬라이드를 건드리면 안 됨
- **mute 패턴 ≠ 자격 회수** — 카메라 토글은 mute(replaceTrack null), 자격 회수는 unpublishTracks로 서버 트랙 제거
- **_publishCamera resume은 항상 publishTracks 재전송** — 서버 duplex 동기화 + 트랙 재등록 보장
- **FloorFsm 없는 참가자도 floor 이벤트 필요** — Engine passthrough 방식으로 해결 예정

---

## 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| pipe 삭제로 first-time path 강제 | pubPc에 orphan transceiver 남음 — m-line 누적 악화 |
| duplex 변경 시에만 publishTracks | 같은 duplex(full→full) 재부여 시 서버 트랙 재등록 안 됨 |
| tracks:update(remove)로 authorized 슬라이드 제거 | 자격 보유 중 floor idle에서도 슬라이드 사라짐 |
| ModerateController에서 pipe.mount() 직접 호출 | SDK 경계 침범 |

---

## 수정 파일 목록

### Core SDK
- `core/endpoint.js` — _publishCamera resume: 항상 publishTracks 전송 (duplex 조건 제거)
- `core/moderate.js` — _onUnauthorized: unpublishTracks 추가 (서버 트랙 완전 제거)

### Demo
- `demo/scenarios/moderate/app.js` — 슬라이드 생명주기 전면 재설계 (authorized/speakers diff 기반)

---

*author: kodeholic (powered by Claude)*
