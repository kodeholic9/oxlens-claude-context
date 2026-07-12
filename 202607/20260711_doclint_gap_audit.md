// author: kodeholic (powered by Claude)
# 마스터 문서·기록 ↔ 소스 갭 전수 감사 (20260711)

> 목적: "문서를 믿고 작업해도 되는가"의 판정. 부장님 지시 — 구석구석 대조.
> 대상: PROJECT_SERVER.md(467줄) 전체 + PROJECT_MASTER.md 서버 관련 절 + 메모리/SESSION_INDEX/git 상태.
> 대조 기준: oxlens-sfu-server HEAD `2e477dd`(main, working tree clean, **미push 커밋 0건**).
> 방법: 5개 반 병렬 문장 단위 대조 + 오탐 후보 2건 본인 직접 재검증(둘 다 기각 — 아래 §3·§5).
> 판정: **A**=문서 낡음(코드가 앞섬) / **B**=코드가 문서 계약 위반(회귀 위험) / **C**=문서 공백(신규 미반영) / **D**=기전 정합·표기만 모호.

---

## §0 종합 판정

**B(코드가 문서·기록의 계약을 위반) = 전 축 0건.** 재도입 금지 대상(SnRangeMap·placeholder sentinel·track-dump·RoomMode·set_id·auto-select) 전수 확인 — 되살아난 것 없음. 기록 축(메모리 19건·세션 인덱스 커밋 해시 15건·git)은 전부 소스와 정합이고 미push 커밋도 없다. **즉 "돌아가는 실체"와 그 이력은 건강하다.**

갭은 전부 반대 방향 — **문서가 코드를 못 따라온 것**: A 19건 + C 7건 + D(모호) 3건 = **29건**. 밀집 구간은 대형 리팩토링 5곳(v3 wire 단일화 0516, phase 3벌 분해 0517, S4 식별 재편 0628, PLI Governor 재설계 0621, FullSim 논리 소유 0709)과 최신 기능(자동 레이어 v1+v2)의 문서 미반영이다.

| 축 | A 낡음 | B 위반 | C 공백 | D 모호 | 계 |
|---|---|---|---|---|---|
| PROJECT_SERVER.md 구조 트리(1~127행) | 6 | 0 | 4 | 0 | 10 |
| PROJECT_SERVER.md 미디어 아키텍처(129~251행) | 6 | 0 | 1 | 0 | 7 |
| PROJECT_SERVER.md 후반부(253~467행) | 6 | 0 | 1 | 2 | 9 |
| PROJECT_MASTER.md 서버 절 | 7 | 0 | 3 | 0 | 10* |
| 메모리·세션 인덱스·git | 0 | 0 | 0 | 1 | 1 |

*중복 계상 정리: MASTER의 oxe2e 삭제·44/43 산식은 A/C 혼합 판정 — 표는 대표 판정 기준. 총계 29건은 중복(oxe2e가 양 문서에 등장) 1건 제외 순수 건수.

---

## §1 PROJECT_SERVER.md 갭 (26건)

### 1-1. 설계 오해 유발 상위 5건 (수정 시급순)

이 5건은 "문서만 읽고 코드를 수정하면 틀린 곳을 고치게 되는" 부류다.

| 순위 | 위치(행) | 문서 주장 | 소스 실체 | 판정 |
|---|---|---|---|---|
| 1 | 204-207 | **PLI Governor = 인과관계 기반**("I-Frame 왔는가를 관측 사실로 판단, 시간 임계치는 안전망") | **정반대** — 0621 재설계로 인과 추정 전면 폐기, 시간 throttle 단일(pli_governor.rs:2-18 "키프레임 수신은 drop 판단에 쓰지 않는다"). "레이어별 차등"만 유효 | A |
| 2 | 197-199 | Fan-out "**Full=물리 Track.subscribers 직접 보유**" | 0709b 처방 2로 **FullSim은 논리 PublisherStream.subscribers 소유**로 이관(publisher_stream.rs:73-81). 물리 보유는 FullNonSim만 | A |
| 3 | 164 | Simulcast **placeholder 사전등록 + sentinel `0xF000_0000\|counter`** + RTP 도착 시 분화 | S4(0628c)로 sentinel·placeholder 색인·alloc_sim_group **전부 폐기**. 현행 = register_stream이 빈 논리 Stream 선확정, 첫 RTP는 find_stream_for_attach로 물리 attach만 | A |
| 4 | 145 | 1PC RTCP 라우터가 "SDES·BYE·APP·**TWCC 무시**" | v2(0710)로 **TWCC(RTPFB fmt15)는 Subscribe 경로 종단 소비**(ingress_rtcp.rs:95-100). 무시는 SDES/BYE/APP만 | A |
| 5 | 290-299 | **ParticipantPhase 단일 5단계**(Created→Intended→Active→Suspect→Zombie) + admin `"phase":"created\|...\|zombie"` | 0517에 **3벌 분해**(PeerState Alive/Suspect/Zombie + PublishState + SubscribeState, state.rs:1-16). admin 문자열도 `"alive\|suspect\|zombie"` — **"active"가 아니라 "alive"** | A |

### 1-2. 구조 트리 갭 (1~127행, 반A)

| 위치(행) | 문서 주장 | 소스 실체 | 판정 |
|---|---|---|---|
| 18 | proto "gRPC v2 … WsMessage {oneof json/binary}" | v3 — `bytes wire=5` 단일 passthrough(oneof 폐기 0516) | A |
| 18 | "SfuService 단일" | 서비스 2개 — SfuService + **CccService**(proto:113) | A |
| 18/58 | TracePackets RPC 무기재 | proto:42 + sfu_service.rs:285 실존 | C |
| 30 | oxsig "(lib.rs, opcode.rs)" | + **code.rs, header.rs** 2파일 더 | C |
| 41 | event_bus "per_user_payloads + binary_payload" | `WsBroadcast{wire}` 단일(v3 통합, event_bus.rs:5-14). per-user는 unicast 반복 발행으로 대체 | A |
| 61 | "RoomHub: DashMap **3-index**" | 단일 인덱스(rooms만) — ufrag/addr 역인덱스는 PeerMap 이관 | A |
| 59-93 | domain/udp 트리에 **bwe.rs/downlink.rs/gcc.rs/auto_layer.rs 미기재** | 4파일 실존(자동 레이어 v1+v2 신설) | C |
| 123 | "oxe2e … 물리 삭제 미정" | **이미 삭제됨**(커밋 202f692, crates/ 부재) | A |
| 16 | policy.toml "(타이머, 대역폭, **방 정책**, 로그)" | [room] 섹션 삭제(0705) — 현행 logging/media/floor/hub만 | A |

### 1-3. 미디어 아키텍처 갭 (129~251행, 반B — 1-1 상위 4건 외)

| 위치(행) | 문서 주장 | 소스 실체 | 판정 |
|---|---|---|---|
| 165 | resolve_stream_kind "**Opus PT=111** → rid → …" 선판별 | PT=111 분기 부재 — 실 순서: 기존ssrc→rtx_ssrc→rid→repaired-rid→rtx_pt→**MID(audio_mid 경로로 오디오 해소)** | A |
| 180 | viaRoom 5빌더 "호출처 **17곳**" | 실측 15곳(build_taken 포함 16) — 수치 드리프트 | A |
| 227-236 | PTT 파이프라인 목록에 **priming CN 없음** | 0623 신설(next_priming_cn, 20ms paced 예열 + exclude_user) — 미기재 | C |

정합 확인(반B): Hyb 1PC 절 8건·Stats 필드명 전수(PublishPipelineStats 5필드/SubscribePipelineStats 4필드 정확 일치)·DcMetrics 19 카운터 실측 일치·STALLED 상수·Duplex 전환·destinations≥2 Denied(0703 배선)·FIELD_PUB_SET_ID 완전 소거 등 — **문서의 계약성 서술 대부분은 살아 있다.**

### 1-4. 후반부 갭 (253~467행, 반C — 1-1의 #5 외)

| 위치(행) | 문서 주장 | 소스 실체 | 판정 |
|---|---|---|---|
| 262 | 발급 자리 "**attach_track_to_stream**의 PublisherStream::new" | 함수 폐기(S4) — 현행 `register_stream`(peer.rs:767) | A |
| 274 | "**has_simulcast_tracks()** 헬퍼로 대체" | **전 트리 부재**(존재한 적 없는 이름) — 실체는 PublisherStream::is_simulcast()/simulcast_video_ssrc() | A |
| 302 | Take-over 7단계 중 "simulcast **purge_subscribe_layers**" | 0429 제거(SubscriberStream auto-clear) — 나머지 6단계 순서는 정합 | A |
| 307 | ICE "latch_by_ufrag→latch_address→get_address" | 실명 find_by_ufrag→**latch_addr**→get_address(기전 정합, 명명 낡음) | D |
| 362 | policy.toml "**ArcSwap 런타임 교체**" | 교체 기계 삭제(0705, 호출자 전무) — **사실상 부팅 1회 로드** | A |
| 437 | SCOPE batch "순서: sub_add → sub_remove" | 실 4단: … → **pub_deselect → pub_select**(pub 축 2단 누락) | C |
| 298 | "CAS로 원자적 상태 전환" | 실 기전 `swap(AcqRel)`(CAS는 suspect_since만) — 원자성은 정합, 용어 부정확 | D |

정합 확인(반C): oxhubd 절 전체(state.rs 심볼 12종·SessionPhase·OutboundQueue·bin_event 철거)·User Probe·Cross-SFU 6건·Supervisor 전 항목·Scope 자료구조 7건 — **hub 서술은 사실상 무결.**

---

## §2 PROJECT_MASTER.md 갭 (반D, 중복 제외 9건)

| 위치(행) | 문서 주장 | 소스 실체 | 판정 |
|---|---|---|---|
| 159-166 | opcode 표에 **0x3005 ADMIN_DOWNLINK_INJECT 결락** | opcode.rs:119 + 양단 핸들러 실존(0709 신설) | C |
| 106 vs 149 | "총 44 op" vs "LAYER_CHANGED 폐기로 44→43" — **자체 모순** | 실 산식 44→43(0705)→**44**(0x3005, 0709). ALL_OPS.len()==44 | A |
| 87 | 헤더 "flags=ACK_STATE\|**PRIO**" | flags bit0-1=ack_state, bit2-7 reserved — **PRIO 비트 없음**(priority는 nibble 파생, 문서 104행과도 자체 상충) | A |
| 116 | RECONNECT "(shadow 기반)" | shadow 철거(0705) — 복구 서술 낡음 | A |
| 255 | "Gauge: Atomic**I64**" | `Gauge(AtomicU64)` | A |
| 255 | "TimingStat: AtomicU64 (count<<32 \| sum_**ms**)" | 4개 별도 AtomicU64(sum/count/min/max) + **마이크로초** 단위 | A |
| 260 | SfuMetrics 카테고리 10개 | 11개 — **simulcast 누락**(auto_demote/promote 카운터) | C |
| 267 | 클라 telemetry "→ TELEMETRY 0x1302"(서버 경유 인상) | hub 종착 **oxcccd 직행**, sfud 미forward(handler/mod.rs:109) — 진단 경로 일원화 미반영 | C |
| 286 | oxe2e "물리 삭제 커밋 미정" | 삭제 완료(202f692) | A |

정합 확인(반D): 0x3005 외 **43개 op 전원 번호·이름 일치**, 헤더 바이트 배치, 아키텍처 원칙·기각 접근법 절 전 항목(핫패스 lock 0·RoomMode·set_id·SnRangeMap — **재도입 0건**), 빌드&환경 절.

---

## §3 기록 축 — 메모리·세션 인덱스·git (반E + 본인 재검증)

**전 축 정합.** 메모리 19건 중 소스 검증 가능 축 15개 전부 현행 일치(trace default 잔존, envelope 덮어쓰기+target_user, 단일 스칼라 offset, sentinel 소거, SRV-0629 exclude_user, telemetry.rs 부재, oxe2epy run-all 진입점, qa/live 실존). 세션 인덱스의 서버 커밋 15건 전부 실존·push 완료. **미push 커밋 0, working tree clean.**

반E가 "phantom 커밋 3건(30b1bee/1fc74f9/ac44715)"으로 A 판정한 건은 **본인 재검증으로 기각** — 셋 다 **oxlens-home 레포** 커밋으로 실존·push 완료(반E가 서버 레포에서만 조회한 오류). 세션 인덱스 기록이 정확했다.

---

## §4 소스 내 화석 주석 (문서 아닌 코드 주석의 드리프트 — 구조 진단서 §9.4와 합산)

1. `rtp_rewriter.rs:22-24` — "RTX gate 미배선, 결재 대기" → 0703 b25e9b9 배선 완료. **주석이 코드보다 낡은 유일한 안전장치 서술** — 최우선 정정.
2. `publisher_track.rs:24` — 모듈 지도가 폐기 함수 `Peer::register_publisher_track` 지시(신규 발견, 반E).
3. `trace.rs:5`/`lib.rs:20` — emit "6곳" → 실측 9곳(보안 자산 인벤토리).
4. downlink/bwe/peer 주석의 옛 킬스위치 이름(`SIMULCAST_AUTO_LAYER`/`BWE_V2`) → 현행 AutoLayerMode.
5. `ingress_subscribe.rs:59` — `room.audio_rewriter`(Slot 이주 전 이름).

---

## §5 감사 자체의 오탐 기각 기록 (교차 검증 실증)

병렬 반 보고 중 2건을 본인 직접 재검증으로 기각했다: ① PLI throttle 필터 마스크 결함(ingress_subscribe.rs:388 — 실코드는 정상, 방어 주석 오독) ② phantom 커밋 3건(§3 — 레포 착오). **"반 보고 → 본인 재검증" 게이트 없이는 거짓 갭 2건이 보고서에 실릴 뻔했다** — 0703 감사의 SubscriberStreamSnapshot 오판과 같은 교훈 재확인.

---

## §6 수정 수순 제언 (문서는 context 레포 — 커밋 부장님)

1. **[1순위] 설계 오해 유발 5건**(§1-1) — PLI Governor·Fan-out FullSim·placeholder sentinel·1PC TWCC·ParticipantPhase. 이 절들은 "읽으면 틀리게 배우는" 상태.
2. **[2순위] 산식·심볼 정확성** — MASTER opcode 표 0x3005 추가+44 산식 정리, PRIO flag 삭제, Telemetry 자료형 2건, 폐기 심볼 3건(attach_track_to_stream/purge_subscribe_layers/has_simulcast_tracks), policy 핫리로드 서술.
3. **[3순위] 문서 공백 채우기** — 구조 트리에 자동 레이어 4파일+TracePackets/CccService, PTT priming CN, SCOPE pub 축, SfuMetrics simulcast, telemetry oxcccd 직행.
4. **[코드 쪽 즉결 후보]** §4 화석 주석 5건 — 특히 RTX gate "미배선" 주석(안전장치를 없는 것으로 서술). 동작 변경 0, 결재 시 일괄.

---

## §7 현행화 집행 기록 (20260711, 같은 세션)

부장님 지시("소스가 권위 — 마스터 문서 현행화, 첫 줄부터 끝까지")로 본 감사의 갭 전량을 **집행 완료**:

- **PROJECT_SERVER.md** — 헤더 현행화 기준을 `20260711 doclint`(HEAD `2e477dd`)로 갱신. 구조 트리(proto v3/CccService/TracePackets/oxsig 4파일/event_bus wire 단일/RoomHub 단일 인덱스/신설 4파일 bwe·downlink·gcc·auto_layer/oxe2e 삭제/policy 유령그룹/trace emit 9곳/tasks PLI sweep 폐기/helpers flush_ptt_silence 유령 명기) + 미디어 아키텍처(1PC TWCC 종단 소비/placeholder sentinel 폐기→register_stream/resolve 순서/viaRoom 수치 제거/Fan-out FullSim 논리 소유/PLI Governor 시간 단일 재작성/**자동 레이어 절 신설**/PTT priming CN·RTX gate 추가) + 후반부(register_stream 발급/has_simulcast_tracks 정정/3벌 상태 재작성/purge_subscribe_layers 제거 반영/latch 심볼/policy 부팅 1회/SCOPE 4단/PUB_SET_ID 소거) 전량 반영.
- **PROJECT_MASTER.md** — doclint 의도 1줄(문서 구성 절) + opcode 표 0x3005 추가·44 산식 정리·PRIO 삭제·RECONNECT shadow 정정 + Telemetry 자료형(Gauge U64/TimingStat 4원자 us)·simulcast 카테고리·0x1302 oxcccd 직행 + 시험 체계(oxe2e 삭제 완료/REGRESSION_GUIDE oxe2epy 기준/qa 14 spec/qa README 부재) + SDK 코어 절 Rust 재편 반영 + 마일스톤 자동 레이어 행 추가 + 날짜 종속 표기 일반화.
- **B급 발견 1건 문서 명기**: STALLED 체커 가드 뒤집힘(PROJECT_SERVER.md STALLED 절 ⚠ — tasks.rs:142 `phase<2`가 구 5단계 기준 잔재, 0517 3벌 분해 후 정상 peer 전원 skip = 감지 전멸. blame: 0423 도입→0517 의미 반전). **코드 수리는 결재 대기.**
- **미확정 항목 처리**: libwebrtc custom "529-line patch" 수치는 소스 근거 미검출 — 단정 제거("재개 시 재확인"로 대체). PROJECT_WEB.md 본문은 이번 doclint 범위 밖(웹 축 별도 회차 권고).

> **doclint 규약**(이 회차에 신설): 정합 감사·현행화 기록은 `context/YYYYMM/YYYYMMDD_doclint_*.md`. `grep -r doclint context/ --include='*.md' -l` 파일명으로 마지막 정합 시점 확인.
