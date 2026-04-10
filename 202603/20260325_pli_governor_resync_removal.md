# 세션 컨텍스트: 2026-03-25 PLI Governor + RESYNC 제거

## 세션 요약

PLI Governor (인과관계 기반 PLI 평탄화) 구현 완료 + TRACKS_ACK mismatch 시 RESYNC 제거.
4인 simulcast conference 완벽 동작 확인. 전원 decoded_delta=71+, fps=24, loss=0%, pli_thrt=0.

---

## 완료된 작업

### 1. PLI Governor 신규 구현

**신규 파일 `src/room/pli_governor.rs`:**
- 업계 SFU(LiveKit/mediasoup/Janus) 시간 스로틀과 달리 **인과관계 기반 판단**
- "PLI 보냈다 → I-Frame 왔는가 → subscriber에게 릴레이됐는가" 관측 사실로 결정
- Layer enum (High/Low/Pause) + min() 연산
- PliPublisherState: 레이어별 pli_pending, last_pli_forwarded_at, last_keyframe_received_at
- PliSubscriberState: user_preferred_layer, governor_layer, effective_layer, needs_keyframe, consecutive_pli_count, 자동 다운/업그레이드 상태
- judge_subscriber_pli(): subscriber PLI 수신 시 Forward/Drop 판단 + 다운그레이드 트리거
- judge_server_pli(): 서버 자발적 PLI burst 판단 (I-Frame 도착 시 취소)
- on_keyframe_received(), on_keyframe_relayed(): I-Frame 도착/릴레이 시 상태 갱신
- should_upgrade(), apply_downgrade(), apply_upgrade(): 자동 레이어 전환 (Phase 2 TODO)
- 테스트 5개 포함

### 2. config.rs PLI Governor 상수 추가

```rust
PLI_RETRY_TIMEOUT_H: 1500ms    // h PLI 유실 재전송 타임아웃
PLI_RETRY_TIMEOUT_L: 500ms     // l PLI 유실 재전송 타임아웃
PLI_MIN_INTERVAL_H: 300ms      // h PLI 최소 간격
PLI_MIN_INTERVAL_L: 100ms      // l PLI 최소 간격
PLI_STALE_KEYFRAME_TIMEOUT: 2s // I-Frame 릴레이 유실 대비
PLI_DOWNGRADE_THRESHOLD_H: 3   // h 연속 PLI → l 다운그레이드
PLI_DOWNGRADE_THRESHOLD_L: 5   // l 연속 PLI → pause 검토
PLI_UPGRADE_STABLE_PERIOD: 5s  // 업그레이드 복귀 안정 기간
PLI_UPGRADE_BACKOFF_BASE: 5s   // 백오프 베이스
PLI_UPGRADE_BACKOFF_MAX: 60s   // 백오프 최대
```

### 3. participant.rs 변경

- `PliPublisherState` import + `pli_pub_state: Mutex<PliPublisherState>` 필드 추가
- `SubscribeLayerEntry`에 `pli_state: PliSubscriberState` 필드 추가

### 4. ingress.rs Governor 통합

- subscriber PLI 릴레이: 3초 고정 스로틀 → Governor `judge_subscriber_pli()` 교체
- Simulcast fan-out: I-Frame 감지 → `on_keyframe_received()` 호출
- Simulcast fan-out: I-Frame 릴레이 완료 → `on_keyframe_relayed()` 호출
- Non-simulcast fan-out: I-Frame 감지 → `on_keyframe_received()` 호출

### 5. pli.rs Governor 통합

- `spawn_pli_burst` 각 발사 전 `judge_server_pli()` 체크
- I-Frame 도착 확인 시 나머지 burst 자동 취소
- **Governor bypass**: GATE:PLI, RESYNC:PLI, NACK_ESC, RTP_GAP → 무조건 발사

### 6. track_ops.rs Governor 통합

- GATE:PLI / RESYNC:PLI 발사 전 `pli_pub_state` 리셋 (gate 기간 중 I-Frame 기록 클리어)

### 7. TRACKS_ACK mismatch RESYNC 제거

- mismatch 발생 시 TRACKS_RESYNC 전송 **제거**
- gate만 정리 + GATE:PLI 발사 + `synced: true` 반환
- subscribe PC 전체 재생성 없음 → 기존 정상 스트림 유지

---

## 테스트 결과

### 4인 Simulcast Conference (최종)
- 전원 decoded_delta=71+, fps=24, loss=0% ✅
- pli_thrt=0 (Governor 과잉 차단 제로) ✅
- GATE:PLI 25건 정상 동작 ✅
- burst CANCELLED 36건 (Governor I-Frame 확인 → 불필요 burst 자동 취소) ✅
- RESYNC 0건 ✅
- mismatch tolerated 52건 (subscribe PC 유지) ✅

---

## 버그 발견 및 수정

### A. Governor가 인프라 PLI까지 간섭 (첫 테스트 실패)
- **증상**: 전원 decoded_delta=0, pli_thrt=94
- **원인**: GATE:PLI, RESYNC:PLI가 Governor 판단을 거치면서 차단됨. gate 기간 중 I-Frame은 subscriber에게 전달 안 됐는데 publisher 측 상태에는 "도착함"으로 기록 → 불일치
- **수정**: (1) GATE/RESYNC/NACK_ESC/RTP_GAP은 Governor bypass. (2) GATE/RESYNC PLI 전 publisher `pli_pub_state` 리셋.

### B. TRACKS_ACK mismatch → RESYNC 연쇄 (P0 이슈 근본 해결)
- **증상**: 새 참여자 입장 시 기존 subscriber 영상 끊김
- **원인**: mismatch → RESYNC → subscribe PC 전체 재생성 → SimulcastRewriter seq/ts 불연속 → Chrome 디코더 거부
- **수정**: RESYNC 제거. mismatch tolerate + gate 정리 + GATE:PLI. subscribe PC 유지.

---

## 변경 파일 전체 목록

### 서버 (oxlens-sfu-server)

| 파일 | 변경 |
|------|------|
| `src/room/pli_governor.rs` | **신규** — Governor 상태 모델 + 판단 로직 + 테스트 5개 |
| `src/room/mod.rs` | `pub mod pli_governor` 추가 |
| `src/config.rs` | PLI Governor 상수 10개 추가 |
| `src/room/participant.rs` | import, pli_pub_state 필드, SubscribeLayerEntry.pli_state 추가 |
| `src/signaling/handler/track_ops.rs` | import, SubscribeLayerEntry pli_state 초기화, GATE/RESYNC PLI Governor 리셋, **RESYNC 제거** |
| `src/transport/udp/ingress.rs` | import, subscriber PLI→Governor 교체, I-Frame 감지→통지, I-Frame 릴레이→통지 |
| `src/transport/udp/pli.rs` | import, burst Governor 체크, bypass 로직 |

---

## 기각된 접근법

### 비대칭 마이크로 키프레임 주입 (제미나이 제안)
- l-layer I-Frame 1개를 h SSRC로 위장 → 즉시 h P-Frame 복귀
- **기각 사유**: 코덱 참조 프레임 체인 파괴. h P-Frame은 h I-Frame을 참조.

### 고정 시간 스로틀만 사용 (LiveKit/mediasoup 방식)
- `last_pli_at + interval` 체크
- **기각 사유**: 상황을 모름. I-Frame 도착 여부 판단 불가.

### TRACKS_ACK mismatch → RESYNC (이전 구현)
- subscribe PC 전체 재생성
- **기각 사유**: 기존 정상 스트림까지 중단. SimulcastRewriter 불연속 → decoded_delta=0.

---

## 핵심 학습

### PLI Governor 설계 원칙
- 관측 사실 기반 (영상 콘텐츠 예측 안 함)
- 시간 임계치는 안전망 (주 판단은 상태)
- 레이어별 차등 (h 무겁고 l 가벼움)
- 인프라 PLI는 Governor bypass (GATE/RESYNC/NACK_ESC/RTP_GAP)

### RESYNC의 악영향
- subscribe PC 전체 재생성은 핵폭탄 — 기존 정상 스트림까지 파괴
- mismatch tolerate가 정답 — missing SSRC는 ROOM_SYNC 폴링으로 자연 복구

### Governor bypass의 필요성
- gate 기간 중 I-Frame은 subscriber에게 전달 안 됨
- publisher 측 "도착함" 기록과 subscriber 측 "못 받음" 불일치
- 인프라 목적 PLI는 Governor 판단 없이 무조건 발사해야 함

---

## 다음 세션 TODO

### P1: Governor Phase 2 — 자동 레이어 다운/업그레이드
- consecutive_pli_count >= DOWNGRADE_THRESHOLD_H → governor_layer = l
- effective_layer = min(user_preferred, governor) → SimulcastRewriter 정식 전환
- 백오프 진동 방지

### P2: SKILL_OXLENS.md 업데이트
- PLI Governor, RESYNC 제거, 기각 사항 반영
- 서버 버전 v0.7.x

### P3: mismatch 원인 조사
- extra SSRC(3025000372) 반복 발생 — 원인 파악 후 mismatch 자체 감소

---

*author: kodeholic (powered by Claude)*
