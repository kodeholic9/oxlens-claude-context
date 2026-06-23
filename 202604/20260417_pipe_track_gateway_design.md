# Pipe Track Gateway 설계

## 날짜: 2026-04-17

## 배경

Phase 2 (lazy media) 도입 후 video track 생명주기를 Engine, Endpoint, PowerManager 세 곳에서 각자 관리.
COLD→HOT 복구 시 "카메라 활성화 이력"을 간접 수단(`_savedVideoTrack`, `_savedVideoConstraints`)으로 역추론 → 둘 다 null이면 이력 소실 → 영상 미복구.

## 근본 원인

`sender.replaceTrack()`을 17곳에서 직접 호출. 상태를 기록하는 곳이 없으므로 "이전 행위자의 의도"를 파악할 수 없음.

## 핵심 원칙

**"진입 지점은 달라도 하나의 길로 통한다"**

- Pipe가 sender.replaceTrack()의 유일한 게이트웨이
- Pipe가 자기 track의 상태를 기억
- 상태 자체가 의도를 인코딩: INACTIVE="켜진 적 없거나 끔", RELEASED="켜졌었는데 시스템이 해제"

## TrackState 상태 머신 (send Pipe 전용)

```
INACTIVE ──(setTrack)──→ ACTIVE ──(suspend)──→ SUSPENDED ──(resume)──→ ACTIVE
                           │                       │
                           └──(release)──→ RELEASED ←──(release)──┘
                           │                       │
                           └──(deactivate)─→ INACTIVE ←─(deactivate)─┘

RELEASED ──(setTrack)──→ ACTIVE
```

### 상태 정의

| 상태 | 의미 | sender.track | savedTrack | savedConstraints |
|------|------|:---:|:---:|:---:|
| INACTIVE | 미활성화 or 사용자 끔 | null | null | null |
| ACTIVE | 정상 송출 | live | null | null |
| SUSPENDED | 전력 절약 (STANDBY) | null | live | (추출 가능) |
| RELEASED | 자원 해제 (COLD, 복구 가능) | null | null | 보관됨 |

### Pipe 메서드 (send 전용, recv → noop)

```js
pipe.setTrack(track)   // INACTIVE/RELEASED → ACTIVE. 이미 ACTIVE → noop 반환
pipe.suspend()         // ACTIVE → SUSPENDED. track 보관 + constraints 추출 + sender 비움
pipe.resume()          // SUSPENDED → ACTIVE (savedTrack). RELEASED → 'need_track'. INACTIVE → 'not_enabled'
pipe.release()         // ACTIVE/SUSPENDED → RELEASED. track stop + constraints 보관
pipe.deactivate()      // * → INACTIVE. 전부 정리. 복구 불가 의도
pipe.swapTrack(track)  // ACTIVE 유지, sender track 교체 (mute/filter/switchCamera)
```

### 반환 규약

| 메서드 | 반환 | 의미 |
|--------|------|------|
| setTrack | 'activated' / 'already_active' | |
| suspend | 'suspended' / 'not_active' | |
| resume | 'resumed' / 'need_track' / 'not_enabled' | 호출자가 getUserMedia 판단 |
| release | 'released' / 'already_inactive' | |
| deactivate | 'deactivated' | |
| swapTrack | 'swapped' / 'not_active' | |

## 행위 매핑 (17곳 → Pipe 경유)

| 행위 | 현재 수행자 | Pipe 호출 |
|------|-----------|-----------|
| 최초 활성화 | Endpoint._publishCamera | pipe.setTrack(track) |
| STANDBY | PowerManager._enterStandby | pipe.suspend() |
| COLD | PowerManager._enterCold | pipe.release() |
| HOT 복구 (보관) | PowerManager._doEnsureHot | pipe.resume() → 'resumed' |
| HOT 복구 (재생성) | PowerManager._doEnsureHot | pipe.resume() → 'need_track' → pipe.setTrack(newTrack) |
| 비활성화 | Endpoint._unpublishCamera | pipe.deactivate() |
| 카메라 전환 | Engine.switchCamera | pipe.swapTrack(newTrack) |
| 음소거 | Endpoint._muteVideo | pipe.swapTrack(dummy) |
| 음소거 해제 | Endpoint._unmuteVideo | pipe.swapTrack(newTrack) |
| Filter 적용 | FilterExtension | pipe.swapTrack(outputTrack) |
| stream restore | Engine._onJoinOk | pipe.setTrack(track) |

## 설계 판단

### Q1: swapTrack을 Pipe에 넣는다 — 합의

ACTIVE 내 track 교체(switchCamera, mute, filter)도 Pipe를 통과. sender 직접 접근 금지 원칙.

### Q2: recv Pipe — direction 체크 + early return

recv pipe에서 setTrack/suspend 등 호출 시 direction='recv'이면 noop.

### Q3: async 직렬화 — Pipe에 넣지 않는다

직렬화는 PowerManager._hotQueue 등 호출자 책임. Pipe는 단일 호출 상태 전이만.

### Q4: stream 동기화 — Pipe 밖

Pipe는 sender만 관리. engine._stream add/remove는 호출자(Endpoint/PowerManager) 책임.

### Q5: pipe.sender 외부 접근

sender를 _sender로 바꿔서 관례적 private. SdpNegotiator의 초기 설정은 `pipe.bindSender(tx.sender)` 메서드 경유.
프로젝트 원칙: "pipe.sender 직접 접근 금지" 기록.

## 위험 지점 5건

1. **swapTrack 없으면 구멍**: switchCamera/mute/filter가 sender 직접 접근 → 해결됨
2. **mute + STANDBY 경쟁**: suspend() 시 sender.track이 dummy일 수 있음 → suspend()에서 체크 필요
3. **recv Pipe 상태 머신 혼재**: direction 체크로 격리
4. **sender 외부 접근**: 관례적 private + bindSender 메서드
5. **_onJoinOk stream restore**: 새 pipe(INACTIVE) + setTrack → 자연 매핑

## 구현 계획

### Phase 1: Pipe 확장 (pipe.js ~80줄 추가)
- trackState 필드 + 상태 머신 메서드 6개
- savedTrack, savedConstraints 필드 (PowerManager에서 이관)
- bindSender 메서드

### Phase 2: PowerManager 리팩토링
- _enterStandby → pipe.suspend() 위임
- _enterCold → pipe.release() 위임
- _doEnsureHot → pipe.resume() 기반 판단
- _savedAudioTrack/_savedVideoTrack 제거 (Pipe로 이관)
- _savedVideoConstraints 제거 (Pipe로 이관)

### Phase 3: Endpoint 리팩토링
- _publishCamera → pipe.setTrack()
- _unpublishCamera → pipe.deactivate()
- _muteVideo/_unmuteVideo → pipe.swapTrack()
- publishAudio/unpublishAudio → 동일 패턴

### Phase 4: Engine + SdpNegotiator
- switchCamera → pipe.swapTrack()
- _onJoinOk stream restore → pipe.setTrack()
- SdpNegotiator: pipe.sender → pipe.bindSender()

---

*author: kodeholic (powered by Claude)*
