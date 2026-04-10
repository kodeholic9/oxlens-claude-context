# 세션: ingress TrackType 기반 경로 분리 설계 + 초반 구현

- **날짜**: 2026-04-04 (심야)
- **버전**: v0.6.16-dev
- **영역**: 서버 ingress 리팩터링 (설계 + 초반 구현, 빌드 성공)
- **이전 세션**: `20260404_scenario_demo_video_toggle.md`

---

## 1. 세션 목표

동적 추가된 half-duplex video가 상대에게 안 보이는 버그의 근본 원인 분석 + 구조적 수정 설계 + 초반 구현.

---

## 2. 근본 원인 분석

### 버그 발현 경로

1. radio 시나리오에서 `addVideoTrack("camera", { duplex: "half" })` 호출
2. `resolve_stream_kind` MISS 경로에서 `RtpStream::new()` → `duplex: Full` 하드코딩
3. `register_and_notify_stream` → intent에서 `duplex=Half` 파생 → participant.tracks에는 정확
4. **stream_map.RtpStream.duplex 미갱신 → Full 그대로**
5. `notify_new_stream` → `stream.duplex=Full` 읽음 → TRACKS_UPDATE에 `duplex:"full"` 전파
6. subscriber가 Conference video로 인식 → 원본 SSRC 기대
7. 서버 fan-out은 PttRewriter → virtual SSRC 송출 → **SSRC 불일치 → video 안 보임**

### 연쇄 오류 범위

TRACKS_UPDATE 잘못된 duplex → SubscriberGate 꼬임 → subscribe SDP 불일치 → ROOM_SYNC 불일치

---

## 3. 설계 결정

### TrackType enum 도입 + 입구에서 확정 + 경로별 분리

상세 설계서: `context/design/20260404_ingress_track_type_refactor.md`

```rust
pub enum TrackType {
    FullNonSim,   // Conference audio/video, screen
    FullSim,      // Simulcast video
    HalfNonSim,   // PTT audio/video
    Pending,      // intent 미도착
}
```

handle_srtp 구조:
```
공통: decrypt → parse → resolve_track_type → register → stats → active_speaker → gap
분기: match track_type { HalfNonSim → ..., FullSim → ..., FullNonSim → ... }
```

---

## 4. 구현 완료 (빌드 성공)

### 수정 파일 4개

| 파일 | 변경 |
|------|------|
| `participant.rs` | `TrackType` enum + `derive()` + `is_half()/is_sim()/to_duplex()` 헬퍼 |
| `stream_map.rs` | `RtpStream.track_type` 필드 추가 (default=Pending), import |
| `ingress.rs` | resolve_stream_kind 전경로 TrackType 파생 + register_and_notify_stream stream_map 보정 + notify_new_stream track_type 기반 분기 + handle_srtp bridge 변수 |
| `track_ops.rs` | `register_nonsim_tracks`에서 `stream.track_type = TrackType::derive(duplex, false)`, import |

### resolve_stream_kind 변경 내역

| 경로 | 변경 전 | 변경 후 |
|------|--------|--------|
| HIT | `stream.duplex` | `stream.track_type` |
| PROMOTED → audio | `Full` 하드코딩 | `TrackType::derive(intent.audio_duplex, false)` + stream 설정 |
| PROMOTED → video | `Full` 하드코딩 | `TrackType::derive(vs.duplex, vs.simulcast)` + stream 설정 |
| MISS Opus audio | `Full` 하드코딩 | `TrackType::derive(intent.audio_duplex, false)` + stream 설정 |
| MISS rid (sim) | `Full` 하드코딩 | `TrackType::FullSim` + stream 설정 |
| MISS MID → audio | `Full` 하드코딩 | `TrackType::derive(intent.audio_duplex, false)` + stream 설정 |
| MISS MID → video | `Full` 하드코딩 | `TrackType::derive(vs.duplex, vs.simulcast)` + stream 설정 |
| RTX 전체 | `Full` 하드코딩 | `TrackType::Pending` |
| Unknown | `Full` 하드코딩 | `TrackType::Pending` |

### register_and_notify_stream 추가

```rust
let derived_tt = TrackType::derive(duplex, track_sim);
if let Ok(mut map) = sender.stream_map.lock() {
    if let Some(s) = map.get_mut(rtp_hdr.ssrc) {
        if s.track_type != derived_tt {
            s.track_type = derived_tt;
            s.duplex = duplex;
        }
    }
}
```

### notify_new_stream 변경

- `stream.duplex` → `stream.track_type` 읽기
- TRACKS_UPDATE duplex 필드: `track_type.to_duplex().to_string()`
- SubscriberGate: `!track_type.is_half()` 조건

### Bridge 변수 (다음 세션에서 제거)

```rust
let track_duplex = track_type.to_duplex();
```
handle_srtp 후반 fan-out 코드가 아직 `track_duplex` 참조 → match 분리 시 제거.

---

## 5. 빌드 에러 수정 이력

| 에러 | 원인 | 수정 |
|------|------|------|
| `no method to_duplex on DuplexMode` ×3 | Python 스크립트에서 `stream.duplex` → `stream.track_type` 치환 실패 (notify_new_stream 1곳) | `stream.duplex` → `stream.track_type` 수동 수정 |

---

## 6. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| stream_map.duplex 핀포인트 수정만 | notify_new_stream에서 또 틀릴 수 있음. 분석도 어려움 |
| RtpStream.duplex + track_type 병행 유지 | 두 필드 간 불일치 위험 (단, 현재는 bridge로 병행 중 — 다음 세션에서 정리) |

---

## 7. ingress.rs 리팩터링 후보 (향후)

현재 2211줄. 성격별 분리 후보:
- Subscribe RTCP (~500줄) → 별도 파일
- MBCP Floor (~200줄) → 별도 파일
- handle_srtp fan-out → TrackType match 분리 (다음 세션)
- 프로세스 분리(oxsfud) 때 자연스러운 분리 시점

---

## 8. 다음 세션 작업

- [ ] **동적 video 테스트** — radio 시나리오 영상 토글 → 상대에게 보이는지 확인
- [ ] **handle_srtp 후반 match 분리** — fanout_half_duplex / fanout_full_nonsim 신규 함수
- [ ] **bridge 변수 제거** — `track_duplex` → `track_type` 직접 사용
- [ ] `RtpStream.duplex` 필드 제거 검토 (track_type이 대체)
- [ ] ingress.rs 파일 분리 검토 (subscribe_rtcp, mbcp)
- [ ] 나머지 시나리오 페이지 7종 구현
- [ ] 세션 컨텍스트 / SESSION_INDEX 갱신

---

## 9. 파일 변경 목록

| 파일 | 변경 |
|------|------|
| `src/room/participant.rs` | TrackType enum 추가 (60줄) |
| `src/room/stream_map.rs` | RtpStream.track_type 필드 + import |
| `src/transport/udp/ingress.rs` | resolve_stream_kind 전경로 + register_and_notify_stream + notify_new_stream + bridge |
| `src/signaling/handler/track_ops.rs` | register_nonsim_tracks track_type 설정 + import |
| `context/design/20260404_ingress_track_type_refactor.md` | 상세 설계서 |

---

*author: kodeholic (powered by Claude)*
