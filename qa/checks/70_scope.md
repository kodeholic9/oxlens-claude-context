# 70_scope.md — Scope Model (Cross-Room rev.2)

> **catalog 매핑**: `10_sdk_api.md §Scope (engine.scope.*)`
> **출처 설계**: `context/design/20260423_scope_model_design.md`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 10

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| SC-01 | `affiliate(r)` → SCOPE_UPDATE → 'changed' | `engine.scope.sub.has(r)`, `sub_set_id` 갱신, `cause:'affiliate'` | `21_opcode 53` | ⬜ |
| SC-02 | `deaffiliate(r)` cascade (pub 자동 제거) | `pub.delete(r)` 도 함께, `cause:'deaffiliate'` | 동일 | ⬜ |
| SC-03 | `select(r)` / `deselect(r)` | `pub.has(r)` 토글, `pub_set_id` 갱신 | 동일 | ⬜ |
| SC-04 | `update({sub_add, pub_add, pub_remove, sub_remove})` batch | 1회 SCOPE_UPDATE 송출, 서버 적용 순서 §4.6 | 동일 | ⬜ |
| SC-05 | `set({sub, pub})` → 서버 diff 적용 | OP.SCOPE_SET, 동일 set_id 유지 (변경 없으면) | `21_opcode 54` | ⬜ |
| SC-06 | Server-authoritative (낙관적 미수신) | 호출 즉시 `sub.has(r)==false` (응답 전), 응답 후 true | `10_sdk_api §Scope` | ⬜ |
| SC-07 | set_id 세션 수명 불변 (reconnect 후 동일) | `sub_set_id` 값이 reconnect 전후 동일 | (서버 shadow 복구) | ⬜ |
| SC-08 | change_id roundtrip | 응답 `change_id` 가 요청과 동일 | `10_sdk_api §Scope.update` | ⬜ |
| SC-09 | SCOPE_EVENT broadcast (강제 변경) | `scope.applyEvent` → 'changed' emit, `cause:'force'` 등 | `21_opcode 107` | ⬜ |
| SC-10 | 'pub' JSON key (Rust serde rename) | wire payload `{"pub": [...]}` (JSON, "pub_rooms" 아님) | `10_sdk_api §Scope.set` | 👁 |

---

> ⚠️ pub_rooms ⊆ sub_rooms ⊆ joined_rooms 불변식은 설계서 §10.1 DRAFT — 현재 서버/SDK 모두 강제 안 함.
> ⚠️ SC-10: 'pub' 가 JS reserved word 아님. Rust struct field `pub_rooms` 의 serde rename.
