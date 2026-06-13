# 묶음 2 — 코드 청결성 완료 보고
> 작업 지침 ← [20260518b_code_cleanliness](../claudecode/202605/20260518b_code_cleanliness.md)

- 작업자: 김과장 (Claude Code)
- 일자: 2026-05-17
- 지침: `context/claudecode/202605/20260518b_code_cleanliness.md`
- 빌드: `cargo build --release -p oxsfud` PASS
- 테스트: `cargo test --release -p oxsfud` 195 passed / 0 failed
- 묶음 1 (208 PASS) 대비 13 감소 — Phase H 의 Pan TLV 테스트 13건 폐기 정합

---

## §0 의무 점검

- working tree clean 확인 (직전 커밋 `28a6341`)
- 브랜치 `feature/signaling-v3` 확인
- 지침 §0 사전 grep 패턴 (`#[allow(dead_code)]`, `Pan`, `pan_seq`, `이주`, `마이그`, `Phase`, `Step`) 적용 → 청산 대상 식별

## Phase 진행 요약

| Phase | 내용 | 결과 |
|-------|------|------|
| A | `#![allow(dead_code)]` 모듈 attribute (5 파일) 제거 | 완료 (직전 commit 자리) |
| B | 단일 함수 `#[allow(dead_code)]` 9자리 폐기 | 완료 — 5건 폐기, 2건 `#[cfg(test)]` 마이그, 1건 attribute 만 제거 |
| C | participant.rs Endpoint 이주 흔적 청산 | 완료 — 260줄 묘비 폐기 |
| D | peer.rs 이주 흔적 청산 | 완료 — 140줄 묘비 폐기 |
| E | 기타 파일 시간순 주석 청산 | 핵심 5파일 (floor / track_ops / room_ops / helpers / floor_broadcast) 청산 — 254 → 204 자리 |
| F | Cross-Room 의존 주석 의미 정정 | state.rs / room_id.rs 의 "Phase 1 Cross-Room Federation" → "Cross-Room rev.2" |
| G | 호출처 0 함수 폐기 | Phase B 에 흡수됨 (`reset_relay_timing`, `rand_u32`, `from_socket`, `purge_subscribe_layers`, `flush_ptt_silence`) |
| H | mbcp_native.rs Pan TLV 완전 제거 | 완료 — 360줄 폐기 (parser/builder/struct fields/tests 전수) |
| I | pub_rooms 자료구조 마이그 (ArcSwap<Option<RoomId>>) | **분리 작업으로 이월** — wire 호환 영향 큼 (peer.rs 의 RoomSet 호환 layer 유지) |
| J | 최종 검증 + 잔존 grep | 완료 |

## Phase J — 잔존 grep 결과

- `#[allow(dead_code)]` 잔존: **0**
- `pan_seq` / `pan_dests` / `pan_per_room` / `pan_affected` / `PAN_RESULT` / `FIELD_PAN`: **0**
- 시간순 묘비 (Phase / Step / 날짜): **204** (시작 254 대비 -50)
  - 잔존은 활성 의미가 있는 자리 (`설계서 (rev.3)` 참조, `Cross-Room rev.2 Step 2` 등) — 본 묶음 청산 범위 외

## Phase J — 주요 파일 5개 선별

```
crates/oxsfud/src/datachannel/mbcp_native.rs       | 360 +-----------------------
crates/oxsfud/src/room/participant.rs              | 260 ++-------------
crates/oxsfud/src/room/peer.rs                     | 140 ++------
crates/oxsfud/src/signaling/handler/track_ops.rs   |  77 +---
crates/oxsfud/src/signaling/handler/helpers.rs     |  45 +--
```

1. **mbcp_native.rs** (-360): Pan TLV 영역 (parse/build/struct fields/tests 13건) 전수 폐기. 외부 호출처 0 확인.
2. **participant.rs** (-260): Endpoint 이주 묘비 (RoomMember 헤더 ~150줄 + SimulcastRewriter / TrackSnapshot / EgressPacket / DC pending buf doc) 청산. `seq_offset` / `last_out_seq` / `last_out_ts` 필드 폐기.
3. **peer.rs** (-140): PublishContext / SubscribeContext / Peer 의 이주 묘비 + Publisher/Subscriber Streams 메서드 헤더 청산.
4. **track_ops.rs** (-77): SWITCH_DUPLEX op=52 폐기 묘비 + Phase 3 Step B 묘비 + Hook Phase 2 Phase E 묘비 청산.
5. **helpers.rs** (-45): `purge_subscribe_layers` / `flush_ptt_silence` 폐기 + Phase ①.5 묘비 청산.

## 산출물 합계

- 18 파일 변경
- +146 / -923 (net -777 lines)
- 195 tests PASS
- attribute 잔존 0 / Pan TLV 잔존 0

## Phase I 이월 사유

- `Peer.pub_rooms: ArcSwap<RoomSet>` → `ArcSwap<Option<RoomId>>` 마이그는 자료구조 변경이 wire 영향 큰 작업
- 묶음 1 (모델 단순화) 단계에서 "자료구조 변경 면적 회피 위한 선조치" 로 RoomSet 호환 layer 유지 결정
- 현재 *논리적으로 max 1 자리* 로 운용 — 자료구조 마이그는 별도 묶음으로 분리
- 본 묶음의 *코드 청결성* 범위 정의에 부합하지 않아 이월

## 호환성 / 위험

- wire 변경 0 — Pan TLV 는 외부 호출처 0 이며 클라 SDK 도 미발행 (svc=0x03 자체 정의 영역, Phase D 묶음 1 에서 핸들러 자리 이미 폐기됨)
- 핫패스 로직 변경 0 — 모든 변경은 주석 / dead_code / 사용 안 된 헬퍼 자리
- 테스트 회귀 0 (Phase H 외 자리 동일 PASS)
