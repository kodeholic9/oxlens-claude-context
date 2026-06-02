# 작업 지침 — 도메인 어휘 enum types.rs 통합 (원본 제거 + 호출처 일괄 + stream_map 폐기)

> 작성: 김대리 (claude.ai) · 결재: 부장님 (kodeholic) · 구현: 김과장 (Claude Code)
> 파일: `context/claudecode/202606/20260602d_enum_types_consolidation.md`
> 선행: `20260602c`(sub 텔레메트리 트랙 정렬, `b5b9172`) 위에 적층.

---

## §0 의무 점검

1. `git status` — `b5b9172` 까지 적층 확인. **`domain/types.rs` 가 이미 생성돼 있다**(김대리 작성, 5 enum 정의). 단 `mod.rs` 미등록 + 원본과 중복이라 **현재 빌드 안 됨** — 본 작업이 그 중복을 해소해 컴파일 복구한다.
2. baseline 목표: 작업 후 `cargo test -p oxsfud` **211 passed** + oxe2e **4/4**. (현재는 중복 정의라 컴파일 실패가 정상 출발점.)
3. 이 작업은 **enum 정의 위치 이동 + 호출처 use 경로 변경**이다. 로직·동작은 한 줄도 안 바뀐다. 동작이 바뀌면 버그다.

---

## §1 컨텍스트

domain/ 의 작은 파일 파편 정리 흐름에서, **순수 도메인 어휘 enum**(의존 0 / 내부 enum / config 상수뿐, 메서드는 자기 변환·판별만)을 `domain/types.rs` 한곳에 모으기로 결정. domain/ 전수 + 다른 디렉토리(error/datachannel/transport) 조사 결과 대상은 아래 5개로 확정. 다른 디렉토리 enum(LightError/ChannelType/DcepMessage/FloorState/FloorAction/SsrcLookupKind 등)은 전부 모듈·프로토콜 전용이라 제외(옮기면 shotgun surgery).

### 이동 대상 (types.rs 에 이미 정의 완료)

| enum | 원본 | 비고 |
|---|---|---|
| `StreamKind` | `domain/stream_map.rs` | 이 파일은 enum 1개만 남은 파편 → **파일째 폐기** |
| `TrackKind` | `domain/publisher_track.rs` | 도메인 전반 범용 — 호출처 최다 |
| `VideoCodec` | `domain/publisher_track.rs` | config(PT 상수) 의존 동반 |
| `DuplexMode` | `domain/publisher_track.rs` | str/u8 변환만 |
| `TrackType` | `domain/publisher_track.rs` | derive 가 DuplexMode 참조(types 내부) |

> `domain/types.rs` 내용은 이미 작성돼 있으니 **건드리지 말 것**. 본 작업은 원본 제거 + 호출처 정리만.

---

## §2 결정된 사항

1. **5 enum 정의를 원본에서 제거**, `domain/types.rs` 단일 출처로. `publisher_track.rs` 의 struct/impl(PublisherTrack/PublishPipelineStats/RtpCache/NackGenerator/PublisherTrackSnapshot)은 **유지**.
2. **`stream_map.rs` 파일째 폐기** (StreamKind 만 있던 파편). `mod.rs` 에서 `pub mod stream_map;` 제거.
3. **`mod.rs` 에 `pub mod types;` 추가.**
4. **경계 enum 은 본 작업 범위 밖 — 그대로 둔다**:
   - `PauseReason`(subscriber_gate.rs) — gate 전용 인자, gate 와 응집. 이동 안 함.
   - `PeerState`/`PublishState`/`SubscribeState`(state.rs) — 이미 3-Layer State 전용 모음. 이동 안 함.
5. **단일 출처 원칙** — 타입은 types.rs 한곳에서만 보이게. re-export 호환 레이어는 두지 않음(★ §3 에서 재확인).

---

## §3 결정 추천 (★ 정지점 — 부장님 판단)

**★ re-export 여부**: 5 enum 을 types.rs 로 옮기면 기존 `crate::domain::publisher_track::{TrackKind, ...}` import 가 전부 깨진다. 두 길:

- **(권장) 전부 갈아끼우기** — 호출처 use 경로를 `crate::domain::types::{...}` 로 일괄 수정. 타입이 types.rs 한곳에서만 보임(단일 출처 깨끗). 대가: TrackKind 가 도메인 전반이라 mechanical 양이 큼(diff 수십~수백 줄).
- **(대안) publisher_track.rs 에 `pub use crate::domain::types::{TrackKind, VideoCodec, DuplexMode, TrackType};`** — 기존 `publisher_track::TrackKind` import 가 그대로 작동, 호출처 수정 ~0. 대가: 타입이 두 경로(types + publisher_track)에서 보이는 모호함 + 단일 출처 원칙 흠집. (단 `stream_map::StreamKind` 는 파일 폐기라 어차피 경로 수정 필요.)

김대리 권장은 **(권장) 전부 갈아끼우기** — 자료구조 단일 출처 원칙 정합, 호환 레이어 잔재 방지. 다만 양이 크니 부장님이 "부담 대비 실익" 판단해 (대안) 으로 뒤집을 수 있음. **이 결정 GO 후 §4 진행.**

> 본 ★ 외(5개 이동 / stream_map 폐기 / 경계 두기)는 §2 확정 — 선조치.

---

## §4 단계별 작업

> Phase A~D 는 컴파일 의존상 **한 commit**(원본 제거 즉시 호출처 깨짐 → 동시 정리해야 빌드). 논리 단계로만 분리.

### Phase A — mod 등록 + 원본 enum 제거

A-1. `domain/mod.rs`: `pub mod types;` 추가. `pub mod stream_map;` 제거.
A-2. `domain/publisher_track.rs`: `TrackKind` / `VideoCodec` / `DuplexMode` / `TrackType` 의 enum 정의 + impl(Display/from_str/derive 등) **4개 블록 제거**. 파일 상단에 `use crate::domain::types::{TrackKind, VideoCodec, DuplexMode, TrackType};` 추가(자기 struct/impl 이 쓰므로). PublishPipelineStats/RtpCache/NackGenerator/PublisherTrack/PublisherTrackSnapshot 은 유지.
A-3. `domain/stream_map.rs`: **파일 삭제**(git rm). StreamKind 는 types.rs 로 이미 이동됨.

### Phase B — 호출처 use 경로 일괄 수정 (★ §3 결정 반영)

**(권장 갈아끼우기 채택 시)** 전 crate grep 으로 아래 두 패턴을 `crate::domain::types::` 로 치환:
- `crate::domain::publisher_track::{TrackKind | VideoCodec | DuplexMode | TrackType}` (단독/중괄호 혼합)
- `crate::domain::stream_map::StreamKind`

B-주의 1: **혼합 import 분리** — `use crate::domain::publisher_track::{PublisherTrack, TrackKind};` 같은 줄은 `PublisherTrack` 은 publisher_track 잔류, `TrackKind` 만 types 로 분리:
```rust
use crate::domain::publisher_track::PublisherTrack;
use crate::domain::types::TrackKind;
```
B-주의 2: **전체 경로 인라인 사용처** — `crate::domain::publisher_track::TrackKind::Video`(admin.rs 등 use 없이 풀경로) 도 `crate::domain::types::TrackKind::Video` 로.
B-주의 3: 빌드 에러 드리븐 — `cargo build -p oxsfud` 가 "not found in `publisher_track`/`stream_map`" 를 정확히 짚어주므로, 에러 0 까지 반복하면 누락 없음.

**(대안 re-export 채택 시)** publisher_track.rs 에 `pub use crate::domain::types::{TrackKind, VideoCodec, DuplexMode, TrackType};` 한 줄. `stream_map::StreamKind` 호출처만 `types::StreamKind` 로 수정(파일 폐기 불가피분).

### Phase C — 빌드/테스트

C-1. `cargo build -p oxsfud` → 에러 0.
C-2. `cargo test -p oxsfud` → **211 passed** (baseline 일치). 단위 테스트도 enum 경로 영향받으면 같이 수정.
C-3. `cargo check` → 0 warning (unused import 정리).

### Phase D — 회귀

D-1. oxe2e 4/4 (conf_basic / ptt_rapid / duplex_cache / simulcast_basic) — 부장님 수행 자리. 동작 무변경이라 baseline 일치 기대.

---

## §5 변경 영향 범위 (파일) — 누락 차단 점검

**정의 변경 (3 파일)**:
- `domain/mod.rs` — types 등록 + stream_map 제거
- `domain/publisher_track.rs` — 4 enum 제거 + use types
- `domain/stream_map.rs` — **삭제**

**호출처 use 경로 (grep 전수 — TrackKind/StreamKind 가 광범위)**. 최소 확인 대상:
- domain/: `subscriber_stream.rs`, `subscriber_stream_index.rs`, `publisher_track_index.rs`, `publisher_stream.rs`, `participant.rs`, `peer.rs`, `room.rs`, `slot.rs`, `floor.rs`, `floor_broadcast.rs`, `speaker_tracker.rs`, `pli_governor.rs`, `scope.rs`
- transport/udp/: `ingress.rs`, `ingress_publish.rs`, `ingress_rtcp.rs`, `ingress_subscribe.rs`, `egress.rs`, `nack_generator.rs`, `rtcp.rs`
- signaling/handler/: `track_ops.rs`, `room_ops.rs`, `helpers.rs`, `admin.rs`, `floor_ops.rs`, `scope_ops.rs`
- `hooks/stream.rs`, `tasks.rs`, `agg_logger.rs`(가능성)
- 위는 **확인 출발점일 뿐** — `cargo build` 에러가 최종 권위. "한 군데 안 봐서 샌다"(20260602b 교훈) 방지로 grep + 빌드 에러 양쪽 교차.

> §5 범위 밖(로직 변경)은 손대지 말 것. 별 문제는 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점**: §3 ★ re-export 여부 1건. GO 후 진행.
2. **선조치**: §2 확정분(5 이동 / stream_map 폐기 / 경계 두기) 은 박고 진행.
3. **추가 변경 금지**: enum 이동 + use 경로 외 손대지 말 것. config.rs 의 stale 주석 등 발견 시 *발견_사항* 만.
4. **2회 실패 시 중단**: 같은 빌드 에러 2회 미해결 → 중단 + 보고.

---

## §7 기각 접근법

- **5개 외 enum 추가 이동** (PauseReason / 상태 enum / FloorState 등) — 전용·종속이라 응집 깨짐. 본 작업은 순수 어휘 5개만.
- **stream_map.rs 를 stream_kind.rs 로 rename 후 존치** — StreamKind 가 types.rs 로 흡수되므로 파일 자체 불필요. 폐기가 정답(파편 제거 목적).
- **types.rs 에 메서드 로직 추가** — 어휘 enum 의 자기 변환(from_str/derive/Display)만. 외부 도메인 의존 메서드는 원본 모듈에.

---

## §8 산출물

- 코드: §5 파일. `domain/stream_map.rs` 삭제. 211 GREEN + oxe2e 4/4.
- 완료 보고: `context/202606/20260602d_enum_types_consolidation_done.md`.
- 보고 항목: commit 해시, re-export 채택 여부(★ 결정), 수정 호출처 파일 수, 삭제 확인(stream_map.rs), baseline 211 + oxe2e 4/4, unused import 0.

---

## §9 시작 전 확인

1. `b5b9172` 적층 + `domain/types.rs` 존재(5 enum) 확인?
2. ★ §3 re-export 여부 결정 GO?
3. 현재 빌드 실패(중복 정의)가 출발점임을 인지 — 작업 완료 시 컴파일 복구.

---

## §10 직전 작업 처리

- `20260602c`(`b5b9172`) 위에 적층. 본 작업은 통계 토픽과 무관한 **파편 정리(enum 통합)** 줄기.
- 완료 후 PROJECT_MASTER 소스 구조에서 `stream_map.rs` 항목 제거 + `types.rs` 추가 반영 자리(별도 지시 시).

---

*author: kodeholic (powered by Claude)*
