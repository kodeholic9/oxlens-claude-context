// author: kodeholic (powered by Claude)
# 무대 뒤의 야경꾼 — tasks·hooks·metrics·trace 열전

**서사 기반 정적 분석 · 실험 기록 6호**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 전편: floor(1)·domain(2)·udp(3)·handler(4)·datachannel(5)
표적: `crates/oxsfud/src/` 무대 뒤 13파일 **1,724줄** (tasks·hooks 4·metrics 4·trace·agg_logger·telemetry_bus, 테스트 포함 전문 통독, 하위 에이전트 위임 없음)

---

## 0. 실험 조건과 표기 규약 (정직 신고)

- **프라이밍 세션 연속** — 방법론 + 전편 5편 숙지. **§6.1 A/B/C 판정 산입 불가.** 산출물 가치 = 미답 표적 재현성 + 전편 발견(E1·E4·D4·H10·P7·sr_generated)의 무대 뒤 쪽 교차 확인.
- 통독: tasks(480) · hooks/mod(55)·stream(223)·floor(41)·media(53) · metrics/mod(14)·env(37)·sfu_metrics(326)·tokio_snapshot(103) · trace(343) · agg_logger(29) · telemetry_bus(20). 테스트 포함 전문.
- 무대 밖 확인(부분 열람): lib.rs(226~345, 스폰 블록) · transport/udp/mod.rs(279~347, flush 루프 — 3호 통독) · domain/state.rs(PeerState/PublishState/SubscribeState enum) · domain/peer.rs(phase 필드·set_phase_state) · domain/peer_map.rs(reap 천이) · signaling/handler/track_ops.rs(record_stalled_snapshot) · Cargo.toml(features) · 호출처 grep(hook 5종·죽은 카운터 전수).
- 표기: 행위 = `파일.rs::함수:줄` 전체 형식. 판단·은유 = [판단]. 발견 = [확인](소스 실증) / [의문](동작 확정, 결함 여부 판단 필요).
- 기지 제외: D·E·U·H·P 계열은 신규 집계 제외. 무대 뒤가 그 발견들의 **주기 작업·계측 쪽**이라 교차 확인은 §9.

---

## 1. 무대 — 나팔은 워커-0만 분다

앞 5막이 민원(handler)·우편(datachannel)·항만(udp)·왕국(domain)을 돌았다면, 이번 막은 **아무도 보지 않는 뒷마당**이다. 관객(클라)에게 직접 응답하지 않고, 시계에 맞춰 순찰하거나(tasks) 상태 천이 뒤를 조용히 따라다니거나(hooks) 장부를 적는(metrics) 자들.

무대의 물리 사실 셋:

1. **야경꾼은 넷, 시계는 각자 다르다.** floor timer(50ms)·stalled checker·active speaker·zombie reaper — lib.rs::run_server:285-319 가 각각 독립 task 로 spawn 하고, 전부 CancellationToken 하나로 동시 퇴근한다(tasks.rs 의 `cancel.cancelled()` 분기). [판단] 4명이 같은 RoomHub·PeerMap 을 순회하되 락이 아니라 DashMap/ArcSwap 원자 접근으로 스치고 지나간다 — 3호에서 본 "락 없는 원자 필드" 문화가 여기 순찰자들에게도 적용.
2. **회계는 워커-0이 겸직한다.** SfuMetrics.flush()·agg_logger::flush() 를 도는 3초 타이머는 tasks 가 아니라 udp worker-0 루프 안에 있다(udp/mod.rs:288·347 — 3호 §1 "시계와 나팔은 워커-0만"). [판단] 무대 뒤 계측의 심장이 무대(udp)에 박혀 있다 — 순찰과 회계의 소속이 다르다.
3. **도청 탭은 물리적으로 부재한다.** trace 모듈 전체 + 6개 emit 호출부가 `#[cfg(feature = "trace")]`(trace.rs:5). 상용 default 빌드면 코드가 컴파일에 없다 = 보안 경계. **단 그 default 가 지금 trace 를 켜 놓았다**(Cargo.toml:25, →BS6).

## 2. 등장인물

### run_floor_timer — 50ms 종치기 (tasks.rs:27)
방마다 발화자의 RTP 도착 시각을 읽어 서버가 대신 ping 하고(tasks.rs:61-68), check_timers 로 T2/liveness 회수를 수확한다(:71). 성격: **화자의 wire PING 을 안 믿고 RTP 원자 시각을 믿는다**(1호 2막 재확인). half-duplex 없는 방은 건너뛴다(:56). 건강.

### run_stalled_checker — 흐름 감시자 (tasks.rs:117)
subscriber 의 미디어가 멈췄는지 감시해 TRACK_STALLED 를 쏜다. 정교한 다단 게이트를 갖췄다 — threshold·cooldown·PTT 화자 검사·mute 검사·gate 검사·Pause 검사·packets_sent 델타(:155-205). **그러나 첫 관문에서 살아있는 자를 전부 내친다**(:142 `phase < 2 continue`, →BS1). [판단] 정교한 문지기가 문 앞에서 손님을 다 돌려보내는 격 — 이 인물이 3막의 비극이다.

### run_active_speaker_detector — 성량 검침원 (tasks.rs:257)
RFC 6464 audio-level 로 발화자를 뽑아 SVC_SPEAKERS DC 방송한다(:298-304). 성격: **DC 로만 말한다** — event_tx(WS)를 인자로 받고도 `_` 로 버린다(:260). 방 플래그 off 면 전부 skip(:283). [판단] 이 "DC 전용"이 4호 D4(Speakers WS fallback 빈칸)의 발원지다(→BS5·§9).

### run_zombie_reaper — 시체 수확자 (tasks.rs:337)
2단계(Alive→Suspect→Zombie) 판정 후 좀비의 트랙을 방에서 걷어낸다. 성격: **걷어내되 발언권과 성량 기록은 안 건드린다**(2호 E1·E4 의 무대) + vssrc 를 0 으로 적어 낸다(:412, 4호 H10). 정상 LEAVE(room_ops)·evict(helpers)와의 정리 항목 비대칭은 4호 §5 대칭표에 박제됨.

### hooks — 그림자 전령 (hooks/)
상태 천이 뒤를 fire-and-forget 으로 따라가는 넷. 원칙이 명문이다 — "Hook = 천이 후 통지/알림/로깅, 정합성 부수효과는 주관심사 인라인, 실패 격리가 정의"(hooks/mod.rs:4-8). 동적 등록(Observer/EventBus) 금지, 컴파일 타임 정적 디스패치(:10-11). 성격: **넷 중 둘은 일하고 둘은 빈 틀이다**(→BS4). 전역 컨텍스트를 OnceLock 으로 늦게 얻되 미초기화 시 최초 1회만 warn(hooks/mod.rs:45-55) — 안전망 갖춘 게으른 초기화.

### SfuMetrics — 회계실 (sfu_metrics.rs:220)
11개 카테고리 그룹 + 타이밍 3 + fan-out + 진단 3. 3초마다 전부 swap(0)→JSON(:276-325). 성격: **장부에 안 쓰는 칸이 다섯 개 있다**(→BS2). nack 만 flat merge(어드민 호환, :313-318). fan-out 은 매크로 불가라 손으로 min/max CAS(:181-199) — 세심.

### trace — 도청 탭 (trace.rs:53)
SRTP 복호 평문을 외부로 뽑는 "합법 도청"(보안 1급 자인, :4). 단일 세션 ArcSwapOption, 다구독 tx 공유, 다른 타겟 동시 = Conflict(:191-193). hot-path emit 은 무매칭 시 alloc 0(:241-246). 성격: **정확하지 않으면 쓰레기라는 게이트**로 매칭 테스트를 조인다(:283 주석). 와일드카드(user/ssrc None) 매칭 완비. 설계는 모범 — 문제는 default 로 켜져 있다는 것뿐(BS6).

### 소품
- **StalledSnapshot**(tasks.rs:103) — ACK 시점 packets_sent 대조표. publisher_id 필드는 실 user_id 만 담긴다(track_ops.rs:752) — "ptt" 는 절대 안 들어간다(→BS3).
- **TokioRuntimeSnapshot**(tokio_snapshot.rs:6) — 3초 delta 검침. 첫 호출 prev 배열 lazy resize(:40-45). saturating_sub 로 카운터 wrap 방어. 건강.
- **EnvironmentMeta**(env.rs:4) — 기동 시 1회 immutable 캡처. build_info=env!("BUILD_INFO"). 건강.

## 3. 3막

### 1막 — 다섯 시계의 순찰
넷의 야경꾼이 각자 시계로 돈다(lib.rs:285-319 spawn). floor 는 50ms 로 가장 부지런하고, 회계(worker-0)는 3초로 장부를 마감한다. 퇴근은 동시다 — CancellationToken 하나(:295 등)가 울리면 넷이 각자 select 분기로 빠져나온다(tasks.rs:43·131·271·351). SIGTERM/SIGINT 가 그 토큰을 당기고(lib.rs:340-346) SHUTDOWN_DRAIN_MS 만큼 배수 대기(:357). [판단] 감사 20260703b 가 잡은 "SIGTERM hang" 사건의 수리가 여기 살아 있다 — 넷이 토큰 하나로 깔끔히 퇴근. **이 막은 건강하다.**

### 2막 — 그림자 전령의 반쪽
hooks 는 상태 천이의 뒤를 따른다. 넷 중 둘은 실제로 일한다: on_publisher_phase 가 첫 RTP(Active 천이) 때 `track:publish_active` agg-log 를 쓰고(stream.rs:56-72), on_subscriber_phase 가 TRACKS_READY(Active) 때 `subscribe:active` 를 동기 발행한 뒤 PLI·FLOOR_TAKEN 을 tokio::spawn 으로 비동기 발사한다(stream.rs:97-111). on_subscribe_ready 는 egress task 를 CAS 로 단 1회 spawn 한다(media.rs:34-52). 셋은 fire-and-forget 원칙 준수 — hot path 영향 0.

나머지 둘은 빈 틀이다. on_peer_phase 는 본문이 통째 `let _ = (...)` 이고(stream.rs:33-40), 그 이유를 정직하게 적었다 — "reaper 인라인이 metadata 풍부하게 발행하므로, 시그니처만으론 그 metadata 전달 불가, trade-off 에서 현 구조 우위, 묶음 6 결재"(stream.rs:23-27). on_floor_event 는 한술 더 떠 `#[allow(dead_code)]` + 호출처 0(floor.rs:35-41). [판단] 빈 본문 자체는 죄가 아니나(agg-log 를 인라인에 둔 판단은 옳다), on_floor_event 는 "미래 webhook/OpenTelemetry 자리"라는 명분으로 서 있는 **호출자 없는 함수**다 — 부장님 피드백 `feedback_no_speculative_design_backlog`(미구현 설계 큐 박제 금지)와 긴장한다(→BS4).

### 3막 — 흐름 감시자의 눈먼 관문
이제 비극. run_stalled_checker 는 subscriber 미디어가 멈췄는지 감시하는 게 목적이다(tasks.rs:116 "Subscribe 미디어 흐름 감지"). 순회 첫 줄에서 이렇게 거른다:

```
for (user_id, peer) in endpoints.peers_snapshot() {
    if peer.phase.load(...) < 2 { continue; }   // tasks.rs:142
```

`peer.phase` 는 PeerState 다 — Alive=0, Suspect=1, Zombie=2(state.rs:30-34, 초기값 Alive:560). `< 2 continue` 는 **Alive(0)와 Suspect(1)를 건너뛰고 Zombie(2)만 통과시킨다.** 정상 활성 subscriber 는 전부 Alive 라 첫 줄에서 탈락하고, 통과하는 자는 곧 reaper 가 삭제할 좀비뿐이다. STALLED 감지가 정확히 **감지해야 할 대상을 배제**한다.

이 장면은 창작이 아니다 — 아래 다단 게이트(threshold·cooldown·mute·gate·packets_sent 델타, :155-205)는 전부 정교하게 살아 있고, `track.stalled_detected` 카운터도 실존한다(sfu_metrics.rs:74). 문지기가 유능한데 문 앞 첫 검문이 반대로 걸려 있다. [판단] 매직 넘버 `2` 는 3-layer state 분리(Hook Phase 3, 2026-05-17) **이전**의 잔재로 보인다 — 그때 phase 가 PublishState(Created=0/Intended=1/**Active=2**)였다면 `>= 2` 통과 = "발행 활성 peer 만"이라는 뜻이 성립했다. 필드가 PeerState 로 이주하면서 상수 2 의 의미가 Active→Zombie 로 뒤집혔다. 2호 E3(머리말 화석)·4호 H5(죽은 배선)·5호 P3(테스트 라벨 화석)과 같은 **리팩터링이 좌표를 두고 온** 족보다. 다만 라이브 재현 전이므로(§5.2) "결함"이 아니라 강한 [확인]으로 둔다 — 소스 논리상 방향이 명백히 반전되어 있다.

---

## 4. F2 — 관계 비교표

### hook 4종 × 본문 유무 × 호출처
| hook | 본문 | 호출처 | 판정 |
|---|---|---|---|
| on_publisher_phase | agg-log(Active) | publisher_track.rs:479 (fanout 첫 RTP) | 일함 ✅ |
| on_subscriber_phase | agg-log + PLI/TAKEN spawn | subscriber_stream.rs:385 (do_tracks_ready) | 일함 ✅ |
| on_subscribe_ready | egress spawn(CAS) | udp/mod.rs:512 | 일함 ✅ |
| on_peer_phase | **빈**(`let _`) | peer.rs:598 (set_phase) | 자인 빈틀(reaper 인라인 대체) — 정합 |
| on_floor_event | **빈**(`allow dead_code`) | **0** | 죽은 코드(미래틀 명분) → **BS4** |

### 4 야경꾼 × 주기 × 종료 × event_tx 사용
| 야경꾼 | 주기 상수 | 시계 출처 | event_tx(WS) 사용 | 근거 |
|---|---|---|---|---|
| floor timer | FLOOR_PING_INTERVAL_MS | SystemTime 직취(:49) | ✅ apply_floor_actions | tasks.rs:27-97 |
| stalled checker | STALLED_CHECK_INTERVAL_MS | Instant | ✅ emit_event | tasks.rs:117-254 |
| active speaker | ACTIVE_SPEAKER_INTERVAL_MS | — | **❌ `_event_tx`** (DC 직송만) | tasks.rs:257-313 |
| zombie reaper | REAPER_INTERVAL_MS | SystemTime 직취(:357) | ✅ (직접 wire 빌드) | tasks.rs:337-480 |

→ active speaker 만 WS 미사용 = D4 뿌리(**BS5**). 나머지 셋은 WS emit 경유.

### metrics flush 나열 × 정의 (누락 검증 — 지시형 대칭)
| SfuMetrics 필드(11 그룹) | flush 나열 | 판정 |
|---|---|---|
| srtp·pli·rtcp·bwe·relay·track·ptt·codec·dc·simulcast | :297-306 직접 | ✅ |
| nack | :313-318 flat merge(nack_*) | ✅(호환 의도) |
| timing 3·fan_out·env·tokio | :291-309 | ✅ |

→ 그렸더니 안 비었다 — 11 그룹 전부 flush 도달(누락 0). 음수 결과 기록.

## 5. F3 — 대칭표 (빈칸)

### 죽은 카운터 (정의 有 × inc 호출 0) — 전수 grep
```
encrypt_fail   (SrtpMetrics)   → inc 0 ❌  (decrypt_fail 은 살아있음 — 짝만 죽음)
rr_relayed     (RtcpMetrics)   → inc 0 ❌  (rr_consumed/sub_received 는 살아있음)
sr_generated   (RtcpMetrics)   → inc 0 ❌  (★3호 rtcp_terminator SR 자작 #[cfg(test)] 봉인의 정합 잔재)
pt_normalized  (CodecMetrics)  → inc 0 ❌  (rtp_gap_detected 는 살아있음)
dc_error       (DcMetrics)     → inc 0 ❌  ("예약 — 클라 onerror 대응" 자인 :157)
```
→ 5개 카운터가 admin 대시보드에 상시 0 표시. sr_generated 는 3호가 잡은 "서버는 SR 을 자작 안 한다(build_sender_report 가 cfg(test) 물리 봉인)"의 계측 쪽 — 카운터가 봉인을 못 따라가 화석으로 남음(**BS2**).

### stalled checker 관문 방향 (PeerState 축)
```
Alive(0)   → phase<2 → continue (skip)  ← 정상 subscriber = 감지 대상인데 배제
Suspect(1) → phase<2 → continue (skip)
Zombie(2)  → 통과 (검사)               ← reaper 삭제 대상, 통보 도달 전 소멸
```
→ 감지 목적(:116)과 정반대. 통과 집합이 비어가는 방향(**BS1**).

### "ptt" 가드 (읽기 有 × 쓰기 0)
```
tasks.rs:161  if snap.publisher_id == "ptt" { continue; }   ← 읽기
track_ops.rs:752  publisher_id: pub_id.clone()               ← 쓰기(실 user_id만)
```
→ "ptt" 는 절대 안 써짐 → 가드 영원히 false. PTT 제외는 record 단계(track_ops.rs:708-709 주석 "PTT ssrc 자체 제외")가 이미 처리 → 이 가드는 잔재(**BS3**).

## 6. F4 — 주석 증언 대조

| 증언 | 위치 | 대조 결과 |
|---|---|---|
| "본 hook 핸들러 본문은 의도적으로 비어있다 … 현 구조 우위 (묶음 6 결재)" | stream.rs:23-27 | **준수.** reaper 인라인이 metadata 풍부 발행(tasks.rs:396-405) 확인 — 빈 본문 정합 |
| "on_floor_event … 현재 호출 0. 미래 채움 시" | floor.rs:31-35 | **죽은 코드.** allow(dead_code) + 호출처 0(grep). 미래틀 명분 vs 미구현 박제 금지 원칙 → **BS4** |
| "dc_error: 예약 — 클라 onerror와 대응" | sfu_metrics.rs:157 | **미배선 자인.** inc 0 → BS2 |
| "⚠️ 현재 default 에 포함 — 개발 편의. 상용 전 default=[] 로 trace 빼기" | Cargo.toml:17-25 | **위험 현존.** default=["trace"] 활성. deploy-oxlens.sh 가 `cargo build --release` 배포 → 상용에 SRTP 평문 도청 탭 포함 → **BS6** (메모리 [[project_trace_feature_default]] 정합) |
| "PTT slot 은 STALLED 판정 대상에서 제외 — false positive 방지" | track_ops.rs:708-709 | **record 단계 처리 확인** → tasks.rs:161 "ptt" 가드는 잉여(BS3) |
| "room_stats DashMap 폐기 → stream 직속 … 구 방별 순회는 항상 1엔트리 → 단일 처리로 동치" | tasks.rs:149-150 | **준수.** stalled 이 stream 직속 필드 순회(:147). Phase B(2026-06-02) 이주 정합 |

## 7. 발견 목록 (건조체, 신규 = BS)

> **[확인]** = 소스/테스트 실증 · **[의문]** = 동작 확정, 결함 여부 판단 필요. 라이브 재현 미실행 — 심각도 잠정.

**BS1 [확인/주요] stalled_checker 관문 방향 반전 — 정상 subscriber 전원 배제, Zombie 만 검사** — tasks.rs:142 `peer.phase.load() < 2` 가 PeerState(Alive=0/Suspect=1/Zombie=2, 초기값 Alive peer.rs:560) 축. Alive/Suspect 를 continue(skip), Zombie(2)만 통과. STALLED 감지 목적(tasks.rs:116)과 정반대 — 정상 활성 subscriber 는 전부 첫 줄 탈락, 통과자는 reaper 삭제 대상 좀비뿐(통보 도달 전 소멸 개연). 매직 2 는 3-layer state 분리(2026-05-17) 전 PublishState::Active(2) 겨냥 화석 추정 — 필드 이주로 의미 반전(2호 E3·4호 H5·5호 P3 동족). 하류 다단 게이트(:155-205)·stalled_detected 카운터(sfu_metrics.rs:74)는 정상이라 오탐 아닌 무력화. 처방 방향(참고): `is_subscribe_ready()` 또는 `phase != Zombie` 로 교체. **라이브 실측 지침**: 정상 방에서 publisher RTP 중단 후 TRACK_STALLED 발생 여부 / stalled_detected 카운터 증가 여부.

**BS2 [확인/경미] 죽은 카운터 5종** — encrypt_fail·rr_relayed·sr_generated·pt_normalized·dc_error 정의만, inc 호출 0(전수 grep). admin 대시보드 상시 0. sr_generated 는 3호 rtcp_terminator SR 자작 #[cfg(test)] 봉인의 정합 잔재(카운터가 봉인 못 따라감). dc_error 는 "예약" 자인(sfu_metrics.rs:157). 각 짝(decrypt_fail·rr_consumed·rtp_gap_detected)은 생존 — 형제 중 하나만 죽은 F3 빈칸.

**BS3 [확인/경미] tasks.rs:161 죽은 "ptt" 가드** — `snap.publisher_id == "ptt"` 읽되, record_stalled_snapshot 이 publisher_id 를 실 user_id(pub_id)로만 세팅(track_ops.rs:752) → "ptt" 영원히 미기입 → 가드 상시 false. PTT slot 제외는 record 단계(track_ops.rs:708-709)가 이미 처리 → 잔재. BS1 수리 시 함께 제거 후보.

**BS4 [의문] on_floor_event 죽은 코드(미래틀 명분)** — floor.rs:35-41 `#[allow(dead_code)]` + 호출처 0. "미래 webhook/OpenTelemetry 자리" 명분(floor.rs:11-16). 부장님 피드백 [[feedback_no_speculative_design_backlog]](미구현 설계 큐 박제 금지)와 긴장 — 유지/제거 판정 필요. on_peer_phase 빈 본문은 reaper 인라인 대체가 자인되어 정합(결함 아님).

**BS5 [의문/설계] active_speaker_detector WS fallback 부재 = D4 뿌리** — tasks.rs:257-313, event_tx 를 `_event_tx`(:260)로 버리고 broadcast_dc_svc(DC 직송, :299-304)만. DC 미수립 청취자(cross-sfu/affiliate)는 active speaker 영구 미달 — 4호 D4·5호 §9 의 발원지 확정. floor 프레임(6빌더 WS fallback 有, 5호 §5)과 비대칭. 의도(UI 편의라 방치) 여부 결정 승격.

**BS6 [확인/보안·기지재확인] trace feature 가 default 활성** — Cargo.toml:25 `default = ["trace"]`. trace 모듈 = SRTP 복호 평문 미디어 도청 탭(보안 1급, trace.rs:4). deploy-oxlens.sh 가 `cargo build --release` 배포 시 상용 바이너리에 도청 탭 물리 포함. 주석 자신이 "상용 전 default=[] 로 빼기"(Cargo.toml:17-25) 자인. 메모리 [[project_trace_feature_default]] 와 정합 — 6호 소스 좌표 재확인. **상용 출하 전 필수 차단** — 이번 막 최고 심각도.

**관찰(결함 아님)**: build_speakers_dc_payload count/uid_len min(255) 절단 방어(tasks.rs:322·327) · TokioRuntimeSnapshot saturating_sub wrap 방어(tokio_snapshot.rs:52-62) · trace emit 무매칭 alloc 0(trace.rs:241-246) · fan_out min/max CAS 수동(sfu_metrics.rs:181-199) · agg_logger/telemetry_bus 는 common::telemetry re-export shim(실 구현 crate 밖, agg_logger.rs:7-12) — 얇은 파사드, 무대 밖.

**영웅 명단 (음수 발견)**: floor timer RTP 원자 시각 기반(wire PING 불신) · hook fire-and-forget 원칙 + 정적 디스패치(동적 등록 금지) · trace "정확하지 않으면 쓰레기" 매칭 테스트 12종 + 와일드카드 · trace hot-path alloc 0 · CancellationToken 단일 퇴근(SIGTERM hang 수리 생존) · metrics 11그룹 flush 누락 0 · Pan-Floor/room_stats 폐기의 이주 정합 주석.

## 8. 자백 절 (서사 단계 판정 교정)

1. **BS1 을 처음 "매직넘버 경미"로 분류 → "주요 방향반전"으로 승격.** `phase < 2` 를 처음엔 "Zombie 제외 의도의 매직 표현"으로 읽고 경미로 적었다가, PeerState 축 실측(Alive=0 초기값, state.rs:560·30-34)으로 **통과 방향이 반대**임을 확인 — 오탐(과대)이 아니라 **과소평가**를 실측이 교정했다. [판단] §5.2 규율은 "그럴듯한 헛소리"만 겨냥하지 않는다 — 방향 실측 없이 "매직넘버는 대개 의도"라 넘기면 진짜 반전을 놓친다. 상수 비교는 **enum 정의를 열어 방향을 확인**하기 전엔 판정 보류.
2. **metrics flush 누락 의심 → 철회.** SfuMetrics 11그룹 중 nack 만 flush 나열에서 빠진 듯 보여(:297-306) 누락 의심했으나, nack 은 flat merge(nack_* 접두, :313-318)로 별도 삽입 확인 — 어드민 호환 의도된 분리. §5 표에 음수로 기록.

## 9. 교차 확인 절 — 전편 발견의 무대 뒤 쪽 검증

| 전편 발견 | 무대 뒤 쪽 확인 |
|---|---|
| **E1 (zombie floor 누락)** | reaper 전문 통독으로 재확인 — tasks.rs:391-472 에 floor.on_participant_leave 부재(트랙/mid 정리만). 5호 P7(DC task 종료 floor 미해제)의 하류 = 여기서도 안 풂 |
| **E4 (speaker_tracker.remove — zombie 칸만 ❌)** | 4호 정정 재확인 — reaper(tasks.rs:391-472)에 tracker.remove 부재. LEAVE/evict(4호 §5)는 호출. E4 는 "zombie 1칸 ❌"로 확정 유지 |
| **H10 (zombie remove vssrc=0)** | tasks.rs:412 `build_remove_tracks(.., 0, ..)` 재확인. LEAVE/evict 는 실 vssrc(4호 §5). simulcast remove entry ssrc 대칭 위반 |
| **D4 (Speakers WS fallback 빈칸)** | **발원지 확정 = BS5.** active_speaker_detector 가 `_event_tx` 버림(tasks.rs:260) + broadcast_dc_svc DC 직송(:299). WS 경로가 애초에 없음 — 5호 §9(수신측 DC 전용)와 송신측이 짝 |
| **sr_generated 죽은 카운터** | 3호 rtcp_terminator "SR 자작 안 함(build_sender_report cfg(test) 봉인)"의 계측 쪽 = BS2. 카운터가 기각 접근법을 못 따라간 화석 |
| **U6 / BweMetrics** | twcc_fb_rx(sfu_metrics.rs:62) 생존 확인 — 3호 U6(TWCC 회신 video 전용)의 관측점은 살아있음. BS2 죽은 5종에 미포함 |

## 10. 방법론 기록 (실험 6호)

- **수확**: 신규 6건 — [확인] 4(BS1·BS2·BS3·BS6) · [의문] 2(BS4·BS5) + 판정 교정 1(BS1 승격) + 자가 철회 1(§8-2).
- **장치별 기여**: BS1 = **F4+enum 실측**(매직 상수 vs enum 정의 축 — 이번 막 백미) · BS2 = F3(형제 카운터 중 하나만 죽은 빈칸) · BS3 = F3(읽기 有×쓰기 0) · BS4 = F4(dead_code 주석 vs 호출처 0) · BS5 = F2(4 야경꾼 event_tx 사용 표 — active 만 ❌) · BS6 = F4(Cargo.toml 주석 자인).
- **이번 막의 백미** [판단]: BS1. 미답 표적("한 번도 안 본 곳")에서 주요 결함 1건 — 무대 뒤 통독의 정당성 실증. 그리고 **자백 절 교훈이 방법론에 새 규율을 제안한다**: 상수 비교(`< 2`, `== 0` 등)는 **비교 대상 enum 의 정의를 열어 방향을 확인하기 전엔 심각도 판정 보류.** "매직넘버는 대개 의도된 것"이라는 사전(事前) 관대함이 방향 반전을 숨긴다 — 2호 E3·4호 H5·5호 P3 이 전부 "리팩터링이 좌표를 두고 온" 족보였듯, 상수도 리팩터링에 뒤처진다.
- **음수 결과 기록**: hook 3종·metrics 11그룹·타이머 퇴근·trace 매칭은 전부 건강. 무대 뒤는 5호 datachannel 처럼 **대체로 성숙**하되, 잔해(죽은 카운터·죽은 가드·죽은 hook)와 화석 반전(BS1) 하나가 섞인 중간 지대다.
- **한계**: 프라이밍 세션(판정 산입 불가) · BS1·BS5 라이브 미재현(심각도 잠정) · agg_logger/telemetry_bus 실구현은 common crate(무대 밖) · BS6 는 기지(메모리)의 소스 재확인이라 신규 아님.

---

## 다음 단계 (부장님 결재 대상)

1. **BS6 상용 출하 전 필수** — deploy 파이프라인 default=[] 확인/차단(도청 탭 상용 포함 방지). 메모리 경고의 소스 실체 확정.
2. **BS1 라이브 실측 + 수리** — 정상 방 STALLED 미발생 재현 후 `phase != Zombie`/`is_subscribe_ready()` 교체. BS3("ptt" 가드) 동반 제거.
3. BS2(죽은 카운터 5종 정리)·BS4(on_floor_event 유지/제거) 소청소.
4. BS5 결정 승격 — Speakers WS fallback(D4) 의도 확인(4호 D4·5호 §9 와 병합).
5. 잔여 막: 성문 계층(stun·dtls·srtp·demux) · oxhubd(H7 판정 걸림) · grpc/lib 기동 — 별도 세션.

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. 무대 뒤 13파일 1,724줄 전수. 신규 BS1~BS6(확인 4·의문 2) + BS1 승격 교정 + 자가 철회 1. ★BS1 stalled_checker 방향 반전(정상 subscriber 전원 배제) ★BS6 trace default 상용 포함 |
