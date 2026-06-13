# 설계 — oxadmin 운영 CLI (supervisor 경유 제어 + 조회)

> author: kodeholic (powered by Claude)
> 2026-06-13. hub REST(supervisor/admin) 위의 단일 운영 CLI.
> show-* 는 oxadmin 을 감싸는 셸 wrapper (oxadmin 출력 = JSON 기본, jq 친화).

---

## §1. 목적 / 범위

운영자·개발자가 hub 한 곳에 붙어 시스템 상태를 보고 lifecycle 을 제어하는 단일 CLI.
**제어는 전부 supervisor 경유**(셸 `kill -9` 우회 금지 — supervisor 가 모르면 watchout 이
backoff 로 되살려 의도가 꼬임). 자체 시험(sfud 띄우고 내리기, 클라 비정상 상황 반응 관찰)이 1차 동기.

1차 범위 3 평면:
- **Unit**(supervisor): show / load / stop / kill / shutdown
- **WS**(hub-local): ws 목록 / ws 강제 해제(cut)
- **Room**(sfud 경유): 방 목록 / 참여자 목록 / 참여자 트랙 / 참여자 reap(좀비 퇴장 강제)

비범위(2차): telemetry(시계열)·agg-log(tail) — 조회 모델이 달라 별종. metrics(현 TODO).

---

## §2. 명령 일람

| 평면 | oxadmin 명령 | 동작 | 경유 | 신설 |
|---|---|---|---|---|
| Unit | `show` / `list` | unit 상태 배열 | supervisor status | — (있음) |
| Unit | `load <alias>` | Stopped/Down → bring_up → Live | supervisor | cmd Load |
| Unit | `stop <alias>` | SIGTERM graceful → Stopped | supervisor | cmd Stop + state Stopped |
| Unit | `kill <alias>` | SIGKILL 즉시 → Stopped | supervisor | cmd Kill |
| Unit | `shutdown` | unit 순차 stop → hub 자신 종료 | supervisor→hub main | cmd Shutdown |
| WS | `ws-list` | 연결 클라 목록(peer_addr 포함) | hub-local | REST 신설 + peer_addr 저장 |
| WS | `ws-cut <conn_id\|user>` | WS 소켓 강제 close (transport 강제 끊김) | hub-local | WsConn close 신호 + REST |
| Room | `rooms` | 방 목록 | sfud ROOM_LIST | — (있음 `/admin/rooms`) |
| Room | `room <room_id>` | 참여자 + 트랙(pub/sub) | sfud ADMIN_SNAPSHOT | REST 노출(로직 있음) |
| Room | `reap <room_id> <user>` | 좀비 퇴장 강제(정상 통보 없이 서버 일방 제거) | sfud | REST 신설(evict 재사용) |

> 참여자/트랙은 엔드포인트 분리 안 함 — `ADMIN_SNAPSHOT(room_id)` 한 응답에 방 뷰+User 뷰+
> Track Identity 통째(track_dump 가 이미 fetch). oxadmin 이 클라 측에서 뷰만 분할.

---

## §3. Unit 평면 (supervisor)

상태머신(현행): `Idle→Starting→Live→Stopping→Down→Backoff→Idle`, intensity 초과 `Blocked`.
**의도적 정지 상태 부재** → `Down`(비정상)은 watchout 이 backoff 재기동. 그래서:

- **`UnitState::Stopped` 신설** — 의도적 정지. watchout 이 `Down`은 backoff, `Stopped`는 무시.
- **`SupervisorCmd` 확장**: `Stop{alias}` / `Kill{alias}` / `Load{alias}` / `Shutdown`
  (현재 `Restart`만). 불변원칙 §3("확장은 새 variant")과 정합.
- **intensity 카운터 제외** — 의도적 stop/kill/load/shutdown 은 `recent_starts` 에 안 셈.
  안 그러면 시험 반복 중 intensity 초과 → `Blocked` → **hub 자폭**. (Restart 의 start_limit
  reset 과 동일 처리.)

### stop / kill / load
- `stop`: `stop.rs` graceful 재사용(StopPhase: Method→SIGTERM→SIGKILL escalation) → `Stopped`.
- `kill`: `signal_group(SIGKILL)` + `reap_blocking` → `Stopped`. stop 과 **정지 방식만** 차이, 둘 다
  supervisor 통하고 둘 다 억제.
- `load`: `Stopped`/`Down`/`Idle`/`Blocked` → `bring_up`(spawn→ready→Live) + 카운터 리셋.

> ⚠ unit `kill`(프로세스 SIGKILL) ≠ room `reap`(참여자 좀비 퇴장). 평면이 다르다 — 헷갈리지 말 것.

### shutdown (hub 자신 포함)
```
oxadmin shutdown
  → supervisor: 관리 unit 순차 graceful stop  [sfud A → B → ...]  (unit 먼저)
  → 전 unit 정지 확인
  → event_tx → hub main "전부 내려감, 종료"   (기존 IntensityExceeded 경로 재사용)
  → hub graceful exit                          (마지막에 본인)
```
- **unit 먼저, hub 나중**: hub 가 먼저 죽으면 supervisor(=hub 일부)도 죽어 sfud 고아화.
  stdin lifeline(EOF 동반종료)이 안전망이나, 명시적 graceful 로 sfud 세션/포트 정리 시간 부여
  (0612 고아 포트 점유 사고 맥락).
- 이미 있는 `SupervisorEvent::IntensityExceeded → hub graceful shutdown` 경로의 **수동 트리거** 버전.
- oxadmin 은 202 수락 후 연결 끊김을 정상 종료로 해석(hub 가 비동기로 내려감).

---

## §4. WS 평면 (hub-local — gRPC 안 거침)

데이터: `HubState.ws_clients: DashMap<user_id, WsConn>` / `room_clients: DashMap<room, HashSet<user>>`.

- **ws-list**: `ws_clients` 순회 → `{user_id, conn_id, rooms[], intents, peer_addr}`.
  - **peer_addr**: 현 `client_ws_handler(ws, State, Query)` 는 ConnectInfo 미수신 → 신설.
    단 이는 §7 localhost 우회와 **동일 배선**(`ConnectInfo<SocketAddr>` extractor + 서버
    `into_make_service_with_connect_info`). **한 번 깔면 ws peer_addr + admin localhost 둘 다 공짜.**
    WsConn 에 `peer_addr: SocketAddr` 필드 추가 후 연결 시 저장(거창한 게 아니라 저장 한 줄).
- **ws-cut**: WsConn 에 **close 신호 신설** — 현 WsConn 은 송신 채널만, 능동 close 수단 없음.
  `close: Arc<Notify>`(or oneshot) 추가 → `handle_client_ws` select! 에 합류 → 신호 시 루프 break →
  기존 cleanup(SESSION_DISCONNECT 통보 + unregister) 경로 그대로.
  - **transport 강제 끊김**(무통보). 클라 reconnect 로직(R1) 의존. WS 죽음 자체에 클라가 반응.

---

## §5. Room 평면 (sfud 경유)

- **rooms**: ROOM_LIST (sfu fan-out 병합). 기존 `/admin/rooms`.
- **room <id>**: `ADMIN_SNAPSHOT(room_id)` → 참여자 + pub/sub 트랙(Track Identity). REST GET 노출
  (현재 track_dump 내부용으로만 호출 → 직접 엔드포인트화).
- **reap <room> <user> (좀비 퇴장 강제)**: 좀비 reaper 가 하는 일을 admin 이 강제 트리거.
  기존 `evict_user_from_room`(helpers.rs, Take-over cleanup 7단계: cancel_pli_burst → floor cleanup →
  rooms.remove_participant → SubscriberIndex detach → peer.leave_room → simulcast purge +
  speaker_tracker.remove → emit_per_user_tracks_update + participant_left broadcast) 재사용.
  - **정상 LEAVE 통보 없이** 서버가 일방 제거. 당사자 WS 는 살아있으나 방에서만 빠짐 → **클라는
    자기가 방에 있다 믿지만 서버는 뺀 좀비 불일치 상태.** 클라가 이를 감지/복구하는지 시험이 목적.
  - 다른 참여자에겐 `participant_left` broadcast (정상 좀비 reaper 와 동일).

---

## §6. reap vs ws-cut — 평면이 다르다 (둘 다 비정상 반응 시험용)

둘 다 "클라 비정상 상황 반응 시험"이지만 끊는 레벨이 다르다. 둘 다 둔다:

| | ws-cut | reap |
|---|---|---|
| 레벨 | transport (WS 소켓) | application (방 멤버십) |
| 동작 | 소켓 강제 close | 방에서 서버 일방 제거(evict) |
| 통보 | 무통보 | 정상 LEAVE 통보 없음(타 참여자엔 participant_left) |
| 클라 관점 | 연결이 끊김 → reconnect 로직 발동 | WS 는 살아있는데 방에서 사라짐 → **좀비 불일치** |
| 시험 초점 | reconnect/복구(R1) | 좀비 불일치 감지·ROOM_SYNC·재가입 여부 |

> 기존 영구 퇴장(ROOM_LEAVE `kick_user`)·graceful `RECONNECT`(request_reconnect)는 **별개로 그대로
> 유지** — oxadmin reap 은 좀비 퇴장 시뮬 전용. (graceful 재접속 유도가 별도로 필요하면 2차.)

---

## §7. 인증 / 출력

- **localhost 무인증**: `verify_admin` 맨 앞에 `peer.is_loopback() → Ok(())` 1곳. 전 admin/
  supervisor 핸들러가 이 함수 단일 게이트라 일괄 적용. `ConnectInfo<SocketAddr>` 배선 필요
  (서버 `into_make_service_with_connect_info`) — Phase 0 확인. **§4 ws peer_addr 과 동일 배선**.
  - ⚠ **리버스 프록시 뒤면 peer 가 항상 127.0.0.1** → 외부 무인증 통과. XFF 신뢰 금지. 전제 =
    hub 직접 노출 + admin 포트 방화벽, 또는 admin 을 loopback 전용 별도 포트(미채택, 명세는 src 체크).
- **원격**: 기존 admin JWT.
- **출력**: JSON 기본(jq 친화). `--pretty`(표) 선택. show-* 셸 wrapper 가 가공.

---

## §8. REST 엔드포인트 (신설/기존)

```
GET  /media/admin/supervisor/status            기존 (show/list)
POST /media/admin/supervisor/stop/{alias}       신설
POST /media/admin/supervisor/kill/{alias}       신설
POST /media/admin/supervisor/load/{alias}       신설
POST /media/admin/supervisor/shutdown           신설
GET  /media/admin/ws                            신설 (ws-list, hub-local)
POST /media/admin/ws/cut/{conn_id|user}         신설 (ws-cut)
GET  /media/admin/rooms                         기존 (rooms)
GET  /media/admin/rooms/{room_id}/snapshot      신설 노출 (room: 참여자+트랙)
POST /media/admin/rooms/{room_id}/reap/{user}   신설 (reap=좀비 퇴장 강제, evict 재사용)
```

---

## §9. Phase

| Phase | 내용 | 정지점 |
|---|---|---|
| 0 | ConnectInfo 배선(서버 connect_info serve + extractor) + verify_admin localhost bypass + ws peer_addr | |
| **A** | UnitState::Stopped + SupervisorCmd Stop/Kill/Load + watchout 제외 + intensity 제외 | ★ stop→watchout 안 살림 확인 |
| B | supervisor shutdown(unit 순차 + hub 종료) — IntensityExceeded 경로 재사용 | ★ shutdown 시퀀스 확인 |
| C | WsConn close 신호 + ws-list(peer_addr)/ws-cut REST | |
| D | room snapshot GET 노출 + reap(user-target evict) REST | |
| E | oxadmin CLI 바이너리 (REST 클라, JSON 출력, 서브커맨드) | |
| F | show-* 셸 wrapper 예시 1~2개 | |

- 정지점: A(억제 동작 = 핵심) / B(hub 자폭 시퀀스 — 위험).

## §10. 기각 / 주의

- 셸 `kill -9` 우회 제어 — supervisor 모르면 watchout 되살림. 전부 supervisor 경유.
- oxadmin reap = ROOM_LEAVE(정상 퇴장)·RECONNECT(graceful) — 아님. evict(좀비 퇴장, 무통보). 정상
  퇴장·graceful 재접속은 기존 별 경로.
- unit `kill`(프로세스) ≠ room `reap`(참여자) — 평면 혼동 금지.
- ws-cut/reap 통합 — transport vs application 레벨 다름. 둘 다 유지.
- 의도 동작 intensity 카운트 — 자폭. 제외.
- XFF 로 loopback 판정 — 위조. peer addr 만.
- 참여자/트랙 엔드포인트 3분할 — snapshot 1개 + oxadmin 뷰 분할.
- ws peer_addr 별도 배선 — localhost 우회와 동일 ConnectInfo 배선. 한 번에.

## §11. 산출물

- `oxhubd`: supervisor(UnitState::Stopped, cmd 4종, shutdown), rest(supervisor stop/kill/load/
  shutdown, ws list/cut, room snapshot, reap), state(WsConn close 신호 + peer_addr), verify_admin
  bypass + ConnectInfo 배선.
- 신규 `oxadmin` CLI crate (서버 workspace bin).
- show-* 셸 wrapper 예시.
