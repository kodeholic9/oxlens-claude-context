// author: kodeholic (powered by Claude)
# 20260616 — SDK 수신 표시 경로 국소 재작성 작업지침 (빈칸 1~9 한 호흡)

> 선행: `202606/20260616a_sdk_full_coupling_audit.md`(전수 감사 — 빈칸 1~9 + V1~3·P1~2 + 대조군 확정).
> 가드: `oxlens-home/sdk/tests/arch_check.mjs`(빈칸 건수 BASELINE — 악화 시 FAIL).
> 권위: 신 SDK = `oxlens-home/sdk/`. 헌법 = `design/20260611_client_sdk_constitution_and_pipe_symmetry.md`.
> 이 문서 = **김대리 작업지침**(전체 설계). 구현은 이 순서·구조대로. 빈칸 즉흥 깎기 금지 — 한 호흡 단위로.

---

## 0. 왜 이 문서인가 (실패 회고)

직전(20260616 세션)에 빈칸 6(통지)·V3(출력훅)·빈칸 7(死표면)을 **즉흥으로 하나씩** 깎았다. 방향은 맞고 회귀 0 이었으나, **전체 설계 없이 응집처를 건드리는 방식**은 감사가 경계한 *"축 없이 부분 패치 → 비일관 재발"* 과 같다(= B1/freeze 가 "개판"이던 이유). 핵심 진앙(**RemotePipe DOM 분리·표시 물리**)은 손도 안 댄 채 주변만 깎였다. 이 문서가 그 축이다.

---

## 1. 목표 — 수신 표시 경로 = 송신(local) 축과 대칭인 단일 파이프라인

- **수신 단일 경로**: 일반 트랙(Room→RemoteEndpoint)·PTT slot(virtual) **두 경로가 RemotePipe 생성·통지·표시를 각자** 만지는 양분(빈칸 6, V1·V3)을 단일화. (통지·출력훅·死표면은 완료 — §3 잔여 = 생성 V1.)
- **DOM/표시 물리 단일 소유 = VideoSurface**: pipe 계층은 VideoSurface 에 위임만(빈칸 1·4). element 생성·visibility·left:-9999px 전투자산은 VideoSurface.
- **상속 방향 정상화**: base `Pipe` 는 송수 공통(track/mid/stage/observe)만. 수신 전용(_muted/_pendingShow/setVisible/unmute listener)은 `RemotePipe`(빈칸 2).
- **통로↔표시 격리**: `setRemoteState`(상태)와 표시(VideoSurface policy)를 분리 — setRemoteState 가 setVisible 직결하지 않음(빈칸 3).
- **보존(대조군, 손대지 말 것)**: transport / floor / talkgroups / local-pipe FSM / engine 라우팅 / 복구 / recycle. 풍파 자산(감사 §3).

---

## 2. 현 상태 (arch_check BASELINE = 24, 9 PASS)

| 빈칸 | 내용 | 현 위반 | 상태 |
|---|---|---|---|
| 1 | DOM 분리(pipe 계층→VideoSurface) | 6 (remote-pipe·local-pipe) | **미착수** |
| 2 | base 상속 역참조 | 5 (pipe.js) | **미착수** |
| 3 | 통로격리(setRemoteState→setVisible 직결) | 5 (remote-pipe·virtual.attach=freeze 흡수 V2) | **미착수** |
| 5 | 상행 단일(stream→sig) | 0 | clean |
| 6 | 번역처 단일(통지 게이트) | 1 (게이트 본문) | **완료**(일반/slot 합류, _announced 멱등) |
| V3 | slot 출력훅 늦주입 | 0 | **완료**(생성 시 주입) |
| 7 | 死표면(media:track) | 0 | **완료**(STREAM_SUBSCRIBED 단일) |
| 8 | 단일 게이트(track.enabled) | 2 (power) | 미착수 |
| 9 | 레이어 의존(LocalPipeState) | 5 (power) | 미착수 |
| V1 | virtual RemotePipe 직접 생성 | (빈칸1·6 에 분산) | **미착수** — 생성 일관 |

> 완료분 커밋: `2bce81d`(통지)·`05ba865`(V3)·`d6fb27d`(死표면). 헌법 골격: `8da8db8`(arch_check).

---

## 3. 목표 구조 (파일별)

### 3.1 `domain/video-surface.js` — DOM/표시 물리 단일 소유 (코어)
현재 passive(element 생성은 pipe 가, surface 는 bind 후 visibility 만). → **element 생성까지 흡수**.
- `createElement(kind)` — video/audio element 생성·기본 속성(autoplay/playsInline/objectFit). 현 remote-pipe.mount 의 createElement 블록 이관.
- `attachTrack(el, track, {outputMuted})` / `setVisible(visible, reason)`(left:-9999px, ★display:none 금지) / `detach()`(srcObject 파괴).
- send/recv **공통 코어** + 정책 주입: 수신=floor masking+remote-mute / 송신=항상표시+placeholder(§13.3 Level1 — 이미 LocalPipe.mount 흡수됨, 대칭 확인).
- **DOM 은 여기만**. pipe 계층은 호출만.

### 3.2 `domain/pipe.js` (base) — 송수 공통만
- 보유: trackId·mid·stage(`_setStage`/observe)·`_surface`(VideoSurface)·`_attachTrack`/`_refreshElement`(공통).
- **제거(→ RemotePipe)**: `_muted`/`_pendingShow`/`setVisible`/`_setupTrackUnmuteListener` 역참조(빈칸 2). base 가 자식 전용 상태를 알지 않음.

### 3.3 `domain/remote-pipe.js` — 수신 전용(통로·상태·표시 위임)
- 통로: transceiver(WIRED)·adoptTrack(ADOPTED). DOM 직접 0 → mount 는 `_surface.createElement`+`_surface.attachTrack`+`_setStage(MOUNTED)` 위임(빈칸 1).
- 상태: `_remoteMuted`/`_remoteActive`/`_pendingShow` 보유. `setRemoteState({muted,sending})` = **상태 갱신만**. 표시 반영은 VideoSurface 가 상태를 읽어 `_hiddenBy` 합성(빈칸 3 — setRemoteState 안에서 setVisible 직결 제거).
- 표시 게이트 `setVisible(reason)` 은 VideoSurface 로 위임(masking/floor/remote-mute 합성).

### 3.4 `domain/room.js` — 번역·통지(완료) + 생성 팩토리
- 통지 단일 게이트(_emitStreamSubscribed/Unsubscribed, _announceEpSub/Unsub) — **완료**.
- **신규(V1)**: `_createRecvPipe(t, {slot})` 공통 팩토리 — `_recvPipeOpts`+`new RemotePipe`+출력훅. 일반=RemoteEndpoint.addPipe 가 사용, slot=virtual.ensure 가 이 팩토리 **결과를 _slots 에 보관**(생성 로직 단일, 소유만 분리). → virtual 의 RemotePipe import·직접 new 폐기.

### 3.5 `ptt/virtual.js` — slot 소유(ownership)만
- `_slots` Map 보유·생명주기(room-scope 불변)·`_byMid` 매칭·freeze masking(floor 구독) 유지.
- `ensure` 가 RemotePipe 를 **직접 new 하지 않고** Room 공통 팩토리(3.4) 경유(V1). RemotePipe import 제거.
- `attach`(freeze) 의 floor→setVisible 직결(V2)은 빈칸 3 과 함께 — VideoSurface policy(masking)로 흡수.

### 3.6 `ptt/power.js` — tier 로직 보존, 게이트/경계만
- 빈칸 8: `cam.track.enabled =` 직접(toggleVideo/_wakePipe) → LocalPipe.setTrackState 게이트 경유. (video off ≠ mute 의미 정합 설계 후.)
- 빈칸 9: `LocalPipeState` 직접 비교 → LocalPipe 경계 boolean(`isActive`/`isSuspended`/`isReleased`). `prevState` 값 비교는 별도(저장 시 boolean 화).

---

## 4. 재작성 순서 (의존 순 — 한 호흡 단위, 각 단계 = 1 커밋 + 검증)

> **DOM 코어가 모든 표시 빈칸의 토대** → VideoSurface 먼저. 그 위에 상속·통로격리·생성·power.

1. **VideoSurface 코어 확정**(빈칸 1·4) — element 생성 흡수 + send/recv 정책 주입. remote-pipe/local-pipe 의 DOM 을 VideoSurface 로 이관.
   - 검증: arch_check 빈칸 1 → 0. 단위(mp_check=surface, t3b1=표시제어). **라이브 체크포인트 A**(아래 §5).
2. **base Pipe 상속 정리**(빈칸 2) — 자식 전용 상태 RemotePipe 이관.
   - 검증: arch_check 빈칸 2 → 0. t3b1.
3. **통로↔표시 격리**(빈칸 3) — setRemoteState 상태만, VideoSurface policy 표시. virtual.attach(V2) masking 흡수.
   - 검증: arch_check 빈칸 3 → 0. t3c(B1/remote-mute)·ptt_check(freeze). **라이브 체크포인트 B**.
4. **수신 생성 일관**(V1) — Room `_createRecvPipe` 팩토리, virtual 은 소유만(RemotePipe import 제거).
   - 검증: arch_check 빈칸 1 잔여 0(virtual)·op_check(virtual slot)·t3a/t3e. **라이브 체크포인트 C**.
5. **power 게이트·경계**(빈칸 8·9) — setTrackState 경유 + LocalPipe boolean.
   - 검증: arch_check 빈칸 8·9 → 0. op_check/ptt_check(power tier). **라이브 체크포인트 D**(cold→full).

> 완료: 빈칸 6·7·V3. 위 5 단계 후 arch_check TODO → 0(권고 빈칸 9 제외 가능).

---

## 5. 검증 체계 (3중)

- **arch_check**(정적): 각 단계 후 해당 빈칸 BASELINE 감소 확인 + 악화 0. 진척의 객관 수치.
- **단위 테스트**(헤드리스): 단계별 영향 파일의 *_check.mjs. 회귀 0.
- **라이브 체크포인트**(부장님 — Claude 직접 시험 금지): 응집처 구조 변경이라 단계마다 1회.
  - **A**(VideoSurface): Conference 영상 표시·mute·PTT freeze 영상 — element 생성 이관이 깨뜨렸는지.
  - **B**(통로격리): full↔half(B1)·remote-mute·floor:taken/idle 표시 토글.
  - **C**(생성 일관): slot 무전 음성·영상 수신(virtual 생성 경로 변경).
  - **D**(power): half→cold→full preview(power.js `_goCold` ↔ `_wakePipe` 실코드 — 감사 §6 1순위).

> 각 체크포인트에서 깨지면 stage(pipe.stage DECLARED→WIRED→ADOPTED→MOUNTED)로 "어디서 멈췄나" 추적. 증상 스냅샷 → Claude 분석.

---

## 6. 불변/금지 (재작성 중 위반 시 버그)

- VideoSurface 외 DOM 접근 금지(빈칸 1). `display:none` 금지 — `left:-9999px`(디코더 정지 연쇄 방지).
- slot 생명주기 = room-join 생성 / room-leave 삭제 **만**. reconcile·TRACKS_UPDATE remove 면제(virtual.detachRoom 만).
- 수신 통지 = 단일 게이트(일반/slot). 직접 emit 금지(빈칸 6).
- track_id 파싱 금지(불투명 키). roomId 명시 전달.
- 대조군(transport/floor/talkgroups/local-pipe/engine 라우팅) 손대지 말 것.
- 라이브 검증 없이 두 단계 이상 누적 금지(회귀 분리 불가).

---

## 7. 기각 (감사 §7 재확인)

- 전면 재작성(풍파 자산 손실). PTT slot 별도 경로 유지(V1 통합이 정답). freeze.js 별파일 부활(virtual 흡수 맞음). media:track 부활(死표면). 빈칸 즉흥 깎기(축 없이 = 비일관 재발).

---

*author: kodeholic (powered by Claude)*
