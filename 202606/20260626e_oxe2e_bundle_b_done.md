// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 묶음 B(봇 수신 원료 적재) 완료 보고 (20260626e)

> **정지점 B.** 작업지침 `20260626c` §3 묶음 B (W2). 커밋 전 — diff 검토 → GO 후 커밋.
> **서버 0줄.** oxe2e 봇 수신 기록에 무가공 (seq, ts) 열 추가. judge 는 아직 안 씀(묶음 C 원료).

---

## 1. 변경 파일 (3 — 전부 oxe2e)

| 파일 | 변경 |
|---|---|
| `crates/oxe2e/src/bot/media.rs` | `RecvLog.packets: HashMap<u32, Vec<(u16,u32)>>` 필드 + 수신 루프에서 `(rtp.seq, rtp.ts)` 무가공 push |
| `crates/oxe2e/src/bot/mod.rs` | `BotResult.packets` 필드 + conf 경로(:292)·floor 경로(:467) 두 곳에서 `recv.packets` 전달 |
| `crates/oxe2e/src/judge/mod.rs` | 테스트 `mk()` BotResult 생성에 `packets: HashMap::new()` (필드 추가에 따른 컴파일 충족) |

### 1.1 무가공 원칙(P-3) 준수
- 수신 루프(media.rs): `parse_rtp_mini`가 이미 까는 `rtp.seq`(u16)/`rtp.ts`(u32)를 **도착 순서 그대로** `packets[ssrc]`에 push. **판정·정렬·해석 0** — "받은 거 그대로 적는다."
- `counts`(기존)는 병행 유지 — 묶음 C에서 등식으로 교체될 때까지 호환.

---

## 2. 게이트 상태

| 게이트 | 결과 |
|---|---|
| `cargo build -p oxe2e` | ✅ PASS |
| `cargo test -p oxe2e` | ✅ judge caching 2 passed, 0 failed |
| oxe2e 5 시나리오 회귀 | **동작 불변** — 봇 수신 기록만 추가, judge가 `packets` 미사용이라 판정 경로 무변경. (서버 재기동 불요 = 봇 변경.) |

> 묶음 B는 **원료만 적재**하고 judge는 안 건드렸으므로, 회귀 판정 결과가 바뀔 수 없다(cargo test로 충분). 실시나리오 PASS/FAIL은 묶음 C에서 judge가 `packets`를 쓰기 시작할 때 의미를 갖는다.

---

## 3. 완료정의 충족

- ✅ `RtpMini`(seq/ts/marker/pt 다 깜)의 seq·ts가 봇 수신 기록에 적재됨.
- ✅ judge가 `BotResult.packets`로 **봇별·ssrc별 (seq, ts) 도착 열**을 읽을 수 있다(아직 안 씀).
- ✅ 서버 코드 0줄. 무가공(P-3) 유지.

---

## 4. 다음

- **묶음 C (judge `count==0` → 등식 6종 + 음성 픽스처)** — ★핵심, "잘 뚫린다" 직접 해소.
  - C1 seq 집합 완전성 / C2 개수 등식 / C3 ts 단조 / C4 track_id 회신 / C5 TRACKS_READY 존재 / C6 codec 정합. 각 등식 = 짝 음성 픽스처(W5).
  - C가 `packets`를 처음 소비. oxe2e/src/judge/mod.rs + scenario verify_* 한정(서버 0줄).

---

*author: kodeholic (powered by Claude)*
*정지점 B 보고. 커밋 전. 서버 0줄. 원료 적재만 — 회귀 판정 동작 불변.*
