# 세션 컨텍스트: Simulcast Graceful Layer Switching
**날짜**: 2026-03-26 (야간)
**범위**: oxlens-sfu-server + oxlens-home

---

## 핵심 성과: Simulcast Stall 근본 원인 해결

### 근본 원인 체인 (진단 순서대로)

1. **PLI SSRC 하드코딩** — fan-out 자가 치유 PLI가 항상 h SSRC로 → l 전환 후 l SSRC PLI 필요 → 수정
2. **Governor Layer 하드코딩** — `spawn_pli_burst`가 Governor를 항상 `Layer::High`로 체크 → l PLI를 h 상태에 기록 → Governor 오차단 → 수정 (layer 파라미터 추가, 13곳)
3. **Chrome l SSRC PLI 무시** — NAL 덤프로 확인: l에 `nal=1`(P-frame)만 도착. h SSRC PLI로 바꿔도 l 키프레임 안 옴. **Mozilla Bug 1498377 (2018, 아직 OPEN)**: webrtc.org SimulcastEncoderAdapter가 non-primary 레이어 PLI에 키프레임 미생성
4. **근본 해결: Graceful Layer Switching** — LiveKit 패턴 적용. `switch_layer()` 즉시 실행 → stall 대신, `target_rid` 설정 + current layer 계속 릴레이 + target 키프레임 자연 도착(3~10초) 시 전환

### 업계 선례

- **Mozilla Bug 1498377**: "primary가 아닌 simulcast 스트림에 FIR/PLI → 키프레임 미생성" — webrtc.org 엔진 버그, 7년째 OPEN
- **mediasoup Issue #296**: H264 simulcast 동일 문제. Chrome 주기적 키프레임까지 대기가 사실상 해법
- **LiveKit**: `Forwarder` + `DownTrack`에서 currentLayer/targetLayer 분리. target 키프레임 도착까지 current 릴레이 → stall 없음

---

## 완료된 서버 변경 (oxlens-sfu-server)

### 1. Graceful Layer Switching (핵심)
**participant.rs**: `SubscribeLayerEntry`에 `target_rid: Option<String>` 추가

**ingress.rs fan-out 로직 변경**:
```
기존: sub.rid == "pause" || sender_rid != sub.rid → drop
변경:
  - pause + target 아님 → drop
  - target layer + keyframe → 전환 실행! (SIM:SWITCH 로그)
  - current layer → 기존대로 rewrite + 릴레이
  - 다른 레이어 → drop
```

**track_ops.rs SUBSCRIBE_LAYER 변경**:
```
기존: entry.rid = target.rid + switch_layer() → 즉시 pending_keyframe=true → stall
변경:
  - pause → 즉시 적용 (릴레이 중단)
  - h↔l → target_rid 설정, current 유지 (graceful)
  - pause→h/l → target_rid 설정 + 키프레임 대기
```

### 2. PLI 대상 SSRC 통일 (h SSRC)
- ingress.rs: fan-out 자가 치유 PLI → `find_ssrc_by_rid("h")` (이전: subscriber 요청 rid)
- track_ops.rs: SUBSCRIBE_LAYER PLI → `rid.as_deref() == Some("h")` + `Layer::High`
- **이유**: Chrome SimulcastEncoderAdapter는 h PLI에만 전체 레이어 키프레임 생성

### 3. spawn_pli_burst layer 파라미터 추가
- pli.rs: `layer: Layer` 파라미터 추가, Governor 체크에 실제 레이어 사용
- 전체 호출처 13곳 수정 (ingress 5, track_ops 4, floor_ops 2, tasks 2)

### 4. build.rs 빌드 정보 주입
- `BUILD_INFO:hash+dirty@timestamp` 형식
- lib.rs: 시작 로그, env.rs: 어드민 스냅샷
- `rerun-if-changed` 미지정 → 매 빌드마다 타임스탬프 갱신
- 검증: `strings target/release/oxsfud | grep -o "BUILD_INFO:[^ ]*"`

### 5. 진단 로그 (진단 완료 후 유지)
- `[SIM:SWITCH]` — 레이어 전환 성공 로그 (old->new, ssrc)
- NAL 덤프 코드 제거됨 (graceful switching으로 대체)

---

## 완료된 클라이언트 변경 (oxlens-home)

### 1. ROOM_SYNC incremental + RESYNC 삭제
- `client.js`: `_onTracksResync()` 삭제, `_onRoomSyncIncremental()` 추가
- `signaling.js`: TRACKS_RESYNC(op=106) 핸들러 삭제
- `media-session.js`: `onTracksResync()` 삭제
- subscribe PC 전체 재생성 코드 경로 완전 제거

### 2. health-monitor 방어 로직 제거
- ROOM_SYNC 자동 복구 제거 (관측 로그만 유지)

### 3. redistributeTiles debounce 80ms
- IO 콜백 + 레이아웃 변경 다발 → 80ms 모아서 op=51 배치 1회

### 4. 3초 안정화 타이머 — 추가 후 롤백 완료
- 근본 해결(graceful switching)이 정답. 땜빵 코드 전부 제거됨

---

## 미해결 — 다음 세션 최우선

### 1. 재입장 시 _visibleThumbs 비어있어서 pause로 빠지는 문제

**증상**: 퇴장→재입장 반복 시 thumbnail 영상이 간헐적으로 안 보임
**원인**: 재입장 시 `redistributeTiles()` 실행 시점에 IntersectionObserver 콜백이 아직 안 옴 → `_visibleThumbs` 비어있음 → visible thumb이 전부 "hidden" 판정 → pause 요청
**서버 로그 증거**:
```
SUBSCRIBE_LAYER subscriber=U365 publisher=U140 rid=pause  ← l이어야 하는데 pause
SUBSCRIBE_LAYER subscriber=U365 publisher=U572 rid=pause  ← l이어야 하는데 pause
```

**수정 방향**: `_visibleThumbs`가 비어있을 때 기본값을 pause 대신 l로. 또는 낙관적 선등록(`_setupThumbObserver`에서 `_visibleThumbs.add(uid)`)이 재입장 시에도 동작하는지 확인. resetUI → _destroyThumbObserver → _visibleThumbs.clear() → 재입장 → renderConfGrid → updateLayout → _setupThumbObserver에서 다시 선등록해야 함.

**파일**: `demo/client/app.js` — `_setupThumbObserver()`, `redistributeTiles()`, `updateLayout()`

### 2. SKILL_OXLENS.md 업데이트
- Graceful Layer Switching 완료 항목 추가
- 기각 사항: "PLI로 l 키프레임 강제 생성" (Mozilla Bug 1498377), "switch_layer() 즉시 실행" (stall 유발)
- 확정 원칙: "Simulcast PLI는 항상 h(primary) SSRC로"

### 3. 세션 컨텍스트 파일 작성
- 이 파일을 20260326_simulcast_graceful_switching.md로 저장 완료

---

## 기각된 접근법 (절대 하지 말 것)

- **l SSRC PLI로 l 키프레임 강제** — Chrome SimulcastEncoderAdapter가 무시. NAL 덤프로 확인 (nal=1 P-frame만 도착). Mozilla Bug 1498377 (2018~현재 OPEN)
- **h SSRC PLI로 전체 레이어 키프레임 기대** — h 키프레임은 오지만 l 키프레임은 보장 안 됨. 주기적(3~10초) 자연 생성만 가능
- **switch_layer() 즉시 실행** — pending_keyframe=true → 키프레임 올 때까지 모든 패킷 drop → 3~10초 stall. graceful switching이 정답
- **3초 입장 안정화 지연** (`_joinStabilizeTimer`) — 땜빵. 근본 원인 해결(graceful switching)이 선행됨. 코드 추가 후 롤백 완료

---

## 변경 파일 전체 목록

### oxlens-sfu-server
| 파일 | 변경 |
|------|------|
| `build.rs` (신규) | git hash + dirty + 빌드 시간 바이너리 주입 |
| `src/lib.rs` | 시작 로그에 BUILD_INFO 출력 |
| `src/metrics/env.rs` | 어드민 스냅샷에 build_info 필드 |
| `src/room/participant.rs` | SubscribeLayerEntry에 target_rid 추가 |
| `src/transport/udp/pli.rs` | spawn_pli_burst에 layer 파라미터 추가 |
| `src/transport/udp/ingress.rs` | graceful fan-out + PLI h SSRC + is_detail 파라미터 |
| `src/signaling/handler/track_ops.rs` | SUBSCRIBE_LAYER graceful + PLI h SSRC + Layer import |
| `src/signaling/handler/floor_ops.rs` | spawn_pli_burst layer 파라미터 + Layer import |
| `src/tasks.rs` | spawn_pli_burst layer 파라미터 (FLOOR_QPOP, GOV:UG) |

### oxlens-home
| 파일 | 변경 |
|------|------|
| `demo/client/app.js` | redistributeTiles debounce, 3초 타이머 롤백 |
| `core/client.js` | _onTracksResync 삭제, _onRoomSyncIncremental 추가 |
| `core/signaling.js` | TRACKS_RESYNC 핸들러 삭제 |
| `core/media-session.js` | onTracksResync 삭제 |
| `core/health-monitor.js` | ROOM_SYNC 자동 복구 제거 |

---

*author: kodeholic (powered by Claude)*
