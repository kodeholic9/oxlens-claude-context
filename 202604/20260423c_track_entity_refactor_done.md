# Track 엔티티 리팩터 Step T1~T3 완료

**날짜**: 2026-04-23 야간 ~ 2026-04-24 새벽
**세션 파일 접두사**: `20260423c_` (scope rev.2 세션 = `20260423`, 설계서 = `20260423b`)
**작업 범위**: Track 엔티티 리팩터 Step T1 / T2 / T3
**설계서**: `context/design/20260423b_track_entity_refactor_design.md`
**버전**: v0.6.24 (기존) — v0.6.25 승격은 T4~T7 + 종합 검증 후로 연기

---

## 0. 배경과 맥락

4/22 자료구조 분석 세션에서 도출된 관찰 #7 "트랙 다중성 미표현" 4 건 중, 다음 2 건을 Track 단위 자원 이주로 해소한다.

1. `PublishContext.rtp_cache` 가 publisher 당 1 개 링버퍼 → camera + screen 동시 publish 시 seq 공간 충돌 위험
2. `PublishContext.simulcast_video_ssrc` 가 publisher 당 1 개 AtomicU32 → multi-video-track 에서 virtual SSRC 부족

동시에 성능 발굴 B ("`tracks.lock()` 선형 탐색") 도 TrackIndex RCU 로 통합 처리.

본 세션은 설계서 §7.1~§7.3 를 cargo test 게이트 단위로 순차 구현. §7.4~§7.7 (T4~T7) 은 미착수.

---

## 1. Step T1 — Track 내부 필드 atomic 전환 + TrackSnapshot DTO (완료)

### 변경 내용

`crates/oxsfud/src/room/participant.rs` 의 `Track` struct 재정의.

| 필드 | 이전 타입 | 신규 타입 | 근거 |
|---|---|---|---|
| `muted` | `bool` | `AtomicBool` | MUTE_UPDATE 중빈도, RCU 복제 낭비 (결정 1) |
| `duplex` | `DuplexMode` | `AtomicU8` (Full=0, Half=1) | SWITCH_DUPLEX 저빈도, 동일 원칙 |
| `rid` | `Option<String>` | `ArcSwap<Option<Arc<str>>>` | promote ("l" 승격) 드뭄, 핫패스 독자 lock-free |

- `#[derive(Debug, Clone)]` 제거 — Mutex/Atomic 포함으로 Clone 불가
- `TrackSnapshot` DTO 신규 — admin / zombie reaper / get_tracks() 경로용 값 타입
- `DuplexMode::{to_u8, from_u8}` 헬퍼 추가
- atomic helpers: `muted_load/store`, `duplex_load/store`, `rid_load/store/rid_store_str`, `snapshot()`

### 치환 범위 (14 파일)

- **핵심 5 파일**: `participant.rs` (struct 재정의), `peer.rs` (add_track_full 분해), `ingress.rs`, `ingress_subscribe.rs` (rid/duplex 직접 접근), `track_ops.rs` (get_tracks 소비)
- **보조 9 파일**: `floor_ops.rs`, `helpers.rs`, `room_ops.rs`, `admin.rs`, `datachannel/mod.rs`, `floor_broadcast.rs`, `tasks.rs`, `pli.rs`, `egress.rs`

주요 치환 패턴:
- `t.muted` → `t.muted_load()` / `t.muted_store(b)`
- `t.duplex == X` → `t.duplex_load() == X`
- `t.rid.as_deref()` → `t.rid_load().as_deref()` (Arc<str> 반환 + 임시변수 바인딩 필요 — 2개 사이트에서 lifetime 이슈 수정)
- `peer.get_tracks()` → `Vec<TrackSnapshot>` 반환. 호출처 그대로 동작 (Clone 가능)

### 부장님 불만 발생 지점 (교훈)

최초 제출에서 `ingress.rs` / `ingress_subscribe.rs` / `floor_ops.rs` 의 `rid` / `duplex` 직접 접근을 grep 누락. cargo check 에서 에러 연쇄 → "더 망가지고 있다" 지적. T1 착수 전 grep 을 정확히 했어야 함.

최종 수정 후 **cargo test 163/163 pass**.

---

## 2. Step T2 — TrackIndex 도입 + Peer.tracks RCU (완료)

### 변경 내용

`crates/oxsfud/src/room/peer.rs`.

```rust
pub struct TrackIndex {
    pub by_ssrc: HashMap<u32, Arc<Track>>,  // O(1) 조회
    pub ordered: Vec<Arc<Track>>,            // admin/진단 순서 보존
}

pub struct Peer {
    pub tracks: ArcSwap<TrackIndex>,   // 이전: Mutex<Vec<Track>>
    ...
}
```

- `add_track_full` / `remove_track` / `switch_track_duplex`: RCU write 경로 (`load_full()` → 새 Index 생성 → `store`)
- `set_track_muted`: Track atomic 직접 변경, RCU 생략 (muted 바꿀 때마다 Index 복제 낭비)
- 공개 API 재조정:
  - `get_tracks() -> Vec<TrackSnapshot>` (Clone 가능 DTO)
  - `find_track(ssrc: u32) -> Option<Arc<Track>>` 신규 (핫패스)
  - `first_track_of_kind(kind: TrackKind) -> Option<Arc<Track>>` 신규 (egress 대표 트랙)
  - `has_half_duplex() -> bool` 신규

### 치환 범위 (3 파일)

- **track_ops.rs**: `tracks.retain()` → ssrc 수집 + `remove_track` 루프 2 건. `tracks.lock().iter().find(|t| t.ssrc == X)` 5 건 → `peer.find_track(X)`. len() 1 건 → `tracks.load().len()`.
- **datachannel/mod.rs L554**: `tracks.lock().iter().any(|t| t.duplex_load() == Half)` → `peer.has_half_duplex()`.
- **floor_ops.rs L55**: 동일 → `peer.has_half_duplex()`.

unused import 2 건 제거: `floor_ops.rs` / `datachannel/mod.rs` 의 `use DuplexMode`.

**cargo check warning 0 + test 163/163 pass**.

### 주의사항

`ingress_mbcp.rs` 의 `sender.endpoint.tracks` 는 dead code (파일이 `mod.rs` 에 미등록). T2 범위 밖으로 연기. PROJECT_MASTER 의 "ingress_mbcp.rs dead code cleanup" 별도 스텝.

---

## 3. Step T3 — per-track 자원 이주 (rtp_cache / virtual_ssrc) (완료)

### Phase A — participant.rs: Track 확장

```rust
pub struct Track {
    ...
    // === T3 per-track 자원 ===
    pub rtp_cache:    Option<Mutex<RtpCache>>,  // video Some, audio None (메모리 절약)
    pub virtual_ssrc: AtomicU32,                 // 0 = unassigned, CAS lazy
}

impl Track {
    pub fn new(...) -> Self {
        let rtp_cache = if matches!(kind, TrackKind::Video) {
            Some(Mutex::new(RtpCache::new()))
        } else { None };
        Self { ..., rtp_cache, virtual_ssrc: AtomicU32::new(0) }
    }

    pub fn ensure_virtual_ssrc(&self) -> u32 {
        // CAS lazy random nonzero (기존 `rand_u32_nonzero()` 재사용)
    }
}
```

### Phase B — peer.rs + participant.rs: PublishContext 슬림화 + shim

**peer.rs**:
- `PublishContext::rtp_cache` 필드 제거
- `PublishContext::simulcast_video_ssrc` 필드 제거
- `PublishContext::new()` 초기화 2 줄 제거
- **신규 helper**: `Peer::simulcast_video_ssrc() -> u32` (load-only, first video track 의 virtual_ssrc.load, unwrap_or(0))
- 테스트 `publish_context_new_smoke` 의 simulcast_video_ssrc assertion 제거

**participant.rs**:
- `RoomMember::ensure_simulcast_video_ssrc()` 내부 교체:
  ```rust
  self.peer.first_track_of_kind(TrackKind::Video)
      .map(|t| t.ensure_virtual_ssrc())
      .unwrap_or(0)
  ```
- **신규 shim**: `RoomMember::simulcast_video_ssrc() -> u32` (load-only, `peer.simulcast_video_ssrc()` 위임)
- 테스트 `room_member_ensure_simulcast_video_ssrc_delegates_to_peer` 재작성: track 등록 후 호출 + Track.virtual_ssrc 로 저장 확인
- 구 위치 주석 2 건 (L923-924, L974-977) T3 재이주 반영

### Phase C — 외부 호출처 치환 (5 건)

| # | 파일 | 라인 | 변경 |
|---|------|------|------|
| 1 | `room.rs` | 210 | `find_publisher_by_vssrc` 의 `p.peer.publish.simulcast_video_ssrc.load(...) == vssrc` → `p.peer.tracks.load().iter().any(|t| t.virtual_ssrc.load(...) == vssrc)` (multi-video-track 지원) |
| 2 | `room_ops.rs` | 275 | `p.peer.publish.simulcast_video_ssrc.load(...)` → `p.peer.simulcast_video_ssrc()` (load-only, leave 경로에서 새 할당 방지) |
| 3 | `track_ops.rs` | 386 | 동일 패턴, remove 경로 |
| 4 | `ingress.rs` | 311 | cache store: `sender.peer.publish.rtp_cache.lock()` → `sender.peer.find_track(rtp_hdr.ssrc).and_then(|t| t.rtp_cache.as_ref())` 경로. stream_kind==Video 가드로 Track 존재 확정 (resolve_stream_kind → register_and_notify_stream → collect_rtp_stats 순서 보장) |
| 5 | `ingress_subscribe.rs` | 647 | NACK RTX cache read: `publisher.peer.publish.rtp_cache.lock()` → `publisher.peer.find_track(lookup_ssrc).as_ref().and_then(|t| t.rtp_cache.as_ref())` 경로. rtx_ssrc match 로 video 확정. |

추가: `room_ops.rs:5` unused import `use std::sync::atomic::Ordering;` 제거 (다른 용도 없음).

### 최종 결과

- **cargo check**: warning 0
- **cargo test**: **163/163 pass**
- **PublishContext 슬림화**: PC pair-scope 자원만 남음 (`stream_map`, `recv_stats`, `twcc_recorder`, `pli_state`, `pli_burst_handle`, `last_*_ms`, `rtx_seq`, `dc` 등)
- **호환 API 불변**: `RoomMember::ensure_simulcast_video_ssrc()`, `Peer::find_track()`, `next_rtx_seq()` 등 시그니처 그대로. 내부만 Track 경로 이주.

---

## 4. 설계 원칙 재확인 (본 리팩터에서 확정된 것)

### scope = 타입 위치로 표현 (설계서 §3.1)

| scope | 담는 타입 | 자원 예 |
|---|---|---|
| user | `Peer` | 2PC MediaSession, pub/sub_rooms, last_seen, phase |
| PC pair | `PublishContext` / `SubscribeContext` | stream_map, recv_stats, twcc, pli_state, send_stats, layers (T5 예정) |
| **track** (T3 신규) | `Track` | **rtp_cache, virtual_ssrc** |
| room member | `RoomMember` | room_id, role, sub_stats |
| room | `Room` | floor, rewriter, participants |

### Track 1등 시민화

- Track = SSRC 단위 1 등 시민. 조회 키 = `ssrc` (O(1) HashMap lookup via TrackIndex)
- `#[derive(Clone)]` 포기 — Mutex/Atomic 자연 소유. 값 복사는 `TrackSnapshot` DTO
- RCU (ArcSwap) = Track 추가/제거 드뭄 + 조회 핫패스. DashMap 은 기각 (결정 9.2)
- atomic 가변 (muted/duplex/rid/virtual_ssrc) + Mutex 복잡 가변 (rtp_cache) 혼합 전략

### 이름 vs 실제 위치 구분

`virtual_ssrc` 3 scope 혼재 (설계서 §12.1):
1. `Track.virtual_ssrc` (T3 신규) — track scope, CAS lazy random
2. `PttRewriter.virtual_ssrc` — room×kind, 상수 (`PTT_AUDIO_SSRC` / `PTT_VIDEO_SSRC`)
3. `SimulcastRewriter.virtual_ssrc` — subscriber×publisher×track, Track.virtual_ssrc 복사본

하나의 용어가 세 곳에 있지만 scope 가 다름. 타 세션에서 참조 시 주의.

---

## 5. 오늘의 지침 (memory 후보)

### 지침 1 — grep 누락은 치명적, T1 패턴 재발 금지

T1 최초 제출에서 `ingress.rs` / `ingress_subscribe.rs` / `floor_ops.rs` 의 rid/duplex 직접 접근 grep 누락 → cargo check 에러 연쇄 → 부장님 "더 망가지고 있다" 불만. 이미 T2 에서 교훈 확정. **치환 리팩터는 구조 변경 전 관련 field 의 전수 grep 이 첫 작업이며, 결과를 제출 매핑 표에 그대로 반영한다.**

### 지침 2 — Filesystem MCP 타임아웃 시 상황 기록 후 재시작 요청

T3 중간에 Filesystem MCP 가 2 회 연속 4 분 타임아웃. 세션 상태 (Phase A 완료 / 매핑 표 12 건 / 미치환 5 건) 를 메시지로 남기고 부장님께 Claude Desktop 재시작 요청. 복귀 시 그대로 이어서 진행 가능. **"진행 불가" 를 묵고 있지 말고 명시적으로 재시작 요청.**

### 지침 3 — `ensure_*` (할당) vs load-only 명확히 구분

`ensure_simulcast_video_ssrc()` 는 side effect (최초 할당) 발생. leave / remove / find 경로에서 무심코 호출하면 "leaving 시점에 새 SSRC 할당" 이라는 무의미한 연산 발생. **별도 `simulcast_video_ssrc()` load-only helper 를 Peer 와 RoomMember 양쪽에 제공, 호출처는 의도에 따라 선택.** 의도가 코드에 드러나면 다른 경로 리팩터 시 혼동 방지.

### 지침 4 — 전체 세션 grep 제안 시 파이프 충돌 주의

`grep -v '//'` 가 파일 경로 `crates/oxsfud/src//` 와 충돌해서 모든 라인이 필터링됨 (grep 결과 빈 문자열 반환). **파이프 필터는 제가 결과 받아서 메시지 내에서 처리하고, 부장님께 드리는 쉘 명령은 최소한으로.** `| grep -v` 는 빼고 raw 결과 받는다.

### 지침 5 — 이전 세션 완료 분을 현 세션에서 중복 실행하지 않는다

MCP 타임아웃 복구 후 grep 결과에서 peer.rs 의 `Peer::simulcast_video_ssrc()` helper 와 participant.rs 의 `RoomMember::ensure_simulcast_video_ssrc()` 내부 교체가 **이미 되어 있는 것** 발견. 타임아웃 전/중에 부장님 또는 제가 진행해둔 작업이 있을 수 있으므로 **grep 결과를 먼저 확인하여 실제 미치환 호출처만 처리.** "계획 표대로 전부 실행" 이 아니라 "현재 상태 vs 목표 상태의 차분만 적용".

---

## 6. 오늘의 기각 후보

없음. 설계서 §9 의 기각 후보 (전면 RCU / DashMap Track / Audio 필수 rtp_cache / Peer.tracks 를 Room 으로 / Arc 아닌 Box·raw) 는 T1~T3 진행 중에 재등장하지 않음.

---

## 7. 남은 Step (T4~T7, 이 세션 외)

설계서 §7.4~§7.7. **부장님 명시 전까지 Claude 가 먼저 제안하지 않음** (memory 규칙 관련 원칙 적용).

- T4: `rooms_snapshot()` 핫패스 → `pub_rooms` (순회 축 변경, Phase 1 동작 동일)
- T5: `layers` 키 `(publisher_user_id, RoomId)` → `(track_ssrc, RoomId)` + `SubscribeLayerEntry.publisher_user_id` 보조 필드
- T6: `recv_stats` / `send_stats` / `stalled_tracker` DashMap 전환 (성능 발굴 G)
- T7: cleanup + 호환 shim 재검토 + clippy

T4~T7 완료 시 v0.6.25 승격 및 종합 검증 (10 시나리오 smoke, Claude in Chrome).

---

## 8. 관련 파일 인덱스

### 세션

- `context/202604/20260422_peer_datastruct_analysis.md` — 4/22 자료구조 분석 (관찰 #7 출처)
- `context/202604/20260423_scope_model_step1_through_7_done.md` — Scope rev.2 Step 1~7
- `context/202604/20260423c_track_entity_refactor_done.md` — **본 세션** (T1~T3)

### 설계

- `context/design/20260423b_track_entity_refactor_design.md` — 본 리팩터 설계 (15 섹션, 15 KB)
- `context/design/20260423_scope_model_design.md` — Scope rev.2 (T4 순회 축 참조)

### 주요 구현 파일

- `crates/oxsfud/src/room/participant.rs` — Track struct 재정의 (§5.1)
- `crates/oxsfud/src/room/peer.rs` — TrackIndex + RCU (§5.2) + PublishContext 슬림화 (§5.4)
- `crates/oxsfud/src/transport/udp/ingress.rs` — cache store 경로 치환 (T3)
- `crates/oxsfud/src/transport/udp/ingress_subscribe.rs` — NACK cache read 경로 치환 (T3)
- `crates/oxsfud/src/signaling/handler/{track_ops, room_ops}.rs` — simulcast_video_ssrc load-only 치환

---

*author: kodeholic (powered by Claude)*
