# 20260720b — oxsig body 타입 신설 (1단계: 파일 채우기)

상태: 완료 (Phase A~H + Phase I). 커밋 cdcc9d5(A~H) + dd146dc(I). origin/main 반영(2단계 5e880b5 포함). <!-- [20260722 정정] 구 "commit 대기" → 실커밋 반영. 총 타입 106종(구 "108" 오기)·69 PASS(구 산수 오기, 하단 Phase I 참조) -->

본 파일은 지침 + 실행 기록 통합 파일이다. 아래 §0~§10 지침 영역은 김과장 수정 금지. 이견·판단은 하단 "실행 기록"에 적는다.

## §0 의무 점검

1. `context/PROJECT_MASTER.md` §코딩 규칙
2. `crates/oxsig/src/opcode.rs` 전문
3. `context/202607/20260720_signaling_body_survey.md` (본 작업의 좌표 출처)
4. `crates/oxsfud/src/signaling/message.rs` (기존 타입 15종)

## §1 컨텍스트

wire body 계약에 단일 권위가 없다. 요청 타입 15종은 `oxsfud`에 있어 hub가 참조 불가(의존 방향 역전), 응답 33개 조립 지점 중 타입 직렬화 2곳, 이벤트 타입 사실상 부재. hub는 typed body 0개.
body 계약을 공통 조상 `oxsig`로 올려 hub/sfud가 같은 타입을 본다.

## §2 결정된 사항 (변경 불가)

* 위치: `crates/oxsig/src/message/` 디렉토리 신설
* 분할 축: opcode 두 번째 nibble = 도메인. 8파일

```
message/
├── mod.rs      재-export
├── session.rs  0x00xx / 0x01xx
├── room.rs     0x10xx / 0x20xx
├── media.rs    0x11xx / 0x21xx
├── scope.rs    0x12xx / 0x22xx
├── data.rs     0x13xx / 0x23xx
├── ext.rs      0x17xx / 0x27xx
├── admin.rs    0x30xx
└── ack.rs      ACK_FAIL / ERROR 공용 어휘
```

* 접미사 3종 고정: 요청 `XxxReq` / 응답 `XxxRes` / 이벤트 `XxxEvent`
* `floor.rs` 만들지 않는다 — MBCP 권위는 `mbcp_native.rs` 단일
* `speakers.rs` 만들지 않는다
* 타입 생성 금지 op: `ACTIVE_SPEAKERS`(0x2500), `FLOOR_MBCP`(0x2400) — 별 지침에서 카탈로그 삭제 예정
* 1단계는 파일 생성만. 호출처 무수정. `oxsfud/signaling/message.rs` 무수정(일시 중복 허용, 2단계에서 정리)

## §3 결정 추천

없음. §2가 전부 확정 상태.

## §4 단계별 작업

Phase A — 골격 + 공용 어휘 ★정지점
`mod.rs` + `ack.rs` 작성 후 정지·보고.

* `mod.rs`: 8모듈 선언 + `pub use` 재-export
* `ack.rs`: ACK_FAIL body 단일 타입. 현재 sfud(숫자 문자열 code)와 hub(`AckCode` enum 문자열) 2계 어휘가 공존 — 실코드 양쪽을 읽고 어느 쪽으로 통일할지 판단하지 말고 두 형태를 병기 보고할 것
* `lib.rs`에 `pub mod message;` 추가
* `cargo check -p oxsig` 통과

여기서 결정된 패턴(derive 조합, 주석 형식, 필드 정렬)이 나머지 7파일의 본이 된다.

Phase B~H — 도메인별 작성
카탈로그 순서: session → room → media → scope → data → ext → admin
각 파일에 해당 도메인의 요청 / 응답 / 이벤트 3방향 전부를 담는다.
필드 추출 규칙:

* 요청 = 서버 파싱부 실코드에서만 (`message.rs` 기존 타입 또는 핸들러 `Value` 접근)
* 응답 = `ok:true`의 `d` 조립부(`json!` 매크로) 실코드에서만
* 이벤트 = 발신부 조립 실코드에서만
* 추측 금지. 조립부에 없는 필드를 "있어야 할 것 같아서" 추가하지 말 것
* 필수/옵셔널 판정: 조립부에서 무조건 넣으면 필수, 조건부/`skip_serializing_if`면 `Option<T>`
* 판정 불가한 것은 타입 만들지 말고 미판정 목록에 기록

derive:

* 요청 = `Deserialize`
* 응답/이벤트 = `Serialize`
* hub·sfud 양쪽이 다루는 것 = 둘 다
* 전부 `Debug`

주의 대상 (조사에서 이미 나온 것 — 그대로 반영하되 보고에 표기):

* `TRACKS_UPDATE` 발신처 5곳 — 필드 합집합이 아니라 각 조립부별 필드 차이를 표로 보고. 타입은 하나로 만들되 어느 발신처가 무엇을 빠뜨리는지 명시
* `PUBLISH_TRACKS` 응답 `d.tracks=[{mid, track_id}]` — 클라 track_id 학습 유일 경로
* `TracksReadyReq.ssrcs`, `CameraReadyReq.room_id` — 파싱 후 미사용 화석. 일단 필드 유지하고 화석 표기만
* `MuteUpdateRequest` — 하위호환 경로 생존 상태. 유지

## §5 변경 영향 범위

생성: `crates/oxsig/src/message/` 9파일
수정: `crates/oxsig/src/lib.rs` (모듈 선언 1줄), `crates/oxsig/Cargo.toml` (serde 미보유 시 추가)
그 외 파일 일체 수정 금지. `oxsfud` / `oxhubd` / `oxrtc` / `common` 손대지 말 것.

## §6 운영 룰

1. 정지점 = Phase A 끝 1회. commit + 보고 + GO 대기
2. 시그니처 선조치 후 보고 — 필드 타입 판정은 김과장이 실코드 근거로 박고 사후 보고
3. 추가 변경 금지 — §5 범위 외 발견은 발견_사항으로 보고만
4. 2회 실패 시 중단
5. 지침 영역(§0~§10) 수정 금지 — 이견은 하단 실행 기록에 적는다
6. Phase 끝날 때마다 실행 기록 append — 몰아쓰기 금지
7. 상단 상태 줄 갱신 (진행중 / 정지점대기 / 완료 / 중단)

## §7 기각된 접근

* `xxx_msg.rs` 평탄 배치 — 접미사 중복 / 크레이트 루트 오염
* 요청·응답·이벤트를 파일 축으로 분리 — `TrackStateReq`(0x1106)와 `TrackStateEvent`(0x2102) 짝이 안 보임
* `oxsfud/message.rs`를 이번에 폐기 — 2단계 소관
* 필드 개선·정규화·이름 변경 — 접미사 3종 외 일체 금지. 현재 wire를 그대로 타입화하는 것이 1단계 목적

## §8 산출물

본 파일 하단 "실행 기록"에 누적 기록. 별도 `_done` 파일 생성 금지.
완료 시 아래 항목 전부 기록:

* 생성 타입 전수 목록 (파일별)
* 미판정 목록 — 타입 못 만든 op + 사유
* `TRACKS_UPDATE` 5발신처 필드 차이표
* ACK_FAIL 2계 어휘 병기
* 발견_사항

`context/SESSION_INDEX_202607.md`에 한 줄 추가 (20~40자).

## §9 시작 전 확인

* `oxsig`에 serde 의존 유무
* 조사 보고서의 좌표가 현 HEAD와 일치하는지 (서버 852a4db 기준)

## §10 직전 작업 처리

직전 세션 잔여 없음. 본 작업이 시그널링 테마의 첫 코드 작업.

---

# 실행 기록 (김과장)

## Phase A — 2026-07-20

* 산출:
  - `crates/oxsig/src/message/mod.rs` — 8모듈 선언 + `pub use` glob 재-export + 1단계 원칙 헤더 주석
  - `crates/oxsig/src/message/ack.rs` — `AckFail` 단일 타입 `{code: String, message: Option<String>, details: Value(skip if null)}` + 2계 어휘 병기 doc + 왕복 시험 3건
  - `crates/oxsig/src/message/{session,room,media,scope,data,ext,admin}.rs` — 헤더 주석만 있는 빈 스텁 7파일
  - `crates/oxsig/src/lib.rs` — `pub mod message;` 1줄 추가
  - Cargo.toml 무수정 (§9 확인: serde derive + serde_json 이미 보유)
* 검증: `cargo check -p oxsig` 통과 · `cargo test -p oxsig` 57 PASS (기존 54 + ack 신규 3). 경고 7건 = 빈 스텁의 glob 재-export unused — Phase B~H가 채우면 자연 소멸.
* 판단한 것 (시그니처 선조치 후 보고):
  1. **스텁 7파일을 Phase A에서 생성** — §4 Phase A가 "mod.rs 8모듈 선언 + cargo check 통과"를 동시에 요구하므로, 선언 대상 모듈 파일이 실존해야 check가 통과. 헤더 주석만 담은 빈 파일로 생성 (§2 "9파일 생성" 범위 내).
  2. **ack 타입명 = `AckFail`** — 접미사 3종(Req/Res/Event)은 op 귀속 타입용. <!-- [20260722 정정] 구 "Est" 오기 → Event --> ACK_FAIL은 전 op 공용 채널 + ERROR(0xF001) 공유 어휘라 접미사 없이 명명. 기존 `oxsig::code::AckFailBody`(hub 계열 전용)와 이름 충돌 회피 겸함 — AckFailBody 처리(흡수/잔존)는 2단계 소관.
  3. **`code: String`** — 2계 어휘(숫자 문자열/enum 문자열)를 판단 없이 둘 다 담는 초집합 표현. `AckCode` enum을 쓰면 sfud 계열("3002")의 deserialize가 깨져 현행 wire 보존 원칙 위반.
  4. **derive 패턴(이후 7파일의 본)**: `#[derive(Debug, Clone, Serialize, Deserialize)]` 순서 고정, 요청=Deserialize·응답/이벤트=Serialize·양측 공용=둘 다, 전부 Debug. serde attr는 기존 message.rs 관례 답습(`skip_serializing_if`/`default`). 타입 doc에 op(0x..)·방향·실코드 좌표·화석 표기.
* ACK_FAIL 2계 어휘 병기 (§4 Phase A 요구):
  - sfud 계열: `Packet::err` @crates/oxsig/src/lib.rs:105-111 → `{"code":"3002","message":"invalid payload"}` — code = v2 숫자 코드의 문자열화. 생산처 = oxsfud 핸들러 전 에러 경로.
  - hub 계열: `AckFailBody` @crates/oxsig/src/code.rs:100-108 (code = `AckCode` SCREAMING_SNAKE) → `{"code":"INVALID_PAYLOAD","message":"...","details":{}}` — 생산처 = oxhubd (build_ack_fail_frame/build_error_frame @ws/mod.rs:149-158, moderate @handler.rs:172-175, dup-session ERROR @state.rs:314-321).
  - 통일 방향 판단은 지침대로 하지 않음 — 신 타입은 두 형태를 손실 없이 왕복(시험으로 고정).
* 정지점 보고: 완료. 부장님 소스 직접 확인 예정이므로 **commit 보류** (지시 시 commit). GO 대기.
* 후속: 부장님 GO — "stub 뿐이냐, 다음 진행해" (2026-07-20).

## Phase B~H — 2026-07-20 (GO 후 연속 진행)

* Phase B session.rs / C room.rs / D media.rs / E scope.rs / F data.rs / G ext.rs / H admin.rs 작성 완료.
* 검증: `cargo check -p oxsig` 무경고 통과 · `cargo test -p oxsig` **64 PASS**(기존 54 + 신규 10) ·
  `cargo check --workspace` 통과(타 크레이트 무영향 확인).
* 신규 시험 10건 = ack 왕복 3 + 조립부 wire 형상 고정 7 (media 3 / scope 2 / room 2).
  "현행 바이트 보존" 주장을 코드가 아니라 시험이 붙들게 함 — skip vs null 직렬화 구분이 핵심.

### 생성 타입 전수 (71종 / 8파일, 1,296줄)

| 파일 | 수 | 타입 |
|---|---|---|
| session.rs | 8 | HelloEvent, IdentifyReq, IdentifyResultEvent, TokenRefreshReq, TokenRefreshRes, TokenRefreshEvent, ReconnectEvent, SessionDisconnectEvent |
| room.rs | 19 | RoomListItem, RoomListRes, RoomCreateReq, RoomCreateRes, RoomJoinReq, MemberInfo, FloorSnapshot, FloorQueueItem, IceConfig, DtlsConfig, CodecPolicy, ExtmapEntry, ServerConfig, RoomJoinRes, RoomLeaveReq, RoomLeaveRes, RoomSyncReq, RoomSyncRes, RoomEvent |
| media.rs | 19 | PublishTracksReq, PublishTrackItem, PublishTracksResItem, PublishTracksRes, TracksReadyReq, TracksReadyRes, MuteUpdateReq, MuteUpdateRes, CameraReadyReq, SubscribeLayerReq, SubscribeLayerTarget, TrackStateReq, TrackStateRes, TrackEntry, TracksUpdateEvent, TrackStateEvent, VideoSuspendedEvent, VideoResumedEvent, TrackStalledEvent |
| scope.rs | 5 | ScopeModeReq, ScopeUpdateReq, ScopeSetReq, ScopeEvent, ScopeSnapshot |
| data.rs | 6 | MessageReq, MessageRes, MessageEvent, AnnotateEventInjected, ClientEventReq, ClientEventItem |
| ext.rs | 6 | ModerateReq, ModerateEvent, ModerateSpeaker, ModerateQueueItem, UserProbeReqEvent, UserProbeReplyReq |
| admin.rs | 7 | AdminSnapshotReq, AdminSnapshotRes, AdminRoomSnapshotRes, AdminReapReq, AdminReapRes, AdminDownlinkInjectReq, AdminDownlinkInjectRes |
| ack.rs | 1 | AckFail |

### 미판정 목록 (타입 못 만든 것 + 사유)

| 대상 | 사유 |
|---|---|
| TELEMETRY(0x1302) 요청 body | 클라 페이로드 통째. hub 종착(oxcccd 직행) + oxcccd 는 "들어오는 모양 보존"으로 Value 저장 — 서버 어디에도 필드 접근 0. 실코드 근거 부재 |
| ANNOTATE(0x1303) 요청 / ANNOTATE_EVENT(0x2302) body | 서버가 파싱 없이 통째 relay, `user_id` 만 주입("action 파싱 없음" @helpers.rs:765). 주입 필드만 `AnnotateEventInjected` 로 남김 |
| USER_PROBE_REPLY(0x1702) payload 본문 | `req_id` 외 전부 클라 진단 자유형. hub 는 통과만(저장 0) |
| ADMIN_TELEMETRY(0x3001) / ADMIN_METRICS(0x3003) body | telemetry_bus / metrics passthrough. 서버는 `type` 으로 op 분류만 하고 필드 미접근 |
| ADMIN_SNAPSHOT(0x3002) 응답 rooms[]/users[] 원소 | 4단 중첩 진단 표면(참가자별 tracks/stream_map/intent/pli_governor/subscriber_gate/sub_mid_map/dc/track_issues …) + 조건부 삽입 다수. 최상위 골격만 타입화, 원소는 Value 유지 |
| FLOOR_MBCP(0x2400) | §2 지침 — binary MBCP TLV, 권위는 mbcp_native.rs 단일 |
| ACTIVE_SPEAKERS(0x2500) | §2 지침 — wire 미발송(DC 이관) |
| HEARTBEAT 요청/응답 · CAMERA_READY/SUBSCRIBE_LAYER/MODERATE/TELEMETRY/ANNOTATE/CLIENT_EVENT/USER_PROBE_REPLY 응답 | 계약이 빈 객체 `{}`. 타입 불요 — 각 파일 모듈 doc 에 좌표와 함께 명시 |
| SCOPE_EVENT(0x2200) 발신 | 타입(`ScopeEvent`)은 SCOPE 응답과 공유해 존재하나 **발신처 0** — 이벤트로서는 미구현 상태 그대로 |

### TRACKS_UPDATE 5발신처 필드 차이표

타입은 `TrackEntry` 하나(합집합). 아래는 각 조립부가 **실제로 채우는** 필드. ○=항상, △=조건부, ─=없음.

| 필드 | ①add publish<br>@helpers:570←track_ops:282-317 | ②add half→full<br>@track_ops:497-507 | ③add RTP-first<br>@ingress_publish:598-620 | ④remove 계열<br>@helpers:502-544(+mid) | ⑤remove half캐시<br>@track_ops:643-659 | (참고) JOIN/SYNC 동봉<br>@helpers:359-405 |
|---|---|---|---|---|---|---|
| user_id | ○ | ○ | ○ | ○ | ○ | △ (PTT slot 은 부재) |
| kind | ○ | ○ | ○ | ○ | ○ | ○ |
| ssrc | ○ | ○ | ○ | ○ | ○ | ○ |
| track_id | ○ | ○ | ○ | ○ | ○ | ○ |
| mid | ○ | ○ | ○ | △ (mid_map 보유 시) | ○ | ○ |
| duplex | ○ "full" | ○ "full" | ○ (derive) | ○ | ○ "half" | ○ |
| active | ─ | ─ | ─ | ─ | ─ | △ (full→half 캐시만 false) |
| source | △ (있으면) | ○ | △ (camera 아니면) | △ (있으면) | ─ | △ |
| rtx_ssrc | ─ | ─ | ─ | △ (있으면) | ─ | △ |
| video_pt | △ (video, pt>0) | △ (video, pt>0) | △ (pt>0) | ─ | ─ | △ |
| rtx_pt | △ (video, pt>0) | △ (video, pt>0) | △ (pt>0) | ─ | ─ | △ |
| codec | △ (video) | △ (video) | △ (video) | ─ | ─ | △ |
| simulcast | △ (video, 항상 false) | △ (video, false) | △ (video, 실값) | ─ | ─ | △ (실값) |

핵심 비대칭 3건:
1. **remove 계열(④⑤)은 codec 4필드를 전혀 안 싣는다** — add 와 형상 비대칭. 제거엔 불필요하나 같은 op·같은 배열의 원소 형상이 action 에 따라 갈린다.
2. **③ RTP-first 만 `simulcast` 실값**(①②는 FullNonSim 이라 항상 false) — 같은 add 인데 의미가 다름.
3. **`user_id` 부재 경우 존재**(JOIN/SYNC 동봉의 PTT slot, leaver 정리 @helpers:624-635) — 그래서 타입에서 `Option<String>`.

### ACK_FAIL 2계 어휘 병기

(Phase A 기록과 동일 — `AckFail.code: String` 이 두 어휘를 손실 없이 수용, 왕복 시험 3건으로 고정)
- sfud 계열 `Packet::err` @oxsig/lib.rs:105-111 → `{"code":"3002","message":"invalid payload"}` (details 필드 부재)
- hub 계열 `AckFailBody` @oxsig/code.rs:100-108 → `{"code":"INVALID_PAYLOAD","message":"...","details":{...}}`

### 발견_사항 (보고만 — §5 범위 밖, 손대지 않음)

1. **ADMIN_SNAPSHOT 응답 골격 2형 불일치** — 전체 `{type:"snapshot", ts, rooms, users}` @admin.rs:229-234 vs 단일 방 `{room, users, ts}` @admin.rs:535-539. 같은 op 인데 `type` 유무·room 단복수가 다르다. 소비처(oxadmin/hub REST)가 둘을 구분해 다루는지 미확인.
2. **reaper 만 ROOM_EVENT 를 타입 미경유 조립** @tasks.rs:465-473 — 타입 경로(RoomEventPayload) 3곳과 동형이나 `role` 필드가 없다. 2단계 이관 시 수렴 대상.
3. **`CameraReadyReq.room_id` 가 필수 파싱** — 미사용(`_req`)인데 부재 시 3002 로 거절된다 @track_ops.rs:972. 화석 필드가 계약상 필수로 남아 있는 상태(따라서 타입도 `String` 유지).
4. **`ScopeSnapshot` vs `ScopeEvent` 형상 분기** — 같은 scope 개념인데 ROOM_JOIN/LEAVE 동봉형은 `{sub,pub}`, SCOPE 응답형은 `{sub,pub,cause,change_id?}`. 클라 applyEvent 가 둘 다 먹도록 되어 있는지는 SDK 소관(미확인).
5. **hub 가 sfud 응답을 뜯어 재조립하는 유일 지점 = ROOM_LIST** @ws/mod.rs:624-651 — 이 때문에 `RoomListItem`/`RoomListRes`/`RoomCreateRes` 는 양방향 derive 가 필요했다(다른 응답 타입은 Serialize 단방향).
6. **`TrackStateRes` 는 한 op 가 3형 응답** (noop/duplex/muted) — 합집합 타입으로 표현했으나, 2단계에서 호출처를 이관할 때 경로별로 어떤 필드를 채울지 강제할 수단이 없다(현행 wire 보존 우선).
7. **sfud행 요청의 `room_id` 이중 계약** — sfud 파싱부엔 없지만 hub 라우팅이 필수로 소비하는 op 가 다수(TRACKS_READY/SUBSCRIBE_LAYER/TRACK_STATE_REQ/PUBLISH_TRACKS). 타입에 `Option` 으로 포함하고 doc 에 "sfud 미파싱, hub 라우팅 소비" 표기 — 2단계에서 이 필드를 누가 검증할지 미결.

### 2단계(호출처 이관) 인수인계 메모

- 본 단계 산출은 **정의만** — `oxsfud/signaling/message.rs` 기존 15종과 의도된 일시 중복 상태(§2).
- 이관 시 주의: `RoomEventPayload`→`RoomEvent`, `ScopeEventPayload`→`ScopeEvent`(+`ScopeSnapshot` 분리),
  `TrackStateReq` 는 이름 동일하나 `room_id` 필드가 추가됨(hub 라우팅 계약 반영).
- wire 바이트 동일성 근거 = 본 단계 시험 7건. 이관 후에도 이 시험이 초록이어야 한다.

## Phase I — 미판정 진단 body 전개 (2026-07-21, 부장님 추가 지시)

부장님 판정: "TELEMETRY/CLIENT_EVENT/USER_PROBE_REPLY 는 oxsig 에 명세처럼 박혀야". Phase B~H 에서 이 3건을 "서버 파싱부 없음 → 미판정"으로 남긴 것이 오판. 근거 정정:

- **계약 권위 = wire 에 무엇이 흐르느냐(클라 생산부)**, "서버가 파싱하느냐" 아님. oxsig 는 자기 헤더에 "서버·클라·도구 전원 공유"로 선언한 wire 단일 권위 — 서버가 Value 로 통과시키는 건 게으름이지 계약 부재가 아니다.
- 소비처 재규명: USER_PROBE_REPLY 는 **oxadmin**(crates/oxadmin/src/main.rs:602-651, render_user_probe)이 46+ 필드를 실제로 읽는다(당초 "hub 는 req_id 만" 만 보고 소비처 미조사한 것이 오류). CLIENT_EVENT 는 서버 3필드 + oxcccd 통째(5필드). TELEMETRY 는 oxcccd 통째.
- 판정 방법: **클라 collector 실측만**(W3C webrtc-stats 대조 안 함 — 표준 끌어오면 "표준대로겠지" 추측이 섞임. lastPacketReceivedTimestamp epoch 오가정 질책 동형 함정). 클라가 담는 것이 곧 계약.
- 깊이 회피 철회: "getStats 파생이라 깊다 → Value" 는 편한 방향 도피였다. 스펙이면 무엇으로든 형태를 가져야 한다(부장님). 단 클라가 **객체를 통째 spread** 한 곳(getSettings/getCapabilities/transport.status/getStats 원본 durations)은 클라 자신이 형태를 위임한 지점이라 Value 가 실측 — 이건 회피 아님.

### 생산부 실측 좌표 (클라 sdk/, sdk0.2 아님)

| body | 생산부 | 소비처 |
|---|---|---|
| TELEMETRY 0x1302 | sdk/observability/telemetry.js (stats @239 / sdp @84) | oxcccd 통째 저장 |
| CLIENT_EVENT 0x1304 | sdk/observability/event-reporter.js:47 | sfud agg-log(3) + oxcccd(5) |
| USER_PROBE_REPLY 0x1702 | sdk/observability/user-probe-collector.js + engine.js:175 | oxadmin(46+ 필드 렌더) |

### 추가 생성 타입 (data.rs +16, ext.rs +19 = +35종)
<!-- [20260722 정정] 구 "+18/+37" 오기 → data.rs 6→22(+16), ext.rs 6→25(+19), 계 +35. 총 71→106(구 "108" 오기). 실측: git grep 'pub struct' @cdcc9d5=71 @dd146dc=106 -->

- **data.rs**: ClientEventItem 에 `ts`/`detail` 추가(결함 수정 — 5필드). TELEMETRY 2형: TelemetryStatsReq(section=stats), TelemetrySdpReq(section=sdp) + MlineSummary, PublishStats/OutboundStat/QldDelta/NetworkPub, SubscribeStats/InboundStat/NetworkSub, CodecStat, PttDiagnostics/PowerStats/PowerBucket/PowerAudio/PowerVideo.
- **ext.rs**: UserProbeReplyReq 확장(정상형+에러형 합집합) + ProbePubTrack/ProbeMediaSource/ProbeRemoteInbound/ProbeTrackInfo/ProbeTransceiverInfo/ProbePipeInfo/ProbeSelfView/ProbeSubTrack/ProbeElement/ProbeBounding/ProbeAudioExtras/ProbeEnv/ProbeConnection/ProbeScreen/ProbeDevice/ProbePermissions/ProbeState/ProbeNetwork/ProbeCandidatePair.

### 타입 판정 규칙 (실측 근거)
- `?? null` / `|| null` → `Option<T>`. `|| 0` → 필수.
- 정수(카운터 원값·`Math.max(0,·)`·`Math.round(·)`) → u64 / packetsLost 는 음수 가능 i64.
- 실수(원본 시간(초)·jitter·audioLevel·fps·`/10`·`/1000`·DOMHighResTimeStamp) → f64.
- 클라 통째 spread(getSettings/getCapabilities/transport.status.pub·sub·dc/restoreMetrics/qualityLimitationDurations[user-probe]/events[type별 가변]) → `serde_json::Value`.

### wire key 컨벤션 (struct 별 상이 — 실측 그대로, 시험으로 고정)
- getStats 파생·DOM struct = camelCase → `rename_all="camelCase"`.
- **예외 `avgQP`**(camelCase 규칙은 avgQp) → 개별 rename. wire 실측 avgQP.
- sdk 자작 필드는 snake(`track_id`/`bitrate_kbps`/`media_source`/`remote_inbound`/`self_view`/`audio_extras`) 및 혼합형(`srcObject_set`/`element_attached`/`filter_applied`/`played_length`/`sinkId`/`audioContext_state`) → struct 내 개별 rename.
- 상위 래퍼(section/room_id/pub_local_sdp/hot_standby) snake → rename 없음.

### 검증
`cargo check -p oxsig` 무경고 · `cargo test -p oxsig` **69 PASS**(64 + 신규 5: client_event 5필드 왕복, OutboundStat camelCase+avgQP, PowerVideo kf, UserProbeReply 에러형, ProbePubTrack snake/camelCase 혼재+self_view) · `cargo check --workspace` 통과.
<!-- [20260722 정정] 구 "63 + 6" 오기: 기준선은 직전 Phase B~H 의 64, 신규는 열거된 5건. 실측 git show dd146dc = +5 #[test]/−0(삭제 없음). 64+5=69 일관 -->

### 발견_사항 (보고만)
1. **`ClientEventItem` ts/detail 누락은 Phase B~H 의 실제 결함이었다** — "서버 파싱부에서만" 규칙을 wire 계약보다 앞세운 탓. oxcccd 통째 저장 경로에서 재직렬화 시 소실됐을 것. 본 Phase 에서 수정.
2. **ANNOTATE 는 의도적 body-agnostic** (부장님 방향) — 향후 확장 서비스형, body 를 모른 채 relay 만. 타입 미생성 확정(미판정 아님 — 설계 결정).
3. **sdk/ vs sdk0.2 진단 생산자 격차** — 진단 3종 생산자는 sdk/(JS, lab·demo·e2e 봇)에만 있고 sdk0.2(3층 라이브 게이트 qa/)엔 op 상수만·생산자 0. 3층 게이트 경로에선 telemetry/client_event/user-probe 가 안 나감. 의도된 미이식 여부 미확인 — §5 범위 밖.
4. **avgQP wire key 는 표준 이례** — W3C 는 avgQp 관행이나 클라가 avgQP 로 담음. 클라 실측이 계약이라 avgQP 로 고정(개별 rename + 시험).
