# 20260711 — Simulcast 자동 레이어 전환 최종 완료 보고 (v1 + v2, push 완료)

> author: kodeholic (powered by Claude)
> 집행: 김과장 (Claude Code, 20260709~11). 설계: 20260709 v1 설계 + 20260710 v2 설계(r2).
> 상태: **기능 완결 — 전 커밋 push 완료** (서버 `2e477dd` / oxlens-home `ac44715` 가 HEAD).
> 본 문서는 요약 — 상세는 설계서·done 문서·소스가 진실.

---

## 1. 기능 요약

구독자별 다운링크 상태를 서버가 판단해 simulcast 레이어(h 640 / l 160)를 자동
승강한다. 판단(DownlinkController)·집행(Forwarder target/키프레임 게이트)은 v1/v2 공통,
**신호원이 세대 차이**: v1 = 수신자 REMB(수신량 기반 추정, 잡탕 종단 시계) →
v2 = TWCC send-side(서버가 자기 hop 의 송신↔도착을 실측) + RTX 패딩 프로브
(promote 를 화면 무접촉 실측 통과 후에만).

## 2. 운영 모드 (배포 설정이 결정 — `policy.toml`)

```toml
[media]
auto_layer = "v2"   # "off" | "v1" | "v2" — 재기동으로 전환
```

| 모드 | 의미 | 국면 |
|---|---|---|
| `off` | 자동 전환 없음 (수동 SUBSCRIBE_LAYER 만) | 비상 킬 / 미사용. **키 부재·오값의 fallback** — 기능은 명시 opt-in |
| `v1` | REMB 수신측 신호 | 후퇴처 (v2 신규 코드 이상 시 기능 유지·신호원만 후퇴) |
| `v2` | TWCC send-side + 프로브 (원자 게이트) | 정식. `bwe_mode="twcc"` 전제 |

도입 v1→v2 / 후퇴 v2→v1→off. 3단 확정 (shadow/noprobe 등 세분화는 유령 손잡이로 기각).
3단 전부 라이브 A/B 실증: off=관측 필드 부재·수신 정상 / v1=실REMB 복귀(61,973bps) /
v2=전체. 키 부재 재기동 → `[config] auto_layer=off` 로그 물증.

## 3. 커밋 계보 (시간순 — 전부 push 완료)

### oxlens-sfu-server (main)
| 커밋 | 내용 |
|---|---|
| `ba23397` | v1 P1+P2 — DownlinkController (수집 atomic/policy_tick 순수/1s tick/apply_cap min 합류/킬스위치) |
| `4ed6be6` | v1 P3 — 주입 훅(0x3005) + 라이브 실측 수리 3 (★F4 PLI 결핍·target-rid PLI·promote REMB 게이트 제거) |
| `bec3e01` | v1 검수 즉결 — stale loss streak 게이트 + governor 버킷 정합 |
| `38ecf5d` | (기반) fan-out 다운스트림 논리 PublisherStream 소유 — 런타임 전환 GAP 해소 + pending 상한 |
| `a762a8c` | v1 결함 수리 A안 — promote REMB 램프 grace(10s) + Controller::tick 봉인 + LOSS_FRESH 분리(pcap 실측 6s) + admin 관측 |
| `2b4bd1b` | v2 P1 — TWCC egress 배관 (스탬퍼 ensure_twcc_seq/FB 파서/SendRecord/FB 자기실증 latch) — 봉인 출하 (★스탬핑만으로 Chrome FB 발화 + REMB 중단 실측 → 원자 개방 요건) |
| `7a6c90e` | v2 P2 — GccEstimator (trendline/overuse 적응임계/AIMD/손실항/ALR 동결) 관측 전용, 합성 6시나리오 |
| `4aa03fb` | v2 P3 — 신호원 교체 + BWE_V2 원자 개방 (signal_bps 신선도 1s·주입 override·폴백 경계) |
| `c790049` | v2 P4a — RTX 패딩 프로브 + promote 사전 검증 게이트 + 프로브 직접 반영(ProbeBitrateEstimator 간이판) |
| `2bf2491` | 운영 모드 — policy.toml media.auto_layer (off/v1/v2), 상수 2개 → 부팅 로드 전역, 호출부 10개소 |
| `2e477dd` | fallback = off (opt-in 확정) |

### oxlens-home (main)
| 커밋 | 내용 |
|---|---|
| `d08d337` | qa: SIM-AUTO-01 신설 (v1 P3 라이브) |
| `2fe53cb` | qa: step③ known-gap → 단언 승격 (GAP 해소) |
| `30b1bee` | sdk0.2: codecs_sub 소비 — sub m-line 한정 transport-cc (§8-5 (a) 방향 분리) |
| `1fc74f9` | qa: SIM-BWE-01 신설 (v2 배관·신호·무단절) |
| `ac44715` | qa: step④ 물증 승격 (배증→프로브 실측 상향) |

## 4. 변경 파일 전수

### oxlens-sfu-server — 신설 4
| 파일 | 역할 |
|---|---|
| `crates/oxsfud/src/domain/downlink.rs` | DownlinkController — SignalSnapshot(D3 소켓)/policy_tick 순수 정책(D4 히스테리시스+grace+프로브 판정창)/Controller::tick 봉인/수집 atomic. 시험 13 |
| `crates/oxsfud/src/domain/bwe.rs` | DownlinkBwe — SendRecord 링버퍼/FB 자기실증 latch/signal_bps(신선도·주입 override)/probe_boost/관측 캐시 |
| `crates/oxsfud/src/domain/gcc.rs` | GccEstimator — 그룹화→trendline→적응임계 overuse→AIMD+손실 min, ALR 동결, 프로브 직접 반영. 순수(시계 주입), 시험 9 |
| `crates/oxsfud/src/transport/udp/auto_layer.rs` | 1s tick — 신호 조립/신호원 교체/집행(Forwarder target+PLI)/프로브 발사기(20ms rate-limit·중단 조건) |

### oxlens-sfu-server — 수정 26
| 파일 | 변경 요지 |
|---|---|
| `crates/oxsfud/src/config.rs` | AutoLayerMode 전역(off/v1/v2)+게터, AUTO_LAYER_*/BWE_*/PROBE_* 상수(출처 주석) |
| `crates/oxsfud/src/lib.rs` | policy 로더 배선(fallback off)+부팅 로그 |
| `crates/common/src/config/policy.rs` | MediaPolicy.auto_layer (serde default "off") |
| `policy.toml` | media.auto_layer 키(랩 "v2" 명시)+모드 주석 |
| `crates/oxsfud/src/transport/udp/twcc.rs` | ensure_twcc_seq(값교체/BEDE 삽입/신설)+parse_twcc_feedback(전 chunk 형)+시험 8 |
| `crates/oxsfud/src/transport/udp/egress.rs` | run_egress_task 스탬핑(transport당 스칼라 seq, RTX 포함)+on_stamped |
| `crates/oxsfud/src/transport/udp/rtcp.rs` | split_compound twcc_fb_blocks 분리+parse_remb/report_blocks(v1)+build_probe_padding |
| `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` | collect_downlink_signals(RR worst/REMB)+FB 소비(latch→추정기)+절개 |
| `crates/oxsfud/src/transport/udp/ingress_rtcp.rs` | 1PC 라우터 FMT15→subscribe 분류+SR 내장 report block 소비 |
| `crates/oxsfud/src/transport/udp/ingress_publish.rs` | (기반 38ecf5d) sim 신규 track 의 논리 attach |
| `crates/oxsfud/src/transport/udp/mod.rs` | tick 게이트+twcc_stamp 전파 |
| `crates/oxsfud/src/hooks/media.rs` | egress spawn 에 stamp 플래그 관통 |
| `crates/oxsfud/src/domain/peer.rs` | SubscribeContext.downlink+.bwe 홈 |
| `crates/oxsfud/src/domain/subscriber_stream.rs` | Forwarder target_since_ms(pending 상한)+F4 PLI 동반 |
| `crates/oxsfud/src/domain/publisher_stream.rs` | (기반) subscribers 신설+attach — fan-out 논리 소유 |
| `crates/oxsfud/src/domain/publisher_track.rs` | (기반) FullSim fanout 순회 원천 교체 |
| `crates/oxsfud/src/domain/slot.rs` | (기반) AttachTarget::Stream |
| `crates/oxsfud/src/domain/mod.rs` | 모듈 등록 (downlink/bwe/gcc) |
| `crates/oxsfud/src/signaling/handler/helpers.rs` | server_codec_policy_sub(transport-cc, sub 한정)+(기반) collect attach 이관 |
| `crates/oxsfud/src/signaling/handler/room_ops.rs` | ROOM_JOIN codecs_sub 조건 동봉 |
| `crates/oxsfud/src/signaling/handler/admin.rs` | 0x3005 inject(+v2 override)+users snapshot downlink/bwe 관측 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | SUBSCRIBE_LAYER apply_cap min 합류 |
| `crates/oxsfud/src/signaling/handler/mod.rs` | 0x3005 배선 |
| `crates/oxsfud/src/metrics/sfu_metrics.rs` | simulcast auto_demote/promote/backoff+bwe.twcc_fb_rx |
| `crates/oxhubd/src/rest/admin.rs` | POST downlink-inject REST |
| `crates/oxsig/src/opcode.rs` | ADMIN_DOWNLINK_INJECT(0x3005) |

### oxlens-home — 신설 3 / 수정 1
| 파일 | 역할 |
|---|---|
| `qa/live/tests/sim_auto_layer.spec.ts` | SIM-AUTO-01 (demote→무단절→프로브 시도→주입 훅) |
| `qa/live/tests/sim_bwe.spec.ts` | SIM-BWE-01 (FB latch·신호 성립·무단절) |
| `sdk0.2/test/codecs-sub.test.ts` | codecs_sub 방향 분리 시험 4 |
| `sdk0.2/src/internal/transport/sdp.ts` (수정) | sub 빌더(2PC/1PC) codecs_sub 우선 소비 — pub answer 무접촉 |

### 시험 도구 (레포 밖)
- `testlogs/202607/bwe_shaper.sh` — macOS dummynet 링크 정형기 (P3/P4 물증·향후 netem 시나리오. sudo)
- `testlogs/202607/bwe_dummynet_20260711.md` — dummynet 물증 기록

## 5. 검증 최종 수치

- 단위: oxsfud **269/269** + common 20/20 (기능 신규 ~40) · clippy 신규 경고 0
- 2층 oxe2epy run-all: **26종 이상 0** (반복 다수)
- 3층 qa/live: **19/19** (SIM-AUTO/SIM-BWE 포함 — 재기동 후 clean)
- 라이브 물증: F4 PLI 수리(fd 38→243) · grace 램프(34k→57k 억제, 재-demote 0) ·
  FB 왕복(base_seq=0) · 스탬핑↔REMB 인과 A/B · dummynet overuse 감지→85k 감산→
  용량 추종→회복 · **프로브 3회 수렴 실측 후 promote**(312k→1.25M→1.63M→2.03M≥1.98M,
  프로브 중 수신 무단절) · 모드 3단 A/B

## 6. 잔여 (기능 밖 — 백로그)

1. **실망 시험 묶음 1회** (부장님 일정): PTT 청감 게이트(프로브+돌림노래) / GRACE 10s
   튜닝(grace 로그) / bufferbloat h↔l 진동 소멸 최종 물증 (fake 는 수요 생성 불가).
2. **P4b video pacing** — 조건부 보류: 실망에서 0624 형 burst 증상 재관찰 시에만 착수.
3. 티켓 2: NACK/drop Δ 오디오 혼입(스코프 재설계) / 용량<최저 레이어 서버 레버 부재.
4. 상용 전: oxsfud trace feature default 제거 (별 체크리스트).
