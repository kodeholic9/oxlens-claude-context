# 완료 보고 — scope.rs 폐기 (RoomSet/RoomSetId 래퍼 제거, sub_rooms → bare HashSet)

> 지침: 별도 지침 파일 없음 — 부장님 구두 지시("scope.rs 삭제 작전") → 김과장 작전 수립 → 부장님 정정·결정 → 실행.
> 선행: `20260602d`(enum types 통합, `3558faf`) 위에 적층.
> 상태: **완료 · commit `8291ff0` · 회귀 4/4 PASS. 다방 청취 유지, 래퍼만 제거.**

---

## 1. commit

| commit | 내용 |
|---|---|
| `8291ff0` | `RoomSet`/`RoomSetId` 폐기, `sub_rooms` → `ArcSwap<HashSet<RoomId>>`, scope.rs 삭제 (한 commit — 타입 의존) |

cargo build **0 error** / check **0 warning** / test **205** / oxe2e **4/4 PASS**.

---

## 2. 작전 경위 (부장님 정정 2회 반영)

1. **초기 진단**: scope.rs(`RoomSet`/`RoomSetId`)는 `Peer.sub_rooms`로 살아있는 cross-room 구독 자료 — stream_map(파편)과 다름. 그냥 삭제 불가.
2. **김과장 1차 작전 (기각)**: "기능째 제거"(sub_rooms→joined collapse) 제안.
3. **부장님 정정 ①**: "다방 청취기능 있어 — `ArcSwap<RoomSet>` → `ArcSwap<HashSet<RoomId>>`로". → 기능 유지, **래퍼만 제거**로 작전 전환.
4. **부장님 정정 ②**: "클라 영향 OK(클라를 서버에 맞춤), 정석대로". → set_id **inline 재생성 band-aid 기각**, wire 필드째 **완전 폐기**.

→ 핵심 통찰: `RoomSet`은 `HashSet<RoomId>` 위에 ① `set_id`(`"sub-{user_id}"` 결정값) ② `with_inserted/removed`(RCU 헬퍼)만 얹은 잉여 래퍼. ①은 저장 불필요(결정값), ②는 HashSet clone+insert/remove로 대체. `RoomId: Borrow<str>`(room_id.rs:86)라 `contains` 무변.

---

## 3. 변경 표면 (6 파일)

| 파일 | 작업 |
|---|---|
| `domain/scope.rs` | **삭제** (RoomSet/RoomSetId + 단위테스트 5개) |
| `domain/mod.rs` | `pub mod scope;` 제거 |
| `domain/peer.rs` | import `scope::RoomSet` 제거 / 필드 `ArcSwap<RoomSet>`→`ArcSwap<HashSet<RoomId>>` / init `RoomSet::new_sub`→`HashSet::new()` / `scope_insert`·`scope_remove`·`sub_insert`·`sub_remove_one`의 `with_inserted/removed`→`clone()+insert/remove` (RCU 유지) / 테스트: set_id assert 제거+rename, `scope_sub_set_id_is_stable_across_mutations` 폐기 |
| `signaling/handler/scope_ops.rs` | `.rooms.iter()`→`.iter()` (2곳) / diff `contains(r)`→`contains(r.as_str())` / ScopeEventPayload literal 에서 `sub_set_id`/`pub_set_id` 제거 |
| `signaling/message.rs` | `ScopeEventPayload.{sub_set_id, pub_set_id}` 필드 삭제 |
| `transport/udp/ingress.rs`, `datachannel/mod.rs`, `signaling/handler/admin.rs` | `sub_rooms...rooms.iter()`→`.iter()` (RTCP hint / FLOOR fallback / admin), admin `"set_id"` 키 제거 |

> 다방 청취(N방 sub) · SCOPE op(`sub_add`/`sub_remove` 선택) · fan-out 역인덱스(attach_to_room) 전부 **유지**.

---

## 4. set_id 거취 (★ 결정 — 정석 폐기)

- `RoomSetId`(`sub-{user_id}`)는 `HashSet`엔 둘 곳 없음. 두 길 중 부장님이 **완전 폐기** 채택:
  - (기각) 출력 시 `format!("sub-{user_id}")` inline 재생성 — wire 보존 band-aid.
  - **(채택) wire 필드째 폐기** — `ScopeEventPayload.sub_set_id`/`pub_set_id` + admin `set_id` 키 삭제. 클라는 서버에 맞춤.
- `pub_set_id`(ScopeEventPayload)는 Phase A(cross-room publish 폐기) 이후 항상 빈값 dead → 함께 제거.

---

## 5. 회귀 (oxe2e)

| 시나리오 | 결과 |
|---|---|
| conf_basic | ✓ PASS |
| ptt_rapid | ✓ PASS |
| duplex_cache | ✓ PASS |
| simulcast_basic | ✓ PASS |

다방 미커버이나, 단일방 collect_subscribe_tracks / SCOPE diff / RTCP hint 경로는 커버. RCU clone 비용 기존 동일.

---

## 6. baseline 변동 — 211 → 205

scope.rs 삭제로 단위테스트 6개 동반 제거 (**실패 아님**):
- scope.rs: `new_sub_has_expected_set_id_format` / `with_inserted_preserves_set_id...` / `with_inserted_is_idempotent` / `with_removed_preserves...` / `set_id_display_format` (5)
- peer.rs: `scope_sub_set_id_is_stable_across_mutations` (1)

→ **이후 단위테스트 baseline = 205.**

---

## 7. 발견_사항 / 남은 일

- `datachannel/mbcp_native.rs::pub_set_id` — **별개** FLOOR_REQUEST wire 필드(클라가 보내는 TLV, 서버 파싱만 하고 핸들러 미사용 dormant). RoomSetId와 무관 → 본 작업 미터치. 별 정리 토픽 후보.
- **클라 정합**: SCOPE 응답에서 `sub_set_id`/`pub_set_id` 사라짐 → oxlens-home / Android SDK 가 참조 시 서버에 맞춰 수정. (서버측 hub 경로는 §8 ★ 에서 검증 — 안전.)
- SESSION_INDEX 갱신 (지시 시).

---

## 8. 부장님 지적 반영 (사후 보완, 2026-06-03) — doc-청소 commit `26f120b`

초기 8291ff0 의 불완전(주석 stale)을 부장님이 짚어 보완. 동작 0, 주석만.

**① 모듈/핸들러 doc stale (이번 작업 책임)** — set_id 통째 폐기하며 doc 동반 갱신했어야 함. 누락 인정. 같은 묶음으로 일괄 청소:
- `scope_ops.rs` 모듈 doc — "SCOPE sub_rooms 전용 축소, pub_set_id/pub_rooms 표시 Phase G 정정", "SCOPE_EVENT(0x2200) broadcast" 옛 모델 → 현행(sub_rooms 전용, set_id 폐기, pub_add/remove dead, SCOPE_EVENT 미emit, 요청-응답형).
- `peer.rs` 모듈 헤더 doc (line 8·15) — `sub_rooms: ArcSwap<RoomSet>` → `ArcSwap<HashSet<RoomId>>` (필드 주석은 8291ff0 에서 고쳤으나 헤더만 안 따라옴 — 부장님 추가 지적).
- `state.rs:19` (전수 재검 중 추가 발견) — `(sub_rooms / pub_rooms RoomSet)` → `(sub_rooms: HashSet<RoomId> + pub_room)` (RoomSet + Phase A 폐기 pub_rooms 둘 다 stale).
- → `rg RoomSet` 잔여 = 의도적 "폐기" 주석만. stale 0.

**② message.rs SCOPE 주석 stale (Phase A 이전부터 썩음, 이번 정리 기회 놓침)** — "SCOPE_UPDATE {sub_add,sub_remove,pub_add,pub_remove}", "순서 §4.6: sub_add→pub_add→pub_remove→sub_remove" 옛 모델 → 현행 + dead wire 잔재 명시로 갱신.

**③ 삭제 테스트 6번째 출처** — §6 에 명시돼 있음: scope.rs cfg(test) 5개 + **peer.rs `scope_sub_set_id_is_stable_across_mutations` 1개** = 6. (peer 측 1개가 6번째.) 출처 확정.

**④ ★ hub shadow 복원 경로 — 검증 완료(안전)** — scope.rs 주석이 "set_id 세션 수명 불변 — reconnect shadow 복원 호환"이라 못 박았던 만큼 hub(oxhubd) shadow 가 sub_set_id 를 누적·복원하는지 점검 필요(부장님 지적: 이건 클라 아닌 **서버(hub)**). **검증 결과**:
  - `oxhubd/src/shadow/mod.rs::ShadowState` 는 **`ROOM_EVENT`(op=0x2001) participant_joined/left 만** 누적(room→참가자 목록). SCOPE/SCOPE_EVENT/sub_set_id 전혀 안 봄.
  - `SCOPE_EVENT`(broadcast op) 는 정의만 있고 oxsfud 어디서도 **미emit** — SCOPE 는 요청-응답뿐.
  - oxsfud 재연결 경로에 SCOPE/set_id 재emit **0** (grep 확인).
  - → sub_set_id 는 (a)SCOPE 직접응답 (b)admin JSON 둘에만 존재했고 둘 다 제거됨. **hub shadow·재연결 어디에도 안 묻음 → 영향 클라 한정 확정.** 초기 보고가 "클라 영역"으로 뭉갠 것은 hub 경로 *미검증* 이었음 — 명시 검증으로 안전 확인.

**별 토픽 후보(일관성)**: `pub_add`/`pub_remove`(ScopeUpdateRequest) · `pub`(ScopeSetRequest) 는 set_id 와 동성격 dead wire 호환 잔재(Phase A 폐기). 이번 미터치 — 차후 set_id 처럼 정석 폐기 검토.

---

*author: kodeholic (powered by Claude)*
