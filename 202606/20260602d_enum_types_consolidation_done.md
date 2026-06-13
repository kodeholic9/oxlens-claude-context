# 완료 보고 — 도메인 어휘 enum types.rs 통합 (원본 제거 + 호출처 일괄 + stream_map 폐기)
> 작업 지침 ← [20260602d_enum_types_consolidation](../claudecode/202606/20260602d_enum_types_consolidation.md)

> 지침: `claudecode/202606/20260602d_enum_types_consolidation.md`
> 선행: `20260602c`(sub 텔레메트리, `b5b9172`) 위에 적층.
> 상태: **완료 · commit `3558faf` · 회귀 4/4 PASS. 로직 0 변경(정의 위치 이동 + use 경로만).**

---

## 1. commit

| commit | 내용 |
|---|---|
| `3558faf` | 5 enum → types.rs 단일 출처 + 원본 제거 + stream_map.rs 폐기 + 호출처 일괄 (한 commit — 컴파일 의존) |

cargo build **0 error** / cargo test **211 = baseline** / cargo check **0 warning** / oxe2e **4/4 PASS**.

---

## 2. ★ 정지점 결정 — re-export 여부

**갈아끼우기(권장) 채택.** re-export 호환 레이어(`pub use`) 두지 않음 → 타입이 `domain::types` 한곳에서만 보임(단일 출처 원칙 정합, 호환 레이어 잔재 0). 대가(mechanical 양)는 regex + 빌드 에러 드리븐으로 흡수.

---

## 3. 처리 내역

**정의 (3 파일)**:
- `domain/mod.rs` — `pub mod types;` 추가, `pub mod stream_map;` 제거
- `domain/publisher_track.rs` — TrackKind/VideoCodec/DuplexMode/TrackType **4 enum 정의(180줄) 제거** + `use crate::domain::types::{...}` 추가. struct/impl(PublisherTrack/PublishPipelineStats/RtpCache/NackGenerator/PublisherTrackSnapshot) 유지
- `domain/stream_map.rs` — **git rm** (StreamKind 1개만 남은 파편, types.rs 흡수)

**호출처 (grep + 빌드 에러 양쪽 교차 — 20260602b §5 누락 재발 방지)**:
- **regex 2종**: ① `crate::domain::publisher_track::(TrackKind|VideoCodec|DuplexMode|TrackType)\b` → `types::` (full-path inline B-주의2 + 단독 `use` 커버, `PublisherTrack` struct 는 enum명 아니라 미오염) ② `crate::domain::stream_map::StreamKind` → `types::StreamKind`
- **brace import 11곳 수동**:
  - pure-enum 5곳 경로 치환: participant.rs / track_ops.rs / hooks/stream.rs / egress.rs / ingress_rtcp.rs
  - **mixed 6곳 split**(B-주의1, struct는 publisher_track 잔류 + enum만 types): peer.rs(+PublisherTrackSnapshot) / publisher_stream.rs / subscriber_stream.rs / publisher_track_index.rs / helpers.rs(+PublisherTrackSnapshot) / ingress_publish.rs(+PublisherTrack)

**경계 enum 미이동** (§2-4): PauseReason(subscriber_gate) / PeerState·PublishState·SubscribeState(state.rs) — 전용·응집.

---

## 4. 보고 항목 (§8)

- **commit**: `3558faf`
- **re-export 채택 여부**: 갈아끼우기 — re-export **안 함** (단일 출처)
- **수정 호출처 파일 수**: 20개 수정 + `stream_map.rs` 삭제 + `types.rs` 신규 (총 git 변경 22 entry). net 59+/234− (enum 정의 순삭 효과)
- **삭제 확인**: `domain/stream_map.rs` git rm 완료 (D), `domain/types.rs` 신규
- **baseline**: cargo test 211 + oxe2e conf_basic·ptt_rapid·duplex_cache·simulcast_basic 4/4 PASS
- **unused import**: cargo check 0 warning (split 후 잔여 import 없음 확인)

---

## 5. 발견_사항

- `signaling/handler/admin.rs` 의 `stream_map_json` 변수명 + `"stream_map"` JSON 키 = **모듈명 아님**(진단 출력 라벨). types 통합과 무관 → 유지. (이름이 폐기된 모듈을 연상시키나 출력 스키마 호환상 둠. 별 토픽에서 rename 검토 가능.)
- `domain/types.rs` 내용은 김대리(claude.ai) 선작성분 — 지침대로 미수정. 원본과 정의 동일 확인.

---

## 6. 회귀

| 시나리오 | 결과 |
|---|---|
| conf_basic | ✓ PASS |
| ptt_rapid | ✓ PASS |
| duplex_cache | ✓ PASS |
| simulcast_basic | ✓ PASS |

서버 재기동 1회(부장님). 로직 0 변경이라 baseline 일치.

---

## 7. 남은 일

- PROJECT_MASTER 소스 구조: `stream_map.rs` 제거 + `types.rs` 추가 반영 (별도 지시 시).
- SESSION_INDEX 갱신 (Phase 121 또는 Phase 120 묶음, 부장님 지시 시).

---

*author: kodeholic (powered by Claude)*
