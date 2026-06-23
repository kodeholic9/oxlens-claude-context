# 아키텍처 문서 작성 — 작업 가이드 (다음 세션 이어받기용)

> 이 폴더(`context/architecture/`)의 문서를 **사람(부장님)이 읽도록** 채워가는 작업의 진행 상태/순서/원칙. 다음 세션은 이 파일부터 읽고 이어간다.
> SESSION_INDEX 와 별개 — 이건 *이 작업 묶음 전용* 가이드.

## 장 구성 (2026-05-31 재배치 완료)

| 장 | 파일 | 상태 |
|----|------|------|
| 0. Overview (지도) | `20260531_sfu_overview.md` | 본문 완성 |
| 1. Signaling & Lifecycle | `20260531_signaling_lifecycle.md` | **골격 (미착수)** |
| 2. 상태 자료구조 (Ownership & Lifecycle) | `20260531_state_ownership.md` | 본문 완성 (§0~§G, ASCII 다이어그램 일부 자리만 남음) |
| 3. Media Pipeline | `20260531_media_pipeline.md` | **본문 완성 (3.1~3.10, 불변식 13 + 기각 10)** |
| 4. PTT & Floor | `20260531_ptt_floor.md` | **골격 (미착수)** |
| 5. Scope & Cross-Room | `20260531_scope_crossroom.md` | **골격 (미착수)** |

## 지금까지 (2026-05-31)
- overview 지도 + 2장(§0~§G) + 3장(3.1~3.10) 본문 완성. 번호 재배치(Media/PTT/Scope=3/4/5).
- 3장 절: 3.1 ingress / 3.2 분류권위(TrackType) / 3.3 fanout / 3.4 forward / 3.5 RTCP Terminator / 3.6 SR Translation / 3.7 PLI Governor / 3.8 SubscriberGate / 3.9 Simulcast / 3.10 NACK·RTX. 전부 그림+왜+불변식.

## 코드-마스터 괴리 (별 토픽)
- [해소] 최상위 = **AppState**(state.rs). `rooms:Arc<RoomHub>` + `endpoints:Arc<PeerMap>`(필드명 endpoints=PeerMap 함정). §0/§A 반영.
- [지침 발행, 김과장 대기] ①② → `20260531e_publisher_2layer_doc_sync.md`. 2계층 배선 완료 반영(publisher_stream.rs dead_code/Stage 주석 + publisher_track.rs Vec/방향역전 주석 + 마스터 마일스톤 1줄(부장님 GO 후)).

## 작성 원칙 (마스터와 정반대 — 사람이 읽는 문서)
1. **그림 먼저** — ASCII 박스/화살표를 텍스트보다 앞에.
2. **왜를 남긴다** — 선택 이유 + 기각한 대안.
3. **불변식을 박는다** — 각 장 끝 "불변식 / 기각한 대안" 두 자리.
4. **코드 라인 번호 금지** — 함수명/타입명/필드명까지만.
5. **갱신 = 새 일자 복사** — overview 상단 표만 고친다.
6. **디테일이 곧 디버깅 지도** — 생성/참조/소멸 시점 + 동시성 타입(왜) + 상태 전이.

## 채우는 순서 (추천)
- [x] 2장 §0~§G + AppState
- [x] 3장 3.1~3.10 전체
- [ ] **4장 PTT & Floor** — 4.1 트랙속성 / 4.2 slot / 4.3 PttRewriter / 4.4 Floor / 4.5 MBCP / 4.6 Freeze Masking / 4.7 Duplex 전환. (3.2~3.6 이 토대)
- [ ] **5장 Scope & Cross-Room** — 5.1~5.6. (2장 §C/§A SubscriberIndex 가 토대)
- [ ] **1장 Signaling & Lifecycle** — wire v3 / JOIN→READY / Phase / take-over.
- [ ] 2장 ASCII 다이어그램 자리 보강(§B/§C/§G 그림).

## 한 절 채울 때 절차
1. 코드(타입/함수/필드) 현물 확인 (라인 아닌 구조).
2. 그림(ASCII) 먼저.
3. "왜 / 기각한 대안" 을 절 + 장 끝에.
4. 코드와 어긋나면 코드가 진실 → 문서를 맞추고 마스터 현행화는 별 토픽.

## 주의
- 이 작업은 **김대리(claude.ai)가 부장님과 같이** 채운다(설계 문서). 김과장 기계 치환 대상 아님.
- 마스터/소스 실수정은 김대리 직접 X — 마스터는 제안+승인, 소스(.rs)는 김과장 지침.

---

*author: kodeholic (powered by Claude)*
