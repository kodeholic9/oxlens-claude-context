# 서버 운영 가이드 — AI용

> **invoke 키워드: `서버실행` / `config구성` / `실행가이드` / `서버운영` / `운영가이드` / `oxadmin`**
> — 이 단어가 나오면 이 가이드를 먼저 로드한다.
> oxhubd(hub) + oxsfud(sfud) 를 **어떻게 띄우고**(§0~§3) **어떻게 제어·관측하나**(§4 oxadmin) **검은화면/무음 격리(§4-D)**. cross-sfu(N sfu) 포함.
> author: kodeholic (powered by Claude)
> created: 2026-06-03 · 운영 CLI(oxadmin) 추가: 2026-06-13 · trace 평면(랩 전용) 추가: 2026-06-15 · user 실시간 진단(USER_PROBE) 추가: 2026-06-20 · 검은화면 격리 runbook(§4-D) 추가: 2026-06-20 · stat 연속 모니터(입체 분석, §4-S) 추가: 2026-06-23

---

## §0 큰 그림 (먼저 — 안 헷갈리게)

```
클라(브라우저/SDK) ──WS(시그널)──> oxhubd(hub) ──gRPC──> oxsfud(sfud) N개
                   <─UDP(미디어)──────────────────────────┘
운영자/개발자  ──REST(localhost)──> oxhubd(hub)  ←── oxadmin CLI (§4)
```
- **hub(oxhubd)** = WS 게이트 + REST + 라우팅 + sfu supervisor. 클라는 **hub WS** 로만 들어온다.
- **sfud(oxsfud)** = 미디어 SFU. **gRPC(hub↔sfud) + UDP(미디어)** 만 bind. **WS 안 띄움**(WS=hub 담당).
- cross-sfu: hub 가 sfu N개를 인지(registry)·연결(dial)·방 배치(room_sfu)·요청/이벤트 라우팅. (서버 control plane: 2026-06-03 Phase 0~2b 완성)
- **운영(제어·조회)** = hub 한 곳의 REST 에 붙는다. 손으로 칠 땐 **`oxadmin`(§4)**, 자동화는 raw REST(§5).

**bind 포트 (충돌 주의 = 실제 bind 되는 것만)**:
| | hub | sfud (인스턴스마다 달라야) |
|---|---|---|
| 실제 bind | WS/REST `[hub].listen`(1974) | **gRPC `grpc_listen`** + **UDP `udp_port`** |
| bind 안 함 | — | `ws_port`(과도기 잔재 — 추출만, listen 0). public_ip=광고값 |

→ sfu 를 N개 띄울 때 **반드시 다르게 줄 것 = grpc_listen + udp_port 둘뿐**. (`ws_port` override 불필요)

---

## §1 config 위치 / 로드 규칙

- config = **`system.toml`(static) + `policy.toml`(dynamic)**. (`.env` 폐기됨)
- 로드 디렉토리 = `--config-dir <dir>` 인자, **없으면 현재 작업 디렉토리(`.`)**.
- 즉 `cd ~/repository/oxlens-sfu-server && ./target/release/oxhubd` → `./system.toml` 읽음.
- **supervisor 가 spawn 한 sfud 자식은 hub 의 cwd 를 상속** → 같은 `./system.toml` 읽음(sfud 별 차이는 args override 로만).
- `system.toml` 직접 수정은 운영 행위 — 작업 지침/보고 맥락에선 **copy-paste 블록으로 제공, 적용은 부장님**. 부장님이 직접 "맞춰라" 지시 시에만 파일 편집.
- 미지 섹션(`[recording]` 등 oxtapd용)은 hub/sfud 가 **무시**(serde) — 무해.

---

## §2 config 두 계층 키 (헷갈리기 쉬운 핵심)

| 키 | 누가 읽나 | 뜻 |
|---|---|---|
| `[sfu]` (단수) | **sfud self** | sfud 자기 기동값(udp/ws/public_ip/grpc_listen). 멀티 시 = **sfud1 기준값** |
| `[[hub.sfu]]` (복수, array) | **hub registry** | hub 가 dial 할 노드 목록. **미설정 시 `[sfu]` 1-element("sfu-1") 폴백** = 단일 sfu |
| `[supervisor]` + `[[supervisor.units]]` | hub | hub 가 자식 프로세스(sfud 등) 자동 spawn/감시/재시작 |
| `[routing]` `placement` | hub | 방 배치 정책(default `round_robin`) |

> 1방 1sfu(room_id 전역 유일) 전제 — 모든 방은 ROOM_CREATE(멱등) 경유. default rooms 사전생성은 폐기(2026-06-03).

---

## §3 실행 패턴

### 패턴 A — 단일 sfu (가장 단순)
`[[hub.sfu]]`/`[supervisor]` 없이 `[sfu]`만. hub 는 폴백 "sfu-1" 로 `[sfu].grpc_listen` 1개 dial.
```bash
cd ~/repository/oxlens-sfu-server
./target/release/oxsfud        # 터미널 1 (50051/19740 bind)
./target/release/oxhubd        # 터미널 2 (1974, sfu-1=50051 dial)
```
순서 무관(hub lazy reconnect). hub 가 sfud 를 자동 기동하려면 `[supervisor]` 1 unit 추가(패턴 B 축소판).

### 패턴 B — 2 sfu (supervisor 자동 기동) ★ 표준
`oxhubd` **하나만** 실행 → supervisor 가 sfud 2개 spawn→ready→관리. cross-sfu 검증된 구성.

`system.toml` 에 추가할 블록 (`[hub.auth]` 뒤, `[sfu]` 앞에 `[[hub.sfu]]`; 끝에 `[supervisor]`):
```toml
# [hub.auth] 다음 — TOML 상 [[hub.sfu]] 는 [sfu]/[supervisor] 보다 앞에 와야 함
[[hub.sfu]]
id = "sfu-1"
grpc_listen = "127.0.0.1:50051"

[[hub.sfu]]
id = "sfu-2"
grpc_listen = "127.0.0.1:50052"
# (public_ip/udp_port/ws_port 는 Phase 3 클라 server_config 자리 — 지금 불요)

# ── 파일 끝 ──
[supervisor]
enabled = true

[[supervisor.units]]
alias = "sfud1"
enabled = true
execution = { type = "spawn", cmd = "<절대경로>/target/release/oxsfud", args = [] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50051", timeout_sec = 30 }
restart = "on-failure"
timeout_stop_sec = 10

[[supervisor.units]]
alias = "sfud2"
enabled = true
# ★ grpc + udp 만 override (ws_port 는 sfud 가 bind 안 함 → 불요)
execution = { type = "spawn", cmd = "<절대경로>/target/release/oxsfud", args = ["--grpc-listen", "127.0.0.1:50052", "--udp-port", "19741"] }
ready = { type = "grpc_connect", addr = "127.0.0.1:50052", timeout_sec = 30 }
restart = "on-failure"
timeout_stop_sec = 10
```
- `[sfu]` 는 sfud1 기준(grpc 50051/udp 19740) 그대로 둔다. sfud2 는 args 로 포트만 갈림.
- 실행: `cd ~/repository/oxlens-sfu-server && ./target/release/oxhubd`
- **Ctrl+C / `kill -TERM`** → hub 가 sfud 들에 SIGTERM → drain → 둘 다 graceful exit(좀비 0).

### sfud CLI override (cross-sfu Phase 0)
`--ws-port`(불요) / `--udp-port`(u16) / `--grpc-listen`(host:port) / `--public-ip`(str). 우선순위 **arg > system.toml > 자동감지**. 미지정 항목은 `[sfu]` 값.

### N(≥3) sfu
`[[hub.sfu]]` + `[[supervisor.units]]` 를 sfu 수만큼. 각 unit args = `--grpc-listen 127.0.0.1:5005N --udp-port 1974N`. (포트만 안 겹치게)

---

## §4 oxadmin — 운영 CLI ★ 손으로 칠 땐 이걸 쓴다

hub REST 위의 **단일 운영 CLI**. 제어(unit lifecycle / WS 끊기 / 좀비 퇴장)와 조회를 한 도구로.
**제어는 전부 supervisor 경유** — 셸 `kill -9` 로 sfud 직접 죽이면 watchout 이 backoff 로 되살려 의도가 꼬인다.

### 빌드 / 전제
```bash
cd ~/repository/oxlens-sfu-server
cargo build --release -p oxadmin     # → target/release/oxadmin
```
- **localhost 전용 자체 시험 도구.** hub 와 같은 머신에서 돈다. loopback 은 **무인증**(hub `verify_admin` 이 peer.is_loopback 이면 토큰 bypass) — 토큰 필요 없음.
- hub 주소 기본 `http://127.0.0.1:1974`. 포트가 다르면 `OXADMIN_URL` env 로만 바꾼다.
- 출력 = **사람이 읽는 표가 기본**. `--json` 이면 raw JSON(compact, jq 친화).

### 명령 일람 (4 평면)
```
oxadmin [--json] <command> [args]
```
| 평면 | 명령 | 동작 |
|---|---|---|
| **Unit**(supervisor) | `show` \| `list` | 자식 unit 상태 표 (alias/state/pid/uptime/restart/last_exit) |
| | `load <alias>` | Stopped/Down/Blocked → 재기동 (카운터 리셋) |
| | `stop <alias>` | graceful stop(SIGTERM escalation) → **Stopped**(watchout 재기동 안 함) |
| | `kill <alias>` | 즉시 SIGKILL → Stopped |
| | `shutdown` | hub 자신 포함 graceful shutdown (unit 먼저, hub 나중) |
| **SFU**(registry) | `sfus` | 라우팅 SFU 노드 목록 (sfu_id/addr/connected/방 수) |
| | `sfu <sfu_id>` | 그 SFU 의 방 목록 (per-sfu ROOM_LIST, 실제 상태) |
| **User**(hub-local) | `users` | 연결 클라(user) 목록 (conn_id/peer_addr/intents/rooms) |
| | `user <user_id>` | 특정 user **실시간 진단**(클라 pull, 3s) — 그 순간 브라우저 getStats/device/권한/element 를 송수신 파이프라인 블록으로 (§4-U) |
| | `stat <user_id> [--interval N]` | **iostat 식 연속 모니터**(클라 pull, N초마다 한 줄 Δ, 기본 2s, Ctrl+C). kind별 활성 스트림 자동선택, TIME(wall-clock)으로 **trace 와 입체 대조** (§4-S) |
| | `user-cut <conn_id\|user>` | WS 소켓 강제 close (transport 강제 끊김, 무통보 → 클라 reconnect 유발) |
| **Room**(sfud 경유) | `rooms` | 전체 방 목록 (room/sfu/user_count) |
| | `room <room_id>` | 참여자/recorder 표 + **trace 인자 카탈로그**(USER/DIR/KIND/SSRC — publish ssrc·egress vssrc). 더 깊은 raw 는 `--json` |
| | `reap <room_id> <user>` | 좀비 퇴장 강제 — 서버 일방 evict, **무통보** |
| **Trace**(sfud gRPC 직접) | `trace …` | 패킷 단위 in/out 진단 — **랩 빌드 전용**. hub 우회, §4-T 별도 |

> **상태 어휘**: `live`=정상 · `stopped`=의도적 정지(oxadmin stop/kill, watchout 무시) · `down`=비정상 종료(watchout 이 backoff 재기동) · `backoff`=재기동 대기 · `blocked`=영구조건(EADDRINUSE 등 — `load` 로만 복구).

### 끊는 3 종 — 레벨이 다르다 (혼동 금지)
| | `kill <alias>` | `user-cut <user>` | `reap <room> <user>` |
|---|---|---|---|
| 대상 | sfud **프로세스** | WS **transport(소켓)** | 방 **멤버십(application)** |
| 효과 | SIGKILL → Stopped | 소켓 강제 close | 방에서 서버 일방 제거(evict) |
| 클라 관점 | (서버 프로세스) | 연결 끊김 → reconnect | WS 살아있는데 방에서 사라짐 = 좀비 불일치 |

> reap ≠ kick(`POST .../kick` = ROOM_LEAVE 정상 퇴장) ≠ RECONNECT(graceful 재접속). reap 은 **무통보 좀비 evict** 전용.

### 예시 세션
```bash
OX=./target/release/oxadmin

$OX show                 # unit 상태 (3 unit live?)
$OX sfus                 # SFU 노드 + 각 방 수
$OX rooms                # 전체 방 (어느 sfu 에 있는지 SFU 컬럼)
$OX room qa_test_01      # 그 방 참여자/트랙
$OX users                # 연결 클라 + peer_addr
$OX user U01             # 실클라 U01 실시간 진단 (송수신 파이프라인 블록 §4-U. 봇은 USER_PROBE 미지원→timeout)

# 제어 (자체 시험: sfud 내렸다 올리고 클라 반응 관찰)
$OX stop sfud2           # → stopped (watchout 이 안 살림)
$OX load sfud2           # → 재기동 → live
$OX user-cut p2          # 봇 p2 소켓 강제 끊기 (reconnect 시험)
$OX reap qa_test_01 p2   # 좀비 퇴장 (불일치 감지 시험). reaped=true/false 정직 보고

# 자동화/jq
$OX --json sfus | jq '.sfus[] | select(.connected｜not)'   # 끊긴 sfu만
```

### show-* 셸 wrapper (커스텀 뷰)
`crates/oxadmin/examples/show-{units,ws}.sh` — `oxadmin --json … | jq … | column` 으로 정렬/필터한 커스텀 표 예시. 빠른 표는 `oxadmin <cmd>` 로 충분(내장).

---

## §4-U oxadmin user — 특정 user 실시간 진단 ★ (USER_PROBE, 20260620)

`oxadmin user <id>` → hub REST → **USER_PROBE_REQ unicast** → 그 user 브라우저가 *그 순간* 자기 상태를
긁어(getStats/device/권한/element/navigator) **USER_PROBE_REPLY** 회신(body `req_id` 매칭, 3s timeout).
oxadmin–hub–클라–hub–oxadmin 동기 요청-응답. 서버 스냅샷(`room`)이 아니라 **클라가 아는 모든 것**.
(wire: S→C 요청=Event 0x2701, C→S 응답=Request 0x1702 — wire ACK 와 application 응답 분리.)

### 출력 — 송신/수신 파이프라인 블록
`STATE / ENV / PERMISSIONS / NETWORK(candidate-pair RTT·BWE) / PUBLISH(트랙별) / SUBSCRIBE(트랙별, PTT slot 포함) / DEVICES`.
- 송신: **SOURCE**(media-source 카메라/마이크) → **ENCODER**(frames/keyframe/impl) → **SENT**(pkts/br/qL)
- 수신: **RECEIVED**(pkts/lost/fps) → **DECODER**(framesDecoded/kf/impl) → **PLAYOUT**(freeze/jb / audioLevel/conceal)
- **어느 줄 값이 0/없음이면 그 단계가 범인.** 송신측(예: U02) PUBLISH 와 수신측(U01) SUBSCRIBE 를 **양쪽 떠서 대조** = 검은화면/무음이 보내는 쪽인지 받는 쪽인지 격리.
- 전체 상세(transceiver/pipe/self_view/getSettings/jitterBufferMin 등) = `oxadmin --json user <id>`.

### ★ 이 도구의 결함 2개 — 모르면 환각한다 (20260620 김대리가 실제로 4~5회 당함, 적나라하게)
> §4-T★ trace 교훈과 같은 부류. **출력 한 장면을 믿고 단정하기 전에 이 둘부터 의심.** 도구는 멀쩡, 매번 AI 가 틀렸다.

1. **collectStats() 연속 호출 캐시 — `user` 를 빠르게 두 번 치면 *같은 스냅샷*(`lastPkt` 까지 동일).**
   - 클라 `transport.collectStats()` 가 연속 호출에 캐시값을 준다. 연속 2~3 회가 토씨까지 똑같다.
   - 김대리 사고: 이걸 "RECEIVED 정체 = 클라 미수신" 으로 오판 → "서버가 안 보낸다" 환각 → 부장 "2초 간격이면 카운터 올라간다" 로 박살. 실제론 정상 수신 중이었다.
   - 철칙: **delta 는 시간 간격(2초+)을 두고 별도로 칠 것.** 연속 호출 delta 는 무의미(캐시). *(미해결 — 다음: collectStats 캐시 TTL/우회.)*

2. **slot(ViaSlot) 의 `oxadmin room` PKTS = 0 은 거짓** — slot egress 가 `rtp_relayed` 카운터를 미집계.
   - room 표에서 PTT slot `--out PKTS=0` 이어도 **실제로는 흐르고 있다**(trace `egress_rtp pass` 로 확인됨).
   - 김대리 사고: PKTS=0 → "서버 fan-out 정지" 단정 2회 → trace egress pass 로 반증. slot 흐름은 **카운터 말고 `oxadmin trace <user> <slot_ssrc> --out` 로 실증.** *(미해결 — 다음: slot egress 를 rtp_relayed 에 연결.)*

> 종합(§4-T★ 와 동일 정신): **user/room 카운터 한 장면으로 단정 금지.** 흐름은 trace, 변화는 시간 간격 delta.
> 검은화면/멈춤 근본은 `kf(keyFramesDecoded)` 증가 여부 + trace IDR 로 **실증한 뒤** 말할 것 — 추측을 결론으로 포장 = 환각.

---

## §4-S oxadmin stat — iostat 식 연속 모니터 ★ (입체 분석, 20260623)

`oxadmin stat <id>` = `user` 와 같은 USER_PROBE pull 을 **N초마다 반복**, 매 샘플 **한 줄 Δ** 로 흘린다(기본 2s, Ctrl+C 종료).
`user`(2회 Δ 스냅샷)와 달리 **연속**이라, 증상이 *언제* 시작/회복하는지 시간축에 찍힌다.
**트랙 선택 불요** — kind별 활성 스트림(직전 구간 pps 최대)을 자동으로 잡고, 화자/슬롯이 바뀌면 따라간다.

### ★ 존재 이유 = trace 와 **동시** = 입체 분석
- **trace**(§4-T) = SFU 와이어(seq/ts/marker — 송출까지). **stat** = 클라 인코더/디코더/NetEq 내부(getStats). trace 혼자는 디코더 내부를 못 본다.
- 둘을 동시에 걸고 **TIME(wall-clock)** 으로 정렬 → "**SFU 와이어 ↔ 수신 NetEq**" 를 같은 시각으로 대조.
```bash
# 터미널 A — SFU 와이어 (그 방의 sfu 에)
oxadmin trace '*' '*' --inout --rtpdump /tmp/t.rtp --sfu sfu-1
# 터미널 B — 수신측 NetEq 3명 한 창에 (동일 TIME + USER 컬럼, 파일 tee)
oxadmin stat U01,U02,U03 --tee /tmp/stat.log
```
> 다중 user = 쉼표 구분. 한 틱에 N행(USER 컬럼)으로 같은 TIME → **한쪽만 jb 폭주(분산)** 즉시 비교.
> `--tee` = stdout + 파일 동시. 단일 user(`stat U01`)는 USER 컬럼 없이 종전대로.
> ★ stat 파일옵션은 `--tee`(구 `--out` — trace dir `--out`(egress)과 글자 충돌해 20260624 개명). trace 의 `--out`/`--in`/`--inout` 은 방향 플래그로 정상 사용.

### 컬럼 (Δ=구간증가분, /s=초당율, 순간=그 시점값)
```
TIME  rxA(src) pps lost disc jb jbT glch acc dec | rxV(src) fps kbps frz dec kf | txA txV
```
| 필드 | 정확히 | 정상 | 경보 |
|---|---|---|---|
| **rxA src** | 활성 수신오디오 track_id(자동) | `U02_..`(직접)/`ptt-R01-audio`(슬롯) | 자주 바뀜=화자전환 |
| **pps** | packetsReceived /s | opus=50 | 0=안받음·정체=끊김 |
| **lost** | packetsLost Δ | 0 | >0 손실 |
| **disc** | packetsDiscarded Δ (지터버퍼가 늦게/일찍 와 버린 패킷) | 0 | >0 타이밍미스 |
| **jb** | jitterBufferDelay 평균 **ms** = 실제 버퍼 깊이 | 40~80 | 급등·지속상승 |
| **jbT** | jitterBufferTargetDelay 평균 ms = NetEQ 목표 | jb가 추종 | 큼=지연늘림 |
| **glch** | (concealed−silent) Δ **샘플**, PLC합성(무음/DTX 제외). **48000=1초** | 0(steady) | ~1500≈30ms은폐·지속=가청끊김 |
| **acc** | removedSamplesForAcceleration Δ — 과적→빨리감기(압축) | 가끔 소량 | 폭증=피치출렁 |
| **dec** | insertedSamplesForDeceleration Δ — 부족→늘려끼움(신장) | 가끔 소량 | 폭증=느려짐 |
| **rxV src** | 활성 수신영상 track_id | `U02_..`/`ptt-R01-video` | |
| **fps** | framesPerSecond (**순간**) | 30 | |
| **kbps** | 수신 비트레이트(Δbytes×8/1000/s) | 가변 | |
| **frz** | freezeCount Δ | 0 | 누적=멈춤 |
| **dec**(영상) | framesDecoded Δ | ≈fps×초 | 정체=검은화면 |
| **kf** | keyFramesDecoded Δ | 가끔 1+ | |
| **txA / txV** | pub 오디오 pps / pub 영상 framesEncoded /s (=인코딩fps) | 50 / 30 | 0=송신정지 |
| **`~`**(예 `47ms~`) | lifetime 평균(구간 Δ 없음=pps0/정지) | — | 값 안 흐름 |
| **`-`** | 그 kind 활성 스트림 없음 | — | |

### 판독 패턴 (20260623 3인 PTT 실증)
- **수신 끊김 격리**: rxA glch↑/disc↑ 인데 **같은 시각 trace 슬롯은 깨끗(seq역행0·marker핸드오프)** → **와이어 아닌 디코더/다운링크 층** 확정.
- **돌림노래(분산)**: 같은 시각 **U01 vs U02 의 jb·glch 가 갈리면**(한쪽만 튐) 수신측 분산. 반대로 **양쪽이 비슷하게 같이 뜨면** 공통 상류 원인.
- **PTT 콜드스타트**: talk-spurt **시작마다** glch~1500(≈30ms) 반복·양쪽 공통 = 첫 음절 클립(예열 영역, 끊김 아님).
- **모드전환**: 화상→PTT 순간 직접 오디오 pps→0 + glch~9000(≈190ms) 1회 = 풀듀플렉스 컷오버(예상).

> §4-U/§4-T★ 와 동일 정신: **한 줄로 단정 금지.** 흐름은 trace, 분산은 **여러 수신측 동시 stat 비교**, 첫 음절 글리치는 콜드스타트로 분류. `lastPacketReceivedTimestamp` 는 시계 base 불신(쓰지 말 것) — 끊김 신호는 **pps Δ**.

### 캡처 3종 + 오프라인 NetEQ 재현 (20260624)

테스트 로그는 항상 **`~/repository/testlogs/<YYYYMM>/`**. 라벨(`<HHMM>_<NN>` 또는 시나리오)로 pcap·stat·event log 짝.

| 축 | 도구 | 누가 | 명령/방법 |
|---|---|---|---|
| 수신 NetEq jb(실측) | `oxadmin stat` | Claude(백그라운드) | `stat U01,U02,U03 --tee testlogs/<ym>/stat_<lbl>.log` (§4-S) — **getStats = ground truth** |
| SFU 와이어 송수신 | `tcpdump` | **부장님(sudo)** | `sudo tcpdump -i lo0 -s0 -w testlogs/<ym>/cap_<lbl>.pcap udp port 19740` (lo0=같은맥/en0=별기기, 19740=sfu-1·19741=sfu-2; src=19740 egress·dst=ingress; SRTP라도 RTP헤더 평문) |
| 수신 탭 실제 도착 | Chrome RTC event log | **부장님(UI)** | `chrome://webrtc-internals/` → "Create diagnostic packet recordings" → **"Enable diagnostic packet and event recording"** 체크 → 저장 base 지정 → 시험 → 체크 해제. PC마다 파일(큰 것=subscribe=수신). **헤더만**(payload 없음) |

**오프라인 NetEQ 재현** (`~/repository/webrtc-checkout/src/out/Default/neteq_rtpplay`, 빌드: `cd ~/repository/webrtc-checkout/src && ~/depot_tools/autoninja -C out/Default neteq_rtpplay`):
```bash
python3 -c "import struct,math;open('/tmp/rep.pcm','wb').write(b''.join(struct.pack('<h',int(2000*math.sin(2*math.pi*440*i/48000))) for i in range(480000)))"  # 더미PCM 1회
neteq_rtpplay --opus 111 --ssrc 0x<vssrc> --replacement_audio_file /tmp/rep.pcm --pythonplot --output_files_base_name=/tmp/ev <evlog_or_pcap> /tmp/ev.pcm
# /tmp/ev.py 의 target_delay_y / arrival_delay_y 파싱. ssrc=슬롯 vssrc(room snapshot/로그 switch_speaker).
```
> ★ **replay 절대값 신뢰 금지** (20260624 실증): 헤더만 로그→DTX 소실 過대예측 + replay 클럭 드리프트(arrival_delay가 단조 감소하면 아티팩트). **상대/메커니즘 가설용**이고, 결론은 **getStats(stat)** 로만. (도구 과신해 반복 오판한 전례.)

### webrtc 오프라인 도구 빌드환경 (neteq_rtpplay + video_replay 공통, 20260624 격리)
- **체크아웃** = `~/repository/webrtc-checkout/src` (`.gclient` 부모 격리 — 옛 `~/repository/src` 폐기). depot_tools = `~/depot_tools`.
- **빌드** = `cd ~/repository/webrtc-checkout/src && ~/depot_tools/autoninja -C out/Default <target>` (`neteq_rtpplay` / `video_replay`). 디렉토리 이동·clean 후 ninja 깨지면 `gn gen out/Default` 1회로 회복(재컴파일 아님, 수초).
- ⚠ **`video_replay --verbose` 패치는 `oxlens-tools` 브랜치(`9f19baf82c`)에만** — 빌드/디버깅은 이 브랜치 체크아웃 상태에서. `main`(upstream 추종)으로 돌아가면 패치 빠짐. push 안 함(로컬 보존).
- **video_replay** = egress RTP 오프라인 디코딩(검은화면 물증, jb/SR 타이밍은 못 봄). 사용법 상세 = `context/202606/20260622_republish_rewrite_fix_libwebrtc_videoreplay.md` + 메모리 project_libwebrtc.

---

## §4-T oxadmin trace — 패킷 단위 in/out 진단 ★ 랩 전용 (설계 20260615)

SFU 내부에서 특정 `user+ssrc` 의 RTP/RTCP 가 **ingress → (변환/gate) → egress** 까지 어떻게 흐르고
**어디서 죽는지**를 평문 전수로 떠내는 디버깅 탭. 다른 4 평면(hub REST)과 달리 **hub 우회 · sfud gRPC 직접 dial**
(고빈도 패킷이 hub 제어 평면을 오염시키면 안 됨). 서버는 원시(평문/암호문)만 토출 — **코덱·프레임 판별은 AI(김대리)**.

### ⚠️ 보안 — 빌드 경계
- trace = SRTP 복호 **평문 미디어**를 외부 스트림으로 뽑는 = **합법 도청 탭**. sfud `#[cfg(feature="trace")]` 로 격리.
- **현재 `oxsfud` default 에 trace 포함**(개발 편의, 2026-06-15) → `cargo build --release` 한 줄로 trace sfud 빌드됨.
  - **상용 진입 전 반드시** `crates/oxsfud/Cargo.toml` `default = []` 로 되돌릴 것 (deploy 가 `cargo build --release` 사용 → 안 빼면 도청 탭이 상용에 묻어 들어감).
- feature off sfud 상대로 `trace` 치면 `"trace disabled in this build"` 거부. oxadmin 은 feature 무관(항상 빌드).

### 사용법
```
oxadmin trace <user> <ssrc> <dir> [<user> <ssrc> <dir>] [--detail] [--bytes N] [--sfu <id>]
```
- `dir` = `--in` | `--out` | `--inout`. `ssrc` = 10진 또는 `0xHEX`. `user` = `'*'`(any — 모든 listener egress 매칭, PTT slot 용).
- 트리플 **1~2개**(순수 매칭 — "짝/경로" 의미는 도구 밖, 사람·AI 가 출력 보고 부여). 같은 타겟 다구독 OK(broadcast), **다른 타겟 동시 trace 는 reject**(단일 타겟).
- `--detail` = 원시 RTP/RTCP **hexdump** 동봉(미동봉 = simple 메타 한 줄). `--bytes N` = 원시 절단(0=통째).
- `--sfu` = multi-sfu 일 때 노드 지정(단일이면 자동). addr 은 oxadmin 이 `sfus` REST 로 획득 후 직접 dial.

### trace 인자 = `oxadmin room <id>` 카탈로그에서 집는다
`room <id>` 표 아래 **tracks 카탈로그**의 컬럼 순서 = trace 인자 순서(`USER SSRC DIR`).
**행 앞 3칸을 그대로 `oxadmin trace …` 뒤에 복붙**하면 된다(DIR 은 `--in`/`--out` 그대로).
```
tracks (행 앞 3칸 그대로 복붙 — `oxadmin trace <USER> <SSRC> <DIR>`):
USER  SSRC        DIR    KIND   NOTE
ptt1  0xA03E8C3A  --in   audio  half        ← 발화자 publish
ptt1  0xA5D8C694  --out  audio  ViaSlot     ┐ 둘이 같은 ssrc
ptt2  0xA5D8C694  --out  audio  ViaSlot     ┘ = PTT slot.virtual_ssrc
```

### 예시
```bash
OX=./target/release/oxadmin

# 1) 한 흐름 — 발화자 publish 들여다보기
$OX trace ptt1 0xA03E8C3A --in --detail

# 2) PTT 양 끝 — 송신 in + 수신 out(전 listener) 동시 (터미널 2개 권장)
$OX trace ptt1 0xA03E8C3A --in --detail              # 터미널 A
$OX trace '*' 0xA5D8C694 --out --detail              # 터미널 B (slot vssrc, any user)

# 3) 파일로 떨궈 AI 직독 (유닉스 파이프라인)
$OX trace ptt1 0xA03E8C3A --inout --detail > pkt.log  # → 김대리에게 붙여 분석
```

### 출력 — 6 trace point (SRTP 경계, 짝 보존)
`ingress_rtp`(unprotect 후 평문) · `ingress_rtcp` · `ingress_decrypt_fail`(원시=암호문) ·
`egress_rtp`(rewrite 후·protect 전, `origin_seq`=rewrite 전 원본 seq 동봉) ·
`egress_gate_drop`(=`GATE:<reason>`, **video full-track 한정** — PTT/audio 는 이 gate 안 탐) · `egress_rtcp`(SFU RR).
- simple 라인: `[wall_ts_us] DIR point result origin_seq`. detail = 그 밑에 hexdump.
- 짝 맞추기: 터미널 A `ingress_rtp` 의 seq(원시 헤더) ↔ 터미널 B `egress_rtp` 의 `origin_seq` 로 join.

### §4-T★ trace 삽질 교훈 — AI 가 실제로 반나절 까먹은 것 (김대리 20260620, 적나라하게)

> 아래 4개는 "trace 가 0 건이다 = 안 흐른다" 로 **잘못 단정**하게 만든 실제 사고들. trace 0 을 보면
> **결론 내기 전에 이 4개부터 의심**할 것. 도구는 멀쩡했고, 매번 사용자(AI)가 틀렸다.

1. **`--sfu` 노드 틀리면 조용히 0 건** (가장 많이 당함).
   - R01 이 재기동/배치로 **sfu-2 → sfu-1 로 이동**했는데 옛 `--sfu sfu-2` 를 그대로 박음 → 그 노드엔
     R01 이 없으니 trace 가 **에러 없이 0 건**. 이걸 "trace 도구가 half/slot 을 못 잡는다" 고 오판하고
     도구 결함 가설로 한참 헤맸다. **실제론 full publish 는 잘 잡혔고, sfu 만 틀렸다.**
   - 철칙: **trace 전 항상 `oxadmin rooms` 로 그 방의 SFU 컬럼 확인 → `--sfu` 거기에 맞춤.**
     room→sfu 는 1:1 이지만 **재기동마다 RoundRobin 으로 바뀐다.** 과거 세션의 sfu 를 기억해서 쓰지 말 것.

2. **ssrc 는 재기동·캠 토글마다 바뀐다 — 옛 ssrc 로 걸면 0 건.**
   - slot `virtual_ssrc` 는 **per-room random**(재기동마다 새 값). publisher ssrc 도 **캠 unpub→pub 마다 새 값**.
     이전 출력의 ssrc 를 복붙하면 현재와 안 맞아 0 건.
   - 철칙: **`oxadmin room <id>` 로 *지금* 신원표를 찍어 현재 ssrc 를 복붙.** 행 앞 3칸(USER SSRC DIR) 그대로.

3. **trace(현재 실시간) ≠ oadmin PKTS(누적) — 둘이 갈려도 trace 가 진실.**
   - `oxadmin room` 의 PKTS 는 **누적 카운터**(흘렀었던 총량), trace 는 **그 N 초의 실시간**.
     PKTS 가 5472 인데 trace 4 초가 0 일 수 있다(과거에 흐르고 지금 정지). 반대로 PKTS 가 안 늘어도
     "과거다" 라고 단정 금지 — **연속 2 번 `room` 찍어 PKTS 델타(증가?)로 현재 흐름 판정**하거나 trace 로 실증.
   - 김대리 사고: trace 0 + PKTS 값 있음 → "과거 누적" 단정 → 다음 순간 PKTS +224 증가(현재 흐름)로 박살.

4. **single-target 제약 — ingress 와 egress 동시 trace 는 reject.**
   - 다른 타겟(예: publisher ssrc `--in` + slot ssrc `--out`) 두 개를 동시에 걸면 두 번째가 reject.
     **한 발언에 하나씩**(또는 같은 타겟 broadcast). in/out ts 비교가 필요하면 발언을 나눠서 캡처.

> 종합: **trace 0 건 = "안 흐른다" 가 아니라 "내가 sfu/ssrc/타이밍을 틀렸을 확률이 먼저"**.
> `rooms`(sfu) → `room`(현재 ssrc) → trace 순으로, 매 발언마다 현재값을 다시 집어라.

---

## §4-D 검은화면 / 무음 격리 runbook ★ (증상 → 어느 단계가 범인)

> 증상 문장이 들어오면 **먼저 송신측/수신측을 식별**한다. 예: **"U01 에서 U02 영상이 안 나온다"**
> → **U02 = 송신측(publisher)**, **U01 = 수신측(viewer)**. ("A 에서 B 가 안 보인다" = B 송신·A 수신.)
>
> 절대 추측으로 단정하지 말 것. 파이프라인을 **[송신] SOURCE→ENCODER→SENT · [서버] ingress→egress ·
> [수신] RECEIVED→DECODER→ELEMENT** 로 끊어 **어느 단계 값이 0/정지인지** 본다. 그 단계가 범인.
> 모든 카운터는 **누적** — "지금 흐르는지" 는 trace(실시간) 또는 2초+ 간격 delta 로만 판정(§4-U/§4-T★).

### 0) 좌표 고정 (틀리면 이후 전부 헛다리)
```bash
oxadmin rooms              # 그 방 SFU 컬럼 → 이후 trace --sfu 는 무조건 여기 (함정 §4-T★ #1)
oxadmin room <room_id>     # 신원표에서 ↓ 두 인자를 *지금* 값으로 복붙 (재기동·캠토글마다 바뀜)
#   U02 video publish ssrc  (--in  행)   = 송신 들여다볼 인자
#   U01 이 받는 video vssrc  (--out 행)   = 서버 forward 볼 인자.  active(*) 여부도 메모
```

### 1) 양쪽 user probe 대조 — 가장 빠른 1차 격리
두 클라가 실 브라우저면 이 한 쌍으로 송/수신 어느 쪽인지 즉시 갈린다. (봇은 USER_PROBE 미지원→timeout)
```bash
oxadmin user U02     # 송신측 — PUBLISH 의 video 블록
oxadmin user U01     # 수신측 — SUBSCRIBE 의 "U02 video" 블록 (+ PTT 면 ptt-<room>-video slot)
```
- 송신(U02): `SOURCE frames`↑? → `ENCODER framesEncoded/kf`↑? → `SENT pkts`↑?
- 수신(U01): `RECEIVED pkts/lost` → `DECODER framesDecoded/kf` → `PLAYOUT freeze` + `ELEMENT visible/display/paused/WxH`
- ★ **collectStats 캐시**(§4-U 함정 #1): 같은 user 를 다시 칠 땐 **2초+ 간격**. 연속 2회는 토씨까지 같은 스냅샷 → "정체" 오판.

### 2) trace 로 실증 — 카운터가 애매하거나 slot 이면 필수
slot `--out PKTS=0` 은 거짓일 수 있어(§4-U 함정 #2) **slot 은 무조건 trace**.
```bash
oxadmin trace U02 <pub_ssrc>    --in  --sfu <노드> --secs 3 --detail   # 송신 들어오나 + IDR 키프레임 있나
oxadmin trace U01 <egress_vssrc> --out --sfu <노드> --secs 3           # 서버가 forward 하나 (origin_seq 연속?)
```
- 흐름 = 라인 수(`… --secs 2 2>/dev/null | grep -c ingress_rtp`). 0 이면 안 흐름(단 sfu/ssrc/타이밍 먼저 의심).
- **키프레임**: `--detail` hexdump 에서 H264 IDR(FU-A `7c 85`/`7c 81`, STAP-A `78 …`) 유무. **검은화면 = pkts 는 오는데 키프레임만 결핍**이 전형.
- single-target(함정 §4-T★ #4): `--in` 과 `--out` 동시 reject → 나눠서 캡처.

### 3) 격리 트리 — 어느 줄이 0/정지면 그 단계가 범인
| 끊긴 단계 | 관측 (값이 0/정지) | 범인 / 다음 행동 |
|---|---|---|
| 카메라 | U02 PUBLISH `SOURCE frames` | 클라 캡처(getUserMedia/카메라 토글) — U02 |
| **인코더** | `ENCODER framesEncoded` 정지 / **kf=0** | 인코더 콜드·죽음. **0620b 검은화면 = half 콜드스타트**(28초 kf 1개) |
| 송신 | `SENT pkts` (SOURCE/ENCODER 는 도는데) | 송신측 네트워크/PC |
| 서버 입력 | ingress trace 0 (SENT 는 도는데) | SSRC 오인/네트워크 — 서버에 안 들어옴 |
| 서버 forward | ingress 흐르는데 **egress trace 0** | 서버 forward(gate_drop / subscriber_stream 회수 / mid 미부착) |
| 수신 | egress 흐르는데 U01 `RECEIVED pkts` 0 | 수신측 네트워크/PC/SSRC |
| **디코더** | RECEIVED 오는데 `DECODER framesDecoded`/**kf=0** | **키프레임 결핍 = 검은화면 전형** → PLI/콜드스타트(0620b) |
| 표시 | DECODER 도는데 `ELEMENT display=none`/`paused`/`0x0` | 클라 표시 바인딩(mount 실패, 0615b) |

> **검은화면의 9할 = "RECEIVED 는 오는데 DECODER kf 가 0"**(키프레임만 안 옴). 이건 카운터로 단정 말고
> **kf 증가 여부 + trace IDR** 로 실증한 뒤 말한다. "안 보인다" → "키프레임이 없다" 까지 좁히는 게 이 runbook 의 끝.
> 무음(audio)도 동형: SOURCE `audioLevel` → SENT → RECEIVED → PLAYOUT `concealedSamples` 급증(언더런) 으로 동일하게 격리.

---

## §5 raw REST (원격 / 자동화 — oxadmin 없이)

localhost 가 아니거나(원격) oxadmin 없이 자동화할 땐 admin JWT + curl. **원격은 무인증 bypass 안 됨** → 토큰 필수.
```bash
# admin 토큰 발급
TOK=$(curl -s -X POST http://127.0.0.1:1974/media/auth/token \
  -H 'content-type: application/json' \
  -d '{"api_key":"ox_k_demo","api_secret":"ox_s_demo","user_id":"adm","role":"admin"}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
H="authorization: Bearer $TOK"
```
| oxadmin | REST |
|---|---|
| `show` | `GET  /media/admin/supervisor/status` |
| `load/stop/kill <alias>` | `POST /media/admin/supervisor/{load,stop,kill}/{alias}` (202) |
| `shutdown` | `POST /media/admin/supervisor/shutdown` (202) |
| `sfus` / `sfu <id>` | `GET  /media/admin/sfus` / `GET /media/admin/sfus/{id}/rooms` |
| `users` / `user-cut <id>` | `GET  /media/admin/users` / `POST /media/admin/users/{ident}/cut` |
| `user <id>` | `GET  /media/admin/users/{ident}/probe` (USER_PROBE → 클라 pull, 3s timeout. 미연결=404) |
| `rooms` / `room <id>` | `GET  /media/admin/rooms` / `GET /media/admin/rooms/{id}/snapshot` |
| `reap <room> <user>` | `POST /media/admin/rooms/{room}/reap/{user}` |
| (kick) | `POST /media/admin/rooms/{room}/kick/{user}` |

> 경로 규칙: 컬렉션은 **복수형**(`/sfus`,`/users`,`/rooms`) + `/{id}/액션`. `ws` 글자는 WebSocket upgrade 경로(`/media/ws`,`/media/admin/ws`) 전용이라 WS 평면 REST 는 `/users` 를 쓴다.

```bash
# healthz (무인증 — k8s/systemd probe)
curl http://127.0.0.1:1974/media/healthz/live    # 항상 200
curl http://127.0.0.1:1974/media/healthz/ready   # enabled unit 전부 Live → 200, 아니면 503
```
api_key/secret 은 `[hub.auth.api_keys]` 의 값(데모 = `ox_k_demo`/`ox_s_demo`).

---

## §6 함정 / 자주 틀리는 것

1. **로그가 파일로 빠진다** — `[dirs] log = "./"` → hub `./oxhubd.log.<날짜>` + sfud `./oxsfud.log.<날짜>`(supervisor 자식은 stdout 도 hub 콘솔로 상속). **콘솔로 한 터미널에서 다 보려면 `log = ""`**.
2. **`public_ip` 하드코딩** — 클라가 받을 미디어 IP. 다른 네트워크면 클라가 미디어 못 받음 → 실제 IP 또는 `""`(자동감지). 멀티 sfu 가 같은 머신이면 동일 public_ip 공유 OK.
3. **`ws_port` override 불필요** — sfud 는 WS 안 띄움(WS=hub). 충돌 안 나니 안 건드린다.
4. **포트 충돌은 grpc_listen + udp_port 만** — 멀티 sfu 시 이 둘만 sfu별로 다르면 됨.
5. **`[[hub.sfu]]` TOML 위치** — `[sfu]`/`[supervisor]` **앞**(= `[hub.*]` 구간 안)에 둘 것. 뒤에 두면 파싱 깨짐.
6. **supervisor cmd 는 절대경로** — 자식 cwd 가 hub cwd 라도 cmd 는 절대경로가 안전.
7. **build** — release 는 `cargo build --release` 선행. 바이너리 = `target/release/{oxhubd,oxsfud,oxadmin}`. (**현재 oxsfud default 에 trace 포함** → release 빌드에 패킷 트레이스 자동 탑재. 상용 전 `Cargo.toml default = []` 로 분리 필수 — §4-T 보안.)
8. **재기동 위생 — 죽이고 바로 올리면 sfud 가 `blocked`** — hub kill → sfud 는 lifeline 으로 동반 종료하지만 gRPC/UDP 포트(50051/52, 19740/41)를 놓는 데 시간이 걸린다. 곧바로 새 hub 를 띄우면 새 sfud 가 EADDRINUSE → **즉시 Blocked**(0612 backoff 폭주 방어). **포트 free 확인 후 기동**하거나, Blocked 면 `oxadmin load <alias>` 로 복구. (`lsof -nP -iTCP:50051 -iTCP:50052 -iUDP:19740 -iUDP:19741`)
9. **oxadmin reap/kick 은 localhost 무인증** — admin 포트(1974)가 외부 노출 + 리버스 프록시 뒤면 peer 가 항상 127.0.0.1 로 보여 **무인증 통과**. 운영 노출 시 admin 경로 방화벽 필수(XFF 신뢰 금지).

---

## §7 관련

- 운영 CLI(oxadmin) 설계: `context/202606/20260613_oxadmin_design.md`
- 패킷 트레이스(oxadmin trace, §4-T) 설계: `context/202606/20260615_oxadmin_trace_design.md`
- user 실시간 진단(oxadmin user, §4-U) + 디버깅 결함 회고: `context/202606/20260620c_user_probe_oxadmin_debug_fail.md`
- cross-sfu 서버 설계: `context/202606/20260603_cross_sfu_design.md`
- supervisor 설계: `context/202606/20260603_oxhubd_supervisor_design.md`
- 회귀시험(oxe2epy): `context/guide/REGRESSION_GUIDE_FOR_AI.md` (봇 붙여 oxadmin 실데이터 관측에도 활용)
- config 구조체: `crates/common/src/config/system.rs` (SystemConfig/HubConfig/SfuConfig/SfuNodeConfig/SupervisorConfig/RoutingConfig)

---

*author: kodeholic (powered by Claude)*



sudo tcpdump -i lo0 -s0 -w ~/repository/testlogs/202606/cap_0624_ptt04.pcap udp port 19740