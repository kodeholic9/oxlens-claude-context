# SubscriberStream Mode 재설계 — 단일 출처화

> author: kodeholic (powered by Claude)
> 작성일: 2026-04-30
> 상태: 부장님 review 대기
> 관련 설계: `20260427_track_lifecycle_redesign.md` (rev.4) 의 §3.2 (RoomScopedStats) 정정

## 0. 한 줄 요약

**`SubscriberStream` 의 매칭 분기를 `Option<layer_entry>` 의 우연한 조합 → `SubscribeMode` enum 으로 단일 출처화. simulcast 여부가 4 곳에 분산된 상태를 정리하고, lazy create 시점 의존성을 제거. forward 본문은 `match self.mode` 단일 분기로 수렴. 이전 설계 (`20260427` rev.4 §3.2) 의 `RoomScopedStats` 가 두 책임 (방 분리 + sim 분리) 을 섞었던 것을 분리.**

---

## 1. 배경 — 현재 회귀

### 1.1 증상 (2026-04-30 시뮬 2명 시험)

publisher h-rid + l-rid RTP 정상 도착 (`rtp_in_h=468`, `rtp_in_l=90`), `forward_entered=558` (simulcast 가드 통과), 그러나:

```
forward_ok / drop_*=0    ← simulcast 분기 카운터 0
scoped_nonsim_for_sim=558 ← forward_entered 와 100% 매칭
```

= **모든 simulcast video forward 호출이 nonsim 분기로 빠짐**. 클라 inbound video=0.

### 1.2 표면 원인 — `RoomScopedStats.layer_entry` lazy create 가 nonsim 으로 박힘

`forward` 본문:
```rust
let new_scoped = if publisher.simulcast && publisher.kind == Video {
    Arc::new(RoomScopedStats::new_simulcast(...))   // layer_entry: Some
} else {
    Arc::new(RoomScopedStats::new_nonsim(...))      // layer_entry: None
};
```

이 `Vacant` 분기는 **첫 호출 1회**. 이후 558회는 `Occupied` 재사용. 첫 1회가 nonsim 으로 박히면 영구. 이후 publisher.simulcast 가 true 여도 결과 영향 없음.

추적해보니 **PublisherStream.simulcast 자체는 모두 true 정확히 박힘**:
- bob.video.h.simulcast = true
- bob.video.l.simulcast = true
- alice.video.h.simulcast = true
- alice.video.l.simulcast = true

→ publisher 데이터는 정확. forward 본문의 가드 평가도 정확. 그런데 lazy create 결과만 어긋남. **자료구조의 표현 방식 자체가 race 를 방치하는 구조**.

### 1.3 부장님 일침 (요지)

> 트랙 라이프사이클 넣은 건데 디버깅이 더 어려워지면 말이 되? 단일 값 보고 분기시켜야 되는데 중간 중간 조건이 많아? 자료구조 문제야?

→ **YES. 자료구조 자체의 구조적 문제**.

---

## 2. 현재 자료구조의 5가지 문제

### P1 — 한 컨테이너에 책임 2개 섞임

```
SubscriberStream
 └── room_stats: DashMap<RoomId, Arc<RoomScopedStats>>
      └── RoomScopedStats {
           layer_entry: Option<Mutex<SubscribeLayerEntry>>,   ← 책임 B (sim 분리)
           send_stats:  Mutex<SendStats>,                     ← 책임 A (방 분리)
           stalled:     Mutex<StalledSnapshot>,               ← 책임 A (방 분리)
       }
```

- 책임 A: 방별 stats 독립 집계 (cross-room 의 본질)
- 책임 B: simulcast layer 매칭 + SimulcastRewriter (publisher 미디어 종류)

두 축은 **다른 차원**. 한 컨테이너에 묶으면 단일 변경이 두 책임에 영향.

### P2 — `simulcast 여부` 가 4 곳에 분산 (단일 출처 위반)

| 위치 | 표현 | 갱신 시점 |
|---|---|---|
| `PublisherStream.simulcast: bool` | **ground truth, 불변** | publisher 등록 1회 |
| `RoomScopedStats.layer_entry: Option<...>` | Some=sim, None=nonsim 간접 | 첫 RTP lazy create 1회 |
| `SubscriberStream.virtual_ssrc != publisher.ssrc` | 간접 (sim 만 vssrc 발급) | SubscriberStream 등록 시 |
| `intent.video_sources[i].simulcast` | 시그널링 의도 | PUBLISH_TRACKS 마다 |

→ 4 곳이 race 시점에 어긋날 수 있음. 현재 회귀가 정확히 이 모양.

### P3 — `lazy create` 가 시점 의존적

`Vacant` 분기는 **첫 1회만** publisher 평가. 이후 호출은 결과 재사용. 첫 1회가 어떤 race 로든 잘못되면 영구 회귀. 그런데 그 평가 시점에 publisher 가 어떤 상태였는지 추적 어려움 (이번 디버깅이 정확히 막다른 골목).

### P4 — 분기 조건 분산

forward 본문 안에서 같은 의미 `publisher.simulcast && kind==Video` 가 **3 번** 평가:

1. forward_entered 가드 (매번 평가)
2. lazy create 분기 (1회만 평가)
3. `scoped.layer_entry.as_ref()` (매번, but (2) 결과 의존)

(1) 와 (3) 이 따로 살아있어 **일관성 보장 코드 부재**. (1) 통과해도 (3) 가 막힐 수 있음.

### P5 — `Option<...>` 의 의미 모호

`layer_entry: Option<...>` 가 의미하는 것이 셋 다 가능:
- (a) publisher 가 simulcast 인가?
- (b) 이 SubscriberStream 이 simulcast 모드인가?
- (c) layer 매칭이 활성화됐는가?

같은 Option 이 셋 다 표현. 코드 read 시 어느 의미인지 매번 추론 필요. 신규 개발자/AI 에게도 부담.

---

## 3. 설계 원칙 (정석)

1. **단일 출처** — simulcast / via-slot / audio 여부는 단일 변수. 다른 곳은 그것을 **참조만**.
2. **분기 = enum match** — Option/bool 의 우연한 조합 아닌 명시적 enum. 컴파일러가 빠짐 강제 (`match` exhaustiveness).
3. **책임 = 컨테이너 1개** — 방별 stats 와 simulcast 매칭을 따로.
4. **시점 결정 명확** — SubscriberStream 등록 시점 (intent + publisher 알고 있는 시점) 에 mode 확정. 이후 불변. lazy create 의 시점 의존 제거.

---

## 4. 새 자료구조

### 4.1 `SubscribeMode` enum (단일 출처)

```rust
pub enum SubscribeMode {
    /// 오디오 (full / half 무관 — half audio 도 결국 fan-out 단계에서는 그대로 forward).
    Audio,

    /// 일반 video (non-simulcast). 1:1 SSRC 매핑, layer 매칭 없음.
    VideoNonSim,

    /// Simulcast video. layer 매칭 + SimulcastRewriter.
    VideoSim {
        layer: Mutex<SubscribeLayerEntry>,
    },

    /// PTT/Hall slot 경유. prefan_payload 사용 + PT rewrite.
    /// kind 는 SubscriberStream.kind (Audio | Video) 로 구분.
    ViaSlot,
}
```

**불변** — SubscriberStream 등록 시점에 정해지고 그 후 안 바뀜. publisher 가 sim 에서 nonsim 으로 바뀌는 일도 없음 (PublisherStream.simulcast 자체 불변).

### 4.2 `RoomStats` (방별 stats 만, sim 분리 책임 제거)

```rust
pub struct RoomStats {
    pub send_stats: Mutex<SendStats>,
    pub stalled:    Mutex<StalledSnapshot>,
}
```

기존 `RoomScopedStats` 에서 `layer_entry` 만 떼어냄. rename: `RoomScopedStats` → `RoomStats` (책임 명확).

### 4.3 `SubscriberStream` 최종 구조

```rust
pub struct SubscriberStream {
    // === identity (불변) ===
    pub mid:           u8,
    pub virtual_ssrc:  u32,
    pub kind:          TrackKind,
    pub subscriber_id: Arc<str>,

    // === publisher 참조 (가변, RCU) ===
    pub publisher_ref: ArcSwap<PublisherRef>,

    // === 모드 (불변, 단일 출처) ===
    pub mode:          SubscribeMode,                    // ← NEW

    // === 방별 stats (sim 책임 제거) ===
    pub room_stats:    DashMap<RoomId, Arc<RoomStats>>,  // ← layer_entry 제거됨

    // === PC 단위 자산 ===
    pub gate:          Mutex<SubscriberGate>,

    // === 메타 ===
    pub peer_ref:      Weak<Peer>,
}
```

---

## 5. mode 결정 시점 — `add_subscriber_stream`

ingress.rs::notify_new_stream 안에서 SubscriberStream 등록할 때 mode 결정:

```rust
let mode = if is_via_slot {
    SubscribeMode::ViaSlot
} else {
    match (sub_kind, publisher_stream.simulcast) {
        (TrackKind::Audio, _)     => SubscribeMode::Audio,
        (TrackKind::Video, false) => SubscribeMode::VideoNonSim,
        (TrackKind::Video, true)  => SubscribeMode::VideoSim {
            layer: Mutex::new(SubscribeLayerEntry {
                rid:               "h".to_string(),
                target_rid:        None,
                rewriter:          SimulcastRewriter::new(virtual_ssrc),
                pli_state:         PliSubscriberState::new(),
                publisher_user_id: publisher_user_id_arc.clone(),
            }),
        },
    }
};

let sub_stream = sub.peer.add_subscriber_stream(
    mid_u8, ssrc_for_subscriber, sub_kind, publisher_ref, mode,
);
```

**중요**: 이 시점에는 PUBLISH_TRACKS intent 도착 후, publisher 의 PublisherStream 도 등록 후. publisher.simulcast 값이 **확정**된 상태. lazy create 시점 race 없음.

---

## 6. forward 본문 — `match self.mode` 단일 분기

```rust
pub(crate) fn forward(self: &Arc<Self>, publisher: &PublisherStream, ...) -> bool {
    // === 1. gate 검사 (Direct + Video 만) ===
    if !matches!(self.mode, SubscribeMode::ViaSlot) && self.kind == TrackKind::Video {
        if let Ok(mut gate) = self.gate.lock() {
            if !gate.is_allowed(sender_user_id) { return false; }
        }
    }

    // === 2. RoomStats lazy create (sim 책임 없음, layer_entry 없음) ===
    let stats = self.room_stats.entry(room.id.clone())
        .or_insert_with(|| Arc::new(RoomStats::new(self.virtual_ssrc, ...)))
        .clone();

    // === 3. mode 단일 분기 ===
    let (final_payload, need_pli) = match &self.mode {
        SubscribeMode::Audio | SubscribeMode::VideoNonSim => {
            (Some(plaintext.to_vec()), false)
        }
        SubscribeMode::VideoSim { layer } => {
            // simulcast layer 매칭 + SimulcastRewriter (기존 로직)
            self.forward_simulcast(layer, publisher, plaintext, rtp_hdr, is_keyframe, ...)
        }
        SubscribeMode::ViaSlot => {
            // prefan_payload + PT rewrite (기존 로직)
            self.forward_via_slot(prefan_payload, target, ...)
        }
    };

    // === 4. egress + stats 갱신 ===
    ...
}
```

- `match` exhaustiveness — 새 mode 추가 시 컴파일러가 모든 호출처 갱신 강제
- forward_entered / scoped_nonsim_for_sim 같은 race 카운터 **불필요** (모순 자체가 없음)
- `RoomStats` lazy create 는 sim/nonsim 무관 — 단일 path

---

## 7. 단계 분할 (안전 마이그레이션)

각 phase 독립 빌드 검증. 한 번에 한 책임.

### Phase 1 — 자료구조 신설 (dead code)

- `SubscribeMode` enum 정의 (subscriber_stream.rs)
- `RoomStats` 구조체 정의 (sim 책임 제거)
- 기존 `RoomScopedStats` 그대로 둠
- `#![allow(dead_code)]` 로 미사용 허용
- 빌드 검증: `cargo check`

### Phase 2 — `SubscriberStream.mode` 필드 추가

- `SubscriberStream` 에 `mode: SubscribeMode` 필드 추가
- `add_subscriber_stream` 시그너처 변경 — mode 인자 추가
- 호출처 (ingress.rs::notify_new_stream) 1곳에서 mode 결정 로직 추가
- `room_stats` 는 그대로 `DashMap<RoomId, Arc<RoomScopedStats>>` 유지 (Phase 4 까지)
- 빌드 검증: `cargo check` + 기존 252 테스트 PASS

### Phase 3 — `forward` 본문 재작성

- `match self.mode` 분기로 재작성
- 기존 `scoped.layer_entry.as_ref()` 분기 제거
- forward 본문에서 simulcast 매칭은 `SubscribeMode::VideoSim { layer }` 의 `layer` 사용
- 빌드 검증: `cargo check` + 시뮬 2명 회귀 시험 (현 회귀 fix 확인)

### Phase 4 — `RoomScopedStats.layer_entry` 제거 + rename

- `RoomScopedStats` 에서 `layer_entry` 필드 제거
- `RoomScopedStats` → `RoomStats` rename
- 호출처 (admin snapshot / SR translation / STALLED) 의 `scoped.layer_entry` 참조를 `mode` 참조로 변경
- 빌드 검증: `cargo check`

### Phase 5 — 정리

- 임시 디버그 카운터 (`forward_entered`, `scoped_nonsim_for_sim`, `forward_drop_gate`, `[FANOUT:DBG]`, `[INGRESS:FANOUT]`) 제거 또는 정상 운영용으로 감산
- CHANGELOG 갱신
- PROJECT_MASTER 의 트랙 라이프사이클 Phase 카운터 갱신
- 빌드 검증: `cargo test` (252 PASS) + 시뮬 2명 + PTT 8명 회귀 시험

---

## 8. 호환성 / 회귀 위험

### 8.1 변경 범위 (예상 ±1000 라인)

| 파일 | 변경 폭 |
|---|---|
| `subscriber_stream.rs` | enum 추가 + forward 재작성 (+200, -100) |
| `peer.rs::add_subscriber_stream` | 시그너처 변경 (+10, -5) |
| `ingress.rs::notify_new_stream` | mode 결정 로직 (+30, -5) |
| `transport/udp/ingress.rs::build_sr_translation` | `scoped.layer_entry` → `mode` 참조 (+10, -10) |
| `signaling/handler/admin.rs` | snapshot 갱신 (+5, -2) |
| STALLED checker (있다면) | scoped 참조 갱신 |

### 8.2 회귀 위험

**낮음** — 기존 동작과 의미적으로 동등 (분기 결과 같음). 단, mode 결정 시점이 lazy → 즉시로 바뀌므로:

- 위험 1: SubscriberStream 등록 시점에 publisher.simulcast 가 false 였다가 후에 true 로 바뀌는 race? → **불가능**. PublisherStream.simulcast 는 불변. 등록 시점이 publisher 등록 후이므로 race 없음.
- 위험 2: PUBLISH_TRACKS 후속 update 로 simulcast 변경? → 현 코드도 simulcast 갱신 안 함 (`create_or_update_at_rtp` 가 hot-swap 시 simulcast 보존). 의미 동일.
- 위험 3: notify_new_stream 보다 먼저 RTP 도착 → SubscriberStream 등록 자체가 안 됨. forward 호출도 안 됨. 안전.

### 8.3 PTT/Hall 회귀

- ViaSlot 분기는 기존과 동일 — prefan_payload 사용 + PT rewrite
- Half-duplex audio/video 의 mode 는 `SubscribeMode::ViaSlot` (publisher_ref::ViaSlot 와 정합)
- 8명 PTT 회귀 시험 Phase 5 에서 검증

---

## 9. 검증 전략

### 9.1 단위 테스트 (Phase 1, 4)

- `SubscribeMode` enum 의 분기 exhaustiveness 보장 (컴파일러)
- `RoomStats::new` / `SubscribeMode::*` 생성 테스트

### 9.2 통합 회귀 (Phase 3)

- 시뮬 2명 — 현 회귀 (forward_entered=N, scoped_nonsim_for_sim=N) fix 확인
- 시뮬 2명 — h-rid / l-rid layer 전환 정상 동작 (PLI burst, switch_layer)
- 일반 video (non-sim) 1:1 — 동작 정상

### 9.3 PTT 회귀 (Phase 5)

- PTT 8명 + half-duplex audio + half-duplex video — Slot rewriter 동작
- Conf + PTT 혼합

### 9.4 STALLED 검증

- `RoomStats.stalled` lazy create 시점 정합 (Phase 4)

---

## 10. 결재 의뢰

부장님 review 의뢰:

- **A**: 위 설계 그대로 진행 (Phase 1~5)
- **B**: enum variant 이름 / 책임 분리 방식 / Phase 분할 다른 의견
- **C**: 추가 조사 필요 (예: PublisherRef 와 SubscribeMode 의 통합 가능성?)

### 10.1 PublisherRef 와 SubscribeMode 분리 유지 근거

`PublisherRef` (Direct / ViaSlot / None) 와 `SubscribeMode` (Audio / VideoNonSim / VideoSim / ViaSlot) 가 일부 겹침 (ViaSlot). 합치자는 의견 가능. 그러나 분리 유지 권장:

- `PublisherRef` = **참조 종류** (Weak vs Strong, Direct vs Slot). 가변 (publisher 가 사라지면 None 으로).
- `SubscribeMode` = **forward 분기** (어떤 처리 path 인가). 불변.

**갱신 주기 다름**. 합치면 가변/불변 섞이고, 무엇보다 ViaSlot mode 의 audio/video 구분을 SubscribeMode 만으로 처리하기 어려움 (현재는 `kind` 와 `publisher_ref` 둘 다 봄). 분리 유지가 의미 명확.

---

## 11. 참고

- 영향 design doc: `20260427_track_lifecycle_redesign.md` rev.4 §3.2 (RoomScopedStats) → 본 설계 적용 후 §3.2 정정 필요
- 이전 회귀 분석: `context/202604/20260430b_fanout_debug_vssrc_revert.md`
- 본 회귀 디버깅 trail: 시뮬 4차 시험 데이터 + 자료구조 자기진단 P1~P5
