# 세션 컨텍스트: OxLabs 2계층 판정 체계 확정

> 2026-03-30 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLabs Phase 0~2 완료 후, 판정 체계의 본질적 한계에 대한 설계 논의.
**"시험장비와 상용장비의 패턴이 동일한가? 정량적 정답이 있는가?"** 질문에서 출발하여, 2계층 판정 체계를 확정.

---

## 핵심 문제 제기 (부장님)

1. **정량적 정답이 없다** — loss 4.8%면 PASS, 5.1%면 FAIL인데 그 경계가 의미 있나?
2. **봇과 실기기의 괴리** — fake RTP는 NetEQ/jitter buffer/FEC/디코더 적응이 없다
3. **체감 품질 측정 불가** — PESQ/VMAF는 실제 미디어 디코딩이 필요하고, 봇에는 디코더가 없다
4. **MVS는 3000개 누적이 의미 있었는데, OxLabs는 100개도 안 될 것 같다**

---

## 논의 경과

### 접근 1: 체감 품질 측정 시도

PESQ(음성 MOS), VMAF(영상 품질) — 업계 표준이지만:
- 원본 미디어를 디코딩해서 파형/픽셀 비교해야 함
- 봇에 디코더가 없음 → 사실상 미니 클라이언트 구축 필요
- E-Model (G.107)로 네트워크 파라미터 → MOS 추정은 가능하나, 추정일 뿐 측정이 아님

**결론**: 봇으로 체감 품질 측정은 불가. 이건 OxLabs의 한계가 아니라 역할 분담의 문제.

### 접근 2: 발상 전환 — "품질"이 아니라 "SFU 행동"을 검증

SFU는 미디어를 생성하지 않고 릴레이한다.
→ **"릴레이를 올바르게 했는가?"는 정답이 있다.**

- subscriber RR이 publisher에 릴레이되면 FAIL (RTCP Terminator 위반)
- PTT 비발화자 RTP가 통과하면 FAIL (gating 위반)
- silence flush가 3프레임이 아니면 FAIL
- 이런 항목들은 **binary pass/fail이고 결정론적**

### 접근 3: 누적 가치 확보

MVS의 3000개는 프로토콜 × 메시지 × 파라미터 조합 폭발.
OxLabs는 기능 축 15 × 조건 축 7 × 규모 축 4 × 타이밍 축 5 = ~2100 조합.
+ 현장 스냅샷 재현이 자동 누적.

초기에 적더라도 **누적 구조가 설계에 내장**되어 있으면 된다.

---

## 확정: 2계층 판정 체계

### Layer 1: SFU 행동 검증 (결정론적)
- **성격**: binary pass/fail, 정답 있음
- **용도**: **실기기 시험 전 gate** — 하나라도 FAIL이면 실기기 안 감
- **누적**: 기능 추가 시 체크포인트 누적 (L1-01 ~ L1-21, 확장 예정)
- **환경**: 주로 pristine (네트워크 열화 없이 SFU 고유 행동만 검증)

주요 체크포인트:
- RTCP Terminator: RR 릴레이 차단, SR NTP 원본 유지, SR ts 연속성
- PTT Relay: gating, silence flush, keyframe 선행, SSRC rewriting, ts_gap
- PLI Governor: PLI→keyframe 응답, burst 자동 취소
- SubscriberGate: ACK 전 video 차단, ACK 후 GATE:PLI
- Floor Control: priority 순 grant, preemption, queue 정합성
- Core: fan-out 무결성, zombie cleanup
- Simulcast: layer switch SSRC/ts/keyframe
- Screen Share: non-simulcast relay

### Layer 2: 열화 내성 검증 (상대적)
- **성격**: 절대 기준 없음, 이전 실행 대비 회귀 감지
- **용도**: 코드 수정 후 "나빠졌는가?" 확인
- **메트릭**: loss_rate, jitter, ooo_count, floor_grant_latency
- **판정**: 이전 동일 시나리오+프로파일 대비 Δ 초과 시 REGRESS

---

## MVS 대비 포지셔닝 정리

| 관점 | MVS (2008) | OxLabs (2026) |
|:---|:---|:---|
| 검증 대상 | 프로토콜 메시지 필드 | SFU 릴레이 행동 |
| 정답 유무 | 있음 (expected value) | **Layer 1: 있음** / Layer 2: 상대적 |
| 시험항목 단위 | 메시지 | 시나리오 × 조건 × 체크포인트 |
| 누적 방식 | 사람이 MVML 작성 | **스냅샷 자동 누적** + 수동 curate |
| 실기기 전 gate | ✅ (전항목 PASS 필수) | ✅ (Layer 1 전항목 PASS 필수) |
| 체감 품질 | 해당 없음 | **해당 없음** (역할 분담) |

---

## 기각된 접근법

- **PESQ/VMAF 봇 내장** — 디코더 필요, 복잡도 폭발, SDK 검증 영역과 중복. OxLabs는 SFU 검증에 집중
- **E-Model MOS 추정을 pass/fail 기준으로 사용** — 추정일 뿐 측정 아님, 신뢰도 부족. 참고 지표로만 가능
- **통계 임계치 절대 기준** ("loss < 5%") — 경계가 자의적, Layer 2 회귀 감지로 대체

---

## 다음 작업

### Phase 2.5: 2계층 판정 리팩터링
- [ ] Layer 1 CheckpointResult 구조체 + 체크포인트 레지스트리
- [ ] 봇에 Layer 1 관측 포인트 추가:
  - subscriber RR 수신 감지 (publisher 봇 측)
  - SR NTP/RTP ts 검증 (subscriber 봇 측)
  - PTT gating 카운터 (비발화 구간 수신 패킷 수)
  - silence flush 프레임 수
  - keyframe 선행 여부
  - fan-out seq 비교 (subscriber N명 cross-check)
- [ ] Layer 2 회귀 비교 (이전 결과 JSON 로드 + diff)
- [ ] JudgeReport 통합 출력

### OXLABS_DESIGN.md 반영 완료
- 섹션 2 "판정 철학 — MVS vs OxLabs" 추가
- 섹션 4.4 "2계층 판정기" 전면 재작성
- L1-01 ~ L1-21 체크포인트 테이블
- 시나리오별 Layer 1 체크포인트 매핑
- 운용 시나리오에 Layer 1 gate 흐름 반영

---

*author: kodeholic (powered by Claude)*
