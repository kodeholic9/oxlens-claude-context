# 완료 보고 — oxe2e Phase 2 (oxrtc 클라 DC 스택 + ptt_rapid)
> 작업 지침 ← [20260530_oxe2e_phase2](../claudecode/202605/20260530_oxe2e_phase2.md)

> 지침: `claudecode/202605/20260530_oxe2e_phase2.md`
> 설계: `design/20260530_oxe2e_design.md` §5-② / DC 설계서
> 선행: Phase 1 완료 (conf_basic 실측 PASS)
> author: kodeholic (powered by Claude)
> created: 2026-05-30

---

## 0. 요약

봇이 oxrtc 클라 DC 스택(SCTP→DCEP→MBCP)으로 floor(PTT)를 걸고 **ptt_rapid**(half-duplex
회전)를 약속↔이행 판정으로 돌린다. 정지점 3개 전부 실측 PASS. 서버 oxsfud DC **0 변경**.

| 정지점 | 실측 | 비고 |
|---|---|---|
| 1 — SCTP association | ✓ PASS | 최대 산, 첫 시도 수립(2회 룰 미발동) |
| 2 — DCEP unreliable 채널 | ✓ PASS | OPEN→서버 ACK |
| 3 — MBCP floor 왕복 + audio 이행 | ✓ PASS | ptt1/ptt2 granted 회전 + vssrc 이행 |

conf_basic 회귀 PASS(402/401). 서버 코드 0 변경 → 211 PASS 불변.

---

## 1. §0 대조 결과 (서버 받는 쪽 ↔ 봇 거는 쪽 거울)

- **SCTP**: `Endpoint::connect(ClientConfig::new(), remote)` → 서버 `run_sctp_loop` 와 동일
  Sans-I/O 루프(poll_transmit/handle/poll_timeout). SNAP 불필요(서버도 4-way). DTLS app data 위.
- **DCEP**: OPEN `[0x03|0x81|prio|reliab=0|label_len|proto_len|"unreliable"]`, 서버 ACK `0x02`. PPID Dcep=50/Binary=53.
- **MBCP**: DC frame `[svc=0x01|len(2BE)|payload]`, MBCP `[byte0:A|type4 | field_count | TLV...]`.
  FLOOR_REQUEST(type0) = PRIORITY + DESTINATIONS(count==1). Granted(type1) GRANTED_ID(id4).

---

## 2. 변경 (oxrtc DC 스택 = 본 작업 §2-1)

| 파일 | 내용 |
|---|---|
| `oxrtc/Cargo.toml` | `sctp-proto = "0.9"` (서버와 동일) |
| `oxrtc/src/dc/mod.rs` (신규) | `establish`(association) / `open_channel`(DCEP) / `spawn`(floor run task: cmd/event 채널) / `pump_once`/`drain`/`read_mbcp` |
| `oxrtc/src/dc/dcep.rs` (신규) | DCEP OPEN 빌더 + ACK 파서 |
| `oxrtc/src/dc/mbcp.rs` (신규) | MBCP 빌더(REQUEST/RELEASE/ACK) + 파서(Granted/Idle/Deny/Taken/Revoke) — byte-level |
| `oxrtc/src/dtls_client.rs` | `dtls_handshake_keep` — DTLSConn+recv task 유지(SCTP용) |
| `oxrtc/src/signal_client.rs` | `SignalSession.initial_tracks` — ROOM_JOIN 초기 tracks 보존 |
| `oxrtc/src/lib.rs` | `pub mod dc` |
| `oxe2e/src/bot/mod.rs` | `run_floor_bot` — pub PC(keep)+SCTP+DCEP+MBCP+half RTP, floor orchestration |
| `oxe2e/src/{config,main}.rs` | floor 상수, 정지점 3 판정(granted + audio 이행) |
| `scenarios/ptt_rapid.toml` (신규) | half-duplex 봇 2, floor 회전 |

빌더/파서 분리(§5) — oxtapd(미래)는 mbcp 파서만 재사용 가능.

---

## 3. 발견_사항

1. **half-duplex "PTT Unified Model"** (`track_ops.rs` HalfNonSim 분기) — half slot 트랙은
   PUBLISH_TRACKS 시 TRACKS_UPDATE(add)를 **보내지 않는다**(JOIN 시 SDP pre-allocate). slot
   vssrc 는 **ROOM_JOIN 응답 초기 tracks 에만** 실린다. full 과 약속 경로가 다름.
   - 그런데 oxrtc `connect_and_join` 이 ROOM_JOIN tracks 를 폐기하던 게 근본 원인 → `initial_tracks`
     보존으로 해결. floor 봇은 이를 vssrc 약속으로 시드.
2. **gate auto-resume**(5s)로 TRACKS_READY 없이도 fan-out 됨 — half 봇 RTP 수신 확인.

---

## 4. 판정 한계 (후속)

- **gating(비발화 미도착) 정밀검증 미구현** — 현재 정지점 3 PASS = floor 왕복 + granted 봇
  audio vssrc 이행까지. "비발화 봇 송신이 fan-out 안 됨"의 시간구간별 검산은 누적 카운터로는
  불가, subscriber 시간스탬프 기록이 필요. 설계 §6 full 판정 대비 한계 — 후속 토픽.
- admin 삼각검증은 Phase 1·2 범위 밖(설계 §9 ssrc 조회 경로 미정).

---

## 5. 실측

```
# 서버 기동(부장님) 후
RUST_LOG=warn ./target/debug/oxe2e scenario scenarios/ptt_rapid.toml
[oxe2e] ptt1: SCTP ✓ / DCEP ✓ / floor granted / 약속 2건 / 수신 139패킷
[oxe2e] ptt2: SCTP ✓ / DCEP ✓ / floor granted / 약속 2건 / 수신 108패킷
[oxe2e] ✓ PASS (정지점 3: MBCP floor 왕복 + audio 이행)

RUST_LOG=warn ./target/debug/oxe2e scenario scenarios/conf_basic.toml
[oxe2e] ✓ PASS (정지점 2: conf_basic 약속↔이행)   # 회귀 무사
```

---

## 6. 불변 확인

- 서버 crate(oxsfud/oxhubd/common) **0 변경** → 211 PASS 논리적 불변.
- oxrtc 변경(DC 스택 + initial_tracks + dtls keep)은 oxe2e 만 소비 → 외부 영향 격리.

---

*author: kodeholic (powered by Claude)*
