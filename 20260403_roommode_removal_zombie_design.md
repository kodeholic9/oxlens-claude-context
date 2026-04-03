# 세션: RoomMode 완전 제거 + 좀비 2단계 설계

- **날짜**: 2026-04-03 (야간 세션)
- **버전**: v0.6.14-dev → v0.6.15-dev
- **영역**: 서버 전역 리팩토링 (14파일)
- **이전 세션**: `20260403_screenshare_mute_bug_analysis.md`

---

## 1. 완료: RoomMode 완전 제거

### 배경
simulcast → `Track.simulcast`, duplex → `Track.duplex`로 이미 트랙 단위 전환 완료 상태.
방 단위 `room.mode`(Conference/Ptt) + `room.simulcast_enabled` 잔재 완전 제거.

### 제거된 것
- `config::RoomMode` enum (Conference, Ptt)
- `message::RoomModeField` enum + `to_config()`
- `RoomCreateRequest.mode`, `RoomCreateRequest.simulcast` 필드
- `Room.mode`, `Room.simulcast_enabled` 필드
- `Room::new()`, `RoomHub::create()` — mode/simulcast 파라미터 제거
- `DuplexMode::from_str_or_default()` — `is_ptt_room` 파라미터 제거 (항상 Full 기본)

### 추가된 것
- `Room::has_half_duplex_tracks()` — 방에 half-duplex 트랙 존재 여부
- `Room::has_simulcast_tracks()` — 방에 simulcast 트랙 존재 여부
- `MediaIntent::audio_duplex: Option<DuplexMode>` — audio 트랙 duplex 속성
- `MediaIntent::find_video_by_source()` — source 기반 VideoSource 조회

### 수정 파일 (14개)

| 파일 | 변경 |
|------|------|
| config.rs | `RoomMode` enum 제거 |
| message.rs | `RoomModeField` + mode/simulcast 필드 제거, duplex 주석 수정 |
| room.rs | mode/simulcast_enabled 제거, `has_half_duplex_tracks()`/`has_simulcast_tracks()` 추가 |
| participant.rs | `from_str_or_default` — `is_ptt_room` 제거 |
| stream_map.rs | `audio_duplex` 필드 + `find_video_by_source()` + 테스트 수정 |
| ingress.rs | `RoomMode` import 제거, `_is_screen_video`/`_room` 제거, duplex→intent 기반 |
| track_ops.rs | `is_ptt`/`simulcast_enabled` 제거, TRACKS_ACK full+half 통합, `register_nonsim_tracks` sim 필터, `audio_duplex` intent 설정 |
| helpers.rs | `server_extmap_policy` rid 항상 포함, `collect_subscribe_tracks` half-duplex 필터, dead code `simulcast_replace_video_ssrc_direct` 제거 |
| room_ops.rs | ROOM_LIST/CREATE/JOIN/SYNC에서 mode/simulcast 제거, subscribe_tracks 통합(full+virtual 공존), floor auto-release 3곳 무조건 실행 |
| floor_ops.rs | PTT room 가드 2곳 제거 (모든 방에서 Floor 허용) |
| tasks.rs | floor_timer→`has_half_duplex_tracks()`, active_speaker→모든 방, sim_upgrade→`has_simulcast_tracks()` |
| admin.rs | mode/simulcast 제거, `has_half_duplex_tracks()` 기반 PTT 섹션 |
| startup.rs | 기본 방 단순화 (mode/simulcast 파라미터 제거), unused `config` import 제거 |
| transport/udp/mod.rs | `room.mode == Ptt` → `room.floor.current_speaker()` 직접 체크 |

### 핵심 설계 변경

**subscribe_tracks 통합 (ROOM_JOIN/ROOM_SYNC)**:
- `collect_subscribe_tracks()`: full-duplex 트랙만 수집 (half-duplex 필터)
- `has_half_duplex_tracks()` → virtual audio/video SSRC 추가 (PttRewriter 경유)
- Conference/PTT/혼합 전부 같은 코드 경로

**TRACKS_ACK expected set 통합**:
- full-duplex 트랙 → 실제 SSRC (simulcast vssrc 포함)
- half-duplex 트랙 → expected에서 제외
- `has_half_duplex_tracks()` → virtual SSRC 추가

**floor auto-release**: room.mode 가드 제거 → 무조건 실행 (FloorController가 빈 상태면 no-op)

**extmap**: rid + repair-rid 항상 포함 (어떤 참가자든 simulcast 가능)

**register_nonsim_tracks**: 항상 호출, 내부에서 simulcast video source는 skip (intent 기반 판단)

### 빌드 결과
- `cargo build --release` — 성공, warning 0

---

## 2. 검토 완료: 좀비 2단계 감지 (Suspect → Zombie)

### 현재 vs 업계 비교

| SFU | 메커니즘 | 감지 시간 |
|-----|---------|---------|
| mediasoup | ICE Consent (RFC 7675) | 30초 |
| Pion/LiveKit | ICE 상태 머신 | disconnected 5초 → failed 25초 |
| Janus | session_timeout | 60초 |
| **OxLens 현재** | STUN/RTP last_seen | **120초 (업계 4배)** |

### 확정 설계

```
ALIVE ──(20초 무응답)──> SUSPECT ──(15초 추가)──> ZOMBIE(삭제)
  ^                         │
  └──(packet received)──────┘
```

| 상수 | 값 |
|------|-----|
| `REAPER_INTERVAL_MS` | 5,000 (5초) |
| `SUSPECT_TIMEOUT_MS` | 20,000 (20초) |
| `ZOMBIE_TIMEOUT_MS` | 35,000 (35초) |

### agg-log 이벤트 3종

```
session:suspect   user=U170 room=R001 last_seen_ago_ms=21340
session:zombie    user=U170 room=R001 last_seen_ago_ms=36120 suspect_duration_ms=15780
session:recovered user=U170 room=R001 suspect_duration_ms=8420
```

### 데이터 구조
- `participant.suspect_since: AtomicU64` (0=ALIVE, non-zero=Suspect 진입 시각)
- 어드민 스냅샷에 `state: "alive"/"suspect"` 표시

---

## 3. 화면공유 / source 하드코딩 검토

핫패스에서 source 문자열("screen", "bodycam" 등) 참조 **없음** — 전부 `track.duplex`/`track.simulcast` 속성만 봄.

**1곳만 남아있음**: track_ops.rs intent 수신 시 sim 파생:
```rust
let sim = if duplex == DuplexMode::Half || src == "screen" { false } else { true };
```
→ 프리셋 작업 시 `TrackInfo.simulcast: Option<bool>` 추가로 제거 예정

bodycam/cctv 등 새 source 추가 시 핫패스 변경 불필요 확인 완료.

---

## 4. 다음 세션 작업

- [ ] 좀비 2단계 구현 (Suspect/Zombie + agg-log 3종 + 어드민 스냅샷)
- [ ] 프리셋 체계 구현 + TrackInfo.simulcast 필드 추가 → screen 하드코딩 제거
- [ ] 클라이언트 PUBLISH_TRACKS에 duplex/simulcast 명시 전송
- [ ] TRACKS_UPDATE에 duplex/simulcast 필드 추가
- [ ] 데모앱 components 추출 + 시나리오별 분리
- [ ] 세션 컨텍스트 / SKILL_OXLENS.md 업데이트

---

## 5. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| room.mode를 "default_duplex"로 이름만 변경 | 중간 레이어가 새 잔재가 됨. 프리셋이 대체하므로 완전 제거가 맞음 |
| Suspect 시 VIDEO_SUSPENDED broadcast | 인코더 문제용 이벤트와 의미 혼동. 내부 플래그로 시작 |
| ZOMBIE_TIMEOUT_MS 30초 (업계 표준) | PTT 현장 기기 모바일 불안정 고려하여 35초로 여유 |

---

## 6. 커밋

```
git commit -am "refactor: RoomMode 완전 제거 — room.mode/simulcast_enabled → track.duplex/track.simulcast 기반 전환

- RoomMode enum, RoomModeField, room.mode, room.simulcast_enabled 완전 삭제
- Room::new/create에서 mode/simulcast 파라미터 제거 (방은 빈 그릇)
- has_half_duplex_tracks(), has_simulcast_tracks() 헬퍼 추가
- floor_ops: PTT room 가드 제거 (모든 방에서 Floor 허용)
- tasks: floor_timer/active_speaker/sim_upgrade를 트랙 기반 판단으로 전환
- helpers: server_extmap_policy rid 항상 포함, collect_subscribe_tracks half-duplex 필터
- room_ops: ROOM_JOIN/SYNC subscribe_tracks 통합 (full + virtual 공존)
- ingress: _is_screen_video/_room dead code 제거, duplex를 intent 기반 파생
- 14파일 수정, dead code simulcast_replace_video_ssrc_direct 제거"
```

---

*author: kodeholic (powered by Claude)*
