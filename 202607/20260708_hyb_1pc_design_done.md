# 20260708 — Hyb(1PC/2PC) 집행 완료 보고 (Phase 0~4 전체)

> author: kodeholic (powered by Claude)
> 집행: 김과장 (Claude Code, 2026-07-09)
> 지침: `20260708_hyb_1pc_design.md`. Phase 0 완료·합격(PASS 150/0, 정지점 1 통과 — 부장님 확인).
> 정지점 2(Phase 1 뒤) 통과 → 부장님 GO → Phase 2~4 집행 완료. push 는 전부 결재 대기.

---

## §0 의무 점검 수행 기록

- 마스터 3종(PROJECT_MASTER/SERVER/WEB) + SESSION_INDEX_202607 정독 완료.
- 가이드 로드: REGRESSION_GUIDE(oxe2epy) + QA_GUIDE(stub) + RUN_GUIDE(재기동 위생 §6-8).
- **회귀 기준선 (작업 전, 0705 커밋 da0ad9c 위, 실행 서버 = HEAD 정합 확인)**:

| 게이트 | 기준선 | 비고 |
|---|---|---|
| `cargo test -p oxsfud` | **211 passed / 0 failed** (1 ignored) | 기대치와 동수 |
| `python -m oxe2epy run-all` | 26종 중 **OK 25 / 이상 1**(`ptt_multiroom`) → **단독 재실행 PASS** | 봇 타이밍 플레이크로 분별(서버 무결) |
| `qa/live` 3층 | **12/12 passed** | Playwright, http-server 자체기동 |

## §9 시작 전 실측 결과

1. **`ingress_subscribe.rs` 절개점**: `handle_subscribe_rtcp` 가 복호(L146~158, `subscribe.media.inbound_srtp`)와 처리(NACK/RR소비/relay — 전부 평문 기반)를 한 함수에 보유. 지침 예상과 일치 — 처리부를 `process_subscribe_rtcp_plaintext` 로 절개(2PC 는 복호→처리 순서 그대로, 동작 diff 0).
2. **egress 목적 `subscribe.media.*` 전수 grep — 치환/비치환 분류**:
   - **치환(egress 목적)**: `egress.rs:203`(run_egress_task addr) / `egress.rs:239,243`(outbound_srtp RTP/RTCP) / `participant.rs:92`(`is_subscribe_ready` — fanout/SR relay/floor broadcast 게이트의 단일 본문. 이름 유지, 본문만 `egress_session()` 분기).
   - **비치환(subscribe PC 자체)**: `peer_map.rs:277`·`helpers.rs:658`·`room_ops.rs:415`(unregister 정리) / `admin.rs:289`(sub PC 표시) / `ingress_subscribe.rs:147`(2PC sub 복호) / `peer.rs` session()/tests.
   - 지침의 grep 목록 예상(rtcp_terminator.rs/pli.rs/hooks::media)과 실측 차이: 그 파일들엔 `subscribe.media` egress 호출 없음 — SR relay 는 `egress_tx` 큐 경유(모드 무관), PLI 는 publish 방향. `is_subscribe_ready` 단일 본문 치환이 `ingress_rtcp.rs:138`/`publisher_track.rs:755`/`floor_broadcast.rs:265` 게이트를 전부 커버.
3. **`room_ops.rs` ROOM_JOIN**: `get_or_create_with_creds(&user_id, participant_type, now, creds_fn)` 2 호출처(본선 + AlreadyInRoom take-over). server_config 는 ufrag 2쌍 그대로(변경 0 확인).
4. **sdk0.2 pcMode 주입점(Phase 2 대비)**: ROOM_JOIN body 조립 = `talkgroups/talkgroups.ts` L156 부근(`sig.request(OP.ROOM_JOIN, body)`), EngineOpts/join opts 관통 예정.
5. **발견_사항 — `SdpConsistency.js` 부재**: 현 `reference/lib-jitsi-meet` checkout(a16478a8)에서 업스트림이 제거·`LocalSdpMunger.ts`(ssrcMap/sourceName 주입) 로 흡수됨. LocalSdpMunger.ts 로 대체 정독. 교대 협상 m-line 일관성은 Phase 0 실증(PASS 150/0)이 이미 커버 — 영향 없음.

## Phase 1 집행 (서버, 커밋 `e7d70fd`, 13파일 +651/−41)

전 신규 분기 `conn_mode` 게이트 뒤 — **2PC 경로 동작 diff 0** (치환 헬퍼 제외).

- **1a**: `ConnMode{TwoPc,OnePc}`(types.rs, Peer 불변 필드) + `RoomJoinRequest.pc_mode`(미지정="2pc" 완전 하위호환) + `get_or_create_with_creds` mode 관통 + **모드 불일치 take-over**(전 방 `evict_user_from_room` 루프 + endpoints 정리 + 재생성 — 기존 take-over 경로 재사용).
- **1b**: `Peer::egress_session()` — TwoPc=`&subscribe.media` / OnePc=`&publish.media`. §9-2 분류대로 치환 4자리.
- **1c**: `udp/mod.rs` DTLS 완료부 — OnePc 는 **Publish** DTLS Ready 시 `on_subscribe_ready`(egress task spawn). TwoPc 불변.
- **1d**: `route_onepc_rtcp`(ingress_rtcp.rs) — publish.media 단일 복호 → compound 패킷 단위 분해 → §2.4 표 라우팅: SR(sender∈by_ssrc)→publish 평문 처리부 / RR(block∈by_vssrc)·NACK(fmt1, target∈by_vssrc)·PLI(by_vssrc→`stream_for_pli_target` 3단)·REMB→subscribe 평문 처리부 / SDES·BYE·APP·TWCC(fmt15)→현행 동일 무시 / 미해소→drop+`rtcp.onepc_unrouted`(METRICS 신설). 선행 절개 = `process_subscribe_rtcp_plaintext` + `process_publish_rtcp_plaintext`.
- **1e**: `MidPool::with_base` + `config::ONEPC_SUB_MID_BASE=32`. `SubscribeContext::new(ufrag, pwd, mid_base)` 인자 방식 채택 — Peer::new 가 모드 보고 base 주입(호출처 = peer.rs 1 + 테스트 2 뿐).
- **1f**: 단위 시험 **15 신설** — ConnMode wire 파싱(strict)/기본값, egress_session 분기(ptr eq + OnePc ready 전이), MidPool base/recycle, 1PC sub mid=32 시작(2PC=0 무손상), peer_map mode 관통(재사용 시 무시), RTCP 라우터 분류 표 7시험(SR known/unknown·RR 1블록/빈RR/미해소·NACK/TWCC·PLI 직해소/3단해소/audio-only 미해소·REMB·SDES/BYE/APP/미지PT), ROOM_JOIN pc_mode take-over 통합시험(1pc→2pc 재생성 + 새 creds + 방 멤버십 정합 + 미지값 reject).

### 시그니처 선조치 (호출처 보고 결정 — 룰 2)

1. **`process_publish_rtcp` 도 대칭 절개** — 지침 1d 는 ingress_subscribe 절개만 명시했으나, 1PC 라우터가 SR 을 "기존 publish 경로"로 위임하려면 평문 진입점이 필요(단일 복호 후 이중 복호 불가). 2PC wrapper 는 복호→처리 순서 그대로 — 동작 diff 0.
2. **`pc_mode` 미지값 = 3002 reject** — 지침은 "미지정=2pc"만 명시. 미지값을 조용히 2pc 폴백하면 클라 오타 시 1PC 폴백 관측 불가(코덱 묵시 VP8 함정과 동형) → strict reject 채택.
3. **모드 take-over 는 전 방 evict 루프** — 기존 AlreadyInRoom take-over 는 단일 방 대상. 모드 전환은 Peer 재생성이라 잔여 방 전부 정리 필요(cross-room 잔재 차단).
4. **RTCP 분류 세칙**: RR RC=0(Chrome keepalive)=무해 무시 / RTPFB fmt≠1(TWCC)=현행(2PC) 동일 무시 / REMB=subscribe 통과(처리부가 media_ssrc=0 을 현행대로 skip) — 전부 2PC 처리부 동작과 등가 유지.

## ★정지점 2 — 회귀 3종 기준선 동수 확인 (Phase 1 바이너리로 재기동 후)

재기동: release 재빌드 → `oxadmin shutdown`(graceful 7s, 자식 전멸) → 포트 free 확인 → oxhubd 재기동(3 unit live).

| 게이트 | 기준선 | 정지점 2 | 판정 |
|---|---|---|---|
| cargo test -p oxsfud | 211/211 | **226/226** (기존 211 무손상 + 신규 15) | ✅ 동수+ |
| oxe2epy run-all | 25 OK+1 플레이크(단독 PASS) | **26종 OK 26 / 이상 0** | ✅ 동수+ |
| qa/live 3층 | 12/12 | **12/12** | ✅ 동수 |

- 경고 0 (cargo check workspace 통과). 커밋 = `e7d70fd` 1건(Phase 단위). **push 안 함**(결재 대기).
- 안전근거: 신규 코드는 전부 `conn_mode==OnePc` 게이트 뒤 + 치환 헬퍼는 TwoPc 에서 원래 세션과 동일 참조(ptr eq 시험). 2PC wire/스키마 변경 = `pc_mode` optional 필드 1개(미지정 기본 2pc).
- 트레이드오프: `is_subscribe_ready` 이름은 유지(호출처 6곳 diff 회피) — 의미는 "egress 가능"로 주석 정정. 1PC 실경로(STUN latch→DTLS→RTP/RTCP 라이브)는 클라(Phase 2) 없이는 무검증 — Phase 3 통합 검증 몫.

## 발견_사항 (조치 불요, 보고만)

1. `reference/lib-jitsi-meet` 에 `SdpConsistency.js` 부재(§9-5 실측 — 위 §9 항목 5).
2. 기준선 run-all 1회에서 `ptt_multiroom` 이상 1건 — 단독 재실행 및 Phase 1 후 run-all 에서 모두 PASS. 봇 타이밍 플레이크 성향(서버 무결). 재발 시 관찰 대상.
3. Phase 0 산출물: `oxlens-home/lab/onepc-spike/index.html` 존재하나 `202607/` 에 Phase 0 별도 `_done` 파일은 없음(정지점 1 은 부장님 확인으로 통과 처리됨).

## Phase 2 집행 (클라 sdk0.2 — oxlens-home 커밋 `4a801b0` 스파이크 + `397426e` 본체 + `a9c77ec` 결함수리)

- **2a** `Transport.pcMode('1pc'|'2pc', 불변)` — '1pc'는 `subPc` getter 가 pubPc 반환(단일 PC), ontrack 은 pubPc 바인딩, teardown 은 2PC 소유분(`_subPcOwn`)만 별도 정리. `status` 에 pcMode 노출.
- **2b** 단일 협상 큐 — `_subQueue`→`_negoQueue` 승격(`_enqueueNego`: 에러는 호출자 전파 + 큐 생존). '1pc'는 `ensurePublishPc`(초기 C-offer)·`_reNegoPublish`·subscribe renego 전부 직렬. '2pc' 현행 분리 유지. 큐 내부 재진입(데드락) 회피 = `_ensurePublishPcNow` 절개.
- **2c** mirror 상태 = **pubPc.localDescription 원문 에코**(스파이크 검증형 — 별도 PcMirrorState 자료구조 없이 최신 협상 상태 자체를 원천으로). extmap **원본 ID 에코 강제**, rid/simulcast send→recv 반전. *(시그니처 선조치: 지침의 "per-mid 캡처·유지"를 localDescription 에코로 충족 — 캡처 스냅샷보다 항상 최신이고 스파이크가 10루프 실증한 형태.)*
- **2d** `buildUnifiedRemoteOffer` — pub 미러 + DC 미러 + sub m-line(`_subTrackCodecs`/`_normalizeSubscribeTracks` 공용 추출, ice=publish 쌍, sdes:mid 제거, extmap=동일 kind pub 에코[세션 일관 ID] 폴백 서버정책). **★sub ssrc 분리형**(`splitMsid`: `a=ssrc cname`+미디어레벨 `a=msid`) — §7 지뢰 회피, 2PC 결합형 무변경. `buildPublishRemoteAnswer(+subRegistry)` — 재-offer 의 sub m-line(recvonly)을 sendonly+ssrc 로 응답(스파이크 hard-fail #1). 기존 sub mid 는 절대 blind-mirror 안 함(스파이크의 미러 느슨함을 정공으로 교정 — recvonly 미러는 inactive 로 협상됨).
- **2e** `EngineOptions.pcMode`(기본 '2pc') + talkgroups `_roomJoin` 에 `pc_mode:"1pc"` 만 명시 송신(2pc=미지정, wire 하위호환). **자동 폴백 1회**: 협상 throw(setRemote/setLocal/re-nego)·ICE failed → diagnostics `onepc:fallback` + 모드 플립(engine/transportSet/talkgroups) + sfu 별 `_rebuildTransport`(R2 재사용) → 재-JOIN 미지정 → 서버 모드 take-over 로 2PC 재수립.
- **2f** `tsc --noEmit` + `tsup` PASS. 단위 12 → **17**(신규 `onepc-sdp.test.ts` 5 — 미러 방향/원본 extmap ID/분리형/BUNDLE 순서/subRegistry/2pc 무변경) 전부 PASS.

## Phase 3 통합 검증 (커밋 `4f57cfa` — qa 하니스 + onepc.spec 5종)

**라이브 실증 결함 1건 발견·봉합**(커밋 `a9c77ec`) — 첫 라이브에서 2인 이상 1PC 가 전멸:
1PC 는 slot sub m-line(32/33)이 pub video 보다 먼저 생김 → "첫 m=video" 파서
(`_parseAnswerVideoPt`)가 slot 섹션의 VP8 pt=96 을 집어 intent codec=H264 와 함께 서버에
96=H264 오등록 → 구독 SDP "96 VP8+96 H264" PT 충돌 → **모든 구독자 setRemote 사망(1pc·2pc
공통 오염)**. 수리 = `_remotePubVideoSection`(전 `m=` 경계 split + recvonly(pub) 섹션 한정,
`_parseAnswerRtxPt` 도 그 섹션 scope). 폴백 메커니즘은 이 실패에서 설계대로 발화(부수 실증).

| 게이트 | 결과 |
|---|---|
| 3a 1PC 변형 3종 | **ONEPC-CONF-01**(3인, 3권위 교차+framesDecoded>0) / **ONEPC-SIM-01**(h/l 2레이어 등록·수신 — §7 "1PC×simulcast 비양립" 기각 라이브 재확인) / **ONEPC-DUPLEX-01**(full→half→full) 전부 PASS |
| 3b 2PC 무손상 | 3층 **17/17**(기존 12 전부 + 신규 5) / cargo **226/226** / oxe2epy run-all 26종 — 회차별 이상 1~2건은 매회 다른 자리(conf_simulcast·repub_hdelay·ptt_multiroom)로 **전부 단독 재실행 PASS** = 봇 타이밍 플레이크(기준선과 동일 특성, 서버 무결) |
| 3c 폴백 실증 | **ONEPC-FALLBACK-01** — qa `corrupt1pc` 노브(1pc transport fingerprint 오염) → 실 협상 실패(`error:setRemote`) → 자동 2pc 재수립 → U01 av 수신 + framesDecoded>0 PASS |
| 3d PTT | **ONEPC-PTT-01** — floor granted(MBCP/단일 PC DC) + 청자 slot audio Δ>0 PASS. (거울 특성: granted 직후 self 포함 FLOOR_TAKEN 이 `_floor='taken'` 덮음 — 단언은 `granted|taken + speaker` 로) |

- 1PC 물증: `qa.pcState()` transports 전원 '1pc' + 폴백 0 + 단일 PC(sub=pub 동일 상태) + sub mid 32/33 시작(ONEPC_SUB_MID_BASE).
- qa 하니스: `pcmode`/`corrupt1pc` URL 노브, `qa.pcState()`, diagnostics 녹취, **reconcile 재조립 시 room 거울 재배선**(R2/폴백 후 새 Room 인스턴스의 trackSubscribed 수신 — qa 어댑터 한정).

## Phase 4 문서

- PROJECT_SERVER.md "미디어 아키텍처" 맨 앞에 **Hyb 연결 모드** 절 신설(ConnMode/RTCP 라우터/egress_session/mid base/클라 링크).
- PROJECT_WEB.md sdk0.2 아키텍처에 **hyb 1PC 모드(pcMode)** 절 신설(단일 큐/mirror-offer/분리형 ssrc/PT 파서 함정/폴백/3층).
- PROJECT_MASTER.md 마일스톤 1줄 + SESSION_INDEX_202607 1행. (context 레포 커밋은 부장님.)

## 커밋 대장 (push 전부 결재 대기)

| 레포 | 커밋 | 내용 |
|---|---|---|
| oxlens-sfu-server | `e7d70fd` | 서버 Phase 1 (13파일 +651/−41, 단위 15 신설 → 226) |
| oxlens-home | `4a801b0` | Phase 0 스파이크 박제(lab/onepc-spike) |
| oxlens-home | `397426e` | 클라 Phase 2 (7파일 +728/−79, 단위 5 신설 → 17) |
| oxlens-home | `a9c77ec` | 1PC pub PT 파서 결함 수리(라이브 실증) |
| oxlens-home | `4f57cfa` | Phase 3 qa 하니스 + onepc.spec 5종 |

## 발견_사항 (추가, 조치 불요)

4. **1PC known-gap — cross-browser PT**: 구독 SDP 의 publisher-PT 반영이 1PC 에선 구독자 자신의
   pub m-line 과 같은 BUNDLE PT 공간을 공유 — Chrome↔Chrome(현 타겟)은 PT 매핑이 안정적이나
   이종 브라우저 publisher 의 PT 가 구독자 로컬 매핑과 충돌하면 setRemote 실패 → hyb 폴백이
   보험(서비스 생존). 근본 해소는 서버 PT rewrite — 별 토픽.
5. run-all 플레이크(봇 타이밍)가 회차마다 1~2건 자리를 바꿔 발생(ptt_multiroom/conf_simulcast/
   repub_hdelay) — 전부 단독 PASS. 빈도가 늘면 봇 타이밍 여유 검토 별 토픽.
