// author: kodeholic (powered by Claude)
# 작업지침 20260606a — uniform ACK 정합 (거짓 no-ack 선언 제거)
> 완료 보고 → [20260606a_uniform_ack_done](../../202606/20260606a_uniform_ack_done.md)

> 0605d(CLIENT_EVENT) 미커밋 워킹트리에 합류. **동작 코드 0 — 선언/주석만.** 한 커밋.
> 단일 출처. 근거는 §1(실증 정독 — 추측 0).

---

## §0 의무 점검

- 본 지침은 **doc/선언 정리**다. flow/wire **동작 코드 변경 0**. 새 동작 추가 금지.
- 0605d 변경분이 워킹트리에 **미커밋 상태로 살아있어야** 한다(이 cleanup 을 얹어 한 커밋). 이미 커밋됐으면 멈추고 보고 → 별 커밋으로 전환.
- `requiresAck()` 는 **두 줄만** 삭제. 함수 통째 리팩터/인라인 금지(§7).

---

## §1 컨텍스트 — 왜 (실증)

v3 "대칭 ACK + 슬라이딩 윈도우" 의 **실제 배선**:

- **서버**: hub WS 루프 `event_rx` arm 이 sfud 이벤트를 **무조건** `outbound.enqueue(op, body)` → windowed (`oxhubd/ws/mod.rs`). `common/ws/outbound.rs::enqueue` 에 requires_ack 분기 없음 — 들어온 건 전부 window. ACTIVE_SPEAKERS 우회 경로 없음. 우회는 `reply_rx`(요청 응답) / `bin_event_rx`(MBCP) 둘뿐 — op 가 아니라 **채널 선택**으로 갈림. 서버엔 requires_ack 함수 자체가 없다.
- **클라**: `signaling.js` `send()`/`request()` 가 **무조건** `_outbound.enqueue` → windowed (requiresAck 미참조). 슬롯은 ACK 수신 시 `_outbound.ack(pid)` 로만 풀림. recv 측 `_handleEvent` 는 **default 포함 전 case 에서 `this.ack()`**. `requiresAck()` 가 실제 읽히는 자리는 `_handleMessage` 의 **parse-fail ACK_FAIL 결정 하나뿐.**

**결론**: ACTIVE_SPEAKERS(0x2500) / CLIENT_EVENT(0x1304) 는 **이미 windowed + acked.** wire.js `requiresAck()` 의 no-ack 예외 두 줄은 *배선된 적 없는 선언* — 이득 0, 혼동만(이번 세션 "telemetry 동형" 오판의 원흉). 0x1304 줄은 클라가 안 받는 op 라 **완전 dead**, 0x2500 줄은 parse-fail 분기에만 닿는 **near-dead**.

부장님 결정: **다 ack(uniform).** 규칙 수렴 = *"윈도우 타면 반드시 ack, 우회하면 면제"*. 우회 면제는 send 메서드/채널 선택(`sendDirect`/`ack`/`sendFloorMbcp` / `reply_tx`·`bin_event_tx`, pid=0 핸드셰이크)으로 **구조적으로** 보장됨 — `requiresAck()` 의 op 예외는 그 위에 얹힌 중복 거짓. 제거 후 서버 dispatch arm 의 CLIENT_EVENT ACK_OK 회신도 "다 ack" 와 완전 정합(더는 예외를 덮어쓰는 모양 아님).

---

## §2 결정된 사항

1. `wire.js::requiresAck()`: `op === 0x2500` / `op === 0x1304` **두 줄 삭제.** 카테고리 가드(Handshake/Internal/Error)는 **유지.** docstring 의 "ACTIVE_SPEAKERS" 제거.
2. `oxsig/opcode.rs`: ACTIVE_SPEAKERS 상수 주석 `(S→C, ACK 없음 — 빈도 높음)` 정정. 헤더 표 `Event (S→C, ACK 필수)` 가 정답 — 표는 그대로. **코드 변경 없음(주석만).**
3. `wire_v3_catalog.md`: 0x2500 관련 "ACK 없음" 류 문구 있으면 동일 정정. 없으면 skip.
4. **0605d 와 한 커밋.** 별 커밋/별 토픽 아님(부장님 "포함" 결정).

---

## §3 결정 추천 (★ 정지점)

- **정지점 0개.** doc/선언 정리 + 동작 0 → 통합 리뷰만. 커밋 직전 diff 보고 후 부장님 GO.

---

## §4 단계별 작업

### Phase A — 클라 `sdk/signaling/wire.js`
- `requiresAck(op)` 에서 아래 두 줄 삭제:
  - `if (op === 0x2500) return false;   // ACTIVE_SPEAKERS ...`
  - `if (op === 0x1304) return false;   // CLIENT_EVENT ...`
- 결과 함수: Handshake(0x0000)/Internal(0xE000)/Error(0xF000) 만 false, 그 외 true.
- 함수 docstring `op 가 ACK 회신 의무인지 — Handshake/Internal/Error/ACTIVE_SPEAKERS 만 false.` → `... Handshake/Internal/Error 만 false.`
- (권장) 한 줄 근거 주석: `windowed path(enqueue) = 반드시 ack. 우회는 채널 선택(sendDirect/ack/sendFloorMbcp).`

### Phase B — 서버 `oxsig/src/opcode.rs`
- `// 0x25xx — Active Speakers (S→C, ACK 없음 — 빈도 높음)` →
  예: `// 0x25xx — Active Speakers (S→C, Event=ACK 대칭. OutboundQueue windowed — no-ack 아님)`
- 코드/테스트 로직 변경 없음 (requires_ack 함수 부재, 카탈로그 op 증감 없음 → `catalog_size` 무변).

### Phase C — `context/design/wire_v3_catalog.md`
- 0x2500 행/설명에 "ACK 없음" 류 있으면 §2 와 동일 정정. grep 후 처리, 없으면 skip.

### Phase D — 검증
- 클라: sdk 전역 `requiresAck` 참조처 grep — 호출처가 변경 견디는지 확인(현재 `signaling.js::_handleMessage` 1자리 예상). 테스트(`*.mjs`)에서 `0x2500`/`0x1304` ack 단정 있으면 갱신.
- 클라 회귀 재실행: PTT / T3d / T3c / T2b + index — 직전 49 무변 목표.
- 서버: `cargo test -p oxsig`(15 PASS, 주석만 바뀌어 무영향) + oxsfud/oxhubd/oxsig 빌드 PASS.

### Phase E — 통합 커밋
- 0605d(클라 8수정 + event-reporter 신규 / 서버 opcode·mod·client_event / 카탈로그·설계서) + 본 cleanup 3건 → **1커밋.**
- 메시지 예: `feat(signaling): CLIENT_EVENT 0x1304 사건 보고 채널 + uniform-ack 정합(거짓 no-ack 선언 제거)`

---

## §5 변경 영향 범위 (본 cleanup 분)

- `oxlens-home/sdk/signaling/wire.js` (requiresAck 2줄 + docstring)
- `oxlens-sfu-server/crates/oxsig/src/opcode.rs` (ACTIVE_SPEAKERS 주석 1줄)
- `context/design/wire_v3_catalog.md` (해당 문구 있으면)
- **그 외 일절 손대지 말 것.** 특히 `outbound.rs` / `signaling.js` 동작 경로 / `ws/mod.rs` event_rx arm 무변.

---

## §6 운영 룰

- 정지점 0 (통합 리뷰). 추가 변경 금지(§5 밖 발견은 *발견_사항* 보고만). 2회 실패 중단.
- **`requiresAck` 함수 통째 삭제/인라인 유혹 차단** — parse-fail 카테고리 판별에 여전히 쓰인다. 두 줄만.

---

## §7 기각 접근법

- **0x2500 을 진짜 bypass(bin_event 패턴)로 빼 no-ack 실현** — 기각. 부장님 결정 "다 ack", 현 windowed 가 정답. active-speaker ack 왕복은 현 상태 그대로(신규 비용 0).
- **`requiresAck()` 함수 폐기/인라인** — 기각. parse-fail ACK_FAIL 분기에서 카테고리 판별로 생존. 두 줄만 제거.
- **별 커밋/별 토픽** — 기각. 0605d 미커밋 + 동일 wire 의미 → 한 커밋.
- **oxsig 에 requires_ack 함수 신설(클라 대칭)** — 기각. 서버는 채널 선택(event_tx 윈도우 / reply·bin 우회)으로 이미 분기. 함수 신설 = 죽은 대칭.

---

## §8 산출물

- 완료보고: `context/202606/20260606a_uniform_ack_done.md` (발견_사항 포함).
- 통합 커밋 해시 + 회귀/빌드 결과.

---

## §9 시작 전 확인

- `git status` (3 레포) — 0605d 변경분 미커밋 워킹트리 생존 확인. 커밋됐으면 중단 + 보고.
- 클라 회귀 baseline(index 49) / 서버 빌드 baseline 확인.

---

## §10 직전 작업 처리

- 0605d(CLIENT_EVENT) = 본 cleanup 과 **한 커밋 합류.** 0605d 자체 재구현 금지(Phase A~C 이미 done, 검증 완료). Phase D 라이브 RUN 은 커밋 후 부장님 — 본 지침 범위 밖.

---

*author: kodeholic (powered by Claude)*
