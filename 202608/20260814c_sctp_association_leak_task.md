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
