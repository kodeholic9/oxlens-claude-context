// author: kodeholic (powered by Claude)

# 2026-04-19 (b) — Cross-Room 설계 문서 relay 전제 오류 수정 완료 확인

**저장 위치**: `context/202604/20260419b_cross_room_doc_relay_error_fix.md`
**연관 설계 문서**: `context/design/20260416_cross_room_federation_design.md` (rev.2)

---

## 세션 배경

- Cross-Room Federation 설계의 핵심 오류("클라이언트 직접 연결"을 기각하고 cascading relay를 기본 구조로 채택)가 이전 세션에서 발견됨
- 제3자(Gemini) 검증에서 relay 기반 전제로 피드백 → 설계서 자체 오류 확인
- 3개 파일 수정 작업이 이전 세션에서 진행 완료됐으나, 검증 보고 직전에 세션 종료
- 본 세션에서 수정 완료 확인 + 코드 영향 점검 + 변경 내용 문서화

---

## 오류 원인 (재확인)

1. 부장님 원안: "진행자가 분리된 장비에 직접 pub으로 참여" + "서버 3~5대에 방 20개 분산"
2. 김대리: "방 20개 = 서버 20대"로 오인 → "브라우저 PC 20쌍 불가" 잘못 반박
3. cascading relay(type:relay participant)를 기본 구조로 설계 → 부장님 원안 왜곡
4. rev.1 수정 시 기각 4("클라이언트 직접 연결 기각") 잔존 → 정합성 깨진 채 구현 진행

---

## 코드 영향 점검 결과

**코드 영향: 제로.**

- `oxlens-sfu-server`에 relay 관련 파일/코드 없음 (search 확인)
- Phase 1 구현(Step 1~10 + followup)은 전부 Endpoint/RoomMember 분리 + 같은 sfud 안 cross-room
- relay 설계 오류는 문서에만 존재, 코드로 유입되지 않음

---

## 수정된 3개 파일 변경 내역

### 파일 1: 설계 문서 (`context/design/20260416_cross_room_federation_design.md`)

rev.1 → rev.2 전면 수정:

| 위치 | 변경 전 | 변경 후 |
|------|---------|---------|
| 헤더 | Phase 1~3 | Phase 1~2, rev.2 표기 |
| §1 비교 테이블 | "relay 연결 수: 서버 수 비례" | "서버 간 연결: 클라이언트 직접 연결", sfud 변경 제로 행 추가 |
| §2 | (없음) | **신설** — 기본 구조: 클라이언트 직접 연결 + Level 1 |
| §4 제약 | (없음) | 서버 간 연결 행 추가, cross-server floor 주의사항, sfud별 Endpoint 분리 표기 |
| §5 구현 | (없음) | 클라이언트 Engine 변경안 (connections Map) 추가 |
| §6 로드맵 (구§5) | 3-Phase (relay/orchestration) | 2-Phase (multi-server 직접 연결), relay→미래 확장 옵션 |
| §7 시나리오1 (구§6) | relay 경유 | 직접 연결 기반 |
| §7 시나리오2 (구§6) | sfud간 relay 경유 | 직접 연결 + cross-server grant 미결 유보 |
| §8 기각4 (구§7) | "클라이언트 직접 연결" 기각 | **"cascading relay 기본 채택"** 기각 |
| §9 미결 (구§8) | relay 인증, origin failover | cross-server floor 중재, grant 전달, PC 실측 |
| §10 핵심 요약 (구§9) | type:relay 언급 | relay 제거, 직접 연결 명시 |
| §11 (구§10) | Addendum 번호만 | 번호 조정, 내용 불변 |
| 부록 | (없음) | **신설** — 오류 정정 이력 (원인/수정범위/코드영향) |

### 파일 2: 세션 기록 (`context/202604/20260416a_cross_room_federation.md`)

| 위치 | 변경 전 | 변경 후 |
|------|---------|---------|
| 배경 | "장비 3~5대" | **볼드 강조** |
| §3~6 논의 흐름 | "직접 연결 기각 → relay 도출 → Phase 1이 relay를 빛나게" | §3 부장님 원안(직접 연결), §4 김대리 오류(relay 끼워넣기, 원인 분석), §5~8 유지(번호 재배정) |
| 확정된 결정 | (없음) | 기본 구조=직접 연결, relay 불필요 행 추가, Endpoint 네이밍 반영 |
| 로드맵 | 3-Phase relay | 2-Phase + Phase 1 ✅ |
| 기각 | 직접 연결 기각 | cascading relay 기본 채택 기각 |
| 지침 | (없음) | "부장님 의도 확인 우선", "업계 지식이 틀", "기각 정합성 검수" 3개 추가 |
| 액션 | (없음) | "PC 3~5쌍 실측" 추가 |

### 파일 3: followup (`context/202604/20260419_cross_room_phase1_followup.md`)

| 위치 | 변경 전 | 변경 후 |
|------|---------|---------|
| Phase 2 (보류) 1줄 | "type:relay 다중 SFU 인스턴스. Zoom 급 스케일 시." | "클라이언트 multi-server 직접 연결 (서버 3~5대, PC 3~5쌍) + hub orchestration. Lifecycle Redesign 실측 완료 후 착수 판단. type:relay는 서버 수십~수백 대 규모에서만 필요한 미래 확장 옵션." |

---

## 오늘의 기각 후보

- (본 세션은 문서 검증/수정 세션이라 신규 기각 없음)

---

## 오늘의 지침 후보

- 📌 **설계 문서 수정 후 전량 교차 검증** — 기각 사항 ↔ 기본 구조 정합성, 시나리오 ↔ 로드맵 정합성을 체크리스트로 확인
- 📌 **rev 번호를 문서 헤더에 명시** — 어떤 버전이 배포되었는지 추적 가능해야 함
- 📌 **코드와 문서의 영향 범위를 분리 점검** — 문서 오류가 코드에 유입됐는지를 별도 확인 (이번에는 코드 영향 제로였지만 항상 그런 건 아님)

---

## 다음 세션 액션

- [ ] 시나리오 테스트 검증 (conference, voice_radio, dispatch, moderate — 이전 세션 이월)
- [ ] Moderate 2nd-authorize black screen fix (track_ops.rs 서버측)
- [ ] SDK Lifecycle Redesign 기반 PC 3~5쌍 동시 운영 PoC 실측
- [ ] Cross-Room Phase 2 시그널링 층 확장 설계 (서버 room_ops.rs + hub state.rs + SDK engine.js)

---

*author: kodeholic (powered by Claude)*
