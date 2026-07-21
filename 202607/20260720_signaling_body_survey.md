# 시그널링 wire body 계약 실측 조사 (2026-07-20)

- 대상: wire **body** 계약 현행 실측. op 번호 체계는 조사 대상 아님.
- 방법: rg + 소스 직독. 기억·문서 추정 배제. 못 찾은 것은 "미발견"으로 남김.
- 좌표: oxlens-sfu-server `852a4db` / oxlens-home `260cc10` (2026-07-20 로컬 HEAD).
- 파일 약칭:
  - `msg` = crates/oxsfud/src/signaling/message.rs
  - `mod` = crates/oxsfud/src/signaling/handler/mod.rs
  - `room` = crates/oxsfud/src/signaling/handler/room_ops.rs
  - `track` = crates/oxsfud/src/signaling/handler/track_ops.rs
  - `scope` = crates/oxsfud/src/signaling/handler/scope_ops.rs
  - `adm` = crates/oxsfud/src/signaling/handler/admin.rs
  - `help` = crates/oxsfud/src/signaling/handler/helpers.rs
  - `cev` = crates/oxsfud/src/signaling/handler/client_event.rs
  - `flr` = crates/oxsfud/src/signaling/handler/floor_ops.rs
  - `svc` = crates/oxsfud/src/grpc/sfu_service.rs
  - `tasks` = crates/oxsfud/src/tasks.rs
  - `ingr` = crates/oxsfud/src/transport/udp/ingress_publish.rs
  - `fbc` = crates/oxsfud/src/domain/floor_broadcast.rs
  - `hws` = crates/oxhubd/src/ws/mod.rs
  - `hmod` = crates/oxhubd/src/moderate/handler.rs
  - `hadm` = crates/oxhubd/src/rest/admin.rs
  - `hst` = crates/oxhubd/src/state.rs
  - `hev` = crates/oxhubd/src/events/mod.rs
  - `sig(oxsig)` = crates/oxsig/src/lib.rs · code.rs
  - `sdk` = oxlens-home/sdk0.2/src

---

## A. op별 body 타입 유무 (전수 44 op)

표기 규칙: `타입명 @파일:줄` = serde 타입 파싱/직렬화. `Value @파일:줄` = serde_json::Value 필드 뽑기 또는 json! 인라인 조립. "해당없음" = 그 방향의 body가 wire에 존재하지 않음.

### Handshake (0x00xx)

| op | 요청 body | 응답 d | 이벤트 body |
|---|---|---|---|
| HELLO 0x0001 | 해당없음 (S→C 단방향) | 해당없음 | json! 인라인 `{heartbeat_interval, user_id, role}` @hws:205-210 (client) · @hws:865-869 (admin) |
| IDENTIFY 0x0002 | Value 파싱 — `body.user_id`만 @hws:759-763 (token 필드는 hub가 안 읽음). sfud측 `IdentifyRequest` @msg:17-21 는 정의만(참조 0, §D) | 해당없음 (응답은 별 op IDENTIFY_RESULT) | 해당없음 |
| IDENTIFY_RESULT 0x0003 | 해당없음 | 해당없음 | json! 인라인 `{user_id, ok:true}` @hws:781-785 |

### Session (0x01xx)

| op | 요청 body | 응답 d | 이벤트 body |
|---|---|---|---|
| HEARTBEAT 0x0101 | 파싱 없음 (`{}`) | json! `{}` @hws:523 (client) · @hws:885 (admin) · sfud 도달 시 @mod:90 | 해당없음 |
| TOKEN_REFRESH 0x0102 | Value 파싱 — `body.token` @hws:795 | json! `{expires_at}` @hws:807-809 | 만료 경고 S→C Msg: json! `{code:"TOKEN_EXPIRING", expires_in_sec}` @hws:382-389 |
| RECONNECT 0x0103 | 해당없음 (C→S 없음) | 해당없음 | json! 인라인 `{reason, resume_url}` @hadm:139-144 (REST /admin/reconnect → broadcast @hadm:147-151) |

### Room Request (0x10xx)

| op | 요청 body | 응답 d | 이벤트 body |
|---|---|---|---|
| ROOM_LIST 0x1001 | 파싱 없음 | json! `{rooms:[{room_id,name,capacity,user_count,created_at,rec,speaker_enabled}], total}` @room:31-39,52-55. hub가 전 sfu fan-out 후 재조립 json! `{rooms, total}` @hws:624-651 | 해당없음 |
| ROOM_CREATE 0x1002 | `RoomCreateRequest` @msg:24-36, 파싱 @room:80. hub 라우팅용 Value `body.room_id` @hws:577 | json! `{room_id,name,capacity,created_at,active_speaker}` — ensure 경로 @room:93-99 · 생성 경로 @room:128-134 | 해당없음 |
| ROOM_JOIN 0x1003 | `RoomJoinRequest` @msg:39-57, 파싱 @room:142. hub도 별도 Value 읽기 `body.room_id`/`body.intents` @hws:721-722 | json! 수동 조립 @room:309-354 — `{room_id, participants, scope, server_config:{ice,dtls,codecs,extmap,max_bitrate_bps,floor_bearer[,codecs_sub]}, tracks, floor}`. codecs/extmap 정책 @help:115-177, scope_snapshot @help:186-191, tracks 조립 collect_subscribe_tracks @help:260-494 | 해당없음 |
| ROOM_LEAVE 0x1004 | `RoomLeaveRequest` @msg:63-65, 파싱 @room:414 + Value 추가 필드 `target_user` @room:421-424 (admin kick 경로) | json! `{room_id, scope}` @room:555-558 | 해당없음 |
| ROOM_SYNC 0x1005 | 파싱 없음 (ctx.current_room 기반; body.room_id는 hub 라우팅 소비만 @hws:658-661) | json! `{room_id, participants, subscribe_tracks, floor, total}` @room:400-406 | 해당없음 |

### Media Request (0x11xx)

| op | 요청 body | 응답 d | 이벤트 body |
|---|---|---|---|
| PUBLISH_TRACKS 0x1101 | `PublishTracksRequest` @msg:72-100 + `PublishTrackItem` @msg:103-140, 파싱 @track:24 | add: json! `{intent:true, action:"add", tracks:[{mid,track_id}]}` @track:337-341 · remove: json! `{intent:true, action:"remove"}` @track:675-678 | 해당없음 |
| TRACKS_READY 0x1102 | `TracksReadyRequest` @msg:183-187 (ssrcs deprecated), 파싱만 하고 `_req` 미사용 @track:772 | json! `{synced:true}` @track:880-882 | 해당없음 |
| MUTE_UPDATE 0x1103 | `MuteUpdateRequest` @msg:144-150, 파싱 @track:890 (legacy 잔존 — dispatch @mod:99) | json! `{ssrc, muted}` @track:964 (do_mute 공유) | 해당없음 |
| CAMERA_READY 0x1104 | `CameraReadyRequest` @msg:177-179, 파싱만(`_req` — room_id 필드 미사용) @track:972 | json! `{}` @track:996 · @track:1010 | 해당없음 |
| SUBSCRIBE_LAYER 0x1105 | `SubscribeLayerRequest`/`SubscribeLayerTarget` @msg:204-212, 파싱 @track:1018 | json! `{}` @track:1143 | 해당없음 |
| TRACK_STATE_REQ 0x1106 | `TrackStateReq` @msg:156-167, 파싱 @track:358 (body 분기 muted?/duplex?) | json! — noop `{ssrc,duplex,noop:true}` @track:415 · duplex `{ssrc,duplex}` @track:533-535 · muted 경로 `{ssrc,muted}` @track:964 | 해당없음 |

### Scope / Data / Extension Request (0x12xx~0x17xx)

| op | 요청 body | 응답 d | 이벤트 body |
|---|---|---|---|
| SCOPE 0x1200 | Value `body.mode` 분기 @scope:49-59 → `ScopeUpdateRequest` @msg:234-249 파싱 @scope:72 · `ScopeSetRequest` @msg:254-259 파싱 @scope:104. hub 라우팅 힌트 Value @hws:443-455 (scope_room_hint) | **타입 직렬화** `ScopeEventPayload` @msg:264-272 → serde_json::to_value @scope:236-245 (`{sub, pub, cause, change_id?}`) | 해당없음 |
| MESSAGE 0x1301 | `MessageRequest` @msg:170-173, 파싱 @room:569 | json! `{msg_id}` @room:589-591 | 해당없음 (별 op MESSAGE_EVENT) |
| TELEMETRY 0x1302 | 파싱 없음 — hub 종착, body Value 통째 ccc tap @hws:671-679, oxcccd가 Value 그대로 저장 (`TelemetrySample` @oxcccd/store.rs:18-26, ingest @oxcccd/service.rs:63-66) | json! `{}` (hub ACK_OK) @hws:684-686 | 해당없음 |
| ANNOTATE 0x1303 | 파싱 없음 — Value 통째 relay + `user_id` 주입 @help:786-791 | json! `{}` @help:793 | 해당없음 (별 op ANNOTATE_EVENT) |
| CLIENT_EVENT 0x1304 | Value 파싱 — `body.room_id`, `body.events[].{source,event,severity}` @cev:18-31. ccc tap @hws:671-679 | json! `{}` @mod:107 | 해당없음 |
| MODERATE 0x1701 | Value 파싱 (hub-local) — `action` @hmod:32, `targets|target` @hmod:182-192, `kinds` @hmod:195-203, `duplex` @hmod:206-211, `phase` @hmod:146-153. `room_id`는 hws:549-551에서 선추출 | json! `{}` (ack_ok) @hmod:168-170 · 실패는 `AckFailBody` @hmod:172-175 | 해당없음 |
| USER_PROBE_REPLY 0x1702 | Value 파싱 — `body.req_id` @hws:538, payload 통째 deposit @oxhubd/probe/mod.rs:40-44 (REST 응답으로 그대로 통과 @hadm:314-315) | json! `{}` (wire ACK_OK, body 무관) @hws:542 | 해당없음 |

### Event (0x20xx~0x27xx, S→C)

| op | 요청 body | 응답 d | 이벤트 body |
|---|---|---|---|
| ROOM_EVENT 0x2001 | 해당없음 | 해당없음 | **타입 직렬화** `RoomEventPayload` @msg:192-200 — join @room:287-295 · leave @room:525-534 · evict @help:746-754. **예외**: zombie reaper는 같은 형상을 json! 인라인 중복 조립 @tasks:465-473 |
| TRACKS_UPDATE 0x2101 | 해당없음 | 해당없음 | json! 인라인 `{action, tracks:[..]}` — 5개 발신처: ①emit_per_user_tracks_update @help:570-571 ②leaver 정리 @help:653-654 ③half→full 신규 sub @track:505-507 ④RTP-first promote @ingr:682-690 (entry 조립 @ingr:598-655) ⑤zombie reaper @tasks:448-454. entry 코어 빌더: build_fullnonsim_add_core @help:240-258 · build_remove_tracks @help:502-544 · collect_subscribe_tracks(JOIN/SYNC 응답용) @help:260-494 |
| TRACK_STATE 0x2102 | 해당없음 | 해당없음 | json! — full→half `{user_id,track_id,ssrc,kind,source,duplex,active:false}` @track:434-437 · half→full active:true @track:471-474 · mute `{user_id,ssrc,track_id,kind,muted}` @track:935-937 |
| VIDEO_SUSPENDED 0x2103 | 해당없음 | 해당없음 | json! `{user_id, room_id}` @track:942 |
| VIDEO_RESUMED 0x2104 | 해당없음 | 해당없음 | json! `{user_id, room_id}` @track:1006 |
| TRACK_STALLED 0x2105 | 해당없음 | 해당없음 | json! `{track_id, pub_pid, kind, ssrc, reason:"no_media_flow"}` @tasks:244-256 |
| SCOPE_EVENT 0x2200 | 해당없음 | 해당없음 | **미발견 (emit 0)** — 정의만 존재, 발신처 없음 @scope:17 주석 실측 일치 (`rg opcode::SCOPE_EVENT` 발신 0건). payload 형은 ScopeEventPayload 공유 예정 선언 @msg:261-263 |
| MESSAGE_EVENT 0x2301 | 해당없음 | 해당없음 | json! `{room_id, user_id, content}` @room:577-585 |
| ANNOTATE_EVENT 0x2302 | 해당없음 | 해당없음 | Value relay (요청 body + user_id 주입 그대로) @help:790 |
| FLOOR_MBCP 0x2400 | **binary MBCP TLV** (JSON 아님) — C→S: hub 무파싱 passthrough @hws:265-269 → forward_wire_to_sfud @hws:461-503 → svc:84-91 → handle_floor_binary @flr:37, TLV 파싱 mbcp_native::parse @flr:70 | 해당없음 (wire ACK와 MBCP ACK 별도 — MBCP build_ack @flr:83,155,181) | **binary MBCP TLV** — unicast @flr:218-231 · broadcast wire 조립 @fbc:44-47,288 |
| ACTIVE_SPEAKERS 0x2500 | 해당없음 | 해당없음 | **wire 발송 없음** — DC SVC_SPEAKERS 이관. binary payload 빌더 @tasks:322-338, DC broadcast @tasks:300-310. 주석 실측 일치 @crates/common/src/signaling/mod.rs:24-25 |
| MODERATE_EVENT 0x2700 | 해당없음 | 해당없음 | json! (hub) — authorized `{action,user_id,kinds,duplex}` @hmod:95-100 · unauthorized `{action,user_id}` @hmod:128-132 · speakers_updated @hmod:243-247 · queue_update @hmod:256-260 · phase_changed @hmod:265-269 |
| USER_PROBE_REQ 0x2701 | 해당없음 | 해당없음 | json! `{req_id}` @hadm:308-310 (unicast) |

### Admin / Internal / Error (0x30xx, 0xE0xx, 0xF0xx)

| op | 요청 body | 응답 d | 이벤트 body |
|---|---|---|---|
| ADMIN_TELEMETRY 0x3001 | 해당없음 | 해당없음 | Value passthrough — telemetry_bus JSON 문자열을 body 안 `type` 필드로 op 분류 @svc:229-243 (`agg_log` 등, 타입 없는 것 전부 여기로) |
| ADMIN_SNAPSHOT 0x3002 | Value 파싱 — `body.room_id` (옵션, 단일 방) @adm:560 | json! 수동 조립 — 전체 @adm:15-235 (build_rooms_snapshot: `{type:"snapshot", ts, rooms:[..], users:[..]}`) · 단일 방 @adm:526-540 (`{room, users, ts}`) | 이벤트 겸용: SubscribeAdmin 초기 1회 + 3초 주기 @svc:213-266, telemetry_bus `type=="room_snapshot"` 분류 @svc:239 |
| ADMIN_METRICS 0x3003 | 해당없음 | 해당없음 | Value passthrough — sfud sfu_metrics `{type:"sfu_metrics",..}` @crates/oxsfud/src/metrics/sfu_metrics.rs:288, op 분류 @svc:238 · hub_metrics 별도 조립 @hev:193-203 |
| ADMIN_REAP 0x3004 | Value 파싱 — `body.room_id`/`body.target_user` @adm:582-584 (body.user_id는 envelope 덮어쓰기로 사용 불가 @svc:108-111). 발신 REST @hadm:249-252 | json! `{reaped, room_id, user_id}` @adm:592-594 | 해당없음 |
| ADMIN_DOWNLINK_INJECT 0x3005 | Value 파싱 — `target_user` @adm:614 · `remb_bps` @adm:628 · `loss_fraction` @adm:636 · `repeat` @adm:625. 발신 REST @hadm:262-280 | json! `{user_id, auto_cap, downlink}` @adm:647-651 | 해당없음 |
| SESSION_DISCONNECT 0xE001 | Value 파싱 — `body.room_id` @mod:130 (user_id는 envelope) | 해당없음 (None 반환 @mod:139) | 발신: hub WS cleanup json! `{user_id, room_id}` @hws:402-406 |
| ERROR 0xF001 | 해당없음 | 해당없음 | **타입 직렬화** `AckFailBody` @crates/oxsig/src/code.rs:100-108 — 중복 세션 킥 @hst:314-321 · token 만료 @hws:373-378 |

보조: 전 op 공통 ACK_FAIL body 두 갈래 — sfud `Packet::err` = json! `{code:"<숫자string>", message}` @crates/oxsig/src/lib.rs:105-111, hub = 타입 `AckFailBody` `{code:"SCREAMING_SNAKE", message?, details?}` @hws:149-158. 같은 ACK_FAIL 채널에 code 어휘 2계 공존(숫자 문자열 vs enum 문자열)이 현행.

---

## B. 정의 위치 분산

| 위치 | 사는 것 |
|---|---|
| crates/oxsig/src/lib.rs | `Packet` (op/pid/ok/d 외피) @36-43, v2 잔존 메서드 wrap/to_json @119-135 |
| crates/oxsig/src/code.rs | `AckCode`(17종) @25-45, `AckFailBody` @100-108 |
| crates/oxsig/src/header.rs | 8B WireHeader (body 아님 — 경계 참고) |
| crates/common/src/signaling/ | 재-export만 (mod.rs:14-20, opcode.rs:5). 자체 body 타입 없음 |
| crates/oxsfud/src/signaling/message.rs | **요청 typed 구조체 집합**: IdentifyRequest, RoomCreateRequest, RoomJoinRequest, RoomLeaveRequest, PublishTracksRequest, PublishTrackItem, MuteUpdateRequest, TrackStateReq, MessageRequest, CameraReadyRequest, TracksReadyRequest, SubscribeLayerRequest/Target, ScopeUpdateRequest, ScopeSetRequest + **Serialize 2종**: RoomEventPayload, ScopeEventPayload |
| oxsfud 핸들러 인라인 (json!/Value) | room_ops·track_ops·helpers·admin·client_event·mod — 응답 d 전부와 이벤트 대부분 (§A·§C 좌표) |
| oxsfud 핸들러 밖 인라인 | tasks.rs (TRACK_STALLED, reaper TRACKS_UPDATE/ROOM_EVENT), ingress_publish.rs (RTP-first TRACKS_UPDATE), sfu_service.rs (admin stream op 분류), metrics/sfu_metrics.rs (sfu_metrics body) |
| oxsfud binary body | datachannel/mbcp_native.rs (MBCP TLV 빌더/파서 — FLOOR_MBCP 전용), tasks.rs:322-338 (ACTIVE_SPEAKERS DC payload) |
| oxhubd | 전부 인라인 json!/Value — ws/mod.rs (HELLO/IDENTIFY_RESULT/HEARTBEAT/TOKEN_REFRESH/TELEMETRY/USER_PROBE_REPLY/ROOM_LIST 병합/SESSION_DISCONNECT), moderate/handler.rs (MODERATE + MODERATE_EVENT 5종), rest/admin.rs (RECONNECT, USER_PROBE_REQ), state.rs (ERROR dup-session). hub 자체 typed body 구조체 0 |
| oxcccd/src/store.rs | 저장측 DTO `TelemetrySample` @18-26 · `TelemetryEvent` @29-38 (wire 계약 아님 — body는 Value 그대로 보존) |
| oxrtc/src/signal_client.rs | 자체 타입 0 — oxsig Packet 재사용 + json! 인라인 발신 @131,140,147,222-247 |
| sdk0.2 (클라) | 자체 타입 0 — 전부 object literal 인라인 (§E 좌표) |

---

## C. 응답 조립 지점 (ok:true 의 d) 전수

방식 분류: **[j]** = json! 매크로 · **[v]** = 수동 Value 조립(빌더 함수/필드 삽입 포함) · **[t]** = 타입 직렬화.

### sfud (Packet::ok)

| 좌표 | op | 방식 |
|---|---|---|
| mod:90 | HEARTBEAT | [j] `{}` |
| mod:107 | CLIENT_EVENT | [j] `{}` |
| room:52-55 | ROOM_LIST | [j] + rooms 배열은 [v] map 조립 @room:28-47 |
| room:93-99 | ROOM_CREATE(ensure) | [j] |
| room:128-134 | ROOM_CREATE(생성) | [j] |
| room:354 | ROOM_JOIN | [v] — json! 골격 @309-334 + 조건부 필드 삽입 codecs_sub @337-339, floor @341-352 |
| room:400-406 | ROOM_SYNC | [j] + subscribe_tracks 는 [v] 빌더 @help:260-494 |
| room:555-558 | ROOM_LEAVE | [j] + scope_snapshot [j] @help:186-191 |
| room:589-591 | MESSAGE | [j] |
| track:337-341 | PUBLISH_TRACKS(add) | [j] + resp_tracks [v] 수집 @track:116,239 |
| track:675-678 | PUBLISH_TRACKS(remove) | [j] |
| track:880-882 | TRACKS_READY | [j] |
| track:964 | MUTE_UPDATE·TRACK_STATE_REQ(muted) | [j] (reply_op 공유) |
| track:415 | TRACK_STATE_REQ(noop) | [j] |
| track:533-535 | TRACK_STATE_REQ(duplex) | [j] |
| track:996 · 1010 | CAMERA_READY | [j] `{}` |
| track:1143 | SUBSCRIBE_LAYER | [j] `{}` |
| scope:244 | SCOPE | **[t]** ScopeEventPayload |
| adm:571 | ADMIN_SNAPSHOT | [v] build_rooms_snapshot/build_room_snapshot |
| adm:592-594 | ADMIN_REAP | [j] |
| adm:647-651 | ADMIN_DOWNLINK_INJECT | [j] + downlink 는 [v] admin_snapshot |

### hub (build_ack_ok_frame / new_ack_ok)

| 좌표 | op | 방식 |
|---|---|---|
| hws:523 | HEARTBEAT(client) | [j] `{}` |
| hws:885 | HEARTBEAT(admin) | [j] `{}` |
| hws:542 | USER_PROBE_REPLY | [j] `{}` |
| hws:561 | MODERATE | [v] — moderate Packet.d 재포장 |
| hws:651 | ROOM_LIST | [j] — 전 sfu 응답 병합 재조립 (sfud 응답 d를 hub가 뜯어 다시 만드는 유일한 요청-응답) |
| hws:685 | TELEMETRY | [j] `{}` |
| hws:807-809 | TOKEN_REFRESH | [j] |
| hmod:168-170 | MODERATE(ack_ok 원본) | [j] `{}` |

그 외 요청-응답 op는 hub passthrough (sfud가 만든 wire 그대로 @hws:705-746, ROOM_CREATE는 응답 room_id를 라우팅 bind에만 사용 @hws:607-619).

---

## D. 고아·화석

| # | 항목 | 실측 |
|---|---|---|
| D1 | `IdentifyRequest` @msg:17-21 | **참조 0** (rg 전수: 정의 1건 외 사용처 없음). IDENTIFY는 hub-local이라 sfud 타입이 원천 무용 |
| D2 | `MuteUpdateRequest` @msg:144-150 + MUTE_UPDATE 핸들러 @track:889-901 | 서버 경로는 살아있음(dispatch @mod:99, do_mute 공유). 단 신클라(sdk0.2)는 op 카탈로그에도 없음 — 발신자는 하위호환 구클라 전제뿐. "폐기 선언"은 opcode.rs에 없음(카탈로그 정식 44 op에 포함), 주석상 "0x1103 하위호환 잔존" @track:899 |
| D3 | `TracksReadyRequest.ssrcs` @msg:183-187 | 필드 자체가 deprecated 주석 + 핸들러가 `_req`로 파싱만 하고 버림 @track:772 — 검증용 파싱만 남은 화석 필드 |
| D4 | `CameraReadyRequest.room_id` @msg:177-179 | 파싱만(`_req`) @track:972 — 필드 소비 0 (라우팅은 hub가 함) |
| D5 | SCOPE_EVENT 0x2200 | op·payload 선언만, emit 0 (§A). 클라(sdk0.2)는 수신 케이스 배선됨 @sdk/internal/signaling/signaling.ts:414 — 오지 않는 이벤트 대기 |
| D6 | ACTIVE_SPEAKERS 0x2500 | wire 발송 0 (DC 이관). priority/intent 매핑 잔존 @crates/common/src/signaling/mod.rs:41-49,87 ("wire 복귀 대비 선행 배선" 주석). sdk0.2 카탈로그에도 잔존 @sdk/internal/protocol/ops.ts:72 |
| D7 | sdk0.2 `LAYER_CHANGED: 0x2106` @sdk/internal/protocol/ops.ts:60 + 수신 핸들러 @signaling.ts:413 | 서버 카탈로그에서 폐기(20260705, opcode.rs:87 주석) — 클라 측 화석 |
| D8 | `Packet::wrap` @oxsig lib.rs:121-128 · `Packet::to_json` @lib.rs:133-135 | 참조 0 (rg 전수 — to_json 히트는 전부 타 타입). 자기 선언("dead path 잔존용")과 실측 일치 |
| D9 | reaper의 ROOM_EVENT json! 인라인 @tasks:465-473 | 카탈로그(RoomEventPayload 타입)가 있는데 안 쓰는 동형 중복 조립 — role 필드 부재만 다름 |
| D10 | oxrtc `common_requires_ack` @crates/oxrtc/src/signal_client.rs:351-359 | common 측 원본은 삭제(20260705)되고 로컬 사본이 유일 정의 — 카탈로그 밖 ACK 의무 정의 1건 |

카탈로그에 없는데 남은 구조체: 위 D1 외 미발견 (message.rs 나머지 구조체는 전부 참조 확인됨 — RoomCreate/RoomJoin/RoomLeave/PublishTracks/PublishTrackItem/TrackStateReq/Message/SubscribeLayer*/ScopeUpdate/ScopeSet/RoomEventPayload/ScopeEventPayload).

---

## E. 클라 대칭 (oxlens-home/sdk0.2) — 어긋난 것만

서버가 읽는 필드 vs sdk0.2 가 실제 보내는 필드 대조. 발신 좌표는 sdk0.2/src 기준.

| # | op | 어긋남 |
|---|---|---|
| E1 | IDENTIFY | 클라 `{token, user_id}` @internal/signaling/signaling.ts:389 — hub는 `user_id`만 읽음 @hws:759-763. **token 필드는 아무도 안 읽음** (인증은 WS `?token=` 쿼리 @hws:168-176) |
| E2 | ROOM_JOIN | hub가 `body.intents` 읽음 @hws:722 — **클라 발신처 미발견** (join body = `{room_id, role[, select:false][, pc_mode]}` @talkgroups/talkgroups.ts:158-164). intents 항상 부재 → None |
| E3 | RECONNECT(S→C) | 서버 발신 @hadm:144-151 — **sdk0.2 op 카탈로그에 없음** (ops.ts 전수: RECONNECT 부재) → default 분기 `'signal:event'` 로만 흡수 @signaling.ts:417-420, 전용 재연결 처리 배선 없음 |
| E4 | MUTE_UPDATE 0x1103 | 서버 핸들러 잔존 — 클라 발신 0 (mute는 TRACK_STATE_REQ로 발신 @core/local-endpoint.ts:632) |
| E5 | LAYER_CHANGED 0x2106 | 클라 수신 배선 잔존(§D7) — 서버 발신 소멸 |
| E6 | SCOPE | 클라는 `mode:'update'` + `pub_select`/`pub_deselect` 만 발신 @talkgroups.ts:180-185 — 서버가 읽는 `sub_add`/`sub_remove`/`change_id`/`mode:'set'` 발신처 sdk0.2 내 미발견 (청취 합류·이탈은 ROOM_JOIN(select:false)/ROOM_LEAVE 경유) |
| E7 | MESSAGE·ANNOTATE·MODERATE·ROOM_LIST·TELEMETRY·CLIENT_EVENT·USER_PROBE_REPLY | 서버 수신 경로 존재 — **sdk0.2 발신처 전부 미발견** (rg OP.* 전수). USER_PROBE_REQ는 `'userprobe:req'` 이벤트로 앱에 표출만 @signaling.ts:415 — REPLY 송신은 SDK 밖 책임으로 남음 |
| E8 | 응답 d 미소비 5건 | TRACKS_READY @engine.ts:393 · CAMERA_READY @local-endpoint.ts:276,284 · PUBLISH_TRACKS(remove) @local-endpoint.ts:306,324 · TRACK_STATE_REQ @local-endpoint.ts:632,635 · SUBSCRIBE_LAYER @signaling.ts:209 — 전부 `send()`(fire-and-forget, pending 미등록 @signaling.ts:165-171)라 서버가 조립한 응답 d(`{synced}`, `{ssrc,muted}` 등)는 클라에서 버려짐 |
| E9 | TRACKS_READY body | 클라 `{room_id}`만 @engine.ts:393 — 서버 파싱 대상(ssrcs)은 미발신(serde default 빈 배열), room_id는 sfud가 안 읽음(hub 라우팅 소비만). 서버가 읽는 필드/클라가 보내는 필드 교집합 = 공집합이나 동작 무해 |

정합 확인(어긋남 아님, 기록만): PUBLISH_TRACKS add 발신 필드(`action/room_id/tracks[].{kind,mid,duplex,simulcast,ssrc,source?,codec?}` + enrich `twcc/rid/repair_rid/mid/audio_level_extmap_id, video_pt, rtx_pt, rtx_ssrc` @core/local-endpoint.ts:432-437 · @internal/transport/transport.ts:504-535)는 서버 `PublishTracksRequest`/`PublishTrackItem` 읽기 필드와 일치. TOKEN_REFRESH `{token}`, HEARTBEAT `{}`, ROOM_CREATE `{room_id,name[,capacity]}` @engine.ts:472-476, ROOM_LEAVE `{room_id}`, ROOM_SYNC `{room_id}`, SUBSCRIBE_LAYER `{room_id,targets:[{user_id,rid}]}` @core/remote-pipe.ts:302 일치.

---

## 부기 — envelope 주입 (body 계약에 걸치는 단면)

sfud gRPC 진입 시 hub envelope의 user_id가 **body.user_id로 무조건 덮어쓰기** 됨 @svc:108-111. 이로 인해 admin→sfud 계열(ROOM_LEAVE kick·ADMIN_REAP·ADMIN_DOWNLINK_INJECT)은 대상 지정을 `target_user` 별도 필드로 운반 @room:421-424 · @adm:584 · @adm:614 (hub 발신측 @hadm:117-119,249-252,271-275). body.user_id는 이 3개 op에서 사실상 예약 필드.
