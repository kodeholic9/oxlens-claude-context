<!-- author: kodeholic (powered by Claude) -->

# PTT 예열 라이브 시험 + 돌림노래 근본 규명 (neteq_rtpplay 오프라인 harness) — 세션 기록

> 기간: 2026-06-23 저녁 ~ 06-24 새벽. 부장(얼박사) ↔ 김대리(Claude).
> 한 줄: PTT 예열(priming)을 구현·라이브 시험 → 2회 실패(jb 폭주) → **브라우저 없이 진짜 NetEQ를 돌리는 오프라인 harness(neteq_rtpplay)를 구축**해 돌림노래 근본을 "수신 NetEQ가 업링크 지터를 증폭"으로 **실증 확정**. 예열은 첫음절용으로 **유지**, SFU-side fix는 **폐기**(LiveKit 대조로 비표준 확인).
> 선행: [[20260623_ptt_neteq_integration_notes]], [[20260623_round_song_uplink_jitter_analysis]], [[20260623a_ptt_priming_design]].

---

## 0. 이번 세션의 수확 (한눈에)

1. **neteq_rtpplay 오프라인 harness** — pcap(tcpdump) → rtpdump 합성 → 실제 webrtc NetEQ 통과 → jb target/expand 추이 측정. 브라우저 런타임 없이 수신측 거동 재현. **이게 최대 성과.**
2. **돌림노래 근본 확정**: publisher 업링크 지터 → SFU pass-through → **수신 NetEQ delay manager가 jb target을 380ms~1s로 증폭**. arrival 지터만 제거하면 target 7ms. marker·ts점프·payload·CN방식 전부 무관.
3. **기각 확정**: SFU-side fix(playout-delay 확장 / SFU 지터버퍼) — LiveKit 등 성숙 SFU도 audio는 pass-through + 수신 NetEQ 일임. marker 조작 — NetEQ가 audio marker 미사용.
4. **oxadmin `stat`** — iostat식 연속 수신 모니터 완성(입체 분석용).
5. **예열(priming)** — 첫 음절 빠른 재생 목적으로 **유지** (커밋 `6584bc3`).

---

## 1. oxadmin `stat` — iostat식 수신 모니터

목적: `trace`(SFU 와이어)와 **동시**에 걸어 수신 클라 NetEq 내부(jb/glch/acc/dec)를 wall-clock으로 정렬 = 입체 분석.

- `stat <user> [--interval N]` (기본 2s, Ctrl+C). kind별 활성 스트림 자동선택(트랙 선택 불요).
- 컬럼: `rxA(src/pps/lost/disc/jb/jbT/glch/acc/dec) | rxV(src/fps/kbps/frz/dec/kf) | txA txV`.
- 필드 정의: jb/jbT = jitterBufferDelay/TargetDelay 평균 ms(Δ구간), **glch = (concealed − silent) Δ**(실 글리치), acc/dec = removed/insertedSamples(압축/신장), src = track_id(출처 user 식별).
- 수정 이력: `next_priming_burst`→track_tag(ssrc 배열 처리), txV = `framesEncoded` Δ(outbound framesPerSecond null 회피).
- 가이드 §4-S로 RUN_GUIDE에 문서화.

---

## 2. PTT 예열(priming) 설계 → 구현

### 배경
돌림노래/cold-start = 화자 전환 시 수신 NetEQ가 차가운 상태로 첫 burst에 반응. 예열 = grant 직후 첫 실음성 전에 CN(comfort noise)을 미리 흘려 버퍼를 데움(첫 음절 보존).

### 구현 (oxsfud, 커밋 `6584bc3`)
- `config.rs`: `PRIMING_MAX_FRAMES=250`(안전상한).
- `slot.rs`: `priming_gen: AtomicU64`(화자 추월 시 옛 task 자가종료).
- `ptt_rewriter.rs`: `next_priming_cn()` — CN 1프레임(silence flush 템플릿 재사용, ext_last+1 seq, arrival-gap ts, advance_last). 첫 3개 marker=1(`priming_marker_left`).
- `floor_broadcast.rs`: `spawn_priming_for_speaker` — grant 시 20ms `interval` task(MissedTickBehavior::Delay), 첫RTP/화자해제/추월/상한까지 CN paced 송출 + task-end 로그(`[PTT:PRIME] sent= stop=`).
- 회귀 테스트 3종 + 전체 211 PASS.

### 설계 변천 (오가정 정정)
1. 1차: grant에 **버스트 5개(100ms)** one-shot. → 윈도우 ~20ms 가정.
2. 부장 지적: "첫 RTP까지 보내야 예열" → **paced**로 정정.
3. 부장 지적: "RTP는 발화 무관 연속 유입" → 침묵방어(PRIMING_MAX_FRAMES 의존) 군더더기 제거.

---

## 3. 라이브 시험 — 2회 연속 실패

trace + `stat U01/U02/U03` 입체 측정.

| 시도 | 결과(수신 jbT) | 비고 |
|---|---|---|
| burst 5개 | jb **420ms** 폭주 | 버스트가 NetEQ jitter 추정기 왜곡 |
| paced(20ms) + marker×3 | jbT **1860ms / 749ms / 300ms**(run마다 변동) | 더 심함. glch 18000~38000 |

- **floor·포워딩은 정상**(seq 역행 0, 핸드오프 marker 정상, panic 없음). 슬롯 실음성도 50pps 연속.
- marker=1×3을 넣었는데 결과가 **일관 호전이 아니라 무작위 변동** → marker가 변수 아님을 시사.

---

## 4. neteq_rtpplay 오프라인 harness 구축 (핵심)

부장 지적: "클라로 넘기지 마라. 수신 NetEQ 동작은 webrtc 소스(`~/repository/webrtc-checkout/src`)에 다 있다."

### 빌드
`~/depot_tools/autoninja -C out/Default neteq_rtpplay` (siso, libs 빌드돼 있어 링크만 — 수십초). → `out/Default/neteq_rtpplay`.

### 입력 합성 (SRTP 우회)
- `sudo tcpdump -i lo0 -s0 -w /tmp/slot.pcap udp port 19740` (sfu-1, localhost=lo0). **SRTP라도 RTP 헤더(seq/ts/marker/ssrc)는 평문.** trace가 못 잡는 egress_tx CN도 tcpdump는 잡음.
- pcap → rtpdump: egress(src=19740) 슬롯 ssrc만, 12B 헤더 + `OPUS_SILENCE([0xf8,0xff,0xfe], 유효 20ms 디코드)`, arrival=pcap 시각. (payload 무관 — delay manager는 타이밍만.)
- `neteq_rtpplay --opus 111 --pythonplot` → `.py`의 `target_delay_y`/`arrival_delay_y` 파싱. **요약 stat(preferred_buffer)이 아니라 타임라인을 봐야** 함(요약은 오해 소지).

---

## 5. 결정적 실험 결과

| 입력 | target_delay |
|---|---|
| 완벽 clean (20ms 균일, 갭 0) | **0ms** (median), max 70 — harness 정상 검증 |
| 실제 pcap 타이밍 | **380ms median / 1008ms peak** — 폭주 재현 |
| arrival을 ts에 맞춤 (지터만 제거, ts패턴 유지) | **7ms** |

→ **세 번째 줄이 결정타**: idle 점프·silence flush·marker·payload 전부 동일한데 **arrival 지터만 없애니 7ms.** 폭주는 100% **전달 지터**.

ingress vs egress 지터 비교: publisher 업링크 |arrΔ−tsΔ| p95 40ms·max 248ms, egress max 236ms(≈통과). → 업링크 지터를 SFU가 pass-through, NetEQ가 95%ile(메모리 누적) target으로 증폭.

---

## 6. 소스 근거 (~/repository/webrtc-checkout/src webrtc NetEQ)

- **marker bit**: `neteq/` 전체 grep 0건. **NetEQ는 audio marker 미사용** → marker=0/1 차이 없음(두 가설 다 무의미).
- **delay 계산**: `decision_logic.cc` PacketArrived → `packet_arrival_history.GetDelayMs` = (이 패킷 delay − 창2s내 min-delay). underrun_optimizer 95%ile → target. 히스토그램 상한 2000ms(=폭주 천장).
- **CNG/DTMF 면제**: line 174 `is_cng_or_dtmf`면 delay manager skip. 단 판정은 **PT 기반**(`IsComfortNoise(pt)`) → 우리 CN(PT111 speech)은 speech로 분류돼 면제 안 됨. CNG PT로 보내면 면제되나 예열(speech 버퍼 데우기) 효과도 사라짐(= raw와 동일).
- **LiveKit 대조**: audio는 `NoQueue` pacer로 **pass-through**(SFU 지터버퍼 없음). playout-delay 확장은 **VIDEO 전용**(a/v sync, `if kind==Video`). → audio 지터는 **수신 NetEQ 일임이 표준**(우리 SFU도 동일=정상).

---

## 7. 근본 원인 (확정)

**돌림노래 = publisher 업링크 지터를 SFU가 그대로 통과시키고, 수신 NetEQ가 jb target을 과증폭(380ms~1s)한 것.** 증폭된 버퍼 → 재생 지연 + 늘었다줄었다(워블) = 돌림노래.

- 무관(반증): marker(NetEQ 미사용), idle-ts점프(ts맞춤→7ms), payload/CN방식, "CN 뭉쳐 도착"(egress median 20ms).
- 표준: audio pass-through + 수신 NetEQ(LiveKit 동일). SFU-side fix는 비표준.

---

## 8. 결정

- **예열(priming) 유지** — 첫 음절 빠른 재생 도구. revert 안 함. (단 marker=1×3은 NetEQ 미사용이라 사실상 no-op — 효과는 paced CN 선충전 자체에서 옴.)
- **SFU-side fix(③playout-delay ④SFU 지터버퍼) 폐기** — LiveKit 대조로 비표준 확인.
- **다음 1순위 = 기기 분리 측정.** 큰 지터(p95 40ms)가 "한 맥 브라우저 3탭 CPU경합" 시험 artifact인지, 실환경 문제인지부터 가름. 실환경에서도 크면 레버는 수신 클라(NetEQ) 레이어.

---

## 9. 변경 파일 상태

| 레포 | 파일 | 상태 |
|---|---|---|
| oxsfud | config.rs / slot.rs / ptt_rewriter.rs / floor_broadcast.rs (priming) | **커밋 `6584bc3`** (유지, 첫음절용) |
| oxadmin | main.rs (stat) | **커밋 `f4209a9`** (다중 user + --out, 빌드·10테스트 PASS) |
| context | 20260623a_ptt_priming_design.md, 본 기록 | 미커밋(부장님 commit) |
| webrtc src | out/Default/neteq_rtpplay (빌드 산물) | 도구, 재사용 |

회귀: oxsfud `cargo test` 211 PASS. 라이브 회귀(oxe2e) 미실시.

---

## 10. 백로그 / 다음 세션

1. **기기 분리(또는 부하↓) 재측정** — 지터가 시험 artifact인지 확정. (fix 결정 전 선결.)
2. neteq_rtpplay harness로 **예열 변형 오프라인 비교** (라이브 반복 없이).
3. 실환경에서도 지터 크면 → 수신 클라 NetEQ 설정(jitterBufferMinimumDelay 등) 검토.
4. priming(`6584bc3`)/stat(`f4209a9`) — **커밋 완료** (2026-06-24).

_기록 끝._
