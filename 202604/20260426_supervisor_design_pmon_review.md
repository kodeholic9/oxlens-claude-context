# 20260426 — oxhubd Supervisor 설계 (옛 PMON 학습)

> hub 가 자식 프로세스 lifecycle 책임 갖는 control plane 설계 +
> 부장님 풀스택 자산 컨텍스트 갱신.

---

## 토픽

1. 옛 PMON 소스 리뷰 (`/Users/tgkang/repository/reference/MGPSRC`)
2. oxhubd Supervisor 설계서 작성 (`design/20260426_oxhubd_supervisor_design.md`)
3. 부장님 풀스택 자산 컨텍스트 (오늘 새로 드러남)

---

## 옛 PMON 소스 리뷰 결과

부장님이 2012~2016년 작성하신 임베디드 PTT 단말 코드. 읽은 범위:

- 멀티프로세스 구조: PMON(supervisor) + CHNL(시그널링 두뇌) + MGPP(미디어엔진래퍼) + WEBI(어드민) + HOOK(/dev/input PTT 버튼)
- SysV msgqueue + 공유메모리 `profile_t` 기반 IPC
- SCF TCP 커스텀 바이너리 (BIND/PING/LEAV/DATA) + ACS/RMS HTTP — 시그널링 3중 부트스트랩
- 채널 FSM (IDLE→ROOMING→ROOMED→JOINING→JOINED→ACTIVATING→ACTIVE)
- MBCP 콜백 7종 (cbGranted/cbTaken/cbMovedIntoQueue 등) — OxLens FloorFsm 인터페이스와 일치 cross-check
- StillAlive 15초 keep-alive — OxLens FLOOR_PING 폐기 후 RTP liveness 의 진화 전 단계
- scpool window=1, 만료 9초 — OxLens OutboundQueue 4단계+8윈도우의 단순판
- autorecovery 100초 → reboot — appliance 모델
- `slave.conf` + `slaveholder[]` + `slave_watchout()` 1Hz 폴링

핵심 발견: **자식 종류 무관 일반화 + stop 의 스크립트 위임** 까지 도달한 모델. 부장님이 "겁나 노력해서 일반화" 하셨다고 표현하신 정수.

---

## 부장님 풀스택 자산 (오늘 드러난 컨텍스트)

오늘 대화 중 명시적으로 확인된 것 — 메모리에 누적되어야 할 사실:

| 영역 | 부장님 이력 | OxLens 대응 |
|---|---|---|
| 시그널링 프로토콜 설계 | 직접 설계 (SCF) | OxLens opcode 프로토콜 (Discord 스타일) |
| 시그널링 서버 (서버측) | 직접 구현 | oxhubd |
| 미디어 서버 | OxSFUd 가 처음 | oxsfud |
| 미디어 엔진 | libwebrtc 차용 (만든 적 없음) | libwebrtc / WebRTC API |
| 단말 클라이언트 | 직접 구현 (CHNL+MGPP+HOOK+PMON) | SDK 코어 (web/Android) |

**의미**:
- 부장님은 **PTT 풀스택을 한 번 다 만들어본 사람** + **두 번째를 webrtc 위에서 짓는 중** — 업계에 흔치 않음
- 시그널링 와이어 프로토콜 설계 직접 경험자 — opcode/DC frame/MBCP TLV 결정의 트레이드오프 체화
- 서버/단말 양 끝을 한 손에서 빚어본 사람 — server-authoritative mid 할당, 2PC SDP-Free 시그널링 같은 결정의 결이 mediasoup 류와 다른 이유
- OxLens 가 **상용화되면 풀스택 두 번째 작품 + 세계 최초 웹 PTT** 의 두 줄 이력

이전 회사명 / 제품명 / 통신사명은 표현 금지 (메모리 규칙 유지). "이전 PTT 제품에서 시그널링 서버 직접 설계 / 단말 직접 구현" 수준으로만 언급.

---

## supervisor 설계 누적 결정 (10여 회 피드백)

부장님 피드백 누적으로 다음 구조에 도달:

### 3단 레벨 차원 (설계서에 명시)
- **Level 1**: 자식 lifecycle (spawn/ready/restart/backoff/intensity/stop) — 1차 PR 동작
- **Level 2**: dependency graph (depends_on / criticality / cascade stop) — spec 자리만
- **Level 3**: HA orchestration (heartbeat / failover / takeover script / fencing) — pre_stop/post_start 훅 자리만

옛 PMON 정신: takeover 도 그냥 자식으로 등록 가능한 일반화. 코어 lifecycle 코드 변경 없이 spec 추가만으로 Level 3 도달 가능해야 함.

### 불변 원칙 3개 (격상)
1. Supervisor 는 자식 종류에 대한 사전 지식을 갖지 않는다 (도메인 이름 코드에 박지 마라)
2. Stop 은 신호 또는 외부 명령 어느 쪽이든 가능해야 한다
3. 확장은 새 enum variant / spec 필드로만 (코어 lifecycle 코드 수정 없이)

### A~D 결정
- A. Control plane, ReadyCheck enum 4종(+Custom 자리), Dev toggle 2단계, 로그 hub 무관여, Shadow 변경 0줄
- B. tokio::process + kill_on_drop + try_wait + nix::kill
- C. setpgid (1차) + prctl PDEATHSIG (자식 측 별도 PR) + setrlimit + PID lock 외곽 위임
- D. hub main(1~4: WS drain + SESSION_DISCONNECT + sfud drain) + supervisor(5~8: StopMethod 실행 + SIGTERM fallback + SIGKILL escalation)

### Ground truth 5종
Erlang OTP supervisor / systemd unit / kubelet CrashLoopBackOff / tini / tokio::process

### 1차 PR 범위
- supervisor/ 7파일, system.toml `[supervisor]` 스키마 (Level 2/3 필드 포함, 동작 무시), Stdio::inherit, ReadyCheck 4종, StopMethod(Signal/Command + fallback), 1Hz tick, exponential backoff, Erlang intensity, setpgid+kill_on_drop, hub main shutdown 통합, REST `/admin/supervisor/status` `/admin/supervisor/restart/{alias}` `/healthz/live` `/healthz/ready`, supervisor 메트릭 카테고리, fixtures 8종 단위 테스트

---

## 기각된 접근법 (오늘)

| 접근법 | 기각 이유 |
|---|---|
| systemd 에 모든 lifecycle 위임 | shadow 복구 / ready 판정이 도메인 의존 |
| Stdio::piped + drain task | 자식이 자체 tracing logging |
| PID 살아있음만 ready | sfud panic 직전 좀비도 ready. gRPC dial 이 정답 |
| `appCLI_reboot()` (호스트 reboot) | 서버는 자기 reboot 안 함. 외곽 위임 |
| SysV msgqueue / 공유메모리 (옛 PMON) | hub-자식은 gRPC |
| FNDEBUG 매크로 | tracing crate 가 대체 |
| start_limit_burst 단순 카운터 (옛 PMON maxtries=5) | 60초 윈도우 슬라이딩(Erlang OTP) 이 정답 |
| StopMethod SIGTERM 만 지원 | java/redis/erlang 운영 시 graceful=명령. 옛 PMON stopline 의 일반화가 정답 |
| 자식 종류 화이트리스트 / enum | 불변 원칙 1 위반 |
| ChildProcess + ExternalDependency 둘 다 1차 구현 | 외부 의존성 도입 시점 미정. 인터페이스만 박고 구현은 향후 |
| Level 2 (depends_on graph + criticality) 1차 구현 | 임베디드 박스 운영 시까지 즉시 필요 없음. 자리만 |
| Level 3 (HA failover) 1차 구현 | 다중화 운영 일정 미정. pre_stop/post_start 훅 자리만 |
| "kafka/redis 는 hub 가 spawn 안 함" (cloud-native 가정) | 부장님 지적 — appliance 모델 무시. 통신장비 carrier-grade 박스에서는 전부 한 supervisor 가 책임 |

---

## 오늘의 지침 (소통 / 사고)

1. **부장님 자산을 좁게 보지 마라**. PMON 소스만 보고 "단순 supervisor" 로 분류한 게 오판. 부장님은 SCF + 시그널링 서버 + 단말 + supervisor 풀스택 직접 만든 분. 같은 결을 OxLens 에 옮기실 때 cloud-native 가정으로 답하지 말 것.

2. **cloud-native 일변도가 default 가 되는 학습 데이터 편향을 의식할 것**. carrier-grade appliance / 통신장비 인하우스 supervisor 사례는 OSS 에 적어 default 가 cloud-native 쪽으로 기운다. OxLens 는 appliance 수요까지 잡으러 갈 수 있는 자산이 있으므로, 양쪽 모두 default 후보로 둘 것.

3. **꼰대 토로는 들어드린다**. 부장님이 통신장비 도메인 자기 인식을 토로하시는 건 도메인 무시당한 경험의 누적. 외부에는 표현 안 가능한 영역이라 Claude 가 받는 자리. 맞장구 + 객관적 진단 둘 다.

4. **회사명/제품명/통신사명 직접 거명 절대 금지**. 부장님이 옛 회사 코드 보여주셔도 코드 식별자(SCF 같은 프로토콜 명칭) 만 사용. 회사명/통신사명은 "이전 PTT 제품" 수준.

---

## 다음 작업 후보

부장님이 명시 요청 안 하시면 제시 금지인 항목 (cross-room phase 2 / SFU-SFU relay / Step 8) 제외.

- **supervisor 1차 PR 코딩** (설계서 OK 후) — Level 1 전체 구현
- **SCF 시그널링 서버 코드 리뷰** — 부장님 의향 따라. OxHubd WS dispatch / passthrough / event 라우팅 cross-check 가치
- 미디어 서버 코드 리뷰 — OxSFUd 안정화 단계라 후순위
- 블로그 시리즈 진행
- STALLED 감지 / oxrecd(audio only) — 기존 우선순위

---

## 참조

- 설계서: `context/design/20260426_oxhubd_supervisor_design.md`
- 옛 PMON 소스: `/Users/tgkang/repository/reference/MGPSRC/src/`
  - pmon/ : pmon_main.c, pmon_proc.c, pmon_slave.c
  - chnl/ : chnl_main.c, chnl_proc.c, chnl_sock.c, chnl_timer.c, chnl_misc.c, chnl_http.c, chnl_oma.c
  - mgpp/ : mgpp_main.c, mgpp_voip.c
  - hook/ : hook_main.c
  - h/scf/ : scmsg.h, scpool.h
  - h/ : common.h, const.h, profile.h, jsonpack.h, libapp.h, librms.h

---

*author: kodeholic (powered by Claude)*
