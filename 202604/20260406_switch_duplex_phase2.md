# 2026-04-06: SWITCH_DUPLEX Phase 2 — full→half 역전환 + 음성 디버깅

## 요약

SWITCH_DUPLEX Phase 2 (full→half) 서버+클라이언트 구현 완료. 음성 수신 복구(track.enabled 버그). PTT jb_delay 폭증 미해결 — 다음 세션에서 집중.

## 수정 파일

### 서버 (oxlens-sfu-server)
| 파일 | 변경 |
|------|------|
| `track_ops.rs` | Phase 1 가드 제거, `to_full` 분기 양방향 지원, floor.release 무조건 호출(queue 포함), 디버그 로그 추가 |
| `ptt_rewriter.rs` | `reset_relay_timing()` 메서드 추가 (사용 안 함 — 아래 기각 참조) |

### 클라이언트 (oxlens-home)
| 파일 | 변경 |
|------|------|
| `core/client.js` | `switchDuplex()` guard 양방향 허용, `_onSwitchDuplexOk` "half" 분기 (PTT reattach) |
| `core/client.js` | ⚠️ `audioTrack.enabled = false` 제거 — PTT는 서버 floor gating이 담당 |
| `demo/scenarios/dispatch/index.html` | `btn-f-half` disabled 제거 |
| `demo/scenarios/dispatch/app.js` | `switchFieldToHalfDuplex()` + duplex:switched "half" 핸들러 + btn-f-half 클릭 |

## 해결된 버그

### 1. switchDuplex() 클라이언트 guard Phase 1 전용
- **증상**: full 상태에서 half 요청 시 `에러 5202: 이미 full-duplex 상태`
- **원인**: guard가 `audioDuplex !== "half"` + `duplex !== "full"` — Phase 1 전용
- **수정**: `audioDuplex === duplex` (같을 때만 차단) + full/half 둘 다 허용

### 2. audioTrack.enabled = false (음성 수신 불가)
- **증상**: full→half 전환 후 PTT 발화해도 상대방에게 음성 안 들림
- **원인**: `_onSwitchDuplexOk("half")`에서 `audioTrack.enabled = false` 설정 → 브라우저가 silence만 송출
- **핵심**: PTT는 서버 floor gating이 담당. 브라우저 track.enabled는 항상 true 유지
- **수정**: enabled 설정 제거, `_muted.audio = false` 유지

## 미해결: PTT jb_delay 폭증 (다음 세션 최우선)

### 증상
- full→half 전환 후 PTT 발화 시 jb_delay=840~927ms (정상 30-50ms)
- "3초 뒤에 첫음 들림", 반복 시 "돌림노래"
- **첫 방 입장부터 발생하는 케이스도 있음** (duplex 전환 무관)

### 분석 경과
1. **reset_relay_timing 시도 → 기각**: full→half 시 last_relay_at을 now로 리셋하면 ts_gap < arrival_gap → 불일치 → NetEQ가 jitter로 해석 → 오히려 악화
2. **reset_relay_timing 제거**: 자연스럽게 ts_gap = arrival_gap 일치시키는 것이 정답. 하지만 여전히 첫 방부터 지연 발생 → duplex 전환과 무관한 근본 원인 있음

### 다음 세션 조사 방향
- **첫 방 PTT jb_delay 재현 조건 파악** — duplex 전환 없이 순수 PTT만으로 재현되는지
- **ts_guard_gap=48000(1초)** 영향 확인 — 짧은 idle 후 발화 시 ts가 1초 강제 점프, arrival gap이 짧으면 불일치
- **silence flush 3프레임과 첫 발화 패킷 사이의 ts/seq 연속성** 검증
- **스냅샷에서 audio pt=0, codec=VP8 표시 버그** — 트랙 등록 시 audio pt/codec 미설정 (기능 무관, 진단 오염)

## 확인된 설계 판단

### PttRewriter 재초기화 불필요 (확인됨)
- half→full 시 clear_speaker() → speaker=None, virtual_base_seq bumped, last_relay_at 갱신(silence flush)
- full→half 복귀 후 floor grant → switch_speaker() → 첫 패킷에서 offset 자동 확정
- stream_map.update_duplex() 정상 동작 확인 (updated=true, HalfNonSim)

### floor.release() 무조건 호출 (수정됨)
- 기존: current_speaker일 때만 호출 → REQUESTING/QUEUED 상태에서 전환 시 큐에 잔류
- 수정: 무조건 호출 → speaker면 해제+silence flush, queue면 제거(silent)

### make-before-break 확인
- full→half 시 subscriber re-nego 불필요 (m-line 잔류)
- 서버가 relay만 중단, ingress gating이 HalfNonSim으로 즉시 전환

## 기각 후보

### reset_relay_timing (추가 후 제거)
- full→half 시 last_relay_at을 now로 리셋
- **기각 이유**: ts_gap < arrival_gap 불일치 → NetEQ가 네트워크 jitter로 해석 → jb_delay 폭증
- **원칙**: ts_gap은 arrival_gap과 일치해야 함. 인위적 조작 금지

### audioTrack.enabled = false (제거)
- Conference 패턴(track.enabled 토글)을 PTT에 잘못 적용
- **원칙**: PTT audio gating = 서버 floor gating. 브라우저 track.enabled는 항상 true

## 지침 후보

- **PTT audio track.enabled는 항상 true**: 서버가 floor gating 담당. 클라이언트에서 track.enabled=false로 만들면 floor 획득해도 silence만 송출
- **PttRewriter last_relay_at 인위 조작 금지**: ts_gap은 arrival_gap과 자연스럽게 일치해야 NetEQ 정상. 리셋하면 불일치 → jb_delay 폭증
- **duplex 전환 시 floor.release() 무조건 호출**: speaker+queue 모두 커버

## 커밋 메시지

### oxlens-sfu-server
```
feat(signaling): SWITCH_DUPLEX Phase 2 — bidirectional half↔full transition

- Remove Phase 1 guard, support both half→full and full→half
- full→half: state change only, no subscriber re-nego (make-before-break)
- floor.release() unconditional — covers speaker + queue cleanup
- Debug log: stream_map update verification (updated/tt)
- reset_relay_timing added but disabled (ts_gap must match arrival_gap)
```

### oxlens-home
```
fix(sdk): SWITCH_DUPLEX Phase 2 client — full→half with PTT reattach

- switchDuplex() guard: allow both directions (was half→full only)
- _onSwitchDuplexOk("half"): PTT reattach + audio track stays enabled
- Remove audioTrack.enabled=false — PTT uses server floor gating
- dispatch: btn-f-half enabled + switchFieldToHalfDuplex() + click handler
```

---

*author: kodeholic (powered by Claude)*
