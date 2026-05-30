# 완료 보고 — oxe2e Phase 1 (봇 oxrtc 전환 + conf_basic)

> 지침: `claudecode/202605/20260530_oxe2e_phase1.md`
> 설계: `design/20260530_oxe2e_design.md`
> author: kodeholic (powered by Claude)
> created: 2026-05-30

---

## 0. 요약

봇이 oxrtc(v3)로 서버에 붙어 **conf_basic**(전환 없는 conference)을 발행/수신하고
**약속↔이행 판정**으로 PASS/FAIL을 내는 헤드리스 gate `oxe2e` 신설. 서버 코드 0 변경.
**실측 PASS 확인** (2026-05-30, 부장님 서버 기동).

| 정지점 | commit | 상태 |
|---|---|---|
| 1 — 시그널링 핸드셰이크 | `33977c2` | crate 골격 + connect_and_join 핸드셰이크. cargo check 통과 |
| 2 — conf_basic 발행/수신/판정 | `e1cd083` | 발행 풀스택 + 약속↔이행. cargo build 통과(bin 25MB) |

(레포: `oxlens-sfu-server`, main 직접 커밋)

---

## 1. §0 oxrtc API 매핑 결과 (대조 산물)

| 봇 단계 | oxrtc API | 비고 |
|---|---|---|
| WS연결→IDENTIFY→JOIN→server_config | `signal_client::connect_and_join(hub_url, token, user_id, room) → SignalSession` | IDENTIFY type="recorder" 하드코딩(서버 무시) |
| STUN binding | `ice_client::ice_bind(&socket, addr, ufrag, pwd, timeout)` | localhost+ICE-Lite → binding만 |
| DTLS→SRTP키 | `dtls_client::dtls_handshake(&socket, addr, label) → SrtpKeys` | recv 스레드 abort 후 socket 재사용 |
| SRTP 세션 | `SrtpSession::new(&keys)` | recv=server_key/send=client_key (DTLS role) |
| RTP 수신 파싱 | `rtp_receiver::parse_rtp_mini` + `RtpReceiver` | per-SSRC |
| 발행 RTP 암호화 | `SrtpSession::encrypt_rtp` ★보강 | send_ctx(client_key) |
| 발행 시그널링 | `SignalWriter::send_request(op, d)` ★보강 | PUBLISH_TRACKS/범용 |
| publish ICE 좌표 | `ServerConfig.pub_ufrag/pub_pwd` ★보강 | publish_ufrag/pwd 파싱 |
| gate resume | `SignalWriter::send_tracks_ready` | TRACKS_UPDATE 수신 시 |

★ = oxrtc 발행 표면 보강(별 토픽, 부장님 승인). oxe2e 전용 소비라 영향 격리.

---

## 2. oxrtc 발행 표면 보강 (§5 불변 일시 해제)

- **`new_publish` 불필요로 판명** — `new_subscribe`가 이미 recv=server_key/send=client_key.
  DTLS role(봇=active)이 키 방향을 결정하므로 발행/구독 동일 생성자. 중복 회피 위해
  `new_subscribe`→`new`로 개명 + 양방향 정합 doc, **`encrypt_rtp`(send_ctx) 한 메서드만 추가**.
- `ServerConfig`에 `pub_ufrag`/`pub_pwd` 추가 + connect_and_join 파싱(`publish_ufrag`/`pwd`).
- `SignalWriter::send_request(op, d) → pid` 추가(split 이후 운영 중 요청).
- oxrtc 소비처는 oxe2e뿐(grep 확인) → 외부 영향 0.

---

## 3. oxe2e 구조

```
crates/oxe2e/
  Cargo.toml          path dep oxrtc/oxsig + reqwest(토큰)
  src/
    config.rs         상수(타이밍/PT/SSRC/토큰/실행) — 매직넘버 단일출처
    auth.rs           REST 토큰 발급(POST /media/auth/token)
    scenario/mod.rs   TOML(meta/server/participants/timeline)
    bot/mod.rs        run_bot: 핸드셰이크→barrier→PUBLISH→송수신→약속수집→결과
    bot/media.rs      transport 셋업 + Fake RTP 빌더 + pub/sub task
    judge/mod.rs      이행(ssrc RTP 도착)+존재(조합 add) 검산
    main.rs           참여자별 봇 동시 구동 → PASS/FAIL + exit(0/1)
scenarios/conf_basic.toml
```

- **충실도 경계(§2-5)**: RTP 헤더(SSRC/seq/ts/marker/PT) + mid ext(RFC5285 one-byte) 충실,
  페이로드 더미(Opus silence 3B / VP8 descriptor+frame byte+dummy fill).
- **전원 join barrier**: 아무도 publish 전 동기화 → 약속이 ROOM_JOIN 초기 tracks가 아니라
  TRACKS_UPDATE로 오게 보장(connect_and_join이 초기 tracks 폐기하는 문제 회피).
- **판정**: 이행 = 약속 ssrc가 sub PC RTP로 도착. 존재 = 각 봇이 다른 전원 트랙 add 수신.

---

## 4. 발견_사항

1. **WS 인증 = URL `?token=JWT`** (oxhubd ws_handler). oxrtc connect_and_join은 token을
   IDENTIFY body에만 실어 URL엔 안 붙임 → oxe2e가 `{hub_url}?token=` 구성으로 흡수(oxrtc 무수정).
2. **recorder(participant_type=1)도 발행 허용** — IDENTIFY type 서버 무시, 발행 권한 검사 없음.
   (설계 의도는 recorder=투명 참가자였으나 발행 제약 미구현 — 서버측 갭, 본 작업 범위 밖.)
3. **토큰 봇별 발급 필요** — JWT sub=user_id. 봇 N명 = 토큰 N개. REST 자동 발급
   (api_key=`ox_k_demo`/`ox_s_demo`, system.toml). scenario에 고정 token도 지원.
4. **PUBLISH_TRACKS ssrc** — 실제 SSRC 송신(non-sim full은 사전등록). 실행 검증 필요 항목.

---

## 5. 실측 PASS (2026-05-30)

```
RUST_LOG=info ./target/debug/oxe2e scenario scenarios/conf_basic.toml
[oxe2e] p1: 약속 2건, 수신 ssrc 2종/402패킷
[oxe2e] p2: 약속 2건, 수신 ssrc 2종/401패킷
[oxe2e] ✓ PASS (정지점 2: conf_basic 약속↔이행)
```

- 전 파이프라인 동작: connect→IDENTIFY→ROOM_JOIN→STUN→DTLS(pub/sub)→SRTP→
  PUBLISH_TRACKS→RTP fan-out→약속↔이행.
- p1↔p2 서로의 audio+video 약속 2건씩 100% 이행, fan-out 대칭(≈5초간 audio 250 + video 150).

### 실측에서 잡힌 함정/수정 (모두 oxe2e/scenario 측, 서버 무수정)
1. **hub_url** = `ws://127.0.0.1:1974/media/ws` (base_path `/media` nest. 9000은 추측 오류, 1974 단일 포트).
2. **방 생성** — 서버 startup.rs 가 `qa_test_01~03` 사전생성(cap 1000). scenario room=`qa_test_01`.
   - REST `POST /media/rooms` 사전생성 시도는 폐기: `rooms.rs` 가 envelope user_id 를 빈 문자열로
     보내 ROOM_CREATE 가 `1001 not authenticated` (admin.rs 와 달리 Bearer 미처리). **서버측 갭**(범위 밖, 기록만).
3. REST 토큰 발급은 정상(`POST /media/auth/token`, api_key ox_k_demo).

---

## 6. 불변 확인 (§10)

- 서버 crate(oxsfud/oxhubd/common) **0 변경** → 211 PASS 논리적 불변.
  (`cargo test -p oxsfud` 실측은 요청 시.)

---

## 7. 다음 (Phase 2 — 별도 지침 영역, 손대지 않음)

- floor / DC / SCTP association / MBCP 빌더+파서 → ptt_rapid.
- admin 삼각검증(track-dump 4-Point) — ssrc 조회 경로(설계서 §9) 확정 후.
- 타임라인 액션 dispatch 정밀화(현재 wait sec만 구동시간으로 사용), simulcast/mute/lifecycle.

---

*author: kodeholic (powered by Claude)*
