# SDK Pipe-Centric Architecture — 점진적 전환 설계

> author: kodeholic (powered by Claude)
> version: v0.1 (2026-04-11)
> status: 방향 확정, Phase 1부터 점진적 코딩

---

## 핵심 원칙

- **모든 것은 Pipe 단위로 동작한다**
- Room = pipe 그룹핑 (향후 multi-room)
- Controller = 같은 duplex의 pipe 집합 관리
- Pipe가 미디어 제어 API를 가짐 (sender 소유는 MediaSession 유지)

---

## 목표 구조

```
Room A
  PttController (half pipes)
    ├── Pipe(pub, half, mic)      → floor gating, power FSM
    ├── Pipe(pub, half, camera)   → freeze, keyframe wait
    ├── Pipe(sub, half, audio)    → silence→speech 전환
    └── Pipe(sub, half, video)    → freeze masking

  NormalController (full pipes)
    ├── Pipe(pub, full, mic)      → mute = suspend/resume
    ├── Pipe(pub, full, camera)   → mute = stop+dummy/restore
    └── Pipe(sub, full, video)    → layout, layer selection

Room B
  ...별도 pipe 집합, 별도 controller
```

---

## 접근: 옵션 B (facade)

sender/track 소유는 MediaSession이 유지. Pipe는 source 기반으로 MediaSession primitive 호출.

```
Pipe.suspend()  → engine.media.suspendTrack(pipe.source)
Pipe.resume()   → engine.media.resumeTrack(pipe.source)
```

이유:
- MediaSession 전면 리팩 불필요 (옵션 A 대비)
- 점진적 전환 가능 — Phase별로 독립, 중간에 멈춰도 안 깨짐
- 상용 안정화 후 옵션 A(Pipe가 sender 직접 소유)로 발전 가능

---

## 점진적 전환 Phase

### Phase 1: LocalPipe 미디어 facade

MediaSession에 source 기반 primitive 추가:
- `suspendTrack(source)` — replaceTrack(null), track 보관
- `resumeTrack(source)` — replaceTrack(saved)
- `acquireTrack(source)` — getUserMedia + replaceTrack

LocalPipe에 facade:
- `pipe.suspend()` / `pipe.resume()` / `pipe.acquire()`
- `pipe.isActive` — track !== null

### Phase 2: Controller → Pipe API 전환

PowerFsm ~30곳 `sdk.media.audioSender.*` → `pipe.suspend()` 등
FloorFsm ~20곳 `sdk.sig/emit` → room 이벤트 버스

PttController 생성자: `new PttController(halfPipes, { eventBus })`
NormalController 신설: `new NormalController(fullPipes, { eventBus })`

### Phase 3: Engine 슬림화

Engine에서 PTT/mute/filter 코드 완전 제거.
Engine = Signaling + MediaSession + Telemetry만 남은 얇은 미디어 엔진.

---

## 현재 상태 (2026-04-11)

완료:
- applied state 캡슐화 (v1.3)
- mute 분기 판단 Room 이관 (Phase 1)
- reconnect Pipe 기반 이관
- PTT 생명주기 판정 Room 이관
- filter/device API LocalEndpoint 확장

다음: Phase 1 LocalPipe facade 코딩

---

*author: kodeholic (powered by Claude)*
