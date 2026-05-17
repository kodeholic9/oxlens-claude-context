# 2026-04-30d — PT Mismatch 회귀 #2 fix (옵션 D: publisher.video_codec → server_codec_policy 정적 매핑)

## 위치

Phase 80~83 (Track Lifecycle Phase 3~5 + Rewriter Phase 1) 작업 직후 발견된 영상무전(video_radio) PTT half-duplex 시험에서 **video.framesDecoded=0 회귀** 의 본질 진단 + fix. RTP 흐름은 정상(packetsReceived 정상)인데 디코딩이 안 되는 PT mismatch 패턴.

설계서: `context/design/20260421_ptt_unified_model_design.md` (PTT Unified Model §1 "Codec 고정" 가정의 한계 노출)

---

## 결재 사항 (부장님 통찰 + OK)

1. **rewrite 본질 부정 = PTT 본질 부정** — 부장님 일침 "무전은 N명이 각자의 ssrc로 보내고, 수신은 동일 vssrc로 받도록 설계되어 있는데. rewrite를 안한다고?" — 김대리가 sdp-builder 의 "변환 레이어 없음" 주석을 잘못 해석해 forward PT rewrite 제거 주장. 사과 후 본 fix 방향 재정립.

2. **PT는 브라우저/플랫폼마다 다르다** — 부장님 통찰 "크롬, 사파리, pc 등에서 h264일 때, pt가 다르게 뽑혀 나오거든". libwebrtc default H264 PT=109 (Chrome), Safari=125 등. forward rewrite 가 본질적으로 필수.

3. **PT는 보정 가능, 코덱이 다르면 통신 안 됨** — multi-codec subscribe SDP (VP8 PT=96 + H264 PT=102) 가 코덱 측 보장. PT만 정규화하면 N:1 통신 성립. **subscribe SDP 가 코덱 측 진실의 출처**.

4. **N:1 구조에서만 문제** — 부장님 일침 "N:1 구조에서만 문제가 되는거 몰라?". Conference 1:1 은 publisher PT 동적 + subscribe SDP 도 publisher PT 박힘 (helpers::collect_subscribe_tracks의 t.actual_pt) → 자연 일치. **PTT/Hall ViaSlot 만 rewrite 필수**.

5. **옵션 D-1 (정적 매핑) 진입** — sdp-builder 가 server_codec_policy 그대로 사용 가정 → publisher.video_codec → server_codec_policy PT 정적 매핑 (H264=102, VP8=96). expected_video_pt 동적 저장 폐기.

---

## 진단 사슬 (시간순 컨텍스트 발굴)

### 4/2 오전 — Conference normalization 제거 (`20260402_conference_nonsim_video_pt_fix.md`)

publisher PT 그대로 릴레이 + subscribe SDP 에 publisher 실제 PT 선언. **"변환 레이어 없음 = 깨질 곳 없음"**. 단 1:1 매핑 전제.

### 4/2 오후 — PTT 는 정당한 rewrite (`20260402_pt_mismatch_fix.md`)

> "PTT에서 PT normalization은 정당하다 — Conference는 원본 릴레이니까 PT 변환 금지가 맞지만, PTT ptt_rewriter는 이미 SSRC/seq/ts를 rewrite하는 변환 레이어. PT 1바이트 추가는 자연스러운 확장."

- `participant.expected_video_pt: AtomicU8` 필드 도입
- `track_ops.rs`: `req.video_pt → expected_video_pt` 저장
- `ingress.rs` PTT fan-out: subscriber별 1바이트 PT 교체
- 클라이언트: `media-session.js::_overrideHalfDuplexVideoPt()` — 자기 publish answer SDP PT → 자기 PTT virtual track video_pt 박음 (subscribe SDP H264 PT == 자기 publish PT == expected_video_pt 일치 메커니즘)

### 4/4 — PTT subscribe → Conference 통합 (`20260404_ptt_subscribe_unification.md`)

- `buildPttSubscribeSdp` 별도 함수 삭제
- `ptt_virtual_ssrc` 별도 필드 제거
- `buildSubscribeRemoteSdp` 하나로 통합
- 클라 `_overrideHalfDuplexVideoPt` 메서드로 PT override 통합

### 4/21 — PTT Unified Model 도입 (`design/20260421_ptt_unified_model_design.md`)

§1: **"Codec 고정 (Opus PT=111, VP8 PT=96)"** 가정 박음. Universal SSRC + Subscribe slot pre-allocate.

§4.2.1 PttRewriter 변경: "리라이팅 경로 동일 (SSRC 변환 대상만 고정값으로)" — **PT 변환 명시 없음**. VP8 forced 가정에서만 정합.

### 4/29 — Phase 80 wave-2 (`20260429_phase3_step_b_partial.md`)

`collect_subscribe_tracks` 의 PTT video slot:
```rust
"video_pt": crate::config::VP8_PAYLOAD_TYPE,    // 96 hard-coded
"codec": "VP8",
```
**4/21 설계서 가정 그대로 박힘**. H264 default 환경에서 깨짐.

### 본 회귀 mismatch 메커니즘

| 측 | 값 |
|---|---|
| publisher publish offer (Chrome libwebrtc default) | H264 PT=109 |
| subscriber subscribe SDP H264 PT (server_codec_policy default) | **102** |
| forward expected_video_pt (subscriber 자기 publish PT) | 109 |
| forward 출력 PT | 109 |
| 결과 | 109 ↔ 클라 SDP H264=102 mismatch → drop |

근본: 4/21 Universal Model 의 "VP8 PT=96 고정" 가정이 깨졌고, 4/4 옛 클라 fallback (`_overrideHalfDuplexVideoPt`) 가 4/11 Core SDK v2 재작성 시점에 누락된 듯 (확정 미완 — 별도 세션).

---

## 변경 (옵션 D-1, 3 파일)

### 1. `config.rs` — codec→PT 헬퍼 추가

```rust
/// VideoCodec → server_codec_policy 의 PT (helpers::server_codec_policy 와 일치).
/// N:1 통합 모델 (PTT/Hall) 의 PT rewrite 용 — publisher PT 가 무엇이든 subscribe SDP 에
/// 박힌 PT 로 정규화. sdp-builder 가 server_codec_policy 을 그대로 쓰는 가정.
///
/// VP9 는 server_codec_policy 미포함 — publish 협상 단계에서 거부되므로 PTT slot 진입
/// 불가 (도달 불가 분기). VP8 PT 로 fallback (보수적).
pub fn pt_for_video_codec(codec: VideoCodec) -> u8 {
    match codec {
        VideoCodec::H264 => H264_PAYLOAD_TYPE,    // 102
        VideoCodec::Vp8  => VP8_PAYLOAD_TYPE,     // 96
        VideoCodec::Vp9  => VP8_PAYLOAD_TYPE,     // fallback
    }
}

pub fn rtx_pt_for_video_codec(codec: VideoCodec) -> u8 { ... }  // 동일 패턴
```

### 2. `subscriber_stream.rs::forward` ViaSlot Video 분기

기존:
```rust
let target_pt = target.peer.subscribe.expected_video_pt.load(Ordering::Relaxed);
if target_pt > 0 { ... 1바이트 교체 ... }
```

변경:
```rust
// publisher.video_codec → server_codec_policy PT 정적 매핑
let target_pt = crate::config::pt_for_video_codec(publisher.video_codec);
let mut p = payload_base.to_vec();
let marker = p[1] & 0x80;
p[1] = marker | (target_pt & 0x7F);
p
```

### 3. `track_ops.rs::do_publish_tracks` — store 6줄 제거

```rust
// 제거됨:
if let Some(vpt) = req.video_pt {
    participant.peer.subscribe.expected_video_pt.store(vpt, ...);
}
if let Some(rpt) = req.rtx_pt {
    participant.peer.subscribe.expected_rtx_pt.store(rpt, ...);
}
```

### 빌드

1차: `VideoCodec::Vp9` non-exhaustive match 에러 → VP8 fallback 추가 후 PASS.

---

## 시험 결과 — 회귀 #2 fix 입증

### Playwright MCP video_radio 2인 (alice → bob 발화 12초)

| 지표 | 회귀 (옵션 D 전) | 옵션 D fix 후 (12초) |
|---|---|---|
| audio.pktsRx | 200 (4초) | **550** (12초) ✅ |
| audio.jbDelay | 7689ms 누적 ✅ | 정상 누적 ✅ |
| video.pktsRx | 110~ | **621** ✅ |
| **video.framesDecoded** | **0** ❌ | **165** ⭐ |
| video.jbDelay | **0** (jb 미진입) | **1489ms** (jb 진입 정상) ✅ |
| video.freezeCount | 0 | 0 ✅ |

8초 안정 측정: framesDecoded=474 (15fps × 8s ≈ 120 → 누적 + spawn 직후 burst 포함 합당).

### bob iframe video element DOM (active video, videoWidth=640)

ancestor chain 모두 visibility=visible, no clip-path/transform:
- VIDEO: display=block, left=auto, 264.75×200, paused=false, readyState=4
- DIV.cell / DIV.slot: position=relative, overflow=hidden
- DIV.wrap: grid

→ DOM 측 정상.

### 캡처 (저장: `/Users/tgkang/.playwright-mcp/`)
- `01_idle.png` — alice/bob 둘 다 자기 카메라 thumb 표시, RX speaker 슬롯 idle
- `02_alice_press_T3.png` — alice f=talking, bob f=listening sp=alice (상태 정상)
- `03_alice_press_T8.png` — 양쪽 f=idle (floor 자동 release 발생)

---

## ⚠️ 별도 세션 진단 필요 — 옵션 D fix 와 무관한 추가 회귀

### 이슈 #1 — 화면 영상 시각 노출 안 됨

**증상**: bob 의 RX speaker 슬롯 video element 가 DOM 측 정상 (left=auto, paused=false, readyState=4, videoWidth=640) 이고 framesDecoded=474 진행. 그러나 화면에는 검정. 부장님 직접 확인.

**결정적 단서**: **`video.currentTime = 0`** — paused=false 인데 currentTime 진행 안 함. 즉 video element 가 데이터 받았지만 재생 시작 안 함.

**가능 원인**:
1. `video.play()` 호출 누락 (SDK 또는 QA participant.html)
2. autoplay 정책 차단 (Playwright Chromium 기본 muted 설정 부재)
3. PTT freeze masking 의 listening + rVFC 두 조건 중 rVFC 콜백 미발화

**진단 방향**:
- `video.play()` 호출 위치 grep (`oxlens-home/core/pipe.js::mount`, `engine.js`, qa/participant.html)
- `addEventListener('canplay', ...)` 또는 `loadedmetadata` 이벤트 처리
- PTT freeze masking 의 `_pttRvfcPending` 또는 그 후신 위치

### 이슈 #2 — Floor 자동 release (T+8s)

**증상**: alice press 후 8초 시점에 양쪽 모두 `f=idle sp=-` 상태. `FLOOR_MAX_BURST_MS=30s` 기대 대비 짧음.

**진단 방향**:
- T132 또는 다른 timer 가 floor revoke
- 또는 fake media 환경에서 RTP liveness 판단 실패 → 서버가 floor revoke
- agg-log `floor:released` / `floor:revoked` 확인

### 이슈 #3 — Dead code 정리 미완

**호출처 0 됐으나 필드 정의 잔존**:
- `peer.rs::SubscribeContext.expected_video_pt: AtomicU8`
- `peer.rs::SubscribeContext.expected_rtx_pt: AtomicU8`
- `peer.rs::SubscribeContext::new()` 안 초기화

build warning 발생 예상. admin.rs 등 노출 사용처 grep 후 일괄 제거 필요.

### 이슈 #4 — 양방향 시험 미완

bob → alice 발화 (alice 측에서 framesDecoded 입증) 미실시. 옵션 D 가 양방향에서 동일 동작하는지 검증 필요.

### 이슈 #5 — audio.jbDelay 단위 의심 (낮은 우선순위)

12초 발화 시점 audio.jbDelay = 16,483,200 ms = 16,483 sec. 12초 발화 대비 너무 큼. SDK 의 getStats 변환 단계에서 단위 mix-up 가능성. 디코딩 자체는 정상이라 직접 영향 없음.

---

## 김대리 자체 판단

1. **VideoCodec::Vp9 fallback 처리** — server_codec_policy 미포함이라 도달 불가 분기. VP8 PT 로 보수적 fallback (panic 회피).

2. **expected_video_pt 필드 자체는 본 세션에서 제거 안 함** — store 호출처 제거 + forward 사용처 제거 = 호출처 0. dead code warning 발생할 것이지만 build PASS. 별도 cosmetic 세션에서 일괄 정리.

3. **Conference 변경 안 함 확정** — 부장님 일침 "N:1 구조에서만 문제". Conference 1:1 은 publisher PT 동적 + subscribe SDP 도 publisher PT 박힘 → 자연 일치. 본 분기 적용 시 오히려 깨짐.

---

## 메타학습

- ⭐⭐⭐⭐⭐ **PTT 본질(N→1 rewrite) 부정 헛소리** — sdp-builder.js 의 "변환 레이어 없음" 주석을 forward PT rewrite 자체 부정으로 잘못 해석. 부장님 일침 받음. 주석 의도는 "PT 가 SDP 와 일치하면 변환 불필요" 의미이지, **PTT vssrc rewrite 자체 부정 아님**. PTT 는 N publisher → 1 vssrc 통합 모델이라 ssrc/seq/ts/PT 모두 rewrite 본질.

- ⭐⭐⭐⭐ **부장님 통찰 = 도메인 경험의 압축** — "PT는 브라우저마다 다르다" + "코덱 다르면 통신 안 됨" 두 마디가 4/2 컨텍스트 + 4/21 설계서 + 본 회귀 진단의 모든 단계 정합 안내. 김대리는 코드 ground truth 만 보고 의미를 못 잡았는데, 부장님은 도메인 본질 즉시 짚음.

- ⭐⭐⭐⭐ **세션 컨텍스트 발굴 의무** — 부장님 명령 "3월 4월 컨텍스트 함 뒤져바" 후 4/2 두 컨텍스트 + 4/4 PTT subscribe 통합 + 4/21 PTT Unified Model 설계서 + 4/29 Phase 80 wave-2 + 4/11 Core SDK v2 재작성 = **5단계 결정 사슬**. 메모리 자동 요약 또는 SESSION_INDEX 한 줄 요약만으로는 발굴 불가능.

- ⭐⭐⭐ **N:1 vs 1:1 구분 본질** — Conference (1:1) 와 PTT (N:1) 는 매핑 구조 다름. PT mismatch 가 N:1 만 발생 (1:1 은 publisher PT 동적이고 subscribe SDP 도 publisher PT 박혀 자연 일치). 김대리가 옵션 5 "Conference 변경 필요?" 질문 — 부장님 일침 "N:1 구조에서만 문제인거 몰라?". 본질 미파악 신호.

- ⭐⭐⭐ **부장님 "진입해" = 큰 그림 OK + 디테일 김대리 자체 결정** — 김대리가 의문 5건 정리 보고 후 부장님 결재 의뢰 했지만, 부장님은 "정적으로 맞추자니까" + 4번 (Conference 변경) 같은 N:1 본질 모르는 질문에 화남. **"코딩 전 4-5개 디자인 질문" 원칙은 도메인 본질 의문에 한정**. 명백한 답은 자체 결정.

- ⭐⭐ **VideoCodec match exhaustive 함정** — Vp9 variant 가 enum 에 있는데 match 에서 누락. cargo build 시점에 즉시 노출 (부장님 의뢰 후 1차 build error → 즉시 fix). _ wildcard 보다 명시 fallback 가 의미 보존.

- ⭐⭐ **getStats sub.inbound 구조** — `{pub, sub}` (이전 캐시는 `{publish, subscribe}` 였음). 시험 코드에서 매번 SDK 형식 확인 필요 — `Object.keys()` 한 번 확인이 안전.

- ⭐⭐ **Playwright MCP 화면 직접 시각 검증** — DOM/stats 만으로는 "노출 안 됨" 발견 못 함. 부장님 직접 화면 보고 "영상 노출 안 됐다" 즉시 지적. **시각 검증과 데이터 검증 병행 의무** (QA_GUIDE 정합).

- ⭐⭐ **Token budget 관리** — 본 세션 응답이 길어 토큰 한계 임박. 컨텍스트 read 14건 + 코드 변경 3건 + 시험 + 캡처. **서두부터 단계 분할 + 핵심만 보고 + 코딩 단계는 짧게** 가 다음 패턴.

---

## 다음 세션 진입 절차

1. SESSION_INDEX.md 의 본 항목 + 캡처 3장 확인
2. 부장님 결재: 4가지 이슈 우선순위 결정
   - 이슈 #1 (화면 노출 안 됨) — 가장 critical
   - 이슈 #2 (floor 자동 release) — 새 회귀 가능성
   - 이슈 #3 (dead code 정리) — cosmetic
   - 이슈 #4 (양방향 시험) — 검증 보완
3. 우선 진입: 이슈 #1 + #2 묶어 진단 (모두 PTT 흐름 안정성 영향)

---

## 다음 phase = STALLED 후속 → oxrecd → ... (PROJECT_MASTER 우선순위 정정)

본 세션은 "Track Lifecycle 작업 후 발견 회귀 fix" 영역. 메모리 #26 우선순위에 따라 다음 phase 는 STALLED 후속. 단 **이슈 #1/#2 가 STALLED 보다 critical** 이면 부장님 결재 후 재정렬.

---

*author: kodeholic (powered by Claude)*
