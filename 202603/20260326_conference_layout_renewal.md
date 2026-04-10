# 세션 컨텍스트: Conference 레이아웃 리뉴얼 (Main+Thumbnail)
**날짜**: 2026-03-26
**범위**: oxlens-home (demo/client/)

---

## 완료 항목

### Main+Thumbnail 레이아웃

기존 N×N 그리드 → Main+Thumbnail 전환 완료.

#### 레이아웃 동작
- **1인**: 전체 화면 (기존 동일)
- **2인+**: Main 대화면(flex-1) + 하단 Thumbnail strip(h-120px, 가로 스크롤)
- Main 선정: `_resolveMainUid()` — pinned > fullscreen > first remote > local
- Thumbnail 탭 → pin, Main 탭 → unpin
- `updateLayout()`은 PTT 모드에서 early return (className 덮어쓰기로 hidden 유실 방지)

#### Simulcast 3단계 분배 (IntersectionObserver)
- main → h (고화질, 대화면)
- visible thumb → l (저화질, 보이는 썸네일)
- hidden thumb → pause (대역폭 0, 스크롤 밖)
- IntersectionObserver: `#thumbnail-strip`이 root, threshold=0.3
- 낙관적 선등록: observe 시 `_visibleThumbs.add(uid)` → 콜백 전 pause 끄김 방지
- observer 콜백(hidden 확인) → `_visibleThumbs.delete` → `redistributeTiles()` 재호출
- `updateLayout()` 끝에서 자동 호출 → 중복 호출 제거
- manual override (`_manualLayerOverride`) 유지
- **서버 fan-out 이미 구현 완료**: ingress.rs L583 `sub.rid == "pause"` → 릴레이 skip

#### 핵심 설계 결정
- **DOM 비파괴 재배치**: `updateLayout()`은 기존 타일 DOM을 파괴하지 않고 appendChild로 재배치. srcObject 보존 → 비디오 끊김 없음
- **thumbnail-strip**: `#thumbnail-strip` div를 `conf-grid` 내부에 동적 생성/제거
- **PTT guard**: `currentRoomMode === "ptt"` → updateLayout early return (hidden 유실 버그 수정)
- **enterFullscreen**: strip.style.display="none" 방식 (DOM 제거 아님)

---

## 변경 파일

| 파일 | 변경 |
|------|------|
| `demo/client/index.html` | .no-scrollbar, .is-main/.is-thumb CSS, conf-grid flex |
| `demo/client/app.js` | updateLayout(), _resolveMainUid(), pinnedUid, IntersectionObserver, redistributeTiles 3단계 |

---

## 버그 수정

- **PTT 화면 분할**: updateLayout()이 conf-grid className을 덮어써서 hidden 유실 → PTT guard 추가

---

## 기각된 접근법

- **N×N 그리드에 main 강조만 추가** — 관제 시나리오에서 main 대화면이 핵심 요구사항. 그리드는 5인 이상에서 타일이 너무 작아짐
- **iframe/별도 container로 main 분리** — srcObject 재할당 필요, 비디오 끊김 발생

---

## 아키텍처 인사이트

### 100인 스케일 가능성
- video가 SFU 대역폭의 90%+. main=h 1개 + visible thumb=l 4~5개 + 나머지 전부 pause → 100인이어도 video egress는 30인 전원 h보다 적음
- **다음 천장은 audio fan-out**: 100인 전원 unmute → egress ~50만 패킷/초. 해법은 audio mixing 또는 cascading SFU이지만 지금은 아님
- OxLens 타겟(파견센터/보안)은 대부분 mute + 발화자 제한 운용이 자연스러움

---

## ROOM_SYNC incremental (subscribe PC 보존)

기존: health-monitor decoder stall → ROOM_SYNC → `_onTracksResync()` → subscribe PC 전체 재생성
변경: health-monitor decoder stall → ROOM_SYNC → `_onRoomSyncIncremental()` → diff → add/remove 개별 처리

- `client.js`: `_onRoomSyncIncremental(serverTracks)` 추가 — track_id 기준 diff
- `signaling.js`: ROOM_SYNC 응답에서 `_onTracksResync` → `_onRoomSyncIncremental` 호출
- `health-monitor.js`: 주석 업데이트 (ROOM_SYNC 요청 자체는 동일)
- `_onTracksResync` 삭제 완료 (TRACKS_RESYNC op=106 핸들러도 함께 삭제)
- `media-session.js` `onTracksResync()` 삭제 완료
- subscribe PC 전체 재생성 코드 경로 완전 제거

---

## 버그 수정: simulcast 자가 치유 PLI 대상 SSRC 오류

**증상**: U068←U569 영상 안 보임. 28패킷 h 수신 후 l 전환 → 무한 stall
**근본 원인**: ingress.rs fan-out 자가 치유에서 PLI를 항상 `find_ssrc_by_rid("h")`로 보냄.
subscriber가 l 레이어 원하는데 h에 PLI → Chrome은 h 키프레임만 생성 → l 키프레임 영영 안 옴
**수정**: `target.subscribe_layers`에서 subscriber가 원하는 rid 조회 → 해당 SSRC에 PLI

### health-monitor 방어 로직 제거
- ROOM_SYNC 자동 복구 제거 (관측 로그만 유지)
- 100인 규모 네트워크 순단 시 방어 로직이 장애 증폭기가 되는 문제
- 근본 원인(PLI 대상 SSRC) 수정이 선행되어야 함

---

## 다음 세션 참고

- **Active Speaker 자동 main 전환**: Phase 4 (ACTIVE_SPEAKERS op=144) 구현 후, top speaker를 자동 main으로 전환
- **Thumbnail strip 크기 반응형**: 현재 h-120px 고정 → 모바일/태블릿 대응 시 조정 필요
- **안정화 기간 필요**: 다양한 NAT 환경, 모바일 네트워크, 장시간 운용, 단말 다양성 테스트

*author: kodeholic (powered by Claude)*
