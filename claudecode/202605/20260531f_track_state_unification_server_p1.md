// author: kodeholic (powered by Claude)
# 작업 지침 — Track State 통일 + 식별 계층 재설계 (서버)

- 지침 ID: `20260531f_track_state_unification_server_p1`
- **갱신: rev.3 (설계서 rev.3 = 0602e 기준)** — rev.1(역추출·self-unicast)·rev.2(room/ 경로·find_by_vssrc 라우팅) 폐기. **0602e `domain/` 구조 + fan-out 방향 역전 + stats 트랙 직속** 반영.
- 작성: 김대리 (claude.ai) / 구현: 김과장 (Claude Code)
- 선행 설계서: `context/design/20260531_track_state_unification.md` **rev.3**
- 범위: 서버 `oxsfud` **Phase 1~2**. 클라(§8-3~6) 별도 세션.

---

## §0 의무 점검 (시작 전)

1. **설계서 rev.3 정독** — §0 식별 3평면(track_id 불투명 / vssrc 값·라우팅 키 아님 / 실ssrc) + §2 결정 A(논리 Stream 정합 근거) + §7 + §10.
2. **`git status` clean 확인** — 2계층은 0602 까지 커밋 완료(rev.2 의 "미커밋 충돌" 경고는 무효). working tree 깨끗한지만 확인.
3. cargo test 211(0602e baseline 205~211 — scope 테스트 동반 삭제분 반영) + clippy + **oxe2e 4/4**(conf/ptt/duplex/simulcast) PASS = 완료 기준.

---

## §1 컨텍스트 — 왜 / 0602e 검증 사실

**왜**: simulcast 가 물리 Track 마다 track_id(h/l/placeholder 3개)로 흩어져 **클라 1 Pipe(1 trackId) ↔ 서버 다수** 계층 불일치(#5b). track_id·vssrc 를 **논리 `PublisherStream`** 으로 올려 클라 `MediaStream`(=Pipe) 계층과 정합 + 불투명 키 조회 + self-unicast 제거.

**0602e 검증 사실** (김대리 코드 확인 완료):
- 경로 **`crates/oxsfud/src/domain/`** (구 `room/` 폐기). enum 은 **`domain/types.rs`** (`TrackType`/`DuplexMode`/`TrackKind`/`VideoCodec`/`StreamKind`).
- 논리 Stream 컨테이너 = **`PublishContext.streams: ArcSwap<Vec<Arc<PublisherStream>>>`**(peer.rs:332). 물리 = `publish.tracks: ArcSwap<PublisherTrackIndex>`(by_ssrc/by_rtx_ssrc).
- 논리 Stream 발급 단일 자리 = **`Peer::attach_track_to_stream`(peer.rs:720)** → `PublisherStream::new`(727). `register_publisher_track`(946)이 RTX 제외하고 호출.
- `PublisherStream`(publisher_stream.rs): 현재 `pli_state`/`tracks` 만. **vssrc·track_id 없음**(이주는 신설).
- `PublisherTrack`(publisher_track.rs): `track_id: Arc<str>`·`virtual_ssrc: AtomicU32` 직속(**제거 대상**). `rr_stats`·`pub_pipeline_stats`·`rtp_cache`·`nack_generator`·**`subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>`(방향역전)** 직속(유지). `stream: ArcSwap<Option<Weak<PublisherStream>>>` 역참조 + `stream()` 메서드 보유.
- **fan-out 방향 역전**(0528~0601): `fanout()→track_type()→broadcast()` 가 `subscribers` Weak Vec 직접 순회. **vssrc 역탐색 폐기**. → vssrc 는 라우팅 키 아님.
- vssrc hot-path = `SubscriberStream.virtual_ssrc`(복사본). publisher Stream.vssrc 는 **subscribe 등록(`collect_subscribe_tracks`, cold-path) 1회** 읽힘 → 이주 hot-path 비용 0.
- `switch_track_duplex`(peer.rs:832) = 호출처 **테스트 3줄(1239~41) 뿐 = dead 확정**.
- `set_track_muted`(peer.rs:845) = `current.get(ssrc)` ssrc 1개 → **Stream 단위 교체 대상**.
- `find_publisher_track`(peer.rs:859) by_ssrc(ingress 라우팅 — **유지**). `ensure_simulcast_video_ssrc`(917) = first video Track lazy → Stream.vssrc 전환 대상.

---

## §2 결정된 사항 (설계서 rev.3)

1. **track_id·vssrc 소유 = 논리 `PublisherStream`** 신설. 물리 `PublisherTrack` 의 `track_id`·`virtual_ssrc` 제거(진단은 `stream()` 역참조).
2. **track_id 생성 = `{user}_{대표 ssrc}`** — non-sim/PTT=원본ssrc, simulcast=vssrc. `attach_track_to_stream` 발급.
3. **track_id 불투명** — `find_stream_by_track_id` 키 조회. 역추출 **금지**(반칙).
4. **vssrc eager**(simulcast) — Stream 생성 시 즉시. non-sim/PTT 는 0. **라우팅 평면 무변경**(Track.subscribers 직접 순회).
5. **학습 = PUBLISH_TRACKS `ok` 응답 `d.tracks=[{mid,track_id}]`** 단일. self-unicast 없음.
6. **mute/duplex = Stream 단위** — mute 는 `stream.tracks` 전체 set_muted(비대칭 해소). simulcast duplex reject.
7. **새 op 없음. ssrc 하위호환**. 변경 7영역(§5). **ingress 라우팅(실 ssrc)·fan-out(subscribers) 평면 무변경**.

---

## §3 결정 추천 (★ 정지점)

추가 결정 없음. 정지점 1개:

### ★ Phase A(식별 이주) 끝
물리↔논리 자료 이동(track_id/vssrc) + 방향 역전 구조 + snapshot/admin/ensure 광범위 참조 = **위험 phase**. cargo test + clippy + oxe2e 4/4 → commit + 보고 → GO → Phase B.

---

## §4 단계별 작업

### Phase A — 식별 이주 (★정지점)

**A-1. `domain/publisher_stream.rs`**
- `PublisherStream` 에 `pub track_id: Arc<str>` + `pub vssrc: AtomicU32` 추가.
- `new(user_id, source, kind, simulcast: bool, first_track_ssrc: u32)` 로 시그너처 확장:
  - `vssrc = if simulcast { rand_u32_nonzero() } else { 0 }`
  - `track_id = if simulcast { format!("{user}_{vssrc:x}") } else { format!("{user}_{first_track_ssrc:x}") }`
- `vssrc_load()` / `track_id()` 헬퍼.
- `rand_u32_nonzero` 는 publisher_track.rs 의 것 재사용(또는 도메인 공용 이동).

**A-2. `domain/publisher_track.rs` 필드 제거 + 역참조**
- `track_id: Arc<str>`, `virtual_ssrc: AtomicU32` + `ensure_virtual_ssrc`/`virtual_ssrc_load` 제거. `new()` 시그너처에서 track_id 인자 제거.
- `create_or_update_at_rtp`(신규 분기)의 `format!("{}_{:x}", ...)` track_id 생성 라인 제거.
- `snapshot().track_id` = `self.stream().map(|s| s.track_id().to_string())` 역참조. **stream() None 가드**(미배선 시 ssrc 문자열 fallback).
- ⚠️ `fanout()`/`broadcast()` 의 simulcast PLI burst 가 `find_ssrc_by_rid("h")` 쓰는 부분은 실 ssrc 라 무변경. vssrc 참조 없는지 확인.

**A-3. `domain/peer.rs`**
- `attach_track_to_stream`(720): `PublisherStream::new` 에 `track.simulcast` + `track.ssrc`(first_track_ssrc) 전달. (register 가 track add 후 호출이라 track.ssrc 가용 — §9 확인.)
- `find_stream_by_track_id(&str) -> Option<Arc<PublisherStream>>` + `find_stream_by_vssrc(u32) -> Option<Arc<PublisherStream>>` 신설(`publish.streams` 선형).
- `ensure_simulcast_video_ssrc`/`simulcast_video_ssrc`(910·917) → `first_stream_of_kind(Video).vssrc` 참조로 전환.
- `switch_track_duplex`(832) 정의 + 테스트(1239~41) 제거.

**A-4. 호출처 전환**
- `collect_subscribe_tracks`(helpers): SubscriberStream.virtual_ssrc 채울 때 publisher **Stream.vssrc** 읽도록(기존 ensure_simulcast_video_ssrc 경유면 자동). 정합 확인.
- admin/agg-log 의 물리 Track `.track_id` 참조 → `stream()` 역참조. ingress `find_publisher_track(ssrc)`(실 ssrc) **그대로**.

→ **정지점: cargo test + clippy + oxe2e 4/4 → commit → 보고 → GO.**

### Phase B — 발신/통지/응답/가드/청산

**B-1. `signaling/message.rs`** — `MuteUpdateRequest`/`TrackStateReq` 에 `#[serde(default)] track_id: Option<String>`(ssrc 보존).

**B-2. `track_ops.rs handle_mute_update`** — track_id 있으면 `find_stream_by_track_id` → Stream → **`stream.tracks` 전체 `set_muted`**. 없으면 ssrc fallback(`find_publisher_track` → 소속 Stream). `set_track_muted`(peer.rs:845)를 Stream 단위로 교체. TRACK_STATE 통지 body Stream.track_id 동봉.

**B-3. `track_ops.rs do_track_state_req`** — track_id → Stream. **simulcast Stream reject**(§11). non-sim/PTT Stream tracks duplex_store. 통지 body track_id.

**B-4. `track_ops.rs do_publish_tracks`** — 응답 `d.tracks=[{mid, track_id}]`. 각 track item `t.mid` + 소속 Stream.track_id. non-sim·simulcast·PTT 전부.

**B-5. `transport/udp/ingress_publish.rs notify_new_stream`** — subscriber 통지 track_id = Stream.track_id(vssrc 기반). self-unicast 없음.

**B-6. admin** — track_id 출처 Stream 역참조.

---

## §5 변경 영향 범위

| 파일 | 변경 |
|---|---|
| `domain/publisher_stream.rs` | track_id+vssrc 필드 + new 확장 + 헬퍼 |
| `domain/publisher_track.rs` | track_id/virtual_ssrc 제거, snapshot 역참조 |
| `domain/peer.rs` | attach_track_to_stream 발급 + find_stream_by_track_id/by_vssrc + ensure 전환 + set_track_muted Stream 단위 + switch 청산 |
| `signaling/message.rs` | track_id: Option<String> 2 struct |
| `signaling/handler/track_ops.rs` | 발신 키·Stream 단위 mute/duplex + 통지 + 응답 tracks + 가드 |
| `transport/udp/ingress_publish.rs` | notify track_id=Stream.track_id |
| admin / helpers(collect_subscribe_tracks) | track_id 역참조 / vssrc Stream 경유 |

**무변경**: ingress 라우팅(`find_publisher_track`/실ssrc), fan-out(`subscribers` Weak Vec 순회), `PublisherTrackIndex`(track_id 인덱스 불요), `rr_stats`/`pub_pipeline_stats`(stats 트랙 직속 그대로).

---

## §6 운영 룰
1. **정지점** — Phase A 끝 1개. commit + 보고 + GO.
2. **시그니처 선조치 후 보고** — `PublisherStream::new` 시그너처 확장 호출처(테스트 mk 포함) 박고 사후 보고.
3. **추가 변경 금지** — §5 밖.
4. **2회 실패 시 중단**.

---

## §7 기각 접근
- track_id 역추출 — 반칙. 키 조회.
- track_id/vssrc 물리 유지 — 클라 Pipe 계층 불일치. 논리 Stream.
- vssrc 라우팅 — 방향 역전. 값(복사본).
- self-unicast — vssrc eager 응답 학습.
- ingress/fan-out 평면 건드리기 — 무관. 시그널링만.

---

## §8 산출물
- 코드 변경 7영역(§5). cargo test + clippy + oxe2e 4/4 로그.
- 완료 보고: `~/repository/context/202606/20260603_track_state_unification_server_done.md` (claudecode/ 아님).

---

## §9 시작 전 확인
- [ ] 설계서 rev.3 정독.
- [ ] `git status` clean.
- [ ] `register_publisher_track`(946) → `attach_track_to_stream`(720) 순서상 track.ssrc 가용 확인(first_track_ssrc 전달 가능).
- [ ] `collect_subscribe_tracks` → SubscriberStream.virtual_ssrc 채우는 경로가 Stream.vssrc 와 정합.

---

## §10 직전 작업 처리
- 레포 현 위치 **0602e**(Phase 121 scope 래퍼 폐기). 2계층(0530)·방향 역전(0528~0601)·stats 트랙 정렬(0602b~c)·domain 재편(0602d~e) 전부 **커밋 완료** — 본 작업은 그 위에서 식별 계층만 재편.
- 0531c(`TRACK_STATE_REQ`) 핸들러 존재 — track_id 수용 + Stream 단위 + 가드 추가.
- baseline test 수(205~211)는 0602e 시점 기준 확인 후 진입.

---

*author: kodeholic (powered by Claude)*
