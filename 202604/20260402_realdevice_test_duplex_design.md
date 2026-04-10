# 세션: 실기기 테스트 + RTP-first 근본 수정 + 트랙 단위 Duplex 설계 구현

- **날짜**: 2026-04-02 (야간)
- **버전**: v0.6.11 (버전 표기 v0.6.10, 빌드 hash 12f6932)
- **영역**: 서버(ingress.rs, track_ops.rs, room_ops.rs, participant.rs, stream_map.rs, message.rs)

---

## 1. 실기기 테스트 분석

### 테스트 1: PTT (room=ecb9d6ca, 4대)

- **기기**: U901(Android Exynos), U028(Android ExternalEncoder), U972(iOS), U592(Android Qualcomm)
- **결과**: 영상 전원 정상 표시, 지연 있음
- **서버 로그**: `/Users/tgkang/repository/testlogs/oxsfud_20260402.log` (74995줄, PTT+Conference 모두 포함)

**PTT 파이프라인 정상 동작 확인:**
- 키프레임 대기: 23ms~443ms (PLI burst #1 전부 Governor 자동 취소)
- ts_gap B안(arrival-time 기반): 4회 전환 모두 정확 계산 확인
- silence flush, gating, rewriting 전부 정상
- NON-SIM:REG 사전등록 정상 (Phase 19 수정 효과)

**U028 네트워크 문제 (SFU 이슈 아님):**
- available_bitrate=225kbps (나머지 2.5~3.3Mbps)
- video_freeze 14회, loss_burst, rtx_budget_exceeded
- 같은 WiFi인데 기기 안테나/거리 문제

**스냅샷 시점(21:09:58) recv_delta=0/decoded_delta=0 — floor idle 상태라 정상**
- U972만 pkts_delta 있음: iOS는 Power FSM 미적용(hasTrack=true 유지)

### 테스트 2: Conference 비심방 (room=41e3a3c1, 4대)

- **기기**: U592(pt=103), U349(iOS pt=96), U901(pt=103), U028(pt=119)
- **결과**: 특정 단말에서 특정 영상 미노출

**영상 미노출 현황:**

| 수신자 | ←U349(pt=96) | ←U592(pt=103) | ←U901(pt=103) | ←U028(pt=119) |
|--------|-------------|---------------|---------------|---------------|
| U592 | ✅ fps=24 | — | ❌ dropped=270 | ❌ dropped=192 |
| U349 | — | ✅ fps=24 | ✅ fps=22 | ✅ fps=17 |
| U901 | ✅ fps=24 | ✅ fps=24 | — | ✅ fps=16 |
| U028 | ✅ fps=24 | ✅ fps=24 | ❌ pkts=0 | — |

---

## 2. 근본 원인 — RTP-first가 non-sim에서도 동작

### 서버 로그 증거 (Conference, U901)

```
21:25:02.108 [STREAM] NEW video rid=1 ssrc=0x0D929DBD pt=120  ← RTX! (intent: rtx=120)
21:25:02.111 [STREAM] NEW video rid=1 ssrc=0xEC005AE3 pt=119  ← 진짜 video
21:25:02.242 [NON-SIM:REG] user=U901 ssrc=0xEC005AE3 kind=video rtx_ssrc=Some(0x0D929DBD)
```

**Phase 19에서 NON-SIM:REG를 추가했지만, ingress의 RTP-first discovery를 non-sim에서 비활성화하지 않았음.** 두 경로가 동시에 돌면서:
1. RTP-first가 RTX(pt=120)를 video로 오등록 + TRACKS_UPDATE broadcast (video_pt=0)
2. 134ms 뒤 NON-SIM:REG가 올바르게 등록하지만 이미 오염된 broadcast 전송 완료

결과: U028의 SUB_TRACKS에 U901 video 2개(0x0D929DBD + 0xEC005AE3), subscribe SDP mid 중복.

### video_pt=0 전달 문제

STREAM:NOTIFY 전수 확인: **video 트랙 전부 video_pt=0**. RTP-first 경로에서 intent 미도착 상태라 PT 정보 없음.

---

## 3. 수정 내역 (빌드 성공)

### 3-1. RTP-first non-sim 차단 (ingress.rs)

**`resolve_stream_kind()`에 `simulcast_enabled: bool` 파라미터 추가.**
2차(rid extension) + 3차(repaired-rid extension) 체크를 `if simulcast_enabled { ... }` 블록으로 감쌈.

non-sim에서 RTP가 intent 전에 도착 시:
- Audio(PT=111) → 1차 체크 → Audio ✅ (변경 없음)
- Video/RTX → 2차 SKIP → 3차 SKIP → 4차(no video) → 5차(no intent) → **Unknown**
- PUBLISH_TRACKS 도착 → register_nonsim_tracks() → Unknown 제거, 올바르게 등록
- 다음 RTP → HIT → 정확한 StreamKind

### 3-2. PT 누락 agg_log (3종)

| agg_log 키 | 파일 | 모드 | 의미 |
|---|---|---|---|
| `nonsim_video_no_pt` | track_ops.rs | non-sim | PUBLISH_TRACKS에 video PT 누락 |
| `nonsim_video_no_rtx_pt` | track_ops.rs | non-sim | PUBLISH_TRACKS에 RTX PT 누락 |
| `sim_video_no_pt` | ingress.rs | simulcast | RTP-first broadcast 시 intent 미도착 race |
| `ptt_vtrack_no_pt` | room_ops.rs | PTT | 다른 publisher 있는데 intent에 PT 없음 |

### 3-3. 트랙 단위 DuplexMode — Phase 1 데이터 모델 (6파일)

**설계 의도**: room.mode(Conference/PTT) 대신 트랙별 duplex(full/half)로 판단. 같은 방에 full+half 공존 가능.

```
참가자A: audio=half(p=15), video=full     ← 사회자
참가자B: audio=half(p=10), video=half     ← 청중
참가자C: audio=full,       video=full     ← 통역사
참가자D: audio=half(p=10), video=off      ← 음성만 참여
```

**추가된 코드:**

| 파일 | 변경 |
|------|------|
| participant.rs | `DuplexMode` enum (Full/Half) + `Default` impl + `from_str_or_default(s, is_ptt)` + `Track.duplex` 필드 + `add_track_ext` duplex 파라미터 |
| message.rs | `PublishTrackItem.duplex: Option<String>` (#[serde(default)]) |
| stream_map.rs | `RtpStream.duplex` + `VideoSource.duplex` + import DuplexMode |
| track_ops.rs | VideoSource 생성 시 duplex + register_nonsim_tracks에서 duplex 읽기/stream_map 설정/add_track_ext 전달 |
| ingress.rs | register_and_notify_stream에서 add_track_ext에 duplex 전달 (room.mode 기반 기본값) |

**기본값 정책**: 클라이언트가 duplex 안 보내면 `room.mode == Ptt → Half`, 아니면 `Full`. 기존 동작 100% 유지.

### 3-4. track_duplex 핫패스 전파 (ingress.rs)

**`resolve_stream_kind()` 반환 타입 변경**: `(StreamKind, bool)` → `(StreamKind, bool, DuplexMode)`

- HIT: `stream.duplex` 반환 (stream_map에 저장된 값)
- MISS: `DuplexMode::Full` 기본값 (register_nonsim_tracks가 나중에 교정)
- 15개 return 문 전부 수정

**`prepare_fanout_payload()`에 `track_duplex: DuplexMode` 파라미터 추가.** 아직 사용 안 함 (Step 2 대기).

---

## 4. 다음 세션 작업: Phase 2 Step 2 — room.mode 분기 교체

### ingress.rs RoomMode::Ptt 14곳 분류

| # | 줄(approx) | 현재 체크 | 용도 | 교체 대상 |
|---|-----------|----------|------|----------|
| 1 | ~162 | `room.mode != Ptt` | Active Speaker (PTT는 floor controller 사용) | `track_duplex != Half` |
| 2 | ~270 | `room.mode != Ptt` | SubscriberGate pause (Conference video만) | `track_duplex != Half` |
| 3 | ~284 | `room.mode == Ptt && Video` | PTT fan-out PT rewrite (subscriber별 video PT 교체) | `track_duplex == Half && Video` |
| 4 | ~492 | `room.mode == Ptt` | **Floor gating** (floor holder만 통과) | `track_duplex == Half` |
| 5 | ~508 | `room.mode == Ptt` | **SSRC rewriting** (PttRewriter) | `track_duplex == Half` |
| 6 | ~1089 | `room.mode == Ptt` | duplex default (이미 추가됨) | 유지 (fallback) |
| 7 | ~1271 | `room.mode != Ptt` | register_and_notify_stream SubscriberGate | `track_duplex != Half` |
| 8 | ~1305 | `room.mode != Ptt` | MBCP skip (non-PTT) | floor controller 존재 여부로 전환? |
| 9 | ~1673 | `room.mode == Ptt` | SR translation: PTT audio virtual SSRC | `track_duplex == Half` |
| 10 | ~1676 | `room.mode == Ptt` | SR translation: PTT video virtual SSRC | `track_duplex == Half` |
| 11 | ~1938 | `room.mode == Ptt` | NACK: is_ptt flag | `track_duplex == Half` |
| 12 | ~2146 | `room.mode == Ptt` | NACK remap: virtual→real seq | `track_duplex == Half` |
| 13 | ~2167 | `room.mode != Ptt` | SR relay: PTT skips SR | `track_duplex != Half` |
| 14 | ~2247 | `room.mode == Ptt` | NACK reverse mapping | `track_duplex == Half` |

### 교체 시 주의사항

1. **#4, #5 (gating + rewriting)**: `track_duplex`가 이미 핫패스에 있으므로 직접 교체 가능
2. **#9~#14 (SR translation, NACK)**: 이 영역은 `prepare_fanout_payload` 밖, 별도 함수에서 room.mode를 직접 참조. track_duplex 전파가 추가로 필요할 수 있음
3. **#8 (MBCP)**: MBCP는 PTT Floor Control 프로토콜. room.mode가 아닌 **room에 FloorController가 활성인지**로 판단하는 게 맞음
4. **혼합 방**: full+half 트랙이 같은 방에 공존 시, PttRewriter와 FloorController가 room.mode와 무관하게 동작해야 함 → 현재 `room.audio_rewriter` / `room.video_rewriter`는 room 생성 시 PTT 방에서만 초기화됨. **모든 방에서 rewriter 초기화 필요** (half 트랙이 있을 수 있으므로)

### 제안 진행 순서

**A 그룹 (핫패스, track_duplex 이미 전파됨)**: #4 gating → #5 rewriting → #3 PT rewrite → #2 SubscriberGate
**B 그룹 (SR/NACK, 추가 전파 필요)**: #9~#14
**C 그룹 (기타)**: #1 Active Speaker, #7 register notify, #8 MBCP

### 구조적 선결과제

- **FloorController**: 현재 PTT room에서만 활성. half-duplex 트랙이 있는 모든 방에서 활성화 필요
- **PttRewriter**: 현재 PTT room에서만 생성. half-duplex 트랙이 있으면 rewriter 필요 → lazy 초기화 또는 모든 방에 생성
- **room.mode 제거 시점**: Phase 2 완료 + 검증 후 Phase 3에서 RoomMode::Ptt enum 제거

---

## 5. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| RTP-first에서 Unknown 보류 → intent 도착 후 재분류 | 레이스 컨디션 자체는 그대로. 도착 순서 의존 구조 유지 |
| simulcast_enabled만으로 2차 가드 + RTP-first 유지 | non-sim에서 rid 오독 재발 가능. 근본 차단이 정답 |
| room.mode를 compound mode(Conference+PTT)로 확장 | 모드 폭발. 트랙 단위 duplex가 정답 (4/1 확정) |
| 사회자 audio=full (전이중) | 사회자도 half + priority(preempt)가 정답. FloorController 로직 통일 |
| role(moderator/panelist)을 SFU에 추가 | 서비스 결합도 높아짐. SFU는 트랙 duplex만 봐야 함 |

---

## 6. 수정된 파일 목록 (빌드 성공 상태)

| 파일 | 수정 내용 |
|------|----------|
| `src/transport/udp/ingress.rs` | simulcast_enabled 가드(2차/3차), sim_video_no_pt agg_log, resolve_stream_kind 반환 (StreamKind, bool, DuplexMode), prepare_fanout_payload track_duplex 파라미터, DuplexMode import |
| `src/signaling/handler/track_ops.rs` | DuplexMode import, VideoSource.duplex, register_nonsim_tracks duplex(stream_map + add_track_ext), nonsim agg_log |
| `src/signaling/handler/room_ops.rs` | ptt_vtrack_no_pt agg_log (첫 참가자 vs 비정상 분리) |
| `src/room/participant.rs` | DuplexMode enum + Default + Display + from_str_or_default, Track.duplex, add_track_ext/add_track_full duplex 파라미터 |
| `src/room/stream_map.rs` | RtpStream.duplex + VideoSource.duplex + DuplexMode import |
| `src/signaling/message.rs` | PublishTrackItem.duplex: Option<String> |

---

## 7. PENDING (이전 세션에서 이월)

- [ ] ts_gap drift B안 RPi 실기기 검증
- [ ] CHANGELOG.md 업데이트 (v0.6.11 → v0.6.12)
- [ ] SKILL_OXLENS.md 업데이트 (DuplexMode 설계 추가)
- [ ] SESSION_INDEX.md 업데이트

---

*author: kodeholic (powered by Claude)*
