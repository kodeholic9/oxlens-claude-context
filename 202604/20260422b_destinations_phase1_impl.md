# 20260422b Destinations TLV Phase 1 구현 세션

## 세션 목적
4/22 오전 자료구조 분석(`20260422_peer_datastruct_analysis.md`)에서 도출된 4건 중 destinations TLV + publish_intent 삭제의 Phase 1 구현. 전일(4/21) 발견된 3인 영상 무전 실패(Peer multi-room leak × DC bearer `participant.room_id` 고정 참조)의 구조적 해소.

---

## 설계 최종 확정 (4/22 맥북 → 본 세션 논의)

오전 논의에서 **Peer.active_floor_room Vec 불필요 / publish_intent 삭제 가능** 확정:

- `Room.floor.current_speaker()` 가 이미 방별 단일 진실 → 신규 상태 저장 불요. 기존 `Option<RoomId>` 유지
- 웨비나/moderate 모델 전제: "JOIN + publish 안 함" 상태 미지원 → 청중도 발언권 받으면 `peer.rooms` 전체 fan-out이 자연
- 구버전 호환 미지원 (Phase 1 신 클라 ↔ Phase 1 신 서버)

### 설계 문서
`context/design/20260422_destinations_message_design.md` (최종본, 초안 병합 후 단일 버전으로 정리)

---

## 구현 Step 1~4 (서버 + 클라)

### Step 1: `mbcp_native.rs` FIELD_DESTINATIONS TLV
- `FIELD_DESTINATIONS: u8 = 12` (0x0C) 추가
- `MbcpNative.destinations: Vec<String>` / `MbcpFields.destinations: Vec<String>`
- Parser/Builder: `u8 count + [u8 len + utf8 room_id] × count`
- 신규 단위 테스트 7개 (single/multi/empty/order/unicode/truncated/with_other_fields)
- `cargo test -p oxsfud mbcp_native` → **13/13 pass**

### Step 2: DC handler destinations 기반 방 선택
`datachannel/mod.rs::handle_mbcp_from_datachannel`:
- 기존: `participant.room_id` 고정 참조 (multi-room에서 모호)
- 변경: FLOOR_REQUEST 경로에서 `msg.destinations` 검증 → `destinations[0]` 으로 room 조회
- 검증 3단계:
  1. TLV 없음 → Denied + agg-log `floor:missing_destinations`
  2. `count ≥ 2` → Phase 1 Denied + agg-log `floor:multi_destination_phase2`
  3. `destinations[0] ⊄ peer.rooms` → Denied + agg-log `floor:destination_not_joined`
- FLOOR_RELEASE 는 `peer.current_floor_room()` 으로 조회 (grant 시점에 서버가 이미 앎)

### Step 3: `publish_intent` 필드 + 가드 7곳 삭제
- `track_ops.rs`: `store(true)` / `store(false)` 2곳
- `ingress.rs`: fan-out 메인 루프 / audio level tracker / SR relay / notify_new_stream — 4곳
- `participant.rs`: `pub publish_intent: AtomicBool` 필드 + initializer
- 한글 주석과의 매칭 실패로 `()` 타입 스텁 경유 후 필드 제거. doc 블록은 cleanup 대기 주석으로 남김
- `cargo test -p oxsfud --lib` → **138/138 pass**

### Step 4: 클라 SDK 확장
`oxlens-home/core/datachannel.js`:
- `FIELD.DESTINATIONS = 12`
- `buildMsg`: destinations 배열 TLV 직렬화
- `parseMsg`: FIELD.DESTINATIONS 역직렬화 (대칭)
- `buildRequest(priority, destinations)` 시그니처 확장

`oxlens-home/core/ptt/floor-fsm.js`:
- `request(priorityOrOpts, destinationsArg)` 오버로드 — `request(priority)` / `request({priority, destinations})` / `request(priority, destinations)` 세 가지 호출 스타일 허용
- 기본값: `[sdk._roomId]` (Phase 1 behavior 보존)

`oxlens-home/core/datachannel.test.mjs` 신규:
- 7개 roundtrip 테스트 (single/multi/order/empty/unicode/coexist/truncated)
- `node core/datachannel.test.mjs` → **7/7 pass**

---

## Step 5: 통합 QA (3인 음성 무전 qa_test_01)

**도구**: playwright MCP (Chrome 확장 localhost 차단 우회)

### 시나리오 A: 3인 회전 PTT

| 단계 | qa_voice_1 | qa_voice_2 | qa_voice_3 |
|------|-----------|-----------|-----------|
| u1 press | **talking** | listening (speaker=u1) | listening (speaker=u1) |
| u1 release | idle | idle | idle |
| u2 press | listening (speaker=u2) | **talking** | listening (speaker=u2) |
| u2 release | idle | idle | idle |
| u3 press | listening (speaker=u3) | listening (speaker=u3) | **talking** |
| u3 release | idle | idle | idle |

→ 완벽 동작. **destinations TLV 기반 FLOOR_REQUEST 정상 작동** 증명.

### 관련 어드민 스냅샷 확인
- DC `unreliable_ready: true`
- `sub_mid_map`: ptt-audio=mid 0, ptt-video=mid 1 (Universal SSRC pre-allocation 정상)
- state.subscribed `ssrc=0x505454A1 / 0x505454B1` (Universal SSRCs 정확 매칭)
- stream_map `first_seen_ago_ms` 찍힘 → 실제 RTP 흐름 증거

### 시나리오 B: multi-room 경계 탐색

한 명이 두 방 JOIN 시도 (`engine.joinRoom("qa_test_02")`)시:
- **서버**: qa_voice_1 Peer 가 `{qa_test_01, qa_test_02}` 모두에 RoomMember 등록 — cross-room Phase 1 서버 부분은 정상
- **클라 SDK**: `_roomId` 단일 필드 덮어쓰기. `state.published=[]` 초기화. handle `state.room`은 "qa_test_01" 로 고정 (불일치)
- 결론: **SDK multi-room 공개 API 미완성**

### Phase 1 한계 정리

| 시나리오 | 서버 | SDK | Phase 1 |
|----------|------|-----|---------|
| 5명 2방 분산 (각 1방씩) | ✅ | ✅ | ✅ |
| 각자 본인 방 PTT/Full-duplex | ✅ | ✅ | ✅ |
| 한 명이 2방 동시 JOIN | ✅ | ❌ | SDK 미완 |
| 한 명이 2방 동시 fan-out (Full-duplex 중계) | ✅ | ❌ | SDK 미완 |
| Multi-destination FLOOR_REQUEST (count≥2) | ❌ Phase 1 Denied | ✅ TLV 전송 | 서버 거부 (예정된 제한) |

→ **Phase 2 범위**: ① SDK multi-room 공개 API, ② 서버 multi-destination atomic grant.

---

## 오늘의 기각 후보

- **`Peer.active_floor_room: Vec<RoomId>` 상태 추가** — `Room.floor.current_speaker()` 가 이미 단일 진실. 이중 관리 리스크. 재확정 기각.
- **`publish_intent` 유지** — JOIN-only viewer 지원 불필요. 웨비나/moderate도 발언권 받으면 모든 JOIN 방 fan-out이 자연. 삭제 확정.
- **TLV 없이 op-level 필드로 destinations 전달** — WS/DC 양 bearer 분기 증가, MBCP 규격 연속성 훼손.
- **클라 `_roomId` 단일 필드를 Array 로 변경 (즉각)** — Phase 2 full 설계 없이 필드만 갈아끼우면 Engine 전반 산발적 영향. 공개 API 설계 먼저.

---

## 오늘의 지침 후보

- **한글 edit_file은 여전히 불안정** — ASCII 영역만 타겟팅하고, 한글 주석 블록은 위/아래 ASCII 앵커로 감싸 제거. 필드 제거 시 `()` 스텁 경유 → 컴파일러가 잔여 참조 찾게 → 잔여 제거 후 `()` 마무리 제거 순서가 안전.
- **scope는 타입으로 표현** — `publish_intent` 가드 삭제 후 fan-out 루프는 `peer.rooms_snapshot()` 순회 + `fan_room.get_participant()` null 체크만 남음. "participant 존재 = fan-out 자격" 으로 의미 정합.
- **playwright MCP가 Chrome 확장 정책 우회 경로** — `localhost/127.0.0.1` 접근 시. `Claude in Chrome:navigate` 실패 → `playwright:browser_navigate` 로 즉시 전환.
- **어드민 스냅샷 ≠ pipeline 통계** — 어드민 room snapshot 은 Peer/RoomMember 구조 덤프. pub/sub 중첩 스키마는 SfuMetrics flush 경로. 검증 시 둘을 구분.

---

## 다음 세션 착수 지점 (Phase 2)

1. **SDK multi-room 공개 API 설계**:
   - `Engine` 의 `_roomId: String` → `_rooms: Map<RoomId, RoomHandle>` 로 확장
   - `joinRoom(id, opts)` 가 기존 방에 add (leave-first 아님)
   - PowerManager / FloorFsm 이 "현재 방" 대신 "다중 방 상태" 다루도록
2. **서버 multi-destination atomic grant**:
   - `FloorController` prepare/commit 2단계 트랜잭션
   - `destinations.len() ≥ 2` 에서 모든 방 `try_grant` 성공 시에만 commit
   - 하나라도 실패 시 모두 rollback + PartialDenied (또는 Denied + cause 문자열)
3. **Per-packet dedup**:
   - Full-duplex가 `peer.rooms` 전체 fan-out 하는데, 같은 subscriber 가 여러 방에서 동일 publisher 를 본다면 중복 수신 → `sent_to: HashSet` 로 1회 차단

---

*author: kodeholic (powered by Claude)*
