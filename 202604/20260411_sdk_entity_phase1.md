# 2026-04-11 세션: SDK API 리모델링 Phase 1 — 엔티티 뼈대 + mount/unmount

> author: kodeholic (powered by Claude)

---

## 작업 요약

SDK 공개 API를 Room/Endpoint/Pipe 엔티티 모델로 리모델링. 
OxLensClient(engine)을 내부에 품는 Room wrapper + mount/unmount(LiveKit 내부구조 참조) 구현.
**껍데기만 씌운 상태 — 내부 의존관계 정리 미완료. 다음 세션에서 체계적 리팩토링 필요.**

## 생성된 파일

| 파일 | 설명 |
|------|------|
| `core/event-emitter.js` | 공유 EventEmitter (client.js에서 추출) |
| `core/pipe.js` | Pipe 엔티티 (mount/unmount + freeze masking) |
| `core/endpoint.js` | LocalEndpoint + RemoteEndpoint |
| `core/room.js` | Room + OxLens.createRoom() 팩토리 |
| `core/index.js` | 통합 entry point |

## 수정된 파일

| 파일 | 변경 |
|------|------|
| `core/client.js` | EventEmitter 추출, `join:data` 이벤트 추가, `_onTracksUpdate` emit 순서 변경, `media:track`에 trackId 추가 |
| `core/media-session.js` | ontrack emit에 `trackId: subEntry?.track_id` 추가 |
| `demo/components/ptt-panel.js` | freeze masking 코드 제거 (Pipe로 이관) |
| `demo/scenarios/conference/app.js` | 새 API 전환 |
| `demo/scenarios/voice_radio/app.js` | 새 API 전환 |
| `demo/scenarios/video_radio/app.js` | 새 API 전환 + pipe.mount(el) |
| `demo/scenarios/dispatch/app.js` | 새 API 전환 (미검증) |
| `context/design/20260411_sdk_api_design.md` | v1.1 (mount/unmount 확정) |

## 핵심 설계 결정

### 확정
- **`_allPipes: Map<trackId, Pipe>`** — 단일 마스터 인덱스. PTT/Conference 분기 없음
- **`trackId` 기반 매칭** — media:track에서 trackId로 Pipe 직접 찾기. user_id/isPtt 분기 없음
- **`join:data` 이벤트** — engine이 join 응답을 SDP nego 전에 발행 → Room이 Pipe를 먼저 생성 → ontrack에서 매칭 (LiveKit 패턴)
- **`tracks:update` 순서 변경** — SDP nego 전에 emit → 같은 이유
- **mount/unmount 용어** — LiveKit의 attach/detach 내부구조 참조하되, API명은 차별화
- **mount(el)에서 freeze masking 자동** — half-duplex video pipe에서 track.onunmute/onmute → visibility 제어 + rVFC 첫 프레임 감지 → pipe:showReady/hideReady
- **ep.lock() kind 인자 제거** — PTT는 audio+video 한 몸

### 기각
- **pending stream buffer** — Room에서 ontrack이 tracks:update보다 먼저 올 때 버퍼로 보상 → 래퍼의 보상 로직이지 근본 해결 아님
- **_onJoinOk에 인위적 tracks:update emit** — 이벤트 의미 왜곡
- **`__ptt__` fake userId** — SDK가 서버 내부 구현(virtual track)을 알 필요 없음. trackId 기반이 정답
- **`_pttPipes` 별도 Map** — user_id 유무로 분기하는 것 자체가 설계 오류. `_allPipes` 단일 Map으로 통합
- **attach/detach 용어** — LiveKit과 동일하면 표절 같음. mount/unmount로 차별화

## ⚠️ 미정리 사항 (다음 세션 리팩토링 대상)

1. **audio 관리** — client.js `_handleRemoteAudioTrack`이 audio element 직접 생성/관리. Pipe를 안 거침
2. **engine 직접 바인딩** — ptt-panel, VideoGrid가 `room.engine` 이벤트 직접 바인딩. Room 이벤트를 안 거침
3. **`room.engine.xxx` 남발** — `setOutputVolume`, `setInputGain`, `isMuted`, `isScreenSharing`, `switchCamera` 등 App에서 engine 직접 호출
4. **floor 이벤트 이중 경로** — ptt-panel은 engine의 `floor:state`, Room은 `pipe:locked/unlocked`. 두 경로 공존
5. **Pipe 이중 관리** — `_allPipes` + `Endpoint._pipes`에 같은 Pipe 참조. `_addPipe` 사용하지 않고 직접 `ep._pipes.set()` 호출
6. **Endpoint._addPipe 미사용** — Room에서 Pipe를 직접 생성해서 `_allPipes`와 `ep._pipes`에 넣음. Endpoint의 `_addPipe`가 사문화

## ⚠️ 오늘의 반성

**설계 없이 코딩 → 땜방 반복 → 디버깅에 시간 낭비.**
- ontrack 타이밍 → pending buffer → 인위적 emit → join:data → 3번 수정
- PTT user_id → `__ptt__` → `_pttPipes` → `_allPipes` + trackId → 3번 수정
- attach/detach → mount/unmount → 전체 치환

**다음부터**: 자료구조 설계 + 이벤트 흐름도 먼저 그리고, 확인받고, 한 번에 코딩.

## 이벤트 매핑 (engine → Room)

| engine 이벤트 | Room 이벤트 | 비고 |
|--------------|------------|------|
| join:data | (내부) Pipe 생성 | SDP nego 전 발행 |
| room:joined | room:connected / room:reconnected | |
| tracks:update(add) | pipe:pushed | SDP nego 전 발행 |
| tracks:update(remove) | pipe:closed | |
| tracks:update(duplex_changed) | pipe:duplex | |
| media:track | pipe:pulled | trackId 기반 매칭 |
| track:state | pipe:muted / pipe:unmuted | |
| _floor:taken_raw | pipe:locked | |
| _floor:idle_raw | pipe:unlocked | |
| active:speakers | ep:speaking | |
| video:suspended | pipe:suspended | |
| video:resumed | pipe:resumed | |
| conn:state(reconnecting) | room:reconnecting | |
| conn:state(disconnected) | room:disconnected | |

---

*author: kodeholic (powered by Claude)*
