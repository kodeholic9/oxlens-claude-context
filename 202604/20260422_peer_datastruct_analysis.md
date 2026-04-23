# 20260422 Peer/RoomMember 자료구조 분석 세션

## 세션 목적
Peer 재설계 Step F 착수 전, `participant.rs` / `room.rs` / `peer.rs` / `room_id.rs` + 호출자(`ingress.rs` / `tasks.rs` / `room_ops.rs`) 자료구조 정합성 점검.

---

## 확정 사항 (구조 변경 방향)

### 1. `Peer.active_floor_room: Mutex<Option<RoomId>>` → `Mutex<Vec<RoomId>>`

**근거**: 여러 방 동시 발화 허용 설계로 변경됨 (Axiom 1 multi-destination). 기존 `Option` 구조는 "한 방 제한"을 강제하는 코드이며, 현 방향과 정면 모순.

**의미 변경**: "user의 floor 보유 방(단일)" → "atomic grant 결과로 잡힌 방 집합(destinations 순서 보존)".

**순서 보존 근거**: destinations의 첫 번째 방이 미디어 전달 방(후술). 따라서 `HashSet` 아님. `Vec<RoomId>` 또는 `IndexSet`.

**동반 변경**:
- `try_claim_floor` / `release_floor` / `current_floor_room` 3개 메서드의 의미 재정의
- `destinations ⊆ peer.rooms` 불변식 추가 ("발화하려면 듣고 있어야 한다")

### 2. `RoomMember.publish_intent: AtomicBool` 삭제

**근거**: destination 전달이 PUBLISH_TRACKS(영구) → FLOOR_REQUEST(매 발화)로 이동. 따라서 "이 방에 publish 자격"을 영구 플래그로 보관할 필요 없음. destinations set이 발화 시점마다 자격 필터 역할 수행.

**동반 삭제**:
- `track_ops.rs`의 `store(true)/store(false)` 세팅 로직
- `ingress.rs` fan-out 루프 4곳의 `if !member.publish_intent.load() { continue; }` 가드
- `process_publish_rtcp`의 SR relay 루프 가드
- 설계서 §3/§10.4 "publish 자격" 개념 자체 소멸

### 3. `PipelineStats` Pub/Sub 분리 (γ)

**근거**: 10개 필드 중 `pub_*` 5개는 user-scope(publisher가 보낸 RTP 1번), `sub_*` 5개는 room-scope(subscriber가 방 맥락에서 수신). Scope가 다름.

**변경**:
```rust
// Peer (user-scope)
pub struct Peer {
    ...
    pub pub_stats: PublishPipelineStats,
}

// RoomMember (room-scope)
pub struct RoomMember {
    ...
    pub sub_stats: SubscribePipelineStats,
}
```

**부수 효과**: 접두사 `pub_`/`sub_` 이중 표기 제거. 컨테이너가 곧 scope.

### 4. `Peer.pipeline: PipelineStats` 삭제

**근거**: 생성만 되고 어디서도 읽히지 않는 dead field. ingress는 `sender.pipeline` / `target.pipeline`으로만 접근 — 전부 RoomMember 경유. (3) 수행 시 자연 소멸.

---

## 관찰 사항 (오늘 세션 범위 밖, 별도 작업 필요)

### 5. Axiom 1 destinations 메시지 구조 — 서버/클라이언트 동시 작업 필요

**확인 사실**:
- 4/21 세션에서 Axiom 3개 + 파생 기능 6개 + 설계 문서 착수까지 도달
- 4/21 이후 맥북에서 **클라이언트 메시지 형태까지 논의**됐으나 설계 문서에 안 담김
- 결과: 서버만 구버전 Floor v2 상태로 남음 (단일 방, priority, queue, preempt)

**복원해야 할 것들**:
- FLOOR_REQUEST에 `destinations` 배열 필드 (room 대상 + user 대상)
- All-or-Nothing grant/deny 응답 포맷
- FLOOR_TAKEN broadcast에 destinations 정보 포함 여부
- room 대상과 user 대상 통합 vs 분리 필드

**확정 내용(오늘 세션 논의)**:
- `destinations ⊆ peer.rooms` ("말하려면 들어야 한다")
- destinations 순서 = 클라이언트 의도 반영 (첫 번째 방이 미디어 전달)

### 6. Multi-destination fan-out — "첫 번째 방 미디어, 나머지 방 FLOOR_TAKEN만"

**시나리오**:
```
방1: A, B / 방2: A, B, C, D
B가 destinations=[방1, 방2] 발화
→ A는 방1 경로로 미디어 1번만 수신 (dedup)
→ 방2에는 FLOOR_TAKEN broadcast만 (C, D는 정상 수신)
```

**구현 요점**:
- ingress hot path에서 per-packet `sent_to: HashSet<&str>` dedup
- `peer.rooms_snapshot()` 대신 `peer.active_floor_rooms()` 순회
- 첫 번째 방이 미디어 전달 방 (destinations 순서)

**자연스러운 이유**:
- Axiom 2 (subscriber 1 stream 불변식) 보존
- 무전기 스캔 모드의 단일 스피커 UX와 부합
- 미디어/시그널링 plane 분리 (SFU 원리)

### 7. 트랙 다중성 미표현 (새 발견) — camera + screen + bodycam 대비

**현재 구조의 문제**:
- `PublishContext.rtp_cache: Mutex<RtpCache>` — **단일** (비디오 2트랙 시 충돌)
- `PublishContext.simulcast_video_ssrc: AtomicU32` — **단일** (camera simulcast + screen non-sim 동시 불가)
- Subscribe 쪽에 "트랙" 엔티티 **부재** (SSRC 키로 HashMap에 분산)
- `layers: HashMap<(pub_id, RoomId), _>` vs `send_stats: HashMap<(ssrc, RoomId), _>` — **키 단위 불일치** (publisher vs 트랙)

**근본 원인**:
"한 user = 비디오 1트랙" 가정이 자료구조에 박혀 있음. 하지만 시나리오 설계에서는:
- `support_field`: full-duplex + screen
- `caster`: audio + screen
- `presenter`: audio + video + screen
- 향후: bodycam 등 다중 카메라

이미 camera + screen 혼용이 설계에 명시되어 있음.

**개선 방향 후보 (판단 아님)**:
- (a) Subscribe 쪽 `SubscribedTrack` 엔티티 도입 — per-publisher-per-track 명시화
- (b) `rtp_cache`를 `HashMap<ssrc, RtpCache>`로 확장
- (c) `layers` 키를 `(pub_id, track_id, room)`로 확장 — 단위 통일

### 8. 바디캠/다중 카메라 향후 대비 — 모드 선택

**두 가지 모드**:

- **(A) 같은 Pub PC에 다중 트랙** — `Track.source` ("camera"/"screen"/"bodycam") 확장
  - Peer 재설계 골격 유지. 작은 수술.
  - 관찰 #7의 4건 반영 필요.

- **(B) 독립 WebRTC 클라이언트** — 바디캠이 자체 네트워크로 sfud 직결
  - user당 1 Peer 가정과 충돌. 큰 수술.
  - 앱 레이어에서 "같은 사람 장비 그룹" 매핑.

**방향성 합의**: **(A)를 기본 모델로, (B)는 앱 영역에 위임**.
- sfud/SDK는 "한 Peer = 한 Pub PC = 여러 트랙 가능"만 지원
- 독립 디바이스는 별도 user로 JOIN + 메타 태그 연관 (moderate/recorder 패턴과 유사)
- 부장님 힌트: "개별 peer 아니더라도, peer에 속한다 정도는 **구분**" — `Track.source`로 충분

---

## 오늘의 기각 후보

- **`active_floor_room: Option<RoomId>` 유지** — 여러 방 동시 발화와 구조적 모순
- **`publish_intent: AtomicBool` 유지** — destinations가 대체, 이중 정보
- **`PipelineStats` 한 덩어리 유지** — Scope가 다른 필드가 섞여 user-scope/room-scope 헷갈림 (부장님 원어: "나중에 해석할 때도 헷갈림 없을 것 같은데")
- **부분 grant 허용** — Axiom 1 원칙 위배 (4/21 세션에서 이미 기각)
- **모든 destinations에 미디어 릴레이** — A가 방1/방2 멤버이면 중복 수신 → Axiom 2 위배
- **바디캠 = 별도 Peer 강제** — Peer 재설계 골격 흔들림. 앱 레이어 위임이 정답

## 오늘의 지침 후보

- **"한눈에 안 들어오면 부정합"** — 부장님 원어: "어려워. 한눈에 파악이 안됨". 필드 수 많아서일 수도 있지만, 그 자체로 관찰 신호. 자료구조가 이해 가능해야 함.
- **"자료구조에서 막히면 나머지 보는 거 의미 없자나"** — 부장님 원어. 골격 단계 문제 발견 시 하위 레이어 분석 중단이 맞음.
- **"scope는 타입으로 표현"** (Peer 재설계 §1 재확인) — PipelineStats (γ) 분리의 근거. 접두사/주석이 아닌 컨테이너 위치로 scope 표현.
- **"미디어 plane과 시그널링 plane 분리"** — multi-destination 발화 시 미디어는 첫 방만, FLOOR_TAKEN은 전 방. 전통 무전기 UX와 일치.
- **"구분은 분리가 아니다"** — 바디캠 관련 부장님 발언. "peer에 속한다 정도는 구분"이면 `Track.source` 필드로 족함. 별도 Peer 만들 필요 없음.
- **"맥북 논의가 설계 문서에 안 담기면 구현에도 안 반영된다"** — publish_intent가 Axiom 기반 구조 없이 구버전 형태로 남은 교훈.

---

## PENDING

**즉시 착수 가능 (Step F 이후 또는 별도 스텝)**:
- [ ] #1~#4 구조 변경 (Peer 재설계 Step F 후 리팩터 스텝)
- [ ] #4 Peer.pipeline 삭제는 당장 가능 (독립 작업)

**설계 작업 필요 (맥북 복원 + 재합의)**:
- [ ] #5 Axiom 기반 FLOOR_REQUEST destinations 메시지 설계
- [ ] #5 서버 FloorController의 atomic grant 로직 설계
- [ ] #5 클라이언트 FloorFsm의 destinations 입력/응답 처리
- [ ] #6 multi-destination fan-out dedup 구현 설계

**장기 (Phase 2 cross-room 진입 시)**:
- [ ] #7 트랙 다중성 반영 (rtp_cache HashMap화, Subscribe 엔티티 도입, 키 단위 통일)
- [ ] #8 Track.source 확장 (bodycam 등), 앱 레이어 가이드

---

*author: kodeholic (powered by Claude)*
