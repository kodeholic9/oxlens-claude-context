<!-- author: kodeholic (powered by Claude) -->

# 20260623b — 비디오 cold-start 기만 가설 + 1차 설계 자기반박

> status: **가설 — oxsfud 실코드 대조 완료(2026-06-23b).** webrtc-src(수신측 VCMTiming)만 미검증. 코드 증거 §8. 잔여 추측 §6에 라벨링.
> 선행: [[20260623_ptt_neteq_integration_notes]] (오디오 NetEQ 기만 완성형), [[20260623a_ptt_priming_design]] (오디오 예열 = CN 버스트), [[20260622_ptt_handoff_gap_analysis]] (핸드오프 갭 실측), [[20260621_pli_governor_redesign_knowledge]] (PLI 거번너 재설계).
> 목적: 오디오에서 확립한 "기만" 프레임을 비디오로 확장 시도 → **프레임이 거의 안 맞음을 확인**하고, 1차 설계를 스스로 반박해 살아남는 것만 추린 기록.

---

## 0. 한 줄

**오디오 cold-start는 속여서 없앴고(CN 예열), 비디오 cold-start는 속일 수 없어서 빨리 가져와 줄인다(키프레임 획득).** 둘은 같은 "기만" 문제가 아니다. 비디오 본진은 측정 전엔 알 수 없으며, 1차 설계가 PLI를 본진으로 단정한 것이 핵심 오류였다.

---

## 1. 가설 — 비디오는 기만 축이 하나 더 있고, 그 축은 SFU 단독으로 못 속인다

오디오 기만 3축: 정체성(SSRC) / 연속성(seq) / 시간(ts). 디코더가 속는 건 앞 둘, 못 속이는 건 시간. cold-start = 빈 버퍼 차오름 → SFU가 CN 합성해 선충전(20260623a).

비디오엔 **4번째 축 = 콘텐츠(디코딩 가능성)** 추가. 오디오는 모든 프레임 self-contained(opus 패킷 1개 = 독립 디코딩)라 이 축이 없었다. 비디오는 참조 체인 때문에 "지금 디코딩 시작 가능" 상태를 만들어줘야 함 = 키프레임 가용성.

**결정적 비대칭**:
- 오디오 cold-start 기만(CN 예열)은 **SFU 단독 가능**. CN = `OPUS_SILENCE [0xf8,0xff,0xfe]` 한 줄을 SFU가 찍어냄.
- 비디오 cold-start 기만은 **SFU 단독 불가**. 키프레임 = 해상도·내용 종속 풀 인코딩 이미지 → encoder만 생성. (정정: §6-④ "단독 불가"는 과장. 더미 IDR 부트스트랩 시늉까지는 가능.)

⟹ 비디오 기만은 본질적으로 **SFU + publisher 협동 기만**. 오디오에서 가졌던 SFU 단독 robustness를 잃음.

---

## 2. 기만 무기고 — 누가 할 수 있나로 분류

### A. SFU 단독 (오디오 상속)
- SSRC 가상화 + seq 연속 (화자전환 봉합) — 무손실 상속.
- freeze-last-frame (gap 동안 마지막 프레임 유지 = CN 봉합 등가물) — 대개 수신 클라(VCMTiming)가 알아서. SFU 할 일 거의 없음.
- 키프레임 캐시 forward — **조건부**. GOP 캐시를 브라우저 디코더가 거부한 실보고 존재(discuss-webrtc), VP8은 손상 시 full keyframe만 디코더 만족. RECON-2(0613f)에서 봇 GOP 차단 전력과도 연결. → primary 불가, PLI fallback 필수.
- **PLI 선제 발사 @ floor-grant** — 1차 설계에서 "비디오 예열 본진"이라 부름. **§4에서 반박됨.**
- PLI 디바운스/단일화 — storm 방지. **단 grant마다 발사와 충돌(§4 반박 5).** 이미 [[20260621_pli_governor_redesign_knowledge]]에서 "추정 drop 전부 제거, min_interval 하나만(H300/L100ms)"으로 결론 난 영역.

### B. publisher 협조 필요 (encoder)
- keyframe-on-grant (floor 잡으면 즉시 IDR 인코딩) — 가장 깔끔, SDK가 floor 이벤트를 encoder에 물려야.
- SVC base-layer-first (VP9/AV1) — base만 먼저 디코딩 가능, 빠른 부트.
- LTR 복구 — full IDR 대신 작은 P-프레임 복구. 디코더 피드백 채널 필요, WebRTC 표준 경로 제한적(VP8 RPSI 실패 보고).

### 함정 3개 (오디오 직관 그대로 옮기면 깨짐) — **이건 코덱/디코더 사실, 안 흔들림**
1. **marker bit 의미 반전.** 오디오 marker=1 = talk-spurt 시작. 비디오 marker=1 = **access unit 마지막 패킷.** §12의 `plaintext[1] |= 0x80` 강제를 비디오 분기에 적용하면 프레임 중간에 "끝" 박아 depacketize 깨짐. 현 코드가 `!require_keyframe`로 게이팅한 게 맞음. **비디오 분기 marker 무수정.**
2. **GDR/intra-refresh는 PTT에서 못 씀.** 브라우저 디코더는 IDR 슬라이스까지 들어오는 스트림 전부 drop. intra-refresh 브라우저 미지원, GDR은 VVC/H.266 신규. WebRTC 코덱(VP8/9·H264·AV1)+브라우저 viewer 조합에선 함정. OxLens 웹/안드로이드 혼재 → 버림.
3. **ts↔wall-clock lock 유지하되 덜 빡빡.** VCMTiming은 NetEQ처럼 재생속도 실시간 신축 안 함, render 스케줄만 재산출(knowledge/2026-06-21-webrtc-receiver-timestamp-render: 큰 점프/공백 hard reset 10초, playout cap 10초). §12 arrival_gap의 ts gap 정밀 재현이 비디오에선 critical하지 않음.

---

## 3. 비디오 "예열"의 정확한 번역

§10 통찰(grant ~ 첫 미디어 = 공짜 윈도우)의 비디오 대칭:
- **오디오 예열** = 그 윈도우에 CN 선충전 → 버퍼 채움 (20260623a).
- **비디오 예열** = 그 윈도우에 PLI 선제 발사 → 키프레임 미리 획득. 윈도우가 PLI 왕복(1 RTT)을 숨김.

**단 — 20260623a §3 가정 정정의 충격이 비디오에도 적용되는지 미확인.** 오디오에선 "grant→첫 RTP 윈도우가 사람 반응시간(200~500ms)"이라는 가정이 **틀렸고**(opus 연속 유입, 윈도우 ~1프레임), 그래서 paced 액터를 버리고 grant 동기 버스트로 갔다. 비디오는 다르다:
- 시나리오 A(카메라 always-ON): 윈도우 짧음, 캐시 IDR 즉시 forward 가능.
- 시나리오 B(grant 시 카메라 ON): 윈도우가 길 수 있음 — **카메라 기동(§4 반박 2)이 지배.**

---

## 4. ★ 1차 설계 자기반박 (강도순)

### 반박 1 (치명) — "기만" 프레임 자체가 비디오엔 거의 안 맞는다
1차에서 PLI-at-grant / keyframe-on-grant / 캐시 forward를 "비디오 기만 무기고"라 부름. **이건 기만이 아니라 정직한 최적화.** 키프레임을 빨리 주는 건 디코더를 속이는 게 아니라 진짜 필요한 걸 빨리 주는 것. 비디오에서 진짜 기만은 **SSRC 가상화+seq 연속(화자전환 봉합) 딱 하나.** 나머지는 정직한 파이프라인 최적화. ⟹ §1의 "4번째 축" 프레임은 오디오 렌즈를 억지로 끼워맞춘 것. 비디오는 기만 문제가 아니라 **키프레임 획득 지연 최소화 문제**고, 다른 종류의 작업.

### 반박 2 (치명) — 시나리오 B 주력이면 진짜 병목은 PLI도 인코딩도 아니다
PowerTel 무전기 모델(평소 카메라 OFF, PTT 시 송출)이 주력이라면: grant 시 카메라 기동 = Camera2 open + 센서 워밍(AE/AF 수렴) + 첫 프레임 캡처 = **수백 ms~1초+.** 예열 윈도우(반응시간) 안에 안 들어올 수 있음. ⟹ 시나리오 B의 cold-start 지배항은 PLI 왕복도 인코딩도 아닌 **카메라 기동.** PLI-at-grant를 "본진"이라 한 게 엉뚱한 데였을 수 있음. 흡수하려면 grant *이전* 카메라 pre-arm 필요 → 배터리/프라이버시(LED) 비용. PLI 한 방으로 안 끝남. **이 층을 1차에서 통째로 안 짚음.**
- 교차근거: [[20260622_ptt_handoff_gap_analysis]] §3.1 — 핸드오프 사슬에 "(장치/마이크 wake)"가 명시돼 있고 갭이 70ms~1272ms로 극심 가변. 영상은 거기에 키프레임 대기까지 더해짐(§2.5 영상 1305ms 정지). 카메라 wake가 실제 사슬에 들어있다는 방증.

### 반박 3 (강함) — 본진을 publisher에 둔 게 fragile
오디오 예열 robust의 핵심 = SFU 단독. 비디오 본진을 keyframe-on-grant(publisher force-IDR)로 옮기면 SFU 제어권 밖. publisher 서드파티/SDK 버전 제각각/HW 인코더 force-IDR API 미개방이면 보장 깨짐. 레거시·이종 클라 환경에서 SFU는 publisher 불신해야 하는데 본진을 그 신뢰에 걺. **오디오 robustness 상실을 trade-off로 명시 안 함.**

### 반박 4 (중간) — "SFU 단독 불가"는 과장
"키프레임은 encoder만, SFU 합성 절대 불가"는 너무 셈. SFU가 미리 구운 단색/검은 더미 IDR로 디코더 부트스트랩 가능(IPTV fast channel change = join 이전 GOP fast burst + I-frame re-encode). 단 정직하게: 더미 IDR로 깨워도 진짜 P-프레임은 진짜 IDR 참조 → 참조 미스매치로 못 받음. ⟹ "단독 불가"가 아니라 **"단독으로는 부트스트랩 시늉까지만"**이 정확.

### 반박 5 (중간) — PLI-at-grant와 PLI 디바운스가 충돌
"storm 막으려 디바운스" + "grant마다 PLI 선제"를 나란히 주장 = 긴장. PTT 화자전환 잦으면 grant 잦고 → grant마다 PLI면 그게 storm. 디바운스 걸면 grant 직후 PLI 묶여 지연 → 예열 반감. 화해 방법 안 풀고 병치만 함. **단 이건 [[20260621_pli_governor_redesign_knowledge]]에서 이미 다룸** — `FLOOR:BRG`(화자전환)는 non-bypass라 거번너 경유하되 "첫 발은 기존과 동일 발사"로 결론. 즉 grant 첫 PLI는 min_interval과 무관하게 나가고 후속만 throttle. 1차 설계가 이 기존 결론을 모르고 충돌인 척 제기한 것. **충돌 아님, 이미 해결된 영역.**

### 반박 6 (약함) — 시나리오 A/B 이분법이 제품 결정을 선점
"B가 주력"은 기술 사실이 아니라 OxLens UX 결정. 실제 제품은 A/B 혼재(같은 룸에 always-on 화자 + push-to-video 화자) 가능. 부장님이 정할 제품 방향을 기술 가정으로 선점함. **추측을 사실처럼 깐 것 인정.**

---

## 5. 종합 — 살아남는 것 / 무너지는 것

**무너짐**: "비디오 기만 4축" 프레임(반박1) · PLI-at-grant=본진 단정(반박2) · publisher 본진 robustness(반박3).

**살아남음**: 함정 3개(marker 반전·GDR 금지·ts lock 완화) = 코덱/디코더 사실, 안 흔들림. SSRC 가상화 봉합도 유지.

**정직한 재정식화**: 비디오 PTT는 "기만"이 아니라 **"키프레임 획득 지연 + 카메라 기동 지연을 누가 어디서 줄이느냐"** 문제. 지배항이 시나리오에 따라 PLI RTT ↔ 카메라 기동 ↔ 인코딩 사이에서 바뀜. **어느 게 본진인지 측정 전엔 모름.** 1차 설계의 핵심 오류 = 측정 없이 PLI를 본진으로 단정.

---

## 6. ★ 측정으로 잠글 것 (추측 라벨 — 미검증)

> [[feedback_verify_dont_speculate]] 준수. 아래는 가정/추정, trace+소스 확정 전까지 결론 아님.

1. **지배항 구간분해 (최우선)**: floor grant → 첫 프레임 render까지를 `grant→PLI도착` / `PLI→IDR인코딩` / `카메라기동` / `전송`으로 쪼개 **지배항부터 실측.** 안 나오면 어떤 기법 깔지 근거 없음. 도구: `oxadmin trace + stat` + getStats `framesDecoded`/`keyFramesDecoded` 첫 증가 시점 + `freezeCount`.
2. **시나리오 A/B 실제 비중**: OxLens가 카메라 always-ON인지 grant-trigger인지 = 제품 결정. 부장님 확정 사항(반박 6).
3. **카메라 기동 시간 (시나리오 B면 지배 후보)**: Camera2 open→첫 프레임 캡처 실측. 윈도우 초과하면 pre-arm 검토(배터리/프라이버시 비용 동반).
4. **캐시 IDR forward 실효**: 브라우저가 SFU 캐시 GOP를 실제 수용하는지(거부 보고 있음). 수용률 낮으면 PLI fallback이 사실상 본진.
5. ~~oxsfud 비디오 분기 실코드 대조~~ — **완료(§8).** `require_keyframe`/`effective_keyframe`/`pending_keyframe`/`TS_GUARD_GAP_VIDEO=3000` 전부 live 코드 확인. 잔여 미확인: 캐시 유무(코드상 없음 확인) / FIR 경로(미확인).

---

## 8. ★ 코드 증거 (oxsfud 실코드 대조, 2026-06-23)

> 소스: `oxlens-sfu-server/crates/oxsfud/src/domain/{rtp_rewriter,ptt_rewriter,pli_governor}.rs`. 가설 주장 ↔ 코드 1:1 대조. **거의 전부 증명, 일부는 코드가 가설보다 셈.**

### 증거 1 — 비디오는 SFU가 아무것도 합성 안 하고 키프레임을 그냥 기다린다 (§1 콘텐츠축 / 반박1·4 확정)
`rtp_rewriter.rs` `rewrite_in_place`: `initialized=false` + non-keyframe → `RewriteResult::PendingKeyframe`(**drop**). 키프레임 도착까지 **모든 P-프레임 폐기**. `ptt_rewriter.rs` `clear_speaker`: `if self.require_keyframe { return None; }` — **video는 silence flush 자체가 없음.** `next_priming_burst`: `if self.require_keyframe ... return Vec::new()` — **video는 예열도 없음.**
→ 오디오는 CN(silence flush 3 + priming burst N)으로 공백을 *합성해 채우지만*, 비디오는 합성 수단이 코드에 0. **"SFU 단독 부트스트랩 불가"가 가설(반박4에서 "시늉까진 가능"으로 완화)보다 강하게, oxsfud는 더미 IDR조차 안 만들고 순수 drop+대기.** 반박1("비디오 기만 거의 불가, 키프레임 정직하게")이 코드로 확정.

### 증거 2 — marker bit 의미 반전, 코드 주석에 박혀 있음 (함정1 확정)
`ptt_rewriter.rs` `rewrite`: `if is_first && !self.require_keyframe { plaintext[1] |= 0x80; }` — **audio만** marker 강제. 바로 위 주석: "VP8 키프레임은 다중 패킷 분할 → marker 강제 시 Chrome 오인 → freeze." 회귀 테스트 `queue_drain_handoff_marks_new_speaker`가 audio marker=1을 가드. → 함정1(비디오 분기 marker 무수정) 코드·주석·테스트 3중 확정.

### 증거 3 — 화자전환·republish는 비디오에서 곧 화면정지 (§1 봉합의 키프레임 의존 확정)
`switch_speaker` → `inner.prepare_source_switch()` → `pending_keyframe=true`. republish 감지(`prev != input_ssrc && inner.initialized`)도 동일 경로. video면 그 직후 키프레임 도착까지 전부 `PendingKeyframe` drop = **전환마다 화면 정지.** 오디오는 같은 전환에서 silence flush+priming으로 연속. → 비대칭이 코드로. [[20260622_ptt_handoff_gap_analysis]] §2.5 영상 1305ms 정지의 코드 레벨 정체.

### 증거 4 — PTT 비디오 키프레임 획득은 inner가 self-heal 안 하고 외부 PLI에 위임 (반박3 확정)
`rtp_rewriter.rs` `needs_pli_retry` 주석: "PttRewriter wrapper는 publisher가 책임 → 미사용." PTT 경로에서 inner의 2초 PLI 자가치유는 **죽어 있고**, 키프레임 획득을 외부 PLI governor/publisher에 맡김. → 반박3("본진을 publisher에 둔 게 fragile, SFU 단독 robustness 상실")이 코드 구조와 정합. 오디오 robustness(SFU가 CN 자력 합성) vs 비디오(외부 의존)의 비대칭이 설계에 이미 새겨져 있음.

### 증거 5 — PLI governor 첫 발 항상 Forward = 반박5는 무효 (재확정)
`pli_governor.rs` `judge_pli`: `last_pli_sent_at`이 None이거나 min_interval(H300/L100ms) 경과면 `Forward`. grant 첫 PLI는 throttle과 무관하게 나가고 후속만 `Drop("throttled")`. → 1차 설계 반박5("PLI-at-grant vs debounce 충돌")는 **존재하지 않는 충돌.** 코드로 종결.

### 증거 6 — 상수·코덱판정 확인 (가설 부록 확정)
`TS_GUARD_GAP_VIDEO: u32 = 3000` (VP8 90kHz×~33ms), `TS_GUARD_GAP_AUDIO = 960`, `SILENCE_FLUSH_COUNT = 3`, `OPUS_SILENCE [0xf8,0xff,0xfe]` 전부 live 확인. 키프레임 판정은 `is_vp8_keyframe`(RFC7741 P-bit) / `is_h264_keyframe`(RFC6184, SPS7·IDR5, STAP-A·FU-A 분해) 구현됨 — mediasoup/Janus 선례(SPS race) 반영. → SFU가 키프레임을 *판정*은 하되 *생성*은 못 함이 코드로 명확.

### 코드로도 못 증명한 것 (정직)
- **함정3(ts lock 비디오에서 덜 빡빡)**: SFU `rewrite` is_first 분기는 audio/video 공통(ticks_per_ms 48 vs 90만 차이) — SFU는 video도 arrival_gap을 ts로 정직하게 박음. "덜 빡빡"은 **수신측 VCMTiming 영역**이라 oxsfud 코드론 증명 불가. webrtc-src 또는 라이브 실측 필요(§6 유지).
- **캐시 유무**: rewriter에 GOP/키프레임 캐시 구조 **없음**(확인). 캐시 forward는 미구현 = 시나리오 A 대비 미비. FIR 경로는 이번 3파일엔 없음(별 파일 가능).

---

## 9. 오디오와의 대조표 (핵심)

| 축 | 오디오 (확립) | 비디오 (가설) |
|---|---|---|
| cold-start 정체 | 빈 버퍼 차오름 | 키프레임 획득 지연 (+ 카메라 기동) |
| 기만 가능? | 가능 (CN 선충전) | 거의 불가 (키프레임은 정직하게 가져옴) |
| SFU 단독? | 단독 가능 | 단독 부트스트랩 시늉까지만 |
| 예열 수단 | CN 버스트 (SFU 합성) | PLI 선발사 + 캐시 forward (publisher 의존) |
| 봉합 | CN splice (micro-gap) | freeze-last-frame (클라가 함) |
| marker 트릭 | marker=1 talk-spurt | **금지 (frame end 의미)** |
| ts lock | 엄격 (NetEQ 공격적) | 완화 (VCMTiming 순함) |
| 본진 | 예열 (측정으로 확정됨, 20260623a) | **미정 (측정 필요)** |

---

_다음: oxsfud 대조 완료(§8). 남은 1순위 = §6-1 지배항 구간분해 실측(grant→PLI도착/PLI→IDR인코딩/카메라기동/전송). 코드가 "SFU는 비디오에서 합성 무력, 키프레임 외부 의존"을 확정했으므로, 본진이 PLI RTT인지 카메라 기동인지 인코딩인지는 **측정만 남음.** 그 다음 캐시 forward(시나리오A) / keyframe-on-grant(시나리오B) 중 택. webrtc-src 수신측 VCMTiming은 함정3 검증 시에만._
