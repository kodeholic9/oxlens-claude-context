# OxLens 제품 성숙도 평가 — 2026-04-10

> 39일간(03-09~04-10) 139개 세션 + 50개 대화 기반 평가
> author: kodeholic (powered by Claude)

---

## 잘하고 있는 것

### 설계→구현 순서가 철저하다
"코딩해줘" 전에 반드시 설계 논의가 있고, 기각 사유까지 기록한다. SWITCH_DUPLEX는 시장 분석(3GPP MCPTT Private Call)부터 시작해서 make-before-break 전략 확정 후 코딩에 들어갔고, Moderated Floor Control은 설계만 하고 "hub 없이 안 된다"는 판단으로 멈췄다.

### 아키텍처 원칙이 코드를 보호한다
"방은 빈 그릇" 원칙 덕분에 RoomMode 제거(14파일) 시 기능 회귀 제로. per-track duplex → TrackType 추상화 → SWITCH_DUPLEX fan-out 로직 0줄. 원칙이 구조를 잡으면 기능 추가가 쌈이 된다.

### 기각 기록이 자산이다
"source 이름으로 simulcast 판단", "ingress에서 non-sim 등록", "gRPC typed proto 7서비스" — 기각 사유를 안 적어두면 3개월 후에 또 시도한다. 업계에서 이 수준으로 기각 사유를 관리하는 1인 프로젝트는 없다.

### 텔레메트리 설계가 상용 수준이다
"AI에게 오염된 정보를 주면 AI도 쓸모없어진다"는 철학 위에, Track Identity → AGG LOG → Contract Check까지 계층화된 진단 체계. LiveKit도 이 수준의 스냅샷 진단은 없다.

---

## 부족한 것 — 대한민국 표준 SFU가 되려면

### 테스트 자동화가 없다
OxLabs 설계(L1 21체크포인트, L2 regression)까지 갔는데 Phase 3에서 멈춤. 부장님이 브라우저 탭 3~4개 열고 눈으로 확인하는 수준. Conference 3인 + PTT 3인 시나리오를 CI에서 돌려야 한다. mediasoup 테스트 800개, LiveKit CI에서 실 미디어 E2E.

### 부하 테스트 데이터가 없다
"아키텍처는 1000인 검증"이라고 쓰여 있지만 30인 이상 테스트한 적 없음. RPi에서 30인이 진짜 되는지, lock_wait가 10인 넘어가면 어떻게 되는지, fan-out N=100일 때 relay latency가 몇 ms인지 — 숫자가 없다. B2B 영업에서 "몇 명까지 되나요?"에 데이터로 답해야 한다.

### 녹음이 없다
디스패치/공공안전 B2B에서 녹음은 법적 요구사항. oxrecd가 계속 밀리고 있는데, 이게 없으면 첫 계약이 안 된다. 기술적으로 어려운 게 아니라 우선순위에서 밀리는 것.

### 문서화된 SDK API가 없다
`addVideoTrack`, `switchDuplex`, `floorRequest` — 좋은 API인데, JSDoc도 `.d.ts`도 없다. 고객 개발자가 SDK를 쓰려면 소스를 읽어야 한다.

---

## 부족한 것 — 글로벌 탑으로 가려면

### TURN/TLS가 없다
ICE-Lite + direct UDP만으로는 폐쇄망 B2B에서만 된다. 공인망, NAT 뒤, 방화벽 환경에서 동작하려면 TURN 필수. 글로벌은커녕 국내 공공망 납품에도 TURN이 필요하다.

### Congestion Control이 수동이다
TWCC 수집은 하지만 서버 측 BWE 피드백이 REMB 고정값. LiveKit StreamAllocator 수준의 subscriber 방향 동적 BWE가 없으면, 다수 참가자 환경에서 graceful degradation이 안 된다. Simulcast 레이어 자동 전환(PLI Governor Phase 2)이 계속 미뤄지고 있는 것도 이 맥락.

### 에러 복구 전략이 hope-based이다
STALLED → ROOM_SYNC 1회 + 토스트가 전부. "ROOM_SYNC 실패 = 서버 버그" 원칙은 맞지만, 서버 버그가 0이 될 때까지 사용자가 기다릴 수는 없다. LiveKit은 TrackSubscriptionFailed + 자동 재구독, mediasoup은 transport 레벨 ICE restart 제공. 상용 환경에서 "서버가 완벽하면 된다"는 전략은 통하지 않는다.

### 멀티 노드 스케일링이 설계 단계이다
단일 인스턴스 RPi에서 출발한 건 전략적으로 맞지만, 글로벌 SFU는 multi-region cascading이 필요. oxhubd 설계에 N:M 비대칭 스케일링이 언급되어 있지만 실제 구현 경로 없음. 지금 당장 할 일은 아니지만 아키텍처가 막히지 않는지 검증 필요.

---

## 방법론 피드백

### "부장님+AI 대리" 모델의 한계를 인식해야 한다
지금 방식은 놀라울 정도로 생산적이지만, AI 대리는 실행 검증을 못 한다. 코드를 쓸 수는 있는데 돌려볼 수가 없다. "빌드 성공"까지는 AI가 하고, "동작 확인"은 부장님이 브라우저에서 한다. 이 갭을 OxLabs 자동화로 메워야 한다. OxLabs가 CI에서 돌아가면 — AI가 코드 쓰고, 테스트 돌리고, 결과 분석까지 한 세션에서 가능해진다.

### 설계 문서를 더 일찍, 더 작게 써라
oxhubd 설계서(0331)는 훌륭했는데, 거기서 구현까지 8일 걸렸다. 그 사이에 annotation, SWITCH_DUPLEX, dispatch 시나리오가 끼어들었다. 설계서 작성 → 즉시 구현 → 검증 사이클을 1~2일로 줄이면, "설계와 구현이 어긋나는" 문제가 줄어든다.

### 성능 프로파일링을 습관화해라
`cargo flamegraph`, `tokio-console` 같은 도구를 한 번도 안 쓴 것 같다. fan-out 핫패스에서 DashMap 직접 순회로 바꾼 건 좋았지만, 실제로 얼마나 개선됐는지 측정한 적이 없다. "아마 빨라졌을 것이다"는 상용 제품의 언어가 아니다.

---

## 총평

39일에 서버+SDK+5시나리오+어드민+텔레메트리를 1인 개발로 만든 건, 설계 역량과 실행 속도 양쪽 다 상위권. Conference+PTT 단일 엔진이라는 기술 해자는 진짜다.

하지만 지금은 **"기술 데모가 인상적인 프로젝트"**이지, **"돈을 받고 납품할 수 있는 제품"**은 아니다. 그 갭을 메우는 건 — 테스트 자동화, 녹음, TURN, SDK 문서, 부하 데이터 — 화려하지 않은 작업들이다.

---

## 우선순위 제안 (제품화 경로)

| 순위 | 항목 | 사유 |
|------|------|------|
| 1 | 녹음 (oxrecd) | 첫 계약의 법적 요구사항 |
| 2 | OxLabs CI 자동화 | AI+사람 생산성 한계 돌파 |
| 3 | 부하 테스트 30인+ | 영업 데이터 확보 |
| 4 | SDK API 문서 (.d.ts + JSDoc) | 고객 개발자 온보딩 |
| 5 | TURN 연동 | 공인망 배포 필수 |
| 6 | Congestion Control 고도화 | 다수 참가자 품질 보장 |

---

*다음 평가: 1개월 후 (2026-05-10) — 위 항목 진행률 기준*
