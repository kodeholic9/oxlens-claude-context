# 서버 운영 가이드 — AI용

> **invoke 키워드: `서버실행` / `config구성` / `실행가이드` / `서버운영` / `운영가이드` / `oxadmin`**
> — 이 단어가 나오면 이 가이드를 먼저 로드한다.
> oxhubd(hub) + oxsfud(sfud) 를 **어떻게 띄우고**(§0~§3) **어떻게 제어·관측하나**(§4 oxadmin). cross-sfu(N sfu) 포함.
> author: kodeholic (powered by Claude)
> created: 2026-06-03 · 운영 CLI(oxadmin) 추가: 2026-06-13 · trace 평면(랩 전용) 추가: 2026-06-15

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
`room <id>` 표 아래 **tracks 카탈로그**가 `USER/DIR/KIND/SSRC` 를 그대로 준다 → 복붙.
```
tracks (trace 인자 — `oxadmin trace <USER> <SSRC> --<DIR>`):
USER  DIR  KIND   SSRC        NOTE
ptt1  in   audio  0xA03E8C3A  half        ← 발화자 publish (--in)
ptt1  out  audio  0xA5D8C694  ViaSlot     ┐ 둘이 같은 ssrc
ptt2  out  audio  0xA5D8C694  ViaSlot     ┘ = PTT slot.virtual_ssrc
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

- 운영 CLI(oxadmin) 설계: `context/design/20260613_oxadmin_design.md`
- 패킷 트레이스(oxadmin trace, §4-T) 설계: `context/design/20260615_oxadmin_trace_design.md`
- cross-sfu 서버 설계: `context/design/20260603_cross_sfu_design.md`
- supervisor 설계: `context/design/20260603_oxhubd_supervisor_design.md`
- 회귀시험(oxe2e): `context/guide/REGRESSION_GUIDE_FOR_AI.md` (봇 붙여 oxadmin 실데이터 관측에도 활용)
- config 구조체: `crates/common/src/config/system.rs` (SystemConfig/HubConfig/SfuConfig/SfuNodeConfig/SupervisorConfig/RoutingConfig)

---

*author: kodeholic (powered by Claude)*
