# 0416a — PTT virtual track remove 보호 + MBCP 큐 갱신 + DC 채널 확장 설계

- **날짜**: 2026-04-16
- **영역**: 서버 + SDK + 설계
- **상태**: 버그 수정 완료, DC 설계 확정, 구현은 다음 세션

---

## 완료 항목

### 1. ★ PTT virtual track remove 보호 (서버 근본 수정)

세션 0415d에서 클라이언트 `subscribeTracks()` 원인으로 추정했으나, **서버가 진짜 범인**.

**근본 원인**: `build_remove_tracks()`가 참가자 퇴장 시 `"ptt-audio"/"ptt-video"` remove를 broadcast → 남은 subscriber의 m-line inactive → track 영구 muted → 영상 영구 미표시.

**수정**: `room_ops.rs` (leave), `tasks.rs` (zombie reaper) — 퇴장 후 남은 참가자 중 같은 kind의 half-duplex 보유자 존재 시 virtual track remove 생략 + mid 반환 생략. `track_ops.rs` 0413b(moderate unpublish)와 동일 원칙.

**수정 파일**: `room_ops.rs`, `tasks.rs` (2파일)

### 2. 진단 강화

- `admin.rs`: 스냅샷에 `sub_mid_map` 필드 추가 (subscriber별 `{track_id, mid, kind}` 배열)
- `room_ops.rs`, `tasks.rs`: `ptt:virtual_remove_skipped` agg-log 추가 (skip 발생 시 즉시 확인 가능)

### 3. ★ MBCP 큐 위치 갱신 (TS 24.380 §6.3.4.4)

**문제**: 큐 삽입 시 1회만 전달. 다른 사람이 나가거나 grant되어 큐 순서 바뀌면 갱신 안 함.

**수정**:
- `floor.rs`: `QueueUpdated` 액션 + `_queue_position_updates()` 헬퍼
- 큐 변경 6곳 전부 적용: grant pop, cancel, insert, leave, T2 timeout, ping timeout
- `floor_broadcast.rs`: `QueueUpdated` → per-user DC `FLOOR_QUEUE_INFO` 전달
- `ptt-panel.js`: QUEUED 라벨 실시간 갱신 (`floor:state`는 QUEUED→QUEUED로 미발화 → `floor:queued` 이벤트에서 직접 라벨 갱신)

### 4. MBCP Granted duration (TS 24.380 §8.2.2)

- `mbcp_native.rs`: `FIELD_DURATION(9)` u16 BE, `build_granted(speaker, duration_s)` 시그니처 변경
- `mbcp.js`: DURATION 파서 추가
- `floor-fsm.js`: Granted에 `duration` 필드 추출 + `floor:granted` 이벤트에 포함

### 5. 수정 파일 목록 (서버 6, 클라이언트 3)

| 파일 | 변경 |
|------|------|
| `room_ops.rs` | PTT virtual track remove 보호 + agg-log |
| `tasks.rs` | 동일 (zombie reaper) |
| `admin.rs` | sub_mid_map 스냅샷 |
| `floor.rs` | QueueUpdated 액션 + 6곳 적용 |
| `floor_broadcast.rs` | QueueUpdated 처리 + Granted duration |
| `mbcp_native.rs` | FIELD_DURATION + build_granted 시그니처 |
| `mbcp.js` | DURATION 파서 |
| `floor-fsm.js` | duration 처리 |
| `ptt-panel.js` | QUEUED 라벨 갱신 + Granted duration 로그 |

---

## DC 채널 확장 설계 (확정, 구현 다음 세션)

### 채널 구조

```
DC "unreliable" (ordered=false, maxRetransmits=0)  ← MBCP, Active Speakers
DC "reliable"   (ordered=true)                     ← 채팅, 명령, 상태 동기화
WS (기존)                                           ← fallback + 시그널링
```

### 메시지 포맷 (DC/WS/gRPC 공통)

```
┌──────────┬──────────┬─────────────────────┐
│ svc (1B) │ len (2B) │ payload (len bytes)  │
└──────────┴──────────┴─────────────────────┘
```

- svc: 서비스 타입 (0x01=MBCP, 0x02=Active Speakers, 0x03=Chat, ...)
- len: payload 길이 (BE u16)
- payload: 서비스별 자유 포맷 (MBCP는 기존 바이너리 그대로)

### 전송 경로 선택

```
send(svc, payload):
  channel = svc가 reliable 요구? → reliable : unreliable
  if channel.ready:
    channel.send(svc + len + payload)
  else:
    ws.send(binary frame: svc + len + payload)   // WS fallback
```

### WS 바이너리 경로

WS 프로토콜이 Text/Binary frame 자동 구분 (opcode 0x1 vs 0x2). Base64 변환 불필요.

```
수신 분기:
  Message::Text(json)   → 기존 JSON opcode 시그널링
  Message::Binary(bytes) → svc + len + payload 파싱
```

### gRPC 바이너리 경로

```protobuf
message WsMessage {
  oneof payload {
    string json = 1;    // 기존 JSON opcode
    bytes binary = 2;   // svc+len+payload
  }
}
```

hub 분기: Text → `json` 필드, Binary → `binary` 필드. sfud에서 동일하게 분기. 기존 JSON 경로 무변경.

### 상용 DC 패턴 조사 결과

- **LiveKit**: `_lossy`(unreliable) + `_reliable` 2채널. WS 항상 병행. DC 실패 → ICE restart → full reconnect
- **mediasoup**: DataProducer/DataConsumer 추상화. `sctpstatechange` 이벤트로 감지. transport 레벨 정리
- **공통**: DCEP 재시도는 불필요 (SCTP reliable 보장). DC 자체 재생성 없음 — PC 재연결에 의존. SCTP HEARTBEAT(30초) 자동 처리
- **핵심 리스크**: SCTP abort chunk(LiveKit #3475), DTLS timeout, NAT rebinding → DC 단절 시 WS fallback 필수

---

## 다음 세션 작업 예정

### 텔레메트리 확장

**DC 건강 지표**: bufferedAmount, readyState 변화, onclose/onerror 횟수, DCEP latency
**svc 통계**: svc별 전송/수신 카운트, DC vs WS fallback 비율
**서버**: dc_tx 성공/실패 (SfuMetrics `dc` 카테고리), admin 스냅샷 `dc_ready`

**세션 시작 타임라인**:

```
T0: getUserMedia → T1: WS connect → T2: IDENTIFY → T3: ROOM_JOIN
→ T4: Pub SDP → T5: DCEP open → T6: Sub SDP → T7: ICE+DTLS(pub)
→ T8: ICE+DTLS(sub) → T9: PUBLISH_TRACKS → T10: 첫 RTP → T11: TRACKS_ACK
→ T12: session ready
```

각 구간 `performance.now()` delta 수집 → 텔레메트리 전송. 모바일에서 `getUserMedia` 3초+ 빈번, DTLS도 환경별 편차 큼.

---

## 이번 세션 기각 후보

| 후보 | 이유 |
|------|------|
| 클라이언트 subscribeTracks() 수정 | 서버가 remove를 보내는 것이 근본 원인. 클라이언트는 정상 동작 |
| 기존 "mbcp" DC에 msg_type 4bit 확장 | 16개 한계 + 단일 책임 위반. svc 멀티플렉싱으로 결정 |
| DC 채널 label별 분리 (speakers, chat 등) | svc 멀티플렉싱이 구조적으로 깔끔 |
| Base64 JSON 래핑 WS fallback | WS binary frame으로 변환 비용 제로 |
| DCEP 앱 레벨 재시도 | SCTP reliable이 보장. PC 재연결에 의존 |

## 이번 세션 지침 후보

| 지침 | 근거 |
|------|------|
| PTT virtual track은 방 레벨 자원 — leave/zombie/unpublish 3경로 모두 잔존 참가자 체크 필수 | 0413b(moderate) + 0416a(leave/zombie) 동일 원칙 3회 적용 |
| DC 메시지 포맷: svc(1)+len(2 BE)+payload — DC/WS/gRPC 전 경로 공통 | 전송 계층과 메시지 포맷 완전 분리 |
| DC 채널 네이밍: "unreliable" / "reliable" | 전송 특성이 이름에 명시 |
| gRPC proto: oneof { json, binary } | 기존 JSON 무변경 + 바이너리 병행 |
| DC 상용 정석: WS fallback 필수 | LiveKit/mediasoup 모두 WS 병행. DC-only는 리스크 |

---

## PENDING

- [ ] DC 큐 위치 갱신 동작 확인 (RPi 배포 + 3인 이상 큐 테스트)
- [ ] Phase 1: DC unreliable svc 멀티플렉싱 (MBCP 래핑 + Active Speakers)
- [ ] Phase 2: DC reliable 채널 추가
- [ ] Phase 3: WS binary fallback (floor_ops.rs 복원 + gRPC oneof)
- [ ] DC 실패 감지 (onclose/onerror → pc:failed)
- [ ] DC readiness 버퍼링 (JOINED→ACTIVE 전환 중 메시지 유실 방지)
- [ ] 세션 시작 타임라인 텔레메트리 (T0~T12 delta)
- [ ] DC 건강 지표 텔레메트리 (bufferedAmount, readyState, svc 통계)

---

*author: kodeholic (powered by Claude)*
