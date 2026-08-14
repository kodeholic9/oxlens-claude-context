---
kind: task
status: open
opened: 20260814
closed:
refs: [202608/20260814b_mcptt_kpi_sctp_datagram_task.md, PROJECT_SERVER.md]
---
# SCTP association 누수 — 봇 소멸 후에도 무한 재전송(peer·태스크 동반 누수)

> 발굴: 김과장(Claude Code) / 일자: 2026-08-14 / **원인 확정, 수리 미착수**
> 부장님 지시: *"누수건 전반에 대해서만 사실 위주로 정리하고, 새 세션에서 진행."*

---

## 지침

1. 이 문서는 **사실 위주**다. 추측과 실측을 명확히 갈라 적는다.
2. 범위는 **누수 전반**. 같은 날 수리한 SCTP datagram 결함(20260814b)과는 별건이다.
3. **새 세션에서 이어받아 진행한다.** 재현이 상시 가능하고(아래 §재현) 소스 좌표가 확정돼 있다.

---

## 실측 사실

### F1. 좀비 association 4개가 60초 간격으로 무한 재전송 중

`oxsfud.log.sfu-{1,2}.2026-08-14` 실측(19:40 시점 기준 전부 생존):

| TSN | 최초 재전송 | 최종 관측 | 경과 |
|---|---|---|---|
| 4029050564 | 18:17:13 | 19:40:18 | **83분+** |
| 3274823619 | 18:33:20 | 19:40:24 | 67분+ |
| 1627924200 | 19:03:51 | 19:30:54 | 27분+ |
| 3803080600 | 19:13:05 | 19:40:08 | 27분+ |

- 같은 TSN·같은 SSN 을 반복 재전송. `n_rtos` 가 **78** 까지 증가.
- RTO 가 최대치(60s)로 백오프된 상태로 **영구히** 반복. 재전송 상한이 없다.
- 봇 프로세스는 이미 종료됨(`pgrep -f oxe2epy` = 0).

### F2. 루프 종료 조건이 두 개뿐이고 둘 다 UDP 에선 안 온다

`crates/oxsfud/src/datachannel/mod.rs` `run_sctp_loop`:

```rust
tokio::select! {
    result = Conn::recv(dtls_conn, &mut buf) => {
        Ok(0) | Err(_) => { break; }      // ① DTLS recv 종료/에러
    }
    _ = timer.tick() => { assoc.handle_timeout(now); ... }   // 50ms 주기
    Some(pkt) = dc_rx.recv() => { ... }
}
if association_lost { break; }             // ② SCTP 스스로 끊김 판단
```

- **UDP 라 상대가 사라져도 `recv` 는 에러가 아니라 영원히 pending.** ① 미발동.
- 상대가 SCTP SHUTDOWN 을 안 보내면 association 은 살아있다고 믿는다. ② 미발동.
- 그 사이 50ms 타이머 arm 이 계속 돌며 `handle_timeout` → 재전송을 반복한다.

### F3. 취소 경로가 없다 — peer 회수 신호가 루프에 닿지 않는다

```rust
pub async fn run_sctp_loop(
    dtls_conn, peer, room_hub, peer_map, socket,   // ← CancellationToken 인자 없음
)
```

- 다른 백그라운드 태스크(`run_floor_timer` · `run_zombie_reaper` · `run_stalled_checker` ·
  `run_active_speaker_detector`)는 **전부 `cancel: CancellationToken` 을 받는다.**
  이 루프만 안 받는다.
- spawn 지점은 `crates/oxsfud/src/transport/udp/mod.rs:535` **한 곳**.
- 즉 reaper 가 peer 를 회수해도, 방을 떠나도, ws-cut 이 나도 이 루프는 모른다.

### F4. 누수 범위가 SCTP 에 그치지 않는다

- `run_sctp_loop` 은 `.await` 로 호출된다(udp/mod.rs:535) → **루프가 안 끝나면 그 위
  transport 태스크도 안 끝난다.**
- 루프가 `Arc<Peer>` 를 보유 → **peer 객체가 안 죽는다.** peer_map 에서 제거돼도 참조 잔존.
- 죽지도 않고, 60초마다 일까지 한다.

### F5. 생성 계기는 아직 특정 못 함 (★가설 아님, 미확정)

- 좀비 생성 시각 4건은 모두 **run-all 실행 구간** 안이거나(18:33, 19:03, 19:13)
  `ptt_join_talk` 검증 구간(18:17)이다.
- **`adv_floor_failover`(급사 `kill()` 연출) 가설은 실험으로 기각**:
  단독 실행 후 90초 관측에서 신규 좀비 0개(기존 4개만 계속 재전송).
- rep_1 기준 역산 시 생성 시점이 스위트 35번째 근처 = `ptt_*` 계열 구간이나,
  **어느 시나리오인지 확정 안 됨.**

---

## 재현

**지금은 서버에 이미 4개가 살아 있어 즉시 관측 가능하다.**

```bash
grep -hoE "retransmitting tsn=[0-9]+" oxsfud.log.sfu-*.2026-08-14 \
  | sort | uniq -c | sort -rn | head
```

서버를 재기동해 초기화한 뒤 다시 만들려면 `run-all` 1회면 된다(4회 실행에서 4개 생성, 회당 1개).
**단, 생성 계기 시나리오가 특정되지 않았으므로 단일 시나리오로는 재현이 보장되지 않는다.**

### ★ 서버 로그 설정 주의

부장님 실행: `RUST_LOG=sctp_proto=trace target/release/oxhubd`
→ **sctp_proto 만 켜지고 oxsfud 로그는 전부 꺼진다.** 실측: 18시 이후 oxsfud 모듈 로그 0줄,
WARN/ERROR 도 0건(15시 240건·17시 68건과 대조). 이 때문에 같은 시간대의 다른 결함
(20260814b §미결 1 seq 결손)은 사후 추적이 불가능해졌다.

**다음부터는 기본 레벨을 같이 준다:**
```bash
RUST_LOG=info,sctp_proto=trace target/release/oxhubd     # oxsfud INFO/WARN/ERROR 보존
RUST_LOG=oxsfud=debug,sctp_proto=trace                   # 더 파야 할 때
```

---

## 수리 방향 (미착수 — 설계부터 볼 것)

1. **`run_sctp_loop` 에 `CancellationToken`** — peer 회수 경로(reaper · ROOM_LEAVE · ws-cut)에서
   발동. 다른 태스크가 이미 같은 패턴이라 이식할 형태가 있다. **근본 수리.**
2. **안전망: 재전송 상한** — `n_rtos` 임계 초과 시 association 포기.
   `sctp-proto 0.9` 에 `max_retransmits` 상당 설정이 있는지 확인 필요(미확인).
3. ICE consent 실패를 감지하는 곳이 이미 있다면 그 신호를 DC 루프로 전파.

1 이 근본, 2 는 1 이 새는 경우의 이중 안전망.

**주의**: peer 생명주기를 건드리므로 잘못 넣으면 **정상 세션을 조기 종료**시킨다.
착수 전 (a) 어떤 이벤트를 종료 신호로 삼을지, (b) 그 이벤트가 정상 통화 중에는 절대
발생하지 않는지 확인이 선행돼야 한다.

---

## 상용 파급

클라가 비정상 종료하면(브라우저 강제 종료, 망 단절, 앱 킬) UDP 라 FIN 이 없어 서버가
감지하지 못하고 **association·transport 태스크·peer 객체가 영구 잔존**한다.
장기 운영 시 축적된다. 오늘 4시간 남짓 시험에 4개가 쌓였다.

---

## 새 세션 이식성

이어받아 진행 가능하다. 근거:
- 원인이 소스 좌표로 확정됨(F2·F3·F4 — 파일·함수·줄 명시)
- 재현이 상시 가능(§재현). 재현을 기다릴 필요가 없다
- 미확정 항목(F5 생성 계기, 수리안 2의 설정 존재 여부)이 명시돼 있다
- 선행 확인 사항(수리 주의)이 적혀 있다

**착수 순서 권고**: F5(생성 계기 특정) → 수리안 1 설계 → 구현 → run-all 로 정상 세션
조기 종료 없음 확인.
