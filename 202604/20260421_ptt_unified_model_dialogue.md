# PTT Unified Model — 설계 대화 기록

> author: kodeholic (powered by Claude)
> date: 2026-04-21
> 설계 문서: `context/design/20260421_ptt_unified_model_design.md`

---

## 출발점

부장님 한 문장: "무전 수신 채널은 방에 디폴트로 갖고 시작하는거 어때?"

- Subscribe SDP 재협상 부담 해소 의도
- PTT slot 2개(audio/video recvonly) 를 방 기본 인프라로 승격

## 사고 전개

부장님의 단계적 수렴 — 제거 우선 편집 패턴:

1. **수신 slot 디폴트** (Subscribe PC 관점, Pub 현행 유지)
2. **모든 방/서버 universal 고정 SSRC** (결정론적 해시보다 과감)
3. **다방 동시 발언은?** "1번방 발언자는?" — 엣지 케이스 자가 발굴
4. **All-or-Nothing + 긴급발언** — 규칙 2개로 복잡도 소거
5. **MCPTT 는 구조적으로 불가능** — 규격 비판 기반 차별화
6. **Cross-SFU 확장** — priority 도메인 정의, SFU 는 숫자 비교만

## 도출된 Axiom 3개

1. **All-or-Nothing atomic grant** — multi-destination 동시 요청, 하나라도 busy 면 전체 NACK
2. **Subscribe PC 당 1 stream 불변식** — universal SSRC 안전성 보장, mixing 불필요
3. **Priority override** — 도메인 정의 priority, SFU 는 u8 비교만

## 파생 기능 (코드 추가 최소로 성립)

- Listen filter (채널 스캔)
- Multi-room speak (다방 발언)
- Whisper (1:1 귓속말)
- 긴급발언 (기존 구현 재사용)
- Cross-SFU priority federation
- 지휘 브로드캐스트

## MCPTT 차별점

MCPTT 가 IMS/SIP 제약으로 우회(mixing, Group Regroup, Broadcast Group)한 요구를 SFU 원리로 직선 해결. "PTT 1급 시민" 포지션의 실체.

## 구현 타임라인

- Phase 1 (Peer F 완료 직후): 단일 SFU slot + universal SSRC + atomic grant
- Phase 2: Listen filter + Multi-destination + Whisper
- Phase 3 (2027~): Cross-SFU federation + 2PC coordinator

## 오늘의 기각 후보

- room_id 해시 기반 결정론적 SSRC → universal 고정으로 단순화
- Publish slot pre-allocate → simulcast/codec 다양성으로 의미 축소
- 부분 grant (일부 방만 획득) → Axiom 1 all-or-nothing 로 단순화
- Subscribe active stream 런타임 선점 규칙 → Axiom 1 이 원천 차단
- Moderate 와의 통합 → 별개 도메인, 경계 명시

## 오늘의 지침 후보

- **"규격을 결과물이 아닌 타협물로 읽는다"** — MCPTT 를 권위가 아니라 IMS 제약 속 타협 아키텍처로 독해. 규격 밖 경험으로 규격 밖 해법 가능.
- **"제약을 인프라로 승격"** — single-speaker 불변식을 코드 제약이 아닌 SDP 레벨 공리로 박으면 전체 구조 단순화.
- **"Axiom 기반 설계"** — 공리 3개로 기능 6+개 파생. 재료 재활용이 설계 응축의 실체.
- **"AI 확장 vs 부장님 축약"** — 이 대화 내내 드러난 패턴. AI 는 일반해/확장 편향, 축약은 도메인 경험자만 가능.

## 참고

- 설계 대화 도중 파생 논의: 이전 회사 PTT 이력 + 현 회사 겸직 / 사업 프로그램 도전 — 기술 외 영역은 부장님 결단 사항으로 분리
- OxLens 착수 2026-03-03, 본 설계는 7주차 대화에서 도출

---

*다음 액션: Peer 재설계 Step F3 완료 → Phase 1 구현 설계서 상세화 → 구현*
