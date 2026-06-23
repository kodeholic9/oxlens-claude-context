// author: kodeholic (powered by Claude)
# 20260603o — Reference 검토 (로컬 3종): 새 클라 골격을 위한 코드 레벨 정독
> 완료 보고 → [20260603o_reference_review_local_done](../../202606/20260603o_reference_review_local_done.md)

> 김과장(Claude Code) 작업 지침. 분업 체계 표준 구조.
> 완료 보고: `context/202606/20260603o_reference_review_local_done.md`.
> 배경: oxlens-home 웹 클라 **전면 재작성** 결정(2026-06-03, 부장님). cross-sfu 가 클라 비대화(Engine God Object 63KB)를 드러냈고, 서버 기능 요구 완결 시점이 재작성 타이밍.
> **이 작업은 코드 작성이 아니다 — 레퍼런스 정독 + 검토 보고서 작성.** 베끼기 금지(§7).

---

## §0 의무 점검

1. 본 지침 통독. **목적 = 새 클라 골격 설계 근거 수집**(베끼기 아님).
2. 검토 대상(로컬, 코드 레벨):
   - `~/repository/reference/client-sdk-js/` (LiveKit, Apache-2.0)
   - `~/repository/reference/lib-jitsi-meet/` (Jitsi, Apache-2.0)
   - `~/repository/reference/mediasoup-client/` (BSD)
3. 현 클라 구조 인지: `oxlens-home/core/` — Engine(63KB God Object) / Room / Endpoint / Pipe / SdpNegotiator / Signaling. PROJECT_WEB.md 참조.
4. **분담**: 로컬 코드 = 김과장(본 지침). 온라인 문서/아키텍처 = 김대리(별도). 같은 질문지(Q1~Q5)로 갈라 보고 한 표로 합친다.

---

## §1 컨텍스트 (왜 보나)

새 클라의 **결정 질문**에 레퍼런스가 어떻게 답했는지 수집한다. 우리는 답을 **베끼는 게 아니라**, 검증된 설계 경계를 보고 **OxLens 정체성(PTT/half-duplex 코어)에 맞게 재단**한다. 레퍼런스엔 PTT 가 없으므로(Q5), 그들과 우리가 갈라지는 지점을 찾는 게 핵심 산출이다.

**우리 새 클라 골격 가설** (검토로 검증/반증할 대상):
- `Kernel` 이 `core`(Transport / Signaling / SDP / Pipe / Room / Endpoint / MediaAcquire / **PTT subsystem** / **Scope**)를 품고, `plugins`(Telemetry / Annotate / Moderate / TrackDump)가 정의된 훅으로만 붙는다.
- 의존 방향 단방향: **부가 → 코어** (코어는 부가를 모름, `if(ptt)` 분기 0).
- 연결 단위(sfu별 PC pair)를 **1급 객체(Transport)**로 추출 — cross-sfu 가 이 안에서만 끝나게.

---

## §2 검토 질문지 (Q1~Q5) — 3종 공통

각 레퍼런스에서 아래 5개에 **코드 위치 + 한 줄 요약**으로 답한다. "좋다/나쁘다" 평가 금지 — **사실(어디에 어떻게)만** 수집.

| # | 질문 | 우리 설계에 주는 것 |
|---|---|---|
| **Q1** | **연결 단위 추상화** — PC(pair/transport)를 어떤 객체로 뺐나? 누가 소유(Engine격)? 누가 생성(factory)? 노드/연결이 N개일 때 자료구조(배열/맵)는? | Transport-per-sfu 추출의 청사진 |
| **Q2** | **코어↔확장 경계** — 코어가 부가 기능(filter/stats/screenshare)을 모르게 하는 훅·이벤트·인터셉터 모델은? 트랙 송신 전처리(filter)와 시그널링 op 위임을 어디서 여나? | Extension 패턴 승격 근거 |
| **Q3** | **방/참가자/트랙 계층** — Room/Participant/Track(우리 Room/Endpoint/Pipe)을 어떻게 나눴나? **논리(방)와 물리(연결/PC)를 어디서 가르나**? Track 객체가 PC 를 직접 쥐나, 한 겹 위 객체가 쥐나? | 논리/물리 분리선 |
| **Q4** | **재협상·재연결** — track add/remove 시 renegotiation 트리거·순서를 코어 어디에 두나? PC 끊김→복구(ICE restart / 재생성) 책임 객체는? track/stream 보존하나 재생성하나? | reconnect/re-nego 배치 |
| **Q5** | **(우리만의 질문) "트랙 평등" 가정의 위치** — 그들엔 half-duplex/floor 가 없다. "모든 트랙은 평등하게 송수신"이라는 가정이 **코어 어디에 박혀 있나**? (예: subscribe 시 자동 구독, mute 처리, 우선순위 부재) | 우리가 PTT(floor gating / half-duplex)를 코어에 넣을 때 **이 지점에서 갈라져야** 함을 표시 |

---

## §3 결정 추천 (정지점)

- **정지점 0개** — 검토 보고서라 위험 phase 없음. 단 **3종 모두 Q1~Q5 빠짐없이** 채울 것(빈칸은 "해당 없음 + 이유" 명시).
- **합격 기준**: 3종 × 5질문 = 15셀 표가 코드 위치(파일:심볼) 근거로 채워지고, **§5 교차 비교**(3종이 같은 질문에 어떻게 다르게 답했나)가 도출됨.

---

## §4 단계별 작업

### Phase A — mediasoup-client (가장 작고 우리와 가까움 — 먼저)
- `Device` / `Transport`(send·recv 분리) / `Producer` / `Consumer` 구조.
- 특히 Q1(Transport 가 1급, Device 가 소유) + Q3(Producer/Consumer = 우리 Pipe 대응).
- 핵심 파일: `src/Device.ts`, `src/Transport.ts`, `src/Producer.ts`, `src/Consumer.ts`, `src/handlers/`.

### Phase B — client-sdk-js (LiveKit — 가장 가까운 청사진)
- `RTCEngine` ↔ `PCTransport`(publisher/subscriber 2개) 소유 구조 = 우리 가설과 동형.
- Q1(RTCEngine 이 transport 소유) + Q2(Room 이벤트 모델) + Q4(reconnect — LiveKit 강점).
- 핵심: `src/room/RTCEngine.ts`, `src/room/PCTransport.ts`, `src/room/Room.ts`, `src/room/participant/`, `src/room/track/`.

### Phase C — lib-jitsi-meet (대조군 — 다른 계보)
- Jitsi 는 다른 접근(JVB, 전통 conference). **대조용** — 우리/LiveKit/mediasoup 와 어디서 갈리나.
- Q3(conference/participant 모델) + Q5(트랙 평등 가정이 가장 두드러질 것).
- 핵심: `JitsiConference.js`, `modules/RTC/`, `modules/xmpp/`(시그널링 — 우리와 완전 다름, 경계만).

### Phase D — 교차 비교 + 보고서
- 15셀 표 완성 → §5 교차 비교 도출.

---

## §5 변경 영향 범위

- **코드 변경 0** — 레퍼런스는 read-only 정독. oxlens 소스 무수정.
- 산출 = 보고서 1개(아래 §8).

---

## §6 운영 룰

1. **정지점 0** — 검토 작업.
2. **베끼기 절대 금지**(§7) — 코드 복사·구조 모방 결론 금지. "그들은 이렇게 했다"는 사실만. "우리도 이렇게 하자"는 김대리 설계 단계 몫.
3. **평가 자제** — "좋다/나쁘다" 아닌 "어디에 어떻게"만. 우열 판단은 설계 회의에서.
4. **추가 조사 금지** — 3종 + Q1~Q5 범위 밖(다른 레퍼런스, 우리 코드 리팩터 제안 등) 손대지 말 것. 발견 시 *발견_사항* 으로 보고만.
5. **2회 막히면 중단** — 특정 레퍼런스 구조 파악 2회 실패 시 "파악 실패 + 막힌 지점" 보고.

---

## §7 기각된 접근법 (베끼기 경계)

| 접근 | 기각 이유 |
|---|---|
| 레퍼런스 코드를 새 클라에 복사/이식 | OxLens 정체성 상실. 라이선스(Apache 고지 의무) + 정체성 둘 다 위반. **구조를 배우되 코드는 우리 것** |
| "LiveKit 구조 그대로 채택" 결론 | 그들엔 PTT 없음(Q5). 트랙 평등 가정이 우리 floor/half-duplex 와 충돌. 재단 필수 |
| 좋다/나쁘다 평가 | 검토는 사실 수집. 우열은 설계 회의(김대리 종합 후 부장님 결정) |
| 3종 중 일부만 (시간 절약) | 대조군(Jitsi) 빠지면 "다른 계보와의 분기"가 안 보임. 3종 다 |

---

## §8 산출물

1. 보고서 `context/202606/20260603o_reference_review_local_done.md`:
   - **15셀 표** (3종 × Q1~Q5, 각 셀 = 코드 위치 `파일:심볼` + 한 줄 사실)
   - **§5 교차 비교**: 같은 질문에 3종이 어떻게 다르게 답했나 (특히 Q1 연결 추상화 / Q3 논리·물리 분리선 / Q5 트랙 평등 가정 위치)
   - **Q5 집중**: 3종 모두에서 "트랙 평등" 가정이 박힌 자리 목록 → 우리가 PTT 코어화 시 갈라져야 할 지점 후보
   - **발견_사항**: 범위 밖 관찰
2. 코드 변경 0 (정독만).

---

## §9 시작 전 확인

- [ ] `reference/` 3종 디렉토리 구조 파악 (각 `src/` 진입점)
- [ ] mediasoup-client `Transport.ts` 의 send/recv 분리 방식
- [ ] LiveKit `RTCEngine.ts` 의 transport 소유 필드(publisher/subscriber)
- [ ] 각 레퍼런스의 "PC 생성" 코드 위치 (Q1 핵심)
- [ ] Q5 — 각 레퍼런스에서 subscribe(수신) 자동성/mute/우선순위 처리 위치

---

## §10 직전 작업 처리

- 직전 = cross-sfu Phase 2b(서버 control plane 완성), 커밋·푸시 완료.
- 본 작업 = 클라 재작성 전 레퍼런스 검토(로컬 코드). 병행 = 김대리 온라인 검토(같은 Q1~Q5).
- 완료 후: 두 보고서(로컬 코드 + 온라인 아키텍처) 합쳐 **새 클라 골격 설계 문서** 진입.
- 백로그(누적): signal_client connect_and_join 분리 / ptt_rapid floor flake / sfu 영구다운 재배치 / admin sfu별 라벨링 / REST `/media/rooms` 인증 불일치.

---

*author: kodeholic (powered by Claude)*
