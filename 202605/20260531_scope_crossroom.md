# 5. Scope & Cross-Room

> 사람이 읽는 문서. 그림 먼저, 왜를 남긴다. → 지도는 `20260531_sfu_overview.md`. 자료구조 토대는 `20260531_state_ownership.md`(2장).
> **[골격]** 목차만 잡힘. 본문은 세션별로 한 절씩.

한 사람이 N개 방을 듣고(sub) 1개 방에 말하는(pub) 모델. MCPTT affiliated/selected 정합.

---

## 5.1 모델 — N방 청취 + 1방 발언
- [본문 TODO] `joined_rooms`(입장) / `sub_rooms`(받을 방, N) / `pub_room`(보낼 방, 1, 단수 강제). 왜 pub 은 단수인가(1방 발언). `pub_room ⊆ sub_rooms` 자명.
- [다이어그램 자리] 한 Peer 의 joined/sub/pub 관계.

## 5.2 Scope 는 타입으로 표현
- [본문 TODO] user-scope=`Peer`, PC pair-scope=`PublishContext`/`SubscribeContext`, room-scope=`RoomMember`. **필드 위치가 의미를 말하게** — 주석/네이밍 의존 금지. 이게 "peer 재설계"의 핵심(계층 부재 → 평탄 흩어짐을 타입 계층으로 해소). *(소유 트리 전모는 2장.)*

## 5.3 Primitive — join/affiliate/auto-select
- [본문 TODO] join(R)→sub+={R}, pub=R(없으면 auto-select). leave(R)→auto-deselect. SCOPE(0x1200)는 sub_rooms 전용(pub 안 건드림). cascade.
- [다이어그램 자리]

## 5.4 SubscriberIndex — fan-out O(1)
- [본문 TODO] `by_room_subscriber: DashMap<RoomId, DashMap<user_id, Arc<Peer>>>`. fan-out 핫패스에서 방 순회 없이 user 단위 조회. floor 전달도 이 인덱스.

## 5.5 Server-authoritative
- [본문 TODO] SDK 낙관적 업데이트 금지. affiliate() 는 전송만, 상태는 서버 응답(SCOPE ok / SCOPE_EVENT)으로만 갱신. partial success 경로 대응. set_id 세션 수명 불변(reconnect shadow 호환).

## 5.6 Floor / STALLED / Admin 의 scope 정합
- [본문 TODO] FLOOR_TAKEN user 단위(SubscriberIndex). floor 판정 방별 독립. STALLED checker user 단위. admin 축 분리(방 뷰 + User 뷰).

---

## 불변식
> [TODO] 방/트랙은 scope 모른다(Peer/SubscriberIndex/floor 전달/admin User 뷰에만) / Server-authoritative(낙관적 업데이트 금지) / set_id 세션 수명 불변 / 외부 접근은 `peer.publish_room()` 단일 진입.

## 기각한 대안
> [TODO] Ghost Participant / Origin 축 / Peer enum Local·Remote(→ room→SFU 매핑이면 충분) / Cross-SFU 2단계 로드맵(→ 단일 Phase) / flat scope API(→ engine.scope.*) / Hub scope_coordinator 집계 레이어(→ 방별 독립이라 불필요) / cross-room publish(→ 1방 발언으로 폐기) 등.

## 보류 (먼 미래 — 지금 설계 금지)
> [TODO] Cross-SFU(SFU-SFU relay) — 측정 전 분기 금지, 분리 가능하니 순차. Phase ② Hall.

---

*author: kodeholic (powered by Claude)*
