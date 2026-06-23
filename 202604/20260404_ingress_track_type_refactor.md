# 설계: ingress TrackType 기반 경로 분리

- **날짜**: 2026-04-04
- **트리거**: 동적 추가된 half-duplex video가 PttRewriter 경로를 안 타는 버그
- **근본 원인**: `resolve_stream_kind` MISS 경로에서 `DuplexMode::Full` 하드코딩 → stream_map.duplex 오염 → notify_new_stream에서 subscriber에게 잘못된 duplex 전파 → SDP/Gate/fan-out/ROOM_SYNC 전부 연쇄 오류

---

## 1. 핵심 원칙

RoomMode 제거 이후, 트랙 라우팅은 **트랙별 속성 `duplex × simulcast`** 조합으로 결정된다.
방(room) 속성은 보지 않는다. 같은 방에 FullSim + HalfNonSim 트랙이 공존 가능.

### TrackType enum (신규)

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrackType {
    /// Full-duplex, non-simulcast: Conference audio/video, screen share
    FullNonSim,
    /// Full-duplex, simulcast: Conference video (h/l 레이어)
    FullSim,
    /// Half-duplex, non-simulcast: PTT audio/video (sim 강제 off)
    HalfNonSim,
    /// 판별 불가 (intent 미도착, Unknown SSRC)
    Pending,
}
```

금지 조합: `Half + Sim` — half-duplex → simulcast 강제 off (PttRewriter + SimulcastRewriter 충돌)

---

## 2. TrackType 결정 로직

### 입력
- `stream_map`의 기존 등록 정보 (HIT path)
- `intent`의 duplex/simulcast 속성 (MISS path)
- SSRC, RTP header extensions (rid, MID)

### 결정 시점 — `resolve_stream_kind` → `resolve_track_type`로 rename

```
fn resolve_track_type(...) -> (StreamKind, bool, TrackType)
```

반환값 변경: `DuplexMode` → `TrackType`

### HIT path (stream_map에 이미 있는 SSRC)

```
stream.kind != Unknown → (stream.kind, false, stream.track_type)
                                                  ↑ RtpStream에 TrackType 필드 추가
```

### MISS path (새 SSRC 발견)

| 판별 단계 | StreamKind | TrackType 결정 |
|-----------|-----------|---------------|
| Opus PT=111 | Audio | intent.audio_duplex → Half이면 HalfNonSim, 아니면 FullNonSim |
| rid extension (sim) | Video | FullSim (sim 경로 진입 = Full 확정) |
| repaired-rid (RTX) | Rtx | FullSim (RTX는 TrackType 무관) |
| RTX PT fallback | Rtx | 무관 |
| MID → audio | Audio | intent.audio_duplex 기반 |
| MID → video | Video | intent.find_video_by_mid → vs.duplex + vs.simulcast 기반 |
| MID → RTX | Rtx | 무관 |
| PROMOTED unknown→audio | Audio | intent.audio_duplex 기반 |
| PROMOTED unknown→video | Video | intent.find_video_by_mid → vs.duplex + vs.simulcast 기반 |
| Unknown (intent 미도착) | Unknown | **Pending** |

### TrackType 파생 헬퍼

```rust
fn derive_track_type(duplex: DuplexMode, simulcast: bool) -> TrackType {
    match (duplex, simulcast) {
        (DuplexMode::Half, _)      => TrackType::HalfNonSim,  // Half → sim 강제 off
        (DuplexMode::Full, true)   => TrackType::FullSim,
        (DuplexMode::Full, false)  => TrackType::FullNonSim,
    }
}
```

---

## 3. RtpStream 변경

```rust
pub struct RtpStream {
    // 기존 필드 유지
    pub duplex: DuplexMode,    // 삭제 대상 (TrackType이 대체)
    pub simulcast: bool,       // 유지 (fanout_simulcast_video에서 조회)
    // 신규
    pub track_type: TrackType, // 입구에서 확정, 이후 변경 없음
}
```

**검토 필요**: `duplex` 필드를 아직 쓰는 곳이 있는지 확인.
→ `stream.duplex`를 읽는 곳: `resolve_stream_kind` HIT path, `notify_new_stream`.
→ 둘 다 `track_type`으로 대체 가능. `duplex` 필드 **제거 가능**.

단, participant.Track에는 `duplex` 필드 유지 (collect_subscribe_tracks에서 필터용).
`track_type`과 `duplex`의 관계:
- `track_type.is_half() → duplex == Half`
- `track_type.is_sim() → simulcast == true`

---

## 4. register_and_notify_stream 변경

현재: intent에서 duplex 파생 → participant.tracks에 저장 → **stream_map 미갱신**

변경:
```
1. intent에서 TrackType 파생 (derive_track_type 사용)
2. stream_map.track_type 갱신 (MISS에서 Pending/잘못된 값이었을 경우 보정)
3. participant.tracks에 duplex + simulcast 저장 (기존 유지)
```

stream_map.track_type 보정은 한 번만 발생 (is_new_track=true일 때만 호출).

---

## 5. notify_new_stream 변경

현재: `stream.duplex`를 읽어서 TRACKS_UPDATE와 SubscriberGate 분기

변경: `stream.track_type`을 읽어서 분기

```
track_type 기반 분기:
- subscriber SSRC: HalfNonSim → 사용 안 함 (virtual SSRC는 방 레벨)
                   FullSim → vssrc
                   FullNonSim → 원본 SSRC
- SubscriberGate.pause(): FullNonSim/FullSim의 Video만
- TRACKS_UPDATE duplex 필드: track_type.to_duplex_str()
```

---

## 6. handle_srtp 경로 분리

### 공통 영역 (변경 없음)

```
[1] SRTP decrypt
[2] RTP parse
[3] resolve_track_type → (stream_kind, is_new_track, track_type)  ← rename
[4] if track_type == Pending → return (early exit)
[5] if is_new_track → register_and_notify_stream
[6] collect_rtp_stats
[7] Active Speaker: Audio && track_type != HalfNonSim             ← 공통 분기 (부가 처리)
[8] RTP gap detect (Video만)
[9] debug logging
```

### 분기 지점 ([9] 이후)

```rust
// [10] payload 생성 + fan-out
match track_type {
    TrackType::HalfNonSim => {
        self.fanout_half_duplex(&plaintext, &rtp_hdr, &sender, &room, stream_kind, is_detail).await;
    }
    TrackType::FullSim if stream_kind == StreamKind::Video => {
        let fanout_payload = plaintext.to_vec(); // passthrough
        // PLI Governor keyframe (sim 내부에서 처리하므로 여기서는 skip)
        self.fanout_simulcast_video(&fanout_payload, &rtp_hdr, &sender, &room, is_detail).await;
    }
    TrackType::FullNonSim | TrackType::FullSim /* audio */ => {
        let fanout_payload = plaintext.to_vec();
        // PLI Governor: non-sim video keyframe 감지
        if stream_kind == StreamKind::Video {
            let is_kf = is_vp8_keyframe(&fanout_payload) || is_h264_keyframe(&fanout_payload);
            if is_kf {
                if let Ok(mut ps) = sender.pli_pub_state.lock() {
                    on_keyframe_received(&mut ps, Layer::High);
                }
            }
        }
        self.fanout_full_nonsim(&fanout_payload, &rtp_hdr, &sender, &room, stream_kind, is_detail).await;
    }
    TrackType::Pending => unreachable!(), // [4]에서 이미 return
}
```

### 신규 함수 3개

**fanout_half_duplex** (현재 prepare_fanout_payload Half 경로 + normal for문 Half 분기):
- floor gating
- PttRewriter (audio/video)
- PLI Governor keyframe 감지 (Half video도 non-sim이므로 필요)
- normal for문 fan-out (Gate 체크 없음, PT rewrite 있음)

**fanout_full_nonsim** (현재 prepare_fanout_payload Full 경로 + normal for문 Full 분기):
- passthrough payload
- normal for문 fan-out (SubscriberGate 체크)

**fanout_simulcast_video** (기존 함수, 변경 없음):
- SimulcastRewriter + 레이어 선택

---

## 7. 공통 영역에서 불가피한 분기 2곳

| 지점 | 조건 | 이유 |
|------|------|------|
| Active Speaker | Audio && !HalfNonSim | Half audio는 floor controller가 화자 관리 |
| PLI Governor | Video && 각 fanout 함수 내부 | sim은 fanout_simulcast_video 내부, non-sim은 fanout 함수 내부 |

PLI Governor는 fanout 함수 내부로 이동하므로 공통 영역에서는 **Active Speaker 1곳만** 분기 잔류.

---

## 8. 영향 범위 + 수정 파일

| 파일 | 변경 |
|------|------|
| `room/participant.rs` | `TrackType` enum 추가 + `derive_track_type()` 헬퍼 |
| `room/stream_map.rs` | `RtpStream.track_type` 필드 추가, `RtpStream.duplex` 제거 검토 |
| `transport/udp/ingress.rs` | `resolve_stream_kind` → `resolve_track_type` rename + MISS 경로 TrackType 파생 + handle_srtp 분기 + fanout_half_duplex/fanout_full_nonsim 신규 함수 |
| `signaling/handler/track_ops.rs` | `register_nonsim_tracks`에서 stream.track_type 설정 |
| `signaling/handler/helpers.rs` | `collect_subscribe_tracks` — track_type 기반 필터 (기존 t.duplex 유지 가능) |

**변경 없는 파일**: client.js, media-session.js, 나머지 서버 파일

---

## 9. Pending 처리 전략

intent 미도착 시 RTP 패킷 → `TrackType::Pending`:
- `handle_srtp`에서 **early return** (패킷 드롭)
- stream_map에 `Unknown + Pending`으로 등록
- intent 도착 후 다음 RTP → PROMOTED 경로 → TrackType 확정
- `register_nonsim_tracks`가 먼저 도착하면 → 사전등록으로 HIT → Pending 안 됨

기존 Unknown 동작과 동일. 추가 pending queue 불필요.

---

## 10. 검증 시나리오

| 시나리오 | 검증 포인트 |
|----------|-----------|
| Conference (audio+video non-sim) | FullNonSim 경로, Gate 동작 |
| Conference (video sim) | FullSim 경로, SimulcastRewriter, 레이어 전환 |
| PTT audio only | HalfNonSim 경로, floor gating, audio rewriter |
| PTT audio + 동적 video 추가 | **핵심 버그**: HalfNonSim 경로, video rewriter |
| Dispatch (Full talker + Half bodycam) | 같은 방에서 FullSim + HalfNonSim 공존 |
| Screen share (Full non-sim) | FullNonSim, source="screen" |
| RTP 레이스 (RTP before PUBLISH_TRACKS) | Pending → PROMOTED → TrackType 확정 |
| ROOM_SYNC incremental | collect_subscribe_tracks 정합성 |

---

## 11. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| stream_map.duplex 핀포인트 수정만 | 근본 해결 안 됨. notify_new_stream에서 또 틀릴 수 있음. 분석도 어려움 |
| prepare_fanout_payload에 TrackType 전달 | 공통 함수에 분기 추가 = 기존 구조 유지. fan-out 분배까지 여전히 if/else 산재 |
| RtpStream.duplex 유지 + track_type 병행 | 두 필드 간 불일치 위험. 단일 진실 원칙 위배 |

---

*author: kodeholic (powered by Claude)*
