# 20260708 — Hyb(1PC/2PC 선택형) 설계 + Phase 0 격리 스파이크 작업지침

> author: kodeholic (powered by Claude)
> 작성: 김대리 (Fable 세션, 소스 실측 기반 — peer.rs / peer_map.rs / transport/{demux,stun,dtls,srtp}.rs /
> udp/{mod,ingress}.rs / sdk0.2 internal/transport/{transport,sdp,transport-set}.ts 전문 정독 완료)
> 집행: 김과장 (Claude Code)

---

## §0 의무 점검 (작업 시작 전 김과장 필수)

1. `context/PROJECT_MASTER.md` + `context/PROJECT_SERVER.md` + `context/PROJECT_WEB.md` 정독.
2. 본 지침 §9 "시작 전 확인" 실측 항목 수행 — 특히 `ingress_subscribe.rs` 복호 위치 (§9-1).
3. 회귀 기준선 확보: `cargo test`(211), `python -m oxe2epy run <all>`, `cd oxlens-home/qa/live && npm test`(12/12)
   — **작업 전** 전부 GREEN 인지 먼저 확인하고 수치 기록. (0705 push 대기 커밋 위에서 작업.)

## §1 컨텍스트

**목표(고정값, 축소 금지)**: 1PC + hyb + 수천 구독 대응.

**동기**: PTT always-on 특성상 STUN consent/keepalive 부담이 2PC에서 2배. 1PC로 절반.
모바일 배터리(DRX) + 연결 수립 시간 + NAT 바인딩 절감.

**전략 = hyb**: 1PC를 메인으로 밀되, **검증된 2PC를 모드 분기 뒤에 무손상 보존**.
hyb가 보험 드는 함정 = 협상/단말형(브라우저가 1PC 교대 협상을 못 받는 류).
규모형 함정은 아님(sub m-line 수는 1PC/2PC 공통 — 5/22~6월 3회 논의로 종결).
1PC 실패 시 클라가 2PC로 폴백해 **서비스는 무조건 동작**한다.

**3회 논의 승계 결론(뒤집지 말 것)**:
- 우리는 sendrecv 미사용(sendonly/recvonly만) → mediasoup BWE 분리 우려 원천 무효.
- Publish/SubscribeContext 분리는 PC 단위가 아니라 direction 단위 — 1PC로 가도 분리 유지.
- 고정 슬롯 offset 예약(0~9/10~11/12+) **폐기** — 동적 MidPool + direction 토글이 현행 정답.
- PTT slot 해석 (a): m-line 자리 개념 없음, per-room vssrc(5/2 모델) 그대로.
- LiveKit은 2PC(1PC 전환 사례 아님). 1PC 구조 레퍼런스 = **lib-jitsi-meet**(`reference/lib-jitsi-meet`),
  m-line recycle = mediasoup-client `RemoteSdp.ts`. livekit 레포는 미디어엔진 품질 참조용.
- 현행 pause(트랙 유지 + RTP만 차단, 서버 fanout 제외)가 구독 변동 대부분을 SDP 없이 흡수
  → 1PC의 유일 실질 약점(renego 얽힘)을 이미 우회 중.

**최대 미검증 가정(Phase 0가 깨볼 것)**: 한 RTCPeerConnection에서
클라-offer 사이클(pub 추가)과 서버-offer 사이클(sub 갱신, 우리 fake SDP)이
**교대로(alternating offerer)** 돌면서 기존 sender/simulcast/SSRC가 보존되는가.

## §2 결정된 사항 (소스 실측 근거)

### 2.1 서버 현행 관문 (실측 확인 완료)

| 관문 | 현행 | 1PC 함의 |
|---|---|---|
| `PcType{Publish,Subscribe}` | peer.rs — STUN latch/DTLS/SRTP/ingress 분기 전체를 관통 | 1PC peer는 **항상 Publish로 latch** (아래 2.3) |
| `MediaSession` | PC당 1개 × 2 (publish.media / subscribe.media). ICE creds/addr/in·out SRTP/media_state | 1PC는 publish.media 하나만 산다. **통합·삭제하지 않는다** — subscribe.media는 미사용 상태로 방치(2PC 무손상) |
| `PeerMap.by_ufrag/by_addr` | ufrag 2개 → (Peer, PcType) 2-way | 1PC는 sub ufrag가 영원히 latch 안 됨 — 등록 자체는 무해, 삭제 불필요 |
| `handle_srtp` (ingress.rs) | `pc_type != Publish → handle_subscribe_rtcp` / Publish → RTP·RTCP 분기 | 1PC는 sub 방향 RTCP(RR/NACK/PLI)가 **Publish 경로로 들어온다** → RTCP 라우터 필요 (Phase 1 핵심) |
| egress | `subscribe.media.{get_address, outbound_srtp}` 사용 | `Peer::egress_session()` 단일 진입으로 치환 (Phase 1) |
| DTLS | 양 PC 모두 서버 passive / 클라 active (dtls.rs `is_client=false`, sdp.ts setup:passive) | 1PC 단일 핸드셰이크, 방향 충돌 없음 ✓ |
| DC | Pub PC 소유 (SCTP loop) | 1PC = 그 PC 그대로. **변경 0** ✓ |
| `on_subscribe_ready` | Subscribe DTLS Ready 시 egress task spawn | 1PC는 **Publish DTLS Ready 시** spawn 필요 (Phase 1) |

### 2.2 클라 현행 관문 (sdk0.2 실측 확인 완료)

- pubPc = 클라-offer / fake-answer(`buildPublishRemoteAnswer` — direction 반전 + extmap 에코 + simulcast recv 라인).
- subPc = fake 서버-offer(`buildSubscribeRemoteSdp` — sendonly×N + a=ssrc vssrc + mid 오름차순 + inactive port=7) / Chrome-answer.
- **핵심 발견**: `buildPublishRemoteAnswer`가 이미 "pub m-line을 서버 시점으로 반전해 그리는" 로직 전부를 보유.
  1PC의 mirror-offer 빌더는 이 로직의 재조립이다(신규 발명 아님).
- pub renego와 sub renego가 현재 **독립 큐**(subPc만 `_subQueue`) — 1PC에서는 한 PC의 signalingState를
  공유하므로 **단일 협상 큐로 통합 필수** (Phase 2 핵심).

### 2.3 Hyb 모드 설계 (확정)

- `ConnMode { TwoPc, OnePc }` — `domain/types.rs` 신설. `Peer`에 불변 필드로 보유
  (`Peer::new` 인자 추가, 생성 후 변경 금지 — 모드 전환 = peer 재생성).
- **모드 선언 = 최초 ROOM_JOIN body `pc_mode: "1pc" | "2pc"`** (미지정 = "2pc", 완전 하위호환).
  Peer 생성 시점(get_or_create_with_creds)과 일치. 이후 JOIN에서 다른 모드 오면 take-over
  (evict_user_from_room + 재생성) 경로 재사용.
- server_config는 현행 그대로 ufrag 2쌍 발급(변경 0). 1PC 클라는 **publish 쌍만 사용**.
  sub ufrag는 미사용 등록(무해). → 서버 wire 스키마 변경 최소.
- **폴백(hyb의 본질)**: 클라가 1PC 협상/연결 실패 감지(setRemote throw / ICE failed / DTLS timeout)
  → teardown → `pc_mode:"2pc"`로 재-JOIN(복구 R2 경로 재사용). 서버는 take-over로 자연 수용.
  폴백은 클라 주도 — 서버에 폴백 로직 없음(단순성).
- **1PC subscribe mid 네임스페이스**: `MidPool::with_base(ONEPC_SUB_MID_BASE)` (config 상수, 권고값 32).
  근거: 1PC에서 클라 pub mid(0..P, DC 포함, P≤6)와 서버 할당 sub mid가 같은 BUNDLE을 공유 → 충돌 방지.
  이것은 기각된 "고정 슬롯 예약"이 아니라 **네임스페이스 분할**이다(예약 m-line 0개, 동적 할당 유지).
  `SubscriberStream.mid: u8` 상한 255 → 223 슬롯 여유.

### 2.4 1PC RTCP 라우팅 규칙 (서버, 확정)

1PC에서 단일 5-tuple로 들어오는 RTCP compound를 패킷 단위로 분해해 라우팅:

| RTCP | 판별 | 라우팅 |
|---|---|---|
| SR(200) | sender ssrc ∈ `PublisherTrackIndex.by_ssrc` | 기존 publish RTCP 경로(SR translation 원천) |
| RR(201) | report block ssrc ∈ `SubscriberStreamIndex.by_vssrc` | 기존 subscribe 경로 — **종단 소비**(publisher 릴레이 금지, RTCP Terminator 불변) |
| PSFB PLI(206) | target ssrc → by_vssrc 우선, 실패 시 `stream_for_pli_target` 3단 해소 | 기존 subscribe PLI relay 경로 |
| RTPFB NACK(205) | target ssrc ∈ by_vssrc | 기존 subscribe NACK/RTX 경로 |
| SDES/BYE | — | 무시(현행 동일) |
| 미해소 | — | drop + `METRICS` 카운터 신설(`rtcp.onepc_unrouted`) — 조용한 drop 금지 |

복호는 이미 publish.media.inbound_srtp 단일(같은 DTLS)이므로 추가 SRTP 작업 없음.

## §3 결정 추천 (★정지점 — 부장님 결재 후 Phase 1 진입)

- **[결재 1] 5/22 미결 2건 정리.**
  (a) 모바일 dynamic decoder acquire 패치 → **보류** 추천. 근거: 그 패치는 "recvonly slot 대량 사전
  박기"의 디코더 압박 대응인데, 현 설계는 동적 MidPool + pause라 inactive 슬롯 대량 상존 자체가 없음.
  Android SDK도 휴면. 필요 트리거(모바일 1PC + 대량 슬롯) 발생 시 재진입.
  (b) Linux Chrome 16-stream 한도 → **무시(문서화만)** 추천. 근거: 활성 디코더 수 문제라 1PC/2PC 무관
  공통 부담이며 selective subscription으로 억제됨. capacity 시험(oxlab cap) 축에서 실측 후 재론.
- **[결재 2] 본 지침 Phase 구성 + 정지점 2개(Phase 0 뒤 / Phase 1 뒤) 승인.**
  기본동작: 결재 시 Phase 0부터 집행.

## §4 단계별 작업

### Phase 0 — 격리 스파이크 (본 서버/SDK 변경 0)

**목적**: §1의 최대 미검증 가정(교대 협상)을 최소 비용으로 깨본다. 실패 시 여기서 설계 재론(매몰 0).

- 자리: `oxlens-home/lab/onepc-spike/` (단일 html+js, sdk0.2 import 없이 독립 — sdp.ts의 빌더 로직은
  복사 참조 가능하되 SDK 소스 무변경).
- 시나리오 (Chrome 최신, 전부 한 페이지 내 단일 RTCPeerConnection):
  1. **C-offer ①**: PC 생성 + DC + audio sendonly + video sendonly(simulcast h/l sendEncodings)
     → createOffer/setLocal → fake answer(= buildPublishRemoteAnswer 동형: recvonly 반전, extmap 에코,
     `a=rid:h recv`+`a=simulcast:recv h;l`, 가짜 ufrag/fingerprint) → setRemote. 단언: stable.
  2. **S-offer ①**: fake 서버-offer = (기존 pub m-line 3개를 서버 시점 recvonly로 미러 + extmap **원본
     ID 에코** + 동일 PT) + 신규 sub m-line 2개(audio/video sendonly + 가짜 vssrc + mid "32","33")
     + DC m-line 미러 → setRemote(offer) → createAnswer/setLocal. 단언: stable / 기존 pub transceiver
     `currentDirection === 'sendonly'` 전원 보존 / `sender.getParameters().encodings` rid [h,l] 보존 /
     localDescription의 pub SSRC 값 사이클 ① 대비 **불변** / mid 순서·값 불변 / 신규 transceiver 2개
     `currentDirection === 'recvonly'`.
  3. **C-offer ②**: screen sendonly 추가 → 사이클 1 반복. 단언: sub m-line(32,33) 위치·direction 보존.
  4. **S-offer ②**: sub m-line 1개 추가(mid "34") + 기존 34→inactive 토글 1회. 단언: 동일 보존 세트.
  5. 위 4단을 **10회 루프** — 누적 renego에서 m-line 순서/SSRC/simulcast 파손 없는지.
- 합격 predicate: 위 단언 전부 PASS × 10회. 부분 실패 시 **실패 지점·에러 원문 그대로** _done에 기록
  (해석 가공 금지 — 이게 설계 재론의 원료다).
- Safari/Firefox = known-gap으로 기록만(Chrome이 1차 타겟).

**★정지점 1**: Phase 0 결과 보고 → 부장님 GO 후 Phase 1.

### Phase 1 — 서버: ConnMode 분기 + RTCP 라우터 + egress 단일 진입

전 변경은 `conn_mode == OnePc` 게이트 뒤. **2PC 경로 diff 0이 목표**(치환 헬퍼 제외).

- 1a. `domain/types.rs`: `ConnMode` 신설. `Peer::new` 인자 + 필드(불변). `PeerMap::get_or_create_with_creds`
  시그니처에 mode 관통. `room_ops.rs` ROOM_JOIN body `pc_mode` 파싱(기본 TwoPc). 모드 불일치 재-JOIN
  → 기존 take-over 경로.
- 1b. `Peer::egress_session(&self) -> &MediaSession`: TwoPc→`&subscribe.media` / OnePc→`&publish.media`.
  `subscribe.media.get_address()` / `outbound_srtp` / `is_media_ready()`의 **egress 목적 호출처 전수 치환**
  (egress.rs / rtcp_terminator.rs / pli.rs / hooks::media / helpers.rs 등 — §9-2 grep 목록으로 전수 확보.
  단, subscribe PC "자체"를 다루는 자리(2PC DTLS 수립 등)는 치환 대상 아님 — 목적 판별 주의).
- 1c. `hooks::media::on_subscribe_ready` 트리거: OnePc는 Publish DTLS Ready 시점(udp/mod.rs
  start_dtls_handshake 완료부)에 동일 spawn. TwoPc 경로 불변.
- 1d. **1PC RTCP 라우터**: `ingress.rs::handle_srtp`의 publish RTCP 진입(`process_publish_rtcp`) 앞에
  OnePc 분기 — §2.4 표대로 compound 분해 후 기존 핸들러 함수로 위임. 선행 리팩터: `ingress_subscribe.rs`의
  복호와 처리 분리(§9-1 실측 후 — 처리부가 평문 진입점을 노출하도록 함수 절개. 2PC 경로는 복호→처리
  순서 그대로라 동작 diff 0).
- 1e. `MidPool::with_base(u32)` + `config::ONEPC_SUB_MID_BASE=32`. `SubscribeContext::new`는 모드 모름
  → Peer::new에서 OnePc면 mid_pool base 적용(생성자 인자 or 생성 직후 설정 — 김과장이 호출처 보고 결정,
  시그니처 선조치 후 보고 룰).
- 1f. 단위 시험: ConnMode 생성/take-over, egress_session 분기, RTCP 라우터 표 6행(합성 compound),
  MidPool base. 기존 211 무손상.

**★정지점 2**: cargo test + oxe2epy + 3층 12/12 **전부 기준선과 동수** 확인 후 보고 → GO.

### Phase 2 — 클라: Transport 1PC 모드 + 단일 협상 큐 + mirror-offer 빌더

- 2a. `Transport`에 `pcMode: '1pc'|'2pc'`(기본 '2pc'). '1pc'면 subPc getter가 pubPc를 반환(단일 PC).
  teardown/status/collectStats 정합.
- 2b. **단일 협상 큐**: '1pc'에서 `_reNegoPublish`와 `_setupSubscribePc`가 같은 Promise 큐를 탄다
  (기존 `_subQueue`를 `_negoQueue`로 승격, '2pc'는 현행 분리 유지). glare rollback 가드 재사용.
- 2c. **PcMirrorState**: 최초 C-offer 협상에서 per-mid {kind, extmap 원본 ID, PT 매핑, ssrc, simulcast,
  direction}을 캡처·유지. **함정: mirror-offer의 extmap ID는 반드시 이 원본 에코** — 새 ID 제안 시
  answerer Chrome이 offer ID를 따라가 wire 헤더확장 ID가 바뀌고, 서버 PublishContext extmap atomic과
  어긋나 rid/mid/twcc 파싱 전멸(검은 화면 계열).
- 2d. `buildUnifiedRemoteOffer(serverConfig, mirrorState, subscribeTracks)`: pub m-line 미러(서버 시점
  recvonly + simulcast recv 라인 — buildPublishRemoteAnswer의 섹션 빌드와 공용 헬퍼로 추출) + DC 미러
  + sub m-line(buildSubscribeRemoteSdp의 buildMediaSection 재사용, ice는 publish 쌍) + BUNDLE 전체.
  sub 트랙 정렬·중복 mid 붕괴 규칙은 기존 그대로.
- 2e. Engine: join 옵션/EngineOpts에 `pcMode`(기본 '2pc'), ROOM_JOIN body `pc_mode` 송신.
  **폴백**: '1pc' 협상·연결 실패 → diagnostics 이벤트 + teardown + '2pc'로 재-JOIN(R2 재사용) 자동 1회.
- 2f. `tsc --noEmit` + tsup + 기존 단위 12/12.

### Phase 3 — 통합 검증 (1PC 라이브 + 2PC 무손상 회귀)

- 3a. 3층(qa/live)에 `pcMode:'1pc'` 변형 시나리오: CONF-VIDEO/SIMULCAST/DUPLEX 최소 3종 1PC로 재실행.
  판정은 기존 3권위 교차 그대로 + framesDecoded>0.
- 3b. **2PC 무손상 predicate**: 기본 모드('2pc')로 기존 3층 12/12 + oxe2epy 전 시나리오 + cargo 전체
  — 기준선(§0-3 기록치)과 동수. 하나라도 어긋나면 병합 불가.
- 3c. 폴백 실증: 1PC 협상을 인위 실패(스파이크에서 발견된 실패 유형 주입 or fake SDP 오염 스위치)
  → 자동 2PC 재수립 → 미디어 정상까지 1케이스.
- 3d. PTT 축: talkgroups 1PC 스모크 1종(floor + slot 수신). MBCP는 DC라 이론상 무변경이지만 실증 필수.

### Phase 4 — 문서/마무리

- PROJECT_SERVER.md "미디어 아키텍처"에 hyb/ConnMode/RTCP 라우터/egress_session 절 추가,
  PROJECT_WEB.md에 pcMode/단일 큐/mirror-offer 절 추가. 마일스톤 1줄. SESSION_INDEX 갱신.
- 커밋은 Phase 단위 분리, **push는 부장님 결재 후**.

## §5 변경 영향 범위 (이외 파일 손대기 금지)

- 서버: `domain/types.rs`, `domain/peer.rs`, `domain/peer_map.rs`, `signaling/handler/room_ops.rs`,
  `transport/udp/{mod,ingress,ingress_subscribe,ingress_rtcp,egress,rtcp_terminator,pli}.rs`,
  `hooks/media.rs`, `config.rs`, (metrics 카운터) `metrics/sfu_metrics.rs`.
- 클라: `sdk0.2/src/internal/transport/{transport,sdp,transport-set}.ts`, `engine.ts`, `types.ts`.
- 스파이크: `oxlens-home/lab/onepc-spike/` 신설.
- 시험: `qa/live` 시나리오 추가, oxsfud 단위 시험 추가.
- **손대지 말 것**: ptt_rewriter / rtp_rewriter / floor / slot / MBCP / SubscriberGate 본문,
  oxe2epy 본체, v0.6 sdk/.

## §6 운영 룰 (표준 4종 + 본건 특칙)

1. 정지점 2개(§4). 2. 시그니처 선조치 후 보고. 3. 추가 변경 금지 — 별 문제는 *발견_사항* 보고만.
4. 2회 실패 시 중단. **특칙**: (a) 모든 신규 분기는 `conn_mode`/`pcMode` 게이트 뒤 — 게이트 없는
   핫패스 변경 발견 시 그 자체가 결함. (b) Phase 0 실패는 실패가 아니라 **산출물**이다 — 원문 보존 보고.
   (c) 기능 축소 방향 선회 금지 — 벽은 "이렇게 넘습니다"로 보고.

## §7 기각 접근법 (재유혹 주의)

- 고정 슬롯 offset 예약(0~9/10~11) — 동적 MidPool과 충돌, 3회 논의로 폐기. base 오프셋(§2.3)과 혼동 금지.
- MediaSession 2개를 1개로 물리 통합 / SubscribeContext 삭제 — 2PC 무손상 원칙 위반. 미사용 방치가 정답.
- 클라-offer로 subscribe까지 통일(클라 mid 자체 할당) — "subscribe mid는 서버 할당" 확정 원칙 역행.
- 서버 주도 폴백 — 폴백은 클라 단독 판단(단순성). 서버는 take-over 수용만.
- LiveKit을 1PC 레퍼런스로 — 2PC다. 1PC 구조는 lib-jitsi-meet(`TraceablePeerConnection.js`,
  `LocalSdpMunger.js`, `SdpConsistency.js`)만.
- mirror-offer에서 extmap ID 재발급 — §4-2c 함정. 원본 에코 강제.
- **sub m-line의 `a=ssrc:X msid:...` 레거시 결합형 — Phase 0 실측 확정 지뢰(Chromium 149).**
  이 형이 remote offer에 들어가는 순간 **같은 PC의 simulcast sender encodings가 증발**한다
  (audio sub의 결합형조차 video simulcast를 죽임 — m-line 경계를 넘는 부작용. SDP엔
  simulcast:send가 살아있는 채 파라미터만 죽음). 생존형 = `a=ssrc:X cname:` + 미디어-레벨
  `a=msid:` 분리(실측 검증, ontrack 정상). **현 sdk0.2 `buildMediaSection`이 결합형 사용 중**
  — 2PC엔 무해(분리 subPc), 1PC Phase 2에서 분리형 전환 필수(2PC 경로는 무변경 유지 가능
  — 모드 분기 뒤에서만 분리형). 따라서 "1PC×simulcast 비양립" 가설은 **기각** —
  simulcast는 1PC 교대 협상 10회를 온전히 통과했다(PASS 150/0).

## §8 산출물

- `oxlens-home/lab/onepc-spike/` + Phase 0 결과 `_done`(정지점 1 보고).
- 서버 Phase 1 커밋(단위 시험 포함) + 정지점 2 보고.
- 클라 Phase 2 커밋. Phase 3 회귀 결과표(1PC 3종 + 2PC 무손상 동수 증빙 + 폴백 1케이스 + PTT 1종).
- Phase 4 문서 갱신. 전체 `_done` 보고서.

## §9 시작 전 확인 (실측 의무 — 본 지침 작성자도 못 본 지점)

1. `ingress_subscribe.rs`(29.7KB) 전문 — 복호(subscribe.media.inbound_srtp)와 처리의 경계 실측.
   1d 절개 지점 확정. **본 지침은 이 파일을 읽지 않고 절개를 지시했다 — 실측이 지침과 다르면 보고 후 정정.**
2. egress 목적의 `subscribe.media.*` 호출처 전수 grep:
   `rg -n "subscribe\.media\.(get_address|outbound_srtp|is_media_ready)" crates/oxsfud/src` — 목록을
   _done에 박고 1b 치환 대상/비대상 분류 근거 남길 것.
3. `room_ops.rs` ROOM_JOIN — server_config 조립부와 get_or_create_with_creds 호출 시그니처 실측.
4. sdk0.2 `engine.ts`의 join/transport ensure 경로 — pcMode 주입 지점 실측.
5. `reference/lib-jitsi-meet/modules/sdp/SdpConsistency.js` — 교대 협상 시 m-line 일관성 유지 기법
   1회 정독(설계 대조용, 코드 차용 아님).

## §10 직전 작업 처리

- 0703/0705 서버 커밋(감사 후속 11건 등) push 결재 대기 중 — 본 작업은 그 위에 쌓는다. push는 별도 결재.
- 백로그 유지: simulcast 레이어 자동 전환 설계(토픽 ①, LiveKit StreamAllocator 대조) — 본 건과 독립,
  다음 세션. F4 unwind 실측 / RemotePipe.muted 표면 결정 — 기존 백로그 그대로.
