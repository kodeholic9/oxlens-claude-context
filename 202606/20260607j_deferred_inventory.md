// author: kodeholic (powered by Claude)
# 미뤄둔 작업 인벤토리 (2026-06-07 세션 — 클라 SDK C1~C7 + 데모 전환)

> 이번 세션에 "나중에"로 격리한 것들 단일 정리. 흩어진 done 보고(0607a~i)에서 추림.
> 분류: **G=라이브 게이트**(mock 금지, 라이브 선결) · **S=서버 선결** · **P=후순위/YAGNI** · **T=정리/별토픽(저비용)**.

---

## G — 라이브 게이트 (단일방 라이브 검증 후 착수)

| # | 항목 | 선결 | 출처 |
|---|---|---|---|
| G1 | **conference 라이브 2탭 RUN**(부장) — C1·C2·C3 첫 통합 작동 | localhost 서버 + 2탭 | 0607i |
| G2 | **데모 Phase 2 voice_radio**(C7 floor 단일방 1사이클: request→grant→talk→release) | G1 통과 | 데모 work order |
| G3 | **C7 Phase B** floor.js 단일방→다방(roomId 차원 + viaRoom/speakerRooms 살림) | **G2 통과(C7 B/C 게이트 해제)** | 0607h |
| G4 | **C7 Phase C** scope.js 본체(affiliate=Room 생성, SCOPE 0x1200, cross-sfu sub PC) | G3 후 | 0607h |

> 핵심: **G1→G2 가 부채 D(라이브 0회) 해소**. G2 통과해야 C7 다방(G3/G4) 게이트 열림. mbcp 다방 TLV·서버 fan-out 은 라이브로만 드러남(C3 user_id wire 전례).

---

## S — 서버 의존 (서버 실측/신설 선행)

| # | 항목 | 막힌 이유 | 닫는 조건 |
|---|---|---|---|
| S1 | **C1 #10 TOKEN_EXPIRING** | 만료 임박 S→C 통지 op 없음 | 서버 통지 op 신설 **또는** 클라 JWT `exp` 자가 디코드 자가 emit(클라단독 가능) — **[결재]** |
| S2 | **C1 #11/C2 #10 미디어PC 재연결·republish** | 미디어 PC 재연결 orchestration 미구현(WS 재연결만) | C2 republish(collectPreset 토대 有) + transport PC 재생성. REPUBLISHED 이벤트 자리만 |
| S3 | **C1 #16 RoomEvent.CLOSED**(KICKED/ROOM_DELETED) | 서버 ROOM_EVENT event_type 미실측 | 서버 room_ops.rs event_type 목록 실측 → 있으면 facade, 없으면 서버 신설 |
| S4 | **C1 #12 세션 resume** | 0x0103 RECONNECT=dead op(3사 0/3) | **신설 안 함.** 필요 시 IDENTIFY body `reconnect`+sid(livekit 패턴) + 서버 resume 지원 선행 — 별건 |

> C1 클라 facade 는 S1~S4 **자리(상수/이벤트)만** 깔림. 발화는 서버 확정 후(추측 코드 금지 — 0x0103 상상 재발 차단).

---

## P — 후순위 / YAGNI (실수요 시)

| # | 항목 | 출처 |
|---|---|---|
| P1 | **C3 D-2** adaptiveStream PiP(⑤) + pixelDensity(③ 정밀) | 0607d |
| P2 | **C3 E** setSubscribed(#3, SDP 변경→_renegotiateSubscribe) / 구독 권한(#11) / PiP 관측(#13) | 0607d |
| P3 | **C4 D** 모바일 백그라운드 재획득(#15, C2 §6-F 공유) / OS 기본장치 label 변경 감지(★4) | 0607e/f |
| P4 | **C4** 선택 출력장치 신규 mount element 자동 setSinkId 상속(현 _switchOutput=현존 element만) | 0607f |
| P5 | **C2 D/E/F** 동시성 락 3종 분리(現 단일 _trackLock 흡수) / stopTrackOnMute / 모바일 재획득 | 0607b |
| P6 | **C2** VideoPresets 전량(h90~h2160) — 현 h/l 2레이어만 export | 0607b |
| P7 | **C6 C** ParticipantEvent + participant.on(SPEAKING=ACTIVE_SPEAKERS 0x2500 라우팅 확인 후) / observer·status 게터 캡슐화 / telemetry SDP→collectSdp 캡슐화 / 타입드 콜백 시그니처(문서) | 0607g |
| P8 | **C7 D** 채널별 mute(Zello) / 전력 status(engine.status.power) / denied·revoke 사유 실측(FloorDenyReason/RevokeCause) / priority·queue·다방 §6 문서 | 0607h |
| P9 | **데모 Phase 3** 고급(상태등/active speaker/수동화질) — P7(C6 C)·C3 화질 표면 선결 / **Phase 4** 나머지 4시나리오(dispatch/moderate/support/video_radio) | 데모 work order |

---

## T — 정리 / 별토픽 (저비용, 동작 무관 or 결정만)

| # | 항목 | 상태 | 처리 |
|---|---|---|---|
| T1 | **emitError/emitFatal 死코드**(lifecycle, 호출처 0) | 미제거(C6-1 이 classify* 만 지목) | 死 확인됨 — 제거 1패치(별 토픽) |
| T2 | **media:fail 하네스 잔여**(`_e2e/peer.html` 리스너, core 소비처 0) | dormant(무crash) | 하네스 throw catch 전환 or 제거 |
| T3 | **C4 release/deactivate _trackLock 제외**(동기 종단 — 보정안 채택) | 적용됨 | **[택1]** 작업지침대로 포함 원하면 sync 보존 변형 |
| T4 | **C2 LocalStream.attach 미구현**(로컬 프리뷰=source track 직접 우회) | 우회 중 | 필요 시 LocalStream.attach(el) 추가(저비용) |
| T5 | **C3 데모 video-grid IntersectionObserver 제거** | conference 는 sdk/ 전환(IO 미사용)이나 타 시나리오 core/ 의존 | 전 시나리오 sdk/ 전환(Phase 4) 후 video-grid 제거 |
| T6 | **EnvAdapter window 미가드** | ✅ 해소(C4 C-2, typeof 가드) | 닫힘 |
| T7 | **system.toml [recording] oxtapd 死섹션** / 서버 oxtapd 미구현 | 발견_사항(0606c D-1) | 서버 별 토픽(수정 보류) |

---

## 요약 — 다음 액션 후보

1. **G1 라이브 RUN(부장)** → 막히면 그 자리 정정 → **G2 voice_radio** → C7 B/C(G3/G4) 게이트 해제. ← *부채 D 핵심 경로*
2. **C5(데이터/제어)** — 유일 미설계 카테고리(설계→구현). 라이브 무관, 지금 가능.
3. **T1·T2·T3·T4** 저비용 정리 묶음(1~2 커밋).
4. **S1(TOKEN_EXPIRING 자가 디코드)** — 클라단독 가능분이면 [결재] 후 지금 가능.

> P(후순위)·S(서버)·G3/G4(다방)는 선결 충족 전 진입 금지(부채 위 부채 방지).

---

*author: kodeholic (powered by Claude) — 미뤄둔 작업 단일 인벤토리. G(라이브 게이트)/S(서버)/P(후순위)/T(정리). 출처=0607a~i done.*
