# 20260416b 0416a 범위 반영 확인 + DC 채널 멀티플렉싱 Phase 1 결정

> author: kodeholic (powered by Claude)
> date: 2026-04-16
> area: 서버 + 웹 클라이언트 + 설계

---

## 요약

세션 인덱스 0416a 범위(PTT virtual track remove 보호, MBCP 큐 갱신, Granted duration, sub_mid_map, DC 확장 설계 등) 실 코드 반영 상태 점검. ★ 2건 포함 대부분 이미 반영됨 확인. **큐 갱신 미동작은 서버 빌드 문제(부장님 해결)**. 남은 작업은 DC 채널 멀티플렉싱 설계 문서의 Phase 1 결정 5건 확정 — 설계서 §13/§14 append 완료.

---

## 반영 상태 점검 결과

| # | 항목 | 상태 | 비고 |
|---|------|------|------|
| 1 | ★ PTT virtual track remove 보호 | ✅ 이미 반영 | `room_ops.rs:handle_room_leave`, `tasks.rs:run_zombie_reaper` 양쪽 다 `ptt:virtual_remove_skipped` agg-log 포함 |
| 2 | ★ MBCP 큐 갱신 (QueueUpdated 6곳) | ✅ 코드 완료 | 콘솔 로그 미동작은 서버 빌드 문제 → 해결됨. 현장 재검증 필요 |
| 3 | Granted duration (FIELD_DURATION=9) | ✅ 이미 반영 | `mbcp_native.rs`, `mbcp.js`, `floor-fsm.js` 전부 duration 경로 |
| 4 | sub_mid_map 스냅샷 | ✅ 이미 반영 | `admin.rs` participant에 `sub_mid_map: [{track_id, mid, kind}, ...]` |
| 5 | DC 채널 확장 설계 | ✅ 본 세션에서 §13/§14 append | Phase 1 결정 5건 확정 |
| 6 | 상용 DC 패턴 조사 (LiveKit/mediasoup) | 🟡 설계서 §9, §10에 반영 | 별도 문서 불필요 — 기각 사항과 복구 패턴으로 흡수 |
| 7 | 세션 타임라인 텔레메트리 설계 | ⏸️ 다음 세션 | 본 범위 밖 |

---

## DC Phase 1 결정사항 (설계서 §13)

| Q | 결정 |
|---|------|
| D1 | DC label `"unreliable"` 원샷 교체 + 미지 label warn agg-log |
| D2 | `dc_tx` → `dc_unreliable_tx` rename, reliable은 Phase 2 |
| D3 | event_bus binary 경로는 Phase 3 진입 시 재논의 |
| D4 | svc별 메트릭: 표준(mbcp/speakers) 고정 + `_app`/`_unknown` 버킷 |
| D5 | DC readiness 버퍼링 Phase 1 포함 (per-participant VecDeque, MAX=64) |

Phase 1 작업 목록은 설계서 §14 참조.

---

## 학습 / 김대리 반성

- **search_files 도구 오해로 2회 오판** — "파일명 검색 전용"인 도구를 "본문 검색"으로 착각. `virtual_remove_skipped`, `sub_mid_map` 모두 "미반영"으로 보고했으나 실제로는 전부 이미 반영됨.
- **교정된 규칙**: 반영 여부 판단은 반드시 `read_text_file`로 본문 확인. `search_files`는 파일명 찾을 때만 사용.
- **원칙 재확인**: "자기 코드 → 선례 → 코딩" 중 "자기 코드"를 얄팍하게 훑어서 생긴 오판. 본문을 끝까지 보는 비용이 재질문/오판 비용보다 싸다.

---

## 이번 세션 기각 후보

| 후보 | 이유 |
|------|------|
| DC label 병행 수용 (구 "mbcp" + 신 "unreliable") | 상용 전 단계. 병행 코드는 잊히면 영구 잔존 |
| `Participant`에 Phase 2용 `dc_reliable_tx` 미리 선언 | 죽은 필드 금지 원칙. Phase 2 증분이 작음 |
| `WsBroadcast` Phase 1에 binary 필드 미리 추가 | Phase 1/2는 event_bus 미경유. Phase 3에서 요구사항 구체화된 뒤 설계 |
| svc별 `LabeledCounter<K>` 런타임 label 도입 | svc 2개(Phase 1), 4개(Phase 2)에 대한 프레임워크 변경은 과잉 |
| DC readiness 버퍼링 Phase 2 지연 | Active Speakers를 DC로 돌리는 순간 신규 참가자가 open 전 이벤트 누락 — Phase 1에서 필수 |
| 상용 DC 패턴 조사를 별도 문서로 분리 | 설계서 §9/§10에 기각 사항 + 복구 전략으로 이미 흡수됨 |

---

## 이번 세션 지침 후보

- **도구 특성 확인**: `search_files` = 파일명 전용. 본문 검색은 `read_text_file` + 필요시 `bash grep`. 도구 설명 문구 한 번 더 확인.
- **"미반영"이라는 진단은 본문 근거 필요**: 네거티브 결과(반영 안 됨)를 주장하려면 반드시 관련 소스 전체 열람 근거 필요. 함수명/식별자만으로 단정 금지.
- **설계 결정의 단위 = Phase**: Phase 1 결정점은 Phase 1만 구속. Phase 3 결정은 Phase 1/2 실 사용 데이터 누적 후.
- **죽은 필드 금지**: "미리 준비"는 허상. 추가 시점에 증분으로 추가.

---

## PENDING

- [ ] MBCP 큐 갱신 현장 재검증 (3인 이상 큐, 부장님 재빌드 서버 기준 → U742 position=1 로그 찍히는지)
- [ ] DC Phase 1 코딩 (다음 세션) — 설계서 §14 작업 목록 전부
- [ ] DC Phase 2 (reliable 채널 + Chat/State Sync)
- [ ] DC Phase 3 (WS binary fallback + event_bus binary 확장 + gRPC oneof)
- [ ] 세션 타임라인 텔레메트리 설계 (별도 세션)

---

## 변경 파일

### 설계 문서 (1)
- `context/design/20260416_dc_channel_multiplex_design.md` — §13/§14 append (D1~D5 + Phase 1 작업 목록)

### 코드 변경
- 없음 (본 세션은 상태 점검 + 설계 확정만)

---

*author: kodeholic (powered by Claude)*
