# 20260413b — Moderate Re-grant 검은 화면 해결 (Full + Half Duplex)

## 요약

Moderate 시나리오에서 grant → revoke → re-grant 시 subscriber 영상 검은 화면 문제를 full/half duplex 모두 해결.
근본 원인: Chrome transceiver inactive→active 재사용 + 동일 SSRC = 렌더 파이프라인 미재연결.

---

## 해결 전략: duplex별 분기

| | full-duplex | half-duplex |
|---|---|---|
| 근본 원인 | 같은 SSRC + subscriber inactive 경유 | 같은 vSSRC + subscriber inactive 경유 |
| 해결 (pub) | transceiver 퇴역 → 새 SSRC | 변경 없음 (vSSRC 고정이라 의미 없음) |
| 해결 (sub) | 새 SSRC이므로 Chrome 정상 인식 | **서버: ptt-video remove broadcast 생략** → subscriber inactive 안 거침 |
| SSRC 변경 가능? | ✅ pub SSRC = sub SSRC (pass-through) | ✗ SFU가 vSSRC로 리라이팅 (고정) |

### 핵심 통찰: "unpublish가 나가기처럼 동작해야 한다"

영상무전에서 나가기 시:
- 나간 참가자의 물리 트랙 정리
- 방에 다른 half-duplex 참가자가 남아있으면 ptt-video virtual track 유지
- subscriber m-line 변화 없음

moderate unpublish도 같은 원리:
- 서버 내부 정리(participant.tracks, stream_map, intent)는 수행
- **half-duplex이면 ptt-video TRACKS_UPDATE(remove) broadcast 생략**
- floor gating이 미디어 통제 — subscriber 입장에서 "아무도 floor 안 잡고 있는 것"과 동일
- re-grant 시 assign_subscribe_mid("ptt-video") → 기존 mid 반환 (멱등)

---

## 수정 내용

### 서버 (track_ops.rs)
- `handle_publish_tracks_remove`에서 `DuplexMode::Half` 트랙은 TRACKS_UPDATE(remove) broadcast 제외
- 서버 내부 정리(participant.tracks, stream_map, intent)는 정상 수행
- agg-log는 half-duplex 포함 전체 기록 (duplex 필드 추가)
- info 로그에 broadcast/skipped_half 카운트 추가

### 클라이언트 (moderate.js)
- `_onUnauthorized` duplex별 분기:
  - full: unpublishTracks + transceiver 퇴역 (direction='inactive' + removePipe)
  - half: unpublishTracks만 (서버가 broadcast 생략, transceiver/pipe 유지, resume path)

### 클라이언트 (room.js)
- `resolveOnTrack`: `e.track.clone()` → `e.track` 원복 (clone 효과 없음 확인)

### 클라이언트 (moderate/app.js)
- moderate:authorized에서 로컬 카메라 마운트: `grantedDuplex === "full"` 조건 제거 → duplex 무관하게 video 있으면 프리뷰 표시

---

## 스냅샷 검증 (full-duplex)

AGG LOG SSRC 변화 확인:
- 1차 grant: 0x8FB1DBD4 → 2차: 0xEA7A0ACE → 3차: 0xF27EFF97 (매번 다른 SSRC)
- transceiver 퇴역 정상 작동

## 스냅샷 검증 (half-duplex)

AGG LOG 확인:
- track:removed duplex=half → broadcast 생략 확인 (TRACKS_UPDATE(remove) 안 나감)
- re-grant: 같은 SSRC resume → ptt-video 재등록 → PTT 발화 성공
- full/half 혼합 시나리오 (half→full→full→half) 정상

---

## 미해결: half-duplex 2차 PTT 시 내 카메라 프리뷰 미표시

### 증상
- 2차 grant → 1차 PTT → 내 카메라 영역 정상
- 2차 grant → 2차 PTT (또는 re-grant PTT) → 내 카메라 영역 미표시

### 추적 중 확인된 것
- floor:taken 핸들러에서 `sdk._stream?.getVideoTracks()?.[0]` 읽어서 video element 생성
- 발언 중(talking)이면 PowerManager HOT → COLD 전환 불가 → PowerManager 무관
- 정확한 원인 미확정 — 다음 세션에서 추적

### 다음 세션 조사 방향
- floor:taken 시점에 `sdk._stream`의 video track 상태 확인 (콘솔 로그 추가)
- moderate:authorized → floor:idle → floor:taken 이벤트 순서/타이밍 확인
- showSlideAvatar 상태 추적

---

## 기각된 접근법

### 1. unpublishTracks 제거 (subscriber inactive 안 거치게) — 기각
- 서버에 트랙 등록 유지 + replaceTrack(null)로 RTP만 중단
- STALLED 오탐, 유령 트랙 관리 부수 문제
- **mute ≠ 자격 회수** 원칙 위반 (PROJECT_MASTER 명시)
- full-duplex에는 적용 불가 (서버가 개별 user track을 관리)

### 2. pub/sub 동일 처리 (duplex 무관 transceiver 퇴역) — 기각
- half-duplex에서 새 SSRC 만들어봤자 SFU가 vSSRC로 덮어씀 → subscriber에 무의미
- 서버에 old SSRC 트랙 남아있는 상태에서 새 SSRC publishTracks → 같은 source에 두 트랙 공존 (교체 로직 없음)
- add_track_full은 SSRC 기준 조회 — source 기반 교체 로직 없음

### 3. clone() (수신 측) — 기각
- 같은 receiver 기반이면 clone도 broken pipeline 공유
- decoded_delta 정상 → 디코딩 OK, 렌더링만 깨짐

---

## 교훈

- **"unpublish가 나가기처럼 동작해야 한다"** — half-duplex virtual track은 방 레벨 자원. 개별 참가자 unpublish가 subscriber의 m-line 상태를 바꾸면 안 됨. 일반 PTT 나가기와 동일 패턴이 정공법.
- **duplex별 분기가 필요한 이유**: full은 per-user SSRC, half는 shared vSSRC. 해결 방향이 근본적으로 다름.
- **서버 한 줄 수정 > 클라이언트 꼼수**: half-duplex 문제는 서버에서 broadcast 필터링(3줄)으로 해결. 클라이언트 transceiver 퇴역은 불필요.

---

## 수정 파일 목록

| 파일 | 변경 | 상태 |
|------|------|------|
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | half-duplex remove broadcast 생략 | ✅ 완료 |
| `core/moderate.js` | _onUnauthorized duplex별 분기 | ✅ 완료 |
| `core/room.js` | resolveOnTrack clone() 원복 | ✅ 완료 |
| `demo/scenarios/moderate/app.js` | 로컬 카메라 마운트 full 조건 제거 | ✅ 완료 |

---

*author: kodeholic (powered by Claude)*
