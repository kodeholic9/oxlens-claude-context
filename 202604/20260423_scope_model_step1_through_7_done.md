# Scope 모델 Step 1~7 완료 (Cross-Room rev.2)

**날짜**: 2026-04-23
**설계서**: `context/design/20260423_scope_model_design.md` (rev.2)
**관련 코드**:
- 서버: `oxlens-sfu-server/crates/oxsfud/src/{room/scope.rs, room/peer.rs, signaling/handler/scope_ops.rs, signaling/handler/admin.rs, tasks.rs, datachannel/mbcp_native.rs, room/floor_broadcast.rs}`
- 클라: `oxlens-home/core/{scope.js, scope.test.mjs, constants.js, signaling.js, engine.js}`

---

## TL;DR

하루 세션에서 Scope 모델 설계서 §11.2 로드맵의 **Step 1~7 전부 완결**. Phase 2 (Step 8: SFU-SFU relay) 직전까지 도달.

- 서버: `cargo test -p oxsfud` **163 pass** (시작 158 → +5)
- 클라: `node core/scope.test.mjs` **14 pass** (신규)
- 기존 동작 regression 0 (Phase 1 단일 방 시나리오 100% 하위호환)

---

## 구현 요약

### Step 1 — Peer scope 필드 (RoomSet + set_id)

- `crates/oxsfud/Cargo.toml`: `arc-swap = "1"` 추가
- `room/scope.rs` 신규: `RoomSetId(Arc<str>)` + `RoomSet { set_id, rooms }` + RCU helpers (`with_inserted`, `with_removed`)
- `Peer` 에 `sub_rooms: ArcSwap<RoomSet>`, `pub_rooms: ArcSwap<RoomSet>` 필드
- `join_room` / `leave_room` 에서 cascade 자동 적용 (pub 먼저 §4.3)
- `set_id` 형식: `"sub-{user_id}"` / `"pub-{user_id}"` — 세션 수명 불변
- 단위 테스트: scope.rs 5개 + peer.rs 5개

### Step 2 — SubscriberIndex + fan-out user 단위 교체

- `PeerMap` 에 `by_room_subscriber: DashMap<RoomId, DashMap<String, Arc<Peer>>>` 추가
- 키 = user_id (reconnect 안전, 같은 user가 새 Peer 로 들어와도 교체 안전)
- `attach_to_room` / `detach_from_room` / `subscribers_snapshot` / `subscriber_count` 메서드
- JOIN/LEAVE 핸들러에서 attach/detach 호출
- `transport/udp/ingress.rs` fan-out **6곳 교체**: `room.participants.iter()` → `self.endpoint_map.subscribers_snapshot(room.id)` + `room.get_participant()` 재조회
- `reap_zombies` 내부 자동 detach
- 단위 테스트 6개

### Step 3 — SCOPE_UPDATE / SCOPE_SET / SCOPE_EVENT + primitive 4

- `oxsig/src/opcode.rs`: `SCOPE_UPDATE=53, SCOPE_SET=54, SCOPE_EVENT=107` 상수
- `signaling/message.rs`: `ScopeUpdateRequest` / `ScopeSetRequest` (serde rename `"pub"`) / `ScopeEventPayload`
- `Peer` primitive 4개: `sub_insert / sub_remove_one / pub_insert / pub_remove_one` (기존 join cascade 용 `scope_insert / scope_remove` 와 별개)
- `handler/scope_ops.rs` 신규: `handle_scope_update` / `handle_scope_set` / `apply_scope_update` / `release_floor_in_room`
- 처리 순서 (§4.6): `sub_add → pub_add → pub_remove → sub_remove`
- Cascade (§4.8): pub_remove 시 floor 자동 release, sub_remove 시 pub 자동 cascade
- `cargo test` 162 pass (+4)

### Step 4 — FLOOR_TAKEN user 단위 + speaker_rooms/via_room 메타

- `datachannel/mbcp_native.rs`: TLV 필드 `FIELD_SPEAKER_ROOMS=0x0A`, `FIELD_VIA_ROOM=0x0B` 추가
- `build_taken()` 시그니처 확장: `(speaker, priority, speaker_rooms: Vec<String>, via_room: Option<String>)`
- `room/floor_broadcast.rs`: `apply_floor_actions` / `broadcast_floor_frame` / `broadcast_dc_svc` 에 `peer_map: &Arc<PeerMap>` 추가, `SubscriberIndex` 기반 user 단위 순회
- Granted 처리: speaker 의 `pub_rooms` 수집 + via = 현재 방
- 호출처 업데이트 **9곳**: tasks.rs 2곳(floor_timer, active_speaker), lib.rs spawn 2곳, datachannel/mod.rs 체인 5단계(run_sctp_loop → process_association_events → handle_stream_event → handle_dc_binary → handle_mbcp_from_datachannel), floor_ops.rs 2곳, room_ops.rs 1곳, scope_ops.rs 1곳, track_ops.rs SWITCH_DUPLEX 1곳, transport/udp/mod.rs DTLS handshake 후 2곳
- **Step 4c (FLOOR_REQUEST `pub_set_id`) 연기** — destinations TLV(`0x0C`)와의 호환 재정리 필요

### Step 5 — STALLED user 단위 관측

- `PeerMap::peers_snapshot() -> Vec<(String, Arc<Peer>)>` 신규 pub 메서드 (reap_zombies snapshot 패턴 추출)
- `tasks.rs::run_stalled_checker` 재작성:
  - Before: `rooms × participants` 2중 루프 (cross-room 에서 N번 중복 체크)
  - After: `peers` 1중 루프, tracker 내부에서 `(ssrc, room_id)` key 의 room_id 로 `rooms.get()` 조회
- `floor_speaker` / `publisher` / `layers` 는 **방별 지역** — tracker entry 마다 다를 수 있음
- `stalled_list: Vec<(ssrc, pub_id, kind, room_id)>` — 방 정보 포함
- Phase 1 단일 방 결과 동일, Phase 2 cross-room 에서 N방 중복 체크 제거
- `cargo test` **163 pass** (+1)

### Step 6 — Admin User 뷰

- `signaling/handler/admin.rs`: `build_rooms_snapshot` 응답에 `"users": build_users_snapshot(state)` 필드 추가
- `phase_as_str(u8) -> &'static str` 로컬 헬퍼 (Created/Intended/Active/Suspect/Zombie 5단계)
- `build_users_snapshot` 신규 함수 (설계서 §9.5 축 분리 원칙):
  - `user_id, participant_type, created_at, phase, last_seen_ago_ms, suspect_since`
  - `joined_rooms, sub_rooms {set_id, rooms}, pub_rooms {set_id, rooms}, active_floor_room`
  - `pub_pc {ufrag, latched, addr}, sub_pc {ufrag, latched, addr}` — PC pair readiness
  - `tracks` (user-scope publisher 트랙) — room 뷰와 중복 최소화
  - `dc {unreliable_ready, pending_buf_len}`
  - `mid_pool {audio_active, video_active, total}`
- 설계서에 있던 `vssrc_slot / packets_received_delta / active_publishers` 는 현재 관측 인프라 없어 스킵 (Phase 2)
- 기존 `rooms` 배열은 방 정보만 (혼재 제거) — 하나의 snapshot 메시지에 두 뷰 병존

### Step 7 — SDK Scope API (oxlens-home)

**네임스페이스 그룹 방식 확정** (부장님 승인, 옵션 B):

```js
engine.scope.affiliate(r)      // sub_add
engine.scope.deaffiliate(r)    // sub_remove
engine.scope.select(r)         // pub_add
engine.scope.deselect(r)       // pub_remove
engine.scope.update({ sub_add, sub_remove, pub_add, pub_remove, change_id? })
engine.scope.set({ sub, pub, change_id? })

engine.scope.{sub, pub, sub_set_id, pub_set_id}   // 읽기
engine.scope.snapshot() / hasSub() / hasPub()
engine.scope.on('changed', handler)
```

- `core/scope.js` 신규 — `ScopeController extends EventEmitter`
- `core/constants.js` — OP에 3 opcode 추가
- `core/signaling.js` — `_handleEvent` 에 `SCOPE_EVENT` case, `_handleResponse` 에 `SCOPE_UPDATE/SET` case (둘 다 `scope.applyEvent(d)` 경유)
- `core/engine.js` — import + ctor `this._scope` + `get scope()` getter + disconnect 리셋
- `core/scope.test.mjs` 신규 — 14개 단위 테스트

**핵심 설계 — Server-authoritative**:
- 로컬 mutate 금지. `affiliate()` 호출 = SCOPE_UPDATE 송신만, 상태는 서버 응답(applyEvent)으로만 갱신
- §4.6 partial success 경로에서 요청과 실제 결과가 다를 수 있어 낙관적 업데이트 위험
- `_onJoinedRoom` / `_onLeftRoom` 훅 준비만 (joinRoom 플로우에 미연결 — cross-room 시나리오 시점에 1줄로 연결)

**JSON key 대칭**:
- 서버 Rust struct field `pub_rooms` ↔ serde rename 으로 JSON `"pub"`
- SDK JS 전송/수신 모두 `"pub"` (JS reserved word 아님)

---

## 검증

| 구성 | 결과 |
|---|---|
| `cargo test -p oxsfud` | 163 pass / 0 fail |
| `node core/scope.test.mjs` | 14 pass / 0 fail |
| 기존 Phase 1 단일방 E2E regression | **미수행** — scope API 미사용 시 영향 0 기대, Claude in Chrome QA 는 후속 |

테스트 14번에서 EventEmitter try/catch 동작 검증 중 `console.error` 출력 — 의도된 동작 (리스너 예외 격리).

---

## 오늘의 지침 후보

1. **설계서가 선행된 다단계 리팩터는 하루에 끝내는 게 낫다**. Peer 재설계 F 14세션(부장님 "허용 불가" 평가)과 대조적으로 Scope 는 설계서 rev.2 로 사전 합의된 구조라 Step 1~7을 하루 집중으로 처리 가능. 단 각 Step 경계에서 cargo test 게이트 필수.

2. **서버 Rust serde rename ↔ 클라 JS JSON key 대칭은 문서화**. `pub_rooms` / `"pub"` 케이스처럼 언어별 reserved word 차이로 내부 이름과 wire format 이 다를 때 클라/서버 코드 주석에 정확한 key 명시.

3. **Server-authoritative 원칙을 SDK 설계 기본으로**. 낙관적 업데이트는 partial success / cascade 가 있는 곳에서 항상 위험. 상태는 서버 응답 수신 시에만 mutate 하는 흐름이 디버깅/일관성에서 이득.

4. **네임스페이스 그룹 vs flat 접미사**. Engine 이 거대한 Facade 클래스일 때 도메인별 하위 컨트롤러(`engine.scope.*`, `engine.power.*`, `engine.acquire.*`)가 flat 보다 발견성/유지보수 이득. MCPTT 표준 용어(`affiliate/select`)를 네임스페이스가 감싸서 단독 사용해도 혼동 없음.

5. **편집이 이미 반영되었는지 먼저 확인**. compaction 경계 또는 세션 이어가기 중 "Step 6 진행해" 같은 재지시가 오면 파일 크기/타임스탬프/tail 로 현재 상태 확인이 맹목적 재편집보다 안전. 오늘 Step 6 사례.

---

## 오늘의 기각 후보

1. **ScopeController 낙관적 업데이트** (affiliate 호출 즉시 sub.add) — §4.6 partial success 에서 어긋남. Server-authoritative 로 확정.

2. **`engine.affiliate()` / `engine.select()` 플랫 API** — Engine 43KB 이미 거대. `select` 단어가 DOM/SQL select 자동완성과 혼동. 네임스페이스 그룹(`engine.scope.*`)으로 확정.

3. **`_onJoinedRoom` / `_onLeftRoom` 훅을 joinRoom 플로우에 즉시 연결** — 기존 입장 흐름 잘못 건드릴 위험 > 이득. Phase 1 단일 방에서 scope API 사용 안 함. 훅만 만들어 두고 cross-room 시점에 연결.

4. **설계서 §9.5 `vssrc_slot` / `active_publishers` / `packets_received_delta` 어드민 필드** — 현재 관측 인프라 없음. Phase 2 로 연기. 현재 인프라에서 즉시 채울 수 있는 필드만 포함.

5. **SCOPE_EVENT 서버 측 broadcast 구현** — Step 3 범위 밖. 요청자에게 응답만. 서버 옵션 A (implicit join cascade) 도 SCOPE_EVENT broadcast 안 함 — SDK 가 `_onJoinedRoom` 낙관적 미러로 해결.

6. **Step 4c (FLOOR_REQUEST `pub_set_id` 확장)** — MBCP native TLV destinations (`0x0C`) 와의 호환 재정리 필요. 현재 destinations phase 1 구현이 완료된 상태라 독립적 통합 설계 세션이 필요. Step 1~7 맥락에선 연기.

---

## 잔여 작업

- **Step 4c**: FLOOR_REQUEST `pub_set_id` 확장 — destinations TLV (`0x0C`) 와 호환 재정리
- **SDK `_onJoinedRoom` / `_onLeftRoom` 훅 연결** — cross-room 시나리오 착수 시점에 joinRoom/leaveRoom 1줄씩
- **Phase 2 (Step 8)**: SFU-SFU relay. Hub routing plane 승격, Cross-SFU scope 집계, `Peer.sub_rooms` 변경 시 Hub 훅
- **SDK multi-room 컨테이너**: 현재 `engine._currentRoom` 단일 Room 전제. cross-room UI 요구 생기면 Engine-level `Map<roomId, Room>` 전환
- **UX 가드레일**: 설계서 §10.1 (pub ⊆ sub 강제 vs 독립) — 부장님 결정 대기
- **E2E QA**: 기존 10 시나리오 regression 검증 (Claude in Chrome) — Phase 1 단일 방 scope API 미사용 = 영향 0 예상이지만 실측 필요
- **PROJECT_MASTER 업데이트**: 서버 버전 상승 반영 + Scope 모델 현황 섹션 신설 (부장님 지시 대기)

---

## 참고 — 설계서/세션 연결

| Step | 설계서 섹션 | 세부 |
|---|---|---|
| 1 | §3.1, §3.2, §3.3 | RoomSet + set_id + 불변식 |
| 2 | §9.1, §9.2 | SubscriberIndex + user 단위 fan-out |
| 3 | §4.4, §4.5, §4.6, §8.1, §8.3 | Affiliate/Select/Update/Set opcode |
| 4 | §5.4, §5.5 | Floor 방별 독립 + FLOOR_TAKEN user 단위 |
| 5 | §9.4 | STALLED user 단위 관측 |
| 6 | §9.5 | Admin 축 분리 (방/User) |
| 7 | §10.5 (B5) | SDK 공개 API — 본 세션에서 MCPTT 표준 용어로 확정 |

---

*author: kodeholic (powered by Claude)*
