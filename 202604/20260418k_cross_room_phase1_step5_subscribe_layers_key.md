# 20260418k — Cross-Room Federation Phase 1 Step 5: subscribe_layers 키 확장

## 목표

설계서 §10.1: `subscribe_layers` 키를 `publisher_id` → **`(publisher_id, room_id)`** 로 확장.

Phase 2 cross-room에서 같은 publisher를 Room 1/2 두 경로로 구독 시
각 경로마다 **독립된 virtual SSRC + simulcast layer 선택**이 필요.
현재 `publisher → virtual_ssrc 1:1` 전제가 깨짐 → tuple key로 분리.

Phase 1 단일방 환경에서는 실질 동작 변화 없음 (room_id는 항상 subscriber의 현재 방).
자료구조 확장이 목적.

## 결과

- **빌드**: `cargo build --release` 4.62s 성공
- **단위 테스트**: `cargo test -p oxsfud --release room::endpoint` → 9/9 통과
  (Step 5는 Participant 필드 테스트 블록 없어 신규 단위 테스트 추가 안 함 — §반성)
- **E2E**: voice_radio + video_radio 2종 정상 (부장님 확인)
- **회귀 없음**: STUN latch / DTLS / SRTP / MBCP Floor / PTT keyframe 대기 / PLI Governor 모두 정상

## 설계 결정

### 1. key 타입: `(String, String)` tuple

```rust
// 기존
subscribe_layers: Mutex<HashMap<String, SubscribeLayerEntry>>
// 신규
subscribe_layers: Mutex<HashMap<(String, String), SubscribeLayerEntry>>
```

- **채택**: tuple of String (native Hash 지원, 변경 범위 최소)
- **기각**: `struct SubscribeKey { publisher_id, room_id }` (이 맥락 전용 타입 과잉)
- **기각**: `RoomId` newtype 전역 도입 (Phase 1 끝에 일괄이 정석)
- **기각**: `HashMap<(Arc<str>, Arc<str>), V>` (기존 `String` 기반 코드 호환성 작업 증가)

### 2. room_id 획득 경로 — 호출처별 원칙

| 호출처 | room_id 출처 | 이유 |
|--------|--------------|------|
| `room_ops/track_ops/helpers` | `room.id.clone()` | 함수 시그니처에 `room: &Arc<Room>` 직접 주어짐 |
| `ingress_subscribe.rs` 3곳 | `room.id.clone()` | `relay_subscribe_rtcp_blocks` / `handle_nack_block`에 room 파라미터 |
| `ingress.rs:fanout_simulcast_video` 2곳 | `room.id.clone()` | 함수에 room 파라미터 |
| `ingress.rs:build_sr_translation` 1곳 | `sender.room_id.clone()` | 함수에 room 파라미터 없음, Phase 1에서 `sender.room_id == target.room_id` 자명 |
| `tasks.rs` 2곳 | `room.id.clone()` | `for room_entry in rooms.rooms.iter()` 순회 맥락 |

**Phase 2 전망**: `build_sr_translation`에 `room: &Arc<Room>` 파라미터 추가 또는 함수 자체가 방별로 호출되게 재설계 필요. **Step 9~10 범위** (SR Translation multi-room).

### 3. `purge_subscribe_layers` — retain 전환

```rust
// 기존: 단일 key remove
layers.remove(leaving_user)

// 신규: tuple key 중 publisher_id가 leaving_user인 것 전부 제거
layers.retain(|(pub_id, _room_id), _| pub_id != leaving_user)
```

Phase 1 단일방에서는 key `(leaving_user, current_room)` 하나만 존재 → 동작 동일. Phase 2 cross-room 대비 코드 정비.

### 4. tasks.rs `for` destructuring

```rust
// 기존
for (pub_id, entry) in layers.iter_mut()
// 신규
for ((pub_id, _room_id), entry) in layers.iter_mut()
```

`upgrades.push((pub_id.clone(), rid))`는 `pub_id`만 쓰므로 하위 로직 변경 없음.

## 작업 내역 (6파일, ~25줄)

| 파일 | 변경 요약 | 호출처 |
|------|----------|--------|
| `room/participant.rs` | 필드 타입 `HashMap<(String,String), SubscribeLayerEntry>` | 정의 1곳 |
| `signaling/handler/helpers.rs` | `purge_subscribe_layers` retain 전환 | 유저 퇴장 cleanup |
| `signaling/handler/track_ops.rs` | `layer_key = (publisher_id, room_id)` 생성 후 entry/get | SUBSCRIBE_LAYER op=51 |
| `transport/udp/ingress_subscribe.rs` | 3곳 tuple key 전환 | RR 역매핑 / PLI Governor / NACK 역매핑 |
| `transport/udp/ingress.rs` | 3곳 tuple key 전환 (★설계에서 누락했던 파일) | Simulcast fan-out 2곳 + SR translation 1곳 |
| `tasks.rs` | 2곳 전환 | STALLED simulcast pause / PLI Governor sweep |

## 기각 사항

### 기각 1: Step 5에서 subscribe_layers를 Endpoint로 이동
- **제안**: 이참에 Participant → Endpoint로 통째 이동
- **기각 이유**: Step 7 (Track 소유권 Endpoint 단일 소유 §10.4) 범위. Step 5는 **key 확장만**에 집중. 경계를 지켜야 Phase 1 각 Step이 독립 검증됨.

### 기각 2: `RoomId` newtype 전역 도입
- **제안**: `struct RoomId(String)` + `Eq/Hash/Display` 구현
- **기각 이유**: Phase 1 끝(Step 10)에 `Participant→RoomMember` 리네임과 함께 일괄 도입이 정석. Step 5에서 하면 변경 범위가 두 배로 증폭.

### 기각 3: tuple 대신 `SubscribeKey` struct
- **제안**: named field로 코드 가독성
- **기각 이유**: 이 맥락 전용 타입. tuple `(publisher_id, room_id)` 의미가 주석 1줄로 충분. struct 생성자/참조자 모두 증폭.

### 기각 4: Arc<str> 전환으로 hot path clone 제거
- **제안**: `(Arc<str>, Arc<str>)` key로 clone이 refcount 증가만
- **기각 이유**: 기존 `String` 기반 코드 호환성 작업이 Step 5 범위를 넘음. Phase 1 완료 후 프로파일링 결과 기반으로 별도 최적화 판단.

### 기각 5: `build_sr_translation`에 room 파라미터 추가
- **제안**: 모든 호출처에서 `room.id` 통일
- **기각 이유**: Step 5 범위 초과. 함수 시그니처 변경 → 호출처 수정 연쇄. Phase 1에서는 `sender.room_id`가 단일 값이라 의미론 안전. Phase 2에서 함수 자체 재설계 (Step 9~10).

## 반성

### 반성 1: ★★★ grep scope 디렉토리 한정 — Step 2 실수 재발

설계 단계 grep에서 **`transport/udp/ingress.rs` (1400줄+)를 통째로 누락**.
`cd` 접근 실패 후 업로드 폴더만 grep → 설계 때 "호출처 8곳 확인"이라고 자신했으나 실제 11곳.

빌드 에러 3건 발생 (ingress.rs:631/719/1421) → 급히 파일 복사해서 추가 수정 → 재빌드 성공.

**2회 실패 예산을 간신히 회피**.

Step 2 세션(20260418h)에서 부장님이 지적한 동일 실수:
> **반성 2건**: grep scope 디렉토리 한정(ingress.rs:1248 누락) / 계획 후 실행 누락(같은 에러 2번)

**동일한 파일에서 동일한 실수 재발.** 지침 내재화 실패. 아래 §지침 후보 1번에 강제 체크리스트 포함.

### 반성 2: 단위 테스트 없음

설계 제시 시점에 "단위 테스트 1개 추가"라고 했으나, `participant.rs`에 `#[cfg(test)]` 블록이 아예 없어 추가 불가 판단. 부장님께 양해 구함.

**올바른 처리**: 설계 시점에 파일에 test 블록 있는지 미리 확인 → 없으면 "Step 7에서 Endpoint로 이동 후 추가"라고 계획 명시. 설계 단계 약속과 구현 단계 실제가 어긋나는 건 신뢰 훼손.

## 오늘의 지침 후보

### 지침 1 ★★★ (강제 체크리스트)

**호출처 추적 리팩터링 전 필수 grep 체크리스트:**

```
□ bash `cd` 성공? (실패 시 업로드 폴더만 grep 금지)
□ 핫패스 파일 수동 포함 — ingress.rs, ingress_subscribe.rs, ingress_mbcp.rs, egress.rs
□ Filesystem:read_text_file로 의심 파일 직접 읽기 (업로드 폴더 grep 보완)
□ 설계서 확정 직전 한 번 더 grep 재확인
```

ingress.rs는 서버의 hot path 핵심 파일인데 **Step 2와 Step 5 두 번이나 놓쳤다**.
특히 Step 2에서 부장님 지적받고도 Step 5에서 재발 → 이 체크리스트를 PROJECT_MASTER에 박아야 할 수준.

### 지침 2

**tuple key로 HashMap 확장 시 destructuring 패턴 정석**:
- `for ((a, b), v) in map.iter_mut()` — iterator 순회
- `layers.entry((k1.clone(), k2.clone()))` — entry 생성
- `layers.retain(|(a, _b), _| predicate)` — 부분 조건 필터
- `layers.get(&(k1.clone(), k2.clone()))` — borrow로 &tuple 생성

Rust에서 tuple은 owned로 key 생성해서 참조로 넘김. clone 2회 alloc 발생하는데 hot path 아니면 무시 가능.

### 지침 3

**`build_sr_translation` 같은 "방 파라미터 없는" 함수의 room_id 획득**:
Phase 1에서는 `sender.room_id` 쓰면 되지만, Phase 2에선 sender가 여러 방에 publish 가능하므로 이 함수 자체가 방별로 호출되게 재설계 필요. **Step 9~10에서 SR Translation multi-room 재설계 때 일괄 처리**.

## 다음 단계

Cross-Room Federation Phase 1 잔여 Step:

| Step | 내용 | 참조 |
|------|------|------|
| 6 | `send_stats` / `stalled_tracker` 키 `(ssrc, room_id)` 확장 | §10.2 |
| 7 | Track 소유권 Endpoint 단일 소유 | §10.4 옵션 A |
| 8 | Participant → RoomMember 리네임 + 역할 축소 | - |
| 9 | `collect_subscribe_tracks` multi-room 순회 + ingress fan-out multi-room 확장 | §4 |
| 10 | 어드민 Endpoint 뷰 + agg-log 정비 + `build_sr_translation` multi-room 재설계 | - |

또는 상용 준비 우선순위:
- Hook System (~2주)
- Moderate 2차 authorize 검은 화면 해결
- Android NetEQ deception (libwebrtc custom build)

## PROJECT_MASTER.md 갱신 — Phase 1 완료 시 일괄 반영 (지금은 보류)

Step 5 반영 항목 (Step 10 완료 시 다른 Step과 함께):

- `### 아키텍처 원칙`에 추가: **subscribe_layers 키 = `(publisher_id, room_id)`** (cross-room에서 같은 publisher를 N개 방으로 구독 시 독립 경로 보장)
- `### 기각된 접근법`에 추가: Step 5 `RoomId` newtype 전역 도입 (Phase 1 끝 일괄), `SubscribeKey` struct (tuple로 충분)

## 커밋 메시지

```
feat(sfud): expand subscribe_layers key to (publisher_id, room_id) (Phase 1 Step 5)

- HashMap<String, SubscribeLayerEntry> → HashMap<(String, String), SubscribeLayerEntry>
- Step 5 per design doc §10.1: Phase 2 cross-room에서 같은 publisher를
  N개 방으로 구독 시 각 방마다 독립된 virtual SSRC + simulcast layer 선택 보장
- Phase 1 단일방 환경에서는 실질 동작 변화 없음 (room_id = subscriber의 현재 방)
- purge_subscribe_layers: remove → retain(|(pub_id, _), _| pub_id != leaving)
- room.id 사용 — 모든 호출처에 room 맥락 확보 (단 build_sr_translation은
  sender.room_id 사용, Phase 2에서 함수 재설계 Step 9~10)
- 6파일 수정: participant.rs, helpers.rs, track_ops.rs,
  ingress_subscribe.rs (3곳), ingress.rs (3곳), tasks.rs (2곳)

Ref: context/design/20260416_cross_room_federation_design.md §10.1
Session: context/202604/20260418k_cross_room_phase1_step5_subscribe_layers_key.md
```

---
*author: kodeholic (powered by Claude)*
