# 세션 컨텍스트: 2026-03-25 Phase 4 — Active Speaker + 배치 SUBSCRIBE_LAYER

## 세션 요약

Simulcast Phase 4 Step 1 완료: RFC 6464 audio-level 기반 Active Speaker 감지 파이프라인 전체 구현.
서버 + 웹 클라이언트 연동. 일반/시뮬캐스트 Conference 모드에서 정상 동작 확인.

---

## 완료된 작업

### 1. rtp_extension.rs — parse_audio_level() 추가

- RFC 6464 one-byte form: [V:1bit | level:7bit] 파싱
- V=VAD (voice activity), level=0~127 dBov (0=최대, 127=무음)
- 기존 find_extension() 범용 파서 재활용
- 테스트 3개 추가 (VAD=true, VAD=false, max volume)

### 2. room/speaker_tracker.rs — 신규 모듈

- `SpeakerTracker`: per-participant EWMA smoothed level
- EWMA α=0.3 (Opus 20ms 패킷 기준 ~60ms 수렴)
- VAD=false 패킷은 smoothed_level 갱신 안 함
- `SPEAKER_INACTIVE_MS=2000` — 2초간 VAD=true 없으면 후보 제외
- `ACTIVE_SPEAKER_SILENCE_THRESHOLD=80` dBov — 거의 무음 후보 제외
- `get_active_speakers(max_count)` — level 오름차순(음량 내림차순) 상위 N명
- `check_and_update()` — delta 비교, 변경 시에만 Some 반환
- `remove()` — 퇴장 시 정리
- 테스트 7개

### 3. config.rs — Active Speaker 상수

```rust
AUDIO_LEVEL_EXTMAP_ID: u8 = 4        // fallback (intent 우선)
ACTIVE_SPEAKER_INTERVAL_MS: u64 = 500 // 브로드캐스트 주기 (300→500 조정)
ACTIVE_SPEAKER_MAX_COUNT: usize = 3   // 상위 3명
ACTIVE_SPEAKER_SILENCE_THRESHOLD: u8 = 80  // 무음 임계값
```

### 4. opcode.rs — ACTIVE_SPEAKERS: u16 = 144

### 5. room/room.rs — speaker_tracker 필드 추가

- `speaker_tracker: Mutex<SpeakerTracker>` — Conference/PTT 모두 생성 (PTT에서는 사용 안 함)

### 6. ingress.rs — audio level 파싱 연동

- `StreamKind::Audio && room.mode != RoomMode::Ptt` 일 때만 처리
- intent의 `audio_level_extmap_id` 사용, 0이면 config fallback
- `speaker_tracker.update(user_id, vad, level)` 호출

### 7. tasks.rs — run_active_speaker_detector()

- 500ms 주기, Conference 방만 순회
- `check_and_update()` delta 방식 — 변경 시에만 WS 전송
- `ACTIVE_SPEAKERS` (op=144) 브로드캐스트
- `[SPEAKER]` 로그 (debug 레벨)

### 8. lib.rs — active speaker detector task spawn

### 9. room_ops.rs — ROOM_LEAVE + cleanup에서 speaker_tracker.remove()

### 10. 클라이언트 — audio_level_extmap_id 전달 + 화자 표시

- `media-session.js`: Chrome offer에서 `ssrc-audio-level` extmap ID 파싱 → intent에 `audio_level_extmap_id` 전달
- `stream_map.rs`: `MediaIntent`에 `audio_level_extmap_id: u8` 필드 추가
- `message.rs`: `PublishTracksRequest`에 `audio_level_extmap_id: Option<u8>` 추가
- `track_ops.rs`: MediaIntent 생성 시 `audio_level_extmap_id` 전달
- `constants.js`: `ACTIVE_SPEAKERS: 144`
- `signaling.js`: op=144 → `active:speakers` 이벤트 emit
- `index.html`: `.is-speaking` CSS (녹색 border + glow 애니메이션)
- `app.js`: `active:speakers` 리스너 → 타일 `.is-speaking` 토글

### 11. 배치 SUBSCRIBE_LAYER

- **서버 변경 불필요**: `SubscribeLayerRequest`가 이미 `targets: Vec<SubscribeLayerTarget>` 배열 구조
- 클라이언트가 배열로 보내면 서버가 순회하면서 처리

---

## 버그 발견 및 수정

### A. Chrome audio-level extmap ID 불일치 (첫 테스트 실패)
- **증상**: 서버 로그에 `[SPEAKER]` 전혀 안 찍힘. 화자 표시 무반응
- **원인**: client-offer 모드에서 Chrome이 `ssrc-audio-level`에 할당하는 extmap ID가 서버 하드코딩(4)과 다름. rid/twcc/mid와 동일한 패턴
- **수정**: Chrome offer에서 실제 ID 추출 → intent에 `audio_level_extmap_id` 전달 → ingress에서 동적 사용 (fallback=config)

---

## 테스트 결과

- 일반 Conference 2인: ✅ 화자 녹색 테두리 정상
- Simulcast Conference 2인: ✅ 화자 녹색 테두리 정상
- 한쪽 마이크 mute → 다른 쪽만 녹색: ✅ 정상
- 양쪽 마이크 ON → 양쪽 녹색: ✅ 정상 (PC 1대 같은 마이크 공유 시)

---

## 변경 파일 전체 목록

### 서버 (oxlens-sfu-server)

| 파일 | 변경 |
|------|------|
| `src/room/speaker_tracker.rs` | **신규** — SpeakerTracker 모듈 (EWMA, delta, 테스트 7개) |
| `src/room/mod.rs` | `pub mod speaker_tracker` 추가 |
| `src/transport/udp/rtp_extension.rs` | `parse_audio_level()` 추가 + 테스트 3개 |
| `src/config.rs` | Active Speaker 상수 4개 |
| `src/signaling/opcode.rs` | `ACTIVE_SPEAKERS: u16 = 144` |
| `src/room/room.rs` | `speaker_tracker` 필드 + import + 초기화 |
| `src/room/stream_map.rs` | `MediaIntent`에 `audio_level_extmap_id` 추가 + 테스트 |
| `src/signaling/message.rs` | `PublishTracksRequest`에 `audio_level_extmap_id` 추가 |
| `src/signaling/handler/track_ops.rs` | MediaIntent 생성 시 `audio_level_extmap_id` 전달 |
| `src/transport/udp/ingress.rs` | audio level 파싱 (intent 동적 ID) + speaker_tracker 연동 |
| `src/signaling/handler/room_ops.rs` | ROOM_LEAVE + cleanup에서 `speaker_tracker.remove()` |
| `src/tasks.rs` | `run_active_speaker_detector()` 500ms 주기 |
| `src/lib.rs` | active speaker detector task spawn |

### 클라이언트 (oxlens-home)

| 파일 | 변경 |
|------|------|
| `core/constants.js` | `ACTIVE_SPEAKERS: 144` |
| `core/signaling.js` | op=144 → `active:speakers` emit |
| `core/media-session.js` | Chrome offer에서 `ssrc-audio-level` extmap ID 추출 → intent 전달 |
| `demo/client/index.html` | `.is-speaking` CSS |
| `demo/client/app.js` | `active:speakers` 리스너 → 타일 `.is-speaking` 토글 |

---

## 이전 세션 대화에서 확정된 설계 방향

### Active Speaker → Simulcast 연동 (mediasoup 패턴)
- **판단 주체는 클라이언트** — 서버는 ACTIVE_SPEAKERS 이벤트만 제공
- 서버가 레이어를 제어하면 UI 레이아웃과 무관하게 저화질로 빠질 수 있음
- 클라이언트가 UI 레이아웃 기반으로 "발화자 → h, 나머지 → l, 안 보임 → pause" 결정

### Dynacast
- 2PC + 클라이언트 SDP 조립 구조라 서버 renegotiation 불필요
- 서버: "이 publisher의 high layer 구독자 0명" 감지 → 시그널 전달
- SDK: `setParameters()`로 `encoding.active = false`
- 가드 필요: 디바운스(끄기 보수적, 켜기 즉시), 새 참가자 입장 시 선제 활성화
- Phase 4 이후, 데모 고도화 단계에서 구현

### 이벤트 트리거 ROOM_SYNC
- 1분 주기 폴링은 유지 (오히려 2~3분으로 늘려도 됨)
- 클라이언트가 "흔들렸다"를 감지하면 즉시 op=50 전송 (WS 재접속, ICE restart, 네트워크 전환, RTP 3초 무수신)
- 디바운스 1~2초
- 데모 후 고도화 단계에서 구현

### playout-delay extension (PTT 초저지연)
- SFU가 egress에서 `min=0, max=0` 주입 → 수신 측 jitter buffer 최소화
- PTT rewrite 경로에서 추가 비용 거의 없음
- 데모 후 고도화 단계에서 구현

---

## 기각된 접근법

### audio-level extmap ID 하드코딩
- `config::AUDIO_LEVEL_EXTMAP_ID = 4` 고정 사용
- **기각 사유**: client-offer 모드에서 Chrome이 할당하는 ID가 4가 아닐 수 있음. rid/twcc/mid와 동일한 문제. intent에서 동적으로 전달해야 함.

---

## 핵심 학습

### extmap ID는 반드시 동적으로 전달
- server_extmap_policy에서 ID를 지정해도, client-offer 모드에서는 Chrome이 다른 ID를 할당
- 모든 extmap은 intent를 통해 Chrome offer의 실제 ID를 서버에 전달해야 함
- 이번 `audio_level_extmap_id` 추가로 완성: mid, rid, repair_rid, twcc, audio_level 전부 동적

### delta 방식 브로드캐스트의 효율성
- check_and_update()가 이전 상태와 비교 → 변경 시에만 전송
- 30인 방에서 아무도 안 말하면 WS 메시지 0개
- 500ms 주기여도 실제 전송은 발화자 변경 시점에만

---

## 다음 세션 TODO

### P1: 레이아웃 변경 (발화자 큰 타일 + 썸네일 스트립)
- 현재 동일 크기 그리드 → active speaker에 따른 차등 레이아웃
- SKILL에 "5+ with scrollable thumbnail strip" 설계 있음
- 이 레이아웃이 있어야 core/abr/ 모듈이 의미 있음

### P2: core/abr/ 모듈 (speaker-tracker.js + layer-selector.js)
- ACTIVE_SPEAKERS 수신 → 레이아웃 기반 판단 → 배치 SUBSCRIBE_LAYER 전송
- 큰 타일 → h, 썸네일 → l, 화면 밖 → pause

### P3: SKILL_OXLENS.md 업데이트
- Phase 4 Active Speaker 완료 반영
- 서버 버전 v0.7.x (Phase 4 포함)

### P4: CHANGELOG.md 업데이트

---

*author: kodeholic (powered by Claude)*
