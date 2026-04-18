# 세션: SDK Lifecycle Redesign 설계

> 2026-04-17b · 영역: SDK 설계 · author: kodeholic (powered by Claude)

---

## 요약

DataChannel 시퀀스 다이어그램 요청에서 시작하여, performance.mark 기반 실측 → getUserMedia 1283ms(96.4%) 병목 발견 → 업계 조사(LiveKit/mediasoup/Twilio) → 업계 문제점 5건 도출 → OxLens SDK Lifecycle 전면 재설계 문서 작성. 서버 사이드 participant state 업계 패턴도 조사 완료.

---

## 완료 항목

### 1. Perf Mark 실측 인프라 구축
- engine.js에 `_perf(label)` / `_perfReset()` 헬퍼 추가
- joinRoom~dc:open까지 12개 구간 mark 삽입
- video_radio app.js에 `ui:buttons_ready` mark 추가
- **실측 결과**: getUserMedia 1283ms(96.4%), 카메라 제외 시 48ms

### 2. 업계 조사 (클라이언트 SDK)
- **LiveKit**: ConnectionState 5단계 enum. connect/publish 분리. Quick(ICE restart)→Full(PC 재생성) 2단계 복구. stream 보존. prepareConnection으로 사전 워밍업
- **mediasoup**: transport.connectionState. participant 개념 없음(앱 책임). transport 단위 독립 관리. produce/consume 개별 호출
- **Twilio Video**: room.state 3단계. createLocalTracks→connect 순서(미디어 먼저)
- **공통 패턴 5개**: 단일 enum / connect-publish 분리 / 단계적 복구 / stream 보존 / gUM 복구 경로 재호출 없음

### 3. 업계 문제점 5건 도출
- 3.1 ConnectionState 단일 enum이 WS/PC 분리 상태 표현 불가 (LiveKit Swift Issue #367, #368, #410)
- 3.2 Quick Reconnect(ICE restart) 서버 재시작 시 무의미. 단일 인스턴스 효용 제한
- 3.3 PTT 고유 상태(Floor, Power, bearer, 가상 SSRC) 복구 전략 업계 부재
- 3.4 미디어 획득 실패 시 부분 동작(청취 모드) 자동 fallback 없음
- 3.5 Twilio "tracks 먼저" → WS 실패 시 카메라 헛도는 문제

### 4. SDK Lifecycle Redesign 설계 문서 작성
**`context/design/20260417_lifecycle_redesign.md`** (산출물, outputs에서 복사 필요)

- **4.1** Phase 5단계 (IDLE→CONNECTED→JOINED→PUBLISHING→READY)
- **4.2** Phase 전이 규칙 + 종속 관계 (JOINED에서 PC를 track 없이 생성)
- **4.3** 자원별 독립 상태 추적 (Phase + ws/pc/media/dc/floor/power/recovery 개별)
- **4.4** Reactive 연쇄 실행 (_setPhase → onPhaseEnter/Exit 자동)
- **4.5** 서버 통보(STALLED/SUSPENDED/REVOKE/kicked/WS close) → Phase 반응 매핑
- **4.6** 오류별 복구 전략 (단계적 fallback, stream 보존)
- **4.7** 재시도 정책 (실패 사유 분류 classifyMediaError/classifyPcError + 액션별 간격/최대/timeout/포기)
- **4.8** 포기 시 자원 해제 체인 + lifecycle:error/fatal 알림 (reason+message+preserved+action)
- **4.9** PTT 고유 복구 (Floor/Power/PttRewriter/bearer, floor 획득 중 복구)
- **4.10** 미디어 부분 실패 처리 (JOINED=청취 모드)
- **4.11** 공개 API 변경안 (enableMic/enableCamera/disableMic/disableCamera + sdk.status + lifecycle 이벤트)
- **4.12** 시나리오 8종 흐름
- **4.13** 관찰 3계층 (sdk.status 동기 스냅샷 / lifecycle 이벤트 / 어드민 텔레메트리) + 데모 공통 표시등
- **4.14** Perf mark 통합 (Phase 전이 + 복구 mark)
- **구현 Phase 1~3** 로드맵, 서버 변경 제로

### 5. 업계 조사 (서버 사이드)
- **LiveKit 서버**: ParticipantInfo.State 4단계 enum (JOINING→JOINED→ACTIVE→DISCONNECTED). state guard로 동작 제한. webhook 발생
- **mediasoup 서버**: participant 개념 없음. transport/producer/consumer 개별 상태. 앱이 peer 정의
- **Janus 서버**: Session→Handle 계층. Event Handler 플러그인으로 비동기 이벤트 push. 명시적 participant state enum 없음
- **OxLens 서버 적용 가능 지점**: ParticipantPhase(Created→Intended→Active→Suspect→Zombie) 도입 후보. 맥북에서 코드 확인 후 구체화 예정

### 6. 현재 복구 경로 코드 추적 (4건)
- getUserMedia 실패: 깔끔하나 수동 재시도만 가능
- setupPublishPc 실패: ★ stuck (좀비 상태, 복구 경로 없음)
- WS 끊김: 전부 파괴 → gUM 재호출 1.3초
- PC failed: leaveRoom → 전부 파괴 → gUM 재호출 1.3초

---

## 변경 파일

### 수정
- `oxlens-home/core/engine.js` — _perf/_perfReset 헬퍼, joinRoom~_onJoinOk 12개 perf mark, ICE/DTLS/DC 이벤트 타이밍
- `oxlens-home/demo/scenarios/video_radio/app.js` — ui:buttons_ready mark

### 산출물
- `design/20260417_lifecycle_redesign.md` — SDK Lifecycle 전면 재설계 (요약본 저장됨, 전체 본문은 다운로드 파일로 교체 필요)
- `design/20260417_server_participant_phase.md` — 서버 사이드 Participant/Session Phase 업계 조사 + OxLens 적용 후보

---

## 오늘의 지침 후보

- **Phase 상태머신 도입**: 암묵적 플래그 조합(5개) → 명시적 Phase enum + 자원별 독립 상태. 복잡도가 올라가는 게 아니라 코딩/디버깅이 쉬워진다
- **stream은 복구 대상이 아니라 보존 대상**: PC 실패 시 stream 파괴 금지. replaceTrack으로 재사용. getUserMedia 재호출 0ms
- **Reactive 연쇄 실행**: _setPhase(JOINED) 한 줄이면 진입 로직이 PC 재생성→replaceTrack→PUBLISHING→READY까지 자동. 수동 절차 나열 금지
- **재시도 전 실패 사유 분류**: NotAllowedError(재시도 무의미) vs NotReadableError(재시도 의미 있음). 분류 없이 일괄 재시도 금지
- **관찰 가능성 3계층**: sdk.status(동기) + lifecycle 이벤트(비동기) + 어드민 텔레메트리(서버 경유). 플래그 조합 추론 금지

## 오늘의 기각 후보

- **joinRoom에서 getUserMedia만 병렬화하는 최소 변경**: 근본 해결이 아님. Phase 분리가 근본 해결
- **클라이언트 Phase를 서버 Phase와 동기화**: 별도 도메인. 클라이언트 Phase는 클라이언트 자원 상태, 서버 Phase는 서버 참가자 상태. 연동은 하되 동기화 강제는 불필요

---

## 다음 세션

- **설계 문서 복사**: outputs → `context/design/20260417_lifecycle_redesign.md`
- **서버 사이드 Phase 설계**: 맥북에서 participant.rs, state.rs, room.rs 열어보고 암묵적 상태 추론 지점 구체 파악. ParticipantPhase enum 설계
- **구현 착수 판단**: Phase 1(내부 리팩터) 시작 여부

---

*author: kodeholic (powered by Claude)*
