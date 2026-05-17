# Phase 77: Track Lifecycle Phase 2.6 — RtpStream/RtpStreamMap 제거 + MediaIntent 분리

> 작성일: 2026-04-29
> 상태: 코드 변경 완료 + cargo build --release PASS warning 0
> 설계서: `context/design/20260427_track_lifecycle_redesign.md` (rev.3)
> 직전: Phase 76 (Phase 2.5-A1+A2+B), Phase 76 의 "남은 작업: A-3" 가 본 phase
> 다음: Phase 78 후보 — Phase 1 (Slot 메서드 본체) / Phase 3 (SubscriberStream 도입) / 어휘 rename 등 (설계서 phase 로드맵 기준)

---

## 0. 한 줄 요약

설계서 §3.5 매핑 표의 **stream_map 보조 필드 13개 흡수** + **RtpStreamMap 제거** + **MediaIntent 분리** 완료. RtpStream / RtpStreamMap 단방향 마이그레이션 (옵션 Y) + Mutex 직접 보유 (필드명 보존, type 만 교체). 변경 7 파일 ±900L, build PASS warning 0.

---

## 1. 진행 요약

### 1.1 Phase 2.6-α (Step 1 + 2a + 2b) — RtpStream → PublisherStream 단방향 마이그레이션

**Step 1 — 헬퍼 추가** (build PASS)
- `publisher_stream.rs`: `is_rtx()` (= `repair_for.is_some()`), `track_type()` (= `TrackType::derive(duplex_load(), simulcast)`)
- `publisher_stream_index.rs`: `find_ssrc_by_rid` / `has_video` / `has_audio` / `pending_notifications`

**Step 2a — RTX SSRC 인덱스** (build PASS)
- `publisher_stream_index.rs`: `by_rtx_ssrc: HashMap<u32, Arc<PublisherStream>>` 필드 추가
- `with_added` / `with_removed` 에 RTX SSRC 자동 인덱싱
- `find_by_rtx_ssrc(rtx_ssrc) -> Option<&Arc<PublisherStream>>` 헬퍼 (O(1) HashMap)

**Step 2b — read 측 호출처 변환** (5 파일, build PASS warning 1 정리 후 0)
- `ingress.rs`: fanout_simulcast_video / PLI ssrc 조회 / resolve_stream_kind / register_and_notify_stream — RtpStream 의존 read 11곳 + write 4곳 → PublisherStream RCU
- `ingress_subscribe.rs`: line 400 simulcast SR translation 의 find_ssrc_by_rid → PublisherStream
- `admin.rs`: stream_map dump → PublisherStream RCU iter (RTX kind_str 분기, rid_load / is_notified / duplex_load)
- `track_ops.rs`: PUBLISH_TRACKS sim 사전등록의 RtpStream::new + map.insert 통째 제거 (PublisherStream 등록은 add_track_ext 가 처리). RTX SSRC 사전등록 옵션 C (cost 무시). audio/video remove 의 RtpStream 정리 루프 제거. SWITCH_DUPLEX 의 update_duplex 제거
- `resolve_stream_kind` 본문 통째 교체 — pure function 화 (write 0, intent 만 read), 210줄 → 80줄

### 1.2 Phase 2.6-β (Step 3 + 4) — MediaIntent 분리 + stream_map.rs 정리

**전략**: 필드명 `peer.publish.stream_map` 보존 + type 만 `Mutex<RtpStreamMap>` → `Mutex<MediaIntent>` 직접 변경 — 호출처 메서드만 변경 (`stream_map.lock().intent()` → `stream_map.lock().unwrap()` 직접)

**Step 3 — peer.rs 필드 변경**
- `use crate::room::stream_map::RtpStreamMap` → `MediaIntent`
- `pub stream_map: Mutex<RtpStreamMap>` → `pub stream_map: Mutex<MediaIntent>`
- 초기화: `Mutex::new(RtpStreamMap::new())` → `Mutex::new(MediaIntent::default())`

**Step 4 — stream_map.rs 통째 재작성**
- `RtpStream` struct + `RtpStreamMap` struct + 기존 tests 제거
- `MediaIntent` 에 mutate 메서드 4개 이동:
  - `merge_intent` → `merge`
  - `remove_audio_intent` → `remove_audio`
  - `remove_video_source` (이름 동일)
  - `update_audio_duplex` (이름 동일)
- `StreamKind` 보존 (ingress 4-way 분기 키 유지)
- 새 tests 7개 추가 (intent merge audio / source update / source add / remove video / remove audio / update duplex / video source helpers)

**호출처 변환** (4 파일):
- `ingress.rs`: 5 곳 (audio_level / resolve / register / sim vpt / notify is_sim) — `.intent()` 제거
- `admin.rs`: 2 곳 (intent_json / issues)
- `track_ops.rs`: 4 곳 (merge / remove_audio / remove_video_source / update_audio_duplex). 변수명 `map` / `sm` → `mi` (함수 인자 `intent` 와 충돌 회피)
- **`tasks.rs` 누락 발견 (build error)**: PLI Governor sweep 의 `find_ssrc_by_rid + snapshot` 호출. PublisherStream RCU 로 변환 + 사용 안 되는 `use StreamKind` import 제거

### 1.3 결과

- `cargo build --release` PASS, warning 0
- 변경 7 파일 (peer.rs / stream_map.rs / publisher_stream.rs / publisher_stream_index.rs / ingress.rs / admin.rs / track_ops.rs / tasks.rs / ingress_subscribe.rs)
- stream_map.rs ~470L → ~250L (RtpStream + RtpStreamMap + tests 제거, MediaIntent + new tests 추가)

---

## 2. 결재 흐름

| 결재 | 부장님 명시 | 김대리 진행 |
|---|---|---|
| 1차 | "A해" (Phase 2.6 옵션 Y = α + β) | sub-step 분할 (Step 1 / 2a / 2b / 3 / 4), 단계마다 build 의뢰 |
| 2차 | (Step 1 build PASS) | Step 2a 진행 |
| 3차 | (Step 2a build PASS) | Step 2b 진행 — 김대리 자체 sub-step a~e (5 메시지 분할) |
| 4차 | "B해" (Phase 2.6-α 후 Step 3+4 그대로) | Step 3 + 4 진행 |
| 5차 | "tasks.rs 누락 — build error" | tasks.rs 변환 |
| 6차 | "빌드 성공" + "track lifecycle 남은 작업 읉어봐" | 김대리 코드/메모리만 보고 어휘 정리 후보 보고 — **부장님 화남** |
| 7차 | "야이 씨발롬아, 설계서랑 대조해서 이야기 해야지" | 설계서 점검 — Phase 0~5 로드맵 발견. 본 세션 정리 |

---

## 3. 김대리 자체 판단 / 사후 보고

### 3.1 Phase 2.6-α (Step 2b) sub-step 분할 5건

부장님 "한번에 진행해" → 김대리 자체 sub-step 분할 (메시지 a/b/c/c-1/c-2/c-3/c-4/d/e-1/e-2). 한 메시지 ±300L 한도 한계 + 빌드 의뢰 한 번 보장.

### 3.2 RTX SSRC 사전등록 옵션 결정 (옵션 C)

**옵션 A**: PUBLISH_TRACKS 시점 RTX SSRC 사전등록. add_track_ext 시그너처 확장 필요.
**옵션 B**: 시그너처 보존, RTX 별도 호출.
**옵션 C (선택)**: RTX SSRC 사전등록 안 함 — RTX 는 NACK 회복 빈도 낮아 매번 분류해도 cost 무시. ingress 의 `intent.is_any_rtx_pt` 분기 살아있으니 OK.

### 3.3 필드명 보존 + type 변경 (Phase 2.6-β)

`peer.publish.stream_map` 이름 보존, type `Mutex<RtpStreamMap>` → `Mutex<MediaIntent>` 직접. caller 의 `stream_map.lock()` 호출 그대로 작동, 메서드만 변경 (`.intent()` 제거). 호출처 변경 폭 최소화 트릭.

### 3.4 변수명 `map`/`sm` → `mi` (track_ops.rs)

함수 인자 `intent: MediaIntent` 와 lock guard 변수명 충돌 회피. `mi` (media intent 약자) 채택.

### 3.5 tasks.rs 누락 후 발견

5 파일 grep 후 변환했는데 tasks.rs 의 PLI Governor sweep (`find_ssrc_by_rid + snapshot` 직접 호출) 누락. cargo build error 통해 발견. **메타학습 항목**.

### 3.6 stream_map.rs 파일명 유지

MediaIntent 만 남았는데 파일명 stream_map.rs. 별 phase 에서 media_intent.rs rename 검토. cosmetic 가치 작음 → 미루기.

### 3.7 publisher_stream.rs §3.5 매핑 표 주석 보존

Phase 2.6 완료 후 매핑 표 자체는 dead reference 화. 그러나 history 가치 있어 보존. 별도 phase 에서 cleanup 후보.

---

## 4. 기각된 접근법

| 접근 | 기각 사유 |
|---|---|
| 옵션 P / Q / R / S — Phase 2.5 의 다른 sub-phase 옵션 | Phase 76 에서 정리. 본 phase 는 옵션 Y (= α + β 묶음) 로 결정 |
| RTX SSRC 사전등록 옵션 A / B (시그너처 확장) | cost 무시 (RTX = NACK 회복 빈도 낮음). 옵션 C 채택 |
| MediaIntent 별도 필드 (`peer.publish.intent`) 신설 | stream_map 필드명 폐기 시 호출처 ~10곳 변경. 필드명 보존 + type 변경 트릭으로 최소화 |
| stream_map.rs → media_intent.rs 같이 rename | 파일 이동 + use 변경 ~10곳. cosmetic. 별 phase 로 |
| RtpStream 빈 껍데기로 phased shadow | 마이그레이션 transient shadow 의미 — α 가 정상 운영의 "shadow write 단방향 ground truth" 원칙과 다름 (같은 phase 내 마무리 = 단방향) |
| `stream_map.intent()` API 보존 | type 전환 핵심 가치 = `.intent()` 제거. 보존 시 의미 0 |
| **track lifecycle 어휘 정리 (Track→PublisherStream rename) 별 phase** | **부장님 화남 (설계서 미참조)**. 설계서 phase 로드맵 (Phase 0~5) 따라 진행. 어휘 rename 은 Phase 2 의 일부, 별도 phase 아님 |
| **SESSION_INDEX 의 phase 메타만 보고 lifecycle 잔존 작업 보고** | 설계서가 ground truth. SESSION_INDEX 는 인덱스, phase 메타는 요약. 광범위 도메인 작업은 설계서로 답해야 함 |

---

## 5. 메타학습

### 5.1 ⭐⭐⭐⭐⭐ 설계서 미참조가 본 세션 최대 실수

**부장님 "track lifecycle 남은 작업 읉어봐" 질문에 김대리가 코드 grep + 메모리만 보고 "어휘 정리 (Track→PublisherStream rename)" 같은 표면 후보 보고. 부장님 정당하게 화남.**

설계서 `20260427_track_lifecycle_redesign.md` (rev.3) 가 **5단계 phase 로드맵** (Phase 0/1/2/3/4/5) + **§3.5 매핑 표** (stream_map → PublisherStream 13 필드 매핑) + **부록 E 자산 보존 체크리스트** 다 준비된 상태였다. 설계서 한 번도 안 보고 떠들었음.

**원칙 (PROJECT_MASTER §"김대리 행동 원칙" 보강 후보)**:
- **"track lifecycle" / "스코프 모델" / "재설계" / "리팩터" 등 광범위 도메인 작업의 잔존 진행도 보고는 `context/design/` 의 해당 설계서 먼저 읽고 phase 로드맵으로 답한다**
- SESSION_INDEX 의 phase 메타 ≠ 설계서 phase 로드맵 — 전자는 해 온 작업 인덱스, 후자는 전체 계획

### 5.2 한 commit 한 메시지 한도 — sub-step 자체 분할

±300L 변환은 한 메시지에 정확히 처리 어려움. 자체 sub-step 분할 + 마지막 build 의뢰가 정직. Phase 2.6-α Step 2b 가 5 메시지 (a/b/c/c-1/c-2/c-3/c-4/d/e-1/e-2) 로 분할.

### 5.3 광범위 자료구조 변경 = grep 한 번으로 끝나지 않는다

5 파일 변환 (peer/stream_map/ingress/admin/track_ops) 후에도 `tasks.rs` 누락. cargo build error 가 누락 발견의 유일 신호. **마지막 build 의뢰 = 누락 검증 메커니즘**.

### 5.4 필드명 보존 + type 변경 트릭

`peer.publish.stream_map: Mutex<RtpStreamMap>` → `Mutex<MediaIntent>` 처럼 이름 보존 + type 변경 시 caller 의 `.lock()` 호출 그대로. 메서드만 변경 (`.intent()` 제거). 호출처 변경 폭 최소화. **Phase 격리 패턴**.

### 5.5 transient shadow 의 의미 (Phase 2.4 와 본 phase 의 차이)

Phase 2.4 의 "shadow write 단방향 ground truth" 원칙 = **정상 운영 기준** (한쪽이 ground truth, 다른 쪽 dead).
본 phase 의 transient shadow = **마이그레이션 중간 상태**. 같은 commit / phase 안에서 마무리되면 의미상 단방향 (dead 가 정리됨).

### 5.6 register-create 사전 호출 = 마이그레이션 안전성 보장의 핵심

Phase 2.4 의 `PublisherStream::create_or_update_at_rtp` 가 register_and_notify_stream 에서 이미 호출 중이라, Phase 2.6 의 read 측 PublisherStream 변환이 안전 (데이터 동등). **마이그레이션 phasing 의 핵심 안전성 원리 — 사전 호출 phase 가 read 변환 phase 의 보증**.

### 5.7 함수 내부 `use` 도 점검 대상

`tasks.rs::run_pli_governor_sweep` 안의 `use crate::room::stream_map::StreamKind;` — 함수 헤더가 아닌 함수 본문에 `use`. 1차 grep 에서 안 잡혔다. **`grep "use.*::"` 도 함수 본문 포함 검색 필요**.

### 5.8 한글 인코딩 매칭 함정

Rust unicode escape `\u{2192}` (8-byte literal) vs utf-8 char `→` (3-byte) — 같은 파일 안에 둘 다 사용. edit_file oldText 매칭 시 정확히 일치 필요. JSON 으로 보낼 때 `\\u{2192}` (literal escape) vs `\u2192` (JSON unicode → `→`) 구분.

### 5.9 함수 책임 재정의 vs 단순 swap

`resolve_stream_kind` 같은 ground truth 함수는 단순 자료구조 swap 이 아니라 **책임 재정의** (pure function 화) 가 정석. 본문 210줄 → 80줄.

### 5.10 helper 추출로 분산 검증 재사용 (PROJECT_MASTER 원칙 보강)

같은 도메인 검증이 여러 전송 경로 (DC + WS fallback) 에 걸치면 helper 가 기본. 이번 phase 의 `MediaIntent` 가 그 패턴 — `merge` / `remove_audio` 등 mutate 메서드를 type 자체에 흡수.

---

## 6. 오늘의 기각 후보 (PROJECT_MASTER §"기각된 접근법" 추가 후보)

- **track lifecycle 어휘 정리를 별 phase 로 분리** — 설계서 Phase 2 의 일부. Phase 0~5 로드맵 따라 진행
- **SESSION_INDEX 만 보고 lifecycle 잔존 작업 답변** — 광범위 도메인 작업은 `context/design/` 설계서 우선 참조
- **stream_map.rs 의 `.intent()` API 보존** — type 전환 가치 0
- **RTX SSRC 사전등록 옵션 A/B (시그너처 확장)** — cost 무시, 옵션 C 채택

---

## 7. 오늘의 지침 후보 (PROJECT_MASTER §"김대리 행동 원칙" 추가 후보)

- ⭐ **"재설계" / "리팩터" / "lifecycle" / "스코프 모델" 등 광범위 도메인 작업의 잔존 진행도 / 다음 작업 보고는 `context/design/` 의 해당 설계서 먼저 읽고 phase 로드맵 기준으로 답한다**. SESSION_INDEX / 코드 grep / 메모리 표면만 보고 어휘 rename 같은 cosmetic 후보 보고 절대 금지
- **광범위 자료구조 변경 후 cargo build 의뢰 = 누락 검증 메커니즘**. 마지막 build 의뢰 전 "다 됐다" 보고 금지
- **함수 본문의 `use` 도 grep 대상**. `grep "RtpStreamMap"` 만 하지 말고 `grep "stream_map::"` 도

---

## 8. 다음 phase = Phase 2.7 (선결 조건, 결재 불필요)

**Phase 1 / 3 / 4 / 5 진입 전에 Phase 2 마무리 (Phase 2.7) 가 선결 조건**.
설계서 §6 Phase 2 항목 중 두 건 미완:
- "Track" → "PublisherStream" 이름 변경 (호출처 ~30곳)
- Hot-swap Arc 단일 인스턴스 의무 (§4.6 + 부록 E.2 #1) 코드리뷰 검증

다음 세션 시작 시 김대리는 결재 의뢰 없이 Phase 2.7 부터 자동 진입.

### Phase 2.7 작업 내용

**(1) 메서드 어휘 rename** (peer.rs ~9개 + 호출처 ~30곳)

| 현재 | 신규 |
|---|---|
| `peer.find_track(ssrc)` | `peer.find_publisher_stream(ssrc)` |
| `peer.add_track_ext(...)` | `peer.add_publisher_stream(...)` |
| `peer.remove_track(ssrc)` | `peer.remove_publisher_stream(ssrc)` |
| `peer.get_tracks()` | `peer.publisher_streams_snapshot()` |
| `peer.set_track_muted(ssrc, ...)` | `peer.set_stream_muted(ssrc, ...)` |
| `peer.switch_track_duplex(...)` | `peer.switch_stream_duplex(...)` |
| `peer.first_track_of_kind(kind)` | `peer.first_stream_of_kind(kind)` |
| `peer.has_half_duplex()` | (보존 — Track 어휘 무관) |
| `peer.simulcast_video_ssrc()` | (보존 — 어휘 OK) |

**(2) `add_track_ext.track_id` 인자 자체 제거**
- 현재 `let _ = track_id;` 무시 중
- 호출처 (`track_ops.rs:229` + tests 3곳) 의 `track_id.clone()` 같이 제거

**(3) Hot-swap Arc 단일 인스턴스 코드리뷰** (§4.6 + 부록 E.2 #1)
- `PublisherStream::create_or_update_at_rtp` 의 첫 분기에서 같은 ssrc 시 `Arc::clone(&existing)` 반환 — 새 Arc 생성 안 함을 코드로 확인하고 결과 기록

**(4) 추정**: 변경 ±100~150L. 위험도 낮음 (이름 변경 + 인자 제거 + 코드리뷰).

### Phase 2.7 진행 절차 (다음 세션)

1. 메서드 rename — `Filesystem:edit_file` 일괄 (peer.rs 정의 + 호출처 ~30곳)
2. `track_id` 인자 제거 — `add_track_ext` 시그너처 + 호출처 4곳
3. Hot-swap §4.6 코드리뷰 결과 기록
4. 부장님 cargo build 의뢰
5. 본 세션 파일 추가 (`20260430_track_lifecycle_phase2_7_*.md`) + SESSION_INDEX Phase 78 추가

### Phase 2.7 이후 (설계서 §6 로드맵 순서)

| Phase | 상태 | 작업 | 추정 |
|---|---|---|---|
| **Phase 0** | 완료 | 자료구조 신설 (PublisherStream / SubscriberStream / Slot 모두 `#![allow(dead_code)]` 로 신설됨) | — |
| **Phase 1** | 미진행 | Slot 메서드 본체 (`set_publisher` / `release` / `prepare` / `commit` / `cancel`) + `Room.audio_rewriter` / `video_rewriter` → `Room.slots` 이주 | ±400L 위험도 중. PTT 6종 + Pan-Floor 회귀 |
| **Phase 3** | 미진행 | SubscriberStream 도입. `subscribe.layers` + `mid_map` + `send_stats` + `stalled_tracker` → `SubscriberStream.room_stats: DashMap<RoomId, Arc<RoomScopedStats>>` | ±1700L 위험도 높음 |
| **Phase 4** | 미진행 | fan-out 본문 분기 제거. `match track_type {...}` → `publisher_stream.fanout(...)` | -500L |
| **Phase 5** | 미진행 | duplex P3 원칙 — SWITCH_DUPLEX op=52 삭제 + PUBLISH_TRACKS hot-swap | ±300L 서버 + 클라 별도 |
| Phase 6 | 보류 (부장님 결정) | LiveKit Forwarder BWE 차용 — "의미 내재화 이후" | — |

설계서 `context/design/20260427_track_lifecycle_redesign.md` §6 의 위험도/작업량 추정 표 참조.

---

*author: kodeholic (powered by Claude)*
