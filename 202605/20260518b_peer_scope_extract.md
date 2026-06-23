# 작업 지침 — F30①: peer_scope.rs 신설 (**기각됨**)

> 작성: 2026-05-18 (김대리, claude.ai)
> 기각: 2026-05-18 (부장님 결정)
> 기각 사유: **YAGNI 원칙 위배** — 현재 면적으로는 분리 가치 없음

---

## 기각 사유

부장님 자세 (2026-05-18):
> *"무언가 추가될 때, 분리 작업하자"*

본 작업은 *추상적 분리 작업*. 현재 PeerScope 영역의 면적:
- 자료 2건 (sub_rooms, pub_room)
- primitive 6 메서드
- 내부 위임 2 메서드 (auto-select, cascade)

이 정도 면적으로는 peer.rs 안 잔존이 자연. 분리 시 오히려 *간접 호출 비용* 증가.

분리 트리거 조건 (미래 진입 자리):
- 새 scope primitive 추가 (예: `pub_swap`, `sub_merge` 등)
- 새 자료 추가 (예: `selected_layer`, `priority_room` 등)
- cross-room 모델 확장 (Phase ② Hall 진입 시점)
- peer.rs 안 scope 영역이 ~300줄 초과

→ 위 조건 중 1건 이상 발생 시 본 작업 재진입.

## 원칙 (어제 묶음 7 결정 정합)

YAGNI (You Aren't Gonna Need It):
- 미리 만들어둔 빈 placeholder + TODO = 분류 오류 반복 위험 (묶음 5 분류 오류 정합)
- 진짜 필요한 시점에 자연 발굴 = 진짜 가치

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-18 (기각 처리)*
