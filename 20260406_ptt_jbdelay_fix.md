# 2026-04-06: PTT jb_delay 폭증 근본 수정 — 이중 silence flush 방지

## 요약

full→half 전환 후 PTT 첫 발화 시 jb_delay 1600ms+ 폭증 원인 분석 및 수정 완료. 근본 원인: `clear_speaker()` 이중 호출로 인한 silence flush 이중 생성. 수정 1줄(가드 추가).

## 수정 파일

### 서버 (oxlens-sfu-server)
| 파일 | 변경 |
|------|------|
| `room/ptt_rewriter.rs` | `clear_speaker()` 상단에 `speaker.is_none()` 가드 추가 — 이중 silence flush 방지 |

## 근본 원인 분석

### 버그 재현 타임라인 (서버 로그 실증)

```
21:53:25  FLOOR granted → switch_speaker → first_pkt (arrival_gap=0ms, 정상)
21:53:28  FLOOR released → silence flush #1 (last_seq=199, last_ts=191040)
          speaker=None, last_relay_at=28.959

21:53:30  SWITCH_DUPLEX half→full
          → floor.release() → flush_ptt_silence() → clear_speaker() 재호출
          → speaker 이미 None인데 silence flush #2 생성 (last_seq=202, last_ts=193920)
          → last_relay_at=30.719

21:53:35  SWITCH_DUPLEX full→half (PttRewriter 무터치)

21:53:37  FLOOR granted → first_pkt arrival_gap=6982ms → ts_gap=335136
```

### NetEQ가 jb_delay를 폭증시킨 메커니즘

subscriber 입장:
- silence flush #1 수신: ts=191040, arrival=28.959s
- silence flush #2 수신: ts=192000 (+=960, 즉 20ms 뒤), arrival=30.719s (1.76초 뒤)
- **ts_gap=20ms, arrival_gap=1760ms**
- NetEQ 해석: "이 패킷이 1740ms 늦게 도착했다" → jitter buffer를 ~1740ms로 확장
- 스냅샷 실측: jb_delay=1634ms ≈ 1740ms − 회복분. **정확히 일치**

### 왜 이중 호출이 발생했는가

1. PTT 발화 종료 → `floor.release()` → `flush_ptt_silence()` → `clear_speaker()` #1 (정상)
2. SWITCH_DUPLEX half→full → `floor.release()` → FloorAction::Released 매칭 → `flush_ptt_silence()` → `clear_speaker()` #2
3. `clear_speaker()`는 speaker=None 체크 없이 `last_virtual_seq/ts != 0`이면 무조건 silence 생성

## 수정 내용

```rust
pub fn clear_speaker(&self) -> Option<Vec<Vec<u8>>> {
    let mut s = self.state.lock().unwrap();

    // 이미 speaker가 없으면 silence flush 생성 금지
    // 이중 clear_speaker 방지: floor.release() 후 SWITCH_DUPLEX에서 또 호출 시
    // ts_gap(20ms) << arrival_gap(수초) → NetEQ가 jitter로 오인 → jb_delay 폭증
    if s.speaker.is_none() {
        return None;
    }

    s.speaker = None;
    // ... 이하 동일
```

## 검증 결과

수정 빌드 후 동일 시나리오(dispatch → half→full→half → PTT 발화) 재현: **jb_delay 정상 복귀 확인**.

## 기각된 접근 (이전 세션에서)

### reset_relay_timing() — 기각 유지
- full→half 전환 시 last_relay_at을 now로 리셋하는 방식
- 이중 flush가 근본 원인이었으므로 불필요. 이중 flush 방지로 충분

## 지침 후보

- **clear_speaker()는 멱등해야 한다**: speaker=None이면 early return. silence flush 이중 생성은 ts_gap << arrival_gap → NetEQ jitter buffer 확장 → jb_delay 폭증의 직접 원인
- **silence flush ts 연속성 원칙**: silence flush의 ts는 이전 패킷에서 +960씩 연속. 시간 간격 두고 이중 생성하면 ts_gap(20ms) vs arrival_gap(수초) 불일치 발생

## audio pt=0, codec=VP8 스냅샷 버그 수정

### 증상
```
[TRACKS:U329] audio(ssrc=345116802,pt=0,codec=VP8,duplex=half)
```
audio 트랙인데 pt=0, codec=VP8 표시 → 진단 오염.

### 원인
1. `track_ops.rs`: `actual_pt`를 audio일 때 `0`으로 하드코딩
2. `track_ops.rs`: `VideoCodec::from_str_or_default(None)` → VP8 기본값이 audio에도 적용
3. `admin.rs`: 모든 트랙에 `video_codec` 무조건 출력

### 수정
| 파일 | 변경 |
|------|------|
| `track_ops.rs` | audio `actual_pt = 111` (Opus PT, 기존 0) |
| `admin.rs` | video만 `video_codec` 출력, audio는 `"codec":"opus"` |
| `snapshot.js` | `t.video_codec \|\| t.codec \|\| "?"` fallback |

### 수정 후 스냅샷 확인
```
[TRACKS:U421] audio(ssrc=379406334,pt=111,codec=opus,duplex=full)
[TRACKS:U137] audio(ssrc=2577329530,pt=111,codec=opus,duplex=half) video(ssrc=3996377572,pt=109,codec=H264,duplex=full,src=camera)
```

## 커밋 메시지

### oxlens-sfu-server
```
fix(ptt): prevent double silence flush — root cause of jb_delay spike

clear_speaker() now returns None if speaker is already None.
Previously, SWITCH_DUPLEX half→full called flush_ptt_silence() after
floor.release(), triggering a second silence flush with ts_gap=20ms
but arrival_gap=seconds → NetEQ interpreted as massive jitter →
jb_delay spiked to 1600ms+.

Also fix audio track snapshot: pt=111(opus) instead of 0,
codec=opus instead of VP8. admin.rs outputs codec field
conditionally by track kind.
```

### oxlens-home
```
fix(admin): snapshot audio codec display — opus instead of VP8

snapshot.js: fallback t.video_codec || t.codec || "?"
for correct display after server-side admin.rs field split.
```

---

*author: kodeholic (powered by Claude)*
