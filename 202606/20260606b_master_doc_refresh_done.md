// author: kodeholic (powered by Claude)
# 완료보고 20260606b — 마스터 문서 현행화 (PROJECT_WEB / MASTER / SERVER)
> 작업 지침 ← [20260606b_master_doc_refresh](../claudecode/202606/20260606b_master_doc_refresh.md)

> 지침: `claudecode/202606/20260606b_master_doc_refresh.md`. 문서만, 코드 0. 창작 금지(명시 source 대조).

---

## 결론

라이브 master 3종(`context/PROJECT_{WEB,MASTER,SERVER}.md`) 현행화 완료. 매 세션 core/ 함정의 원흉(stale 웹 구조) + 시그널링 drift(42op/0x1304/0x2500) + 서버 미반영(cross-sfu/supervisor/client_event) 청산. 전부 이번 세션 직접 정독 실증(sdk/ 실트리 + 헤더 주석 + oxhubd/oxsfud 실트리 + state.rs/grpc 실측 + done 0603e~n).

---

## Phase A — PROJECT_WEB.md (전면)

- **제목/intro**: "Core SDK v2" → "신 SDK = sdk/". 활성=sdk/, core/=레거시 명기.
- **구조 트리**: core/ 평탄본(구) → **sdk/ 실트리 전면 교체**(directory_tree 실측). 각 파일 1줄 = **헤더 주석 대조 확정**(창작 0). `[scaffold]` 표기(op-registry/negotiator/dc-channel/device-manager/plugins·/scope = 골격). demo/ = 6시나리오+admin(현 core/ 의존).
- **아키텍처**: "Core SDK v2 (Engine→Room→Endpoint→Pipe)" → **6 평면 + 3 확장 훅**(design 20260603 §2): 코어설비/관측(단방향)/제어(WS1개)/미디어(TransportSet→Transport sfu별N)/장치/논리축. 핵심 판단 갱신(PC=Transport 소유, _renegotiateSfu 합집합, 관측 단방향 철칙, collectStats). freeze masking·프리셋·Scope API = 유지(경로 정합).
- **권위 링크**: design 20260603 `_core_design` + `_knowledge` 짝(둘 다 존재 확인).
- **core/ 표기**: demo/ 가 core/ import 中 실증 → "레거시·제거 예정"(삭제 단정 금지, §0 준수).

## Phase B — PROJECT_MASTER.md

- **시그널링**: 총 "42 op"→"43 op"(실측 1곳 — 지침 "2곳"은 drift, 실측 우선). 0x1303 ANNOTATE 아래 **0x1304 CLIENT_EVENT 행 추가**. 0x2500 ACTIVE_SPEAKERS "ACK 없음 — 빈도 높음" → "Event=ACK 대칭(windowed)"(147 정합).
- **프로젝트 구성 표**: 웹클라 행 "Core SDK v2 + demo" → "활성 SDK = sdk/(전면 재작성, 설계 20260603). core/ 레거시". + 문서 인덱스 PROJECT_WEB 설명 정합.
- **포인터 헤더**(line 60/66): "Core SDK v2" 잔재 → "신 SDK = sdk/" / "6 평면 + 3 확장 훅"(포인터라 무위험, 현행화 취지 — 3 명시항 외 추가 정합).
- **행동 원칙 7항 신설**: 보고 종결 = 4-라벨 단일 ask([결재]/[택1]/[질문]/[보고], 바운스 금지).

## Phase C — PROJECT_SERVER.md (분량 큼)

- **C-0 헤더**: "0602e(Phase B 진행)" → "0606a (cross-sfu Phase 0~2b + supervisor + CLIENT_EVENT 반영)".
- **C-1 oxhubd 구조**: state.rs **cross-sfu registry**(sfu_registry DashMap + room_sfu 1:1 + RoundRobin + place/assign/sfu_for_room/bind_room) / grpc "1개"→**per-node registry**(SfuNode 별 client lazy reconnect) / **supervisor/ 8파일**(backoff/component/mod/ready/spec/stop/unit/tests) / rest **supervisor.rs·health.rs** / **track_dump/mod.rs**. ws/mod.rs ROOM_CREATE·sfu_for_room·ROOM_LIST fan-out 주석.
- **C-2 oxsfud**: handler "8파일"→"9파일" + **client_event.rs 행**(CLIENT_EVENT→agg-log, 146).
- **C-3 신규 섹션 "Cross-SFU (Phase 0~2b)"**: room→sfu 1:1, RoundRobin place_room, ROOM_CREATE bind(멱등), sfu_for_room 라우팅, ROOM_LIST fan-out, user 단위 경계 관통 없음. Source done 0603j~n 명기(substance 단일출처).
- **C-4 신규 섹션 "Supervisor (oxhubd, POSIX)"**: spec/기동+ready/backoff 재기동(intensity 가드)/stop(graceful)/observability. Source done 0603e~i 명기.
- **C-5 준수**: C-3/C-4 substance = scope/위치 + done source 만(창작 0). 실측 1차 확인분(state.rs registry, ws/mod.rs 라우팅)만 사실 기재.

---

## 검증 (잔여 stale grep)

- "Core SDK v2" 잔여 = **0** (3파일).
- "42 op / 총 42" = **0**.
- ACTIVE_SPEAKERS "ACK 없음 — 빈도" = **0**(MASTER).
- 0x1304/CLIENT_EVENT = WEB/MASTER/SERVER **3파일 전부 반영**.
- 코드/동작 변경 = **0**(문서 3파일만).

---

## 발견_사항

- **지침 "42 op 2곳" = 실측 1곳**: MASTER 의 op 총수 언급은 line 94 한 곳뿐. §9 "drift 시 실측 우선"대로 1곳 정정.
- **MASTER 포인터 헤더 2개**(웹 구조/아키텍처 → PROJECT_WEB 이동 stub)도 "Core SDK v2" 잔재라 같이 정합(3 명시항 외, 무위험 포인터).
- **demo/ 는 여전히 core/ import**(sdk/ 미사용) — core/ 삭제 단정 불가 확정. 0605c demo 실배선 후 제거 가능.

---

## ★ 부장님 조치 필요

**claude.ai 프로젝트 지식 mirror(`/mnt/project/`) 재업로드** — 갱신된 PROJECT_{WEB,MASTER,SERVER}.md 3종. 안 하면 다음 세션 ME 가 옛본 보고 core/ 함정 재발(본 작업 무효화).

---

## 커밋 구조

지침 §2.4/§8: **A+B 한 커밋 + C 별 커밋**(C 분량 큼). context 레포 단독(코드 0).

---

*author: kodeholic (powered by Claude)*
