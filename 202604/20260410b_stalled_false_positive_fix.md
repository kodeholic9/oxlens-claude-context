# 세션: STALLED 오탐 근본 수정 + HealthMonitor 단순화

**날짜**: 2026-04-10
**영역**: oxsfud (track_ops.rs) + oxlens-home (health-monitor.js, voice_radio, video_radio)
**상태**: 빌드 확인 완료. Conference/PTT 정상 동작 확인.

---

## 작업 내역

### 1. STALLED PTT 오탐 — 근본 원인 규명 + 수정

**증상**: PTT 방(voice_radio, video_radio) join 후 ~10초에 STALLED 발생 → HealthMonitor Phase 3(leave→rejoin) → 전원 퇴장

**근본 원인**: `record_stalled_snapshot`이 half-duplex 트랙의 **원본 SSRC**를 stalled_tracker에 등록. PTT 미디어는 PttRewriter를 거쳐 **가상 SSRC**로만 subscriber에게 relay. 따라서 원본 SSRC의 send_stats는 아키텍처상 영원히 0.

- 현재 speaker의 원본 SSRC → half-duplex 체크 통과(is_speaker=true) → send_stats delta=0 → **오탐**
- 비 speaker의 원본 SSRC → half-duplex 체크에서 skip되지만, speaker일 때 문제
- 가상 SSRC는 `"ptt"` publisher로 별도 등록 → floor idle 체크 정상 동작

**수정**: `record_stalled_snapshot`에서 `t.duplex == DuplexMode::Half`인 트랙의 원본 SSRC 등록을 skip. 가상 SSRC(`"ptt"`)는 아래 블록에서 별도 등록되므로 기존 동작 유지.

**사이드 이펙트 없음 확인**:
- PTT에서 원본 SSRC로 subscriber에게 직접 relay하는 경로 없음
- full-duplex 트랙은 영향 없음 (조건이 half-duplex만 skip)
- full+half 혼합 시나리오도 정상

### 2. HealthMonitor 단순화

**이전 구조**: Phase 1(ROOM_SYNC) → Phase 2(sendTracksAck) → Phase 3(leave→rejoin)

**문제점**:
- Phase 2: `sendTracksAck()`은 SSRC 목록 재전송. 서버에서 stalled_tracker 리셋만 됨. 미디어 복구 효과 없음
- Phase 3: `leaveRoom()` → SDK가 `room:left` emit → 앱 UI가 이전 화면으로 전환 → rejoin 전에 UI가 이미 나가버림. 카메라 켜진 채 통화화면 이탈
- `_checkMediaFlow`: subscribe PC 전체 packetsReceived 합산 delta. 트랙 단위 STALLED에 전체 합산 판정 → 정밀도 불일치

**수정 후 구조**: STALLED 수신 → ROOM_SYNC 1회 전송 + 토스트("트랙이상이 발생하였습니다. 복구합니다.") + 5초 쿨다운. Phase 2/3/`_checkMediaFlow` 전부 제거.

**설계 근거**: ROOM_SYNC로 트랙 정합성이 맞춰지면 미디어가 복구되어야 함. 안 되면 서버 버그.

---

## 변경 파일 목록

| 파일 | 변경 |
|------|------|
| `oxsfud/src/signaling/handler/track_ops.rs` | `record_stalled_snapshot` half-duplex 원본 SSRC skip |
| `oxlens-home/core/health-monitor.js` | Phase 2/3 제거, `_checkMediaFlow` 제거, RECOVERY_STATE 정리 |
| `oxlens-home/demo/scenarios/video_radio/app.js` | `stalled:recovery` 토스트 추가 |
| `oxlens-home/demo/scenarios/voice_radio/app.js` | `stalled:recovery` 토스트 추가 |

---

## 기각 사항

| 기각 | 이유 |
|------|------|
| floor grace period (last_transition_at) | 근본 원인이 원본 SSRC 등록 자체. grace period는 증상 완화일 뿐 |
| recv_stats 교차 체크 | 원본 SSRC가 등록 안 되면 불필요. 복잡도만 증가 |
| STALLED 감지 전체 비활성화 | 감지 자체는 필요. 진짜 stalled 케이스(SDP 꼬임, Gate 미열림 등) 존재 |
| Phase 3(leave→rejoin) 유지 | UI가 room:left를 받아 화면 전환 → rejoin 전에 이탈. reason 분기로 해결 가능하나 ROOM_SYNC 실패=서버버그이므로 과잉 |
| Phase 2(sendTracksAck) 유지 | 미디어 복구 효과 없음. stalled_tracker 리셋만 — 타이머 벌이일 뿐 |
| `_checkMediaFlow` 유지 | 전체 합산 vs 트랙 단위 불일치. 자체 판단 불필요 |
| reason 기반 room:left 분기 | Phase 3 자체를 제거하므로 불필요 |

## 오늘의 지침 후보

- **PTT에서 원본 SSRC는 subscriber에게 relay되지 않는다**: stalled_tracker, send_stats 등 subscriber 관련 데이터에 half-duplex 원본 SSRC를 넣으면 안 됨. 가상 SSRC만 유효
- **ROOM_SYNC 실패 = 서버 버그**: 클라이언트에서 에스컬레이션(sendTracksAck, leave→rejoin)으로 복구하려는 시도는 근본 해결이 아니라 증상 은폐

---

## 로그 분석 핵심 발견

서버 로그(`oxsfud.log.2026-04-10`)에서 확인된 연쇄:
```
join → PUBLISH_TRACKS(HalfNonSim) → TRACKS_ACK
→ 10초 후 STALLED(원본 SSRC, send_stats 영원히 0)
→ HealthMonitor Phase 1(ROOM_SYNC) → Phase 2(sendTracksAck) → Phase 3(leaveRoom)
→ room:left → 앱 UI 이전 화면 전환 (카메라 ON 유지)
→ 전원 순차 퇴장
```

---

*author: kodeholic (powered by Claude)*
