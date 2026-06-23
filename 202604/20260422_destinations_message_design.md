# Destinations Message Design — FLOOR_REQUEST 발화권 요청 메시지 재설계

> author: kodeholic (powered by Claude)
> date: 2026-04-22
> status: draft (부장 승인 대기)
> 선행: `20260421_ptt_unified_model_design.md` (Axiom 3개) / `20260422_peer_datastruct_analysis.md` (#1~#4)
> 목적: 4/21 맥북 논의에서 휘발된 "FLOOR_REQUEST destinations" 구조를 복원·확정하고, 4/22 논의에서 다음 사실을 정립시킨다:
>   1. `Peer.active_floor_room: Vec<RoomId>` 신규 상태 저장 불필요 (`Room.floor.current_speaker()` 적록)
>   2. "JOIN했지만 publish 안 하는 방" 은 지원 안 함 — 웨비나/moderate도 발언권 받으면 모든 방에 fan-out 되는 게 자연
>   3. `publish_intent` 삭제 가능

---

## 0. 배경

4/21 세션에서 Axiom 3개 + 파생 기능 설계 완료. 같은 날 맥북에서 **클라이언트가 FLOOR_REQUEST 시 발화 대상 방/유저를 서버에게 어떻게 전달할지**에 대한 논의가 진행됐으나 설계 문서에 기록되지 않음. 서버는 구버전 Floor v2 상태로 남고, 4/22 3인 영상 무전 실패(Peer multi-room leak × DC bearer `participant.room_id` 고정 참조)의 근본 원인.

**구버전 호환 미지원** — Phase 1 신 클라 ↔ Phase 1 신 서버. destinations TLV 필수.

---

## 1. 핵심 원칙

### 1.1 destinations는 **Publisher의 순간 의도**다
서버는 "어디로 말할지" 모른다. Publisher가 매 FLOOR_REQUEST 마다 **명시**. TLV 필수(없으면 Denied).

### 1.2 `destinations ⊆ peer.rooms` 불변식
"말하려면 들어야 한다." destination 이 Publisher의 `peer.rooms` set 에 포함되는지 검증. 벗어나면 Denied.

### 1.3 서버는 destinations를 저장하지 않는다
destinations는 FLOOR_REQUEST 처리 중에만 존재하고, 처리 완료 후 버려진다. 발화 상태의 단일 진실은 **`Room.floor.current_speaker()`**(기존 상태). 신규 필드 추가 없음.

Hot path는 `room.floor.current_speaker() == sender.user_id()` 로만 점검 — 이미 `fanout_half_duplex` 에 구현된 로직.

### 1.4 방별 destinations → 방별 Floor
`destinations = [roomA]` 요청 → `roomA.floor.try_grant(publisher)`. roomA의 Floor만 잡힌다. `peer.rooms` 의 다른 방 B/C는 Floor를 잡지 않으므로, Half-duplex RTP 는 그 방 fan-out에서 자동 차단(`floor.current_speaker() ≠ publisher`).

### 1.5 웨비나/진행자 모델은 Full-duplex이므로 무관
Full-duplex(진행자, 발언권 받은 청중)는 destinations 개념 무관 — `peer.rooms` 전체에 상시 fan-out. 발언권 받은 청중이 여러 방에 JOIN했다면 자연히 모두에 들린다.

### 1.6 순서 보존 — Phase 2
Phase 2에서 destinations 순서를 보존해야 할 경우 `Vec` 사용. Phase 1은 len==1 제한으로 순서 무관.

### 1.7 User destination은 Phase 2
Phase 1 범위는 **Room destination 만**. Whisper(1:1) 는 Phase 2 에서 `UserId` variant 추가.

---

## 2. 메시지 포맷 (MBCP native 확장)

### 2.1 FLOOR_REQUEST 페이로드에 TLV 추가

```
FIELD_DESTINATIONS = 0x0C      (미할당 TLV id — mbcp_native.rs 상수 테이블 재확인 필요)
  Length: 가변
  Value: u8 count + [u8 room_id_len + utf8 room_id] × count
```

- `count = 0` 또는 TLV 생략 → **Denied** (엄격)
- `count = 1` → 단일 방 (Phase 1 정상 동작)
- `count ≥ 2` → Phase 1은 **Denied + agg-log warn** (Phase 2 enable)

### 2.2 서버 처리 위치
`datachannel/mod.rs` `handle_mbcp_from_datachannel`:
- 기존: `participant.room_id` 참조 (multi-room에서 모호)
- 변경: FLOOR_REQUEST 페이로드에서 FIELD_DESTINATIONS 파싱 → `destinations[0]` 으로 Room 조회

### 2.3 destinations 없음 = 거부
구버전 호환 미지원. TLV 생략 FLOOR_REQUEST는 즉시 Denied. agg-log에 `floor:missing_destinations` 기록.

---

## 3. 응답 메시지

### 3.1 Granted (성공)
기존과 동일. destinations 정보 응답에 포함안함 (클라가 이미 알).

### 3.2 Denied (단일 방 실패)
기존 Denied. `cause` 필드에 구체 사유. Phase 1 범위.

### 3.3 PartialDenied (Phase 2) — 멀티 방 일부 실패
Phase 2 착수 시점에 재결정. 현재 권장은 **Denied + cause 문자열** (선택 A).

---

## 4. 서버 자료구조 변경 (#2만 — #1 기각)

### 4.1 #1 `Peer.active_floor_room: Vec<RoomId>` — **기각**
- 이유: `Room.floor.current_speaker()` 가 이미 단일 진실. 이중 관리 불필요.
- Hot path 역조회도 O(1) (`peer.rooms.len()` 이 대개 1).

### 4.2 #2 `RoomMember.publish_intent: AtomicBool` — **삭제**
- 웨비나/moderate 모델 전제: "JOIN했지만 publish 안 하는 방" 은 지원 안 함. 청중도 발언권 받으면 모든 JOIN 방에 fan-out되는 게 자연.
- Full-duplex: `track_type` 분기로 자동 라우팅. `publish_intent` 가드 불필요.
- Half-duplex: `room.floor.current_speaker()` 일치 여부로 자동 필터링. `publish_intent` 가드 불필요.
- 삭제 대상:
  - `track_ops.rs`: `publish_intent.store(true)` 1곳 (PUBLISH_TRACKS add)
  - `track_ops.rs`: `publish_intent.store(false)` 1곳 (PUBLISH_TRACKS remove, tracks empty 시)
  - `ingress.rs` fan-out: `if !member.publish_intent.load() { continue; }` 가드 1곳 (hot path 메인 루프)
  - `ingress.rs` audio level 추적: `publish_intent` 체크 1곳
  - `ingress.rs` `process_publish_rtcp`: SR relay 루프의 `publish_intent` 가드 1곳
  - `notify_new_stream`: TRACKS_UPDATE broadcast 루프의 `publish_intent` 체크 1곳
  - `participant.rs` `RoomMember` 필드 자체 삭제

### 4.3 `try_claim_floor(destinations: &[&str]) -> Result<(), RoomId>`
기존 시그니처 유지(single room_id)하되 Phase 1 구현은:
```rust
if destinations.len() != 1 { return Err(...); }
room_hub.get(destinations[0])?.floor.try_grant(publisher)
```
Phase 2에서 atomic grant 로 확장.

---

## 5. Fan-out 변경

### 5.1 현재 (publish_intent 기반)
```rust
for room_id in sender.peer.rooms_snapshot() {
    let fan_room = room_hub.get(room_id)?;
    let member = fan_room.get_participant(sender.user_id())?;
    if !member.publish_intent.load() { continue; }  // 가드 — 삭제 예정
    match track_type {
        HalfNonSim => self.fanout_half_duplex(..., &fan_room, ...).await,
        FullSim if video => self.fanout_simulcast_video(...).await,
        FullNonSim | FullSim => self.fanout_full_nonsim(...).await,
    }
}
```

### 5.2 변경 후 (publish_intent 가드 제거)
```rust
for room_id in sender.peer.rooms_snapshot() {
    let fan_room = room_hub.get(room_id)?;
    // publish_intent 가드 제거 — Full/Half 둘 다 자연 분기
    match track_type {
        HalfNonSim => {
            // fanout_half_duplex 내부의 room.floor.current_speaker() 체크가
            // destinations[0] 방에만 통과시키므로 자동 필터링
            self.fanout_half_duplex(...).await;
        }
        FullSim if video => self.fanout_simulcast_video(...).await,
        FullNonSim | FullSim => self.fanout_full_nonsim(...).await,
    }
}
```

### 5.3 Cross-room leak 자동 방지
- Half-duplex: destinations[0] 방의 Floor만 speaker로 publisher 지정 → 다른 방 `floor.current_speaker()` 는 다른 값 또는 None → `fanout_half_duplex` 에서 즉시 return.
- Full-duplex: publisher가 모든 `peer.rooms` 에 fan-out — 웨비나/moderate 모델과 일치.

### 5.4 per-packet dedup은 Phase 2
Phase 1은 destinations.len() == 1 이므로 dedup 불필요.

---

## 6. Phase 1 구현 범위

| 항목 | Phase 1 | Phase 2 |
|---|---|---|
| FLOOR_REQUEST destinations TLV | ✓ 필수, count == 1 | count ≥ 2 |
| DC handler가 TLV에서 room 선택 | ✓ | ✓ |
| `publish_intent` 삭제 | ✓ | — |
| fan-out `floor.current_speaker()` 기반 | ✓ (기존) | ✓ |
| Atomic grant (prepare/commit) | — | ✓ |
| per-packet dedup | — | ✓ |
| User destination (Whisper) | — | ✓ |
| Listen filter (channel scan) | — | ✓ |

**Phase 1 의 실질 개선**:
1. DC bearer 가 메시지 self-contained → 4/22 3인 영상 무전 실패(multi-room Peer × 고정 방) 구조적 해결.
2. `publish_intent` 삭제로 자료구조 간소화 — 4/22 분석 #2 수행.

---

## 7. 클라이언트측 변경

### 7.1 FloorFsm — destinations 파라미터
- `press()` → `press({ destinations: [currentRoom.id] })`
- SDK 내부 기본값: `[currentRoom.id]`
- MBCP payload 빌더에 FIELD_DESTINATIONS TLV 추가 (필수)

### 7.2 SDK 공개 API (진입점 준비)
- `Room.floor.press()` → 내부적으로 destinations=[this.id]
- 향후 `engine.floor.press({ destinations: [roomA, roomB] })` 확장 가능.

### 7.3 구버전 호환 없음
신 SDK만 신 서버와 통신. destinations TLV 필수.

---

## 8. 마이그레이션 순서

1. **설계서 확정** (본 문서 부장 승인)
2. **TLV 정의** — `mbcp_native.rs` FIELD_DESTINATIONS 상수 추가, 파서/빌더 구현, 단위 테스트
3. **DC handler 변경** — `datachannel/mod.rs` 의 `handle_mbcp_from_datachannel` 에서 TLV 기반 방 선택
4. **#2 publish_intent 삭제** — 가드 6곳 제거, 필드 제거, 빌드/테스트
5. **클라 SDK FloorFsm** — destinations 파라미터 추가, payload 빌더 TLV 추가
6. **통합 QA** — 3인 음성 / 3인 영상 / 5인 voice 통과

Phase 2는 별도 사이클.

---

## 9. 기각된 대안

- **`Peer.active_floor_room: Vec<RoomId>` 상태 추가** — `Room.floor` 와 이중 관리, 이중 동기화 리스크. `floor.current_speaker()` 로 충분.
- **TLV 없이 op-level 필드로 전달** — WS/DC 양 bearer 분기 증가, MBCP 규격 연속성 훼손.
- **destinations 없이 서버가 `peer.rooms` 전체로 broadcast** — Axiom 2 위배, 무전기 UX 파괴.
- **`destinations: HashSet<RoomId>`** — Phase 2에서 첫 방 미디어 규칙이 순서 의존이므로 Vec 가 정답.
- **Phase 1에 User destination 포함** — 범위 팽창, Whisper 는 별개 UX 설계 필요.
- **release 에 room_id 명시** — grant 시점에 서버가 이미 알고 있음 (Room.floor 내부 상태).
- **구버전 클라 fallback** — 호환 부담 없음, 엄격 거부 유지.
- **`publish_intent` 유지** — JOIN-only viewer 지원 불필요 (웨비나/moderate 모델: 발언권 받으면 자연스럽게 모든 JOIN 방으로 fan-out).

---

## 10. 오픈 이슈

- FIELD_DESTINATIONS TLV id 0x0C 선택 근거 — `mbcp_native.rs` 상수 테이블 재확인 필요.
- Phase 2 Atomic grant 시 prepare 실패 시 부분 grant 취소 트랜잭션 범위 — FloorController 락 범위 재설계 필요.
- destination 이 비어있는 `count=0` — 구버전 호환 제거로 일괄 Denied.

---

*author: kodeholic (powered by Claude)*
