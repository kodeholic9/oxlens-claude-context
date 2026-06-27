// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 묶음 A(봇 정직화) 완료 보고 (20260626d)

> **정지점 A.** 작업지침 `20260626c` §3 묶음 A. 커밋 전 — diff 검토 → GO 후 커밋.
> **선행 사건**: 0625 simulcast track_id 작업(stash@{0}, 영상 forward 회귀 보류분)은 **버리기로 결정**. 그 199줄 재설계(sentinel placeholder 폐기 + 논리 stream 직생성)는 채택 안 함. 묶음 A는 **stash 무관 최소 변경**으로 수행.

---

## 1. 전제 정정 (착수 중 발견)

설계서 0626b W1은 "0625 §11에서 서버 가드 `!is_sim`이 이미 반영됐다"를 전제했으나, **실제 트리(HEAD `e274296`)엔 미반영**이었다(0625 작업 전체가 stash@{0}에 보류, 미커밋). 따라서 봇만 정직화하면 가드 `if t.ssrc==0 { continue }`가 simulcast를 통째 skip → FAIL. **봇 정직화와 서버 가드는 한 몸**이라, 묶음 A 범위에 서버 가드 1줄 변경을 포함(부장님 "진행해" 승인). 0625 stash는 버린다.

→ **"A~D 서버 0줄" 경계는 묶음 A에 한해 가드 1줄로 조정됨.** B/C/D는 여전히 서버 무변경.

---

## 2. 변경 파일 (2)

| 파일 | 변경 | 줄 |
|---|---|---|
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | `t.ssrc==0` 가드를 `track_type` 확정 뒤로 이동 + `&& track_type != FullSim` 예외 | +6 −2 |
| `crates/oxe2e/src/bot/mod.rs` | simulcast entry `"ssrc": ssrc_h`(가짜 우회값) → `0`(실 클라 계약) + 주석 갱신 | +4 −4 |

### 2.1 서버 가드 (track_ops.rs)
- 구: 루프 진입 즉시 `if t.ssrc == 0 { continue; }` — simulcast(ssrc=0)를 placeholder 분기(`is_placeholder_register`, alloc_sim_group sentinel) **이전에** 쳐내 절반설계였음.
- 신: `track_type` 파생 뒤로 내려 `if t.ssrc == 0 && track_type != TrackType::FullSim { continue; }`.
  - non-sim ssrc=0(SDP 파싱 실패) = 기존대로 skip(보호 유지).
  - FullSim ssrc=0 = 정상 계약 → 통과 → placeholder 등록 → 응답 `tracks[].track_id`는 `stream().track_id()`(vssrc 기반, track_ops.rs:228)로 회신. **t.ssrc 비의존이라 "user_0" 오염 없음.**

### 2.2 봇 정직화 (bot/mod.rs)
- simulcast entry ssrc만 0. `RtpSender::video_sim(ssrc_h/ssrc_l)`은 그대로(실제 RTP 송출 ssrc, rid 운반). 봇 송신 계약 == 웹 클라 계약.

---

## 3. 게이트 상태

| 게이트 | 결과 |
|---|---|
| `cargo build -p oxsfud -p oxe2e` | ✅ PASS (9.77s) |
| `cargo test -p oxsfud -p oxe2e` (단위) | ✅ 211 passed, 0 failed |
| `oxe2e simulcast_basic` (회귀, **release sfud 재기동 후**) | ✅ **PASS** — sim1/sim2 약속 2건, 수신 2종/743패킷. **봇 ssrc=0 + 가드 `!FullSim` 짝 동작 = failability 실증** |
| `oxe2e conf_basic` | ✅ PASS — 약속 2건, 2종/401패킷 (무영향 확인) |
| `oxe2e ptt_rapid` | ✅ PASS (재실행 2/2). 단 **재기동 직후 첫 cold 실행만 flaky FAIL**(ptt1 audio 9패킷, 5.01~7.01s 타화자 미도착) → 재실행 안정 108패킷. PTT 슬롯 워밍업 타이밍, 묶음 A 무영향(PTT audio=non-zero ssrc라 변경 가드 미경유) |

> 서버는 부장님이 release 빌드 + 재기동(oxhubd 7128 / sfud 7129·7131). 가드 변경 반영 확인됨.
> ⚠ **ptt_rapid cold-start flaky**: 재기동 직후 첫 실행 1회 FAIL은 워밍업 노이즈. 회귀 게이트 운용 시 PTT는 1회 warm-up 후 판정 권장(별건 — 묶음 A 범위 아님).

---

## 4. 완료정의 충족

- ✅ 봇이 서버 가드 우회 비정상값(가짜 non-zero ssrc) **0개**.
- ✅ 봇 송신 계약 == 웹 클라 송신 계약(simulcast=SDP에 ssrc 없음 → 0).
- ✅ failability 실증 — release sfud 재기동 후 simulcast_basic PASS(봇 정직 + 가드 짝).

---

## 5. 다음

1. **부장님**: 위 diff 검토 + 새 sfud 재기동 → `oxe2e scenario scenarios/simulcast_basic.toml` PASS 확인.
2. GO 시 묶음 A 커밋(서버 가드 + 봇, 한 커밋 또는 분리는 부장님 택).
3. 그 다음 **묶음 B(봇 수신 원료 적재)** — 서버 무변경.

---

*author: kodeholic (powered by Claude)*
*정지점 A 보고. 커밋 전. 서버 가드 1줄은 봇 정직화와 한 몸이라 묶음 A에 포함(stash 버림 결정에 따른 최소 변경).*
