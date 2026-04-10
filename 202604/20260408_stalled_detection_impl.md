# STALLED Detection 구현 (1~3단계 전체 완료)

> 2026-04-08 세션
> author: kodeholic (powered by Claude)

---

## 완료 사항

### STALLED 감지 — 서버 + 클라이언트 전체 구현

설계 문서 `context/design/20260407_stalled_detection_impl_guide.md` 기반.
1단계(서버 감지) + 2단계(시그널링 통보) + 3단계(클라이언트 복구 FSM) 일괄 구현.

#### 서버 변경 7파일

| 파일 | 변경 |
|------|------|
| `config.rs` | `STALLED_CHECK_INTERVAL_MS=5000`, `STALLED_THRESHOLD_MS=5000`, `STALLED_COOLDOWN_MS=30000` |
| `room/participant.rs` | `StalledSnapshot` struct + `stalled_tracker: Mutex<HashMap<u32, StalledSnapshot>>` |
| `signaling/opcode.rs` | `TRACKS_RESYNC(106)` → `TRACK_STALLED(106)` (dead code 정리) |
| `metrics/mod.rs` | `tracks_resync_sent` → `stalled_detected` (필드/new/flush/JSON 4곳) |
| `signaling/handler/track_ops.rs` | `record_stalled_snapshot()` 헬퍼 + TRACKS_ACK 양쪽 경로 호출 |
| `tasks.rs` | `run_stalled_checker()` 5초 interval |
| `lib.rs` | spawn 블록 추가 |

#### 클라이언트 변경 3파일

| 파일 | 변경 |
|------|------|
| `core/constants.js` | `TRACKS_RESYNC(106)` → `TRACK_STALLED(106)` |
| `core/signaling.js` | op=106 핸들러 → `track:stalled` emit |
| `core/health-monitor.js` | 전체 재작성 — Stalled Recovery FSM (3단계 복구) |

#### 핵심 설계 결정

1. **packet_count_at_ack 스냅샷 방식** — TRACKS_ACK 시점 send_stats.packets_sent 기록, 5초 후 delta==0이면 STALLED
2. **op=106 재사용** — TRACKS_RESYNC dead code 정리
3. **SSRC 기반 key** — send_stats 조회 O(1)
4. **쿨다운 보존** — tracker clear 시 prev_notified 이관
5. **PTT virtual SSRC** — "ptt" publisher_id로 별도 추적

#### 정당한 사유 5개

1. PTT floor 없음 (half-duplex + floor speaker 아님)
2. 트랙 muted
3. SubscriberGate paused
4. Simulcast pause
5. Publisher 퇴장/트랙 제거

#### 클라이언트 복구 FSM

```
NORMAL → TRACK_STALLED → RECOVERING_SYNC (ROOM_SYNC, 5s)
  → OK → NORMAL
  → fail → RECOVERING_RENEGO (sendTracksAck, 5s)
    → OK → NORMAL
    → fail → RECOVERING_RECONNECT (leave → rejoin)
      → OK → NORMAL
      → fail → GIVEN_UP
```

- RECOVERING_* 중 추가 TRACK_STALLED 무시
- 복구 중 decoder_stall 억제 (ROOM_SYNC 2회 방지)
- 이벤트: `stalled:detected`, `stalled:recovery`, `stalled:recovered`, `stalled:given_up`

### 테스트 결과

- Conference 3인 정상 시나리오: **STALLED 오진 없음** (스냅샷 확인 완료)
- 비정상 시나리오(의도적 fan-out 차단): 실운영 중 자연 발생 시 스냅샷으로 확인 예정

---

## 미완료

- 어드민 대시보드 `render-panels.js`에서 `tracks_resync_sent` → `stalled_detected` JSON 키 갱신
- `Cargo.toml` 버전 범프 (현재 env에 v0.6.15 표시)

---

## 오늘의 기각 후보

- **send_stats.last_send_time 방식**: packet_count_at_ack 스냅샷이 기존 코드 변경 최소

## 오늘의 지침 후보

- **STALLED checker는 zombie reaper와 독립** — zombie=heartbeat, STALLED=미디어. 합치지 않는다
- **op=106 재사용 시 기존 참조 전수 확인** — 서버 metrics 4곳 + 클라이언트 constants 1곳
- **복구 FSM에서 getStats delta 체크** — 1초 간격 2회 측정으로 "미디어 흐름 여부" 판정
