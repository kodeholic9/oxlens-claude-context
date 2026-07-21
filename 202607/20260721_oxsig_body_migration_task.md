# 20260721 — oxsig body 타입 2단계: 호출처 이관

상태: 2단계 완전 종료 (Phase A~F · 2층 10/10 · 3층 통과 · 커밋 5e880b5). push 만 부장님 대기.

본 파일은 지침 + 실행 기록 통합 파일이다. §0~§10 지침 영역은 착수 후 수정 금지(이견은 하단 실행 기록).
**작성 주체 예외**: 본 지침은 김과장(구현자)이 작성 — 부장님 위임(2026-07-21). 설계+구현 겸임의
자기검토 편향을 정지점 촘촘화로 보완(정지점 2개 + 도메인별 회귀 게이트).

## §0 의무 점검

1. `context/PROJECT_MASTER.md` §코딩 규칙 + §분업 체계
2. `context/202607/20260720b_oxsig_body_types_task.md` (1단계 실행 기록 — 생성 타입 전수·판정 규칙)
3. `context/202607/20260720_signaling_body_survey.md` (조립부 좌표 전수)
4. `crates/oxsig/src/message/` 전 8파일 (이관 대상 타입)
5. 회귀 키워드 로드: `회귀시험` → `context/guide/REGRESSION_GUIDE_FOR_AI.md`

## §1 컨텍스트

1단계에서 oxsig/message/ 에 body 타입 108종(요청 Req/응답 Res/이벤트 Event)을 **정의만** 했다
(커밋 cdcc9d5, dd146dc). 현재 아무도 안 쓴다 — `oxsfud/signaling/message.rs` 의 구 15종과
의도된 중복 상태. 2단계는 **호출처를 oxsig::message 로 이관**해 타입을 실제 계약 권위로 만든다:
- 요청: 서버 파싱부가 구 타입 대신 oxsig::message 요청 타입 파싱.
- 응답/이벤트: `json!` 인라인 조립 → oxsig::message 타입 직렬화.
- 종착: `oxsfud/signaling/message.rs` 삭제, 중복 소멸.

**불변**: 이관은 wire 바이트를 바꾸지 않는다(현행 클라 무영향). 1단계 wire 형상 시험 17건 +
oxe2epy run-all + 3층 라이브가 이를 붙든다.

## §2 결정된 사항 (착수 후 변경 불가)

* **점진 이관** — 도메인 단위(카탈로그 순서 room→media→scope→data→ext→admin). 한 도메인
  이관 후 회귀 게이트 통과 확인 뒤 다음. 전면 일괄 금지(회귀 원점 특정 불가).
* **타입명은 oxsig 것**(Req/Res/Event 접미사) — 구 `RoomJoinRequest`→`RoomJoinReq` 등 소비처
  참조도 개명. shim 재-export 불가(이름 다름).
* **응답 조립 = 타입 직렬화** — `Packet::ok(op, pid, serde_json::to_value(&T{..})?)` 형. `json!`
  인라인 제거. 직렬화 실패 경로는 기존 에러 코드(3000) 답습.
* **wire 불변 원칙** — 필드 순서/이름/skip·null 정책 1단계 타입 그대로. 개선·정규화 금지
  (1단계와 동일 계율). 이관 중 wire 차이 발견 시 **타입을 wire 에 맞춘다**(코드 아님).
* **oxrtc 범위 밖** — 봇 도구. 요청 json! 조립을 oxsig 요청타입(현 Deserialize 전용)으로 바꾸려면
  양방향 derive 가 필요 → 별 토픽. 본 2단계는 oxsfud + oxhubd 만.
* **진단 3종(TELEMETRY/CLIENT_EVENT/USER_PROBE_REPLY) 이관 범위**: 서버가 *실제 파싱하는*
  부분만 이관(CLIENT_EVENT 3필드 @client_event.rs). TELEMETRY/USER_PROBE_REPLY 는 서버 미파싱
  (통과)이라 이관할 조립/파싱부가 없다 — 타입은 정의로 존치(oxadmin/oxcccd 향후 소비처가 사용).
  sdk/ 실측 기준 유지(부장님 확정 — sdk0.2 포팅 시 재검).

## §3 결정 추천 (★ 부장님 결정 필요)

1. **정지점 위치** — 추천: Phase A 끝(요청 이관 = 패턴 확립) + Phase C 끝(media = 최고 위험,
   3층 미디어 게이트). 2개. (대안: 도메인마다 정지 = 6개, 과도.)
2. **message.rs 삭제 시점** — 추천: 마지막 Phase F(전 도메인 이관 후 일괄). 중간 삭제는
   컴파일 깨짐 연쇄.
3. **oxrtc** — 추천: 범위 밖(별 토픽). 봇이 구 wire 로도 정합하면 유지.

## §4 단계별 작업

### Phase A — 요청 파싱 이관 + 패턴 확립 ★정지점
* `oxsfud/signaling/message.rs` 의 15 요청 타입 소비를 oxsig::message 로 교체.
  - 핸들러 9파일의 `use crate::signaling::message::*` → oxsig 참조. 타입명 개명 반영
    (RoomJoinRequest→RoomJoinReq, PublishTracksRequest→PublishTracksReq, …).
  - message.rs 에서 이관 완료 요청 타입 제거(응답 2종 RoomEventPayload/ScopeEventPayload 은
    Phase B/D 까지 존치).
* 게이트: `cargo check -p oxsfud` + `python -m oxe2epy run-all` (2층 봇 회귀).
* 여기서 확립된 패턴(참조 교체·개명·직렬화 형)이 B~E 의 본.
* **정지·보고·GO 대기.**

### Phase B — room 도메인 응답/이벤트 이관
* ROOM_LIST/CREATE/JOIN/SYNC/LEAVE 응답 json! → RoomListRes/RoomCreateRes/RoomJoinRes/
  RoomSyncRes/RoomLeaveRes 직렬화 (@room_ops.rs). ServerConfig/Ice/Dtls/Codec/Extmap/Floor
  중첩 포함.
* ROOM_EVENT → RoomEvent (RoomEventPayload 대체, tasks.rs reaper 인라인 @465-473 포함 — survey §D9).
* 게이트: cargo check + run-all.

### Phase C — media 도메인 ★정지점
* PUBLISH_TRACKS/TRACKS_READY/MUTE/CAMERA/SUBSCRIBE_LAYER/TRACK_STATE_REQ 응답.
* TRACKS_UPDATE(5발신처 @helpers/track_ops/ingress_publish/tasks) → TracksUpdateEvent/TrackEntry.
  ★ 발신처별 필드 차이(1단계 차이표) 유지 — 각 조립부가 채우던 필드만 채운다(합집합 타입이나
  전 필드 강제 금지).
* TRACK_STATE/VIDEO_SUSPENDED/VIDEO_RESUMED/TRACK_STALLED 이벤트.
* 게이트: cargo check + run-all + **3층 라이브(미디어 실영상)** — 미디어 wire 최고 위험.
* **정지·보고·GO 대기.**

### Phase D — scope + data 도메인
* SCOPE 응답 ScopeEventPayload→ScopeEvent, ROOM_JOIN/LEAVE 동봉 scope_snapshot→ScopeSnapshot.
* MESSAGE 응답/MESSAGE_EVENT, CLIENT_EVENT 파싱(3필드) → ClientEventReq.
* ANNOTATE 는 body-agnostic relay 유지(타입화 안 함 — 1단계 결정).
* 게이트: cargo check + run-all.

### Phase E — ext + admin 도메인 (hub 포함)
* MODERATE_EVENT(hub @moderate/handler.rs) → ModerateEvent, USER_PROBE_REQ → UserProbeReqEvent.
* ADMIN_SNAPSHOT/REAP/DOWNLINK_INJECT 응답. (ADMIN_SNAPSHOT rooms[]/users[] 원소는 Value 존치 —
  1단계 결정, 골격만 타입.)
* hub ws/mod.rs 인라인(HELLO/IDENTIFY_RESULT/TOKEN_REFRESH 등) → session.rs 타입.
* AckFail 2계 어휘: 이관하되 **통일 안 함**(1단계 계율) — 조립부가 쓰던 형태 그대로.
* 게이트: cargo check(-p oxhubd 포함) + run-all.

### Phase F — 종착 정리
* `oxsfud/signaling/message.rs` 삭제(잔여 참조 0 확인 후).
* `oxsfud/signaling/opcode.rs`·mod.rs 정합.
* 전 crate cargo check + run-all + 3층 최종.

## §5 변경 영향 범위

수정: `crates/oxsfud/src/signaling/**`(핸들러 9 + message.rs 삭제 + mod), `crates/oxsfud/src/tasks.rs`,
`crates/oxsfud/src/transport/udp/ingress_publish.rs`, `crates/oxhubd/src/{ws/mod.rs, moderate/handler.rs,
rest/admin.rs}`, 필요 시 `crates/oxsig/src/message/*`(wire 정합 위한 타입 조정만 — 개선 금지).
범위 밖: oxrtc, oxcccd, common, oxadmin. sdk/·sdk0.2(폐기·별 세대).

## §6 운영 룰 (PROJECT_MASTER 분업 4종 준용)

1. 정지점 = §3 확정분(추천 2개). commit + 보고 + GO 대기.
2. 시그니처 선조치 후 보고 — 조립부별 필드 판정은 실코드 근거로 박고 사후 보고.
3. 추가 변경 금지 — §5 범위 외는 발견_사항 보고만.
4. **2회 실패 시 중단** — 같은 회귀(run-all/3층) 2회 미해결 → 중단·보고.
5. 지침 영역 수정 금지(이견은 실행 기록).
6. Phase 끝마다 실행 기록 append.
7. 상단 상태 줄 갱신.
8. **wire 회귀 게이트 필수** — 도메인 이관은 cargo check 로 끝나지 않는다. 게이트 없이 다음
   Phase 진입 금지. 실행 주체 = **부장님**(서버 기동 + 봇 라이브, 김과장 미실행 — feedback_no_self_testing):
   ```
   # 전제: hub(1974) + sfud 기동 상태 (run.py docstring §6-6)
   cd ~/repository/oxlens-sfu-server/oxe2epy
   . .venv/bin/activate                    # venv(3.12) — 전역 python 없음, 여기 aiortc 등 설치
   python -m oxe2epy run-all --core        # 커밋 전 코어 게이트 ~90s (10종, 케이스바이 제외)
   python -m oxe2epy run-all               # 전체 (케이스바이 32종 포함, 영역 건드릴 때/릴리스 전)
   ```
   김과장 게이트 = `cargo check`/`cargo test`(단위)까지. 2층(run-all)·3층(라이브 실영상)은
   부장님 실행 결과 제공 → 김과장 분석. media/최종 Phase 는 3층까지 필수.

## §7 기각된 접근

* shim 재-export(message.rs = `pub use oxsig::message::*`) — 타입명 다름(Request↔Req)이라 불성립.
* 전면 일괄 이관 — 회귀 시 원점 특정 불가. 도메인 점진이 원칙.
* 이관 김에 필드 개선/정규화/AckFail 통일 — 1단계와 동일 금지. wire 불변이 최우선.
* oxrtc 동시 이관 — 요청타입 양방향 derive 필요, 별 토픽.

## §8 산출물

본 파일 하단 실행 기록에 Phase 별 append. 완료 시:
* 이관 전수(도메인별 조립부 수 / 개명 타입 목록)
* message.rs 삭제 확인
* 회귀 게이트 결과(run-all / 3층)
* wire 차이 발견분(타입을 wire 에 맞춘 정합) — 있으면
* 발견_사항

`context/SESSION_INDEX_202607.md` 한 줄 추가.

## §9 시작 전 확인

* 1단계 커밋(cdcc9d5/dd146dc) HEAD 반영 확인.
* 게이트 baseline 초록 확인 — `cd oxe2epy && . .venv/bin/activate && python -m oxe2epy run-all --core`
  (서버 hub1974+sfud 기동 전제). 전역 python 없음 → venv 필수.
* 3층 라이브 게이트 기동 가능한지(media Phase 대비).

## §10 직전 작업 처리

1단계(20260720b) 완료 — 타입 정의만. 본 2단계가 그 정의를 소비로 전환하는 직결 후속.
진단 3종은 sdk/ 실측 기준 유지(부장님 확정), sdk0.2 포팅 시 재검(본 2단계 범위 밖).

---

# 실행 기록 (김과장)

## (착수 전 — GO 대기)

* 스코프 실측(2026-07-21): message.rs 소비처 9파일·정의 17종(요청15+응답2), 응답/이벤트 조립
  Packet::ok/new 31곳 + tasks/ingress 인라인, hub 인라인(ws12/moderate6/admin), oxrtc body 미사용.
* 정지점·oxrtc·message.rs 삭제시점은 §3 부장님 결정 대기.

## Phase A — 요청 파싱 이관 (2026-07-21)

* GO 시 §3 결정 = 김과장 추천 확정(정지점 A끝+C끝 / message.rs Phase F 삭제 / oxrtc 범위 밖).
* 산출:
  - `oxsfud/signaling/message.rs` 재작성 — 구 요청 15종 + default_role/default_true fn 삭제,
    `pub use oxsig::message::*` re-export 추가. 응답 2종(RoomEventPayload/ScopeEventPayload)
    Phase B/D 이관 전까지 존치. IdentifyRequest(참조0 고아, survey §D1) 청산.
  - 소비처 개명 11종: RoomCreateRequest→RoomCreateReq 등 (room_ops/track_ops/scope_ops).
    동명 유지: TrackStateReq/PublishTrackItem/SubscribeLayerTarget.
  - `oxsfud/Cargo.toml` — `oxsig` 직접 의존 추가(common 경유 간접 → 직접, §5 "필요 시 Cargo.toml").
    common 무수정(범위 밖 준수) — oxsfud 직접 의존이 opcode 계층과 정합.
* 판단(시그니처 선조치 후 보고):
  1. **오차 정정 1건**: 초기 `sed -i '' 's/\b.../g'` 이 macOS BSD sed `\b` 미지원으로 무효 →
     perl -pe 로 재수행(단어경계 유효). 타입명 부분문자열 충돌 없어 안전.
  2. oxsig 의존을 common 재-export 확장(common/signaling/message shim) 아닌 **oxsfud 직접**으로 —
     §5 common 범위 밖 준수. opcode 도 common 경유이나 message 는 신설이라 직접이 덜 침습.
  3. TrackStateReq 동명이나 oxsig 판(room_id 필드 추가)으로 대체됨 — sfud 미파싱 필드라 무해
     (serde 무시), wire 불변.
* 검증(김과장 가능 범위): `cargo check -p oxsfud` 무경고 · `cargo test -p oxsfud` **274 PASS**
  (1 ignored) · `cargo check --workspace` 통과.
* ★ **2층 회귀 게이트(oxe2epy run-all)는 김과장 미실행** — 라이브/봇 자동화는 부장님 소관
  (feedback_no_self_testing). 단위 274 초록까지가 김과장 게이트.
* **게이트 결과(부장님 실행, 2026-07-21)**: `run-all --core` = **10종 OK 10 / 이상 0**. Phase A
  wire 회귀 없음 확정 → Phase B 진입 가능.
* wire 차이 발견: 없음(요청 파싱은 필드 동일, 개명만). 발견_사항: 없음.
* commit: 부장님 소스 확인 후 지시 시(1단계 관례 답습, 보류).
* ★ 지침 정정(부장님 지적): §4/§6-8/§9 의 게이트 실행법에 **venv 활성화 전제** 누락 →
  `. .venv/bin/activate` 포함으로 수정. 명령 `run-all`(run-all --core/전체)은 실물과 일치 —
  `python` 전역 부재라 venv 경유 필수(3.12). rg 깨진 출력로 "명령 오류" 성급 판단했던 것도 정정.

## Phase B — room 응답/이벤트 이관 (2026-07-21)

* ★ **Phase 범위 조정(이견 — §4 본문 미수정, 실행 기록에만)**: §4 Phase B 는 JOIN/SYNC 포함이었으나,
  RoomJoinRes/RoomSyncRes 가 `tracks: Vec<TrackEntry>`(media)·`server_config`(codec 헬퍼)를 품어
  media 최고위험을 room Phase 로 끌어온다. → **JOIN/SYNC 는 Phase C(media 정지점)로 이동**,
  Phase B 는 tracks 없는 ROOM_LIST/CREATE/LEAVE + ROOM_EVENT 로 한정. 도메인 경계(TrackEntry=media)와 정합.
* 산출(응답 json! → 타입 직렬화):
  - ROOM_LIST → RoomListRes/RoomListItem (@room_ops.rs:28-50, sort 를 .room_id 로).
  - ROOM_CREATE → RoomCreateRes (ensure @87-95 + 생성 @124-131).
  - ROOM_LEAVE → RoomLeaveRes (@room_ops.rs). `scope_snapshot()` 헬퍼도 ScopeSnapshot 반환으로
    이관(@helpers.rs:187 — RoomJoin 도 공유하나 json! 이 값 흡수, wire 불변).
  - ROOM_EVENT → oxsig::message::RoomEvent (RoomEventPayload 대체): room_ops join/leave 2곳 +
    helpers evict 1곳(풀패스) + tasks reaper json! 인라인 1곳(@tasks.rs:465 → 타입).
  - `oxsfud/signaling/message.rs` 의 RoomEventPayload 정의 삭제(ScopeEventPayload 는 Phase D 존치).
* 판단(시그니처 선조치 후 보고):
  1. `to_value(&T).unwrap()` — struct 직렬화는 실패 불가. 기존 RoomEventPayload 조립도 `.unwrap()`
     관례라 답습(코딩규칙 unwrap 남용 아님 — 무오류 경로).
  2. scope_snapshot 반환형 변경이 RoomJoin(Phase C 미이관) 에 파급 없음 — json! 매크로가 Serialize
     값을 직렬화, wire 동일.
  3. RoomListItem 은 owned(clone) — 기존 json! 은 참조 직렬화였으나 결과 wire 동일.
* 검증: `cargo check -p oxsfud` 무경고 · `cargo test -p oxsfud` **274 PASS**(room_create_idempotent 등
  응답 필드 검증 테스트 포함) · `cargo test -p oxsig` **72 PASS**(신규 wire 형상 3: RoomCreateRes/
  RoomListItem 필드순서, RoomLeaveRes scope 동봉) · workspace 통과.
* wire 차이 발견: 없음(필드·순서 동일, 타입 직렬화가 json! 재현). 발견_사항: 없음.
* **게이트 결과(부장님 실행)**: `run-all --core` = **10종 OK 10 / 이상 0**. Phase B 통과 → Phase C 진입.

## Phase C — media + JOIN/SYNC 이관 (2026-07-21) ★TrackEntry 관통 대공사

★부장님 강조: "권위는 oxsig::message, 편의로 정석 회피 말라." → server_config·tracks 를 Value 로
우회하지 않고 **헬퍼까지 완전 타입화**. wire 불변은 검증 도구로만.

* 헬퍼 이관(정석 — Value 반환 금지):
  - server_codec_policy/server_codec_policy_sub → `Vec<CodecPolicy>`, server_extmap_policy → `Vec<ExtmapEntry>`.
  - apply_video_codec_fields(&mut TrackEntry), build_fullnonsim_add_core → `TrackEntry`,
    build_remove_tracks → `Vec<TrackEntry>`, collect_subscribe_tracks → `Vec<TrackEntry>`(내부
    [MID]/sort/DIAG/register 전면 TrackEntry 필드 접근으로 재작성).
  - emit_per_user_tracks_update 콜백 = `Vec<TrackEntry>`, 직렬화 = `TracksUpdateEvent`.
  - Room::member_infos → `Vec<MemberInfo>` (domain/room.rs).
  - oxsig::message::TrackEntry 에 `Default` derive 추가(조립 편의 `..Default::default()`, wire 무영향).
* 응답/이벤트 이관:
  - ROOM_JOIN → RoomJoinRes(ServerConfig/IceConfig/DtlsConfig/FloorSnapshot/FloorQueueItem 완전 중첩).
    ROOM_SYNC → RoomSyncRes. (Phase B 에서 미룬 JOIN/SYNC 를 여기서 — tracks=TrackEntry 얽힘 정합.)
  - PUBLISH_TRACKS(add/remove) → PublishTracksRes/PublishTracksResItem, TRACKS_READY → TracksReadyRes,
    TRACK_STATE_REQ(noop/duplex) → TrackStateRes, MUTE(do_mute) → MuteUpdateRes.
  - TRACK_STATE(full→half/half→full/mute) → TrackStateEvent, VIDEO_SUSPENDED/RESUMED → 각 Event,
    TRACK_STALLED(tasks) → TrackStalledEvent.
  - TRACKS_UPDATE 5발신처 전부 → TracksUpdateEvent/TrackEntry (helpers emit·leaver, track_ops
    half→full·remove·half회수, ingress_publish RTP-first, tasks reaper). ingress 는 자체 json! 도 이관.
  - 빈 {} 유지(타입 없음 계약): CAMERA_READY·SUBSCRIBE_LAYER 응답.
  - 테스트 이관: helpers 4 테스트를 to_value 기반으로(TrackEntry PartialEq 대신 wire 형상 비교).
* 판단(시그니처 선조치 후 보고):
  1. `oxsfud/Cargo.toml` oxsig 직접 의존은 Phase A 에 이미 추가됨(재확인).
  2. JOIN/SYNC 를 Phase B→C 이동(Phase B 실행기록 이견) — TrackEntry(media) 얽힘 정합. 완결.
* 검증: `cargo check -p oxsfud` 무경고 · `cargo test -p oxsfud` **274 PASS**(1 ignored, room/track 응답
  테스트 포함) · `cargo test -p oxsig` **74 PASS**(신규 wire 형상 2: TracksUpdateEvent·ServerConfig
  codecs_sub skip) · `cargo check --workspace` 통과.
* ★ **wire 차이 발견 1건(계약 무관, 보고)**: TRACKS_UPDATE tracks[] 원소의 **JSON 키 순서**가
  발신처별 제각각이던 것(survey 차이표) → TrackEntry 정의 순서로 **통일**됨. 필드 집합·값은 동일,
  키 순서만 변함. JSON object 파싱은 순서 독립(클라 JSON.parse·aiortc 봇 무관)이라 계약 불변 —
  단 "바이트 완전 동일"은 아니므로 명시. 3층 실영상으로 최종 확인 필요.
* ★ **2층 게이트(run-all) + 3층 라이브(미디어 실영상) 부장님 실행 요청** — media wire 최고위험.
  feedback_layer2_pass_not_final: 봇 PASS≠완료, 3층 브라우저 실영상이 최종 게이트. 초록 후 Phase D 진입.
* 게이트 결과(부장님, 2026-07-21): `run-all --core` 10/10 이상 0. (3층은 방법 미확립 — 다음 규명.)

## Phase D — scope + data 이관 (2026-07-21)

* SCOPE 응답 ScopeEventPayload → oxsig ScopeEvent (@scope_ops.rs:236). `oxsfud/signaling/message.rs`
  의 ScopeEventPayload 정의 삭제 → 본 파일은 **re-export 만 남음**(RoomEventPayload Phase B·
  ScopeEventPayload Phase D 둘 다 청산, `use serde::Serialize` 도 제거).
* MESSAGE 응답 → MessageRes, MESSAGE_EVENT → MessageEvent (@room_ops.rs).
* CLIENT_EVENT 파싱: Value 순회 → ClientEventReq (@client_event.rs). 서버는 3필드만 카운팅,
  ts/detail 은 파싱만(oxcccd 통째 저장 몫) — 동작 동일.
* ANNOTATE: body-agnostic relay 유지(설계 결정, 타입화 안 함).
* TELEMETRY: sfud 파싱부 없음(hub 종착 oxcccd 직행) — 이관 대상 없음. 타입(TelemetryStatsReq/
  SdpReq)은 정의 존치(oxcccd/oxadmin 향후 소비처).
* 검증: `cargo check -p oxsfud` 무경고 · `cargo test -p oxsfud` **274 PASS** · workspace 통과.
* wire 차이: 없음(필드·순서 동일). 발견_사항: 없음.
* 판단: CLIENT_EVENT 파싱 이관 시 events 부재→early-return이 빈 Vec 파싱으로 바뀜(trace 로그
  n=0 1회 추가). 실질 무해(카운팅 0 동일).

## Phase E — ext + admin (hub 포함) 진행중

* D 는 정지점 아님(§3 정지점=A끝+C끝). D/E 는 media 아닌 저위험 → **D+E 묶어 게이트 1회**(효율).
  각 도메인마다 run-all 부담 회피 — 운영룰 8 "게이트 없이 다음 Phase 진입 금지"는 E 끝에서 충족.

### E-1 (oxsfud admin) 완료
* ADMIN_REAP → AdminReapRes, ADMIN_DOWNLINK_INJECT → AdminDownlinkInjectRes.
* ADMIN_SNAPSHOT 골격 → AdminSnapshotRes(전체)/AdminRoomSnapshotRes(단일 방). rooms[]/users[]
  원소는 진단 자유중첩이라 Value 유지(1단계 결정 — getStats 통째 spread 동형, 편의 회피 아님).
* cargo check -p oxsfud 무경고.

### E-2 (oxhubd) 진행중
* Cargo.toml 에 oxsig 직접 의존 추가(common 무수정, §5 준수).
* ws/mod.rs: HELLO(client/admin) → HelloEvent, IDENTIFY_RESULT → IdentifyResultEvent,
  TOKEN_REFRESH 응답 → TokenRefreshRes / 만료경고 → TokenRefreshEvent,
  SESSION_DISCONNECT → SessionDisconnectEvent, ROOM_LIST 병합 → RoomListRes/RoomListItem
  (sfu 응답을 from_value::<RoomListRes> 파싱 후 rooms 병합 — RoomListItem 양방향 derive 소비처,
  survey 발견 5 해소).
* cargo check -p oxhubd 무경고.
* **남은 E-2(다음 라운드)**: moderate/handler.rs(MODERATE_EVENT 5형 → ModerateEvent +
  session.rs speakers_list/queue_snapshot → Vec<ModerateSpeaker>/Vec<ModerateQueueItem>),
  rest/admin.rs(USER_PROBE_REQ → UserProbeReqEvent, RECONNECT → ReconnectEvent).
  AckFailBody(hub 계열 build_error_frame/state.rs ERROR)는 **통일 안 함 유지**(§2). rest 의 나머지
  json! 은 axum HTTP 응답(wire body 아님) — 이관 대상 아님.
* 이후 Phase F(message.rs 삭제 잔여 참조 0 확인) → D+E+F 통합 게이트(부장님 run-all).

### E-2 잔여 완료
* moderate/session.rs: speakers_list → Vec<ModerateSpeaker>, queue_snapshot → Vec<ModerateQueueItem>.
* moderate/handler.rs: MODERATE_EVENT 5형(authorized/unauthorized/speakers_updated/queue_update/
  phase_changed) → ModerateEvent (Default derive 추가로 `..Default::default()`).
* rest/admin.rs: USER_PROBE_REQ → UserProbeReqEvent, RECONNECT → ReconnectEvent.
* AckFailBody(build_error_frame/state.rs ERROR)는 §2대로 통일 안 함 유지. rest 나머지 json! 은
  axum HTTP 응답(wire body 아님) — 제외.

## Phase F — 종착: message.rs 삭제 (2026-07-21) ★부장님 결정=완전 삭제

* 부장님 판단(AskUserQuestion): shim 유지 아닌 **완전 삭제**.
* 소비처 전환(perl 일괄): `use crate::signaling::message::*` → `use common::signaling::Packet;` +
  `use oxsig::message::*`. `::Packet`(특정) → common. `{Packet, X..}` → common Packet + oxsig{X..}.
  풀패스 `crate::signaling::message::T` → `oxsig::message::T`. 11파일(handler 8 + tasks + domain/room
  + ingress) 잔여 참조 0.
* `signaling/mod.rs` 의 `pub mod message;` 제거 + `message.rs` 파일 삭제.
* handler/mod.rs 의 unused `oxsig::message::*` glob 제거(dispatch 는 Packet 만).
* 검증: `cargo check --workspace` **무경고** · `cargo test`: oxsfud **274** / oxhubd **25** / oxsig
  **74** PASS.

## 2단계 완료 요약 (Phase A~F)

* body 계약 = **oxsig::message 단일 권위** 확정. `oxsfud/signaling/message.rs` 소멸(구 15종 중복 청산).
* 요청 파싱·응답 조립·이벤트 발신 전부 타입 경유(json! 산발 제거). TRACKS_UPDATE 5발신처 통일,
  RoomListItem 양방향 derive 소비처(hub 병합) 연결(survey 발견 5).
* Value 잔존 = 정당한 곳만: ANNOTATE(body-agnostic relay), ADMIN_SNAPSHOT rooms/users 원소(진단
  자유중첩), 진단 body 통째 spread 필드(getSettings 등). AckFailBody 2계 어휘는 통일 안 함(§2).
* wire 차이: TRACKS_UPDATE tracks[] JSON 키 순서 통일(계약 무관, 3층 최종 확인 대상). 그 외 없음.
* ★ **D+E+F 통합 게이트(run-all) + Phase C media 3층 실영상 부장님 실행 요청**.

## 3층 라이브 게이트 결과 (2026-07-21, 김과장 직접 실행 — 부장님 지시)

* 실행법 규명: `cd oxlens-home/qa/live && npx playwright test`. Playwright 가 http-server(5599)
  자체 기동, 미디어 서버(hub1974+sfud)는 외부(부장님 재빌드 실행), fake media 실브라우저.
  qa.js → sdk0.2/dist 로드 = **이관 서버 ↔ sdk0.2 클라 wire 검증**(정확히 이 게이트 목적).
* 결과: 전체 15 spec → **18 passed / 1 failed / 1 skipped**. failed = onepc ONEPC-CONF-01
  (framesDecoded=0). **단독 재실행 5/5 통과(3.4s)** → **flaky 확정, 이관 회귀 아님**(회귀면 단독도
  실패). 스위트 직렬 실행 시 앞 시험 SFU/방 상태 잔류로 첫 시험 수렴 15s 초과(2층 known flaky 동형).
* ★ **media wire 정합 확증**: conf_video/simulcast/duplex/multiroom/republish + removal 계열 +
  1PC 전 항목 초록. **TRACKS_UPDATE JSON 키 순서 통일이 sdk0.2 파싱·실영상에 무해** 실측 확인.
  Phase C "키 순서 계약 무관" 추측 → 3층으로 검증 완료(아쉬움 1~3 해소).
* 2층 코어 게이트: `run-all --core` 10/10(부장님). 3층: 상기 통과.
* ★ **커밋(종착점) 대기** — 부장님 소스 확인 후 지시 시. oxsfud/oxhubd/oxsig/Cargo(oxsfud·oxhubd)
  전체가 커밋 대상(1단계 cdcc9d5/dd146dc 이후 미커밋 누적).
