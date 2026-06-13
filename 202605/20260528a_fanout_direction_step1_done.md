# 완료 보고 — Step 1: PublisherStream.subscribers 신설 + 양방향 등록 (병행)
> 작업 지침 ← [20260528a_fanout_direction_step1](../claudecode/202605/20260528a_fanout_direction_step1.md)

**문서 ID**: `20260528a_fanout_direction_step1_done.md`
**작성**: 김과장 (Claude Code)
**작업 지침**: `20260528a_fanout_direction_step1.md`
**설계서**: `context/design/20260528_fanout_direction_redesign.md` §8 Step 1
**상태**: Phase A~C 완료, commit + Step 2 진입 GO 대기

---

## §0 검증 결과 요약

| 항목 | 지침 명시 | 실제 |
|---|---|---|
| `cargo test -p oxsfud` baseline | 299 PASS | **214 PASS** (사전 보고 후 박힘) |
| `cargo test -p oxsfud` 본 작업 후 | 299 + 신규 | **217 PASS** (214 + 3 신규) |
| 신규 코드 라인 `cargo clippy` | 경고 없음 | 깨끗 |
| 컴파일 에러 | 0 | 0 |

baseline 차이 (299 vs 214) 는 진입 전 보고 + 부장님 결재 후 214 baseline 으로 진행.

---

## §1 변경 사항 (영향 범위 §5 정합)

### 1.1 `crates/oxsfud/src/room/publisher_stream.rs`

| 변경 | 위치 | 내용 |
|---|---|---|
| 필드 신설 | `PublisherStream` struct 끝 | `subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` |
| `new()` 초기화 | struct 리터럴 끝 | `subscribers: ArcSwap::from_pointee(Vec::new())` |
| 메서드 신설 | `fanout` 위 | `attach_subscriber` / `detach_subscriber` (`#[allow(dead_code)]`) / `subscriber_count` (`#[allow(dead_code)]`) |
| 테스트 신설 | 파일 끝 | `mod subscribers_tests` — 3건 |

import: 기존 `Arc, Mutex, Weak` 이미 박힘. `SubscriberStream` 은 full path 참조 (`crate::room::subscriber_stream::SubscriberStream`) — 순환 import 회피.

### 1.2 `crates/oxsfud/src/signaling/handler/helpers.rs`

`collect_subscribe_tracks` 의 SubscriberStream register 루프만 수정:
- `pref` 가 `PublisherRef::Direct(w)` 인 경우만 `w.upgrade()` 로 PublisherStream Arc 확보.
- `add_subscriber_stream` 반환 `Arc<SubscriberStream>` 받아서 `Arc::downgrade` 후 `pub_stream.attach_subscriber(...)` 호출.
- `ViaSlot` / `None` 은 attach 안 함 (설계서 §4 결정 3 — Slot 경로 유지).

### 1.3 안 건드린 것 (§5 보장)

- `PublisherStream::fanout` — 기존 lookup 경로 그대로
- `SubscriberStream::forward` / `publisher_ref` / `mode`
- release 경로 (`release_subscribe_track` / `remove_subscriber_streams_by_*`)
- Slot / PTT 경로 / Floor

병행 보장 — fanout 은 아직 subscribers Vec 안 씀. Step 1 은 채워두기만.

---

## §2 단위 테스트 3건 결과 (지침 §C.1)

전부 PASS. 위치: `publisher_stream.rs` 의 `mod subscribers_tests`.

| 테스트 | 검증 내용 |
|---|---|
| `attach_subscriber_basic` | Weak 2건 attach → `subscriber_count() == 2` |
| `attach_subscriber_cleans_dead_weak` | Arc drop 후 신규 attach → retain 이 dead 청소 → count 1 + 살아있는 weak id 확인 |
| `detach_subscriber_removes_matching` | subscriber_id 매칭 weak 제거 → 남은 weak id 확인 (sub2) |

mock helper:
- `mk_publisher_stream()` — `PublisherStream::new(...)` 매개변수 18개 직접 호출. `peer_ref: Weak::new()` (dangling — 본 단위 시험 OK).
- `mk_subscriber_stream(mid, subscriber_id)` — `PublisherRef::None` + `SubscribeMode::VideoNonSim` + `peer_ref: Weak::new()`.

---

## §3 발견 사항 (지침 §8 — 산출물 명시 항목)

### 3.1 중복 Weak 누적 가능성 (Step 2 진입 전 판단 자리)

`add_subscriber_stream` 이 idempotent — 같은 mid 재호출 시 기존 `Arc<SubscriberStream>` 반환. 그 Arc 를 그대로 downgrade 후 attach 하므로:

```
ROOM_JOIN  → collect_subscribe_tracks → add_subscriber_stream → attach (Weak A)
ROOM_SYNC  → 동일 mid 재호출       → 기존 Arc 반환          → attach (Weak A 다시)
PUBLISH add → 동일 mid 재호출       → 기존 Arc 반환          → attach (Weak A 또 다시)
```

결과: 같은 SubscriberStream 의 Weak 가 N회 누적. `attach_subscriber` 의 `retain` 은 **dead 만** 청소 — 살아있는 중복은 안 청소.

**현재 영향**: 0 (fanout 은 subscribers 안 씀 — 병행).

**Step 2 진입 영향**: broadcast 가 subscribers Vec 순회하면 같은 sub 에게 N번 forward → egress 중복 송신 = 클라이언트 측 패킷 중복 또는 SN 충돌.

지침 §7 의 "중복 weak 방지 로직 선제 추가 — 기각, 관측만" 정합으로 본 Step 에서는 그대로. **Step 2 진입 전 부장님 판단 자리** — 다음 셋 중 하나:

1. `attach_subscriber` 안에 `subscriber_id` 중복 체크 박음 (살아있는 Weak 의 id 매칭 시 skip).
2. `collect_subscribe_tracks` 가 register 루프 진입 전 같은 mid 의 기존 attach 여부 확인 후 skip.
3. Step 2 broadcast 본문에서 `seen: HashSet<*const SubscriberStream>` 으로 중복 호출 회피.

설계서 §5.1 + §6.1 은 1번 방향 시사 (attach 가 단일 진입점) 으로 보임. 별 토픽 보고 자리.

### 3.2 clippy 기존 error 1건 (영향 범위 §5 외)

`crates/oxsfud/src/transport/udp/ingress_subscribe.rs:422` 에:

```rust
.filter(|b| (b.get(1).copied().unwrap_or(0) & 0x7F) != config::RTCP_PT_PSFB)
```

`config::RTCP_PT_PSFB = 206` 인데 `_ & 0x7F` 결과는 0~127 범위 — 206 과 절대 같지 않음 → 필터가 항상 true (drop 안 됨). clippy 가 `incompatible bit mask` 로 잡음. 본 작업 영향 범위 §5 외 — 손대지 않음 (지침 §6.2). 별 토픽 정정 필요.

### 3.3 baseline 차이 (사전 보고됨)

지침 명시 `cargo test -p oxsfud` 299 PASS vs 실제 214 PASS. 진입 전 보고 → 부장님 결재 (214 baseline 박고 진입) → 본 작업 후 217 PASS (214 + 신규 3) 로 일관 정합. 지침서 (`20260528a_fanout_direction_step1.md` §0.1 / §C.2) 의 299 인용 출처는 미상 — 설계서 (`20260528_fanout_direction_redesign.md` §8) 도 같은 숫자 박힘. 작성자(김대리 claude.ai) 환경 차이 추정.

---

## §4 Step 2 진입 전 확인 자리 (지침 §8)

### 4.1 중복 Weak 처리 방향 결재 (§3.1)

세 옵션 중 어디가 정답인지 부장님 판단 부탁.

### 4.2 Step 2 면적 사전 점검

설계서 §8 Step 2 영향 파일:
- `publisher_stream.rs` — `broadcast` 메서드 신설 (fanout 본문 흡수)
- `transport/udp/ingress*.rs` — fanout 호출처 → broadcast 로 (Full 트랙만)

PTT(Half) 는 Step 2 에서도 기존 `prefan_out_via_slot` + lookup 경로 유지 (Step 4 까지). simulcast 의 PLI burst 도 broadcast 안에서 책임 — forward 반환 `need_pli` 그대로 활용.

핵심 위험: `fanout` 의 prefan_out_via_slot / SimulcastMetrics / PublishState 천이 / pli_state.on_keyframe_received 등 부수 흐름이 broadcast 로 같이 이주해야 함. 면적 작지 않음. 진입 전 별 지침 받으면 좋겠음.

---

## §5 산출물

| 항목 | 상태 |
|---|---|
| commit | **대기** — 부장님 결재 후 진행 |
| 메시지 (예정) | `feat(sfu): PublisherStream.subscribers 신설 + 양방향 attach (방향 역전 Step 1, 병행)` |
| 완료 보고 파일 | 본 문서 |
| SESSION_INDEX 갱신 | 부장님 직접 (context 레포 commit 금지 정합) |

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-28*
