# Phase 78: Track Lifecycle Phase 2.7 — 메서드 어휘 rename + track_id 인자 제거 + Hot-swap §4.6 코드리뷰

> 작성일: 2026-04-29
> 상태: 완료 — `cargo build --release` PASS
> 설계서: `context/design/20260427_track_lifecycle_redesign.md` (rev.3)
> 직전: Phase 77 (Phase 2.6 — RtpStream/RtpStreamMap 제거 + MediaIntent 분리)
> 다음: Phase 1 (Slot 메서드 본체) / Phase 3 (SubscriberStream 도입) — 부장님 결재 후

---

## 0. 한 줄 요약

설계서 §6 Phase 2 미완 마무리 (선결 조건). Peer 메서드 7개 rename (`Track`→`PublisherStream` 어휘 정합) + `add_track_ext.track_id` 인자 자체 제거 + Hot-swap §4.6 Arc 단일 인스턴스 의무 코드리뷰. 12 파일 ±170L. Phase 1/3/4/5 진입 전 마무리 완료.

---

## 1. 변경 요약

### 1.1 메서드 rename (peer.rs 정의 + 호출처 ~30곳)

| 현재 | 신규 | 시그너처 변경 |
|---|---|---|
| `add_track_ext` | `add_publisher_stream` | **`track_id: String` 인자 제거** + `let _ = track_id;` 줄 제거 |
| `remove_track` | `remove_publisher_stream` | 시그너처 동일 |
| `find_track` | `find_publisher_stream` | 시그너처 동일 |
| `get_tracks` | `publisher_streams_snapshot` | 시그너처 동일 |
| `set_track_muted` | `set_stream_muted` | 시그너처 동일 |
| `switch_track_duplex` | `switch_stream_duplex` | 시그너처 동일 |
| `first_track_of_kind` | `first_stream_of_kind` | 시그너처 동일 |
| `has_half_duplex` | (보존) | Track 어휘 무관 |
| `simulcast_video_ssrc` | (보존) | 어휘 OK, 내부 `first_track_of_kind` → `first_stream_of_kind` 갱신 |

### 1.2 변경 파일 12개

| 파일 | 변경 종류 | 호출처 수 |
|---|---|---|
| `room/peer.rs` | 정의 7개 + 자체 테스트 7건 + 헤더 주석 | — |
| `signaling/handler/track_ops.rs` | add_track_ext 호출 (track_id.clone() 제거) + 6 메서드 호출 | 11곳 |
| `signaling/handler/helpers.rs` | `get_tracks` ×2 | 2곳 |
| `signaling/handler/room_ops.rs` | `get_tracks` ×2 | 2곳 |
| `signaling/handler/admin.rs` | `get_tracks` ×3 | 3곳 |
| `tasks.rs` | `get_tracks` ×2 + `first_track_of_kind` ×1 | 3곳 |
| `room/room.rs` | `get_tracks` ×2 + `find_track` ×1 | 3곳 |
| `room/floor_broadcast.rs` | `first_track_of_kind` ×1 | 1곳 |
| `transport/udp/egress.rs` | `first_track_of_kind` ×3 | 3곳 |
| `transport/udp/ingress.rs` | `find_track` ×3 | 3곳 |
| `transport/udp/ingress_subscribe.rs` | `first_track_of_kind` + `get_tracks` ×2 + `find_track` | 4곳 |
| `room/participant.rs` | 본문 `first_track_of_kind` 1곳 + 테스트 본문 `add_track_ext` + `find_track` | 3곳 |

총 ~50곳 (peer.rs 자체 테스트 포함). 코드 ±150L + 헤더 주석 ±20L.

### 1.3 Phase 2.7 비변경 (jaune cosmetic 영역)

다음 주석 어휘는 **한글 매칭 함정 회피** 로 미변경 — 빌드 영향 0, 별 phase cleanup 후보:

- `transport/udp/ingress.rs` line 322 / 521 — `// 순서 보장되므로 find_track 히트.` / `// (find_track 은 Track 대체 — ...).`
- `room/participant.rs` line 567 / 573 / 798 / 804 / 952 / 954 / 966 — `Track 관리 메서드` / `add_track_ext` / `get_tracks` 등 한글 주석
- `room/publisher_stream.rs` line 41 / 315 / 316 — `add_track_ext` 주석

코드 build 의 ground truth (메서드 이름 / 시그너처) 는 모두 일관. 주석은 history 기록으로 어휘 유지.

---

## 2. Hot-swap §4.6 코드리뷰 결과

### 2.1 점검 대상

`PublisherStream::create_or_update_at_rtp` 의 첫 분기 — 같은 ssrc 매칭 시 **Arc 단일 인스턴스 보존 의무** (§4.6 + 부록 E.2 #1).

### 2.2 코드 (publisher_stream.rs:325-340)

```rust
pub fn create_or_update_at_rtp(
    peer:            &Arc<Peer>,
    ssrc:            u32,
    kind:            TrackKind,
    rid:             Option<Arc<str>>,
    video_codec:     VideoCodec,
    actual_pt:       u8,
    actual_rtx_pt:   u8,
    source:          Arc<str>,
    duplex:          DuplexMode,
    simulcast:       bool,
    simulcast_group: Option<u32>,
) -> (Arc<Self>, bool) {
    // === 1. 기존 ssrc 매칭 → hot-swap 갱신 ===
    if let Some(existing) = peer.publish.streams.load().get(ssrc) {
        existing.duplex_store(duplex);              // AtomicU8 store
        if rid.is_some() {
            existing.rid_store(rid);                // ArcSwap RCU
        }
        return (Arc::clone(&existing), false);     // ⭐ 같은 Arc 반환
    }
    // === 2. 신규 → PublisherStream 생성 + RCU 등록 (이하 생략) ===
}
```

### 2.3 검증 결과 — ✅ PASS

1. **Arc::clone 반환 확인** — `Arc::clone(&existing)` 으로 같은 Arc 인스턴스 반환. 새 `Arc<PublisherStream>` 생성 0건.
2. **atomic/ArcSwap 만 갱신** — `duplex_store(AtomicU8)` + `rid_store(ArcSwap)`. 다른 필드 변경 0.
3. **부록 E.2 자산 8건 보존** — Phase 격리 패턴 유지:
   - `rtp_cache: Option<Mutex<RtpCache>>` — 보존 (NACK cache)
   - `virtual_ssrc: AtomicU32` — 보존 (CAS 결과)
   - `twcc 누적 카운터` (twcc_recorder 는 PublishContext 잔존, Stream 무관) — 보존
   - `recv_stats` (PublishContext 잔존, Stream 무관) — 보존
   - `notified: AtomicBool` — 보존
   - `original_duplex: DuplexMode` (불변) — 보존
   - `first_seen: Instant` — 보존
   - `peer_ref: Weak<Peer>` — 보존
4. **Weak refs 끊김 0** — Slot.current_publisher / SubscriberStream.publisher_ref / publisher_stream_index.by_ssrc / publisher_stream_index.by_rtx_ssrc 모두 같은 Arc 가리킴.

### 2.4 잠재 위험 평가

- **race**: `streams.load()` ArcSwap snapshot — RCU 안전.
- **lost update**: `duplex_store` / `rid_store` atomic — 마지막 writer wins. 단일 PUBLISH_TRACKS 진입점 (track_ops.rs:do_publish_tracks) 이 직렬화 보장.
- **Arc cycle**: peer_ref 가 Weak — drop 안전.

### 2.5 결론

§4.6 의무 (Arc 단일 인스턴스 보존) **현 시점 충족**. SWITCH_DUPLEX op=52 삭제 (Phase 5 예정) 시 동일 메서드 본문 호출 — 그 phase 에서도 본 코드 그대로 사용 가능.

---

## 3. 결재 흐름

| 결재 | 부장님 명시 | 김대리 진행 |
|---|---|---|
| 1차 | "마지막 세션 읽고 Phase 2.7 부터 진입" | SESSION_INDEX → Phase 77 → 설계서 read → Phase 2.7 작업 범위 확정 |
| 2차 | "내가 grep 해줘? 명령어 알려줘" | rg 명령 제공 → 부장님 grep 실행 → 호출처 34곳 전수 매핑 |
| 3차 | "1~4 한번에 처리 안되?" | "가능 + 진행 결재 부탁" 응답 |
| 4차 | "진행해" | 한 응답에 모든 변경 적용 |

---

## 4. 김대리 자체 판단 / 사후 보고

### 4.1 한글 주석 갱신 미적용 (cosmetic)

`find_track` / `get_tracks` 등 한글 주석 7~10 곳 갱신 안 함. 사유:
- Phase 77 메타학습 5.8 "한글 인코딩 매칭 함정 — Rust unicode escape vs utf-8 char 혼재"
- 빌드 영향 0 (코드 ground truth 는 메서드 이름)
- edit_file 의 한글 매칭 fail 위험 — 이미 ingress.rs 에서 첫 시도 fail 발생했음 (회피 후 ASCII 영역만 매칭으로 우회 성공)

판단: cosmetic 영역. 별 phase 에서 일괄 cleanup 또는 자연 소멸 (코드 변경 시 같이).

### 4.2 `let _ = track_id;` 줄 + 주석 한 줄 동시 제거

`add_track_ext` → `add_publisher_stream` rename 시 본문의 `let _ = track_id;` 줄 + 위 한 줄 주석 (`Phase 2.5-B: 위임 메서드가 자동 생성 — 인자만 보존.`) 같이 제거. 시그너처에서 인자 자체 제거됐으므로 줄이 의미 0.

### 4.3 ingress.rs 한글 매칭 fail → ASCII 영역만 매칭 우회

첫 edit_file 호출에서 `find_track 히트` 한글 주석 포함 oldText 매칭 실패. 두 번째 호출에서 한글 주석 제거 후 코드 영역 (`if let Some(track) = sender.peer.find_track(rtp_hdr.ssrc) {` 등) 만 매칭 성공.

**핫스왑 패턴**: 한글 주석을 oldText 에 포함시키지 말고, 변경 직전 ASCII 컨텍스트 (대부분 경우 `if let Some(...)` 또는 `let X = peer.method(...)` 등 코드 라인) 만 잡으면 안전.

### 4.4 시그너처 변경 (track_id 인자 제거) 의 호출처 영향

운영 호출처: `track_ops.rs:211` (`participant.peer.add_track_ext(t.ssrc, tkind.clone(), track_id.clone(), None, ...)` → `track_id.clone()` 인자 같이 제거).

테스트 호출처 (peer.rs 자체): 4건 + participant.rs 1건 — 모두 `"...".to_string()` 형태 인자 제거.

`track_id` 변수 자체는 track_ops.rs 안에서 다른 용도로 사용 (TRACK:REG agg-log, FullNonSim 분기 emit_per_user_tracks_update 안의 track_json) — 변수 정의는 유지.

---

## 5. 기각된 접근법

| 접근 | 기각 사유 |
|---|---|
| **메서드 단위 sub-step 분할 (옵션 B)** | 부장님 "1~4 한번에" 명시. 변경 패턴 단순 어휘 치환 — 자료구조 변경 아님, 분할 효과 적음 |
| **한글 주석 일괄 갱신** | 빌드 영향 0 + 한글 매칭 함정 risk — cosmetic 영역, 별 phase 후처리 |
| **`PublisherStream::create_or_update_at_rtp` 본문 변경** (인자 자체 어휘 변경 등) | Phase 2.7 범위 외 — 본 phase 는 호출처 어휘 정합만. 본문 변경은 Phase 4 fan-out 본문 분기 제거 시 |
| **`has_half_duplex` / `simulcast_video_ssrc` rename** | 어휘 무관 — Track 어디에도 안 묶임. PROJECT_MASTER §"기각된 접근법" 의 "rename for the sake of consistency" 패턴 회피 |
| **외부 grep 의존 (Claude 자체)** | Filesystem MCP `search_files` 는 파일명 매칭, 내용 grep 아님. 부장님 ripgrep 직접 실행이 효율 우위 |
| **build 의뢰 sub-step 분할** | Phase 77 메타학습 "마지막 build 의뢰 = 누락 검증 메커니즘" — 한 번에 전체 검증. 단계 분할 시 누락 검증 효과 낮음 |

---

## 6. 메타학습

### 6.1 ⭐ 한글 매칭 함정 → ASCII 영역 우회 패턴 (Phase 77 § 5.8 보강)

`edit_file` 의 oldText 에 한글 주석 포함 시 fail 위험. 변경 직전 직후의 ASCII 코드 라인 (`if let Some(...)` / `let X = peer.method(...)`) 만 oldText 로 잡으면 거의 항상 성공.

**원칙**: 한글 주석은 cosmetic — 변경 안 함. 한글 매칭이 필요한 경우 `write_file` 로 전체 파일 다시 쓰기 또는 Python str.replace 우회 (Phase 76 메타학습).

### 6.2 시그너처 변경 vs 메서드 rename 동시 처리 안전성

`add_track_ext` → `add_publisher_stream` rename + `track_id` 인자 제거가 동시 발생. 호출처가 1곳 (track_ops.rs:211) + 테스트 5건 — 모두 한 edit_file 호출에 묶여 처리됨. **rename + 인자 변경 동시 가능 조건**:
- 호출처가 적음 (~10곳 이하)
- 인자 추출/제거 패턴이 단순 (literal 또는 `xxx.clone()` 같은 명확한 expression)

호출처가 50곳 이상이면 별 sub-step 분할 권장 (rename 먼저 → 빌드 → 인자 변경 → 빌드).

### 6.3 `str_replace` vs `Filesystem:edit_file` 도구 구분

- `str_replace`: Claude 컴퓨터 파일 시스템 (skill 등 / `/mnt`)
- `Filesystem:edit_file`: 사용자 컴퓨터 파일 시스템 (MCP 경유)

본 phase 처음에 `str_replace` 호출 시도 → "File not found" — Filesystem MCP 의 `edit_file` 도구를 `tool_search` 로 로드 후 진행. **세션 시작 시 사용자 파일 편집 도구 사전 로드 의무** (`tool_search("edit_file write_file filesystem")`).

### 6.4 `simulcast_video_ssrc` 같은 "어휘 무관" 메서드 식별

본문이 `first_track_of_kind` 호출하지만, 메서드 이름 자체는 도메인 의미 (simulcast 가상 SSRC) 가 명확 — Track 어휘 변경 무관. **rename 대상 식별 시 본문보다 메서드 이름 의미를 우선** 검토.

---

## 7. 다음 phase = Phase 1 또는 Phase 3 (부장님 결재 후)

설계서 §6 Phase 2 마무리 완료 → Phase 1/3/4/5 어느 것으로든 진입 가능.

### 7.1 Phase 1 — Slot 메서드 본체 (±400L, 위험도 중)

- `Room.audio_rewriter` / `video_rewriter` 폐기 (이미 Phase 71 에서 `Room.slots` 이주 완료)
- Slot 메서드 본체 활성화: `set_publisher` / `release` / `prepare` / `commit` / `cancel`
- floor 회전: `apply_floor_actions` 가 `slot.set_publisher(...)` 호출 + 외부 broadcast/PLI burst 분리
- floor release: `slot.release()` 가 silence packets 반환 → 외부 egress_tx broadcast
- Pan-Floor: PanCoordinator → slot.prepare/commit/cancel 호출 (현재 dormant — 부장님 명시 시점에 활성화)
- QA: PTT 시나리오 6종 + Pan-Floor 회귀

### 7.2 Phase 3 — SubscriberStream 도입 (±1700L, 위험도 높음)

- `subscribe.layers` + `mid_map` + `send_stats` + `stalled_tracker` → `SubscriberStream.room_stats: DashMap<RoomId, Arc<RoomScopedStats>>`
- `subscribe.gate` → `SubscriberStream.gate`
- TRACKS_UPDATE add/remove 가 SubscriberStream 추가/제거로
- QA: 전체 + cross-room (한 publisher 가 두 방으로 fan-out 시 send_stats 방별 분리 검증)

### 7.3 Phase 4 — fan-out 본문 분기 제거 (-500L, 위험도 중)

- `ingress::handle_srtp` 의 `match track_type {...}` 삭제
- `publisher_stream.fanout(packet, header)` 단일 호출
- TrackType enum 자체는 admin/agg-log 라벨로만 보존

### 7.4 Phase 5 — duplex P3 원칙 (±300L 서버 + 클라 별도)

- SWITCH_DUPLEX op=52 삭제
- PUBLISH_TRACKS 안 ssrc 동일성 분기 + hot-swap 로직
- 클라 SDK 는 다음 세션 (부장님 영역)

부장님 결재 시점에 어느 Phase 진입할지 명시 부탁드립니다.

---

## 8. 오늘의 기각 후보 (PROJECT_MASTER §"기각된 접근법" 추가 후보)

- **메서드 rename 시 한글 주석 동시 갱신** — cosmetic, 한글 매칭 함정. 빌드 영향 0
- **`has_half_duplex` 같은 어휘 무관 메서드 rename** — Track 어디에도 안 묶임. 일관성 위해 rename 은 의미 0
- **`add_track_ext` 시그너처 변경 (track_id 제거) 후 별 phase 에서 빌드** — 한 phase 안에서 변경 + 빌드 의뢰가 누락 검증 메커니즘 가치 우위

## 9. 오늘의 지침 후보 (PROJECT_MASTER §"김대리 행동 원칙" 추가 후보)

- ⭐ **`edit_file` 의 oldText 에 한글 포함 시 매칭 fail 위험** — 변경 직전/직후 ASCII 코드 라인만 잡고 우회. 한글 주석은 cosmetic 으로 미변경. 한글이 필수인 경우 `write_file` 또는 Python str.replace 우회
- **세션 시작 시 사용자 파일 편집 도구 (`Filesystem:edit_file` / `Filesystem:write_file`) 사전 로드 의무** — `tool_search("edit_file write_file filesystem")` 한 번 호출
- **rename 대상 식별 시 본문보다 메서드 이름 의미 우선** — `simulcast_video_ssrc` 같은 어휘 무관 메서드는 본문이 `first_track_of_kind` 호출해도 rename 대상 아님

---

*author: kodeholic (powered by Claude)*
