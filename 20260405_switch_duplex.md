# 2026-04-05: SWITCH_DUPLEX (op=52) 설계 + 서버 구현

## 요약

트랙 duplex 런타임 전환 기능 설계 및 서버 Phase 1 구현 완료.
같은 방에서 half-duplex(PTT) → full-duplex(양방향) 전환을 SDP re-nego 최소화로 실현.

## 설계 핵심 (부장님 설계)

### make-before-break 원칙
- 최초 전환 시: subscriber에 원본 audio track add → SDP re-nego 1회
- 이후 왔다갔다: relay 경로 스위칭 + MUTE_UPDATE만 (re-nego 없음)
- m-line을 남겨두고 서버가 relay만 안 하면 subscriber는 silence 처리
- full→half 역전환 시 re-nego 불필요 (m-line 잔류)

### TrackType 추상화의 성과
- ingress `match track_type` 분기가 이미 FullNonSim/HalfNonSim 경로를 완전 분리
- SWITCH_DUPLEX가 해야 할 일 = track_type 값 변경 뿐
- 새 fan-out 로직 0줄. RoomMode 제거 → 트랙 단위 duplex가 이 기능을 자연스럽게 가능하게 함

## 시장 분석

### 음성 half↔full 전환
- 실수요 확인: 3GPP MCPTT "Private Call escalation" 규격에 명시
- 기존 해법: 별도 SIP 세션 생성 (MCPTT), 채널 이탈 (TETRA/P25), 미지원 (Zello/Voxer)
- OxLens 차별점: 같은 방 내 인플레이스 전환, 기존 채널 청취 유지

### 영상 half↔full 전환
- 시장 필요성 낮음 확인
- 영상은 PTT 화자의 one-way push (MCVideo) 또는 별도 full-duplex 세션
- Motorola WAVE PTX, OSNET 등 모두 영상 PTT와 양방향 영상을 별개 기능으로 분리
- → 영상 duplex 전환은 구현하지 않음. 프리셋 간 전환으로 충분

## 시그널링 설계

### op=52 SWITCH_DUPLEX (Client → Server)
```json
{ "op": 52, "d": { "kind": "audio", "duplex": "full" } }
```

### TRACKS_UPDATE 확장 — action: "duplex_changed"
```json
{ "op": 101, "d": { "action": "duplex_changed", "user_id": "alice", "kind": "audio", "duplex": "full", "ssrc": 12345678 } }
```

## 서버 처리 시퀀스 (half → full)

```
Phase A: 상태 변경
  1. Track.duplex = Full
  2. stream_map track_type = FullNonSim + intent.audio_duplex 갱신
  3. floor 자동 해제 (현재 화자면) + silence flush

Phase B: subscriber 준비
  4. TRACKS_UPDATE(add) — 원본 audio track broadcast
  5. subscriber SDP re-nego → TRACKS_ACK

Phase C: 알림
  6. TRACKS_UPDATE(duplex_changed) broadcast (전체)
  7. agg-log: duplex:switched
```

## 수정 파일 (서버, 6파일)

| 파일 | 변경 |
|---|---|
| opcode.rs | `SWITCH_DUPLEX = 52` 추가 |
| message.rs | `SwitchDuplexRequest` 구조체 |
| participant.rs | `Track.original_duplex` 필드, `switch_track_duplex()` 메서드 |
| stream_map.rs | `update_duplex()`, `update_audio_duplex()` 메서드 |
| handler/mod.rs | op=52 dispatch |
| track_ops.rs | `handle_switch_duplex()` ~110줄 |

## Phase 구분

| Phase | 범위 | 상태 |
|---|---|---|
| Phase 1 | half → full 전환 (서버) | ✅ 구현 완료, 빌드 성공 |
| Phase 1 | half → full 전환 (클라이언트) | 다음 세션 |
| Phase 2 | full → half 역전환 | 미정 — PttRewriter 재초기화 필요 |
| Phase 3 | selective routing (특정 참가자 대상) | 미정 — 멀티채널 구조 선행 |

## 에러 코드

| 코드 | 메시지 |
|---|---|
| 5201 | no track for kind / unsupported kind |
| 5202 | already in requested duplex |
| 5203 | only half->full supported / track was not originally half-duplex |

## 기각 후보
- **PUBLISH_TRACKS 재활용으로 duplex 전환**: 의미가 어긋남 (intent 선언 vs 속성 변경). 전용 opcode가 명확
- **영상 duplex 전환 구현**: 시장 필요성 낮음. MCVideo는 one-way push가 주류
- **full→half Phase 1 포함**: PttRewriter 초기화 + gating 즉시 적용 복잡도. 분리가 안전

## 지침 후보
- **SWITCH_DUPLEX는 상태 변경 + 기존 흐름 재활용**: 새 fan-out 로직 불필요. TrackType이 라우팅을 결정
- **original_duplex로 전환 범위 제한**: 원래 half인 참가자만 전환 가능

## BWE 이슈 (전 세션 이월)
- 미해결: BWE cold start (addTransceiver/removeTransceiver on camera toggle)
- 합의된 방향: blank video transceiver at PC init + replaceTrack
- Chrome Initial Probing 동작 미검증

## 커밋 메시지

### oxlens-sfu-server
```
feat(signaling): add SWITCH_DUPLEX op=52 — runtime half→full duplex transition

- Phase 1: half→full audio only (full→half deferred to Phase 2)
- Track.original_duplex field for transition scope limiting
- stream_map.update_duplex() for ingress TrackType hot-swap
- Auto floor release + silence flush on transition
- TRACKS_UPDATE(add) for subscriber re-nego + duplex_changed broadcast
- Zero new fan-out logic — TrackType abstraction handles routing
```
