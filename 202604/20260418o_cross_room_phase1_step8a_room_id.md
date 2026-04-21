# 20260418o: Cross-Room Phase 1 Step 8a — RoomId newtype

## 목표
설계서 §10.1 §10.2 "subscribe_layers / send_stats / stalled_tracker 튜플 키의
room_id 부분을 String에서 RoomId로 타입화" — 지점 그림에 타입 명시.

## 변경 내역

### 신규 파일
- `crates/oxsfud/src/room/room_id.rs`
  - `pub struct RoomId(String)` + 5 단위 테스트
  - trait: `Borrow<str>` / `Deref<Target=str>` / `AsRef<str>` / `Display`
  - `From<String>`, `From<&str>`, `From<&String>`
  - `Serialize` + `Deserialize` + `#[serde(transparent)]`

### 필드 타입 전환 (8 파일)
| 파일 | 항목 |
|---|---|
| `room/mod.rs` | `pub mod room_id;` 추가 |
| `room/participant.rs` | `room_id`, send_stats/subscribe_layers/stalled_tracker 튜플 키 |
| `room/endpoint.rs` | `rooms: HashSet<RoomId>`, `active_floor_room: Option<RoomId>` |
| `room/room.rs` | `Room.id`, `RoomHub.rooms`, `ReaperResult/ZombieInfo` |
| `signaling/handler/room_ops.rs` | `Participant::new` 호출 시 `.into()` |
| `signaling/handler/track_ops.rs` | layer_key `(String, RoomId)` 튜플 생성 |
| `transport/udp/ingress_subscribe.rs` | tuple key 조회, WsBroadcast.room_id `.to_string()` |
| `signaling/handler/helpers.rs`, `transport/udp/ingress.rs`, `transport/udp/mod.rs`, `room/floor_broadcast.rs` | `.to_string()` 변환 |
| `startup.rs` | `create_with_id(RoomId::from(id.to_string()), ...)` |

### 호출처 cascade 최소화 판단
- **Borrow<str>**: `DashMap<RoomId, _>.get("room-1")` 같이 String 할당 없이 조회 — hot path 영향 0
- **Deref<Target=str>**: newtype에 일반적으로 안티패턴이나 `Option<RoomId>::as_deref()` 25+ 호출처 cascade 차단 효과. `str`는 손상성 높은 타입이라 부작용 위험 낮음
- **`#[serde(transparent)]`**: JSON은 `"room_id": "abc123"` String 표현 유지 — hub/어드민/SDK 클라이언트 프로토콜 변경 0

## 테스트
- 신규: `room::room_id::tests` 5건 — Borrow/HashSet/Display/conversions/tuple key
- 수정: `endpoint::tests::floor_cross_room_rejected` — Err 비교 `.as_str()` 추가
- `cargo test -p oxsfud --release`: **114 passed / 0 failed**
- doctest: endpoint.rs 개념 다이어그램 코드 펜스에 `text` 힌트 추가

## 오늘의 기각 후보
- **RoomId에 Deref 붙이기**: newtype에 Deref는 안티패턴이라 거부 — 
  본 프로젝트는 호출처 cascade 차단 효과가 크고 Target=str는 손상성 강한 타입이므로 예외적 채택

## 오늘의 지침 후보
- **newtype 도입 시 `#[cfg(test)]` 내부까지 grep 필수** — 
  `try_claim_floor` Err 타입 변경 시 테스트 `assert_eq!(other, "r1")` 깨짐
- **doc-test 코드 펜스에 언어 힌트 명시** — 
  한국어/의사코드가 포함된 ``` 블록은 `text`/`ignore` 명시, 안 하면 rustdoc이 Rust 파싱 시도 → 실패
- **newtype에 Deref<Target=str> 판단 기준**: 
  (1) 호출처 cascade 효과가 크고 (2) Target 타입이 str처럼 손상성 강할 때만 채택. 일반 T에는 금지.

## 다음 (Step 8b)
**Participant → RoomMember rename** — 기계적 치환
- `pub struct Participant` → `pub struct RoomMember`
- `Arc<Participant>` / `&Participant` / `use ...::Participant` 전역 치환
- 유지: 파일명 `participant.rs`, 메서드명 `add_participant`/`get_participant`, 변수명 `p`/`participant`/`pub_p`/`sub_p`, enum `ParticipantPhase`, 주석/로그 내 "participant" 단어

---
author: kodeholic (powered by Claude)