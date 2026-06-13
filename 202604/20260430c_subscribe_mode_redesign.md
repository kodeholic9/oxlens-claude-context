# 20260430c — SubscribeMode 재설계 (Phase 1~5a 완료)

> 본 세션 = 직전 fan-out 회귀 진단 ([20260430b_fanout_debug_vssrc_revert](20260430b_fanout_debug_vssrc_revert.md)) 의 후속.
>
> 진단으로 밝혀진 회귀의 **자료구조적 근본 원인**을 김대리(매크로 분석)가 파악, 부장님 결재 후 SubscribeMode enum 도입으로 fix.

---

## 들어가기 전 — 회귀의 본질 (다음 세션 회복용)

### 직전 회귀 (20260430b 에서 발견)

```
시뮬 2명 simulcast video → forward_entered=558 = scoped_nonsim_for_sim=558
publisher.simulcast=true 정확한데 forward 의 lazy create 가 nonsim 으로 박힘
→ layer_entry=None → 모든 simulcast forward 가 nonsim 분기
→ 클라 framesDecoded=0 (영상 안 보임)
```

### 근본 원인 — 자료구조의 **단일 출처 위반**

simulcast 여부가 **4 곳에 분산** (P2):
1. `publisher.simulcast: bool` — publisher 본체
2. `RoomScopedStats.layer_entry: Option<...>` — receiver 측 lazy create 결과
3. `publisher_ref::Direct/ViaSlot` — ArcSwap
4. `publisher.kind: TrackKind` — 부분 정보

→ forward 본문이 (1) + (2) 둘에 의존. 첫 RTP 도착 시점의 lazy create 결과 영구화 → 시점 race.

부장님 일침:
> "트랙 라이프사이클 넣은 건데 디버깅이 더 어려워지면 말이 되? 단일 값 보고 분기시켜야 되는데 중간 중간 조건이 많아?"

### 해법 — `SubscribeMode` enum 단일 출처

```rust
pub enum SubscribeMode {
    Audio,
    VideoNonSim,
    VideoSim { layer: Mutex<SubscribeLayerEntry> },
    ViaSlot,
}
```

- `SubscribeMode::derive(is_via_slot, kind, publisher_simulcast, virtual_ssrc, publisher_user_id)` 헬퍼로 SubscriberStream 등록 시점 1회 결정 후 **불변**.
- forward 본문이 `match self.mode` 단일 분기 — 시점 의존성 0.
- 새 mode 추가 시 컴파일러가 모든 호출처 갱신 강제 (`match` exhaustiveness).

설계서: `context/design/20260430_subscriber_mode_redesign.md`

---

## 진행 결과 (Phase 1~5a 완료)

### Phase 1: 자료구조 신설 (dead, +68L)

- `subscriber_stream.rs`: `SubscribeMode` enum + `::derive()` 헬퍼 + 새 `RoomStats` struct (dead, `#![allow(dead_code)]`).

### Phase 2: SubscriberStream.mode 필드 + 호출처 결정 로직 (4 파일)

- `SubscriberStream.mode: SubscribeMode` 필드 추가, `::new` 시그너처에 mode 인자.
- `peer.rs::add_subscriber_stream`: 시그너처 mode 추가 + import.
- `ingress.rs::notify_new_stream`: `publisher_stream_arc.simulcast` 직접 read + mode 결정.
- `helpers.rs::collect_subscribe_tracks`: publisher_refs tuple 6요소 확장 `(PublisherRef, vssrc, kind, is_via_slot, publisher_simulcast, publisher_user_id)`. **PTT slot 도 (is_via_slot=true) 로 등록**.
- `track_ops.rs:351` (FullNonSim 분기): `publisher_simulcast=false` 하드코딩.

### Phase 3: forward 본문 match 재작성 (subscriber_stream.rs, ★ 회귀 fix)

- forward 본문 통째 재작성. 모든 가드를 `self.mode` 단일 출처로:
  - `publisher.simulcast` 가드 → `matches!(self.mode, VideoSim{..})`
  - `publisher_ref::ViaSlot` ArcSwap.load() → `matches!(self.mode, ViaSlot)`
  - `publisher.kind` → `self.kind`
  - `layer_entry` 분기 → `match &self.mode { VideoSim { layer } => ... }`
  - **lazy create 의 simulcast 분기 제거 — 항상 nonsim 으로 박음** (layer_entry 책임은 mode 가 담당)
- 키프레임 pli_state 갱신 분기도 `if let SubscribeMode::VideoSim { layer }` 로 전환.

**시뮬 2명 시험 결과**:
```
forward_ok=764, scoped_nonsim_for_sim=0, framesDecoded=118~120
회귀 fix 확정.
```

### Phase 4a: 호출처 mode 참조로 전환 (track_ops.rs / ingress.rs)

- `track_ops.rs::handle_subscribe_layer` (op=51 SUBSCRIBE_LAYER): `RoomScopedStats lazy create + layer_entry` 의존 폐기 → `sub_stream.mode::VideoSim { layer }` 직접 참조. ~50L → ~30L.
- `ingress.rs::build_sr_translation` (sim 분기): 같은 패턴.

**SUBSCRIBE_LAYER 동작 검증**: `engine.subscribeLayer([{user_id, rid: 'l'}])` 호출 시 클라 frameWidth 640→160 정상 전환.

### Phase 4b/4c: RoomScopedStats 통째 삭제 + RoomStats 단독화

- 기존 `RoomScopedStats` struct + impl (~80L) 통째 삭제.
- `SubscriberStream.room_stats` 타입: `DashMap<RoomId, Arc<RoomScopedStats>>` → `Arc<RoomStats>`.
- 호출처 추가 4 파일 (빌드 에러 추적):
  - `egress.rs:191` — `RoomScopedStats::new_nonsim` → `RoomStats::new`
  - `ingress_subscribe.rs:285/370/567` — `s.room_stats.get(...).layer_entry` → `s.mode::VideoSim::layer` 직접 참조
  - `tasks.rs:215` (run_stalled_checker pause 가드) + `tasks.rs:381` (run_pli_governor_sweep) — 같은 패턴

### Phase 5a: admin snapshot 에 sub_streams 노출 (★ UI fix)

- `admin.rs::build_users_snapshot` user 뷰에 `sub_streams` 배열 추가:
  ```json
  {
    "mid": 3,
    "vssrc": "0x2A9DB6AA",
    "kind": "video",
    "mode": "VideoSim",
    "current_rid": "l",
    "target_rid": null,
    "rewriter_initialized": true
  }
  ```
- UI 가 `current_rid` 보고 `sim:on/l` 표시 가능 (이전엔 publisher 측 stream_map 의 rid 만 보여서 항상 `sim:on/h`).

### Phase 5b: dead 카운터 + 임시 디버그 정리

- `sfu_metrics.rs::SimulcastMetrics` dead 카운터 3개 struct 필드 자체 제거: `forward_entered`, `forward_drop_gate`, `scoped_nonsim_for_sim`.
- forward 본문 디버그 카운터 호출 제거 (Phase 5b 첫 단계).

### Phase 5c: doc comment 정리 (부분 완료)

- 한국어 인코딩 매칭 일부 실패 — 코드 컴파일 영향 없음. 다음 세션 정리 가능.

---

## 시뮬 시험 데이터 (3명 simulcast video)

### 라운드 1 검증 (Phase 4 + 5a 완료 직후)

```
SFU 카운터:
  forward_entered:        0      ← Phase 5b 호출처 제거 (정상)
  forward_ok:           529
  forward_drop_layer:   399
  scoped_nonsim_for_sim:  0      ← race 0 (mode 단일 출처 작동)
  layer_switched:         0      ← 카운트 위치 문제 (실제 전환은 됐음, Phase 5 후속 정리)
  rtp_in_h:             326
  rtp_in_l:             138

클라 inbound (alice → bob.l 전환 후):
  alice ← bob.video:    160×90 ✅ (l-rid 전환 성공)
  alice ← charlie:      640×360 (h 유지)
  charlie ← alice:      160×90 ✅ (l-rid 전환 성공)
  나머지 4건:           640×360 (h 유지)

admin sub_streams (alice):
  { mid:3, vssrc:0x2A9DB6AA, kind:video, mode:"VideoSim", current_rid:"l", rewriter_initialized:true }
  ← UI 가 current_rid="l" 보고 sim:on/l 표시 가능
```

---

## 변경 파일 누계 (라운드 1 + 2)

| 파일 | 변경 |
|---|---|
| `subscriber_stream.rs` | SubscribeMode enum 신설 + RoomScopedStats 통째 삭제 + RoomStats 단독 + SubscriberStream.mode 필드 + ::new 시그너처 + forward 본문 match 재작성 |
| `peer.rs` | add_subscriber_stream 시그너처 mode 추가 + import |
| `ingress.rs` | notify_new_stream mode 결정 + build_sr_translation sim 분기 mode 참조 |
| `helpers.rs::collect_subscribe_tracks` | publisher_refs 6요소 + PTT slot is_via_slot=true |
| `track_ops.rs` | FullNonSim 분기 mode 인자 + record_stalled_snapshot RoomStats::new + handle_subscribe_layer mode 참조 |
| `egress.rs` | run_egress_task RoomStats::new |
| `ingress_subscribe.rs` | 3 곳 (Simulcast NACK rid lookup + PLI Governor + handle_nack_block sim 분기) mode 참조 |
| `tasks.rs` | run_stalled_checker pause 가드 + run_pli_governor_sweep mode 참조 + room_stats 내부 루프 평탄화 |
| `admin.rs::build_users_snapshot` | sub_streams 배열 추가 |
| `sfu_metrics.rs` | SimulcastMetrics 3 dead 카운터 제거 |

---

## ★ 내일 시험 점검표 (가장 중요)

### 1. half-duplex PTT 시험 (필수)

본 세션은 simulcast (full-duplex video) 만 검증. **Half-duplex (ViaSlot mode) 미검증**.

#### 검증 대상

```
SubscribeMode::ViaSlot 분기:
  - is_via_slot 판정이 self.mode 로 전환됨 (publisher_ref ArcSwap.load() 검사 제거)
  - prefan_payload 사용 + PT rewrite (Video) 정상
  - PTT audio (kind=Audio) 의 floor gating 동작
```

#### 시험 시나리오

1. **음성무전 (voice_radio)**: 3명 spawn, half-duplex audio only.
   - alice 발화 (floor.request → granted) → bob/charlie inbound audio 정상 수신
   - alice release → silence flush → bob 발화 → 화자 전환 정상
2. **영상무전 (video_radio)**: 3명 spawn, half-duplex audio + video.
   - 발화자 video freeze masking 정상 (ViaSlot video 의 PT rewrite + prefan_payload)
3. **혼합 시나리오 (dispatch)**: full + half 동시.

#### QA UI spawn 패턴

```js
await __qa__.spawn({
  user: 'alice', room: 'qa_ptt_01',
  tracks: { mic: { enabled: true, duplex: 'half' } },
});
// floor request 호출 패턴은 다음 세션에서 확인 필요 — engine._currentRoom?.floor?.request() 가능성
```

### 2. 클라 SDK 측 UI fix (별도 세션)

부장님 영역. admin snapshot 의 `user.sub_streams[].current_rid` 보고 화면 표시 갱신:
- 현재: `sim:on/h` 항상 표시 (publisher stream_map 의 rid 만 봄)
- 목표: `sim:on/l` 등 receiver 측 current layer 표시

### 3. Phase 4 의 ViaSlot 분기 회귀 가능성 (의심)

부장님 "로컬/리모트 아무 화면이 안나오는데" 메시지 — 진단 미완.

가능성:
- (a) qa UI 봤음 → 정상 (디버그 페이지에 video 없음)
- (b) 데모 시나리오 페이지 → live-server 응답 없음 등 환경 문제
- (c) **Phase 4 의 ViaSlot 분기 회귀** — collect_subscribe_tracks 의 PTT 등록은 정상이지만 forward 본문에서 ViaSlot 매칭 실패 가능성

**검증법**: 데모 voice_radio 페이지 직접 열고 floor 시험.

#### ViaSlot 분기 검증 코드 위치

`subscriber_stream.rs::forward` 의 line ~310 부근:
```rust
SubscribeMode::ViaSlot => {
    let payload = if self.kind == TrackKind::Video {
        let target_pt = target.peer.subscribe.expected_video_pt.load(Ordering::Relaxed);
        if target_pt > 0 {
            let mut p = payload_base.to_vec();
            let marker = p[1] & 0x80;
            p[1] = marker | (target_pt & 0x7F);
            p
        } else { payload_base.to_vec() }
    } else { payload_base.to_vec() };
    (Some(payload), false)
}
```

**audio 의 경우 PT rewrite 안 함, 그대로 forward**. 정상이어야 함.

`is_via_slot` 가드:
```rust
let is_via_slot = matches!(self.mode, SubscribeMode::ViaSlot);
let payload_base: &[u8] = if is_via_slot {
    match prefan_payload {
        Some(p) => p,
        None => return false,  // ← 이 분기 진입하면 PTT silence
    }
} else { plaintext };
```

**`prefan_payload=None` 일 때 false 반환**. PTT 발화자 없으면 prefan 결과 없으니 정상. 발화자 있는데 None 이면 회귀.

---

## 부장님 결재 사항 (PROJECT_MASTER 갱신 제안)

직접 수정 금지 원칙 (메모리). 다음 변경 제안:

### "현재 상태" 섹션에 항목 추가

```
**Phase 2.5 (2026-04-30): SubscribeMode 도입 + simulcast video fan-out 회귀 fix 완료**
- SubscribeMode enum 신설 (Audio / VideoNonSim / VideoSim{layer} / ViaSlot)
- 4 곳 분산된 simulcast 여부 표현(P2)을 enum 단일 출처로 수렴
- forward 본문 match 단일 분기 — 시점 race 제거
- 호출처 8 파일 mode 참조로 전환 (track_ops / ingress / ingress_subscribe / egress / tasks / helpers / peer / admin)
- RoomScopedStats → RoomStats rename + layer_entry 필드 제거
- admin snapshot 에 user.sub_streams 배열 추가 (mode + current_rid + target_rid + rewriter_initialized) — UI 의 sim:on/h 표시 fix
```

### "핵심 학습 & 원칙" 추가

```
- **SubscribeMode 단일 출처** — simulcast 여부를 4 곳 (publisher.simulcast / scoped.layer_entry / publisher_ref / publisher.kind) 에 분산하면 시점 race 발생. enum match exhaustiveness 로 컴파일러가 호출처 갱신 강제
```

### "기각된 접근법" 추가

```
- **Option<layer_entry> 의 Some/None 으로 simulcast 여부 표현** — 첫 RTP 시점의 publisher 평가 결과가 lazy create 로 영구화. mode enum 으로 등록 시점 1회 결정이 정답
- **scoped_nonsim_for_sim 같은 추적 카운터로 race 검출** — 자료구조 본질 fix 가 정답. 카운터는 race 가 일어나는 자료구조 위에 임시 진단
```

---

## 학습 환류 (반복 위험)

1. ⭐⭐⭐ **자료구조의 단일 출처 위반** — 회귀의 본질. 부장님 일침으로 발견 (김대리는 디버깅 카운터 추가 루프 시도). 다음 세션에서도 같은 패턴 의심: 같은 정보가 N 곳에 표현되면 race.
2. ⭐⭐⭐ **enum match exhaustiveness** — 새 mode 추가 시 컴파일러가 모든 호출처 갱신 강제. Option/bool 의 우연 조합보다 압도적으로 안전.
3. ⭐⭐ **시점 의존성 (lazy create)** — 첫 RTP 시점의 publisher 평가 결과를 영구화하면 race. 시점 1회 결정 후 불변 박는 게 정답.
4. ⭐⭐ **"단일 값 보고 분기" 원칙** — 부장님 일침. 중간 조건 많으면 자료구조 문제. 코드 가독성 문제 아니라 자료구조 설계 문제.
5. ⭐ **edit_file 의 atomic 동작** — 두 edit 분리해서 진행 시 한 매칭 실패하면 둘 다 rollback. 한국어 인코딩 매칭 risk 있는 chunk 는 단일 edit 로.

---

## 다음 세션 즉시 시작 가이드

1. **먼저 읽기**: `SESSION_INDEX.md` → 본 파일 (`20260430c_subscribe_mode_redesign.md`)
2. **첫 행동**:
   - half-duplex PTT 시험 (위 ★ 점검표 1번)
   - SFU 재기동 상태 확인 (`oxsfud.log.*` 마지막 entry)
   - QA UI 또는 데모 voice_radio 페이지 사용
3. **회귀 의심 시**: ViaSlot 분기 (subscriber_stream.rs::forward line ~310) 직접 점검 + agg-log 확인
4. **부장님 결재 대기 항목**: PROJECT_MASTER 갱신 제안 (위 섹션)

---

*author: kodeholic (powered by Claude)*
