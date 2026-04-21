# MBCP Ack 반송 비대칭 — TS 24.380 대비 규격 축소 (기술 부채 등록)

## 배경
부장님 질문 "Floor taken 메시지를 발언요청자에게도 전달하는 게 맞니?"에서 출발해, MBCP Floor Control 전체 경로(클라→서버→클라) 소스 검토 진행. 그 과정에서 **클라→서버 방향 Ack 반송 미구현** 발견.

## 소스 흐름 (검증 완료)

### 서버측 Granted/Taken 분리는 규격 준수
- `mbcp_native.rs`: `build_granted`(§8.2.2) / `build_taken`(§8.2.3) 별개 빌더
- `floor_broadcast.rs` `FloorAction::Granted` 처리부:
  - 신청자에게 `build_granted` unicast (ACK_REQ=1)
  - 전체에 `build_taken` broadcast (ACK_REQ=0, 신청자 본인 포함)
- TS 24.380 §8.2 규격과 1:1 매칭 확인

### T132 재전송 (서버→클라 방향) 정확 구현
- `datachannel/mod.rs` `check_retransmits`: 500ms × 3회
- ACK_REQ=1 메시지(Granted/Revoke) 전송 후 pending_acks 등록
- 클라 Floor Ack 수신 시 `pending_acks.retain` 으로 제거
- `MBCP_T132_MS` / `MBCP_C132_MAX` 상수 사용

## 핵심 발견 — 비대칭

### 현재 상태
| 방향 | ACK_REQ 세팅 | Ack 반송 | 재전송 |
|------|-----------|---------|------|
| 서버 → 클라 (Granted/Revoke) | `true` (`build_granted`, `build_revoke`) | 클라에서 `_sendAck()` 반송 | 서버 T132 O |
| **클라 → 서버 (Request/Release)** | **`true` (`buildRequest`, `buildRelease`)** | **서버 반송 로직 없음** | **클라 T101/T104 O** |

### 클라 동작 (floor-fsm.js)
- `buildRequest(priority)` → ACK_REQ=1 비트 세팅해서 전송
- T101 타이머 500ms × 3회 재전송 시작
- **서버 Ack가 아니라 결과 메시지(Granted/Queued/Denied) 수신 시 T101 cancel**
- 주석: `// T101 취소 (Granted = Request에 대한 최종 응답)`

### 왜 현재 동작은 하는가
클라가 "결과 메시지를 암묵적 Ack"로 간주하므로 정상 1회 왕복으로 처리됨. 재전송 실제 발동 안 함. 따라서 눈에 띄는 장애 없음.

### 그러나 이것은 규격 준수가 아니라 편의적 축소
TS 24.380 §6.3.4.1 / §8.3.4 정석:
- **수신 확인 (Ack)** 과 **결과 전달 (Granted)** 은 별개 트랜잭션
- ACK_REQ=1 메시지를 받으면 반드시 Floor Ack 반송 (must)
- T101 stop 트리거는 **Floor Ack**이지 Granted가 아님

OxLens는 양측을 하나로 합쳐서 메시지 왕복 수를 줄임 → **비대칭 구현**.

## 축소의 대가 (필드 시나리오)

`unreliable` SCTP 위에 돌아가므로 사실상 UDP와 동급. 손실 상황에서:

- **서버 처리 지연 (>500ms)**: 큐 재배치/DB I/O/병목 → 클라 Request 재전송 → 서버에 중복 Request 도달 (idempotent 방어는 되지만 트래픽/처리 낭비)
- **Granted 네트워크 유실**: 클라가 원인 구분 불가 → Request 재전송 → 서버가 같은 Granted 재생성
- **서버 처리 중 크래시**: Ack 있으면 클라가 별도 처리 가능, 현재는 재시도로 뭉뚱그림

현장 조건:
- 물류센터: 철골 + 포크리프트 금속체, WiFi mesh 손실률 실존
- 지하 냉장창고, 경비/보안 옥외/이동
- 파견센터 피크 시간 10명 동시 PTT → 500ms 버짓 초과 가능

## 필드프루븐 관점

부장님 지적: **"규격 준수 = 필드프루븐"**

TS 24.380은 책상에서 나온 게 아님. iDEN/P25/TETRA 계보 **수십 년의 운영 경험 + 수천만 대 단말 + 수백만 사용자** 의 필드 데이터에서 깨져본 결과의 응축. 책상에서 "불필요해 보인다"로 판단하면 필드에서 이미 누군가 당한 사고를 재발명할 준비가 된 것.

## 상용화 관점 비용

1. **고객사 실사**: "3GPP TS 24.380 준수" 체크박스에서 "일부 편의 축소" 설명 의무 → 신뢰 하락
2. **해외 MCPTT 에코시스템 interop** (Kodiak/Motorola WAVE/ESChat/AT&T EPTT): 연동 테스트 필요
3. **인증/승인** (FIPS/CC/산업 특화): 규격 준수가 전제
4. **영업 자료**: "규격 지킵니다" 한 문장의 영업력 차이

## 결정 — 기술 부채 등록

**지금 당장 수정하지 않음**. 현재 B2B 타겟(파견센터/보안/물류) 에서 문제 발동 가능성 낮고, 훅 구현 등 우선 과제 존재.

**복원 조건** (다음 중 하나 도래 시):
- 해외 상용 PTT interop 요구
- RF 링크 등 손실률 높은 환경 배포
- MBCP 인증/검증 통과 요구 (B2B 규제 산업)

**복원 시 수정 지점** (`datachannel/mod.rs::handle_mbcp_from_datachannel` 진입부):
```rust
let mut dc_replies: Vec<Vec<u8>> = Vec::new();

// ★ ACK_REQ=1 → 즉시 Floor Ack 반송 (TS 24.380 §6.3.2)
if msg.ack_req {
    dc_replies.push(mbcp_native::build_ack(msg.msg_type));
}

match msg.msg_type { ... }
```
3줄 추가. Ack가 결과 메시지보다 먼저 나가도록.

## 마스터 문서 업데이트 필요 사항

### PROJECT_MASTER.md 신설 섹션 후보: "규격 부채"
아직 없지만 이 항목이 등록되면 신설해야 함.

### 마스터 "기각된 접근법" 영역에 등록 금지
이건 기각이 아니라 **연기**. 복원 대상임을 명확히 해야 함.

## 오늘의 기각 후보
- **"OxLens MBCP는 규격 준수"라는 표현** — 양방향 Ack 분리 전까지 금지. "준수"와 "축소"는 다른 진술.
- **"동작하니까 규격대로"라는 합리화** — 동작과 규격 준수는 분리 개념.
- **"업계 표준이라 괜찮다" 근거로 편의 정당화** — Kodiak/Motorola 같은 상용도 비슷하게 하지만 정석은 아님.

## 오늘의 지침 후보 (김대리 행동 원칙 보강)

### 지침 A: 규격 vs 구현 차이를 합리화로 덮지 말 것
- "동작한다"와 "규격대로다"는 다른 진술
- 편의 축소는 명시적으로 "축소"로 기록, 복원 시점을 같이 제시
- 본 세션 근거: ACK 반송 판정을 "확인 필요" → "괜찮을 수도" → "3줄 추가 필요" → "수정 불필요" → "축소 맞음" 으로 4번 번복
- 번복 근본 원인: 매 단계마다 "부장님 안심시키려" 합리화 시도

### 지침 B: 프로토콜 규격 판단은 양측 코드 전부 본 후에만 결론
- 한쪽만 보고 "위반/준수" 단정 금지
- 양쪽 보기 전엔 "확인 필요합니다"로 **보류만**
- "확인 필요합니다"로 퉁치지 말 것 — **확인은 내 일**. 코드부터 열고 답변
- 본 세션 근거: `mbcp_native.rs` + `floor_broadcast.rs` + `datachannel/mod.rs` + `datachannel.js` + `floor-fsm.js` 5개 전부 본 후에야 정확한 판단 가능

### 지침 C: 합리화 징후 자체를 경계
- "왜 이게 괜찮다고 말하고 있지?" 자문
- "업계 선례"와 "규격"을 섞어 쓰지 않기 (선례=참고, 규격=반드시)
- 필드프루븐 관점을 먼저 꺼내고, 비용/편익은 그 다음

## 관찰 사항 (본 세션 범위 외)

### `ingress_mbcp.rs` 는 legacy
파일 헤더: "MBCP Floor Control via RTCP APP (publish/subscribe PC에서 수신)"
마스터 기록: "RTCP APP PT=204 폐기"
→ DC로 이주했는데 RTCP APP 기반 코드가 소스 트리에 남아 있음. 정리 대상.

### 마스터 진행도 불일치
`context/202604/20260421_peer_refactor_done.md` / `20260421_peer_refactor_step_f2_done.md` 존재.
`PROJECT_MASTER.md`의 Peer 재설계 Step F1/F2는 `○` (미완료) 표기.
→ 마스터 업데이트 지연 추정. 부장님이 직접 조정하시는 영역이라 본 세션에서 건드리지 않음.

---
author: kodeholic (powered by Claude)
