# 20260709b — 런타임 h→l 전환 미완결 GAP 분석 보고 (좌표 확정)

> author: kodeholic (powered by Claude)
> 집행: 김과장 (Claude Code, 2026-07-09 야간). 지침: `20260709b_runtime_layer_switch_gap.md`.
> **분석 전용 — 동작 변경 0** (킬스위치 토글 A/B 후 원복, tree clean·계측 코드도 불요했음).
> 정직 신고: 집행자는 신규 세션이 아니라 **당일 auto-layer 당사자 세션** — §D 는 지침 정독 시
> 시야에 들어왔으나 §B 관측을 독립 수행 후 대조했고, 좌표는 관측(코드 blame + A/B 프로브 +
> 서버 로그)만으로 확정했다. 또한 당사자로서 어제 세운 가설("F4 발동=attach 존재")의 기각
> 논리 자체를 재검 대상에 넣었고 — 그 기각이 틀렸음이 이번 관측으로 드러났다(아래).

---

## §B-0 판정 (최우선) — **오늘(0709) 변경 무관, 기존 결함 확정**

| 물증 | 내용 |
|---|---|
| 정적 | 원인 라인 `helpers.rs:290` `if t.simulcast && t.rid.as_deref() == Some("l") { continue; }` — **blame `c5038868` 2026-05-05** (auto-layer 2달 전) |
| 동적 | **킬스위치 OFF 빌드**(auto-layer 완전 비활성)에서 재현 — 아래 A/B 프로브 |

## 절단 좌표 — 마디 [2] FAIL: **l 물리 track 에 구독자 attach 부재 (collect 경로의 l-skip)**

fan-out 은 **각 물리 PublisherTrack 의 `subscribers`(Weak Vec) 를 순회**한다
(`publisher_track.rs::fanout → broadcast(&self.subscribers…)`). 따라서 l 패킷이 구독자의
forward 에 도달하려면 **l track 의 subscribers 에 그 SubscriberStream 이 attach** 되어 있어야
한다. attach 는 두 경로뿐:

- **경로 ①** `helpers::collect_subscribe_tracks`(ROOM_JOIN/SYNC) — `attach_targets` 수집 시
  **`rid=="l"` 을 skip** (L290, 구독 entry 중복 방지 목적의 라인이 attach 까지 삼킴)
  → **h track 에만 attach**.
- **경로 ②** `ingress_publish::register_and_notify_stream`(신규 track RTP-first 등록) —
  등록되는 **그 track** 에 방 구독자들의 stream 을 attach → h/l 이 각각 등록될 때 각각 붙음.

즉 **구독 시점이 track 분화보다 뒤면(publish 먼저 → join 나중 = 경로 ① 만) l attach 가 없다.**

### A/B 프로브 (킬스위치 OFF + 기존 수동 경로만, 2026-07-09 22:50)

| 순서 | 경로 | 결과 (원문) |
|---|---|---|
| **A: publish→join** | collect ① | `[B0:SA] before=null after=null` — **video 완전 무수신**(12s). h 는 fake 환경에서 초반 수십 패킷 후 BWE 로 죽는데, h 에만 attach 라 l 은 도달 0 → **F4 조차 발동 불가**(서버 로그에 SA2 의 [SIM:DEMOTE] 부재 = l 이 forward 에 안 왔다는 간접 물증) → 아무것도 안 나감 |
| **B: join→publish** | ingress ② | `[B0:SB] before={fd:33,w:160} after={fd:73,w:160}` — l attach 존재 → h 사망 시 **F4 demote+SWITCH 정상**(`22:50:47 [SIM:DEMOTE] sub=SB2 … (PLI 동반)` → `[SIM:SWITCH] sub=SB2 h->l`) → l 릴레이 지속 |

### 마디별 pass/fail 표

| 마디 | 판정 | 근거 |
|---|---|---|
| [1] publisher l RTP 송신 | **PASS** | outbound-rtp l active fps=20 kf=7 + `oxadmin trace` l ingress 60pkts/3s (0709 프로브) |
| [2] l 패킷 → 해당 구독자 forward 도달 | **FAIL (A 순서)** | 위 표 — collect l-skip. B 순서는 PASS |
| [3] 분기 판정(sender_layer/target) | (도달 시) PASS | B 순서에서 F4→SWITCH 정상 = 분기 건강 |
| [4] l is_keyframe 성립 | (도달 시) PASS | B 순서 SWITCH 성공 = l kf 검출 정상. kf 판정은 fanout 의 `is_vp8/h264_keyframe`(payload) — 레이어 무관 |
| [5] SWITCH 실행 | (도달 시) PASS | `[SIM:SWITCH]` 로그 원문 (B) |

**결론: 전환 기계([3][4][5])는 건강하다. 죽어 있던 것은 배관([2]) — l track 에 다운스트림이
등록되지 않는 순서(publish 먼저)가 있다.** "런타임 전환 경로가 죽어있다"는 어제 표현은 부정확
— 정확히는 **"collect 로 attach 된 구독(join 이 분화보다 늦은)에서 l 배관이 없다"**.

### 증상 스펙트럼 통일 (같은 뿌리)

- setQuality('l')/auto-demote 후 **영구 pending·640 유지** = h 생존 중 + l 도달 0 (기존
  GAP-simulcast-layerswitch 의 원 관찰).
- **완전 무수신(framesDecoded=0/fdΔ=0)** = h 사망 후 + l 도달 0 — F4 도 발동 불가.
  **SIMULCAST-01 간헐·SIM-AUTO step③ 의 뿌리**. 간헐성의 정체 = **join 시점 race**:
  join 이 h/l 분화 완료보다 늦으면 A 형(사망 위험), 이르면 B 형(정상).
- 어제(0709) 내 기각 논리("F4 발동=attach 존재") 정정: F4 발동 런들은 전부 B 형(join 이
  분화와 겹침)이었다 — A 형에선 F4 자체가 안 뜬다는 것을 몰랐다.
- ※ ONEPC-CONF-01 간헐(발견_사항 ①)은 **non-sim** 이라 본 뿌리 아님 — 별 조사 유지.

## §D 대조 (좌표 확정 후 개봉)

| 후보 | 판정 |
|---|---|
| H1 [마디 2] attach 소급 부재 | **적중** — 단, 정밀 좌표는 "등록 시점 current 레이어 목록"이 아니라 **collect 의 명시적 l-skip 라인**(h 는 항상, l 은 절대 안 붙음). "처음부터 l 정상" 대조군의 실제 원인도 ingress 경로 ② 의 track별 attach |
| H2 [마디 4] l kf 판정/Chrome 미응답 | **기각** — B 순서에서 SWITCH 성공(l kf 검출·응답 정상). ※단 어제 "h-ssrc PLI 로 l kf 안 옴" 실측은 별개로 유효(target-rid PLI 수리 유지 근거) |
| H3 [마디 3] sender_layer N:1 오염 | **기각** — B 순서 분기 정상. sender_layer 는 track(=self) 의 rid — track 단위 fanout 이라 패킷 단위와 일치 |
| 검수 관찰(pending 영구) | **유효·별개** — l 부재 publisher 에 target=Low pending 영구. 본 수리 후에도 pending 나이 상한은 방어로 유의미 |

## 처방 후보 (구현은 결재 후)

- **처방 1 — attach 만 l 에도 (최소 침습)**: collect 의 attach 수집에서 sim 은 논리 Stream 의
  **전 물리 track**(h+l, 이후 분화분은 경로 ② 가 커버)에 같은 sub_stream 을 attach.
  구독 entry(SDP m-line, vssrc 1개) 생성은 현행(h 대표 1 entry) 유지 — skip 라인의 원 목적
  (entry 중복 방지)과 attach 를 분리. `AttachTarget::Track` → `Tracks(Vec)` 확장 or 논리
  Stream 에서 tracks 순회 attach. **trade-off**: 변경 폭 최소(helpers 국소)·모델 유지 /
  attach 가 여전히 물리 track 단위라 "분화·교체 시 소급" 문제를 경로 ② 에 계속 의존
  (repub 등 다른 순서 조합의 잠재 구멍 여지).
- **처방 2 — sim 다운스트림을 논리 PublisherStream 소유로 (구조 정합)**: FullSim 의 fan-out
  순회 목록을 물리 track 이 아닌 **논리 Stream.subscribers** 로 이동 — 어느 rid 패킷이든
  같은 목록을 돌고 레이어 선택은 forward 가 이미 담당(current/target 분기). 물리 track
  분화·교체·repub 과 무관하게 attach 안정 = 순서 race 원천 소멸. "물리 교체돼도 논리 생존"
  (track_id/vssrc 소유 원칙)과 정합. **trade-off**: fanout 경로 구조 변경(FullSim arm 의
  순회 원천 교체 + attach 호출처 2곳 이동)·회귀면 넓음 / 근본 해소.
- (공통 방어) 검수 관찰 반영 — Forwarder pending 나이 상한(예 10s 초과 시 target 클리어)
  1줄: l 자체가 없는 publisher 에서의 영구 pending 차단.
- 추천: **처방 2** (근본·원칙 정합 — race 를 좌표만 옮기는 1안 대비). 급하면 1안 선행 후
  2안 이관도 가능하나 이중 작업.

## 처방 집행 (결재 후 — 정석=2안 확정, 2026-07-09 야간)

부장님 질의("정석이 뭔데")에 답: **2안이 정석** — LiveKit(DownTrack 은 WebRTCReceiver=논리
트랙에 attach) / mediasoup(consumer 가 producerRtpStreams 전 레이어 관찰) 공통형이고,
우리 식별 계층 원칙("물리 Track 교체돼도 논리 Stream 생존")과 정합. 1안은 어긋난 소유권
위의 대증요법이라 병기 자체가 과잉이었음(정석 명백 — 반성).

**집행 = 서버 `38ecf5d` + qa `2fe53cb`** (push 결재 대기):

- `PublisherStream.subscribers` 신설(+`attach_subscriber` — Track 동형 계약: subscriber_id
  유일 idempotent + dead Weak 청소, 단위시험 1). **FullSim fan-out 순회를 논리 Stream
  목록으로 이동** — 어느 rid(h/l) 패킷이든 같은 목록, 레이어 선택은 forward 분기.
  FullNonSim(물리=논리 1:1)/Half(Slot) 는 현행 유지 — 경계 최소.
- attach 호출처 2곳 이관: collect(`AttachTarget::Stream` 신설 — l-skip 라인은 entry 중복
  방지 원목적만 잔존) + ingress 신규-track 등록(sim 은 논리에 idempotent attach).
- **pending 나이 상한**(검수 관찰 2): `Forwarder.target_since_ms` +
  `SIM_TARGET_PENDING_MAX_MS=10s` — forward 초입에서 만료 클리어(now≈publisher.last_rtp_ms
  재사용, 시계 추가 0). 설정 자리 4곳(SUBSCRIBE_LAYER×2/F4/tick) 기록, SWITCH/Pause 시 0.
  킬스위치 무관 일반 방어. F4 의 선(先) switch_layer 잔재는 다음 키프레임 자가치유에 위임(주석).

### 검증 (수리 빌드)

- cargo **241/241** / 2층 run-all **26/26 이상 0**.
- **A 순서(publish→join) 라이브**: 어제 완전 사망(null/정지) → **fdΔ=60/50 지속, w=160**
  (l 배관 정상 — F4 폴백 릴레이 지속).
- **SIM-AUTO step③ known-gap → 단언 승격 PASS**: demote 후 fdΔ=41 w=160 (무단절 재개)
  + promote h 복귀까지 전 사이클.
- **3층 19종 3연속 18/18** — 그간 풀런마다 1건씩 떨어지던 간헐(SIMULCAST-01/ONEPC-CONF-01)
  이 3연속 무결. sim 계열 간헐은 본 뿌리(배관 [2])로 소멸 판단. ONEPC-CONF(non-sim)까지
  같이 조용해진 것은 인과 미확정(간접 효과 or 우연) — 발견_사항 ① 은 관찰 지속(강도 하향).

## 산출물 정리

- §B-0: **오늘 변경 무관** (blame 2026-05-05 + 킬스위치 OFF 재현).
- 좌표: **마디 [2] — collect 경로 l-skip 로 l track attach 부재** (순서 의존: publish→join 만).
- 동작 변경 0 · 계측 커밋 0 (기존 로그/trace/프로브로 충분) · 킬스위치 ON 원복·재기동 완료.
- 처방 2안 + 공통 방어 1 — 결재 대기.
