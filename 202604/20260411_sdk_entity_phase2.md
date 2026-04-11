# 2026-04-11 세션: SDK 엔티티 리팩토링 Phase 2 — 종속관계 정리 + duplex SSOT 설계

> author: kodeholic (powered by Claude)

---

## 작업 요약

Phase 1에서 "껍데기만 씌운" Room/Endpoint/Pipe 3축의 내부 종속관계를 정리. Pipe 생명주기를 Endpoint 단일 책임으로 전환하고, client.js의 remote audio 관리를 Room의 Pipe.mount()로 이관. duplex/simulcast 정보 흐름을 desired state(Pipe) / applied state(MediaSession) / orchestrator(Engine) 3계층으로 재설계. OxLensClient → Engine 리네이밍 착수.

**근본 진단: 현재 Room은 engine의 래퍼(이벤트 프록시)이지, engine을 대체한 것이 아니다. 점진적으로 engine의 책임을 Room 계층으로 이관해야 한다.**

---

## 완료된 작업

### v1.2: Pipe 생명주기 단일 책임 (코딩 완료)

| 파일 | 변경 |
|------|------|
| endpoint.js | `_addPipe()` room._allPipes 자동 연동. `_removePipe()` _allPipes 동시 삭제. `_removeAllPipes()` 신규. LocalEndpoint `_publishPipes` Map + `pipes` getter Pipe[] |
| room.js | `new Pipe()` 제거 → `ep._addPipe(t)` 위임. participant_left `ep._removeAllPipes()`. audio 자동 mount/unmount. `setOutputVolume()`. Local publish pipe 이벤트 배선. 버그 3건 수정 |
| engine.js (구 client.js) | `_remoteAudios` / `_handleRemoteAudioTrack` / `_cleanupRemoteAudio` 제거. `setOutputVolume()` deprecated stub. class Engine 리네이밍. `trackConfig` callback 필드 추가. `_simulcastEnabled` 삭제 |
| moderate.js | `_onAuthorized`에서 `audio:enabled` 이벤트 emit 추가 |

### 버그 수정 3건

| 버그 | 수정 |
|------|------|
| FLOOR_TAKEN `d.user_id` → `d.speaker` | room.js `_floor:taken_raw` 핸들러에서 `d.speaker`로 수정 |
| video:suspended 전체 video pipe paused | source 기반 특정 pipe만 |
| pipe:duplex 인자 타입 불일치 (Remote=Pipe, Local=plain) | LocalEndpoint._publishPipes에서 Pipe 찾아서 전달 |

### 파일명 변경

- `client.js` → `engine.js`
- class `OxLensClient` → `Engine`

---

## v1.3 설계 완료 (코딩 미착수)

### desired state vs applied state

| 구분 | 위치 | 역할 |
|------|------|------|
| desired state | Pipe (SSOT) | "이렇게 되고 싶다" — 앱이 설정 |
| applied state | MediaSession._applied | "마지막으로 적용한 값" — 전이 판단용 |

### callback provider 패턴

```
Pipe → Room.trackConfig callback → Engine.trackConfig("mic") → desired 조회
Engine → media.applyTrackConfig("mic", desired) → MediaSession applied state 전이
```

### MediaSession 캡슐화

- `_audioDuplex`/`_videoDuplex`/`_simulcastEnabled` → `_applied` Map
- `applyTrackConfig(source, desired)` — prev→next diff, 전이 로그, 롤백
- `getApplied(source)` — applied state 조회
- `dumpApplied()` — 디버깅/스냅샷

### 디버깅 장치 5종

1. 전이 로그 (모든 applyTrackConfig 호출, prev→next)
2. desired ≠ applied drift 감지 (주기적 검사)
3. applied state 스냅샷 (telemetry 병합)
4. 전이 실패 롤백 (catch → applied 복원)
5. 이벤트 타임라인 기록 (agg-log 연동)

### v1.3 코딩 잔여

| 항목 | 파일 | 상태 |
|------|------|------|
| MediaSession `_applied` Map + applyTrackConfig/getApplied/dumpApplied | media-session.js | 🔲 |
| Engine `media._xxDuplex` 직접 접근 → 캡슐화 메서드 전환 (~35곳) | engine.js + media-session.js | 🔲 |
| room.js callback 주입 + 직접 대입 제거 | room.js | 🔲 |
| power-fsm.js getApplied 전환 | power-fsm.js | 🔲 |
| import 경로 변경 (client.js → engine.js) | 전체 | 🔲 |
| _autoRejoin Room 이관 (bootstrap timing) | room.js + engine.js | 🔲 |

---

## ⚠️ 구조적 한계 인식 — Room은 아직 래퍼다

### 현황

Room은 engine의 40개 이벤트를 받아서 이름만 바꿔서 재발행하는 **이벤트 프록시**. engine(43KB)이 여전히 완전한 SDK로서 PTT 모드 판정, mute 3-state, floor guard, reconnect, filter pipeline, 카메라 토글을 전부 가지고 있음.

### 증거

1. 데모앱이 `room.engine.xxx` 남발 — Room API만으로 불충분
2. support/moderate가 Room 미사용 — Engine이 독립 동작 가능하니 Room 불필요
3. LocalEndpoint.pipes가 형식적 — Remote Pipe는 mount/unmount/freeze masking, Local은 빈 껍데기
4. Room.leave()와 engine.leaveRoom() 양쪽에서 정리 — 정리 경로 이중

### 목표 방향: Room이 engine의 주인

engine의 책임을 하나씩 Room/Endpoint/Pipe로 이관:

| 현재 engine 책임 | 이관 대상 | 우선순위 |
|-----------------|----------|----------|
| remote audio 관리 | Room auto-mount (Pipe) | ✅ 완료 |
| duplex/simulcast 보관 | Pipe(desired) + MediaSession(applied) | 🔲 v1.3 |
| mute 제어 | LocalEndpoint 또는 Pipe | 🔲 향후 |
| PTT attach/detach | Room의 Pipe lifecycle 연동 | 🔲 향후 |
| reconnect context save/restore | Room이 Pipe 기반으로 | 🔲 향후 |
| filter pipeline | Pipe 레벨로 | 🔲 향후 |

**최종 형태:** Engine = Signaling + MediaSession + Telemetry만 남은 얇은 미디어 엔진. 비즈니스 로직은 전부 Room 계층.

---

## 기각 사항

| 기각 | 이유 |
|------|------|
| MediaSession duplex/simulcast 3필드 삭제 | applied state 관리 책임 — desired(Pipe)와 역할이 다른 별도 상태. 삭제하면 전이 판단 불가 |
| Engine에 getter 3개 추가 (audioDuplex, videoDuplex, simulcastEnabled) | callback 자체가 getter. 별도 getter는 캐시와 다를 바 없음 |
| Engine._publishConfig Map 추가 | Pipe가 SSOT인데 Engine에 또 복사본 — 이중 관리 |
| MediaSession이 Pipe를 import/참조 | 계층 역전 (하위가 상위 참조) |

## 오늘의 지침 후보 (SKILL 반영 검토)

| 지침 | 설명 |
|------|------|
| **Pipe = desired state SSOT** | duplex/simulcast의 유일한 진실의 원천 |
| **MediaSession = applied state** | PeerConnection에 적용된 상태. 전이 판단/롤백/디버깅 책임 |
| **Engine = orchestrator** | desired 조회(callback) + applied 지시(applyTrackConfig) + 비즈니스 로직 |
| **직접 필드 접근 금지** | `media._audioDuplex` 대입/읽기 → applyTrackConfig()/getApplied() 경유 |
| **Room이 engine의 주인** | 래퍼가 아니라 주인. engine 책임을 점진적으로 Room 계층으로 이관 |

---

## 설계 문서 갱신

| 문서 | 버전 | 내용 |
|------|------|------|
| `design/20260411_sdk_api_design.md` | v1.2 | Pipe 생명주기 단일 책임, 종속관계 불일치 7건 + 이중 경로 5건 진단, 변경 명세 |
| `design/20260411_sdk_api_design.md` | v1.3 | desired/applied state 분리, callback provider, Engine 리네이밍, 디버깅 장치 5종, applied state 캡슐화 |

---

*author: kodeholic (powered by Claude)*
