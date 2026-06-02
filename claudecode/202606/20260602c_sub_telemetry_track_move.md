# 작업 지침 — sub 텔레메트리 트랙 차원 정렬 (SubscribePipelineStats → SubscriberStream, 정공)

> 작성: 김대리 (claude.ai) · 결재: 부장님 (kodeholic) · 구현: 김과장 (Claude Code)
> 파일: `context/claudecode/202606/20260602c_sub_telemetry_track_move.md`
> 선행: `20260602b` Phase C(pub) commit `9abdf43` 위에 적층. pub 텔레메트리는 이미 PublisherTrack 으로 이동 완료 — 본 작업이 sub 측을 마저 내려 **pub/sub 대칭 완성**.

---

## §0 의무 점검

1. `git status` / `git log` — `9abdf43`(Phase C pub) 까지 적층 확인. `SubscriberStream` 에 `room_id`/`sr_stats`/`stalled`/`stats_primed` 직속 + `PublisherTrack.pub_pipeline_stats` 존재 전제.
2. baseline: `cargo test -p oxsfud` → **211 passed** + oxe2e 4/4. 작업 후 유지가 GREEN 기준.
3. 이 지침은 **카운터 inc 위치 이동**이다. RTCP 동작(SR 번역 / NACK 처리 / RTX 재전송)은 한 줄도 안 바뀐다. 동작이 바뀌면 버그다.

---

## §1 컨텍스트 — 보류분의 진짜 원인

`20260602b` 에서 sub 측(`SubscribePipelineStats` @ `RoomMember.sub_stats`)은 "stream 1:1 귀속 불가"로 보류됐다. **그 판정은 절반만 맞다.** 5필드 전부 stream 귀속 가능하다 — 현재 inc 시점이 compound/RoomMember 합산 층이라 그렇게 보일 뿐, 본질 제약이 아니다.

### 5필드 inc 호출처 전수 + 귀속 판정 (코드 확인 완료)

| 필드 | 현재 inc 위치 | 현재 단위 | 정공 (stream 해소) |
|---|---|---|---|
| `rtp_relayed` | `subscriber_stream.rs::forward` | **stream** (self) | 그대로 — `self.sub_pipeline_stats` |
| `rtp_dropped` ① | `forward` egress full | **stream** (self) | 그대로 — `self.sub_pipeline_stats` |
| `rtp_dropped` ② | `ingress_subscribe.rs::handle_nack_block` RTX egress full (`member.sub_stats.rtp_dropped`) | member 합산 | `find_subscriber_stream_by_vssrc(nack.media_ssrc)` → stream |
| `sr_relayed` | `ingress_rtcp.rs::relay_publish_rtcp_translated` 전송 성공 후 (`target.sub_stats.sr_relayed`) | member, **compound 1회** | `build_sr_translation` 이 블록별 sub_stream 이미 해소 → 시그너처 반환 → 전송 성공 후 SR별 stream inc |
| `nack_sent` | `ingress_subscribe.rs::handle_subscribe_rtcp` `nack_blocks.len()` 합산 (`member.sub_stats.nack_sent`) | member, **compound 합산** | `handle_nack_block` 진입 시 그 block 의 `media_ssrc` 해소 stream 에 1 (블록 수 보존) |
| `rtx_received` | **producer 0 (inc 호출처 전무)** | dead | **필드 삭제** — 이동 아님 |

**핵심**: `sr_relayed`/`nack_sent` 가 "compound 단위"로 보인 건 inc 를 **compound 조립/수신 층**에서 했기 때문이다. 두 함수 모두 내부에서 이미 블록별 `media_ssrc → sub_stream` 을 해소하고 있다(SR 은 sr_stats 읽으려고, NACK 은 RTX 조립하려고). inc 를 그 해소 지점으로 내리면 전부 stream 귀속이다.

---

## §2 결정된 사항 (부장님 GO)

1. **`SubscribePipelineStats` 통째 `SubscriberStream` 직속 이동.** struct-split(일부 RoomMember 잔류)은 **금지** — 땜빵이다. 전부 stream 으로 내린다.
2. **inc 시점 교정** — compound/member 합산 inc 를 전부 stream 해소 지점으로 이동 (§4 필드별).
3. **`rtx_received` 삭제** — producer 0 dead counter. 트랙 이동 대상 아님. 필드 + snapshot + admin JSON 키 전부 제거.
4. **struct 정의 위치**: `SubscribePipelineStats` / `SubscribePipelineSnapshot` → `participant.rs` 에서 `subscriber_stream.rs` 로 이동 (SubscriberStream 소속). pub 측 `PublishPipelineStats`→publisher_track.rs 와 대칭.
5. **의미 변경은 세분화일 뿐 동작 변경 아님**: `sr_relayed`/`nack_sent` 가 "subscriber 합산"→"stream 별". admin 이 stream 합산하면 기존 subscriber 단위 숫자와 동일 (정보 손실 0). RTCP 처리 로직 불변.

### 목표 자료구조 (pub/sub 대칭 완성)

```
PublisherTrack
 ├ rr_stats           : Mutex<RrStats>            (RR)
 └ pub_pipeline_stats : PublishPipelineStats      (텔레메트리, 이미 이동됨)

SubscriberStream
 ├ room_id            : RoomId                    (STALLED 체커용, 이미 직속)
 ├ sr_stats           : Mutex<SrStats>            (SR, 이미 직속)
 ├ stalled            : Mutex<StalledSnapshot>    (정체 판정, 이미 직속)
 ├ stats_primed       : AtomicBool                (이미 직속)
 └ sub_pipeline_stats : SubscribePipelineStats    (텔레메트리 — 본 작업으로 이동, rtx_received 제거된 4필드)

RoomMember     : sub_stats 필드 삭제 → 순수 멤버십 메타만
SubscribePipelineStats : 정의 subscriber_stream.rs 로 이동 + rtx_received 필드 삭제
```

`SubscribePipelineStats` 최종 필드: `rtp_relayed` / `rtp_dropped` / `sr_relayed` / `nack_sent` (rtx_received 제거 = 4필드).

---

## §3 결정 추천 (★ 정지점 — 부장님 판단)

1. **★ Phase 묶음**: 자료 이동(sub_stats 삭제 + sub_pipeline_stats 추가)과 inc 호출처 교정은 **컴파일 의존상 한 commit이 자연**이다 — RoomMember.sub_stats 를 지우는 순간 모든 inc 호출처가 깨지므로 동시 교정해야 빌드된다. §4 의 Phase A/B 는 논리 단계일 뿐, commit 은 묶는 게 맞다. admin(Phase C)은 별 commit 가능. 부장님 판단.

2. **★ `sr_relayed` plumbing — `build_sr_translation` 시그너처 변경**: 현재 `-> Option<SrTranslation>` 인데, inc 를 stream 별로 하려면 어느 sub_stream 의 SR 인지 caller 가 알아야 한다. 안에서 이미 `find_subscriber_stream_by_vssrc` 로 sub_stream 을 찾으므로(sr_stats 읽는 자리) → **`-> Option<(SrTranslation, Arc<SubscriberStream>)>`** 으로 반환 확장. caller(`relay_publish_rtcp_translated`)가 SR 번역 성공한 sub_stream 들을 모았다가 **egress try_send 성공 후** 각 stream `sub_pipeline_stats.sr_relayed` inc. (non-sim 에서 sub_stream 못 찾는 `unwrap_or((0,0))` 경로는 inc 대상 없음 — Option 으로 자연 처리.) 이 시그너처 변경 승인 요청.

> 위 ★ 2건 외(struct 위치 / rtx_received 삭제 / 의미 세분화)는 §2 자명 확정 — 김과장 선조치 + 사후 보고.

---

## §4 단계별 작업

### Phase A — 자료 이동 (struct + 필드)

A-1. `domain/participant.rs`:
  - `SubscribePipelineStats` / `SubscribePipelineSnapshot` 정의를 `subscriber_stream.rs` 로 이동. **이동 시 `rtx_received` 필드 + snapshot 필드 + to_json 키 삭제** (4필드로).
  - `RoomMember.sub_stats` 필드 삭제. `RoomMember::new` 에서 초기화 제거. RoomMember 는 멤버십 메타(room_id/role/joined_at/peer)만.
A-2. `domain/subscriber_stream.rs`:
  - `SubscribePipelineStats` 정의 받기 (use 정리).
  - `SubscriberStream` 에 `sub_pipeline_stats: SubscribePipelineStats` 필드 추가.
  - `SubscriberStream::new` 에서 `sub_pipeline_stats: SubscribePipelineStats::new()` 초기화 (인자 불필요 — 누적 카운터라 0 시작).
  - **생성처 확인**: `hooks/stream.rs` 가 `SubscriberStream` 을 `new()` 호출로 만드는지(20260602b F2 에서 리터럴→new() 전환됨) 확인. new() 안 초기화면 자동 정합. 리터럴 잔존 시 sub_pipeline_stats 채움.

### Phase B — inc 시점 교정

B-1. `subscriber_stream.rs::forward` — `rtp_relayed` / `rtp_dropped`①:
  - `ctx.target.sub_stats.{rtp_relayed,rtp_dropped}` → `self.sub_pipeline_stats.{..}` (self = SubscriberStream).
B-2. `ingress_subscribe.rs::handle_nack_block` — `rtp_dropped`②(RTX egress full):
  - 현재 `member.sub_stats.rtp_dropped.fetch_add(1)` → `nack.media_ssrc` 로 `subscriber.find_subscriber_stream_by_vssrc(nack.media_ssrc)` 해소 후 `sub_stream.sub_pipeline_stats.rtp_dropped`. (이 함수는 이미 `nack.media_ssrc` 로 simulcast 분기에서 sub_stream 을 찾고 있음 — 그 핸들 재사용 가능. 못 찾으면 drop 카운트 누락 허용 — RTX 자체가 stream 매칭 전제.)
  - `room.get_participant(&subscriber.user_id)` member 조회 제거.
B-3. `ingress_subscribe.rs::handle_subscribe_rtcp` — `nack_sent`:
  - 현재 `member.sub_stats.nack_sent.fetch_add(parsed.nack_blocks.len())` (compound 진입 시 총량) 삭제.
  - `handle_nack_block` **진입 시** 그 block 의 `media_ssrc` 해소 stream 에 `sub_pipeline_stats.nack_sent += 1` (NACK 블록당 1 — 합이 기존 nack_blocks.len() 보존). block 1개 = media_ssrc 1개 = stream 1개. (parse 구조상 1 block 안 여러 media_ssrc 가능성은 김과장이 `parse_rtcp_nack` 확인 — 보통 1 block 1 ssrc.)
  - `handle_subscribe_rtcp` 의 member 조회 제거.
B-4. `ingress_rtcp.rs::build_sr_translation` + `relay_publish_rtcp_translated` — `sr_relayed`:
  - `build_sr_translation` 반환을 `Option<(SrTranslation, Arc<SubscriberStream>)>` 로 확장 (★ §3-2). 내부에서 이미 찾는 sub_stream 동봉. sub_stream 없는 non-sim 경로는 None 동반 불가 → **`Option<(SrTranslation, Option<Arc<SubscriberStream>>)>`** 가 정확 (번역은 되지만 stream 미해소 가능).
  - `relay_publish_rtcp_translated`: SR 번역 성공한 sub_stream(Some) 들을 Vec 에 수집 → compound `egress_tx.try_send` **성공 분기**에서 각 sub_stream `sub_pipeline_stats.sr_relayed += 1`. 현재 `target.sub_stats.sr_relayed.fetch_add(1)` (compound 1회) 삭제.
  - 주의: relay blocks(PLI 등)은 stream 무관 — sr_relayed 는 **SR 블록 한정**. PLI 만 있는 compound 는 sr_relayed inc 0 (기존도 SR 없으면 의미 없음 — 단 기존은 compound 단위라 1 셌을 수 있음. 의미 세분화로 정합).
B-5. `cargo test -p oxsfud` → 211 유지.

### Phase C — admin 빌더

C-1. `signaling/handler/admin.rs`:
  - `sub_stats.snapshot()` (RoomMember 순회) 출력 → `SubscriberStream` 순회로 `sub_pipeline_stats.snapshot()` 수집. 기존 RoomMember(subscriber) 단위 JSON 호환 위해 **stream 합산**(user 단위 출력 유지) 또는 stream 별 노출 — 출력 형태 김과장 선조치 + 보고.
  - `rtx_received` JSON 키 제거 (snapshot 4필드).
C-2. `cargo test -p oxsfud` → 211 유지 + oxe2e 4/4.

---

## §5 변경 영향 범위 (파일) — 누락 차단 점검

- `domain/participant.rs` — SubscribePipelineStats 정의 이동(반출), RoomMember.sub_stats 삭제 (Phase A)
- `domain/subscriber_stream.rs` — SubscribePipelineStats 정의 수입 + rtx_received 삭제, sub_pipeline_stats 필드/new 초기화, forward inc (Phase A/B)
- `transport/udp/ingress_subscribe.rs` — handle_subscribe_rtcp(nack_sent 제거), handle_nack_block(nack_sent + rtp_dropped② stream 해소) (Phase B)
- `transport/udp/ingress_rtcp.rs` — build_sr_translation 시그너처 + relay_publish_rtcp_translated(sr_relayed stream 해소) (Phase B)
- `signaling/handler/admin.rs` — snapshot 빌더 stream 순회 + rtx_received 키 제거 (Phase C)
- `hooks/stream.rs` — SubscriberStream 생성처 (new() 호출이면 자동 정합, 리터럴이면 sub_pipeline_stats 채움) — **확인 의무** (20260602b F2 누락 재발 방지)
- `domain/subscriber_stream_index.rs` — SubscriberStream 필드 추가 영향 없을 것(인덱스는 mid/vssrc 키만). 확인.
- admin snapshot 소비처(클라/대시보드 JSON) — rtx_received 키 사라짐. JS 측 참조 있으면 발견_사항 보고(서버 §5 밖).

> **§5 범위 밖 손대지 말 것.** 별 문제는 *발견_사항* 보고만, 부장님 컨펌 후 별 토픽.
> **20260602b 누락 교훈**: SubscriberStream 필드 추가/struct 이동 시 **모든 생성처·참조처·snapshot 소비처**를 grep 으로 전수 — "한 군데 안 봐서 줄줄이 샌다".

---

## §6 운영 룰

1. **정지점**: §3 ★ 2건 (Phase 묶음 / build_sr_translation 시그너처). commit + 보고 + GO 대기.
2. **시그니처 선조치 후 보고**: build_sr_translation 반환 타입(`Option<(SrTranslation, Option<Arc<SubscriberStream>>)>`), admin 출력 형태 — 분석 후 박고 사후 보고.
3. **추가 변경 금지**: §5 범위 밖.
4. **2회 실패 시 중단**: 같은 컴파일 에러 / 테스트 실패 2회 후 미해결 → 즉시 중단 + 보고.

---

## §7 기각 접근법

- **struct-split (rtp_relayed/dropped 만 stream, sr_relayed/nack_sent 는 RoomMember 잔류)** — 땜빵. sr_relayed/nack_sent 도 내부에서 stream 해소 가능하므로 통째 내린다. 차원 비대칭 절반만 풀면 의미 없음.
- **rtx_received 를 SubscriberStream 으로 이동** — producer 0 dead. 이동이 아니라 삭제. dead 필드 끌고 가기 금지.
- **`sr_relayed` 를 compound 단위로 유지 (RoomMember 잔류)** — inc 시점이 틀린 거지 자료가 안 떨어지는 게 아님. build_sr_translation 이 이미 sub_stream 해소 — 시그너처 반환으로 정공.
- **nack_sent 를 handle_subscribe_rtcp 의 blocks.len() 합산으로 유지** — 같은 이유. handle_nack_block 이 media_ssrc 해소하므로 block 별 stream inc.
- **inc 를 try_send 전에 (전송 실패해도 카운트)** — sr_relayed 는 기존이 전송 성공 후 inc. 시점 보존 — 성공 분기에서만.

---

## §8 산출물

- 코드: §5 파일들. 211 tests GREEN + oxe2e 4/4 유지.
- 완료 보고: `context/202606/20260602c_sub_telemetry_track_move_done.md`.
- 보고 항목: commit 해시, build_sr_translation 시그너처 최종형, nack 블록↔stream 매핑 확인(parse_rtcp_nack 구조), admin 출력 형태, rtx_received 삭제 파급(JS 참조 유무), baseline 211 + oxe2e 4/4.

---

## §9 시작 전 확인

1. `9abdf43`(Phase C pub) 적층 확인? SubscriberStream 에 room_id/sr_stats/stalled/stats_primed + PublisherTrack.pub_pipeline_stats 존재?
2. baseline 211 + oxe2e 4/4?
3. §3 ★ 2건 (Phase 묶음 / build_sr_translation 시그너처) GO?

---

## §10 직전 작업 처리

- `20260602b` Phase C(pub) `9abdf43` 위에 적층. 본 작업 완료 시 pub/sub 텔레메트리 모두 트랙 단위 — 차원 비대칭 완전 해소.
- 완료 후 SESSION_INDEX 갱신 자리 (20260602b + 20260602c 묶어 한 줄, 부장님 지시 시).

---

*author: kodeholic (powered by Claude)*
