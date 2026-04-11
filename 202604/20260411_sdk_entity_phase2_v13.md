# 2026-04-11 세션 (2차): SDK 엔티티 Phase 2 — v1.3 완료 + Room 이관

> author: kodeholic (powered by Claude)

---

## 작업 요약

v1.3 코딩 완료 (applied state 캡슐화, 디버깅 장치 3종). Engine 책임을 Room 계층으로 이관: mute Phase 1, reconnect Pipe 기반, filter/PTT/device API 확장.

---

## 완료된 작업

### v1.3: applied state 캡슐화 (4파일)

- **media-session.js**: `_applied` Map(mic/camera/screen) + `applyTrackConfig()`/`getApplied()`/`dumpApplied()` + legacy setter 6개
- **engine.js**: 직접접근 20곳 캡슐화 + `_simulcastEnabled` 자체 필드 제거
- **room.js**: 6곳 캡슐화
- **power-fsm.js**: 2곳 캡슐화
- **디버깅**: 전이 로그(applyTrackConfig 내장), drift 감지(10초 주기), applied 스냅샷(telemetry 병합)
- **import**: room.js `OxLensClient`→`Engine`, client.js shim 생성, index.js Engine export

### Mute 이관 Phase 1 (3파일)

- **pipe.js**: `_localMuted` 필드 추가
- **room.js**: `toggleMute(kind)` — Pipe.duplex 기반 4갈래 분기 판단, Engine 실행 위임. `isMuted(kind)` — Pipe._localMuted 조회. `mute:changed` → `pipe:localMuted`/`pipe:localUnmuted`
- **endpoint.js**: `muteAudio`/`muteVideo` → Room 경유

### Reconnect 이관 — Pipe 기반 (2파일)

- **engine.js**: `_autoRejoinEnabled` 플래그. Room이 false 설정 → Engine _autoRejoin 비활성화
- **room.js**: `_savedReconnect` 필드. RECONNECTING에서 Pipe 스냅샷 저장 → IDENTIFIED에서 `_pipeBasedRejoin()` (Pipe 정보로 applyTrackConfig + joinRoom)

### API 확장 (2파일)

**endpoint.js (LocalEndpoint):**
- `addFilter(source, name, filter)` / `removeFilter` / `clearFilters` — source 기반 통합 filter API
- `switchCamera()` / `setInputGain(value)` / `setAudioProcessing(opts)`

**room.js:**
- `speaker` / `floorState` / `simulcastEnabled` getter (PTT 상태)
- `roomId` / `userId` / `connState` getter (기본 정보)
- `addOutputElement(el)` / `removeOutputElement(el)` (오디오 출력)

---

## 변경 파일 목록 (전체 세션)

| 파일 | 변경 |
|------|------|
| `core/media-session.js` | `_applied` Map + API 3개 + legacy setter 6개 + 내부참조 전환 |
| `core/engine.js` | 직접접근 캡슐화 + `_simulcastEnabled` 제거 + `_autoRejoinEnabled` |
| `core/room.js` | 캡슐화 + toggleMute/isMuted + drift + reconnect + getter 확장 |
| `core/endpoint.js` | muteAudio/muteVideo Room 경유 + filter/camera/audio API |
| `core/pipe.js` | `_localMuted` |
| `core/ptt/power-fsm.js` | 2곳 캡슐화 |
| `core/telemetry.js` | applied_state 스냅샷 |
| `core/client.js` | **신규** re-export shim |
| `core/index.js` | Engine export 추가 |

---

## 이관 현황

| 항목 | 상태 | 비고 |
|------|------|------|
| remote audio 관리 | ✅ v1.2 | Room auto-mount |
| duplex/simulcast 보관 | ✅ v1.3 | Pipe(desired) + MediaSession(applied) |
| mute 제어 | ✅ Phase 1 | Room 분기 판단 + Engine 실행 |
| reconnect | ✅ | Room Pipe 기반, Engine standalone 유지 |
| filter pipeline | ✅ API | LocalEndpoint 통합 API, 내부 Engine 위임 |
| PTT attach/detach | 🔲 | Engine 깊이 결합 — 별도 세션 |

---

## 기각 사항

| 기각 | 이유 |
|------|------|
| Engine.toggleMute 내부 분기 제거 | Phase 2 — 데모 재작성 후 standalone 불필요 시 |
| Engine._savedXxx 6필드 제거 | standalone 하위호환 유지 필요 |
| PTT 전체 이관 | Engine 내부(floor guard, media gating, ptt-controller)와 깊이 결합 |

## 오늘의 지침 후보

| 지침 | 설명 |
|------|------|
| `_applied` Map이 SSOT | MediaSession 내부 duplex/simulcast의 유일한 진실 |
| Legacy setter = 브릿지 | 데모 갱신 후 삭제 예정 |
| Room이 분기 판단의 주인 | mute: Pipe.duplex 기반. Engine은 primitive 실행만 |
| Pipe 기반 reconnect | _savedXxx 불필요. Pipe 스냅샷이 컨텍스트 |

---

## 다음 세션 시작점

1. **Phase 1 코딩**: MediaSession source 기반 primitive (`suspendTrack`/`resumeTrack`/`acquireTrack`) + LocalPipe facade (`pipe.suspend()`/`pipe.resume()`)
2. 데모 재작성 (Room API 기반)
3. Phase 2: PttController → Pipe API 전환
4. 설계 문서: `design/20260411_pipe_centric_design.md`

---

*author: kodeholic (powered by Claude)*
