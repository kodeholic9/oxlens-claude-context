// author: kodeholic (powered by Claude)
# oxhubd + common 전수 감사 — 리팩토링 상처·미구현·주석-코드 불일치 (20260703b)

> 조사: 김과장 (조사반 3개 병렬 정독 + 상위 발굴 직접 재검증 + **라이브 hub 로그 판별**). 수리 0 — 발굴·보고만.
> 범위: oxhubd 5,994줄(31파일) + common 2,120줄(14파일). oxsfud는 전건(20260703) 기감사.
> 특기: supervisor반은 실프로세스 하니스로 stop→load 경합을 재현 시도(재현 불가 실증) →
> REST 계층 결함으로 원인을 뒤집었고, 본인이 `oxhubd.log`에서 당일 재현 2건의 실로그로 확정.
> ★ = 본인 직접 재검증 완료.

---

## §1 상 — 실동작 결함 (6건)

### H1. ★supervisor 명령 제어면 — "명령 소실이 성공으로 보이는" 3중 결함
- **큐 경합 아님**: 조사반이 실프로세스 하니스(gap 0ms~2s ×6 + SIGTERM 무시 자식 + status 폭격)로
  재현 시도 — cmd 채널은 FIFO 단일 consumer, Stop 완주 후 Load 처리로 **순서 역전 불가 실증**.
- 실체 3중: ① `rest/supervisor.rs:88` `let _ = send(...)` + 즉시 202 (별칭 검증 0, 결과 회신 0)
  ② `mod.rs:398/441` unknown alias → warn만 남기고 증발 ③ `mod.rs:434` 허용 상태 밖 load →
  "ignored — already running" warn 드롭.
- ★실로그 확정: 07-03 06:59 `stop/load unknown alias 'sfud-1'` ×4 (오별칭 세션 — oxadmin은 전부 202 OK),
  07-05 16:02 `load ignored — already running (live)` ×2 (stop이 10s 걸리는 동안 관측 혼선).
- 수리 방향: `dispatch_alias` 별칭 사전 검증 + oneshot 회신(처리 결과 동기 반환).

### H2. ★sfud SIGTERM graceful 종료 실패 — 5/5 전량 SIGKILL escalation (sfud 측, 로그 발굴)
- hub 로그 전수: `stop via signal SIGTERM` 5회 = `stop timeout — SIGKILL escalation` 5회 (**성공 0**).
- sfud `lib.rs:315-325` SIGTERM 핸들러는 실재 — drain 이후 exit 경로가 10s 내 완주 못 하는 회귀 의심.
  0603e "sfud SIGTERM graceful 수신 정합" 산물이 깨진 상태. **모든 stop이 사실상 강제 종료** —
  drain/AGG flush 등 종료 계약 전부 미이행 가능.

### H3. ★binary "OutboundQueue 우회" 인프라 통째 사망 — 문서·주석 허위
- `state.rs:470/484` `broadcast_to_room_binary`/`send_event_to_user_binary` **호출처 0**,
  `bin_event_tx` 송신자 0 → ws select 분기 영구 침묵. 실제 S→C MBCP 는 OutboundQueue 경유.
- PROJECT_SERVER.md "binary 메시지는 OutboundQueue 우회(T132 이중화 방지)" = 미구현 계약.
  sfud 측 주석(floor_broadcast.rs:288 "hub OutboundQueue 가 pid 재할당")이 실동작과 정합 — hub 쪽이 화석.
- 판단 필요: 우회 배선(생산자 연결) vs 계약 철회(사망 인프라 제거 + 문서 정정). T132 이중화의 실해 실측이 선행.

### H4. ★TELEMETRY 가 안 쓸 sfud 게이트 뒤 — 장애 순간 진단 유실
- `ws/mod.rs:661` `sfu_for_room` 실패 시 SfuUnavailable 반환이 **oxcccd tap(676)·TELEMETRY 종착(684)보다 앞**.
- sfud 다운/방 미매핑 순간(진단이 가장 필요할 때) telemetry 유실. 수리 = tap+종착을 게이트 앞으로 재배열.

### C1. ★policy.toml 3분의 2가 유령 손잡이 + 죽은 런타임 교체 경로
- 12 정책 그룹 중 **8개 전체**(Heartbeat/Reaper/Room/Rtx/Simulcast/PliGovernor/Rtcp/ActiveSpeaker) +
  floor 7필드 중 6개 + media.egress_queue_size — **양 크레이트 읽기 0** (실효값 = oxsfud config.rs 하드 상수).
  ★floor.max_burst_ms 직접 검증: `FloorConfig::default = config::FLOOR_MAX_BURST_MS` 직결.
- `update_policy`/`reload_policy` ★호출 전 크레이트 0 — "hub REST → 즉시 반영" 문서만 남은 죽은 ArcSwap 기계.
- **T2 사건(S2)과 직결**: policy 계층이 살아 있었다면 24h 디버그는 toml 한 줄이었음 — 유령 손잡이가
  하드 상수 수정 문화를 만든 구조적 근인. PliGovernorPolicy 6필드는 0621 재설계로 개념 자체가 소멸한 특수 악성.
- 실사용은 logging.level / media.bwe_mode·remb_bitrate_bps / floor.bearer / hub.* 뿐.

### C2. ★HubTlsConfig 완전 미구현 — `tls.enabled=true` 조용히 평문
- ★oxhubd 전체 "tls" 참조 0. 파싱만 되는 보안 설정 — 최소한 기동 시 "미지원" 거부/경고 필요.

## §2 중 (요지)

| 항목 | 내용 |
|---|---|
| Connect unit 기동 패닉 | `ExecutionConfig::Connect` toml 파싱 통과(★spec.rs:130 확인) → `unimplemented!()` — config 오류가 검증 에러 아닌 crash. enabled 시 부팅 fail-fast라 잠복은 없음 |
| supervisor run 무통보 사망 | `main.rs:222 let _ = run.await` — run task 죽어도 hub 계속 서빙, 전 cmd 영구 큐잉 |
| stop 락 독점 | Stop 처리기가 children Mutex+run loop 을 최대 10s 점유 — status/healthz(k8s probe) 블록 |
| stale pid/uptime | try_reap 이 pid/started_at 미청소 — stopped unit 이 죽은 pid+증가 uptime 보고(oxadmin show 오판) |
| admin metrics 200 스텁 | `/media/admin/metrics` 가 "not yet implemented"를 **200 OK** 로 (auth refresh 는 501 정직 — 비대칭) |
| moderate v2 어댑터 박제 | "임시" Packet 어댑터 5·16 이후 상존, ws/handler 주석이 서로 v2/v3 라 주장 + dead store |
| admin_cut 지표 오염 | duplicate kick 도 admin_cut 계상 (이중 계상) |
| shadow write-only | 매 ROOM_EVENT 누적하나 `room_members()` 호출 0 — 복구 read 미구현 (비용만 지불) |
| LAYER_CHANGED 고아 op | 0x2106 emit/dispatch 전 크레이트 0 — 0621 sweep 폐기와 함께 발신처 소멸 (카탈로그 44 assert 연동 주의) |
| ACTIVE_SPEAKERS ack 모순 | common "no-ack 예외" vs oxsig "no-ack 아님" 정면 충돌 + 서버는 wire 로 안 보냄(DC 이관) — intent::SPEAKERS 도 흔적 |
| room 스코프 토큰 무력 | claims.room_id 를 WS/join 어디서도 미검증 — 방 한정 토큰이 전 방 통용. **→ 진단 정정(0705, 부장님 확인): 방 스코프 자체가 비의도 잔재 — 검증 도입이 아니라 claim 제거로 종결(`1235c66`)** |
| udp_worker_count 무시 | `let _udp_workers` 읽자마자 버림 — "0=auto 코어수" 약속 미구현 |
| agg_inc/agg_register 죽은 API | 호출 0 + agg_flush retain 이 사전등록 엔트리 drain — 계약 깨진 채 미발화 |
| grpc reconnect()/endpoint() dead | 단일 클라이언트 시절 자가 재연결 API 잔재 (실 lazy reconnect 는 state.sfu_by_id) |
| ROOM_LIST fan-out 무음 누락 | 실패 sfu 를 warn/계측 없이 부분 병합 — 정상 응답으로 위장 |
| policy Default 표류 | reaper 기본 20s/35s vs 실상수 15s/20s + "config.rs와 일치해야" 가 가리키는 파일 부재 |

## §3 하 (요약)

SessionPhase::Disconnected 미도달(상태기계 장식) · forward_wire_to_sfud Err 도달불능 · moderate unreachable 분기 3종+remove_session dead · supervisor health_tick/ReadyCheckExecutor/StopPhase/restart route 사장 · `_ACK_STATE_PROBE`·`enqueued_at`·`last_acked_at` 죽은 필드 · REST 모듈 route 지도 낡음(11 중 4만) · "(REST status 핸들러는 다음 지침)" 화석 · 신호 send 에러 전부 삼킴 · supervisor tests 가 cmd 큐 경로 사각 · metrics_group! 필드 doc 불가·Gauge 미지원 미문서 · opcode 주석 "1=Room" 오기 · drain() 유령 언급 등 ~20건 (조사반 원보고 참조).

## §4 깨끗함 확인 (특기)

main.rs·convert.rs(비움 문서화 정합)·probe/(track_dump 승계 정확)·ccc/·events/·backoff.rs·process.rs·
auth JWT·verify_admin ConnectInfo 배선·admin kick/reap 의 target_user 규칙(envelope 함정 회피) — 전부 코드-주석 정합.
track_dump/`__ptt__`/set_id 잔재 oxhubd 내 0건. cross-sfu no-fallback 룰 정합.

## §5 총평·수순 제안 (결재용)

**총평**: sfud 와 병의 결이 다릅니다. sfud 는 "주석이 코드를 못 따라온" 화석이 주였다면, hub 는
**"약속한 인프라가 절반만 지어진" 미완**이 주입니다 — binary 우회·shadow 복구·policy 런타임 교체·TLS·
room 스코프 토큰이 전부 "계약/문서만 있고 소비자·구현이 없는" 동일 패턴. 운영 제어면(supervisor REST)의
무회신 202 는 오늘 실측으로 실해가 확인된 유일한 즉발 결함.

수순 제안:
1. **즉결 후보 (저면적)**: H4 TELEMETRY 재배열 · H1 별칭 사전 검증+oneshot 회신 · C2 TLS 기동 거부 ·
   metrics 스텁 501 화 · stale pid/uptime 청소.
2. **원인 규명 필요**: H2 sfud SIGTERM hang (drain 후 exit 경로 조사 — sfud 측 별 토픽).
3. **설계 판단**: H3 binary 우회 배선 vs 철회 · C1 policy 계층 살리기(하드 상수→policy 연결) vs
   공식 축소(유령 그룹 제거 + "정적 설정" 선언) · shadow 복구 기능 완성 vs 제거 · room 스코프 토큰 검증 도입.
4. **일괄 청소**: §2 하위 + §3 사코드·화석 (sfud 방식 동일 — 참조 0 재확인 후).
