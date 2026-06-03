# 세션 기록 — Track State 식별계층 재설계(서버) + PROJECT_MASTER 3분리 (2026-06-03)

> 김대리(claude.ai) 설계·지침 세션 + 김과장(Claude Code) 구현. 본 파일은 경위 기록 — 상세는 done 보고서들.

---

## 1. Track State 통일 + 식별 계층(track_id/vssrc) 재설계 — 서버 A·B

- **설계 재정초 rev.1→rev.3**: rev.1(역추출·self-unicast)·rev.2(room/ 경로·find_by_vssrc 라우팅) 폐기. **0602e 코드 간극 발견** — 설계서가 ① room/→domain/ ② enum types.rs ③ stats 트랙 직속(0602b~c) ④ **fan-out 방향 역전(0528~0601)** 을 미반영. 코드 전제를 0602e 로 교체해 rev.3 재작성. 설계 사상(track_id 불투명 / track_id·vssrc 논리 Stream 이주 / self-unicast 제거)은 유지.
- **서버 구현**(지침 20260531f rev.3): A 식별 이주(`8b0627a`) + B 발신/통지/응답(`208a498`). 식별 3평면(track_id 불투명·논리 Stream / vssrc 값·복사 / 실 ssrc 물리 Track) 분리. test 204 / oxe2e 4/4.
- **정정 + 회귀 강화**(부장님 적발): do_track_state_req active 통지 track_id 누락(`bf51697`). oxe2e 가 통지 wire 필드 미판정(충실도 경계)이라 못 잡음 → **judge 강화**(`4efaf4a`, evaluate_caching track_id 검증 + 단위테스트 양성/음성). 교훈: 시그널링 wire 필드는 judge 가 통지 페이로드를 직접 단언해야 잡힌다.
- 상세: `20260603_track_state_unification_server_done.md`. 클라(transceiver.mid·setTrackState·TRACK_STATE 수신) = 별 세션.

## 2. PROJECT_MASTER 3파일 분리 + 0602e 현행화

- **배경**: 마스터가 0531 에서 정지, 코드는 0602e — 휘발성 높은 소스구조·아키텍처가 안정 원칙과 한 파일에 섞여 간극 누적(서버 작업자가 stale 마스터 믿고 헛디딤).
- **Phase A 분리(이동)**: `PROJECT_SERVER.md`(서버 코드 종속) + `PROJECT_WEB.md`(웹클라 종속) 신규. 마스터는 코드 비종속 원칙·계약만. 헤더 단위 분할(verbatim) — 원본 21섹션 손실 0(프로그램 검증). commit `9a2ec84`.
- **Phase B~D 현행화**: SERVER 0602e 반영(domain/ 트리·fan-out 방향역전·stats 트랙직속·scope HashSet) + track_state 식별계층(Phase C) + 마스터 슬림화(Phase D, 현재상태 단일출처 202606 + 마일스톤 0602b~e·track_state). commit `071cef5`.
- **발견_사항 채택**: ③ engine.scope.* SDK API subsection SERVER→WEB 이전(자료구조는 SERVER). ① Telemetry 체계(common/server/hub/web 혼재) + ② SDK 코어(Android 휴면) = 마스터 잔류.
- 지침: `claudecode/202606/20260603_doc_split.md`.

---

## 3. 핵심 학습

- **설계서는 코드 전제와 함께 늙는다** — rev.2 가 0602e 4대 변화(domain rename·types·stats·방향역전)를 못 따라가 재정초. 문서-코드 간극이 누적되면 작업자가 헛디딘다 → 마스터 3분리로 휘발성 격리.
- **회귀의 충실도 경계** — oxe2e 봇은 라우팅/active-flag 만 판정, 통지 wire 필드(track_id) 미검증. 그 사각이 active 통지 track_id 누락을 통과시킴 → judge 가 통지 페이로드를 직접 단언하도록 강화.
- **문서 분리는 섹션 증발 위험** — 수기 전사 대신 헤더 단위 분할 + verbatim 보존 검증(손실 0). 분류 모호분(Telemetry/Android/scope SDK API)은 임의 판단 말고 발견_사항 보고 → 부장님 결정.

---

*author: kodeholic (powered by Claude)*
