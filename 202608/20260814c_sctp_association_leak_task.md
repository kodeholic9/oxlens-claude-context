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

## ★ 근본 수리 설계 (20260815 확인 — 다음 세션 착수분)

**부장님 지적: "계속 땜빵만 하고 있는 전형적인 그 패턴."** 맞다. `253df78`(ufrag 축출)은
누수를 남긴 채 충돌만 피한 것이고, 근본은 손대지 않았다. 아래가 근본이다.

### 결정적 사실 — 세션을 지우면 태스크가 스스로 죽는다

`transport/demux_conn.rs` `DemuxConn::recv`:
```rust
match rx.recv().await {
    Some(data) => { ... }
    None => Err(webrtc_util::Error::Other("dtls rx channel closed".into())),
}
```
**tx 가 drop 되면 recv 가 에러를 반환한다.** 그리고 매달린 두 루프의 종료 조건이 정확히 그것:
- sub keepalive: `Ok(0) | Err(_) => break`
- pub `run_sctp_loop`: `Ok(0) | Err(_) => { break; }`

즉 `dtls_map` 엔트리를 제거하면 → tx drop → recv 에러 → **루프 종료 → 태스크·Arc<Peer> 해제**.
어제 제안한 "CancellationToken 을 peer 생명주기에 엮는" 큰 작업이 **불필요할 수 있다.**

### 수리안 (단순): `remove_stale()` 에 유휴 판정 추가

```
현재:  tx.is_closed()                  → 태스크가 죽어야 지움  (순환 의존 — 그래서 영영 안 지워짐)
추가:  마지막 STUN 수신 후 N초 경과     → 지움 → tx drop → 태스크 종료
```
- 마지막 STUN 시각은 서버가 이미 안다(`latch+response (keepalive)` 경로). `DtlsSessionEntry` 에
  `last_stun: Instant` 를 두고 STUN 처리에서 갱신하면 된다.
- `remove_stale()` 은 이미 1000패킷마다 호출되므로 호출 지점을 새로 만들 필요가 없다.
- 정상 클라는 ICE consent(keepalive STUN)를 계속 보내므로 **조기 종료 위험이 낮다.**
  RFC 7675 consent freshness 와 같은 발상 — 표준적이다.
- N 값은 미정. WebRTC 관행(consent 30s 간격) 고려해 60s 안팎이 후보. **실측 후 결정.**

### 착수 전 확인 사항

1. `last_stun` 갱신 지점이 keepalive STUN 을 실제로 다 받는가(`latch_changed=false` 분기 포함).
2. pub PC 는 SCTP 루프가 `Conn::recv` 를 `select!` 안에서 쓴다 — tx drop 이 그 arm 을
   깨우는지 확인(sub 은 직접 recv 라 명확).
3. 조기 종료 회귀: run-all 43종 + 장시간 유휴 시나리오에서 정상 세션이 안 끊기는지.
4. 성공하면 **`253df78`(ufrag 축출) 은 걷어낼 수 있는지** 재검토 — 근본이 고쳐지면
   포트 재사용 잔재 자체가 안 생긴다. 다만 축출은 이중 안전망으로 남길 여지도 있다.

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

---

## 진행 · 20260815 01:00 — ★같은 뿌리의 **세 번째 증상** 발견·차단 (포트 재사용)

이 누수는 SCTP 좀비 하나가 아니었다. **정리 안 되는 태스크 하나가 세 증상을 만든다.**

| # | 증상 | 상태 |
|---|---|---|
| ① | SCTP association 좀비 — 60초마다 무한 재전송 | 미수리 |
| ② | transport 태스크 + `Arc<Peer>` 누수 | 미수리 |
| ③ | **DTLS 포트 재사용 → 신규 연결 영구 차단** | **증상 차단(`253df78`)**, 근본 미수리 |

### ③ 발견 경위

soak run 2·3 이 `adv_loss` 에서 중단(5회 중 2회 = **40%**). 신설 진단이 지점을 지목했다:
```
ice_state=completed nominated=1 check_done=True / dtls_state=connecting → WantReadError
```
ICE 는 성공인데 서버가 DTLS 를 **시작조차 안 했다.** 포트 이력이 답이었다:
```
:58276  22:37 listenC sub → USE-CANDIDATE → handshake OK → SRTP ready
        23:32 botB    sub → latch+response 만
        00:08 botB    pub → latch+response 만   ← 실패
```
`dtls_map` 키가 SocketAddr 뿐이고 판정이 `!has(&remote)` 라, OS 가 옛 세션의 소스 포트를
새 클라에 배정하면 서버가 "이미 있음"으로 보고 USE-CANDIDATE 를 무시한다.

### 왜 옛 엔트리가 안 지워지나 = ①②와 같은 뿌리

`remove_stale()` 은 `entry.tx.is_closed()` 로만 지운다. 그 tx 를 쥔 태스크가 안 끝난다:
- pub = `run_sctp_loop` (F2 — recv 에러 / association_lost 로만 종료)
- sub = keepalive 루프 `match dtls_conn.recv(..) { Ok(0)|Err(_) => break }`
**둘 다 UDP 라 상대가 사라져도 그 조건이 안 온다.**

### 수리(증상 차단만)

`253df78` — 엔트리에 ufrag 를 실어 세션 동일성 판정(`has_live` / `evict_conflicting`).
키는 SocketAddr 유지(**바꿀 수 없다** — DTLS 레코드에 ufrag 가 없어 `inject` 가 주소로만 라우팅).
진입 두 경로(STUN USE-CANDIDATE / DTLS 선도착) 모두 반영, ufrag 출처 동일성 확인
(`register_session(&peer, &peer.publish.media.ufrag, ...)` ↔ `session(pc).ufrag`).
축출 시 tx drop 으로 매달린 태스크 정리도 유도된다. 단위 시험 3종 신설.

**근본은 그대로다** — 루프가 안 끝나는 한 ①②는 계속되고, ③도 축출로 덮을 뿐이다.

### ★ 그래서 미결이 느는 게 아니다

겉보기엔 후보가 늘지만 **①②③이 한 뿌리**다. `run_sctp_loop`/keepalive 루프에
종료 경로(수리안 1: CancellationToken)를 넣으면 **셋이 동시에 사라진다.**
수리 우선순위가 올라갔다 — ③은 실사용 직격(클라 재접속 시 연결 자체 실패)이기 때문이다.

---

## 진행 · 20260814 20:16 — F5 자료 수집 중

seq 결손 빈도 측정 soak(20260814b §미결 1-②)이 돌면서 **좀비 생성 자료도 같이 쌓인다.**
서버를 로그 켜고 재기동해 **좀비 0 기준선**에서 출발했으므로, run-all 30회 동안
몇 개가 생기는지 = 회당 생성률이 그대로 나온다.

확인:
```bash
grep -hoE "retransmitting tsn=[0-9]+" ~/repository/oxlens-sfu-server/oxsfud.log.sfu-*.2026-08-14 \
  | sort -u | wc -l                    # 누적 좀비 개수
```
회당 1개가 유지되면 F5 는 "run-all 안의 특정 시나리오"로 좁혀지고, 회차별 생성 시각을
`soak_*/summary.txt` 의 회차 시각과 대조하면 **어느 시나리오 구간인지** 특정된다.

---

## 진행 · 20260815 07:50 — ★「단순 수리안」의 전제가 틀렸다 (소스 재검증 + 스핀 실측)

부장님 지시: *"정확한 원인 분석이 중요해."* 위 §★근본 수리 설계를 착수 전에 소스로 재검증했다.
**전제 두 개가 사실과 다르다.** 위 절은 R3(append-only)에 따라 고치지 않고 여기서 정정한다.

### 정정 1 — 두 루프 다 `DemuxConn` 이 아니라 `DTLSConn` 을 읽는다

| 루프 | 좌표 | 읽는 대상 |
|---|---|---|
| pub SCTP | `datachannel/mod.rs:116` `Conn::recv(dtls_conn, ..)` | **DTLSConn** |
| sub keepalive | `transport/udp/mod.rs:579` `dtls_conn.recv(..)` | **DTLSConn** |

위 절의 *"sub 은 직접 recv 라 명확"* 은 틀렸다. `DemuxConn` 은 두 루프 어디에서도 직접 읽히지
않고 **DTLS 내부 reader 태스크**만이 읽는다.

### 정정 2 — tx drop 은 루프를 못 깨운다. 대신 **코어를 태운다**

`dtls-0.17.1` 원본 좌표 3개가 결론을 확정한다.

```
conn/mod.rs:786   let n = next_conn.recv(buf).await?;      ← 우리 DemuxConn. 채널 닫히면 즉시 Err
conn/mod.rs:403   if Error::ErrAlertFatalOrClose == err { break }   ← 그 외 에러는 trace 만 찍고 재호출
error.rs:154      Util(#[from] util::Error)                ← "dtls rx channel closed" = Error::Util
```

우리 에러는 `Error::Util` 이라 :403 의 등식이 성립하지 않는다 →
**reader 가 `read_and_buffer` 를 무한 재호출하는 busy loop 로 들어간다.**
그리고 reader 가 안 끝나므로 `decrypted_tx` 도 안 떨어져,
`read()`(conn/mod.rs:443)의 `decrypted_rx.recv()` 는 **영원히 pending** — 두 루프 다 안 깨어난다.

> 즉 `remove_stale()` 에 유휴 판정만 넣으면 **좀비가 사라지는 게 아니라 좀비 1개가 스핀 1코어로
> 바뀐다.** 현재 좀비 7개 → 코어 7개.

### 실측 — sfu-2 는 지금 이 스핀을 돌리고 있다

`2026-08-15 07:39~07:47`, soak 진행 중 관측:

| | sfu-1 (pid 79734) | sfu-2 (pid 79736) |
|---|---|---|
| CPU time / 경과 | 1:06 / 6:34:16 | **73:34** / 6:34:16 |
| 현재 %CPU | 0.4 | **103.8 ~ 111.0** |
| `ps -M` | 실행 스레드 0 | **1 스레드 R, 99.3%** |
| `sample` 최상위 스택 | 해당 없음(0건) | `DTLSConn::new::{{closure}}` → `DemuxConn::recv` **1031 samples** |

**CPU 회계가 축출 시각과 맞는다.** sfu-2 축출은 `04:36:12.365`(botA pub, `:64522`) 1건.
그 이후 벽시계는 3h11 이지만 맥이 반복 절전 중이라 **각성 누계는 68.6분**(`pmset -g log` 로 산출).
관측된 CPU 73:34 와 같은 규모다 = **각성 중 사실상 100% 점유**. 차이 ~5분은 정상 미디어 처리분
+ 구간 추정 오차.

### 왜 sfu-1 은 멀쩡한가 — 축출이 항상 스핀을 낳지는 않는다 (원인 미확정)

축출 2건의 **대상 이력**이 다르다.

| | sfu-2 04:36:12 | sfu-1 06:17:04 |
|---|---|---|
| 축출된 옛 세션 | botS **pc=sub, 01:16:15** 생성 (3h20 전) | botA **pc=sub, 06:16:58** 생성 (**6초 전**) |
| 그 세션의 주인 | 이미 사라진 봇(close_notify 없음) | 같은 run 의 같은 봇 |
| 결과 | **스핀** | 스핀 없음 |

**가설(미확정)**: 옛 세션이 **정상 종료된 뒤 아직 `remove_stale` 이 안 걷어간 엔트리**였다면
(tx 는 이미 closed) 축출은 무해하다. 살아서 매달린 엔트리를 축출할 때만 스핀이 생긴다.
sub keepalive 종료는 `udp/mod.rs:598` trace 라 현재 로그로는 사후 확인 불가 —
**확인법**: 그 종료 지점을 debug 로 승격하거나 카운터를 붙인다.

### ★반대 증거 — 정상 종료 경로는 이미 완벽히 작동한다

`conn/mod.rs:447~460`: decrypted 채널이 닫히면 `read()` 는 **`Err(ErrAlertFatalOrClose)`** 를 낸다.
그래서 상대가 close_notify 를 보내면 reader break → 채널 닫힘 → 두 루프 모두 `Err(_) => break`.
실측(sfu-2 `06:22:47.162`): `ROOM_LEAVE user=botADV` → 같은 ms 에 `[DC] SCTP loop ended`
(`datachannel/mod.rs:197`). **좀비는 close_notify 없이 사라진 peer 에서만 생긴다.**

### 수리 방향 재확정

1. **유휴 판정 단독 = 금지.** 좀비를 스핀으로 바꾼다(위 정정 2).
2. **수리안 1(CancellationToken)이 여전히 근본이고, 이제는 유일한 경로다.**
   취소 → 루프 `break` → `Arc<DTLSConn>` drop → `reader_close_tx`(conn/mod.rs:325) drop →
   reader 의 `reader_close_rx.recv()` 가 `None` 으로 완료 → **reader break**.
   `DTLSConn` 에 `Drop` 구현은 없지만 **sender drop 만으로 성립한다**(원본 확인).
3. **유휴 판정(`last_stun`)은 폐기가 아니라 "취소 트리거"로 쓴다.** 지우는 주체가 아니라
   `cancel.cancel()` 을 호출하는 주체다. 제거는 그 뒤 tx closed 를 보고 기존 `remove_stale` 이 한다.
4. **`253df78`(ufrag 축출) 재평가**: 증상 차단은 유효하나 **살아 있는 엔트리를 축출하면 스핀이
   남는다.** 취소 경로가 들어간 뒤에는 축출도 `cancel → 제거` 순서로 바꾼다. 걷어내는 게 아니라
   **순서를 고친다.**

### 착수 전 확인 (갱신)

| # | 항목 | 상태 |
|---|---|---|
| 1 | `last_stun` 갱신점이 keepalive STUN 을 다 받나 | **확인** — `udp/mod.rs:426~450` 도달. 조기 return 은 unknown ufrag(:404)·integrity 실패(:433) 뿐. `peer.last_seen`(:420)은 이미 매 STUN 갱신 |
| 2 | tx drop 이 pub 의 `select!` arm 을 깨우나 | **확인 — 아니오.** 위 정정 2 |
| 3 | 조기 종료 회귀(run-all 43 + 장시간 유휴) | 미확인 |
| 4 | `253df78` 존치 여부 | 위 4번으로 대체 — 존치하되 순서 수정 |
| 5 | **(신규)** `Arc<DTLSConn>` 이 취소 시 실제로 drop 되나 = 유일 소유인가 | 미확인. `udp/mod.rs:568`(pub)·`:579`(sub) 두 소비처가 같은 Arc 를 쓴다 |

### 확인 #5 통과 + 취소 배선 좌표 (소스 확인, 코드 미변경)

**#5 = 통과.** `dtls::accept_dtls` 는 `Result<DTLSConn, _>`(`transport/dtls.rs:74`) —
**Arc 가 아니라 소유값**이다. spawn 태스크의 지역변수이므로 루프가 break 하고 태스크가 끝나면
`DTLSConn` 이 drop 되고, 그 안의 `reader_close_tx` 가 떨어지며 reader 가 종료된다.
Arc 공유가 없어 취소 한 방이면 전부 풀린다.

**단, F3 의 *"다른 태스크가 이미 같은 패턴"* 은 그대로 못 쓴다.** 기존 `CancellationToken`
(`lib.rs:252`)은 **서버 종료용 1개**를 4개 백그라운드 태스크가 공유하는 형태다(`tasks.rs:32/120/265/345`).
필요한 건 **peer 생명주기 토큰**이라 새로 둬야 한다.

**배선 지점은 사실상 한 곳이다.** peer 회수 3경로가 전부 같은 모양(`unregister_session` +
`endpoints.remove(user_id)`)으로 끝난다:

| 경로 | 좌표 |
|---|---|
| reaper | `domain/peer_map.rs:277~284` |
| ROOM_LEAVE | `signaling/handler/room_ops.rs:449~456` |
| ws-cut(leave helper) | `signaling/handler/helpers.rs:678~685` |

→ 토큰을 `Peer` 에 두고 **`PeerMap::remove()`(peer_map.rs:98) 안에서 한 번 취소**하면 세 경로가
모두 덮인다. 콜백 주입 없이 직접 호출이다.

**★그리고 이게 유휴 판정보다 먼저다.** F4 대로 **좀비들은 이미 reaper 가 peer_map 에서
걷어간 뒤**였다 — 루프만 그 사실을 몰랐을 뿐이다. 즉 `remove()` 취소 하나로 관측된 좀비 4~7개는
전부 잡힌다. `last_stun` 유휴 판정은 **peer 가 영영 회수되지 않는 경우**(WS 는 살아 있는데
미디어만 사라진 상태)에만 필요한 2차 안전망이므로, 1차를 넣고 재측정한 뒤에 결정한다.

### 구현 · 20260815 08:15 — 서버 `4b8aeb2` (단위 통과, 2층 게이트 잔여)

부장님 "진행해" 사인. 위 설계 그대로 넣었다. **영향 범위 4파일 / +155 −20.**

| 변경 | 좌표 |
|---|---|
| `MediaSession.transport_cancel` 신설 + `transport_cancel()` / `cancel_transport()` | `domain/peer.rs` |
| `Peer::cancel_transport()` — PC pair 둘 다 | `domain/peer.rs` |
| `PeerMap::remove()` 가 취소 (회수 3경로 수렴점) | `domain/peer_map.rs:98` |
| `run_sctp_loop(.., cancel)` + `select!` 취소 arm | `datachannel/mod.rs:84,116` |
| sub keepalive 루프를 `select!` 로 전환 + 취소 arm | `transport/udp/mod.rs:579` |
| `DtlsSessionEntry.cancel` + `evict_conflicting` **취소 먼저, 제거 나중** | `transport/udp/mod.rs:83,116` |

**현재 동작**: peer 가 회수되면(reaper 5s 틱 / ROOM_LEAVE / ws-cut) 두 루프가 즉시 break →
태스크 종료 → `DTLSConn` drop → reader 종료. 포트 재사용 축출도 tx 를 떨어뜨리기 전에 취소를
켜므로 스핀이 남지 않는다.

**트레이드오프**: 정리 시점이 reaper 틱에 묶인다(무접속 소멸 시 최대 그 주기만큼 지연).
대신 정상 통화 중에는 `remove()` 가 호출되지 않아 **조기 종료 위험이 구조적으로 없다** —
유휴 판정(last_stun) 방식보다 안전한 축이다.

**안전 근거**:
- 단위 **280 통과**(0 실패). 신규 3종 — `evict_cancels_before_drop` /
  `peer_map_remove_cancels_transport` / `peer_map_lookup_does_not_cancel`(조회·재사용·타 유저
  회수로는 취소 안 됨 = 조기 종료 가드).
- take-over 경로 확인: 모드 불일치·2003 재-JOIN 모두 `remove` 후 **새 Peer 재생성**
  (`room_ops.rs:174,214`, 기존 시험 `!Arc::ptr_eq` 단언) → 취소된 토큰이 재사용되지 않는다.
- `cargo check --workspace --all-targets` 무경고.

**잔여**: 2층 `run-all` 43종 + 좀비 0 확인. **soak(N=30) 종료 후** — 지금 돌리면 표본이 깨진다.
release 바이너리는 08:15:28~08:15:48 에 재빌드(nice -19, -j3)했다. 돌고 있는 서버 프로세스는
그대로이므로 soak 표본에 영향 없다(재기동해야 새 바이너리가 뜬다).

### F5 갱신 — 좀비 생성률은 "회당 1개"가 아니다

soak(20260815 01:10 기동, N=30) 기준선 5 → run 1 에서 6 → run 10 에서 7.
**11회에 +2 = 0.18/run.** 종전 근거(4회/4개)는 이 표본에서 반증됐다.
생성 계기 특정(F5)은 여전히 미결이고, 표본이 커진 만큼 `summary.txt` 회차 시각 대조가 더 쉬워졌다.
