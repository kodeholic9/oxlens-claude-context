// author: kodeholic (powered by Claude)

# Subscribe RTCP Cross-Room 설계

> **날짜**: 2026-04-19
> **상태**: 구현 완료 (→ `context/202604/20260419_cross_room_phase1_followup.md` 참조)
> **위치**: `context/design/20260419_subscribe_rtcp_cross_room.md`
> **선행 의존**: Cross-Room Phase 1 Step 9-B (ingress fan-out), Step B (register/notify 방별 독립)
> **대상 파일**: `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` 단일

---

## 0. 대원칙 (최우선)

**Phase 1 단일방 기존 동작에 영향 0.**

- `subscriber.endpoint.rooms_snapshot().len() == 1` 인 모든 시나리오에서 이 변경 전/후 동작이 **바이트 단위로 동일**해야 한다.
- 변경은 "단일방일 때는 원래 방 하나로 lookup, 다방일 때만 추가 방 순회" 의 단순 확장 형태여야 한다.
- `cargo test -p oxsfud --release`: 114 passed + 신규 테스트 0 ~ 소수. 기존 테스트 한 건이라도 깨지면 설계 실패로 간주.
- E2E (voice_radio, conference, video_radio, dispatch, support, moderate): 증상 변화 0. NACK/PLI/SR translate 지연·빈도·결과 모두 동일.

이 원칙이 아래 모든 설계 선택을 지배한다. 코드 간결성·구조 미학보다 우선한다.

---

## 1. 배경

`ingress_subscribe.rs` 의 세 함수 (`handle_subscribe_rtcp`, `relay_subscribe_rtcp_blocks`, `handle_nack_block`) 는 subscriber의 **주 방 하나** 를 `room: &Arc<Room>` 로 받아 그 방 내부에서만 SSRC 매칭을 시도한다.

Subscribe PC는 물리적으로 **참가자당 1개**. subscriber 가 ch1/ch2 cross-room 가입 시 한 PC에 두 방 publisher 트랙이 섞여 들어오고, NACK/PLI 가 ch2 publisher SSRC를 참조하면 ch1 기준 lookup 이 실패한다:

- `room.find_publisher_by_vssrc(ssrc)` — ch2 에만 있는 simulcast publisher 놓침
- `room.{audio,video}_rewriter.virtual_ssrc() == ssrc` — ch2 rewriter 의 가상 SSRC 놓침
- `room.find_by_track_ssrc(ssrc)` — ch2 원본 트랙 놓침

결과: `"publisher not found"` drop → NACK/PLI 유실 → subscriber video freeze.

9-B 에서 publish 쪽 fan-out 은 `rooms_snapshot()` 순회로 전환됐지만, **RTCP 귀환 경로는 아직 방 하나 가정**이다. 본 설계는 이 반쪽짜리 상태를 닫는다.

---

## 2. 확정 사항

### 2.1 함수 시그니처: `room: &Arc<Room>` **유지**

세 함수 모두 `room` 인자 유지. 이 `room` 은 호출부 `ingress.rs::handle_srtp` 에서 `self.room_hub.get(&subscriber.room_id)` 로 조회한 **subscriber의 주 방**. 용도는 두 가지:

1. **진단 로그 카테고리 키** — `agg_logger::agg_key(&["nack_pub_not_found", &room.id])` 등. 9-B / Step 10 / B 전반과 동일 원칙 (`sender.room_id` 의 "주 방" 의미는 cross-room 에서도 유효).
2. **단일방 경로에서 이 `room` 하나만 순회** — 대원칙 (§0) 준수. `rooms_snapshot().len()==1` 이면 이 `room` 과 snapshot 의 유일 원소가 동일.

시그니처 유지의 부수 효과: 호출부 `ingress.rs` 에 변경 전파 없음. 변경 범위 단일 파일 확정.

### 2.2 SSRC → (room, publisher) 역추적 helper 신설

내부 helper 추가. 외부 노출 없음 (`fn` 가시성 `impl UdpTransport` 내부).

```rust
/// Subscribe RTCP 블록의 media_ssrc 로부터 (방, publisher, 실제 lookup SSRC) 를 찾는다.
///
/// 탐색 우선순위 (방별로 3경로 차례로, 한 방에서 hit 하면 반환):
///   ① Simulcast virtual:   room.find_publisher_by_vssrc(ssrc)
///   ② PTT virtual audio/video: room.{audio,video}_rewriter.virtual_ssrc() == ssrc
///   ③ Conference 원본:      room.find_by_track_ssrc(ssrc)
///
/// 방 순회 순서 (중요):
///   - 먼저 subscriber.room_id (주 방) 을 시도 — Phase 1 단일방에서 첫 hit 보장.
///   - 그 다음 rooms_snapshot() 의 나머지 방 순회. 주 방과 중복은 스킵.
///   - 단일방: 1회 시도 → 기존 동작과 동일 순서·동일 lookup.
fn find_publisher_for_subscribe_rtcp(
    &self,
    subscriber: &Arc<RoomMember>,
    primary_room: &Arc<Room>,
    media_ssrc: u32,
) -> Option<SubscribeRtcpTarget>;
```

```rust
/// helper 반환 타입.
struct SubscribeRtcpTarget {
    room: Arc<Room>,            // 매칭 성공한 방
    publisher: Arc<RoomMember>, // 해당 방의 publisher
    lookup_kind: SsrcLookupKind,// 매칭된 경로 (Simulcast/PttAudio/PttVideo/Conference)
    effective_ssrc: u32,        // 실제 publisher 에게 보낼 SSRC (PTT/Simulcast 역매핑 후)
    // NACK 역매핑용 부가 정보
    real_seqs: Option<Vec<u16>>, // NACK 경로에서만 사용. relay 경로는 None.
}

enum SsrcLookupKind {
    Simulcast,   // virtual → 실제 rid 레이어 SSRC 또는 h SSRC (PLI 차별)
    PttAudio,    // audio virtual → floor holder audio SSRC
    PttVideo,    // video virtual → floor holder video SSRC
    Conference,  // 원본 SSRC 그대로
}
```

> **주의**: 실제 `effective_ssrc` 계산은 "PLI 인가 NACK 인가" 에 따라 달라진다 (현재 코드의 `is_pli_block` 분기). helper 는 **경로 판별만** 하고 `effective_ssrc` 계산은 호출 측에서 기존 로직 그대로 수행하는 편이 안전 (기존 코드 이식 최소화). 최종 결정은 §2.3 에서.

### 2.3 구현 스케치 (세 함수 각각)

#### 2.3.1 `handle_subscribe_rtcp`

변경 없음. 기존 그대로 `subscriber`, `room` 받아 decrypt → split_compound → `handle_nack_block` / `relay_subscribe_rtcp_blocks` 호출.

#### 2.3.2 `relay_subscribe_rtcp_blocks`

현재 구조:
```rust
for block in &parsed.relay_blocks {
    // ① find_publisher_by_vssrc     ← room 하나
    // ② ptt virtual ssrc 매칭        ← room 하나
    // 아니면 block.media_ssrc 그대로
    // effective_ssrc 계산
}

for (media_ssrc, blocks) in &publisher_rtcp {
    let publisher = room.find_by_track_ssrc(*media_ssrc); // ← room 하나
    ...
}
```

변경 후 (2단 구성 유지, 내부 lookup 만 방 순회로 감쌈):

```rust
// Step 1: block 그룹핑 (기존)
//   - 방 순회는 block 당 1회, 각 block 에 대해 rooms_snapshot() 순회
//   - helper 가 SsrcLookupKind + matched room 반환
let mut publisher_rtcp: HashMap<(String /*room_id*/, u32 /*effective_ssrc*/), Vec<&[u8]>> = HashMap::new();
let mut pli_per_key: HashMap<(String, u32), u64> = HashMap::new();

for block in &parsed.relay_blocks {
    if block.media_ssrc == 0 { continue; }
    let block_pt = plaintext.get(block.offset + 1).copied().unwrap_or(0);
    let is_pli_block = block_pt == config::RTCP_PT_PSFB;

    let target = match self.find_publisher_for_subscribe_rtcp(
        subscriber, room, block.media_ssrc,
    ) {
        Some(t) => t,
        None => continue,   // 기존과 동일 — 매칭 실패 drop
    };

    // effective_ssrc 계산은 기존 코드 이식 (is_pli_block 분기 포함)
    let effective_ssrc = compute_effective_ssrc(&target, is_pli_block, block.media_ssrc, subscriber);

    let key = (target.room.id.to_string(), effective_ssrc);
    publisher_rtcp.entry(key.clone()).or_default().push(&plaintext[block.offset..block.offset + block.length]);
    if is_pli_block {
        *pli_per_key.entry(key).or_insert(0) += 1;
    }
}

// Step 2: 그룹별 전송 (기존)
//   - 키가 (room_id, ssrc) 로 변경 → PLI Governor 키, agg_log room_id 모두 matched room 기준
for ((room_id_str, effective_ssrc), blocks) in &publisher_rtcp {
    let matched_room = match self.room_hub.get(room_id_str.as_str()) {
        Ok(r) => r,
        Err(_) => continue,
    };
    let publisher = matched_room.find_by_track_ssrc(*effective_ssrc);
    // ... (기존 로직 그대로, room → matched_room 치환)
}
```

**핵심 변경점 2가지**:
- `publisher_rtcp` 의 키: `u32` → `(String /*room_id*/, u32)`. 같은 SSRC 가 여러 방에서 쓰일 수 있다는 가정은 실제로 거의 없지만, 키를 방별로 분리해 **PLI Governor 상태 / LAYER_CHANGED 알림 / agg_log room_id 가 정확한 방을 지칭**하도록 보장.
- `subscribe_layers` 조회 시 기존 `(publisher_id, room.id.clone())` 를 `(publisher_id, matched_room.id.clone())` 로. 기존 복합키 구조 활용 — 타입 변경 0.

**기존 동작 호환**: 단일방 (`rooms.len()==1`) 에선 `matched_room == room` → 키가 달라져도 값은 동일 → 그룹핑 결과 바이트 동일.

#### 2.3.3 `handle_nack_block`

현재 구조:
```rust
for nack in &nack_items {
    // ① find_publisher_by_vssrc → simulcast 역매핑
    // ② ptt virtual video ssrc 매칭 → 화자 video ssrc
    // 아니면 nack.media_ssrc 그대로
    // lookup_ssrc 결정 후 room.find_by_track_ssrc(lookup_ssrc)
}
```

변경 후:
```rust
for nack in &nack_items {
    let lost_seqs = expand_nack(nack.pid, nack.blp);
    METRICS.get().nack.seqs_requested.add(lost_seqs.len() as u64);

    let target = match self.find_publisher_for_subscribe_rtcp(
        subscriber, room, nack.media_ssrc,
    ) {
        Some(t) => t,
        None => {
            METRICS.get().nack.pub_not_found.inc();
            crate::agg_logger::inc_with(
                agg_key(&["nack_pub_not_found", &room.id]), // ← room (주 방) 그대로, 기존과 동일
                ..., Some(&room.id),
            );
            continue;
        }
    };

    // lookup_ssrc / cache_seqs 계산: 기존 로직 이식 (PTT 역매핑 / Simulcast reverse_seq)
    let (lookup_ssrc, cache_seqs) = resolve_nack_lookup(&target, &nack, &lost_seqs, subscriber);

    let publisher = &target.publisher;
    // ... (기존 로직 그대로, publisher 참조만 target.publisher 로)
    // RTX cache, budget, 에스컬레이션 등 변경 없음
}
```

**기존 동작 호환**: 단일방에선 helper 가 첫 시도에 주 방에서 hit → 기존 3경로 판별과 동일 순서로 결과 도출.

### 2.4 `find_publisher_for_subscribe_rtcp` 구현 세부

```rust
fn find_publisher_for_subscribe_rtcp(
    &self,
    subscriber: &Arc<RoomMember>,
    primary_room: &Arc<Room>,
    media_ssrc: u32,
) -> Option<SubscribeRtcpTarget> {
    // 1) 주 방 먼저 시도 (단일방에서는 여기서 반환)
    if let Some(t) = try_match_in_room(primary_room, media_ssrc) {
        return Some(t);
    }

    // 2) 다른 방 순회 (주 방 제외)
    for room_id in subscriber.endpoint.rooms_snapshot() {
        if room_id.as_str() == primary_room.id.as_str() { continue; }
        let room = match self.room_hub.get(room_id.as_str()) {
            Ok(r) => r,
            Err(_) => continue,
        };
        if let Some(t) = try_match_in_room(&room, media_ssrc) {
            return Some(t);
        }
    }
    None
}

fn try_match_in_room(room: &Arc<Room>, media_ssrc: u32) -> Option<SubscribeRtcpTarget> {
    // ① Simulcast
    if let Some(pub_p) = room.find_publisher_by_vssrc(media_ssrc) {
        return Some(SubscribeRtcpTarget {
            room: room.clone(),
            publisher: pub_p,
            lookup_kind: SsrcLookupKind::Simulcast,
            effective_ssrc: media_ssrc, // caller 가 계산
            real_seqs: None,
        });
    }
    // ② PTT audio virtual
    if room.audio_rewriter.virtual_ssrc() == media_ssrc {
        let speaker = room.floor.current_speaker().or_else(|| room.floor.last_speaker())?;
        let pub_p = room.get_participant(&speaker)?;
        return Some(SubscribeRtcpTarget {
            room: room.clone(),
            publisher: pub_p,
            lookup_kind: SsrcLookupKind::PttAudio,
            effective_ssrc: media_ssrc,
            real_seqs: None,
        });
    }
    // ③ PTT video virtual
    if room.video_rewriter.virtual_ssrc() == media_ssrc {
        let speaker = room.floor.current_speaker().or_else(|| room.floor.last_speaker())?;
        let pub_p = room.get_participant(&speaker)?;
        return Some(SubscribeRtcpTarget {
            room: room.clone(),
            publisher: pub_p,
            lookup_kind: SsrcLookupKind::PttVideo,
            effective_ssrc: media_ssrc,
            real_seqs: None,
        });
    }
    // ④ Conference 원본
    if let Some(pub_p) = room.find_by_track_ssrc(media_ssrc) {
        return Some(SubscribeRtcpTarget {
            room: room.clone(),
            publisher: pub_p,
            lookup_kind: SsrcLookupKind::Conference,
            effective_ssrc: media_ssrc,
            real_seqs: None,
        });
    }
    None
}
```

**단일방 동등성 증명 (§0 대원칙)**:
- `rooms.len()==1` ⇒ `rooms_snapshot()[0] == primary_room` ⇒ 2) 루프는 주 방 스킵 후 빈 순회 → helper 는 1) 결과 그대로 반환.
- 1) 내 판별 순서 (Simulcast → PTT audio → PTT video → Conference) 는 현재 `relay_subscribe_rtcp_blocks` / `handle_nack_block` 의 판별 순서와 동일.
- 따라서 단일방 hit/miss 결과는 기존과 바이트 단위 동일.

### 2.5 agg_log / PLI Governor / LAYER_CHANGED 키 정책

| 항목 | 현재 | 변경 후 | 근거 |
|---|---|---|---|
| `nack_pub_not_found` agg key | `[.., &room.id]` | **`room.id` 유지** | "subscriber 주 방" 의미 고정 (Step 10 원칙) |
| `rtx_cache_miss` / `nack_escalation` / `rtx_budget_exceeded` | `[.., &room.id, &subscriber.user_id]` | **`room.id` 유지** | 동일 |
| `pli_subscriber_relay` | `[.., &room.id, pub, sub]` | **`matched_room.id`** 로 변경 | publisher 참조 키는 matched room 기준이어야 cross-room 에서 의미. 단일방 동일. |
| `layer_downgrade` agg key | `[.., &room.id, sub]` | **`matched_room.id`** 로 변경 | 다운그레이드는 matched room 의 publisher 기준. 단일방 동일. |
| LAYER_CHANGED `room_id` field | `room.id.to_string()` | **`matched_room.id.to_string()`** | 알림 수신자 입장에서 "어느 방 맥락의 레이어 변경" 이 명확 |
| `subscribe_layers` 키의 room_id | `room.id.clone()` | **`matched_room.id.clone()`** | 기존 복합키 구조 그대로 활용. 단일방 동일. |

단일방에서는 `matched_room == room` 이므로 모든 키가 기존과 동일.

### 2.6 effective_ssrc / cache_seqs 계산: 기존 로직 그대로 이식

§2.3.2, §2.3.3 의 `compute_effective_ssrc` / `resolve_nack_lookup` 은 helper 가 `SubscribeRtcpTarget.lookup_kind` 와 `matched_room` 을 제공하면 **현재 코드 블록을 그대로 function 으로 감싼 것**. 로직 변경 0. 이식 목적은 함수 본체 가독성 복원 (block 당 분기 깊이 감소).

만약 함수 분리가 오히려 diff 를 키우면, 인라인 유지도 허용 (대원칙 위배 아님, 스타일 판단).

---

## 3. 파일·라인 범위

| 파일 | 함수 | 변경 |
|---|---|---|
| `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` | (신규) `SubscribeRtcpTarget` struct, `SsrcLookupKind` enum | 신설 ~30줄 |
| 〃 | (신규) `find_publisher_for_subscribe_rtcp()`, `try_match_in_room()` | 신설 ~70줄 |
| 〃 | `relay_subscribe_rtcp_blocks` | Step 1 그룹핑 루프에서 helper 호출 + 키 `(room_id, ssrc)` 로 변경. Step 2 전송 루프에서 matched_room 조회 + agg_log/Governor 키 matched_room 기준. ~80줄 |
| 〃 | `handle_nack_block` | helper 호출 + 반환된 target 사용. RTX/cache/에스컬레이션 로직 그대로. ~60줄 |
| 〃 | `handle_subscribe_rtcp` | 변경 없음 |

신규 pub 함수 0개. 외부 API 변경 0개.
예상 순증 LoC ≈ +150 (helper + struct/enum + 주석).
예상 순감 LoC ≈ -60 (기존 분기 deduplication).

---

## 4. 기각 대안

- **`room: &Arc<Room>` 인자 제거** — 세 함수 + 호출부 (`ingress.rs::handle_srtp`) 연쇄 변경 필요. 이익 없음. 진단용 "주 방" 의미도 잃음.
- **외부에서 방별 loop 으로 `handle_subscribe_rtcp` 다회 호출** — 같은 RTCP compound 를 N번 decrypt/parse. SRTP counter 진행 문제 발생 가능 (decrypt 는 inbound context 의 ROC/index 를 건드림). 기각.
- **주 방에서만 찾고 안 되면 drop (현재 동작 유지)** — 본 설계의 존재 이유. 기각.
- **publisher_rtcp 키를 `u32` 유지 + matched_room 을 Vec 로 부가** — 같은 SSRC 가 여러 방에서 중복될 때 모호. `(room_id, ssrc)` 복합키가 명확.
- **`find_publisher_for_subscribe_rtcp` 에서 모든 방 순회 후 "가장 적합한" 방 선택** — 첫 hit 으로 충분. 같은 SSRC 가 여러 방에서 매칭되는 시나리오는 사실상 없음 (simulcast virtual / PTT virtual 은 방별 고유, conference 원본 SSRC 는 publisher 가 어느 방에 있든 고유). 첫 hit 원칙으로 단일방 동등성 보장.

---

## 5. 공수

**3일** 예상.

- **Day 1 오전**: `SubscribeRtcpTarget` / `SsrcLookupKind` / `find_publisher_for_subscribe_rtcp` / `try_match_in_room` 신설.
- **Day 1 오후**: `relay_subscribe_rtcp_blocks` 리팩터. 단위 테스트 추가 (try_match_in_room 단독 테스트 4종 — Simulcast/PTT audio/PTT video/Conference hit).
- **Day 2 오전**: `handle_nack_block` 리팩터. 단위 테스트 추가 (helper 의 우선순위 순서 검증).
- **Day 2 오후**: `cargo test -p oxsfud --release` → 114 + 신규. voice_radio / conference 단일방 E2E.
- **Day 3 오전**: dispatch (FullSim 시나리오), support (화면공유 시나리오), moderate (grant 기반 duplex 전환) 회귀.
- **Day 3 오후**: labs conf_basic 등 회귀.

---

## 6. 검증 계획

### 6.1 대원칙 회귀 (필수, **절대 양보 없음**)
- `cargo test -p oxsfud --release`: **114 passed 유지** + 신규 helper 테스트.
- voice_radio: PTT 발화 → NACK / PLI 동작 증상 0 변화. RTX 복구율 동일.
- conference: Simulcast h/l 전환, 다운그레이드, LAYER_CHANGED 도착. 기존과 육안 구분 불가 수준.
- dispatch / support / moderate: 모두 동일 증상.
- 어드민 스냅샷 `nack.pub_not_found` / `nack.cache_miss` / `pli.throttled` 카운터: 동일 부하에서 수치 차이 ±5% 이내.

### 6.2 신규 단위 테스트
- `try_match_in_room` — Simulcast vssrc hit, PTT audio/video virtual hit, Conference 원본 hit, 모두 miss 시 None.
- `find_publisher_for_subscribe_rtcp` 단일방 동등성 — `rooms_snapshot()` 에 1개 방만 있을 때 결과가 `try_match_in_room(primary_room)` 과 동일.
- (선택) `find_publisher_for_subscribe_rtcp` 다방 우선순위 — 주 방 miss + 타 방 hit 시 타 방 반환, 타 방 room_id 확인.

### 6.3 Cross-room 실동작 검증 (SDK cross-room 완료 후, 본 설계 완료 기준에 **미포함**)
- subscriber A 가 ch1/ch2 가입. ch2 publisher B 의 video 에 대해 NACK → B 에게 RTX 전달 확인.
- ch2 publisher B 의 simulcast 레이어 다운그레이드 → LAYER_CHANGED `room_id=ch2` 로 A 에게 도착.

---

## 7. 오늘의 지침 후보

- **단일방 동등성은 '논증'으로 보장한다.** "단일방이면 loop 1회라 동작 변화 0" 은 구호가 아니라 설계 선택 하나하나에서 반복 확인해야 하는 조건. `rooms_snapshot()` 의 첫 원소 == `primary_room` 을 보장하는 순서로 helper 를 짜는 이유.
- **Subscribe PC 는 물리 1개, RTCP 귀환 경로 매칭은 subscriber.rooms 순회가 원칙.** Publish 쪽 fan-out 루프를 심었으면 RTCP 귀환 쪽도 같은 규칙이 필요 — B 의 "반쪽짜리 상태 닫기" 원리와 동일.
- **SSRC 기반 lookup 을 방 하나로 제한하면 안 된다.** PTT virtual / Simulcast virtual / Conference 원본 어느 것도 "방 global" 이 아님. 한 방에서 fail 하면 다른 방도 시도해야 옳다.
- **Decrypt 는 한 번만.** RTCP compound 를 외부에서 rooms loop 돌며 N번 decrypt 하면 SRTP context 를 망친다. 방 순회는 **파싱 완료 후의 매칭 단계에서만**.

---

## 8. 후속 작업 연결

- 본 설계 완료 후 **SDK Cross-Room 설계서** (별건): 진행자 다방 참여를 SDK/서버/hub 3층에 완결. 본 설계가 subscribe RTCP 의 서버측 cross-room 대응을 마쳐두면, SDK 쪽이 다방 JOIN 을 실제로 발행할 때 server-side 가 깨끗이 받아준다.
- Phase 2 type:relay — 보류 (Zoom 수준 스케일 시 착수).

---

*author: kodeholic (powered by Claude), 2026-04-19*
