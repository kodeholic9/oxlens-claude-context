# 20260415b DataChannel MBCP 규격 준수 구현

> author: kodeholic (powered by Claude)
> date: 2026-04-15
> area: 서버 + 웹 클라이언트 (전체)

---

## 요약

**MBCP over DataChannel을 3GPP TS 24.380 규격 준수로 전면 재구현.**

Phase 1(RTCP APP 포맷 + WS fallback)에서 Phase 2(TS 24.380 native 포맷 + DC 전용 + ACK/재전송)로 전환. 클라이언트 7파일 + 서버 3파일 변경. Floor Control이 DC 양방향으로 동작 확인.

---

## 완료 항목

### 1. MBCP 바이너리 포맷 전환 (RTCP APP → TS 24.380 native)

| 항목 | Phase 1 (이전) | Phase 2 (현재) |
|------|---------------|---------------|
| 포맷 | RTCP APP PT=204 + "MBCP" name | TS 24.380 native TLV |
| 메시지 헤더 | V=2,P,subtype,PT=204,length,SSRC,name(12B) | ACK_REQ(1b)+type(4b), field_count(1B) → 2B |
| 필드 | app-data (flat bytes) | TLV: id(1)+len(1)+value |
| ACK | 없음 | Floor Ack (type=8) |
| Ping | MBCP_SUBTYPE_FPNG=5 | **제거** — RTP liveness |

### 2. 클라이언트 변경 (7파일)

| 파일 | 변경 |
|------|------|
| `core/mbcp.js` | **전면 재작성** — TS 24.380 native builder/parser, MSG/FIELD 상수, buildRequest/Release/Ack 편의 빌더 |
| `core/constants.js` | FLOOR_PING_MS 제거, MBCP_T101_MS(500)/C101_MAX(3)/T104_MS(500)/C104_MAX(3) 추가 |
| `core/ptt/floor-fsm.js` | **전면 재작성** — T101/T104 재전송, PING 완전 제거, DC-only 전송, handleDcMessage(서버→클라이언트 DC 수신), Floor Ack 송신 |
| `core/sdp-negotiator.js` | maxRetransmits:0, parseMsg import, DC onmessage→floor-fsm 라우팅, _handleDcMessage 메서드 |
| `core/sdp-builder.js` | m=application answer 섹션 생성 (DataChannel SDP) |
| `core/engine.js` | _mbcpChannel, _dcReady 필드 |
| `core/power-manager.js` | _scheduleDown에 FLOOR.REQUESTING guard 추가 |

### 3. 서버 변경 (3파일)

| 파일 | 변경 |
|------|------|
| `datachannel/mbcp_native.rs` | **신규** — TS 24.380 native parser/builder, MSG_* 상수, TLV 필드, build_granted/deny/idle/taken/revoke/ack/queue_info 편의 빌더, 단위 테스트 |
| `datachannel/mod.rs` | pub mod mbcp_native, parse_mbcp_app→mbcp_native::parse 교체, FPNG 제거, **DC 양방향 응답** (Granted/Denied/Queued를 SCTP stream에 직접 쓰기), handle_stream_event borrow 해소 (read→drop→write 구조) |
| `tasks.rs` | **RTP liveness = implicit ping** — floor timer에서 speaker의 last_video_rtp_ms/last_audio_arrival_us 읽어 floor.ping() 갱신 (기존 ingress hot path 데이터 활용, 새 필드 0개, hot path 변경 0줄) |

### 4. 설계 문서

- `context/design/20260415_mbcp_datachannel_v2_design.md` — 규격 대조, WS path 제거 근거, 타이머 체계, 포맷 정의, 마이그레이션 계획

---

## 핵심 아키텍처 결정

### FLOOR_PING 제거 → RTP liveness (T2)

```
이전: 클라이언트 2초마다 FLOOR_PING(WS/DC) → 서버 last_ping 갱신 → 5초 미수신 → revoke
현재: 서버 floor timer(2초 주기)에서 speaker의 last_rtp 확인
      → ingress.rs에서 이미 갱신되는 last_video_rtp_ms / last_audio_arrival_us 활용
      → RTP 흐르면 floor.ping() 갱신 → RTP 중단 5초 → revoke
      → 새 atomic 필드 0개, hot path 변경 0줄
```

### WS Floor Path 제거

```
DC(SCTP) + RTP = 같은 Pub PC DTLS 위 → 생사 동일
Pub PC 살아있으면 DC 살아있음 → WS fallback 불필요
클라이언트 floor-fsm.js: sig.send(OP.FLOOR_*) 전량 제거, DC-only
```

### DC 양방향 응답 (서버→클라이언트)

```
handle_stream_event:
  1. assoc.stream(id) → read → drop stream
  2. handle_dc_binary → handle_mbcp_from_datachannel → FloorController
  3. FloorAction::Granted/Denied/Queued → mbcp_native::build_* → dc_replies
  4. assoc.stream(id) → write dc_replies → SCTP으로 클라이언트에 직접 응답
```

별도 outbound 채널 불필요 — 같은 요청 처리 루프 안에서 즉시 응답.

### T101/T104 재전송 (TS 24.380 §6.2)

```
Floor Request:
  전송 → T101(500ms) → ACK 미수신 → 재전송 → C101(3) 초과 → 포기 → floor:denied

Floor Release:
  전송 → T104(500ms) → ACK 미수신 → 재전송 → C104(3) 초과 → 포기 → 강제 IDLE

Granted/Denied/Queued/Idle 수신 → T101/T104 즉시 취소
```

---

## 발견된 버그 및 수정

### 1. PowerManager _scheduleDown REQUESTING 미보호 (Phase 1 시험에서 발견)

- 증상: 발화 시작 1초 후 hot_standby → 트랙 제거 → 미디어 중단
- 원인: `_scheduleDown()` guard에 FLOOR.REQUESTING 누락
- 수정: guard 조건에 REQUESTING 추가

### 2. DC 경로 Floor Granted 누락 (Phase 1 시험에서 발견)

- 증상: DC로 Floor Request → 서버 처리 → 클라이언트가 Granted 수신 못함
- 원인: DC apply_floor_actions는 FLOOR_TAKEN broadcast만 보냄, 요청자에 대한 granted 개별 응답 없음
- 수정 (Phase 1 임시): floor-fsm _onFloorTaken에서 REQUESTING+speaker=자기 → granted 처리
- 수정 (Phase 2 정식): 서버가 DC로 Granted/Denied/Queued를 직접 응답

### 3. DC 경로 Denied/Queued 응답 미도달 (Phase 2 시험에서 발견)

- 증상: 타인 발화 중 Floor Request → T101 3회 재전송 후 포기
- 원인: 서버 apply_floor_actions의 Denied/Queued가 RTCP FRVK로만 전송 — 클라이언트 RTCP 파서 없음
- 수정: handle_mbcp_from_datachannel이 dc_replies Vec 리턴 → handle_stream_event에서 SCTP stream에 직접 쓰기

---

## 미완 / 다음 세션 TODO

### PTT STALLED false positive (기존 이슈, DC 변경과 무관)
- 증상: 발화 시작 직후 TRACK_STALLED: ptt_video no_media_flow
- 원인: keyframe 대기 중 send_stats.packets_sent delta=0 → STALLED 판정
- 정당사유 추가 필요: floor speaker의 video가 kf_pending 상태일 때 STALLED 제외

### 서버 T132 재전송 (Phase 2-B 잔여)
- 서버→클라이언트 Floor Granted/Taken/Idle에 ACK_REQ=1 설정 시, 클라이언트 Floor Ack 미수신 → 재전송
- 현재 ACK_REQ=1로 보내고 있으나, 서버측 재전송 타이머 미구현

### apply_floor_actions 코드 중복 (기술 부채)
- datachannel/mod.rs의 apply_floor_actions ↔ ingress_mbcp.rs의 apply_mbcp_floor_actions 중복
- 공용 함수 추출 필요

### SDP validation warning
- `publish answer SDP validation failed: ['section 2: missing direction']`
- m=application 섹션에 direction(sendrecv/inactive) 미포함 — Chrome은 동작하지만 validator 경고
- sdp-builder.js에 `a=sendrecv` 추가 검토 (또는 validator에서 application 제외)

### WS Floor 핸들러 정리 (확정 후)
- signaling.js의 op=40/41/42 outbound + op=141/142/143 inbound 핸들러
- floor-fsm.js의 `_floor:*_raw` WS 이벤트 구독
- DC 양방향이 안정화되면 WS floor 핸들러 완전 제거

---

## 기각 후보

| 접근법 | 기각 사유 |
|--------|---------|
| is_publish_ready()로 implicit ping | **꼼수** — Pub PC 연결 상태 ≠ RTP 흐름. 인코더 사망/트랙 disabled 못 잡음. last_rtp_ms가 정석 |
| FLOOR_PING을 DC로 이관 | MBCP 규격에 없음. RTP liveness(T2/T103)가 정석 |
| WS + DC dual path 유지 | DC와 미디어 생사 동일. dual path = 복잡성만 증가 |
| SCTP maxRetransmits:1 유지 | 앱 레벨 T101/T104와 SCTP 재전송이 겹침. 0이 맞음 |
| RTCP APP 포맷 유지 (DC 경로) | DC는 RTCP 패키징 불필요. TS 24.380 native가 정석 |
| Participant에 last_rtp_at 새 필드 추가 | 불필요 — ingress에 이미 last_video_rtp_ms/last_audio_arrival_us가 있음 |
| dc_outbound_tx 채널로 서버→클라이언트 응답 | 과잉 — 같은 handle_stream_event 루프에서 즉시 쓰기로 충분 |

---

## 오늘의 지침 후보

- **MBCP 규격 준수**: FLOOR_PING은 TCP용 발명품. MBCP는 RTP liveness + ACK/재전송이 정석
- **DC와 미디어 생사 동일**: 같은 Pub PC DTLS 위 → WS fallback 불필요
- **꼼수 감지**: is_publish_ready()는 "연결 살아있냐"지 "RTP 흐르냐"가 아님. 기존 hot path 데이터(last_video_rtp_ms)를 읽는 것이 정석
- **DC 양방향 응답**: 별도 outbound 채널 없이 같은 SCTP stream에서 read→process→write 가능
- **handle_stream_event borrow 해소**: sctp-proto Stream이 &mut Association을 borrow → read 후 drop → write로 순차 처리

---

## 변경 파일 목록

### 클라이언트 신규/수정 (7파일)
- `core/mbcp.js` — 전면 재작성
- `core/constants.js` — 타이머 상수
- `core/ptt/floor-fsm.js` — 전면 재작성
- `core/sdp-negotiator.js` — DC onmessage, maxRetransmits:0
- `core/sdp-builder.js` — m=application
- `core/engine.js` — DC 필드
- `core/power-manager.js` — REQUESTING guard

### 서버 신규/수정 (3파일)
- `crates/oxsfud/src/datachannel/mbcp_native.rs` — 신규
- `crates/oxsfud/src/datachannel/mod.rs` — native 파서 + DC 양방향 응답
- `crates/oxsfud/src/tasks.rs` — RTP liveness

### 설계 문서 (1파일)
- `context/design/20260415_mbcp_datachannel_v2_design.md`

---

*author: kodeholic (powered by Claude)*
