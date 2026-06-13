# 작업 지침 — domain/signaling/transport 네이밍 부채 청산 (거짓 이름 + 주석 불일치)
> 완료 보고 → [20260603b_naming_cleanup_done](../../202606/20260603b_naming_cleanup_done.md)

> 작성: 김대리 / 결재: 부장님 ("전부 간다", ★1·2·3 전부 확정) / 구현: 김과장
> 토픽: naming_cleanup · 일자: 2026-06-03(b) · 직전: 20260603_doc_split / 0603 식별 계층 재설계 A·B(`8b0627a`/`208a498`)

---

## §0 의무 점검

- [ ] `PROJECT_MASTER.md` / `PROJECT_SERVER.md` 통독 (2계층 명명 streams=논리/tracks=물리, 식별 3평면 track_id/vssrc/실ssrc, Scope 모델 Primitive 표 affiliate/deaffiliate)
- [ ] **시작 전 `cargo test` GREEN 수 실측** — 동작 변경 0이므로 *종료 시 같은 수* 유지가 유일한 검증 기준. (0603 기준 204 추정 — 실측값 done 보고에 박을 것)
- [ ] `git status` clean 확인 후 진입
- [ ] QA_GUIDE / METRICS_GUIDE 로드 불필요 (시험·스냅샷 세션 아님)
- 본 작업은 **rename + 주석 수정만**. 로직/제어흐름/자료구조 변경 절대 금지.

---

## §1 컨텍스트

세 영역(domain/ · signaling/handler/ · transport/udp/)에 걸쳐 **마이그레이션이 이름을 안 따라간** 네이밍 부채. 출처 패턴 3종:

1. **폐기된 개념을 이름이 계속 가리킴** — lazy CAS→eager, TRACKS_ACK→READY, Endpoint→Peer, Pan-Floor/FLOOR_PING 폐기, simulcast 한정인데 일반명
2. **2계층 전환(streams=논리/tracks=물리)이 변수·인자·주석에 미반영** — 물리 `PublisherTrack`을 `stream`으로 호칭
3. **주석/doc이 폐기된 상태·동작을 서술** (거짓 doc)

상당수는 코드 주석에 **본인들이 거짓을 자백**해 둠 (`endpoint_map` "F3 정리 예정", `ensure_*` "ensure=단순 조회", `virtual_ssrc` "virtual 의미 보장 안 함"). 논쟁 여지 없는 청산 대상.

---

## §2 결정된 사항

### 그룹 ① 거짓 의미 (함수·메서드·필드 rename)

| ID | 현재 | → 확정 | 위치 | 근거 |
|---|---|---|---|---|
| A5 | `ensure_simulcast_video_ssrc` (Peer + RoomMember) | **폐기**, `simulcast_video_ssrc`로 통합 | peer.rs / participant.rs | 주석 자백 "ensure=단순 조회", 본문 동일 |
| A6 | `Room::find_publisher_by_vssrc` | `find_publisher_by_simulcast_vssrc` | room.rs | 주석 자백 "동작은 simulcast 한정" |
| A7 | `Room::find_by_track_ssrc` | `find_publisher_by_ssrc` | room.rs | 자매 3메서드 중 반환 대상(publisher) 누락 — 일관성. 코드베이스가 RoomMember를 "publisher"로 호칭 |
| S1 | `handle_tracks_ack`/`do_tracks_ack`/`TracksAckRequest` | `handle_tracks_ready`/`do_tracks_ready`/`TracksReadyRequest` | track_ops.rs | op은 TRACKS_READY, wire `is_ack()`와 충돌 |
| T1 | `UdpTransport.endpoint_map` 필드 | `peer_map` | transport/udp/mod.rs + 전체 참조 | 주석 자백 "타입만 PeerMap, F3 정리 예정" |
| SC-1 | `Peer::sub_insert` / `sub_remove_one` | **`affiliate` / `deaffiliate`** | peer.rs | ★결정1=affiliate 확정. 클라(`engine.scope.affiliate`)·문서(Primitive 표 affiliate(R))·서버 삼자 정합 |
| SC-2 | `Peer::scope_insert` / `scope_remove` | **`sync_scope_on_join` / `sync_scope_on_leave`** | peer.rs | "scope를 insert" 동사 오용 제거. **scope 명사는 유지** — 이 cascade는 sub_rooms(affiliation)+pub_room(selection) *둘 다* 동기화하므로 둘을 묶는 우산 명사 scope가 정확 (affiliate로 못 덮음). 본문 불변, 이름만 |

> **scope 어휘 방침** (부장님 결정): `scope`는 affiliation+selection을 묶는 **우산 명사로 정당** — 청산 안 함. 클라도 `engine.scope.*` 네임스페이스로 동일 사용 → 헷갈림 방지 위해 유지. `engine.scope.affiliate()`는 네임스페이스.동사 정합(모순 아님). **"scope가 동사처럼 쓰인 자리"(scope_insert/remove)만** 정리 대상.

### 그룹 ② 거짓 타입 (변수·인자 rename — 동작 0, 컴파일러 검증)

| ID | 자리 | 현재 → | 위치 |
|---|---|---|---|
| A2 | `publish.tracks.load()` 받는 변수 | `streams` → `tracks` | publisher_track.rs `broadcast`, peer.rs 다수 (`.iter()` 클로저 `s` 포함 검토) |
| A3 | `create_or_update_at_rtp` 반환 | `new_stream` → `new_track` | publisher_track.rs |
| A4 | 테스트 변수 | `pub_stream` → `pub_track` | publisher_track.rs subscribers_tests |
| T2 | **hot path** | `stream` → `track` (`stream.fanout`→`track.fanout`) | ingress.rs `handle_srtp` |
| S2 | `find_publisher_track` 받는 변수 | `pub_stream_arc` → `pub_track` | track_ops.rs `do_publish_tracks` + `handle_track_state_req`(2자리) |
| B-idx | `with_added(stream: Arc<PublisherTrack>)` 인자 + "스트림" 주석 | `track` | publisher_track_index.rs |

> ⚠️ 로컬 변수/인자/클로저만. 필드명 `publish.tracks`(물리=정합)/`publish.streams`(논리=정합), 타입명 `PublisherStream`/`SubscriberStream` 은 **건드리지 말 것**.

### 그룹 ③ 주석/doc 불일치 (동작 0, 컴파일 영향 0)

| ID | 거짓 주석 | 사실 | 위치 |
|---|---|---|---|
| C1 | "Prepared 상태 비가시" / "Prepared / Taken(other) / Idle" | FloorState에 Prepared 없음 (Pan-Floor 폐기) | floor.rs `current_speaker` / `ping()` |
| C2 | RoomMember `ensure_*` doc "lazy 할당(CAS)" | eager (A5와 모순) | participant.rs |
| C3 | `cancel_pli_burst` doc "이 **publisher**의 모든 burst" | 이 논리 Stream(source) 1개만 | publisher_stream.rs |
| C4 | `PublishContext.streams` 주석 "`streams`(물리 Track)" | 논리 PublisherStream 컨테이너 | peer.rs |
| C5 | PublisherTrackIndex doc/주석 "스트림" 다수 | 물리 PublisherTrack | publisher_track_index.rs |
| C6 | `endpoint_map`/"EndpointMap이 소유" 주석군 | PeerMap (T1 동반) | mod.rs / ingress.rs / room.rs |
| C7 | mod.rs 모듈 doc "track_ops: ... ACK ..." | READY (S1 동반) | signaling/handler/mod.rs |
| C8 | `build_remove_tracks` "Track struct 내부 ID와 다름" 류 | 표현 유지하되 track_id 평면(식별 계층 0603) 정합 확인 | helpers.rs |

> **김과장 위임**: 위는 김대리 관측분. 같은 부류 *추가* 거짓 주석(폐기 잔재: SwitchDuplex/op=52, MediaIntent, Pan, RtpStream(map), simulcast_group, room_stats, recv_stats/send_stats 구명칭 등) grep 발굴해 함께 정합. §5 범위 밖 파일은 *발견_사항* 보고만.

### 보류 (본 작업 제외)

- **A1 `SubscriberStream.virtual_ssrc` → `egress_ssrc`** (★결정3=제외). `by_vssrc` 인덱스 키·`SubscriberStreamIndex` API·`SrStats::new`·fanout/egress 핫패스·`Slot.virtual_ssrc`(진짜 가상=유지) 어휘 충돌 + 0603 식별 계층과 얽힘. → **식별 계층 후속 토픽**. done에 "이관" 명시만.
- **SCOPE op(0x1200) affiliation 정직화** (부장님 결정=별 토픽). SCOPE op은 실제론 sub_rooms(affiliation)만 바꾸고 pub_room(selection)은 안 건드림 → 엄밀히 `AFFILIATE`가 정직하나, **wire 프로토콜 변경 + 클라(constants.js opcode 카탈로그) 동반**이라 "동작 0 / 서버 내부 한정" 성격을 깸. scope 명사 자체는 정당하므로 우선순위 낮음. 별 토픽 후보로만 박아둠.
- room.rs YAGNI dead enum (`SsrcKind`/`RtpDispatchResult`/`DiscardReason`/`LookupResult` + `lookup_publisher_for_ssrc`) — Phase D.3 진입 시. 비대상.

---

## §3 결정 (전부 확정 — 미결 없음)

- **★결정1 = affiliate (A) 확정**: `sub_insert`→`affiliate`, `sub_remove_one`→`deaffiliate`. cascade `scope_insert`→`sync_scope_on_join`, `scope_remove`→`sync_scope_on_leave` (scope 명사 유지). 사유: 클라 `engine.scope.affiliate/deaffiliate` + 문서 Primitive 표 affiliate(R)/deaffiliate(R) 삼자 정합. (B `add_sub_room`은 삼자 어휘 분열로 기각)
- **★결정2 = `find_publisher_by_ssrc` rename 확정** (A7).
- **★결정3 = A1 제외 확정**: 식별 계층 후속 이관.
- scope 전면 청산(SCOPE op·네임스페이스) = 안 함 (보류, 별 토픽).

---

## §4 단계별 작업

> 동작 변경 0. 각 Phase 후 `cargo test` GREEN 수 불변 확인. **컴파일 통과 = 호출처 정합 완료**를 1차 검증으로.

### Phase A — 그룹 ③ 주석/doc 청산 (정지점 없음)
- C1~C8 + grep 발굴분. 코드 토큰 미변경(주석/doc 문자열만).
- grep: `Prepared`, `lazy 할당`, `CAS`, `EndpointMap`, `endpoint_map`(주석), `물리 Track`(streams 문맥), `SWITCH_DUPLEX`, `op=52`, `MediaIntent`, `RtpStream`, `simulcast_group`, `recv_stats`, `send_stats`, `room_stats`.
- 한글 주석 다수 — `write_file` 전체 덮어쓰기 권장(NFC/NFD silent fail 회피).
- **검증**: `cargo build` 통과, 테스트 수 불변.

### Phase B — 그룹 ② 거짓 타입 변수 rename (정지점 없음)
- A2/A3/A4/T2/S2/B-idx. 로컬 바인딩·인자·클로저만. 클로저 `|s|`는 혼동 유발 자리만.
- **검증**: `cargo build` + `cargo test` GREEN 불변.

### Phase C — 그룹 ① 의미 rename (★정지점 1: Phase C 끝)
- 순서: A5 → A6 → A7 → S1 → T1 → SC-1(affiliate/deaffiliate) → SC-2(sync_scope_on_join/leave).
- **S1**: 함수·요청타입·내부 doc(`record_stalled_snapshot`)만. **opcode 상수 TRACKS_READY·wire·클라 절대 불변** — 클라 영향 0 done 명시.
- **T1**: `endpoint_map` rename = `UdpTransport` 정의 + `bind`/`from_socket_with_id` 생성자 + 모든 `self.endpoint_map.*`. grep 전수.
- **SC-1**: `sub_insert`/`sub_remove_one`은 SCOPE op 핸들러(scope_ops.rs) 호출처 정합. 시그니처·반환 불변, 이름만. **SCOPE op 자체·wire는 불변** (보류 항목).
- **SC-2**: `scope_insert`/`scope_remove`는 `join_room`/`leave_room` 내부 단일 호출. 시그니처·반환·본문 불변, 이름만.
- grep(호출처): `find_publisher_by_vssrc`, `find_by_track_ssrc`, `ensure_simulcast_video_ssrc`, `handle_tracks_ack`, `do_tracks_ack`, `TracksAckRequest`, `endpoint_map`, `scope_insert`, `scope_remove`, `sub_insert`, `sub_remove_one`.
- **검증**: `cargo build` + `cargo test` GREEN 불변. → **정지점: commit + 부장님 보고 + GO**.

---

## §5 변경 영향 범위

- **domain/**: peer.rs, participant.rs, publisher_track.rs, publisher_track_index.rs, publisher_stream.rs, room.rs, floor.rs
- **signaling/handler/**: mod.rs, track_ops.rs, helpers.rs, scope_ops.rs(SC-1 호출처)
- **transport/udp/**: mod.rs, ingress.rs (+ endpoint_map 참조 있는 모든 파일 — grep)
- **클라(oxlens-home) wire 영향 = 0** — 전부 서버 내부 식별자/변수/주석. opcode(TRACKS_READY/SCOPE)·wire·JSON 키·`engine.scope.*` 네임스페이스 전부 불변. (S1·SC-1이 의심점이나 서버 함수명만이라 무영향 — done에 확인 박을 것)
- `subscriber_stream.rs` / `subscriber_stream_index.rs` = **비대상** (A1 보류). 손대지 말 것.
- 범위 밖 파일 손대지 말 것. 별 발견은 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점**: Phase C 끝(1). 그 외 통합 리뷰.
2. **동작 0 불변식**: 매 Phase `cargo test` GREEN 수 = 시작 실측값. 1개라도 변하면 = rename이 동작 건드림 → 중단·보고.
3. **추가 변경 금지**: §5 범위 밖, 로직 변경, "겸사겸사 개선" 금지.
4. **시그니처 선조치 후 보고**: 호출처 의존 rename은 grep 정합 후 박고 사후 보고.
5. **2회 실패 시 중단**.
6. **rename ≠ 동작**: rename이 제어흐름·자료구조를 바꿔야 한다면 rename 아님 → 멈추고 보고.

---

## §7 기각 접근법

- **A1을 본 묶음에 합치기** — ★결정3 제외 (식별 계층 후속)
- **scope 명사 청산 / SCOPE op rename** — scope는 정당한 우산, 클라도 동일 사용. op rename은 wire/클라 동반이라 본 작업 범위 밖 (별 토픽 보류)
- **`add_sub_room`류 flat 어휘** — 클라/문서 affiliate와 삼자 분열 (★결정1로 기각)
- **주석만 고치고 이름 방치** (또는 역) — 그룹 ②·③은 짝. C2↔A5, C4↔A2, C6↔T1, C7↔S1 동반
- **일괄 치환(sed류)** — 클로저 `s`/짧은 변수 오검. Phase·항목 단위로
- **필드명 `publish.tracks`/`streams`·타입명 손대기** — 이미 정합. 회귀

---

## §8 산출물

- 코드: §4 Phase별 rename + 주석 정합
- 완료 보고: `~/repository/context/202606/20260603b_naming_cleanup_done.md` — Phase별 변경 파일·라인 수, 시작/종료 `cargo test` GREEN 수(불변 입증), 클라 wire 무영향 확인, grep 발굴 추가분, A1·SCOPE op "별 토픽 이관" 명시
- master 반영: PROJECT_SERVER.md 소스 구조 주석의 식별자명 변경분(affiliate/deaffiliate, peer_map, sync_scope_on_join 등) 정합 필요분 done에 적시 (적용은 김대리 판단)

---

## §9 시작 전 확인

- [ ] `cargo test` GREEN 수 실측·기록
- [ ] `git status` clean
- [ ] 2계층 명명·식별 3평면·scope 어휘 방침 숙지
- 비고: **★1·2·3 전부 확정, 미결 없음.** Phase A·B·C 전부 즉시 진입 가능 (정지점은 Phase C 끝 1개).

---

## §10 직전 작업 처리

- 0603 식별 계층 재설계 A·B(`8b0627a`/`208a498`) 직후. C8(track_id 주석)은 그 결과와 정합 확인.
- 20260603_doc_split(문서 분리)와 충돌 없음 (이쪽 코드, 저쪽 md).

---

*author: kodeholic (powered by Claude)*
