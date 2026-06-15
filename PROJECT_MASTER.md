---
name: oxlens
description: |
  OxLens SFU 서버 + 웹 클라이언트 + Android SDK 프로젝트 컨텍스트.
  코딩, 설계, 리팩터, 디버깅, 코드리뷰 요청 시 반드시 참조할 것.
  키워드: oxlens, SFU, PTT, 무전, oxsfud, oxhubd, oxsig, oxrtc,
  Engine/Room/Endpoint/Pipe, SdpNegotiator, PeerConnection, 2PC,
  RTCP Terminator, SR Translation, PLI Governor, SubscriberGate,
  RoomHub, FloorController, PttRewriter, SimulcastRewriter,
  DataChannel/SCTP/DCEP, MBCP/TS 24.380, MidPool, SubScribe MID,
  ParticipantPhase, SessionPhase, freeze masking, moderate/grant/revoke,
  cross-room federation, Peer 재설계, telemetry, 어드민,
  wire v3 (8B 헤더 / 16진 opcode), WireAckState, Track Dump,
  NackGenerator, IngressPublish/IngressRtcp, PublishContext (pub_room/pub_stats home).
---

# OxLens — 프로젝트 마스터 문서

## 문서 구성

이 마스터는 **코드 위치 비종속 원칙·계약**만 보유. 코드 종속(휘발성) 상세는 분리(2026-06-03):

| 파일 | 담는 것 |
|---|---|
| **PROJECT_MASTER.md** (이 파일) | 개요·구성·시그널링 계약·마일스톤·핵심 학습/원칙·기각·빌드·코딩 규칙·분업·세션·시험 체계 |
| **[PROJECT_SERVER.md](PROJECT_SERVER.md)** | 서버 소스 구조(domain/)·미디어 아키텍처·oxhubd·Peer 재설계·scope 자료구조 |
| **[PROJECT_WEB.md](PROJECT_WEB.md)** | 웹클라 소스 구조·신 SDK(sdk/) 평면 아키텍처·프리셋 체계 |

> Android SDK(`oxlens-sdk-core`)는 **휴면** — 별도 파일 없음(아래 "SDK 코어" 참조).

### 가이드 (키워드 로드 의무 — 해당 작업 시작 전 반드시 읽는다)

| 가이드 | 트리거 키워드 | 담는 것 |
|---|---|---|
| `guide/QA_GUIDE_FOR_AI.md` | 시험/E2E/Smoke | 환경·도구·절차·오진 방지·불변식 |
| `guide/METRICS_GUIDE_FOR_AI.md` | 스냅샷 분석 | 메트릭 해석·오진 패턴 |
| `guide/REGRESSION_GUIDE_FOR_AI.md` | 회귀시험 | oxe2e 시나리오 운용 |
| `guide/RUN_GUIDE_FOR_AI.md` | 기동/실행 | 서버·클라 기동 절차 |
| `guide/MEDIA_DEBUG_GUIDE_FOR_AI.md` | **미디어 디버깅 / 검은 화면** | 환경 정합 0순위·4축 계층 분해(getStats)·게이트/PLI 체인·코덱 계약 (2026-06-13 신설) |
| `guide/WEBSDK_GUIDE_FOR_AI.md` | **웹 SDK 사용 / SDK 시험 작성** | 외부 평면 전수(커버리지 매핑표 §11)·검증된 샘플·합성 미디어·수신 단언 원칙 (2026-06-13 신설) |
| `guide/CAPACITY_GUIDE_FOR_AI.md` | **성능시험 / capacity / 부하시험** | `oxlab cap` 3축(방송/무전/회의) N 스윕·복호-skip·active/N 신뢰성·봇 vs SFU 병목 분리·멀티머신 확장 (2026-06-13 신설) |

---


## 프로젝트 개요

- **목적**: 상용화 목적의 경량 Conference SFU 서버 + PTT 확장
- **타겟**: B2B
- **규모**: 상용 상한 1만 user (cross-room × SFU 3~5대로 커버). 초과 시 영업상 거절. 방당 인원 균등 배치 유도가 서비스 방침 (도메인 특성 아님 — 시장 축소 금지 원칙). 한 방이 단일 SFU 초과하는 cascading 시나리오는 영업상 회피, 설계 불필요.
- **개발자**: kodeholic (GitHub)

---

## 프로젝트 구성

| 항목 | 로컬 경로 | 설명 |
|------|-----------|------|
| 서버 | `/Users/tgkang/repository/oxlens-sfu-server` | Cargo workspace (common + oxsig + oxrtc + oxsfud + oxhubd + oxcccd + oxe2e + **oxadmin** 운영 CLI) |
| 웹 클라이언트 | `/Users/tgkang/repository/oxlens-home` | Vanilla JS + Tailwind. 활성 SDK = sdk/ (전면 재작성, 설계 20260603). core/ 레거시 |
| SDK 코어 | `/Users/tgkang/repository/oxlens-sdk-core` | Android Kotlin SDK (libwebrtc 기반) |
| 랩스 | `/Users/tgkang/repository/oxlens-sfu-labs` | Cargo workspace (E2E, 벤치마크, OxLabs 품질 루프) |

---

## 서버 소스 구조 (oxlens-sfu-server, Cargo workspace)

→ **[PROJECT_SERVER.md](PROJECT_SERVER.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## 웹 클라이언트 구조 (oxlens-home, 신 SDK = sdk/)

→ **[PROJECT_WEB.md](PROJECT_WEB.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## 신 SDK 아키텍처 (6 평면 + 3 확장 훅)

→ **[PROJECT_WEB.md](PROJECT_WEB.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## 시그널링 프로토콜 (v3 wire, 2026-05-16)

**v3 wire**: 8B 바이너리 헤더 + 16진 opcode 카탈로그 + ACK 의무화 + WS Binary 단일.
헤더 byte 배치: `[ver(1)=0x01, flags(1)=ACK_STATE|PRIO, op(2 BE), pid(4 BE)]` + payload(JSON or binary).
외부 호환 Packet v2 (`{op,pid,ok,d}`) 보존 — handler 호출처 마이그 부담 거의 0.
ACK: 모든 메시지의 `ok` 필드 기반 대칭 ACK. `flags.ACK_STATE` 로 요청/응답 구분.
설계서: `context/design/20260516_signaling_v3.md`, `context/design/wire_v3_catalog.md`

### opcode 카테고리 (상위 nibble)

```
0x0000~0x00FF  Handshake     (pid=0, ACK 없음, hub 로컬, body=JSON)
0x0100~0x01FF  Session       (ACK 필수, hub 로컬, body=JSON)
0x1000~0x1FFF  Request       (C→S, ACK = 응답, body=JSON)
0x2000~0x2FFF  Event         (S→C, ACK 필수, body=JSON, FLOOR_MBCP 만 binary)
0x3000~0x3FFF  Admin Event   (S→admin)
0xE000~0xEFFF  Internal      (hub↔sfud, 클라 비노출)
0xF000~0xFFFF  Error         (양방향, 종결)
```

두 번째 nibble = 도메인. Request: 1=Room(0x10)·Media(0x11), 2=Scope, 3=Data, 7=Extension. Event: 1=Room(0x20)·Media(0x21), 2=Scope, 3=Data, 4=Floor, 5=Speakers, 7=Extension.

카테고리 nibble 하나로 dispatch / 방향 / pid 부여 / ACK / priority / intent 전부 lookup. flag 비트 신설 금지가 v3 도그마. 총 **44 op** (ADMIN_REAP `0x3004` 추가, 20260613). 새 op 추가 시 `oxsig::opcode::ALL_OPS` + `context/design/wire_v3_catalog.md` 동시 갱신.

### Handshake / Session (Control)
| op | 이름 | 설명 |
|---|---|---|
| 0x0001 | HELLO | heartbeat_interval 전달 (S→C) |
| 0x0002 | IDENTIFY | 인증 (C→S, extra 필드 지원) |
| 0x0003 | IDENTIFY_RESULT | 인증 결과 (S→C) |
| 0x0101 | HEARTBEAT | 생존 확인 (hub 전용, sfud touch 안 함) |
| 0x0102 | TOKEN_REFRESH | JWT 갱신 |
| 0x0103 | RECONNECT | 세션 복구 (shadow 기반) |

### Request (Client → Server, 0x1xxx)
| op | 이름 | 설명 |
|---|---|---|
| 0x1001 | ROOM_LIST | 방 목록 요청 |
| 0x1002 | ROOM_CREATE | 방 생성 (extra 필드 지원) |
| 0x1003 | ROOM_JOIN | 방 입장 → server_config + scope 스냅샷 동봉. `select` 플래그(기본 true=발언방 지정, `select:false`=청취 affiliate) — **auto-select 폐기(S-e, 0610)**, 명시 select 만 |
| 0x1004 | ROOM_LEAVE | 방 퇴장 |
| 0x1005 | ROOM_SYNC | 참여자+트랙+floor 전체 동기화 (폴링) |
| 0x1101 | PUBLISH_TRACKS | 트랙 의도 (duplex/simulcast 명시, 증분 add/remove, **per-track tracks[].mid** 0611). PublishContext atomic store + PublisherStream/placeholder 등록. ⚠ **tracks[].codec 사실상 필수** — 미지정 시 서버 묵시 VP8 등록 → 실 인코딩(H264)과 어긋나 구독자 디코딩 0(0613 검은 화면 근본 원인. 서버 offer-pt 판별 전환은 이월) |
| 0x1102 | TRACKS_READY | subscribe SDP renego 완료 후 발행 (구 TRACKS_ACK 개명 — wire ACK 와 application READY 분리, SMS submit/status-report 패턴). SubscriberGate resume + GATE:PLI 트리거 |
| 0x1103 | MUTE_UPDATE | (하위호환 잔존) 클라 송신 폐기 — G1(0609) TRACK_STATE_REQ body 분기(`{muted?}`)로 통합 |
| 0x1104 | CAMERA_READY | 카메라 웜업 완료 → PLI 트리거 |
| 0x1105 | SUBSCRIBE_LAYER | Simulcast 레이어 선택 (h/l/pause, targets 배치 지원) |
| 0x1106 | TRACK_STATE_REQ | 트랙 상태 단일 경로 — body 분기 `{muted?}`(mute, G1 0609 MUTE_UPDATE 흡수) / `{duplex?}`(half↔full 전환). full→half 캐싱 보존 + active:false 통지, half→full 보존 stream 자동 재송출. 식별 = track_id 우선(ssrc 는 폴백+echo — 0613 확인). **room_id 필수**(F11 hub 라우팅) |
| 0x1200 | SCOPE | scope 변경 (body `mode: "update"` 증분 / `"set"` 전체). sub = `sub_add`/`sub_remove`, **pub = `pub_select`/`pub_deselect`**(S-e~S-g, 0610 — auto-select 폐기. cross-sfu 발언 전환 = 이전 sfud pub_deselect + 새 sfud pub_select 분할 송신). 응답에 scope 스냅샷 |
| 0x1301 | MESSAGE | 텍스트 메시지 |
| 0x1302 | TELEMETRY | 클라이언트 telemetry 보고 |
| 0x1303 | ANNOTATE | Canvas Annotation (action: stroke/clear/zoom, 순수 relay) |
| 0x1304 | CLIENT_EVENT | 클라 사건 보고 (배치, fire-and-forget, priority P2). event-reporter → agg-log 녹임 + admin |
| 0x1701 | MODERATE | Moderated Floor Control (grant/revoke/hand, hub-local Extension) |
| 0x1702 | TRACK_DUMP_REPLY | Track Dump 진단 응답 (REQ/REPLY 매칭은 body `dump_id: u32`, wire pid 와 분리) |

### Event (Server → Client, 0x2xxx)
| op | 이름 | 설명 |
|---|---|---|
| 0x2001 | ROOM_EVENT | 입장/퇴장/설정변경 (action 분기) |
| 0x2101 | TRACKS_UPDATE | 트랙 추가/제거/duplex_changed (per-user **per-track mid** — top-level audio_mid/video_mid 폐기, 0611) |
| 0x2102 | TRACK_STATE | 트랙 상태 통지 — mute(`muted` 필드) + duplex active/inactive(`active`+`source`+`duplex` 필드, 2026-05-31) |
| 0x2103 | VIDEO_SUSPENDED | 비디오 중단 → avatar 전환 |
| 0x2104 | VIDEO_RESUMED | 비디오 재개 |
| 0x2105 | TRACK_STALLED | 미디어 정체 감지 알림 (ssrc 목록) |
| 0x2106 | LAYER_CHANGED | Simulcast 레이어 전환 통보 |
| 0x2200 | SCOPE_EVENT | scope 변경 broadcast — payload `{sub, pub(0/1-elem vec), cause, change_id}` (`sub_set_id`/`pub_set_id` 폐기 — RoomSetId 제거 동반, 0602e). 서버 미emit 상태(S-d 설계 대기) — 클라는 수신 시 보고만 |
| 0x2301 | MESSAGE_EVENT | 메시지 브로드캐스트 |
| 0x2302 | ANNOTATE_EVENT | Annotation 브로드캐스트 (action 분기, 서버 무상태) |
| 0x2400 | FLOOR_MBCP | **body=binary** MBCP TLV (TS 24.380). 구 FLOOR_TAKEN(141)/IDLE(142)/REVOKE(143)/Queue Info 통합 — 메시지 종류는 MBCP body 안 self-describing |
| 0x2500 | ACTIVE_SPEAKERS | Active Speaker 목록 (RFC 6464). Event=ACK 대칭(windowed) |
| 0x2700 | MODERATE_EVENT | Moderated Floor 이벤트 (authorized/unauthorized/speakers, hub-local) |
| 0x2701 | TRACK_DUMP_REQ | Track Dump 진단 요청 broadcast (hub → 방 안 모든 클라, hub-local Extension) |

### Admin / Internal / Error
| op | 이름 | 설명 |
|---|---|---|
| 0x3001 | ADMIN_TELEMETRY | 어드민 telemetry 중계 |
| 0x3002 | ADMIN_SNAPSHOT | 어드민 스냅샷 (방 + User 뷰). hub admin REST track-dump + oxadmin room snapshot |
| 0x3003 | ADMIN_METRICS | 어드민 SfuMetrics + HubMetrics flush |
| 0x3004 | ADMIN_REAP | 좀비 퇴장 강제 (admin→sfud, evict_user_from_room. oxadmin reap, 20260613). 대상 = `target_user`(body.user_id 는 envelope user 로 덮어써짐) |
| 0xE001 | SESSION_DISCONNECT | hub→sfud WS 끊김 통보 (Internal, 클라 비노출. sfud 는 인지+로깅만, 삭제 안 함) |
| 0xF001 | ERROR | 양방향, 종결 |

> **Floor Control 일원화**: WS JSON Floor path 완전 삭제 + FLOOR_TAKEN/IDLE/REVOKE 3 op 통합. Floor Control 은 DataChannel MBCP(TS 24.380) 전용 (0x2400 FLOOR_MBCP). bearer=ws fallback 시에도 동일 MBCP 바이너리를 WS binary 프레임으로 전달.

> **v2 → v3 핵심 매핑** (참고): TRACKS_ACK(16) → TRACKS_READY(0x1102), SCOPE_UPDATE(53)+SCOPE_SET(54) → SCOPE(0x1200)+`mode` 분기, FLOOR_TAKEN/IDLE/REVOKE(141~143)+FLOOR_QUEUE_POS(43) → FLOOR_MBCP(0x2400)+MBCP type self-describing, SESSION_END(dead) cleanup. body=JSON 기본 + 0x2400 만 binary.

---

## 미디어 아키텍처

→ **[PROJECT_SERVER.md](PROJECT_SERVER.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## oxhubd — WS 게이트웨이 + Extension

→ **[PROJECT_SERVER.md](PROJECT_SERVER.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## 현재 상태

서버 버전 / 구현 완료 / 할 일 등 진행 상태는 전부 `context/SESSION_INDEX.md` + `context/202606/` 세션 파일을 **단일 출처**로 한다. 본 마스터 문서에는 절대 중복 기록하지 않는다. 의심 시 `context/YYYYMM/` 파일 직접 확인을 SESSION_INDEX 조회보다 우선.

## Peer 재설계 원칙 (장기 출처)

→ **[PROJECT_SERVER.md](PROJECT_SERVER.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## 마일스톤

큰 단계의 완료/진입만 한 줄 단위로 박는다. 세부 진척은 `context/SESSION_INDEX.md` 단일 출처.

- ✅ **Track Lifecycle redesign** (rev.3, ~2026-04-29) — Phase 1~5 (Slot 도입 / 메서드 활성화 / SubscriberStream / fanout 분기 제거 / SWITCH_DUPLEX op=52 폐기) 전부 완료.
- ✅ **Rewriter 일반화 Phase ①** (2026-04-30) — `RtpRewriter` 공통 토대 + `Ptt`/`Simulcast` wrapper 마이그 + `SubscribeMode` enum 단일 출처 + PT 정적 매핑 + vssrc 분류 cleanup + Step C `advance_phase(Active)` 보강 (`publisher_stream.rs::fanout` L444, RTP 단일 진입점). 252 tests PASS. 잔여 0.
- ✅ **Phase ①.5 Cross-room PTT slot 일반화** (2026-05-02) — universal PTT vssrc/track_id/mid 상수 폐기. `Slot.virtual_ssrc` per-room random alloc + `ptt-{room_id}-audio/video` 경로별 track_id + `MidPool::with_reserved_start` 폐기 + `collect_subscribe_tracks` sub_rooms 순회 + `build_remove_tracks` room_id 인자 + cross-room leave 시 leaver SDP 정리 emit. 7 파일 ~200L. 252 tests PASS. Axiom 2 한계 해소. 한방 git commit 박음 (Track Lifecycle rev.3 + Rewriter ① + ①.5 누적) + push 완료.
- ✅ **Phase ①.5b inner SSRC 정합 보강** (2026-05-09) — 5/2 한방 commit 의 부분 적용 영역 (`PttRewriter::new_audio/new_video` 가 universal `PTT_AUDIO_SSRC` default 호출) 보강. 부장님 grep 한 번이 잡음. `Slot.virtual_ssrc` (per-room) ≠ `Slot.rewriter.inner.virtual_ssrc` (universal) 불일치 → wire-level RTP SSRC 가 universal 그대로 였던 회귀 fix. 3 파일 ~12L 코드 + ~10L 주석 (ptt_rewriter.rs 시그너처 변경 + slot.rs 인자 전달 + 주석 3건). 252 tests PASS. 일반 commit + push 완료.
- ⏳ **Phase ①.5 웹 클라 정합** (2026-05-02 commit + 2026-05-03 단일방 검증 통과) — 서버 per-room 자료구조와 정합. constants.js (PTT 상수 6개 폐지 + regex 매칭) + engine.js (`_pttPipes` Map<roomId,{audio,video}> 전환 + 메서드 5개 재작성) + room.js (호출처 roomId 전달 + remove PTT 분기 신설). 3 파일 ~150L. 단일방 6/6 스모크 통과 (test_phase15_smoke.html 자동 실행 페이지). cross-room 시험 보류.
- ✅ **묶음 1 모델 단순화** (2026-05-17, `bfeb987`) — Pan-Floor 모듈 + Cross-Room publish (pub_set scope) 폐기. 208 PASS.
- ✅ **묶음 2 코드/주석 청결성** (2026-05-17, `bfeb987`) — dead_code attribute / 이주 묘비 / Pan TLV 청산. 18 파일 -777줄 net. 195 PASS.
- ✅ **묶음 3 자료구조 일관성 ① — pub_room 단수 정합** (2026-05-17, `4a5b7f3`) — `pub_rooms: ArcSwap<RoomSet>` → `pub_room: ArcSwap<Option<RoomId>>` (1방 발언 타입 강제). Peer mutation 일원화 (register_publisher_stream / remove_subscriber_streams_by_mids). SubscriberGate HashMap → AtomicBool 단순화. TrackSnapshot → PublisherStreamSnapshot rename. 189 PASS.
- ✅ **묶음 4 PLI Governor 통합 + F8 해소** (2026-05-17, 7 commits) — SubscriberStream.pli_state 신설 (mode 무관). send_pli_to_publishers 본문에 judge_server_pli 통합. gate.resume 후 sub_state symmetric reset. 192 PASS.
- ✅ **묶음 6 Hook 본문 + State 천이 agg-log + hooks/floor.rs 빈 틀** (2026-05-17, 5 commits) — track:publish_active / subscribe:active agg-log 신설. on_peer_phase 빈 채 유지 (reaper 인라인 정합). hooks/floor.rs 미래 횡단 관심사 정합. 194 PASS.
- ✅ **묶음 7 scope 통지 흔적 제거 (YAGNI 정합)** (2026-05-17, `20260519c`) — `handle_scope_announce_for_room` 빈 placeholder + TODO 제거 + spawn 호출 1줄 제거 + 4 파일 주석 정리. 부장님 *"다채널 수신 처리할 때 자연 발굴"* 원칙 적용. -7줄 net, 194 PASS.
- ✅ **묶음 8 운영성 마무리** (2026-05-17, `20260520a`) — F26 ingress_mbcp.rs dead 파일 청소 (-107줄) + 주요 모듈 5개 `//!` 표준화 + `context/design/wire_v3_catalog.md` 신설 (275줄, 18 섹션) + PROJECT_MASTER E-1 명세 7항목 반영. 194 PASS.
- ✅ **F29 participant.rs 해체** (2026-05-18, 4 commits) — 자료 16건 → 4 모듈 이주 (publisher_stream.rs 6 / subscriber_stream.rs 3 / tasks.rs 1 / peer.rs 6). participant.rs 936줄 → 308줄 (-628, 66% 감소). RoomMember + SubscribePipelineStats / Snapshot 만 잔존. 194 PASS. *김대리 권고 + 부장님 결재 + 김과장 mechanical refactor* 분업 체계 100% 적용.
- ✅ **F28 race 해소 + F29-a 모듈 doc 정합** (2026-05-18, 2 commits) — `serial_test` dev-dependency + `#[serial]` 매크로 2자리. participant.rs / peer.rs 모듈 doc 갱신 (F29 정책 반영 + `pub use re-export` 예외 명시). production 코드 변경 0, 194 PASS × 10회.
- ✅ **oxlens-home v3 마이그 Phase 1** (2026-05-18, 0518e) — 클라 측 Signaling v3 진입. wire.js 신규 + constants.js v3 16진 opcode 카테고리 전환 + signaling.js binary frame 재작성 + Pan-Floor (svc=0x03) 전체 폐기 (datachannel.js TLV 4건 + floor-fsm.js FSM 영역 + scope.js panRequest/panRelease wrapper + sdp-negotiator.js svc=0x03 분기). 5 commits 누적 +341/-767, sdp-builder 82/82 + wire round-trip 5/5 PASS.
- ✅ **wire 헤더 byte 배치 정정 + Track Dump 인프라** (2026-05-20, 0520b) — 클라 잠복 결함 `[op,pid,flags,ver]` → 서버/설계서 정합 `[ver,flags,op,pid]` / `VER_V3=0x01` 통일. Track Dump 인프라 신규 (Phase 1 서버 oxsig 2 op + oxhubd track_dump ~340줄 + REST handler + WS REPLY 분기 / Phase 2 SDK track-dump-collector ~280줄 / Phase 3 어드민 render-track-dump ~230줄). 279 PASS.
- ⏳ **Track Dump v2.2 재설계** (2026-05-20~21, 0520c~d, **미완료**) — v1 결함 5건 짚음 → v2/v2.1/v2.2 정정. canonical source = `getStats() outbound-rtp/inbound-rtp` 확정 (RTCRtpSender.getParameters ssrc 미노출 — W3C webrtc-pc #1174). `collectIdentityFromStats(stats,mid,role)` 신규 + simulcast layer 다중 자료 mid 매칭. 단위 시험 33 PASS. 어드민 매트릭스 cli-pub null (track_id ID 체계 불일치), 자료구조 거짓말 잔재 노출 → Phase 111 정정 진입 신호.
- ✅ **재입장 영상 미노출 100% 재연 버그 정정** (2026-05-21, 0521a, `fe5bd04` + `afb0ab5`) — 본질 = `mid_map`/`mid_pool`/`SubscriberStreamIndex` 비대칭. evict/zombie reaper/handle_room_leave 세 정리 흐름이 mid_map+mid_pool 만 정리, Index 정리 누락 → 재입장 idempotent 분기가 옛 publisher_ref 잔재 반환. 3곳 정정 (helpers.rs:603 Take-over / tasks.rs:524 zombie / room_ops.rs:437 정상 LEAVE) + 클라 `TRACKS_READY` opcode 정정 + 어드민 매트릭스 8 보강. 서버 279 / 클라 176 PASS.
- ✅ **ingress.rs SRP + RTX 통합 청산** (2026-05-21, 0521b) — 설계 v1→v4 4차 정정 (업계 3장 조사). Phase A 4파일 분리 (`ingress.rs` 946→211 / `ingress_publish.rs` 신규 475 / `ingress_rtcp.rs` 신규 236). Phase B 의사결정 헬퍼 2 (`decide_rid_promotion` / `evaluate_publisher_floor`). Phase E NackGenerator 본 토대 (publisher 측 손실 감지 + bwe_timer 합류). Phase D enum 4 신설 + `Room::lookup_publisher_for_ssrc` 통합 lookup. Phase C `process_rtx_packet` (RFC 4588 디캡슐 + cache 512→1024 + audio cache). Phase F 단위 시험 18. 194 → 212 PASS.
- ✅ **ingress 계층구조 정합 + 진단 로그 청산** (2026-05-21~23, 0521c, `30b546c` + `94ff5c5`) — Phase 1 `Peer::pub_room` → `PublishContext::pub_room` 이전 + `Peer::publish_room()` 단일 진입 헬퍼 (publish 자료 home 일원화). Phase 2 `first_room_hint` 함수 폐기. Phase 3 RoomMember → Peer 시그너처 축소 5함수. Phase 4 `[DBG:RTP]` 진단 로그 청산 (`is_detail`/`seq_num` 인자 7 함수 + `dbg_rtp_count` 필드 폐기 + `update_speaker_tracker` / `detect_video_rtp_gap` 헬퍼 분리). §10 후속 (0523): `pub_stats` 이전 + RoomMember 위임 메서드 5 폐기. 31 files / +270 / −388 / 118줄 순감소. 212 PASS 일관.
- ✅ **옛 commit 본질 후퇴 정정 3건** (2026-05-24, `24b2bf5` + `53aea9c` + `81a99c4`) — `AckState` → `WireAckState` 본명 정합 (11파일/83자리). `release_subscribe_track` 본문 순서 정렬 (mid_map → SubscriberStreamIndex → mid_pool — mid_pool.release 가 다음 add 시작 신호이므로 Index 먼저 깨끗해야 idempotent 분기 잔재 차단). `emit_leaver_room_remove` 단일 진입점 통합 (helpers/tasks/room_ops/leaver-emit 4 호출처 → release_subscribe_track 호출). 299 PASS.
- ✅ **bitmask 버그 정정 (RTCP PSFB 필터)** (2026-05-29, `b811543`) — `relay_subscribe_rtcp_blocks` 의 PLI throttle 필터가 RTCP PT 에 `& 0x7F` 적용 → PSFB(206)가 78로 마스킹되어 throttle 무력. RTCP PT 는 byte[1] 8비트 전부 (marker bit 분리는 RTP 전용). 동작 변경 = PLI throttling 실제 작동. 메트릭(`pli.sent`/`throttled`)이 결정 지점에서 세서 거짓 정상 보고하던 자리.
- ✅ **catch 2 MediaIntent 분해/폐기** (2026-05-29, `37539e0`~`98f2431` 6 commit) — MediaIntent struct 폐기(축소 잔존). extmap 4종 + audio_mid/audio_duplex → PublishContext atomic 이전, video_sources 트랙 메타 → PublisherStream 흡수(mid 필드 신설), simulcast placeholder 사전등록(sentinel ssrc `0xF000_0000|counter`, mediasoup NewRtpStream 정합). 핫패스 `stream_map.lock()` 0건 — 매 RTP lock+clone allocation 폐기. 211 PASS (self-test 7 자연 소멸, production 0). 동작 변경 1건 = simulcast 등록 시점 RTP-first→PUBLISH_TRACKS. E2E verify 보류.
- ✅ **Publisher 2계층 전환** (2026-05-30) — `PublishContext ⊃ PublisherStream(논리, camera/screen) ⊃ PublisherTrack(물리, SSRC)`. 구 `PublisherStream`(SSRC) → `PublisherTrack` rename + 논리 `PublisherStream` 신설 (`(source, kind)` 묶음, `PublisherTrack` 는 `stream: Weak` 역참조). `pli_state`/`pli_burst_handle`/`last_pli_relay_ms`/`simulcast_pli_pending` 을 publisher-단일 → 논리 Stream(source) 단위로 이주 → **명제 B 해결** (camera/screen 이 같은 `PliPublisherState.layers[High]` 공유 → screen keyframe 이 camera pending 거짓 해제하던 오염 차단) + catch 4 흡수. `recv_stats` DashMap → 각 `PublisherTrack` 1:1 귀속 (RR 은 비-RTX Track 순회, media SSRC 당 1). `simulcast_group` 약한 끈 폐기. 4 stage (① rename ② 논리 신설+PLI 이주 ③ 명명 청산 `streams`=논리/`tracks`=물리 ④ recv_stats+cleanup). 211 PASS, Stage 1~4 배선 완료 (커밋 `96ded24`). **회귀 대기** — camera+screen oxe2e 시나리오 + 브라우저 명제 B 실증(admin `pli_state` dump) 미완.
- ✅ **Duplex Activeness (half↔full 전환) 서버 3단계** (2026-05-31) — Phase 1 분류 권위 `TrackType` 단일화 (fanout/forward 분기를 `track_type()` match 로, is_half/is_simulcast_video 재조합 폐기) → Phase 2 full→half 캐싱 (republish 폐기 → 개인 SubscriberStream/mid 보존 + collect `active:false` 생명주기 기준 C) → Phase 3 `TRACK_STATE_REQ`(0x1106) 신설 + half→full 복귀(보존 Weak 자동 재송출) + 통지(결정 D: full→half active:false / half→full active:true·신규 sub add) + PUBLISH_TRACKS hot-swap 분리(이중화 금지). oxsig 54 + oxsfud 211 PASS + 회귀(conf_basic/ptt_rapid) 무변경 + duplex_cache 신규 e2e(음성 대조 FAIL 로 판별성). 클라(TRACK_STATE_REQ 발신·통지·UI 전환) + 신규 sub add 실행 검증 = 별도.
- ✅ **통계 자료구조 트랙 차원 정렬** (2026-06-02, 0602b~c) — RecvStats→RrStats/SendStats→SrStats 개명 + `room_stats` DashMap 잉여 제거(sr_stats/stalled/stats_primed 직속 + room_id 정체 필드 승격) + 텔레메트리 PublishPipelineStats→PublisherTrack / SubscribePipelineStats→SubscriberStream 직속(pub/sub 대칭, rtx_received dead 삭제). 동작 0, test 211, oxe2e 4/4. 설계자 "DashMap 죽은 차원" 오류 적발(room_id 값은 산 자료).
- ✅ **domain/ 파편·래퍼 정리** (2026-06-02, 0602d~e) — ① enum 5종 → `domain/types.rs` 단일출처(stream_map.rs 폐기) ② `room/`→`domain/` rename ③ scope.rs 폐기(RoomSet/RoomSetId 래퍼 제거, sub_rooms→bare HashSet, set_id wire 폐기 — 다방 청취 유지). test 205, oxe2e 4/4.
- ✅ **Track State 통일 + 식별 계층(track_id/vssrc) 재설계 — 서버 A·B** (2026-06-03) — 식별 3평면 분리(track_id 불투명·vssrc 값 → 논리 PublisherStream / 실 ssrc → 물리 PublisherTrack). A 식별 이주(`8b0627a`) + B 발신/통지/응답 Stream 단위(`208a498`, mute/duplex Stream 단위·응답 d.tracks·self-unicast 폐기). test 204, oxe2e 4/4. 회귀 강화(judge 통지 track_id 검증). 클라(transceiver.mid·setTrackState·TRACK_STATE 수신) = 별 세션.
- ✅ **Cross-SFU Phase 0~2b + Supervisor** (2026-06-03) — 단일 hub + N sfud(room→sfu 1:1, RoundRobin place_room), oxhubd supervisor(자식 sfud spawn/감시/backoff). 상세 [PROJECT_SERVER.md](PROJECT_SERVER.md).
- ✅ **웹 신 SDK 전면 재작성 (sdk/)** (2026-06-03~13, Phase 147~154) — 설계 `20260603_client_rewrite_core_design.md`. C1~C7 API 계열 + **헌법 5조**(권위 파생/단일 게이트/SerialLock/식별 4평면/연결 3종) + 글로벌 EventBus 완전 폐기 + talkgroups(방 관계 권위, applyEvent/reconcile) + 복구 R1/R2(RESYNC 금지) + e2e 브라우저 하니스 14케이스 + 미디어 평면(소생/장치상실 복구/하이브리드 장치 정책/blockedBy) + 발행 트랜잭션(trackKey 키잉/단일 청소). 상세 [PROJECT_WEB.md](PROJECT_WEB.md).
- ✅ **scope wire S-a~S-g + F11 + per-track mid** (2026-06-09~11) — auto-select 폐기(명시 select), SCOPE pub_select/pub_deselect(cross-sfu 분할 송신), sfud행 op room_id 필수(다방 배달 F11), top-level audio_mid/video_mid 폐기.
- ✅ **검은 화면(수신 video 디코딩 0) 해결** (2026-06-13) — 2겹: TRACKS_READY 포팅 갭(클라 미송신 → gate resume/PLI 부재) + 배치 발행 codec 폴백 부재(서버 묵시 VP8 오등록 vs 실 인코딩 H264). CONF-2/3 라이브 PASS. 디버깅 확인 사항 = `guide/MEDIA_DEBUG_GUIDE_FOR_AI.md`.
- ✅ **성능(capacity) 측정기 — 봇 wire v3 재배선 + 3축 + 분산** (2026-06-13, labs `8749d9d`) — oxlab-bot 을 wire v3(oxsig path 참조·hub 1974)로 재배선하고 `oxlab cap` N 스윕 부하 측정기 신설. 3축(broadcast egress / ptt slot / conf mesh) + 복호-skip(Count/Full) + send-ts latency. **reaper 회피 = 봇 STUN consent 주기 전송**(송신0 sub 가 idle 시 zombie 되던 것 — ready-sync 회귀 진범). 봇/SFU 병목 분리 = active/N + 봇·sfud CPU/mem(sysinfo). 분산 인프라(`cap-dist`/`cap-worker`, 멀티머신 ssh). 단일 머신 DTLS setup 천장 ~200(SFU 진짜 천장은 멀티머신 필요). bench·e2e-ptt(v2 wire 화석) 폐기. **업계 3인방 부하시험 대조**(LiveKit `lk load-test` 합성미디어 16core 3000sub / mediasoup ~500consumer/worker / Janus Jattack 실transport 1000viewer·생성기 CPU>SFU / CoSMo 실브라우저 분산) — DTLS 생성기 병목은 업계 공통, 복호-skip+active/N 병목분리가 우리 차별점. 가이드 `guide/CAPACITY_GUIDE_FOR_AI.md` §7.
- ⏸ **Phase ② Hall** — 부장님 명시(2026-05-02): 먼 미래로 보류.

---

## Scope 모델 (Cross-Room rev.2, 2026-04-23 + 묶음 1 Phase A, 2026-05-18)

→ **[PROJECT_SERVER.md](PROJECT_SERVER.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## 프리셋 체계 (v2, 2026-04-12)

→ **[PROJECT_WEB.md](PROJECT_WEB.md)** 로 이동 (2026-06-03 분리). 상세는 그 파일 참조.

---

## Telemetry 체계

### Telemetry 프레임워크 (common::telemetry)
- `Counter`: AtomicU64 / `Gauge`: AtomicI64 / `TimingStat`: AtomicU64 (count<<32 | sum_ms)
- `Registry<T>`: OnceLock wrapper, static 접근
- `metrics_group!` 매크로: 카테고리별 구조체 자동 생성 + `flush()` JSON nested 구조

### SfuMetrics (oxsfud, static Registry)
- 카테고리: srtp, pli, rtcp, bwe, nack(flat merge), relay, track, codec, ptt, **dc**
- `METRICS.get().category.field.inc()` — Arc 전달 없이 어디서든 접근

### HubMetrics (oxhubd, Arc)
- 카테고리: ws, flow, grpc, auth, msg, stream
- sfud sfu_metrics flush 시 hub_metrics도 flush → 어드민에 병합 전송

### 클라이언트 수집 (telemetry.js → TELEMETRY 0x1302)
- Publish: packetsSent/Delta, retransmittedDelta, nackDelta, fps, encodeTime, qldDelta
- Subscribe: packetsReceived/Delta, packetsLost/Delta, lossRateDelta, jitter, jbDelay, nackDelta, fps, freeze
- Events 12종: quality_limit_change, pli_burst, nack_burst, bitrate_drop, video_freeze, loss_burst, video_recv_stall, critical_error 등

### 어드민 시각화 (demo/admin/)
- 개요 테이블 + 상세 패널 (publish/subscribe, 인코더 진단, 구간 손실 cross-reference)
- SFU 패널: SfuMetrics + Contract 체크 (15항목), nested JSON key 접근
- Hub Gateway 섹션, DC 섹션 (19 카운터)
- 통합 타임라인 (CLI + SFU 이벤트 병합), 스냅샷 (Track Identity + Governor/Gate + Hub Gateway + DC)
- Ring buffer: user별 20개 (60초분), SFU 20개. 3초 주기 room snapshot 갱신

---

## 시험 체계 (E2E / Smoke)

- **회귀시험 (oxe2e, 2026-05-30 신설)**: 단위(cargo test) ↔ 브라우저 E2E 중간의 헤드리스 회귀 gate. 헤드리스 봇이 구조 라우팅(fan-out/floor/gating)을 빠르게 검증 — 미디어 품질은 제외(브라우저 몫). conf_basic/ptt_rapid 커버. 가이드 `context/guide/REGRESSION_GUIDE_FOR_AI.md` (invoke "회귀시험").
- **성능(capacity) 시험 (oxlab cap, 2026-06-13 신설)**: 회귀(안 깨졌나)와 **다른 축** — 참여자 수 N 을 스윕해 SFU 천장을 곡선으로 찾는 부하 측정기(pass/fail 아님). 3축(방송/무전/회의) + 복호-skip. 가이드 `context/guide/CAPACITY_GUIDE_FOR_AI.md` (invoke "성능시험"/"capacity"/"부하시험").
- **정의**: 본 프로젝트에서 "E2E 테스트"와 "Smoke 테스트"는 **동일한 행위**를 가리킨다. 두 용어는 상호 교환 가능 — 별도 체계를 만들지 않는다.
- **단일 출처**: `context/guide/QA_GUIDE_FOR_AI.md` — 환경/도구/절차/오진 방지/불변식 체크 전부 이 문서가 단일 기준.
- **로드 의무**: 시험 세션 시작 전 반드시 QA_GUIDE 를 먼저 읽는다 (METRICS_GUIDE 와 같은 의무 규칙). 로드 없이 실행 금지.
- **인프라**: `oxlens-home/qa/` UI + `window.__qa__` API + admin WS 교차검증 (`ws://127.0.0.1:1974/media/admin/ws`). Playwright MCP 또는 Claude in Chrome 로 실행.
- **핵심 원칙 3 (QA_GUIDE §0)**:
  1. 서버 카운터로 교차검증 — client `getStats` 숫자만으로 원인 추정 금지. 항상 `__qa__.admin.sfu()` 로 교차.
  2. localhost 에서 물리 유실은 불가능 — `packetsLost` 는 seq 갭 해석. 원인은 논리(rewrite / self-skip / transition)에서 찾는다.
  3. "정상 패턴" 라벨 ≠ UX 면죄부 — 화이트리스트 항목(`audio_concealment`, `video_freeze during transitions`)이라도 사용자 체감 저하면 개선 대상.
- **적용 범위**: 시나리오 10종 회귀/smoke, 버그 재현, 배포 후 확인. 브라우저 기반 시험은 이 체계로만 돌린다.
- **브라우저 e2e 하니스 (oxlens-home/e2e/, 2026-06-10 신설)**: 외부평면 케이스 러너 14종(CONN/ROOM/CONF/MUTE/CAM/SCR/SW/PTT/TG/RECON) — 같은 페이지 합성 봇(canvas 타임코드/주파수 톤) + 라이브 타일 + 반복 통계. **CONF 는 framesDecoded>0 단언**(검은 화면 가드 — track 도착 단언만으론 검은 타일이 PASS). 수신 미디어 증상 디버깅은 `guide/MEDIA_DEBUG_GUIDE_FOR_AI.md` 선로드.
- **SDK 글루 검증 (oxlens-home/sdk/tests/, 0613 일원화)**: node mock 체크 19종(`node sdk/tests/<name>_check.mjs`) — 실 webrtc 없이 배선/계약 검증. 커밋 전 전체 PASS 의무.
- **비적용 범위**: Rust/JS 단위 테스트(`cargo test`, `core/*.test.mjs`), 성능 부하(oxlens-sfu-labs `oxlab cap` — `CAPACITY_GUIDE_FOR_AI.md`), Android SDK — 별도 체계.

---

## SDK 코어 (oxlens-sdk-core)

Android Kotlin SDK. libwebrtc AAR 기반.
- Jetpack Compose UI + Camera2 + Twilio AudioSwitch
- Telemetry (S/A/B/C + events + PTT diagnostics)
- 2PC SDP, Publish+Subscribe, Mute 3-state, PTT FloorFsm
- **미해결**: NetEQ deception (PTT 전환 시 RTX storm → NetEQ collapse)
  - libwebrtc custom build: oxlens-custom branch (529-line patch, 3 commits)

---

## 핵심 학습 & 원칙

### 김대리 행동 원칙

1. **자기 코드 → 선례 → 코딩** — 문제 발생 시 ①우리 코드에 이미 있는 메커니즘 먼저 확인 ②없으면 업계 선례(mediasoup/LiveKit/Janus) 조사 ③이해한 후 코딩. 순서가 바뀌면 있는 걸 또 만들거나 부순다.
2. **완료 = 끝까지 동작** — 로직만 있고 데이터가 안 들어가면 미완성. 시험 불가를 완료로 표시 금지.
3. **2회 실패 시 중단** — 같은 문제에 2회 시도 실패하면 "모릅니다" 하고 부장님께 접근 방향을 묻는다.
4. **성능 고려 코딩 시 힌트 제공** — atomic 변수 합치기, lock-free 패턴, 핫패스 lock 회피 등 설계 판단의 근거를 사전에 설명할 것.
5. **⭐⭐⭐⭐⭐ 스냅샷에서 출발한다** — 서버 로그를 먼저 뒤지지 않는다. 스냅샷 체인: AGG LOG → TRACK IDENTITY → SDP STATE → Subscribe/Publish → Pipeline Stats → 코드 경로. TRACK IDENTITY에서 문제의 6~7할 발견. `track:publish_intent`로 클라이언트/서버 책임 경계 판별. 환경 탓은 데이터 근거 없이 금지.
6. ⭐ 스냅샷 분석 전 `METRICS_GUIDE_FOR_AI.md`를 반드시 먼저 읽는다 — 가이드 없이 분석하면 매번 같은 오진을 반복한다.
7. **보고 종결 = 4-라벨 단일 ask** — 모든 보고는 마지막에 라벨 하나로 끝낸다:
   - **[결재]** 추천 단일안 + 기본동작. 포크가 있어도 default 를 박는다(메뉴 던지기 금지).
   - **[택1]** 진짜 부장 판단(설계 포크/사업/리스크 수용)일 때만. 각 trade-off 1줄 + 내 추천 명시.
   - **[질문]** 소스로 못 구하는 것 하나("X냐 Y냐").
   - **[보고]** 조치 불요 명시.
   **내가 풀 수 있는 결정은 바운스 금지** — 소스 확인/권한 내에서 풀어 *결과*를 보고한다. (작업지침 §3 결정추천의 대화 보고판.)

### 아키텍처 원칙 (반복 위험 높은 것만)
- **PT는 동적** — video/audio 판별에 PT 하드코딩 금지. `is_video_pt`/`is_audio_pt` 삭제됨
- **Simulcast SSRC는 SDP에 없다** — RTP rid extension 파싱 → 동적 매핑이 유일한 방법
- **SFU는 SR 자체생성 금지** — 서버 클록 NTP → jb_delay 폭등 (Janus PR #2007)
- **RESYNC(subscribe PC 재생성) 금지** — 기존 정상 스트림까지 파괴. mismatch tolerate가 정답
- **텔레메트리 ≠ 제어 신호** — 로직 데이터는 로직 경로에서 직접 수집. 텔레메트리를 읽어서 의사결정 금지
- **RTX는 모든 통계에서 제외** — recv_stats/send_stats 오염 방지
- **프리셋은 SDK 밖** — SDK는 Pipe primitive만. 프리셋/역할은 앱 레이어 JSON
- **admin ≠ dispatch** — admin은 SFU 운영자/개발자용, dispatch는 최종 사용자용
- **half-duplex → simulcast 강제 off** — PttRewriter + SimulcastRewriter 충돌 방지
- **audio=half + video=full 혼합 시 Power/Mute duplex 체크 필수**
- **clear_speaker()는 멱등** — speaker=None이면 silence flush 금지. 이중 호출 → jb_delay 폭증
- **카메라 토글 = mute 패턴** — `replaceTrack(null/track)`. addTransceiver 금지 (SSRC/BWE 보존)
- **mute 패턴 ≠ 자격 회수** — 카메라 토글은 replaceTrack, 자격 회수는 unpublishTracks
- **PTT audio `track.enabled`는 항상 true** — 서버 floor gating 담당
- **hub WS dispatch는 투명 프록시, Extension은 정책 수행** — sfud 미디어+상태 마스터 불변
- **자료구조 단일 출처 + 분류 권위 단일** — 같은 정보(simulcast 여부, duplex 등)가 N 곳에 표현되면 시점 race. **분기 판단은 단일 주체로** — fanout/forward 의 모드 분기 = publisher `TrackType`(FullNonSim/FullSim/HalfNonSim) 단일 권위, `publisher.track_type()` 파생 (Phase 1, 2026-05-31). subscriber 의 `via_slot:bool` + `forwarder:Option` 은 *자료* 로 등록 시점 1회 결정 후 불변 (구 `SubscribeMode` enum 은 catch 6 에서 자료로 응축, 분류 *판단* 은 TrackType 으로 복원 — "자료 단순화가 분류 권위를 흩는" 안티패턴 회피)
- **STALLED checker는 zombie reaper와 독립** — zombie=heartbeat, STALLED=미디어
- **PTT에서 원본 SSRC는 subscriber에게 relay 안 됨** — 가상 SSRC만 유효
- **ROOM_SYNC 실패 = 서버 버그** — 에스컬레이션은 증상 은폐
- **subscribe mid는 서버가 할당** — 클라 자체 할당 = m-line 무한 누적
- **MidPool은 kind별 분리 필수** — RFC 8843
- **room:joined는 subscribe PC 전에 emit** — 앱이 participants 먼저 채움
- **ensureHot은 duplex 변경 전에 호출** — `Pipe.duplex` 변경 후면 sender 못 찾음
- **PTT video element에 `display:none` 금지** — `left:-9999px` + `overflow:hidden` 사용
- **publish 재호출은 재발행이 아니라 소생** — SUSPENDED→resume / RELEASED→같은 sender 재장착(같은 SSRC, PUBLISH_TRACKS 불요). 새 발행 우회 = 좀비 transceiver (구 "resume 은 publishTracks 재전송" 원칙 폐기, 0612)
- **PC는 Transport 소유 (Engine/Room 아님)** — "나↔하나의 sfu" 물리 연결. cross-sfu = TransportSet 크기 N, 같은 sfu 멀티룸 = sub PC 공유 + recv pipe 합집합 1회 renego
- **sfud/hub lifecycle 독립 전이** — 각 데몬 독립 판단, 상대는 통보만, 제어 금지
- **HEARTBEAT는 sfud touch 안 함** — sfud liveness = STUN(UDP) 기반
- **disconnect → SESSION_DISCONNECT 통보만** — LeaveRoom 보내면 종속. zombie 자연 경로
- **`sender.replaceTrack` 직접 호출 금지** — Pipe Track Gateway가 유일 게이트
- **`getUserMedia` 직접 호출 금지** — MediaAcquire가 유일 게이트
- **connect(WS) → publish(media) 분리** — joinRoom 미디어 미포함
- **stream 보존 복구** — PC failed 시 track/stream 재사용 (getUserMedia 0ms)
- **PTT virtual track remove는 잔존자 체크 필수** — 안 하면 subscriber 영상 영구 미표시
- **앞단 완성 후 뒷단 고민 의미** — 분리 가능한 설계에서 뒷단을 미리 상세화하면 대부분 폐기된다. 앞단이 서면 뒷단의 제약이 드러나 자동으로 구체화됨 (Peer 재설계의 "one-shot" 원칙과 자매 — Peer 는 쪼갤 수 없어서 one-shot, Cross-SFU 는 분리 가능해서 순차)
- **byte-level wire 검증 = 서버/클라 대칭 보증의 유일 방법** — 각 언어 상수 조회만으론 불충분. 실제 `buildMsg()` 출력 바이트를 `assertEq(v[2], 13)` 식 직접 확인. 상수 일치와 wire 일치는 다른 문제
- **helper 추출로 분산 검증 재사용** — 같은 도메인 검증이 여러 전송 경로(DC + WS fallback)에 걸치면 helper 가 기본. `Peer::resolve_floor_target` 가 이 패턴
- **hook 분류 = 횡단 관심사 fire-and-forget 만. 주 흐름은 자기 도메인 모듈** (묶음 5 분류 오류 정합) — MBCP (3GPP TS 24.380) Granted/Taken/Idle/Revoke broadcast 같은 *PTT 표준 규격 = 주 흐름* 을 hook 으로 빼면 실패 격리 불가. hook 은 외부 webhook / OpenTelemetry / 분산 로깅 자리만
- **표현 정확도 — 폐기/이주/마이그/통합 동사 검증** (묶음 2 반성 정합) — commit 메시지 / doc 주석에서 "함수 9자리 폐기" 같은 표현은 실제 *함수 6 + 필드 3* 혼합 자리 였음. 동사가 자료 범위를 정확히 표현하는지 검증 의무
- **mechanical refactor 함정 — 옛 별칭/순서의 *의도* 점검 의무** (0524 반성 정합) — 별칭 폐기 시 *게으름 가명 vs 명료성 가명* 판정 누락이 반복 함정. 공통 함수 흡수 시 옛 코드 순서 *답습 vs 자료 의미 차원 정공* 판정. `release_subscribe_track` 본문 순서 (mid_map → SubscriberStreamIndex → mid_pool) 가 자료 의미 정공 사례 — mid_pool.release 가 다음 add 의 시작 신호이므로 Index 먼저 깨끗해야 idempotent 분기 잔재 차단
- **추상적 분리 작업 금지 — 진짜 가치 발현 시점까지 보류 (YAGNI)** (2026-05-18 부장님 결정) — 현재 면적으로는 분리 가치 없을 때 *미리 모듈 신설* 금지. 분리 트리거 (자료 추가 / 메서드 추가 / 면적 증가) 발생 시 자연 진입. 동일 원칙 — 묶음 5 분류 오류 원복 + 묶음 7 흔적 제거 + F30① peer_scope.rs / 9b last_seen 이주 기각 사례 정합
- **TRACKS_READY 는 application READY** (0613 실증) — subscribe 재협상 완료 시 클라 송신 의무. 서버 video gate 가 이 신호로 resume + PLI burst — 미송신이면 gate 타임아웃 후에도 키프레임 요청이 없어 수신 영상 영구 블랙
- **코덱 계약 3+1 한 몸** (0613 실증) — 클라 실 인코딩(setCodecPreferences 폴백 H264) = intent tracks[].codec(sugar/배치 폴백 H264) = 서버 등록 = 구독자 SDP 선언. 한 곳이라도 어긋나면 "패킷은 오는데 디코딩 0". 서버 묵시 VP8 기본은 함정(이월)
- **track 도착 단언 ≠ 영상 시험** (0613 실증) — STREAM_SUBSCRIBED/ontrack 은 SDP 산물. 영상 시험은 framesDecoded>0 까지(e2e CONF 검은 화면 가드). getStats 4축 분해(packetsReceived/framesDecoded/pliCount/codec mime)는 MEDIA_DEBUG_GUIDE
- **디버깅 전 환경 정합 0순위** (0613 실증) — 실행 중 프로세스 기동시각 vs 소스 HEAD, supervisor crash loop(고아 포트 점유), 클라 ES 모듈 캐시(포트 변경 우회), 클라 UTC vs 서버 KST. 오염 환경 위 디버깅은 전부 헛수고

> Peer 재설계 관련 원칙(Scope 타입 표현, PC pair = 1쌍, PC 종류 ≠ packet 방향, 편의 프록시 금지)은 위 "Peer 재설계 (완료)" 섹션에 단일 출처로 기술. 세부 원칙은 코드 주석 + `context/design/` 문서에 기록.

### 기각된 접근법 (반복 유혹이 높은 것만)

- **PT 하드코딩 판별** — is_video_pt/is_audio_pt 삭제 완료
- **SSRC 사전등록(simulcast)** — non-sim만 사전등록, sim은 RTP-first
- **subscribe PC 전체 재생성(RESYNC)** — decoded_delta=0
- **텔레메트리 기반 의사결정** — Governor가 Metrics 읽는 건 반칙
- **FloorService 물리적 분리** — PTT 레이턴시 재앙
- **mediasoup식 시그널링 마스터** — sfud가 상태 마스터 (PTT gating)
- **RoomMode를 default_duplex로** — 프리셋이 대체, 완전 제거
- **source 이름으로 simulcast 판단** — 클라이언트 명시가 정답
- **프리셋을 SDK 안에** — 시나리오/UI 종속
- **suspect_since를 enum + 시각 분리** — 단일 AtomicU64
- **reset_relay_timing()** — 근본 원인은 이중 silence flush
- **ingress에서 non-sim 트랙 등록** — track_ops 전담
- **gRPC typed proto 7서비스** — JSON passthrough 1서비스
- **HealthMonitor Phase 2/3** — ROOM_SYNC 실패=서버버그
- **standalone WS 모드** — hub 전담
- **Room-level MidPool** — per-subscriber가 정석
- **kind 무관 MidPool** — mid ↔ m=line kind 매핑 정합 깨짐 (RFC 8843 BUNDLE 안에서도 m=line 단위 kind 결정)
- **`display:none`으로 PTT video** — `left:-9999px` 확정
- **_pendingTracks 큐** — 이벤트 순서 보장이 근본
- **Room이 PC 소유** — Engine 소유
- **Transport 클래스 (mediasoup식)** — 2PC 고정, 추상화 과잉
- **PowerFsm → Pipe.transitionPower()** — God Object화
- **Pipe.toSubscribeTrack()** — SdpNegotiator 담당
- **클라이언트 mid 자체 할당** — 서버 할당이 정석
- **WS Floor fallback 유지** — DC-only가 정답. bearer=ws는 동일 바이너리를 WS binary로 전달
- **FLOOR_PING 유지** — RTP liveness가 정답 (hot path 0줄)
- **disconnect → LeaveRoom** — 종속. zombie 자연 경로
- **HEARTBEAT touch()** — sfud STUN 독립 관찰
- **`sender.replaceTrack` 직접 호출** — 산재되면 상태 추적 불가
- **`getUserMedia` 산재 호출** — MediaAcquire 단일 게이트
- **ICE restart로 주소 변경** — STUN consent check 자동 갱신. DemuxConn/DtlsSessionMap 갱신이면 충분
- **청중 중복 트랙 dedup (cross-room)** — SFU dumb 원칙, 앱에서 userId 기반 렌더
- **Endpoint 이름 유지** — 클라이언트 측 "연결 끝점" 의미와 혼동. `Peer`가 자연
- **DcChannel 이름** — "DataChannel Channel" 중복 표현. `DcState`가 정확
- **평탄 구조 + 주석으로 타협** — 구조가 의미를 표현하지 못하면 주석은 임시 반창고. 타입으로 scope 표현이 정답
- **Ingress/Egress를 PC 컨테이너 이름으로** — PC 종류와 packet 방향은 다른 축. `transport/udp/ingress.rs`와 이름 충돌. `Publish/SubscribeContext`가 정석
- **ScopeController 낙관적 업데이트** — affiliate 호출 즉시 sub.add 추가하면 §4.6 partial success 경로에서 상태가 분기. Server-authoritative 확정
- **flat scope API** (`engine.affiliate()` / `engine.select()` 등) — Engine 43KB 이미 비대, `select` 단어가 DOM/SQL select 자동완성 혼동. `engine.scope.*` 네임스페이스 그룹 확정
- **Hub scope_coordinator / 집계 레이어** — Floor 판정 방별 독립이라 불필요 (설계서 §6.2 rev.2). Hub 는 passthrough 유지
- **SCOPE_EVENT 방 단위 broadcast** — 집계 없이 요청자에게만 응답. 강제 변경(kick/moderate 회수/reconnect 복원)만 broadcast
- **Ghost Participant / Origin 축 / Peer enum Local/Remote 분기** — Cross-SFU 를 user 단위로 추적하려는 발상. 실제로는 room → SFU 매핑만 있으면 됨. user 단위 경계 관통 불필요 (설계서 20260424 §scope 경계)
- **Cross-SFU Phase A (hub 경유 미디어) + Phase B (direct) 양단계 로드맵** — B2B 소수 SFU 환경에서 Phase A 재사용 주장은 환상. 단일 Phase 로 충분. 측정 전 분기 금지
- **cross-sfu 용어 폐기** — 용어 통일 ≠ 용어 제거. cross-sfu ⊃ cross-room 전제 관계가 선명하도록 phase 번호로 명시 (cross-room phase 7 ← 기각, cross-sfu phase 1 ← 정답)
- **destinations + pub_set_id 공존 허용** — 의미 이중화. MUTEX 원칙과 충돌
- **MBCP 옵션 A (TS 24.380 표준 준수 재정렬)** — 메시지 타입/TLV 전면 재매핑 비용 대비 표준 단말 상호운용 이득 없음 (웹 브라우저 PTT 타겟). 옵션 B (자체 포맷 명시) 로 확정
- **SESSION_INDEX 만 보고 완료 판단** — 세션 압축 요약은 긍정 사례(완료) 누락 경향이 체계적. 완료 여부 의심 시 `context/YYYYMM/` 파일 직접 확인을 SESSION_INDEX 조회보다 우선
- **`Option<layer_entry>` 의 Some/None 으로 simulcast 여부 표현** — 첫 RTP 시점의 lazy create 결과가 영구화 → 시점 race. SubscribeMode enum 등록 시점 1회 결정이 정답
- **카운터로 race 검출 (scoped_nonsim_for_sim 등 추적 카운터)** — 자료구조 본질 fix 가 정답. 카운터는 race 가 일어나는 자료구조 위 임시 진단일 뿐, 디버깅 카운터 추가 루프는 안티패턴
- **MBCP 주 흐름을 hook 으로 이주 — 분류 오류** (묶음 5 원복) — PTT 표준 규격 broadcast 는 *주 흐름 자체*. hook = fire-and-forget 패턴 (실패 격리) 와 충돌. `hooks/floor.rs` 는 *진짜 횡단 관심사* 자리만 (외부 webhook / OpenTelemetry / 분산 로깅)
- **미리 만들어둔 빈 placeholder + TODO — YAGNI 위반** (묶음 7) — `handle_scope_announce_for_room` 같은 빈 본문 + TODO 마킹은 분류 오류 반복 위험. 진짜 다채널 수신 처리 진입 시 자연 발굴
- **on_peer_phase 본문에 agg-log 이주 — metadata 손실 vs 시그니처 확장 trade-off** (묶음 6) — hook 시그니처 `&'static str cause` 만으로는 reaper 안의 `last_seen_ago_ms` / `suspect_duration_ms` / rooms 목록 전달 불가. 시그니처 확장 면적 vs metadata 손실 trade-off 에서 *reaper 인라인 발행 유지* 우위
- **MediaIntent 완전 폐기 (extmap까지 제거)** (2026-05-29, catch 2) — simulcast RTP-first + audio_mid race 안전망이 잔존 강제. **축소 잔존** (struct 폐기 / extmap·audio_mid 는 PublishContext 잔존) 이 정답. PC pair 협상 메타는 SDP 결과라 PC pair-scope 유지 필요
- **MediaIntent 트랙 메타 유지 (catch 2 거부)** (2026-05-29) — 핫패스 lock+clone 영구 + 자료 단일출처 위반. 트랙 메타는 PublisherStream 흡수 (placeholder 사전등록으로 simulcast RTP-first 자료 carrier 역할 보존)
- **F30① peer_scope.rs 신설 — 시기상조 분리 기각** (2026-05-18) — 현재 peer.rs scope 영역이 자료 2 + primitive 6 만 — 분리 가치 발현 없음. F29 성공 후 *분리 모드 관성* 으로 권고했다가 부장님 *"무언가 추가될 때 분리"* 결정. 분리 트리거 (새 primitive / 새 자료 / cross-room 면적 증가 / peer.rs 안 scope 영역 300줄 초과) 발생 시 재진입
- **rVFC 첫 프레임 reveal 게이트** (0613) — 숨김(offscreen)·백그라운드 video 에서 rVFC 발화 미보장 → "보이려면 프레임, 콜백은 보여야" 순환 = 영구 미노출. 동기 즉시 적용 + 재설계 후보는 opacity 마스킹
- **DeviceManager static 전역화** (0613) — 세션 상태 보유자(_selected/_sinkUnsupported). 전역 접근 = "누가 부르는지 모르는 호출"(bus 폐기 교훈의 호출판). 직접 호출의 직관성은 조립부 주입으로 충족
- **mic-check 라이브러리 통째 흡수** (0612) — requestMediaPermissions 가 자체 getUserMedia 호출 = MediaAcquire 단일 게이트 충돌. 분류 매트릭스만 차용(code 축 보존 + blockedBy 별도 축)
- **오디오 입력 우선순위 자동 매니저(AudioSwitch 식) 웹 구현** (0612) — 업계(LiveKit 포함) 누구도 웹 SDK 레벨 미구현. OS default 추종 + 사용자 선택(하이브리드)이 표준
- **모바일 출력 라우팅(무전=스피커/통화=이어피스) 웹 강제** (0612) — setSinkId Android 불가, iOS26+ 만. 플랫폼 천장 — 모바일 현장 = 네이티브
- **active 축 완전 단일화(trackState 파생 getter)** (0613) — 발행 진행 window(active=true+INACTIVE)는 등록 축/미디어 축의 의도된 어긋남. 합치면 screen 이중 발행 가드 파손 + base 침습. 선택은 active, 결정은 trackState 전체 분기
- **9b last_seen MediaSession 이주 — 현 정책 정합 상태** (2026-05-18) — `Peer.last_seen` 와 `PublishContext.{last_video_rtp_ms, last_audio_arrival_us}` 가 이미 부분 분리 — user-scope max() 정책과 정합. MediaSession 안으로 이주 자체는 PC pair-scope 원칙 정합하나 현재 행동 변화 0. 분리 트리거 (Take-over 패턴 진입 / ICE migration 정밀화 / DTLS Failed 정밀화 / Admin PC 별 디버깅 수요) 발생 시 재진입

### 텔레메트리 철학
- "AI에게 오염된 정보를 주면 AI도 쓸모없어진다" — AI-Native 설계
- **텔레메트리는 사후 보고서이지 제어 신호가 아니다** (2026-03-31 확정)
- 스냅샷 분석 시 `context/guide/METRICS_GUIDE_FOR_AI.md`를 반드시 먼저 읽을 것

---

## 빌드 & 환경

- **macOS** (맥북) — 레포 루트: `/Users/tgkang/repository/`
- 서버: Cargo workspace (resolver="3"), Rust + Tokio + Axum + tonic + prost, 배포 타겟 RPi (aarch64)
- `.cargo/config.toml`: `+crt-static` 필수 (LiveKit 프리빌드 호환)
- Config: system.toml + policy.toml (.env / dotenvy 삭제됨)
- protobuf: `brew install protobuf` (tonic-build codegen)
- 풀 클린 빌드: 10~15분 / 증분: 수초
- 웹: Vanilla JS ES modules, Tailwind CSS, Phosphor Icons
- SDK: Kotlin, libwebrtc AAR, Jetpack Compose

---

## 코딩 규칙

- 파일 상단: `// author: kodeholic (powered by Claude)`
- 매직 넘버 금지 → `config.rs` 상수 또는 `policy.toml` 설정 사용
- `unwrap()` 남용 금지 → `LiveResult<T>` 또는 로그 후 continue
- 기존 Conference/PTT 기능 깨뜨리지 않기 (각 Phase는 기존 E2E 통과 필수)

---

---

## 분업 체계 (2026-05-17 확립)

김대리 (claude.ai) 와 김과장 (Claude Code, 구현 전담) 의 분업으로 작업 사이클 운영. 부장님 (kodeholic) = 설계 결정 / GO 사인 / 정지점 검토 / 산천포 회피.

### 역할 분담

| 자리 | 김대리 (claude.ai) | 김과장 (Claude Code) |
|------|--------------------|----------------------|
| 분석 / 설계 / 리뷰 / 역사 복원 | ★ 단일 책임 | (지침 §0 사전 점검만) |
| 작업 지침 작성 | ★ 단일 책임 | — |
| 구현 / cargo check 인루프 / mechanical refactor | — | ★ 단일 책임 |

### 작업 지침 파일 자리

- **작업 지침**: `~/repository/context/claudecode/YYYYMM/YYYYMMDD<suffix>_<topic>.md` — 단일 출처
- **작업 완료 보고**: `~/repository/context/YYYYMM/YYYYMMDD<suffix>_<topic>_done.md`
- **두 자리 혼동 금지** — 김과장이 완료 보고를 claudecode/ 자리에 만들었던 사고 1회 (0517c)

### 운영 룰 4종

1. **정지점** — 위험 phase 만 (보통 0~3개). commit + 부장님 보고 + GO 사인 대기. 위험도 낮은 작업은 정지점 0개 + 통합 리뷰
2. **시그니처 선조치 후 보고** — 호출처 컨텍스트 의존 결정은 김과장이 분석 후 박음 + 사후 보고
3. **추가 변경 금지** — 작업 지침 §5 영향 범위 외 파일 손대지 말 것. 별 문제 발견 시 *발견_사항* 으로 보고만, 부장님 컨펌 후 별 토픽
4. **2회 실패 시 중단** — 같은 컴파일 에러 / 같은 테스트 실패 2회 시도 후 미해결 → 즉시 중단 + 보고

### 작업 지침 표준 구조

§0 의무 점검 → §1 컨텍스트 → §2 결정된 사항 → §3 결정 추천 (★ 정지점) → §4 단계별 작업 (Phase A~G) → §5 변경 영향 범위 → §6 운영 룰 → §7 기각 접근법 → §8 산출물 → §9 시작 전 확인 → §10 직전 작업 처리

### 산천포 회피 (김대리 자기 규율)

- 세션 시작 시 *오늘 추진 백로그* 명시 후 진입
- 후속 청소 사이클 *2 이상 연쇄* → 멈춤 + 백로그 복귀
- 세션 종료 시 백로그 갱신 + 다음 세션 우선순위 명시

### 적용 사례

- **2026-05-17** 한 세션 내 6 사이클 (Hook Phase 1~3 + admin cleanup + PeerSnapshot+rename + 세션 마무리). 모든 사이클 운영 룰 100% 준수, 252 tests PASS, 클라 wire 영향 0.
- **2026-05-17** 묶음 1~8 한 세션 진행 (모델 단순화 → 코드 청결성 → 자료구조 일관성 ① → PLI Governor 통합 → Floor hook 시도+원복 → Hook 본문 + State agg-log → scope 흔적 제거 → 운영성 마무리). 운영 룰 4종 100% 준수. 묶음 5 분류 오류는 부장님 검토 후 원복 — *분업 체계 자체 검증 사례* (김과장 적용 → 부장님 정정 → 김대리 다음 지침 보정 사이클 작동). 195 → 194 tests PASS, 클라 wire 영향 0.
- **2026-05-18** F29 (participant.rs 해체) + F28/F29-a 후속 정리 (응집도 작업 2건). 김대리 권고 → 부장님 결재 → 김과장 mechanical refactor 분업 100% 적용. F29 정지점 2건 (Phase 1 끝 / Phase 4 끝) GO 통과. 자료 16건 → 4 모듈 이주, participant.rs 936줄 → 308줄 (-628). F30① peer_scope.rs 시기상조 분리 기각 (부장님 *YAGNI* 결정) — *분리 모드 관성 회피* 사례. 194 PASS × 10회 유지, 클라 wire 영향 0.
- **2026-05-21** ingress.rs 946줄 SRP 위반 + RTX 본질 결함 통합 청산 (0521b). 설계 v1→v4 4차 정정 (업계 3장 조사 — janus/livekit/mediasoup), 부장님 검토 단계별 동석. Phase A~F (ingress 4파일 분리 + 헬퍼 2 + NackGenerator + enum 4 + RTX 디캡슐 + cache 1024+audio + lookup 통합 + 시험 18). 194 → 212 PASS. 후속 0521c (ingress 계층구조 정합) + 0524 (옛 commit 본질 후퇴 정정 3건, 299 PASS) 까지 한 흐름.
- **2026-05-24** 옛 commit 본질 후퇴 정정 3건 (`24b2bf5`/`53aea9c`/`81a99c4`). 부장님 자료 정합 요청 → 옛 commit 본질 후퇴 발견 → 정정. *mechanical refactor 함정 일관 본질 학습* — 옛 별칭/순서의 의도 점검 누락이 일관 함정. 별칭 폐기 시 게으름 vs 명료성 판정, 공통 함수 흡수 시 옛 코드 순서 답습 vs 자료 의미 차원 정공 점검 의무.

---

## 세션 컨텍스트

세션 간 컨텍스트: `/Users/tgkang/repository/context/` 디렉토리

### 디렉토리 구조
```
context/
├── 202603/          ← 2026년 3월 세션 파일
├── 202604/          ← 2026년 4월 세션 파일
├── 202605/          ← 2026년 5월 세션 파일
├── claudecode/      ← 김대리 작업 지침 파일 (YYYYMM/YYYYMMDD<suffix>_<topic>.md)
├── design/          ← 아키텍처, proto, API 설계 산출물
├── biz/             ← 사업 문서
├── blog/            ← 블로그 초안
├── lesson/          ← 부장님 학습 문서
├── guide/           ← AI 가이드 문서
│   ├── METRICS_GUIDE_FOR_AI.md ← 스냅샷 분석 가이드
│   └── QA_GUIDE_FOR_AI.md      ← QA 자동화 가이드 (__qa__, admin 교차검증)
└── SESSION_INDEX.md ← 마스터 인덱스 (루트 유지)
```

### 규칙
- 세션 파일: `YYYYMM/YYYYMMDD_토픽.md` (월별 디렉토리에 저장)
- 설계 문서: `design/YYYYMMDD_토픽.md`
- 새 세션 시작 시 `SESSION_INDEX.md` → 최신 컨텍스트 파일 순으로 읽기
- 세션 종료 시 해당 월 디렉토리에 새 파일 생성 + `SESSION_INDEX.md` 업데이트
- **세션 컨텍스트에 "오늘의 기각 후보" 및 "오늘의 지침 후보"를 반드시 포함할 것**
- **`SESSION_INDEX.md`는 인덱스다** — 한 줄 요약(20~40자) + 파일명만. 세부 기록은 세션 파일에. 기존 항목이 길다고 관성으로 따라 쓰지 말 것.

### 프로젝트 문서 관리
- **PROJECT_MASTER.md** — 유일한 마스터 프로젝트 문서. 현재 유효한 상태/원칙만 집약. 완료 이력은 SESSION_INDEX 단일 출처
- **분업 체계 (2026-05-17~)**: 김대리 (claude.ai, 분석/설계/지침) + 김과장 (Claude Code, 구현). 상세는 §분업 체계

---

*author: kodeholic (powered by Claude)*
