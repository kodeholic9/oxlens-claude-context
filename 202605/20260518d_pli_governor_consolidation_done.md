# 묶음 4 — 자료구조 일관성 ② (PLI Governor 통합) 완료 보고
> 작업 지침 ← [20260518d_pli_governor_consolidation](../claudecode/202605/20260518d_pli_governor_consolidation.md)

- 작업자: 김과장 (Claude Code)
- 일자: 2026-05-17
- 지침: `context/claudecode/202605/20260518d_pli_governor_consolidation.md`
- 빌드: `cargo build --release -p oxsfud` PASS
- 테스트: `cargo test --release -p oxsfud` **192 passed / 0 failed** (묶음 3 종료 189 + 신규 3)

---

## §0 의무 점검

- `cargo test --release -p oxsfud` 189 PASS 확인 후 진입
- 직전 PTT 정합 점검 — 행위적 끊김 0건 확인 후 진입
- 사전 grep:
  - `pli_state` refs: 32자리 (마이그 면적)
  - `entry.pli_state`: 6자리 (Phase B/D 마이그 자리)
  - `send_pli_to_publishers` 호출처: hook 1자리 (F8 해소 면적)

## Phase 진행 — Phase 단위 commit 분리 (bisect 용이성)

| Phase | commit | 내용 | 결과 |
|-------|--------|------|------|
| A | `18b28d3` | `SubscriberStream.pli_state: Mutex<PliSubscriberState>` 필드 신설 | 완료 |
| B | `e572e77` | `ingress_subscribe` 의 `entry.pli_state` → `sub_stream.pli_state` 마이그 | 완료 |
| C | `aacde13` | `subscriber_stream::keyframe_relayed` 자리 마이그 (mode 무관 통합) | 완료 |
| D | `30c1931` | `SubscribeLayerEntry.pli_state` 필드 폐기 + `tasks.rs::pli_sweep` 자리 정합 | 완료 |
| E | `e239301` | `send_pli_to_publishers` 본문에 `judge_server_pli` 통합 (F8 해소) | 완료 |
| F | `c989f6d` | `track_ops::do_tracks_ack` 의 sub_state symmetric reset (묶음 3 TODO 해소) | 완료 |
| G | (본 commit) | 단위 테스트 3건 + 잔존 grep + 보고서 | 완료 |

## 시그니처 선조치 결정

### Phase E — `judge_server_pli` layer 인자
- 분석: `send_pli_to_publishers` 호출처는 `hooks/stream.rs::handle_pli_for_room` **1자리만**
- 결정: hook 안 호출이 아닌 **`send_pli_to_publishers` 본문 안에 Governor 통합** — F8 해소 정합
- Layer 인자: `target_ssrc` 가 simulcast 시 rid="h" 만 선택 → **Layer::High 고정**
- 효과: hook 안 본문 무변경, send_pli_to_publishers 본문 강화

### Phase F — sub_state 순회 자료구조
- 분석: `track_ops::do_tracks_ack` 의 `pli_targets` 산출 자리에서 이미 `subscriber.peer.subscriber_streams_snapshot()` 순회 + `gate.resume()` 분기 + publisher_id 추출
- 결정: **그 순회 안에서 동시 처리** — 자료구조 추가 불필요. publisher_id dedup 후 publisher 측 reset 으로 묶임

## Phase 세부

### Phase A
- `SubscriberStream.pli_state: Mutex<crate::room::pli_governor::PliSubscriberState>` 추가
- 생성자 `SubscriberStream::new` 안 `pli_state: Mutex::new(PliSubscriberState::new())` 초기화
- mode (Audio / VideoNonSim / VideoSim / ViaSlot) 무관 — 모든 SubscriberStream 보유
- Audio / ViaSlot 에서는 호출 안 됨 (Mutex 인스턴스 1개 overhead 미미)

### Phase B
- `ingress_subscribe.rs:349-388` VideoSim 분기 안 `entry.pli_state` → `sub_stream.pli_state.lock()` 사용
- **Lock 순서: layer entry → pli_state** (deadlock 회피 명시)
- `judge_subscriber_pli` / `apply_downgrade` / `effective_layer` / `consecutive_pli_count` 호출처 모두 마이그

### Phase C
- `subscriber_stream.rs::forward` 의 keyframe relayed 자리 — VideoSim 한정 (`entry.pli_state`) → mode 무관 (`self.pli_state.lock()`)
- VideoNonSim 도 이제 keyframe relayed 추적 (이전 없었음 — 옵션 A 의 장점)

### Phase D
- `SubscribeLayerEntry.pli_state` 필드 제거
- `tasks.rs::pli_sweep` 의 `entry.pli_state` → `sub_stream.pli_state.lock()` 사용 (Lock 순서: layer entry → pli_state)
- `PliSubscriberState` import 정리 (subscriber_stream.rs / participant.rs 의 사용 안 함 import 제거 — full-path 사용)
- `entry.pli_state` 잔존 0 확인

### Phase E (F8 해소)
- `transport/udp/egress.rs::send_pli_to_publishers` 본문 안 publisher 순회 자리에 Governor 통합
- 매 publisher 별 `judge_server_pli(&mut pub_state, Layer::High)` 호출
- `PliDecision::Forward` 만 실제 PLI 발사. `Drop` 시 publisher skip (debug log)
- Server PLI 5종 (spawn_pli_burst 5자리) 중 hook 자리만 본 함수 경유 — 다른 자리 (이미 Governor 통과) 영향 없음

### Phase F (묶음 3 TODO 해소)
- `track_ops::do_tracks_ack` gate.resume 자리 — gate 풀린 SubscriberStream 단위로 pli_state 동시 reset:
  - `needs_keyframe = false`
  - `needs_keyframe_since = None`
  - `consecutive_pli_count = 0`
- 같은 순회 안에서 publisher_id dedup → publisher 측 reset (`PliPublisherState::new()`) 으로 묶임
- Governor publisher / subscriber 사이드 symmetric 정합

### Phase G
- 신규 테스트 3건 (pli_governor.rs::tests):
  - `judge_subscriber_pli_mode_agnostic` — mode 무관 동작
  - `server_pli_throttle_after_keyframe` — F8 해소 검증 (judge_server_pli Drop 분기)
  - `sub_state_reset_resets_pli_cycle` — Phase F symmetric reset 정합

## §G 잔존 grep

```
entry.pli_state | SubscribeLayerEntry.pli_state : 0  ✓
send_pli_to_publishers (외부 호출처)             : hook 1자리 (Governor 통과 정합)
PliSubscriberState import 잔존 (unused)         : 0  ✓
```

## 주요 변경 파일 5개 선별

```
crates/oxsfud/src/room/pli_governor.rs             | 51 +++++++ (신규 테스트 3건)
crates/oxsfud/src/signaling/handler/track_ops.rs   | 25 ++ (Phase F symmetric reset)
crates/oxsfud/src/transport/udp/egress.rs          | 14 ++ (Phase E F8 해소)
crates/oxsfud/src/transport/udp/ingress_subscribe.rs | 14 ++ (Phase B 마이그)
crates/oxsfud/src/tasks.rs                         | 14 ++ (Phase D 정합)
```

## 산출물

- 7 commits (Phase A~G — bisect 용이)
- 8 파일 +102 / -34 (net +68 lines)
- 192 tests PASS (신규 3건 추가)

## 해소된 백로그

- **F8** (GATE:PLI vs Hook PLI 중복) — handle_pli_for_room 가 Governor 통과 — 해소
- **묶음 3 Phase C TODO** (gate.resume 후 sub_state reset) — Phase F 에서 symmetric reset — 해소

## 위험도 평가

- **hot path 변경 있음** — `subscriber_stream::forward` (keyframe relayed), `ingress_subscribe` (PLI 판정), `egress::send_pli_to_publishers` (Governor)
- Lock 순서 명시: `layer entry → pli_state` — deadlock 회피
- 런타임 검증은 부장님 환경 (smoke test) 의존. 코드 정합은 단위 테스트로 확인 (192 PASS).
- Audio / ViaSlot mode 에서 `pli_state` 생성되지만 호출 안 됨 (의도된 동작, overhead 무시).

## 호환성 / 위험

- 클라 wire 영향 0
- 핫패스 영향: `gate.is_allowed()` Mutex → atomic (묶음 3) + Governor 통과 (묶음 4 F8) — 발사 부하 감소 방향
- mode 무관 PLI 추적 가능 — VideoNonSim 도 이제 keyframe relayed 갱신
