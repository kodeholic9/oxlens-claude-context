// author: kodeholic (powered by Claude)
# 20260616b — SDK 국소 재작성(빈칸 1~9) + 경계 누수 정리 + arch_check 헌법 가드

> 흐름: 결함 부록(B1·캡션) → §7-11 freeze 흡수 → op_check 현행화 → **부장님 전수 감사(20260616a) 수령** →
> arch_check 가드 신설 + 수신 표시 경로 국소 재작성(빈칸 1·2·3remote·4·6·7·8·9·V3) → 경계 누수(dataset/style/visibility/UA) →
> c2/c3/t3d connState 복원 → §7-4 slot 식별. 라이브 회귀는 다음 세션(부장님). oxlens-home 18커밋(`4ce2dad`~`7db5b56`).
> 작업지침: `design/20260616_sdk_recv_pipeline_rewrite_guide.md`. 감사: `202606/20260616a_sdk_full_coupling_audit.md`.

---

## 1. 커밋 (oxlens-home, 18개)

| 커밋 | 내용 | 묶음 |
|------|------|------|
| `4ce2dad` | §13 B1 — 수신 active 토글 구독/해제 통지 일관(토대① 수신판) + 셀프뷰 캡션 duplex | 결함 부록 |
| `004d67c` | §7-11 — freeze 흡수(발언축 영상 마스킹 → virtual, freeze.js 삭제) | 결함 부록 |
| `4a494be` | op_check — talkgroups/virtual 테스트 stale 현행화(대조군) | 테스트 |
| `8da8db8` | **arch_check — SDK 결합도 헌법 가드 신설**(빈칸 1~9 건수 BASELINE) | 헌법 골격 |
| `2bce81d` | 빈칸6① — 수신 통지 단일 게이트 일반화(일반/slot 합류, _announced 멱등) | 국소 재작성 |
| `05ba865` | 빈칸6②/V3 — slot 출력훅 생성 시점 주입(늦주입 땜빵 폐기) | 국소 재작성 |
| `d6fb27d` | 빈칸7 — media:track room emit 死표면 폐기(STREAM_SUBSCRIBED 단일 표면) | 국소 재작성 |
| `22122a2` | 단계1 빈칸1 — VideoSurface 코어: element 생성·listener 흡수(DOM 단일 소유) | 국소 재작성 |
| `23ea64d` | 단계2 빈칸2 — base 상속 정상화(_outputMuted 훅, 자식 역참조 제거) | 국소 재작성 |
| `e8d2030` | 단계3a 빈칸3 — remote-mute/active 를 floor 게이트에서 분리(통로격리) | 국소 재작성 |
| `60f0f59` | 단계3b 빈칸4 — freeze 특수(detach/재attach)를 VideoSurface reveal/conceal 로(표시≠물리) | 국소 재작성 |
| `f036f51` | 빈칸9 — power LocalPipeState 직접비교 → LocalPipe 경계 getter | 국소 재작성 |
| `5fc69ca` | 빈칸8 — track.enabled 단일 게이트(power 우회 제거, mute/video-off 합성) | 국소 재작성 |
| `8944d95` | arch_check — 빈칸3 virtual freeze 는 PTT 본질로 유지 명시 | 가드 |
| `7a7e521` | 경계 누수 — VideoSurface 레이아웃 style 제거 + telemetry visibility env 단일화 | 경계 |
| `8677dfe` | UA 래퍼 제거 — _isSafari/_isFirefox 2단 위임 폐기, shared/ua.js 직접 | 경계 |
| `d234a06` | c2/c3/t3d — mockSig connState 복원(identify timeout 해소) + c3 dataset 검증 현행화 | 테스트 |
| `7db5b56` | §7-4 — slot 식별 서버 불변 확인 + virtual.ensure 직접 대입 폐기(rebind 게이트) | 잔여 부록 |

---

## 2. arch_check 헌법 가드 (`sdk/tests/arch_check.mjs`) — 핵심 산물

감사 20260616a 빈칸 1~9 를 **건수 기반 BASELINE**(라인 변동 무관)으로 박은 정적 가드. 위반이 BASELINE 초과 = FAIL.
응집처(pipe/remote-pipe/room/virtual)에 **부분 패치로 빈칸을 악화시키는 걸 차단**한다(직전 B1/freeze 가 "개판"이던 패턴 재발 방지).
12 게이트 PASS/0 FAIL. **TODO 27→4**(잔여 = 의도/정상).

| 게이트 | 상태 |
|---|---|
| 1 DOM분리 / 2 상속 / 4 표시≠물리 / 6 통지 / 7 死표면 / 8 게이트 / 9 레이어 / V3 출력훅 / 앱경계 / 식별게이트 | ✅ 해소 |
| 3 통로격리 | 🔸 remote 분리, virtual freeze 3 잔여 = **PTT 본질(-9999px masking, 부장님 결정 — 둔다)** |
| 6 본문(1) | 단일 게이트 emit = 정상 |

---

## 3. 빈칸 해소 — 수신 표시 경로 단일 파이프라인

- **빈칸1 DOM**: element 생성·unmute/visibility listener 를 VideoSurface 로. 정책(duplex/kind)은 isHidden+video-element 로 환원(passive 유지).
- **빈칸2 상속**: base 가 자식 전용(_muted/_pendingShow/setVisible) 역참조하던 걸 _outputMuted 훅 + RemotePipe override 로.
- **빈칸3 통로격리**: setRemoteState 의 remote-mute/active 를 floor 게이트(track 보류/detach)에서 분리 → _surface.setVisible 직접(floor 특수 불요). **freeze 판단 reason='floor'→duplex==='half'**(부장님 통찰 — freeze 는 트랙 속성).
- **빈칸4 표시≠물리**: freeze 의 detach/재attach 를 VideoSurface reveal()/conceal() 로. pipe 는 보류 판단만.
- **빈칸6 통지**: STREAM_SUBSCRIBED 발행을 단일 게이트(_emitStreamSubscribed, _announced 멱등)로. 일반/slot 합류.
- **빈칸7 死표면**: media:track room emit 폐기. STREAM_SUBSCRIBED+RemoteStream 단일 표면(demo 무시 — 재작성 예정).
- **빈칸8 게이트**: track.enabled 를 LocalPipe(_applyEnabled = !muted && _enabled)로 합성. power 직접 토글 제거.
- **빈칸9 레이어**: power 의 LocalPipeState 직접비교 → LocalPipe isActive/isSuspended/isReleased getter.
- **V3 출력훅**: slot 출력훅을 ensure 생성 시점 주입(Room 늦주입 땜빵 폐기).

---

## 4. 경계 누수 (SDK 가 앱 관심사 떠안음) — 전수조사 + 정리

| 누수 | 조치 |
|---|---|
| **dataset**(pipeId/source/userId) | 소비처 0, 디버깅 육안용 — 제거(앱 CSS/DOM 책임, LiveKit 패턴) |
| **레이아웃 style**(width/height/objectFit) | 제거(lab .tile video 가 이미 보유, inline 이 덮고 있었음) |
| **telemetry visibility** | document.visibilityState 직접 → env.visible(env-adapter 단일 추상) |
| **UA 래퍼** _isSafari/_isFirefox | 2단 위임(ua.js→pipe→VideoSurface 콜백) 폐기 → ua.js 직접. **VideoSurface 콜백 DI 는 테스트 mock 의도라 유지** |

**유지 결정**: freeze `-9999px`(PTT 본질) / adaptive-stream(ElementInfo) document.visibilitychange(DOM 저수준 관측 레벨 — env 주입은 4단계 체인이라 결합 증가).

---

## 5. 테스트 — c2/c3/t3d identify timeout 정정

"서버연결 baseline"으로 치부했던 c2/c3/t3d FAIL 은 실제로는 **mockSig connState 누락 stale**(이전 세션 engine.connect 가드 추가 시). connState 추가로 identify 통과 →
- c2: 가려져 있던 setMuted→TRACK_STATE_REQ(muted) 검증 복원(빈칸8 정합 확인).
- c3: recycle element dataset 검증을 dataset 폐기에 맞춰 현행화.
**전체 회귀 20/0 PASS**(헤드리스 16 + 살아난 c2/c3/t3d).

---

## 6. §7-4 — slot 식별 서버 불변 확인(서버 작업 종료 후)

서버 코드 실증: slot mid/ssrc 체류 중 불변 —
- vssrc: Room::new alloc_ptt_vssrc() per-room 1회, slot.new 보관.
- mid: assign_subscribe_mid 가 mid_map.get(track_id) 로 기존 mid 재사용. slot 상존 → release_stale_mids 회수 안 함.
→ virtual.ensure 직접 대입(rebind 게이트 우회) 폐기. 정상 no-op, 변경 감지 시만 rebind + log.warn. arch_check 식별게이트 0.

---

## 7. 교훈

- **축 먼저, 부분 패치 금지**: 즉흥 빈칸 깎기는 감사가 경고한 "축 없이 비일관 재발". 작업지침(전체 그림) 박고 한 호흡씩. arch_check 가 그 가드.
- **위치이동 ≠ 격리**: setRemoteState→_applyRemoteVisibility 메서드 이동은 arch_check 수치 0 변화(위치이동)라 revert. 진짜 격리는 floor 게이트에서 remote 분리(_surface 직접).
- **가드를 코드에 맞추지 말 것**: op_check 를 코드에 맞춘 건 talkgroups=대조군이라 정당했으나, 빈칸 강제형 메서드 스코프화는 "회피" 경계.
- **소스 검증 후 단정**: c2 "서버연결 무관" 오판(실제 mockSig stale). §7-4 는 서버 소스로 불변 확정.
- **부장님 영감**: dataset=앱 관심사 / freeze 판단=duplex(트랙 속성) / UA 래퍼 잉여 — 세 지적이 결정적.

---

## 8. 남은 것 (다음 세션)

- **라이브 회귀** — 18커밋 누적분(특히 빈칸8 _resumePipe mute 합성, VideoSurface element/freeze reveal·conceal). 부장님 환경.
- **§7-10 발언방 일원화** — ptt(floor/virtual.roomId)가 talkgroups.selected 참조. 타이밍 위험(setContext 가 _pub 갱신 전) + cross-sfu userId. 라이브 전제.
- **§7-8 hydrate 완전 통합** — ROOM_SYNC 는 reconcile 응집(완료), hydrate(ROOM_JOIN) 통합 미완. 전제: 응답 형태 정합([미확인], 서버 확인 가능) + role/participant 회귀.
- §7-4 ✅ 완료.

---

*author: kodeholic (powered by Claude)*
