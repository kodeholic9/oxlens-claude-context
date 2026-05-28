# 작업 지침 — Step 1: PublisherStream.subscribers 신설 + 양방향 등록 (병행)

**문서 ID**: `20260528a_fanout_direction_step1.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**설계서**: `context/design/20260528_fanout_direction_redesign.md` §8 Step 1
**부장님 GO**: 대기 (본 지침 검토 후)

---

## §0 의무 점검 (착수 전 반드시)

1. `cargo test -p oxsfud` baseline 확인 — **299 PASS** 기록. 본 작업 종료 시 동일 유지 필수.
2. 설계서 `20260528_fanout_direction_redesign.md` §3 (방향 역전) + §4 (결정 4개) + §5.1 통독.
3. 본 작업은 **병행 단계** — 기존 `fanout` / `publisher_ref` / `forward` **한 줄도 안 건드림**. subscribers 필드를 *채워두기만* 한다.

---

## §1 컨텍스트

### 1.1 현재 구조 (As-Is)

`PublisherStream::fanout` 이 매 RTP 마다 방 전체 순회 + `find_subscriber_stream_by_vssrc(vssrc)` lookup 으로 subscriber 를 찾는다. SubscriberStream 은 `publisher_ref: ArcSwap<PublisherRef>` 로 역방향 참조.

### 1.2 Step 1 목표

`PublisherStream` 에 `subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` 를 신설하고, SubscriberStream 등록 시점에 **해당 publisher 의 subscribers 에 attach** 한다.

**이 단계에서는 fanout 이 subscribers 를 안 쓴다** (기존 lookup 유지). 목적은:
- subscribers Vec 이 기존 lookup 결과와 *일치하는지* 검증 (Step 2 에서 lookup 폐기 전 안전 확인)
- 방향 역전 토대 마련

### 1.3 왜 병행인가

방향 역전은 fan-out 핫패스 변경 — 위험 큼. Step 1 에서 자료만 채우고 fanout 은 그대로 두면, subscribers 가 정확히 채워지는지 단위 테스트로 검증 가능. Step 2 에서 비로소 fanout 을 subscribers 순회로 교체.

---

## §2 결정된 사항 (설계서 §4 pin — 변경 금지)

1. **이름 유지** — `PublisherStream` / `SubscriberStream`. Track/Route 개명 안 함 (Step 7 별 토픽).
2. **Track home = PublishContext** — `PublishContext.streams` 현행. Room 으로 안 올림.
3. **Slot 현행 유지** — PTT(Half/ViaSlot) 는 Step 1 에서 subscribers 안 채움. Direct(Full) 만 attach.
4. **detach 명시 안 함** — SubscriberStream Arc 본체는 `SubscribeContext.streams` 보유. 제거 시 Weak 자연 dead. attach 시 `retain` 으로 dead 청소. **release 경로 안 건드림.**

---

## §3 결정 추천 (정지점)

### ★ 정지점 1개 — Phase C 끝 (작업 전체 완료)

Step 1 은 면적 작고 위험 낮음 (병행, 핫패스 미변경). 중간 정지점 불필요. **Phase A~C 일괄 진행 후 commit + 부장님 보고 + GO 대기.**

---

## §4 단계별 작업

### Phase A — PublisherStream.subscribers 필드 + 메서드

**파일**: `crates/oxsfud/src/room/publisher_stream.rs`

#### A.1 필드 신설

`PublisherStream` struct 에 필드 추가 (`peer_ref: Weak<Peer>` 아래, `=== 메타 ===` 블록 끝):

```rust
    // === fan-out 다운스트림 (Step 1, 2026-05-28 — 방향 역전 토대) ===
    /// 이 PublisherStream 이 fan-out 하는 SubscriberStream 들 (Weak).
    /// FullNonSim/FullSim 만 채움. HalfNonSim(PTT) 는 Slot 경로 유지 (Step 4 통합 전까지 빈 채).
    /// Step 1: 채워두기만 — fanout 은 아직 기존 lookup 사용 (병행 검증).
    /// dead Weak 는 attach_subscriber 의 retain 으로 자연 청소 (명시 detach 없음).
    pub subscribers: ArcSwap<Vec<Weak<crate::room::subscriber_stream::SubscriberStream>>>,
```

> import 주의: `subscriber_stream::SubscriberStream` 은 full path 로 참조 (publisher_stream.rs 가 subscriber_stream 을 use 하면 순환 우려 — full path 안전. 컴파일 에러 시 `use` 추가 판단은 김과장).

#### A.2 `new()` 초기화

`PublisherStream::new` 의 struct 리터럴 끝 (`peer_ref,` 다음) 에 추가:

```rust
            subscribers: ArcSwap::from_pointee(Vec::new()),
```

#### A.3 attach / detach 메서드

`impl PublisherStream` 블록 안 (적절한 자리, 예: fanout 메서드 위) 에 추가:

```rust
    /// SubscriberStream 을 fan-out 다운스트림에 등록 (방향 역전, Step 1).
    /// 호출처: helpers::collect_subscribe_tracks 의 register 루프 (Direct pref 만).
    /// 매 호출 시 dead Weak 청소 (retain) — 명시 detach 불필요.
    pub fn attach_subscriber(&self, weak: Weak<crate::room::subscriber_stream::SubscriberStream>) {
        let cur = self.subscribers.load_full();
        let mut new = (**cur).clone();
        new.retain(|w| w.upgrade().is_some());  // dead 청소
        new.push(weak);
        self.subscribers.store(Arc::new(new));
    }

    /// 명시 detach (Step 1 호출처 없음 — Step 2+ 대비 정의만).
    /// subscriber_id 매칭 Weak 제거 + dead 청소.
    #[allow(dead_code)]
    pub fn detach_subscriber(&self, subscriber_id: &str) {
        let cur = self.subscribers.load_full();
        let new: Vec<_> = cur.iter()
            .filter(|w| {
                w.upgrade()
                    .map(|s| s.subscriber_id.as_ref() != subscriber_id)
                    .unwrap_or(false)  // dead → 제거
            })
            .cloned()
            .collect();
        self.subscribers.store(Arc::new(new));
    }

    /// 현재 등록된 다운스트림 수 (dead 포함 — 단위 테스트/진단용).
    #[allow(dead_code)]
    pub fn subscriber_count(&self) -> usize {
        self.subscribers.load().len()
    }
```

### Phase B — collect_subscribe_tracks 에서 attach 호출

**파일**: `crates/oxsfud/src/signaling/handler/helpers.rs`

#### B.1 register 루프 수정

현재 `collect_subscribe_tracks` 끝부분의 SubscriberStream register 루프:

```rust
    // SubscriberStream register (Idempotent on mid).
    for t in &tracks {
        let track_id = match t.get("track_id").and_then(|v| v.as_str()) {
            Some(s) => s, None => continue,
        };
        let mid = match t.get("mid").and_then(|v| v.as_u64()) {
            Some(m) if m <= u8::MAX as u64 => m as u8,
            _ => continue,
        };
        if let Some((pref, vssrc, kind, is_via_slot, pub_simulcast, pub_uid)) = publisher_refs.remove(track_id) {
            let mode = crate::room::subscriber_stream::SubscribeMode::derive(
                is_via_slot,
                kind.clone(),
                pub_simulcast,
                vssrc,
                std::sync::Arc::<str>::from(pub_uid.as_str()),
            );
            subscriber.peer.add_subscriber_stream(mid, vssrc, kind, pref, mode);
        }
    }
```

이것을 다음으로 교체 — **`pref` 를 attach 에 쓰기 위해 clone 후, add_subscriber_stream 반환 Arc 를 publisher 에 attach**:

```rust
    // SubscriberStream register (Idempotent on mid).
    // Step 1 (2026-05-28): Direct pref 의 경우 publisher.subscribers 에 양방향 attach (방향 역전 토대).
    //   ViaSlot 는 Slot 경로 유지 (설계서 §4 결정 3) — attach 안 함.
    for t in &tracks {
        let track_id = match t.get("track_id").and_then(|v| v.as_str()) {
            Some(s) => s, None => continue,
        };
        let mid = match t.get("mid").and_then(|v| v.as_u64()) {
            Some(m) if m <= u8::MAX as u64 => m as u8,
            _ => continue,
        };
        if let Some((pref, vssrc, kind, is_via_slot, pub_simulcast, pub_uid)) = publisher_refs.remove(track_id) {
            // Step 1: Direct pref 의 PublisherStream Arc 를 attach 위해 미리 upgrade.
            let pub_stream_for_attach = match &pref {
                crate::room::subscriber_stream::PublisherRef::Direct(w) => w.upgrade(),
                _ => None,  // ViaSlot / None → attach 안 함
            };
            let mode = crate::room::subscriber_stream::SubscribeMode::derive(
                is_via_slot,
                kind.clone(),
                pub_simulcast,
                vssrc,
                std::sync::Arc::<str>::from(pub_uid.as_str()),
            );
            let sub_stream = subscriber.peer.add_subscriber_stream(mid, vssrc, kind, pref, mode);
            // 양방향 등록 — publisher 가 자기 다운스트림 알게 (Step 2 broadcast 토대).
            if let Some(pub_stream) = pub_stream_for_attach {
                pub_stream.attach_subscriber(std::sync::Arc::downgrade(&sub_stream));
            }
        }
    }
```

> `add_subscriber_stream` 은 이미 `Arc<SubscriberStream>` 반환 (peer.rs 확인). idempotent 분기 (기존 mid 면 기존 Arc 반환) 도 그 Arc 를 attach — 같은 SubscriberStream 이 중복 attach 될 수 있으나 retain 이 dead 만 청소하므로 **중복 weak 누적 가능**. Step 1 검증에서 중복 여부 확인 (아래 §4 Phase C 테스트). 중복이 문제면 attach 안에서 subscriber_id 중복 체크 추가 판단 — 단 Step 1 에서는 *일단 그대로*, 테스트로 관측만.

### Phase C — 단위 테스트 + 검증

**파일**: `crates/oxsfud/src/room/publisher_stream.rs` (tests 모듈) 또는 peer.rs tests

#### C.1 신규 단위 테스트

```rust
#[test]
fn attach_subscriber_basic() {
    // PublisherStream 1개 + SubscriberStream weak 2개 attach → count 2
    // (Peer/SubscriberStream mock 생성은 기존 테스트 헬퍼 패턴 참조)
}

#[test]
fn attach_subscriber_cleans_dead_weak() {
    // SubscriberStream Arc drop 후 새 attach → dead 청소되어 count 1
}

#[test]
fn detach_subscriber_removes_matching() {
    // subscriber_id 매칭 detach → 해당 weak 제거
}
```

> 김과장: mock 생성 패턴은 publisher_stream.rs / subscriber_stream.rs 기존 테스트 + peer.rs `mk_peer` 헬퍼 참조. SubscriberStream::new 시그너처는 subscriber_stream.rs 확인. 테스트 3개가 어려우면 최소 `attach_subscriber_basic` + `attach_subscriber_cleans_dead_weak` 2개.

#### C.2 검증

- `cargo test -p oxsfud` → **299 + 신규 PASS**
- `cargo clippy -p oxsfud` 경고 없음 (신규 코드 한정)

---

## §5 변경 영향 범위

| 파일 | 변경 | 비고 |
|---|---|---|
| `room/publisher_stream.rs` | subscribers 필드 + new() 초기화 + attach/detach/count 메서드 + 테스트 | 신규 ~50줄 |
| `signaling/handler/helpers.rs` | collect_subscribe_tracks register 루프 attach 추가 | ~10줄 |

**안 건드리는 것 (절대)**:
- `PublisherStream::fanout` — 기존 lookup 유지
- `SubscriberStream::forward` / `publisher_ref` / `mode`
- release 경로 (`release_subscribe_track` / `remove_subscriber_streams_by_*`)
- Slot / PTT 경로

---

## §6 운영 룰

1. **정지점 1개** (§3) — Phase C 완료 후 commit + 보고 + GO 대기.
2. **추가 변경 금지** — §5 영향 범위 외 파일 손대지 말 것. 별 문제 발견 시 *발견_사항* 으로 보고만.
3. **2회 실패 시 중단** — 같은 컴파일 에러 / 테스트 실패 2회 후 미해결 → 중단 + 보고.
4. **시그니처 선조치 후 보고** — 순환 import / SubscriberStream::new 시그너처 등 호출처 컨텍스트 의존 결정은 김과장이 박고 사후 보고.

---

## §7 기각 접근법 (이 Step 에서 하지 말 것)

- **fanout 을 subscribers 순회로 교체** — Step 2. Step 1 은 병행 (lookup 유지).
- **publisher_ref 폐기** — Step 3.
- **detach 를 release 경로에 추가** — dead weak 자연 청소로 충분 (결정 4). Step 1 detach 호출처 없음.
- **ViaSlot(PTT) attach** — Slot 경로 유지 (결정 3). Direct 만.
- **중복 weak 방지 로직 선제 추가** — Step 1 은 관측만. 중복이 테스트에서 문제면 그때 판단.

---

## §8 산출물

- commit: `feat(sfu): PublisherStream.subscribers 신설 + 양방향 attach (방향 역전 Step 1, 병행)`
- 완료 보고: `context/202605/20260528a_fanout_direction_step1_done.md`
  - 각 Phase 검증 결과 (test 수, clippy)
  - **발견 사항**: 중복 weak 관측 결과 (idempotent 재등록 시 중복 누적 여부)
  - 다음 Step (Step 2) 진입 전 확인 자리

---

## §9 시작 전 확인

1. baseline `cargo test -p oxsfud` 299 PASS?
2. 설계서 §3·§4·§5.1 읽었는가?
3. 본 Step 은 **병행** — fanout/forward/publisher_ref 안 건드림. 이해했는가?

---

## §10 직전 작업 처리

직전 작업 (0524a 옛 commit 본질 후퇴 정정 3건) 완료 상태. 본 Step 은 그 위 신규 진입. 충돌 없음.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-28*
