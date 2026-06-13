// author: kodeholic (powered by Claude)
# 완료보고 20260606a — uniform ACK 정합 (거짓 no-ack 선언 제거)
> 작업 지침 ← [20260606a_uniform_ack](../claudecode/202606/20260606a_uniform_ack.md)

> 지침: `claudecode/202606/20260606a_uniform_ack.md`. doc/선언 정리 — **동작 코드 0**.

---

## 결론

`requiresAck()` 의 windowed 에 배선된 적 없는 op 별 no-ack 예외 두 줄(0x2500/0x1304) + 그 거짓을 옮긴 주석/문구 제거. 규칙 수렴 = **"윈도우 타면 반드시 ack, 우회하면 면제(채널 선택)"**. 동작 경로 무변(클라 회귀 index 49 무변, 서버 빌드/테스트 PASS).

---

## ★ 가드 발동 — 별 커밋 전환 (§0/§9)

지침은 "0605d 미커밋 워킹트리에 합류 → 한 커밋" 전제였으나, **0605d 는 직전 턴 부장님 "커밋해" 지시로 이미 3 레포 커밋됨**(home `f84516b` / server `dfccd85` / context `2b3c1ed`). git status 3 레포 확인 = 0605d 변경분 미커밋 잔존 0(워킹트리 깨끗). 따라서 §0 가드대로 **별(단독) 커밋으로 전환**. 0605d 재구현 없음(이미 done).

---

## 변경 (doc-only, 3 파일)

### Phase A — `oxlens-home/sdk/signaling/wire.js`
- `requiresAck()` 에서 `if (op === 0x2500)` / `if (op === 0x1304)` **두 줄 삭제.** 카테고리 가드(Handshake 0x0000 / Internal 0xE000 / Error 0xF000)는 유지(parse-fail ACK_FAIL 분기에서 생존).
- docstring: `... ACTIVE_SPEAKERS 만 false` → `... Handshake/Internal/Error 만 false` + 근거 주석(windowed=ack, 우회=채널 선택).
- 함수 통째 리팩터/인라인 안 함(§6).

### Phase B — `oxlens-sfu-server/crates/oxsig/src/opcode.rs`
- `// 0x25xx — Active Speakers (S→C, ACK 없음 — 빈도 높음)` → `(S→C, Event=ACK 대칭. OutboundQueue windowed — no-ack 아님)`. 주석 1줄, 코드/테스트 로직 무변(requires_ack 함수 서버 부재, catalog_size 무증감).

### Phase C — `context/design/wire_v3_catalog.md`
- 카테고리 표 `Event ... ACK 필수 (ACTIVE_SPEAKERS 예외)` → `ACK 필수 (windowed — 예외 없음)`.
- `## 13. Event — Speakers (0x25xx, ACK 없음)` → `(0x25xx, Event=ACK 대칭, windowed)`.
- (Handshake/Admin 의 "ACK 없음" 은 진짜 no-ack 경로 — 무변. §5 밖.)

---

## 검증 (Phase D)

- **참조처**: sdk 의 `requiresAck` 호출 = `signaling.js:258` 1자리(recv `if (requiresAck(op)) this.ack(...)`). 두 줄 제거 후 0x2500/0x1304 → true → ack 호출 = "다 ack" 와 정합(변경 견딤). 테스트 mjs 의 0x2500/0x1304 ack 단정 = 없음(갱신 불요).
- **sanity**: `requiresAck` 0x2500=true / 0x1304=true / 0x1101=true / 0x0001=false / 0xE000=false / 0xF000=false — uniform 확인.
- **클라 회귀**: PTT / T3d / T3c / T2b ALL PASS, index 49(무변).
- **서버**: `cargo test -p oxsig --lib` 54 PASS(opcode 15 포함), oxsfud/oxhubd/oxsig 빌드 PASS.

---

## 발견_사항

- **0605d done 보고(2b3c1ed)의 "fire-and-forget / requiresAck=false / TELEMETRY 동형 ACK_OK" 서술**은 본 정정으로 의미 갱신: CLIENT_EVENT 도 windowed+acked(uniform). 서버 dispatch 의 ACK_OK 회신은 예외 덮어쓰기가 아니라 "다 ack" 의 일반 케이스 — 이제 완전 정합. (커밋된 과거 보고는 보존, 본 보고가 상위.)
- 서버엔 `requires_ack` 함수 자체가 없음(채널 선택으로 구조적 분기) — 클라 대칭 함수 신설 안 함(§7 기각).

---

## 다음

본 cleanup 커밋 후 → 0605d Phase D 라이브 RUN(부장님, CLIENT_EVENT 사건→agg-log 노출 + mount/unmount DOM 경로 확인). 이후 track-dump.js stub 폐기 정리.

---

*author: kodeholic (powered by Claude)*
