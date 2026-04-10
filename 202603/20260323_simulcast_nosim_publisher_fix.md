# 세션 컨텍스트: Simulcast 방 non-simulcast publisher 영상 릴레이 실패 수정

> 날짜: 2026-03-23
> 서버 버전: v0.6.6
> 관련 파일: `ingress.rs`, `track_ops.rs`

---

## 발견된 문제 2가지

### 문제 1 (서버 버그 — 이번 세션에서 수정 중)
**Simulcast 방에서 rid 없는 publisher(iPhone Safari 등)의 video가 릴레이되지 않음**

- U128(iPhone)이 simulcast 방에 입장 → `PUBLISH_TRACKS count=2 simulcast=true` (audio + video 1개, rid 없음)
- 다른 3명은 `count=3` (audio + video h + video l)
- `fanout_simulcast_video()` 진입 시 `sender_rid == None → return` → **U128 video 블랙홀**
- 결과: 4명 Conference에서 U128 영상을 아무도 못 봄

**근본 원인**: `ingress.rs:448-451`에서 `sender_rid`가 None이면 즉시 return. simulcast 방이지만 simulcast를 지원하지 않는 기기(rid 없는 단일 video)를 고려하지 않았음.

### 문제 2 (클라이언트 한계 — 향후 과제)
**안드로이드 HW 디코더가 H264 멀티스트림 동시 디코딩 실패**

- U175(Qualcomm OMX.qcom.video.encoder.avc) — Conference 방에서 3 video 수신 중 1개만 디코딩, 나머지 decoder_stall
- 비결정적으로 살아남는 트랙이 순환함 (스냅샷 1: U545 생존, 스냅샷 2: U128 생존)
- Simulcast 방에서도 2 video 중 1개 stall (U148 항상 실패 — 높은 jitter/RTT 관련 가능성)
- 대응: Adaptive Quality Phase A 필요 (서버 측 자동 layer 하향, decoder_stall 감지 → low layer 전환)

---

## 문제 1 수정 내역

### 수정 전략
`sender_rid == None`인 publisher의 video를 `"h"` (high) 레이어로 간주.
- SimulcastRewriter가 SSRC/seq/ts를 가상 값으로 rewrite → subscriber SDP 매칭 보장
- rid 기반 트랙 lookup에는 `or_else(|| rid.is_none() video fallback)` 추가

### 수정 완료 (4곳)

#### 1. `ingress.rs` — fanout_simulcast_video sender_rid fallback
```rust
// 수정 전 (448-451)
let sender_rid = match sender_rid {
    Some(r) => r,
    None => return, // simulcast track이 아님
};

// 수정 후
let sender_rid = sender_rid.unwrap_or_else(|| "h".to_string());
```

#### 2. `ingress.rs` — PLI h_ssrc lookup fallback (498)
```rust
// rid 없는 publisher fallback 추가
.find(|t| t.kind == TrackKind::Video && t.rid.as_deref() == Some("h"))
.or_else(|| {
    tracks.iter().find(|t| t.kind == TrackKind::Video && t.rid.is_none())
})
```

#### 3. `ingress.rs` — subscriber RTCP 역매핑 fallback (903)
```rust
// 동일 or_else 패턴 추가
```

#### 4. `ingress.rs` — NACK 역매핑 fallback (1084)
```rust
// 동일 or_else 패턴 추가
```

### 미완료 (1곳)

#### 5. `track_ops.rs:378` — SUBSCRIBE_LAYER PLI lookup
```rust
// 현재 코드
.find(|t| t.kind == TrackKind::Video && t.rid.as_deref() == Some(&target.rid))

// 필요한 수정: 동일 or_else fallback 추가
```
long-press popup으로 layer 선택 시 rid 없는 publisher에게 PLI를 못 보내는 문제.
실질적 영향: rid 없는 publisher는 single layer라서 layer 선택 자체가 무의미하지만,
PLI 실패 시 키프레임 미수신 가능성.

---

## 검증 필요 사항

### 빌드 후 테스트 시나리오
1. Simulcast 방: U128(iPhone, rid 없음) + U545(Mac) + U175(Android) 3인
   - 모든 참여자가 U128 영상을 정상 수신하는지
   - U128이 다른 참여자 영상을 정상 수신하는지
2. Conference(일반) 방: 기존 동작 변경 없는지
   - `room.simulcast_enabled == false`이면 `fanout_simulcast_video` 자체를 타지 않으므로 영향 없음
3. PTT 방: 기존 동작 변경 없는지

### 추가 확인 포인트
- U128의 가상 SSRC가 정상 생성되는지 (`ensure_simulcast_video_ssrc`)
- TRACKS_UPDATE broadcast에서 U128 트랙이 다른 참여자에게 통보되는지
  - `broadcast_tracks` 필터: `rid != Some("l")` → rid=None은 통과 → 문제 없음
- SR Translation: rid 없는 publisher의 SR이 정상 릴레이되는지
  - `ingress.rs:1367-1370`: `tracks.iter().any(|t| t.ssrc == pub_ssrc && t.kind == TrackKind::Video)` → rid 무관 → 문제 없음

---

## 버전/CHANGELOG

수정 완료 후 v0.6.7로 bump 예정:
- `[FIX] Simulcast: non-simulcast publisher (no rid) video relay — treated as "h" layer fallback`
- `[FIX] Simulcast: PLI/NACK/RTCP reverse mapping fallback for rid-less video tracks`

---

## 문제 2 관련 메모 (향후 참조)

### 텔레메트리 증거 (Conference 방 4인, H264 1.5Mbps×3)
- U175 subscribe video: 3개 중 1개만 decoded_delta>0, 나머지 decoder_stall + frames_dropped_burst
- 살아남는 트랙이 비결정적으로 순환 (스냅샷마다 다름)
- U175 디코더: `ExternalDecoder (MediaCodecVideoDecoder)` — Qualcomm HW
- U175 pub 인코더: `NdkVideoEncodeAccelerator(OMX.qcom.video.encoder.avc)` — 인코딩에도 HW 사용 중
- 인코딩 1개 + 디코딩 3개 = HW 코덱 인스턴스 4개 동시 사용 → 고갈

### U148 특이점 (3회 스냅샷 연속 stall 대상)
- RTT 52~79ms (다른 기기 2~6ms 대비 10배+)
- audio_gap 매 3초 40~50ms × 10~20회 (Exynos h264 인코더 jitter)
- huge=174 (누적, 비정상적으로 높음)
- 수신 측 jb_delay 156~315ms

### 대응 방향
- 단기: Simulcast low layer 강제 (해상도 낮추면 디코더 부하 감소)
- 중기: decoder_stall 텔레메트리 감지 → 서버 자동 layer 하향 (Adaptive Quality Phase A)
- QUALITY_ASSESSMENT.md의 Adaptive Quality 15/100 → Phase A 완료 시 70 예상

---

*author: kodeholic (powered by Claude)*
