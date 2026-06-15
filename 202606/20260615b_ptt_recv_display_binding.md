// author: kodeholic (powered by Claude)
# 20260615b — PTT 수신 표시 파이프라인 개편(§13 표시 2계층) + 송신 게이트 floor 직결 + 무음/검은화면 근본

> 세션 흐름: PTT half-duplex 송신 게이트를 power FSM→floor.state 직결로 재구조 → 라이브에서 **상대 음성·영상 미표시** 발견 →
> 끝점 역추적(§10)으로 **근본=수신 slot 의 mount 트리거 부재** 규명 → 수신 단일 파이프라인 개편 →
> 케이스 누적(무음/preview stale/타일 증식/캡션/full→half 잔존)이 **한 뿌리(생명주기 통지 분산+누락)**임을 진단 →
> **§13 표시 바인딩 2계층 + 송신/수신 표시축 대칭** 개편 + **§5 stage 가시화**.
> 라이브 시험은 부장님, Claude 는 분석/구현(직접 시험 금지). 설계서 = `design/20260615_ptt_recv_pipeline_redesign.md`(§1~§13).

---

## 1. 이번 세션 커밋 (oxlens-home, 15개)

| 커밋 | 내용 | 묶음 |
|------|------|------|
| `14ea096` | PTT half-duplex 송신 게이트를 floor 직결로 재구조(power=tier 전담) | 송신 게이트 |
| `92914ba` | 수신 PTT slot mount 트리거 복원 + 배관 Room 승격 | §1·축3 (**무음 해결**) |
| `e16afea` | isPttVirtualTrack 단순화 + slot roomId 명시 + 죽은코드 청소 | §7-3·§7-5 |
| `4d8feac` | slot 출력 훅 Room 승격 — 무전 음성 선택 스피커 | §7-6 |
| `06a65a5` | RemoteEndpoint.addPipe 자체 멱등화 | §7-9 |
| `aac0c62` | ROOM_SYNC diff+적용을 Room.reconcile 로 응집 | §7-8 부분 |
| `3e41315` | hydrate created 가드 → needRenego(slot-only 무전방 통로) | §7-1 |
| `18e327c` | power 재acquire RESTARTED 통지 — COLD 후 self-view 갱신 | §4 비대칭(A) |
| `00e0c91` | 수신 트랙 생명주기 통지 누락 2건(재acquire/remove) — **부장님 직접** | 케이스1·2 |
| `c4ea58b` | **토대 ①** — 송신 track 교체 통지 단일 게이트 applyRestoredTrack | §13.3 |
| `0fad951` | **Level 1** — LocalPipe.mount/unmount + LocalStream.attach/detach(self-view) | §13.3 |
| `f047461` | lab — self-view 를 ls.attach() 로 + 무전 영상 무전 수신 표시(B2) | §13/lab |
| `8498ad5` | **Level 2** — RemoteStream.track raw getter(고급) | §13.3 |
| `5e111ff` | **§5** — pipe 배선 단계 stage 가시화(송수 공통) | §5 |
| `d8df469` | §7-7 — applyTracksUpdate add 평면 분해 헬퍼 추출(가독) | §7-7 |

> 서버측: 부장님이 `00e0c91` 외 ptt_rewriter/oadmin trace 등 별도 진행(서버 작업 중 — Claude 확인만).

---

## 2. 송신 게이트 floor 직결 재구조 (`14ea096`)

부장님 통찰 2겹으로 power.js 전면 재작성:
- **겹① 게이트 주체 분리**: 송신 on/off 게이트를 power FSM 에서 **floor.state 직결**(`floor.on("state")` 단일 구독).
  REQUESTING||TALKING=열림(resume), 그 외=닫힘(suspend). power 는 **닫힘 동안 절전 깊이(HOT_STANDBY→COLD)만**.
- **겹② talk-ahead**: resume 트리거 `granted`→`request`(REQUESTING). 앞 음절 보존(서버가 어차피 floor gating).
- `attachHalfPipe`/`detachHalfPipe` 폐기 → `onDuplexChanged` 단일. env wake 게이트 트리거 제거.
- full→half 전환: 서버 통지(TRACK_STATE_REQ) **다음에** 게이트 정합(부장님 지시 — 서버 커밋 후가 끊는 위치).

---

## 3. 무음/검은화면 근본 — §1 mount 트리거 부재 (`92914ba`)

**증상**: half(PTT) 상대 음성·영상 미표시. full 은 정상.
**삽질 회고**: ts_gap·enabled·코덱·서버 rewrite 를 순서대로 의심하다 헤맴 — 전부 빗나감. 부장님이 **"끝점부터(§10)"**, **"track-identity/패킷 흐름 먼저"**로 교정.

**진짜 원인(끝점 역추적)**:
- 일반 트랙: `ontrack → STREAM_SUBSCRIBED → 앱 attach() → mount()`.
- slot: `room._onTrackReceived` 의 `if(!isPtt)` 가드로 **STREAM_SUBSCRIBED 안 쏨**. `media:track` emit 단 하나(RoomEvent enum 에 없음) → 앱(lab)이 구조적으로 못 잡음 → **attach()=mount() 0 → srcObject 없음 → 무음/검은화면**.
- dump 실증: `packetsReceived=1168`(통로 OK) + `audioLevel/totalAudioEnergy=0`(playout 0) = WIRED·ADOPTED 됐는데 MOUNTED 부재.

**조치**: slot 도 STREAM_SUBSCRIBED 통지. 배관(통지/핸들/출력 훅)을 endpoint→**Room 승격**(Ownership=virtual._slots 유지, 배관만 Room). RemoteStream provider=Room. 일반 경로 무변경(회귀 0).

---

## 4. §13 — 표시 바인딩 2계층 + 송신/수신 표시축 대칭 [핵심]

> 부장님 통찰: *"매뉴얼+예제로 일반 개발자가 10분 내 만들어야 하는데 그게 안 되면 SDK 가 약한 것."* — 맞다.

### 4.1 케이스 누적이 한 뿌리
무음·preview stale·**타일 증식**·캡션 stale·full→half 잔존 = 서로 다른 버그가 아니라 **같은 구멍이 경로별로**. 뿌리 = *track 생명주기(생성·교체·제거·표시) 통지가 앱에 N이벤트로 분산 + 경로별 누락*. 재acquire RESTARTED 경로만 **5개**(restartTrack/_recoverPipe/_doEnsureHot/_restoreVideoTrack/_wakePipe). 단발은 두더지.

### 4.2 개편 3층
1. **토대 ①(`c4ea58b`)** — 송신 교체 통지 **단일 게이트** `LocalEndpoint.applyRestoredTrack`. 5경로 수렴 → 누락 0.
2. **Level 1(`0fad951`)** — `LocalPipe.mount/LocalStream.attach`(self-view). base Pipe 의 `_surface/_attachTrack/_refreshElement` 는 **이미 송수 공통**이었고 LocalPipe 만 mount 가 없어 셀프뷰가 raw 였음. 송신 정책=**muted+항상표시**(floor masking 없음). → 앱 raw srcObject·RESTARTED 수동 배선이 `attach()` 한 줄(§13.4 실현).
3. **Level 2(`8498ad5`)** — `RemoteStream.track`/`LocalStream.track` raw getter(고급 직접 제어). 단 토대① 위에서만 안전.

### 4.3 §5 stage(`5e111ff`)
`pipe.stage`: DECLARED→WIRED→ADOPTED→MOUNTED 단조(표시/LIVE 별축). base Pipe.stage/_setStage + observe("pipe:stage"). LocalPipe(bindSender→WIRED/setTrack→ADOPTED/mount→MOUNTED) / RemotePipe(adoptTrack: transceiver→WIRED·track→ADOPTED / mount→MOUNTED). "어디서 멈췄나" 한 문장 진단 = 비정상 케이스 추적 인프라.

---

## 5. 남은 부록 (다음 세션 착수점)

안전/격리/가독은 소진(§7-1/3/5/6/7/8부분/9 + §13 + §5). 남은 건 **전제가 걸림**:

| 항목 | 막는 것 |
|------|---------|
| §7-10 발언방 일원화 | ptt↔talkgroups **결합 변경** → 라이브 회귀 |
| §7-11 freeze 흡수 | freeze↔floor **결합 + 관심사** → 라이브 |
| §7-4 ensure rebind | slot mid/ssrc 불변 **[미확인]**(서버 작업 중 — 확인 후) |
| §7-8 hydrate 완전 통합 | role/participant **회귀** → 라이브 |

**다음 세션 순서(권고)**:
1. **라이브 회귀** — §13/§5/§7-7 누적(표시 경로·stage·add 헬퍼)이 Conference/PTT/preview/타일 안 깨뜨렸는지.
2. **비정상 케이스 일괄** — 부장님 보류분(아래 §6). 이제 stage 인프라로 추적.
3. 결합 부록(§7-10/11)을 라이브와 함께.

---

## 6. 미해결 — 비정상 케이스 (부장님 "한몫에 조치")

부장님 라이브에서 비정상 순서로 깨지는 부분 발견(일괄 조치 보류):
- 송신: 캠 half→cold→full 전환 시 preview(케이스1 — `00e0c91` 로 일부 채움, 토대① 흡수).
- 송신: 캠 체크→미체크 반복 시 수신 타일 증식(케이스2 — `00e0c91`, applyTracksUpdate remove STREAM_UNSUBSCRIBED).
- B1(미적용): full→half 시 개인 트랙 active:false 가 STREAM_UNSUBSCRIBED 미발 → "영상 수신(다방)" 개인 타일 잔존.
- 셀프뷰 캡션 full(실제 half) — lab 캡션 stale(track:changed 미반영). lab UI.
- → stage(§5)로 "어디서 멈췄나" 추적해 일괄. **B1 = 수신 active:false → 제거 통지 일관**이 토대 ① 의 수신 버전.

---

## 7. 교훈

- **끝점 역추적(§10)**: element srcObject→mount→트리거→앱 구독 4칸 먼저. 윗단(ts_gap/서버) 정독 금지. 본 무음은 lab.js 한 칸(media:track 미구독)이었는데 ts_gap·enabled·코덱·서버로 헤맴.
- **SDK 약점 = 생명주기 통지 분산**: 좋은 SDK 는 `attach(el)` 한 줄, 교체·제거 자동. OxLens 는 STREAM_*·RESTARTED·media:track·track:changed·floor 6개 수동 조립 → 하나 누락=깨짐. → 토대(통지 단일 지점)+VideoSurface(자동)+raw(고급) 2계층.
- 단정 반복(enabled=false / 서버 rewrite ts_gap) → 부장님이 "소스상 없으면 없는 거" / "track-identity·패킷 먼저"로 매번 교정. **소스 검증 후 단정**.

---

## 변경 파일 (이번 세션)
- sdk(클라): `domain/local-endpoint.js`·`local-pipe.js`·`local-stream.js`·`remote-pipe.js`·`remote-stream.js`·`pipe.js`·`room.js`·`engine.js`, `ptt/power.js`·`ptt.js`·`virtual.js`, `shared/constants.js`, `tests/op_check.mjs`·`ptt_check.mjs`
- lab: `lab/lab.js`·`lab/index.html`(radio-vid)
- 설계: `design/20260615_ptt_recv_pipeline_redesign.md`(§1~§13 — 부장님 작성 + Claude §13 추가)
