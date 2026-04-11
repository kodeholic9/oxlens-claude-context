# 세션 컨텍스트: SDK API 설계 v1 — Endpoint/Pipe 모델 확정

> 2026-04-11 | Phase 48 | author: kodeholic (powered by Claude)

---

## 작업 요약

1. **LiveKit / Sendbird SDK 분석** — 사용자에게 노출된 API 표면 전수 조사
2. **엔티티 모델 확정** — Room / Participant / Track → Room / Endpoint / Pipe
3. **용어 확정** — Publish→Push, Subscribe→Pull, Track→Pipe, Participant→Endpoint
4. **API 표면 설계** — 메서드 29개, 속성 14개, 이벤트 31개 (총 74개)
5. **mount/unmount 패턴 확정** — SDK가 video element 소유, App은 DOM 배치만
6. **설정 우선순위 확정** — app > server > SDK 기본값
7. **나/남 경계** — 나의 행위=ep, 남의 파이프 조작=pipe

## 핵심 설계 결정

### 엔티티 모델
```
Room ── Endpoint ── Pipe
         (나/남)      (미디어 관)
```

### 용어 대응
| 기존 | 신규 | 비유 |
|------|------|------|
| Participant | Endpoint | 배관의 끝점 |
| Track | Pipe | 미디어가 흐르는 관 |
| Publish | Push | 관에 밀어넣다 |
| Subscribe | Pull | 관에서 당기다 |

### API 분리 원칙
- **나의 행위** → `ep.pushAudioPipe()`, `ep.muteAudio()`, `ep.lock()` — 주어가 나
- **남의 파이프 조작** → `pipe.pull()`, `pipe.pullLayer()`, `pipe.mount()` — 목적어가 남의 것
- **audio/video 분리** → `pushAudioPipe()` / `pushVideoPipe(source)` — audio는 source 불필요

### mount vs observe
- **mount 확정** — video element는 자원 해제 필요 (srcObject, 디코더, 메모리)
- **observe 기각** — mount가 있으면 el을 이미 소유, 별도 observe 불필요

### pipe:showReady / pipe:hideReady
- SDK가 판단(floor + 키프레임 도착 + silence 완료), App이 실행(display 토글)
- 통제는 빼고, 시점만 emit

### 설정 우선순위
```
app 설정 (room.config) > 서버 설정 (server_config) > SDK 기본값
```
- app 우선: UI 타이머, Power FSM, 필터, 비트레이트 힌트
- 서버 강제: floor timeout, max participants, 대역폭 cap

### 내부 자동 (노출하지 않는 것)
- HEARTBEAT, EVENT_ACK, FLOOR_PING, TELEMETRY
- Power FSM (타이머만 room.config로 주입)
- auto-reconnect (이벤트만 room:reconnecting/reconnected)
- SDP 조립, subscribe-only 모드

## 산출물

- **설계 문서**: `context/design/20260411_sdk_api_design.md`
  - Room/Endpoint/Pipe 전체 API 표면
  - opcode 매핑표
  - 4개 시나리오 사용 예시 (Conference/PTT/Moderate/CCTV)
  - 미확정 항목 7개

## 오늘의 기각 후보

| 기각 | 이유 |
|------|------|
| pipe.observe(el) | mount가 el을 이미 소유 — observe 불필요 |
| pipe 레벨 mute/lock | 나의 행위이므로 ep.mute()/ep.lock() |
| attach/detach 용어 | mount/unmount가 자원 소유 의미 전달 |
| Power FSM API 노출 | 내부 자동 — 타이머만 room.config() |
| node 용어 | endpoint가 통신 도메인에서 더 명확 |
| perk/trait 용어 | pipe(배관)가 push/pull과 자연스러움 |

## 오늘의 지침 후보

- **Endpoint/Pipe/Push/Pull** — SDK 공식 용어
- **나=ep, 남=pipe** — 자연어 어순 일치
- **pushAudioPipe/pushVideoPipe** — audio는 source 불필요, video만 camera/screen 구분
- **mount/unmount** — 자원 해제 필요한 것은 SDK 소유
- **showReady/hideReady** — SDK가 판단, App이 실행
- **room.config()** — runtime 설정 주입, init-time은 createRoom() 옵션

## 다음 세션 우선순위

1. **pipe.mount() SDK 구현** — client.js에 Pipe 클래스 추가, video element 소유
2. **Endpoint/Pipe 이벤트 체계 전환** — 기존 raw 이벤트 → 신규 이벤트명
3. **moderate app.js 단순화** — mount/unmount 패턴 적용
4. **전 시나리오 확산** — conference, radio, dispatch에 동일 패턴 적용
5. **SKILL_OXLENS.md 업데이트** — SDK API 설계 반영

## 변경 파일 목록

### 신규 파일
- `context/design/20260411_sdk_api_design.md` — SDK API 설계서 v1

### 코드 변경 없음 (설계 세션)

---

*v1.0 — 2026-04-11*
