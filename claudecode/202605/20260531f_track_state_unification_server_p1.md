// author: kodeholic (powered by Claude)
# 작업 지침 — Track State 통일 + 식별 계층 재설계 (서버)

- 지침 ID: `20260531f_track_state_unification_server_p1`
- **갱신: rev.2 (설계서 rev.2.1 기준 전면 재작성)** — 어제 rev.1 초안(역추출·self-unicast·peer 무변경) 폐기. track_id 불투명 키조회 + vssrc 논리 이주로 전환.
- 작성: 김대리 (claude.ai) / 구현: 김과장 (Claude Code)
- 선행 설계서: `context/design/20260531_track_state_unification.md` **rev.2.1** (§0 식별 3계층 / §2 결정 A / §7 서버 변경 / §10 기각 / §11 미결)
- 범위: 서버 `oxsfud` **Phase 1~2** (식별 이주 + 발신/통지/응답). 클라(설계서 §8-3~6)는 서버 검증 후 별도 세션.

---

## §0 의무 점검 (시작 전 — 반드시)

1. **설계서 rev.2.1 정독** — §0 식별 3계층 분리(track_id 불투명/vssrc egress/실ssrc ingress) + §2 결정 A + §7 + §10. §0 "track_id 파싱 금지, 키 조회"가 본 작업 헌법.
2. **★ working tree 충돌 확인 (최우선)** — `git status` + `git log --oneline -5`. **Publisher 2계층(0530d/0531e)의 Stage 2~4 가 미커밋이면** 본 작업과 `publisher_stream.rs`/`publisher_track.rs`/`peer.rs` 가 정면 충돌한다(같은 파일 대폭 수정). 미커밋 잔재 있으면 **진입 전 보고** — 커밋/정리 선행 여부를 부장님이 결정. working tree clean 확인 후 착수.
3. cargo test + clippy 통과 = 완료 기준. E2E/브라우저는 본 작업 책임 아님.

---

## §1 컨텍스트 — 왜 / 검증된 사실

**왜**: 트랙 지목이 ssrc 기반이고 클라가 자기 track_id 권위값을 안 들어 오지목·SDP 재파싱이 반복(#1~#5). 특히 simulcast 는 물리 Track 마다 track_id(h/l/placeholder 3개)로 흩어짐(#5b). → **track_id 를 불투명 식별자로 논리 Stream 에 단일화**, vssrc 를 논리 Stream 에 정착시켜 PUBLISH_TRACKS 시점에 track_id 확정.

**검증된 코드 사실** (김대리 사전 확인):
- 논리 `PublisherStream`(publisher_stream.rs) 에 현재 `vssrc`·`track_id` **없음**(PLI 자료만). vssrc 는 물리 `PublisherTrack.virtual_ssrc` 에 있고 `ensure_simulcast_video_ssrc()`=`first_track_of_kind(Video).ensure_virtual_ssrc()` 로 lazy 할당 → placeholder 분화 시 끊길 위험 구조.
- 물리 `PublisherTrack` 은 `stream: ArcSwap<Option<Weak<PublisherStream>>>` 역참조 보유(`track.stream()`). → track_id 논리 이주 후 진단/admin 은 이 역참조로 우회 가능(연쇄 붕괴 아님).
- `find_publisher_track(ssrc)` = by_ssrc 1개 조회(ingress 라우팅 — **유지, 시그널링 평면과 별개**).
- `set_track_muted(ssrc,_)` = ssrc 1개만 → **Stream 단위로 변경**(h/l 비대칭 해소).
- `switch_track_duplex`(peer.rs:895) = production 호출 0, 테스트 3줄(1262~64)만 = **dead 확정**.
- track_id 생성 단일 지점 = `PublisherTrack::create_or_update_at_rtp` 의 `format!("{}_{:x}", peer.user_id, ssrc)`.

---

## §2 결정된 사항 (설계서 rev.2.1 확정)

1. **track_id·vssrc 소유 = 논리 `PublisherStream`**. 물리 `PublisherTrack` 은 실 ssrc 만(track_id/virtual_ssrc 필드 제거).
2. **track_id 불투명** — 파싱/역추출 **금지**(반칙). `find_stream_by_track_id`/`find_stream_by_vssrc` 키 조회. 역추출 헬퍼 신설 금지.
3. **track_id 생성 규칙 = `{user}_{대표 ssrc}`** — non-sim/PTT=원본ssrc, simulcast=vssrc. **PTT 는 원본ssrc 기반**(egress=방 slot 은 대표 아님).
4. **vssrc eager** — 논리 Stream 생성 시 simulcast 면 즉시 할당(PUBLISH_TRACKS 시점). non-sim/PTT 미할당.
5. **학습 = PUBLISH_TRACKS `ok` 응답 `d.tracks=[{mid,track_id}]` 단일 경로** — non-sim·simulcast·PTT 통일. **self-unicast 통지 없음**(rev.1 폐기).
6. **mute/duplex 발신 = Stream 단위 적용** — mute 는 Stream 아래 모든 물리 Track. simulcast duplex 는 reject.
7. **새 op 없음. 하위호환** — Mute/TrackStateReq 에 ssrc 필드 보존, track_id 우선.
8. **변경 7파일**(§5). ingress 라우팅(실 ssrc) 평면은 절대 track_id 로 바꾸지 말 것.

---

## §3 결정 추천 (★ 정지점)

전반은 확정. 추가 결정 없음. 정지점만:

### ★ 정지점 1 — Phase A(식별 이주) 끝

물리↔논리 자료 이동(track_id/vssrc)이 fan-out/notify/admin/agg-log 광범위 참조를 건드리는 **위험 phase**. Phase A 끝에서 cargo test + clippy PASS → commit + 보고 → GO → Phase B.

> Phase B(발신/통지/응답)는 자료 이동 후의 핸들러 배선이라 위험도 낮음 — 별도 정지점 없이 통합 리뷰.

---

## §4 단계별 작업

### Phase A — 식별 이주 (★정지점)

**A-1. `publisher_stream.rs` 자료 신설**
- `PublisherStream` 에 `track_id: Arc<str>`(불변, 생성 시 발급) + `vssrc: AtomicU32`(0=미할당) 추가.
- `new(user_id, source, kind, ...)` 시그너처에 track_id 발급 로직: simulcast 면 vssrc=`rand_u32_nonzero()` 후 `track_id={user}_{vssrc:x}`, 아니면 `track_id={user}_{대표 물리 ssrc:x}`.
  - ⚠️ Stream 생성 시점에 대표 물리 ssrc 를 알아야 함(non-sim/PTT). `attach_track_to_stream` 흐름에서 첫 물리 Track ssrc 로 발급하거나, Stream new 에 대표 ssrc 인자 전달. 호출처 컨텍스트 보고 박고 사후 보고(운영룰 2).
- `vssrc_load()` / `ensure_vssrc()`(simulcast lazy CAS, 단 eager 가 기본) / `track_id()` 헬퍼.

**A-2. `publisher_track.rs` 필드 제거 + 역참조 우회**
- `PublisherTrack` 에서 `track_id: Arc<str>`, `virtual_ssrc: AtomicU32` + 관련 메서드(`ensure_virtual_ssrc`/`virtual_ssrc_load`) 제거.
- `snapshot()` 의 `track_id` = `self.stream().map(|s| s.track_id())` 역참조(미배선 시 fallback — ssrc 문자열 등, 가드).
- `create_or_update_at_rtp` 의 track_id 생성 라인 제거(Stream 이 발급).

**A-3. `peer.rs` 조회 헬퍼 + ensure 전환 + dead 청산**
- `find_stream_by_track_id(&str) -> Option<Arc<PublisherStream>>` (streams 선형 탐색, track_id 비교).
- `find_stream_by_vssrc(u32) -> Option<Arc<PublisherStream>>`.
- `simulcast_video_ssrc()`/`ensure_simulcast_video_ssrc()` → 논리 Stream.vssrc 참조로 전환(first video Stream 의 vssrc).
- `switch_track_duplex`(895) 정의 + 테스트(1262~64) 제거.

**A-4. 호출처 전환** — `ingress_publish.rs`/`track_ops.rs` 등에서 `ensure_virtual_ssrc`/`virtual_ssrc_load`/`.track_id`(물리) 참조를 Stream 경유로. ingress 라우팅의 `find_publisher_track(ssrc)`(실 ssrc)는 **그대로**.

→ **정지점: cargo test + clippy → commit → 보고 → GO.**

### Phase B — 발신/통지/응답/가드/청산

**B-1. `message.rs`** — `MuteUpdateRequest`/`TrackStateReq` 에 `#[serde(default)] track_id: Option<String>` 추가(ssrc 보존).

**B-2. `track_ops.rs handle_mute_update`** — track_id 있으면 `find_stream_by_track_id` → 논리 Stream → **Stream 아래 모든 물리 Track `set_muted`**(비대칭 해소). track_id 없으면 ssrc fallback(`find_publisher_track` → 그 Track 소속 Stream). TRACK_STATE 통지 body 에 Stream.track_id 동봉.

**B-3. `track_ops.rs do_track_state_req`** — track_id → Stream 조회. **simulcast Stream 이면 reject**(2006, §11). non-sim/PTT Stream 의 물리 Track duplex_store. TRACK_STATE 통지 body track_id 동봉.

**B-4. `track_ops.rs do_publish_tracks`** — 응답 `d.tracks=[{mid, track_id}]` 수집. 각 track item 의 `t.mid` + 해당 Stream.track_id. non-sim·simulcast·PTT(half) **전부 포함**(simulcast 도 vssrc eager 라 track_id 확정됨). 응답 = `{intent, action, tracks}`.

**B-5. `ingress_publish.rs notify_new_stream`** — subscriber 통지 track_id = Stream.track_id(vssrc 기반). wire `ssrc`(vssrc) 와 일치. **self-unicast 추가 안 함**(응답 학습으로 충분).

**B-6. admin** — track_id 출처를 Stream 역참조로(매트릭스 row 키 정합).

---

## §5 변경 영향 범위

| 파일 | 변경 |
|---|---|
| `room/publisher_stream.rs` | track_id + vssrc 필드 + 발급/조회 헬퍼 |
| `room/publisher_track.rs` | track_id/virtual_ssrc 제거, snapshot 역참조 |
| `room/peer.rs` | find_stream_by_track_id/by_vssrc + ensure 전환 + switch 청산 |
| `signaling/message.rs` | track_id: Option<String> 2 struct |
| `signaling/handler/track_ops.rs` | 발신 키 조회 + Stream 단위 mute/duplex + 통지 + 응답 tracks + 가드 |
| `transport/udp/ingress_publish.rs` | notify track_id=Stream.track_id, self-unicast 없음 |
| admin(`build_*_snapshot` / track dump) | track_id 출처 Stream 역참조 |

**ingress 라우팅(`find_publisher_track`/실 ssrc) 평면 무변경.** 영향 범위 밖 발견 시 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점** — Phase A 끝 1개(§3). commit + 보고 + GO.
2. **시그니처 선조치 후 보고** — Stream new 의 대표 ssrc 전달 방식 등 호출처 의존 결정은 박고 사후 보고.
3. **추가 변경 금지** — §5 밖 손대지 말 것.
4. **2회 실패 시 중단** — 같은 에러 2회 후 미해결 → 즉시 중단 + 보고.

---

## §7 기각 접근 (재유혹 차단)

- **track_id 역추출(`rsplit_once`)** — 캡슐화 위반(반칙). 키 조회만.
- **simulcast self-unicast 통지** — vssrc eager 로 응답 학습. 불요.
- **vssrc 물리 Track 유지** — placeholder 분화 끊김. 논리 Stream 소유.
- **물리 track_id 유지** — 3개 흩어짐. 단 admin 은 stream() 역참조(제거 아닌 참조 이전).
- **ingress 라우팅을 track_id 키로** — 평면 혼선. 실 ssrc 유지.
- **track_id→Stream HashMap 인덱스** — 선형 탐색 충분.

---

## §8 산출물

- 코드 변경 7영역(§5).
- cargo test + clippy PASS 로그.
- 완료 보고: `~/repository/context/202605/20260531f_track_state_unification_server_done.md` (claudecode/ 자리 아님).

---

## §9 시작 전 확인

- [ ] 설계서 rev.2.1 §0/§2/§7/§10 정독.
- [ ] **`git status` clean — Publisher 2계층 미커밋 잔재 없는지(§0-2). 있으면 보고.**
- [ ] track_id 생성 단일 지점이 Stream 으로 이동했는지(물리 생성 라인 제거 확인).

---

## §10 직전 작업 처리

- 오늘(0531) a~e: a 분류권위 / b duplex캐싱 / c duplex통지(TRACK_STATE_REQ) / d master sync / e publisher 2layer doc sync.
- **본 작업은 0531c(TRACK_STATE_REQ) + Publisher 2계층(0530d) 토대 위에 식별 계층을 재편**. `do_track_state_req` 핸들러 존재 — track_id 수용 + Stream 단위 + 가드 추가.
- ★ **2계층 Stage 2~4(0530d) 미커밋 충돌 위험 최상** — `publisher_stream.rs`/`publisher_track.rs`/`peer.rs` 정면. §0-2 working tree 확인이 본 작업 진입의 전제.

---

*author: kodeholic (powered by Claude)*
