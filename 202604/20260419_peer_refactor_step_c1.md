# Peer 재설계 Step C1 설계서 — Pub PC-scope RTP 필드 이주

**날짜**: 2026-04-19
**범위**: Peer 재설계 Step C1 — RTP 수신 관련 5필드를 `RoomMember` → `PublishContext`(= `peer.publish`)
**선행**: Step A (`room/peer.rs` 스켈레톤), Step B (MediaSession 이주 + credential 재사용)
**참고 설계서**: `20260419_peer_refactor_step_a.md`, `20260419_peer_refactor_step_b.md`, `20260419c_peer_refactor_direction.md`

---

## 1. 목표

Peer 재설계 Step C1. **RTP 수신 hot path 에 귀속되는 Pub PC-scope 5필드를 `RoomMember` 에서 `PublishContext` 로 이주**한다.

### 1.1 이주 대상 필드 (5개)

| 현재 위치 (`participant.rs` RoomMember) | 이주 위치 (`peer.rs` PublishContext) | 성격 |
|------|------|------|
| `rtp_cache: Mutex<RtpCache>` | `peer.publish.rtp_cache` | Publisher RTP 저장 (NACK → RTX 재전송 원본) |
| `stream_map: Mutex<RtpStreamMap>` | `peer.publish.stream_map` | SSRC ↔ kind/rid 자동발견 상태 + MediaIntent |
| `recv_stats: Mutex<HashMap<u32, RecvStats>>` | `peer.publish.recv_stats` | RTCP Terminator 수신 통계 (RR 자체 생성용) |
| `twcc_recorder: Mutex<TwccRecorder>` | `peer.publish.twcc_recorder` | TWCC sequence 기록 (BWE feedback 생성용) |
| `twcc_extmap_id: AtomicU8` | `peer.publish.twcc_extmap_id` | Chrome offerer가 할당한 TWCC extension ID |

### 1.2 Step B 와의 핵심 차이

- **Step B 치환 경로**: `member.publish.ufrag` → `member.endpoint.peer.publish.**media**.ufrag` (MediaSession은 PublishContext의 `media` 필드이므로 한 단계 더)
- **Step C1 치환 경로**: `member.rtp_cache` → `member.endpoint.peer.publish.rtp_cache` (PublishContext 직속 필드, `.media` 없음)

즉 C1 호출처는 `member.<필드>` → `member.endpoint.peer.publish.<필드>` 로 **한 계층만 삽입**. Step B보다 치환이 단순하다.

### 1.3 Step C1 이 C1 으로 묶인 이유 (설계 직관)

5필드 모두 **RTP 수신 hot path 에서 같은 lock 경로** 를 따라 접근된다:
- `handle_srtp` (ingress) → `resolve_stream_kind`(stream_map) → `collect_rtp_stats`(recv_stats + rtp_cache + twcc_recorder + twcc_extmap_id)
- 이주를 쪼개면 한 hot path 안에서 필드별로 다른 경로(`member.endpoint.peer.publish.stream_map` vs `member.recv_stats`)가 혼재 → 리뷰어/디버거 인지 부담 증가

따라서 5필드를 한 Step에서 원자 이주한다.

---

## 2. 범위에서 제외되는 것

다음은 Step C1 범위 **밖**. 각 Step에서 별도 처리.

### 2.1 기존 공개 API 유지 (갈래 A)

- 현재 `RoomMember` 에 이 5필드를 wrap 하는 공개 메서드는 **없음** (모두 필드 직접 참조).
- 따라서 Step B 의 갈래 A(기존 공개 API, 내부만 위임) 케이스가 Step C1 에는 **없음**. 모든 호출처는 갈래 B(필드 직접 참조 → 풀 경로 치환).

### 2.2 Step C2 이후로 미룸

- `simulcast_video_ssrc` (Step C2)
- `expected_video_pt` / `expected_rtx_pt` — 이는 사실 **subscriber 가 선언한 SDP PT** 이므로 Pub 이 아닌 **Sub 쪽**이라는 해석도 가능. 코드 주석 재검토 필요(`// subscriber가 기대하는 video/RTX PT 저장 ... PTT fan-out 시 PT rewrite용`). Step C2 진입 시 재판단.
- PLI 관련 5필드 (Step C3)
- 진단 2필드 (Step C4)
- RTX 2필드 (Step C5)
- DC 3필드 (Step C6)

### 2.3 Step D(Sub PC-scope) 이후

- `send_stats`, `stalled_tracker` — 이미 peer.rs 설계상 SubscribeContext 소속. Step D3.
- `subscriber_gate`, `subscribe_layers` — Step D2.
- `egress_tx`, `egress_rx` — Step D1.

---

## 3. 불변식

Step A~B 에서 확립된 4개 불변식 + Step C1 특수 1개.

### 3.1 전 Step 공통 (peer.rs 상단 참조)

1. **Transport 독립성** — `DemuxConn.peer_addr` / `DtlsSessionMap` 불변. hot path 포인터 chase 증감 0.
2. **MediaIntent user-scope** — Publish PC 가 user 당 1개인 한 MediaIntent 도 user-scope 영구. 방별 분할 금지.
3. **Egress singleton** — Sub PC user 당 1개. Step D1 에서 실제 도입.
4. **MediaSession 역할 분리** — MediaSession 은 행동, Context 는 상태. Context 가 MediaSession 을 소유하되 승격하지 않는다.

### 3.2 Step C1 특수

**5. RTP 수신 hot path 무결성** — `handle_srtp` 의 lock 순서와 lock 범위는 Step C1 후에도 그대로. 특히:
- `recv_stats` 의 lock 획득 시점/해제 시점이 바뀌지 않아야 한다 (인접 code path와 데드락 가능성)
- `stream_map` 의 intent() 호출 패턴 무변경 (clone 여부, 내부 read lock 등)
- hot path 에서 `member.recv_stats.lock()` 이 `member.endpoint.peer.publish.recv_stats.lock()` 으로 바뀔 뿐, 실행 시간에 유의미한 차이 없음 (포인터 chase 한 단계)

---

## 4. 핵심 설계 선택

### 4.1 편의 프록시 신설 금지 (정석)

Step B 와 동일 원칙. `RoomMember` 에 `rtp_cache()` / `recv_stats()` 같은 accessor 신설 **금지**. 호출처는 전부 풀 경로 `member.endpoint.peer.publish.<필드>` 치환.

### 4.2 갈래 A 없음

위 §2.1 참조. 이 5필드에 대한 기존 공개 API 가 없으므로 "내부만 위임" 전환 대상도 없다.

### 4.3 hot path 성능

`member.publish` → `member.endpoint.peer.publish` 는 `Arc<Endpoint>` 한 단계 deref 추가. `peer` 는 embed (Arc 아님)이므로 포인터 chase 1회.

기존 `member.recv_stats.lock()`:
- `member` (`Arc<RoomMember>` deref) → `recv_stats` 필드 (embed Mutex) → `.lock()`

Step C1 후 `member.endpoint.peer.publish.recv_stats.lock()`:
- `member` (`Arc<RoomMember>` deref) → `endpoint` (`Arc<Endpoint>` deref) → `peer` 필드 (embed) → `publish` 필드 (embed) → `recv_stats` 필드 (embed Mutex) → `.lock()`

포인터 chase 1회 추가. L1 cache hit 시 수 cycle. hot path 대비 무시 가능. Phase 1 기준 영향 없음. 측정 필요 시 egress/ingress micro-benchmark.

### 4.4 lock 순서 무변경

RTP 수신 hot path (`handle_srtp`):
1. `sender.publish.inbound_srtp.lock()` → decrypt → drop
2. `sender.stream_map.lock()` → resolve → drop
3. `sender.recv_stats.lock()` → update → drop
4. `sender.rtp_cache.lock()` → store → drop
5. `sender.twcc_recorder.lock()` → record → drop

Step C1 후 각 lock 경로가 `sender.endpoint.peer.publish.xxx.lock()` 로 바뀌지만 **획득 순서/범위 불변**. 데드락 리스크 없음.

---

## 5. 호출처 cascade 대응 규칙

Step B 의 §5 와 동일 원칙. 갈래 B 만 존재(위 §2.1 참조).

### 5.1 갈래 B — 필드 직접 참조 풀 경로 치환

cargo check 가 누락 없이 에러로 드러낸다. 각 에러를 다음 규칙으로 치환.

```rust
// Before — RoomMember 필드 직접 참조
let mut stats = member.recv_stats.lock().unwrap();
let twcc_id = member.twcc_extmap_id.load(Ordering::Relaxed);
member.rtp_cache.lock().unwrap().store(seq, data);
let intent = member.stream_map.lock().unwrap().intent().clone();
member.twcc_recorder.lock().unwrap().record(twcc_seq, now);

// After — 풀 경로 (PublishContext 직속, .media 없음)
let mut stats = member.endpoint.peer.publish.recv_stats.lock().unwrap();
let twcc_id = member.endpoint.peer.publish.twcc_extmap_id.load(Ordering::Relaxed);
member.endpoint.peer.publish.rtp_cache.lock().unwrap().store(seq, data);
let intent = member.endpoint.peer.publish.stream_map.lock().unwrap().intent().clone();
member.endpoint.peer.publish.twcc_recorder.lock().unwrap().record(twcc_seq, now);
```

### 5.2 치환 규칙 (5가지)

| from (RoomMember) | to (Peer) |
|------|------|
| `X.rtp_cache` | `X.endpoint.peer.publish.rtp_cache` |
| `X.stream_map` | `X.endpoint.peer.publish.stream_map` |
| `X.recv_stats` | `X.endpoint.peer.publish.recv_stats` |
| `X.twcc_recorder` | `X.endpoint.peer.publish.twcc_recorder` |
| `X.twcc_extmap_id` | `X.endpoint.peer.publish.twcc_extmap_id` |

### 5.3 find-replace 시 주의

- `stream_map` 은 `RtpStreamMap` 타입명과 구별. 타입은 touch 금지, **필드 접근** 만 치환.
- `twcc_extmap_id` 는 `rid_extmap_id` / `mid_extmap_id` 등 다른 extmap id 와 혼동 금지 (MediaIntent 내부 필드이며 저건 `stream_map.lock().intent().rid_extmap_id` 경로). Step C1 치환 대상은 **RoomMember 필드로서의** `twcc_extmap_id` 하나뿐.
- `recv_stats` 는 `send_stats` 와 혼동 금지 (후자는 Sub PC-scope, Step D3). cargo check 가 타입으로 구분해줄 것.

### 5.4 Korean 주석 영역

Step B 반성(`20260419e_peer_refactor_step_b_done.md` 참조)에 따라 Korean 주석이 포함된 영역은 `edit_file` 의 `oldText` 에서 **코드 라인만** 포함. 주석은 건드리지 않는다.

단, 필드 명칭을 언급하는 주석이 있다면(`// rtp_cache: ...` 류) 그 주석도 의미상 업데이트가 바람직. 다만 Step C1 범위 밖으로 잡고, Step F 에서 Endpoint → Peer 리네임 시 한꺼번에 문서 정리.

---

## 6. RoomMember 변화

### 6.1 필드 제거 (5개)

```rust
// Before (participant.rs)
pub struct RoomMember {
    // ...
    pub rtp_cache: Mutex<RtpCache>,
    pub twcc_recorder: Mutex<TwccRecorder>,
    pub recv_stats: Mutex<HashMap<u32, RecvStats>>,
    pub twcc_extmap_id: AtomicU8,
    pub stream_map: Mutex<RtpStreamMap>,
    // ...
}

// After (5필드 제거, 주석 블록으로 교체)
pub struct RoomMember {
    // ...
    // --- RTP 수신 (Step C1, 2026-04-19): `Endpoint.peer.publish` 로 이주 ---
    //
    // 이 5필드는 Pub PC-scope 자원이므로 같은 user 의 여러 JOIN 에 걸쳐 단일
    // Peer 를 공유한다. 접근 경로:
    //   member.endpoint.peer.publish.rtp_cache
    //   member.endpoint.peer.publish.stream_map
    //   member.endpoint.peer.publish.recv_stats
    //   member.endpoint.peer.publish.twcc_recorder
    //   member.endpoint.peer.publish.twcc_extmap_id
    // ...
}
```

### 6.2 RoomMember::new() 시그니처 무변경

이 5필드는 `RoomMember::new()` 내부에서 **자동 초기화**(`Mutex::new(HashMap::new())` 등)되어 있을 뿐, 외부에서 주입하는 인자가 아니다. 따라서 `new()` 시그니처 변경 없음.

초기화 로직은 제거. PublishContext 가 Endpoint 생성 시 이미 해당 필드를 초기화하므로 중복 초기화 없음 (Step B 와 동일 패턴).

### 6.3 공개 API 무변경

§2.1 참조. RoomMember 에 이 5필드를 wrap 하는 공개 메서드가 없으므로 공개 API 변화 0.

---

## 7. PublishContext 사용 시작

### 7.1 dead code 상태 → 활성화

Step A 에서 `#![allow(dead_code)]` 로 선언된 필드들. Step B 에서 이미 `media` 필드가 사용되기 시작했으므로 모듈 레벨 `allow(dead_code)` 는 유지되지만 범위를 좁혀도 OK.

Step C1 후에는 5개 필드(rtp_cache/stream_map/recv_stats/twcc_recorder/twcc_extmap_id)가 추가로 사용된다. 나머지 필드(PLI/진단/RTX/DC)는 여전히 dead code. 모듈 상단 `#![allow(dead_code)]` 는 Step C6 까지 유지.

### 7.2 PublishContext::new() 무변경

peer.rs Step A 설계에 따라 `PublishContext::new(ufrag, ice_pwd)` 는 이미 5필드를 초기화한다. 시그니처 변화 없음. Step C1 에서는 이 초기화 로직을 실제로 "사용하기 시작"한다.

---

## 8. 작업 순서

### 8.1 코드 변경 순서

1. **`participant.rs` 에서 5필드 제거** + 주석 블록으로 교체. `RoomMember::new()` 내부에서 5필드 초기화 라인 제거.
2. `cargo check -p oxsfud` → 갈래 B 호출처가 cargo 에러로 드러남.
3. **에러 목록을 §5.2 치환 규칙** 으로 전수 치환. 파일별 처리.
4. 재빌드, 테스트.

### 8.2 Step B 와 다른 점

- Step B 는 **Endpoint 구조 변화**(Peer embed 추가) + **ROOM_JOIN/LEAVE 흐름 재편**(get_or_create_with_creds, unregister_session 조건화)이 포함되어 복잡했다.
- Step C1 은 **순수 필드 이주** — 구조 변화도 흐름 변화도 없다. `participant.rs` 에서 필드 5개 제거 + `new()` 초기화 라인 제거가 전부. 나머지는 cascade 치환.

---

## 9. 리스크 및 사전 체크

### 9.1 초기화 누락 리스크

`RoomMember::new()` 에서 이 5필드 초기화를 제거해야 하는데, 누락하면 컴파일 에러. cargo 가 잡아준다 (필드 제거된 struct literal은 반드시 에러).

### 9.2 PipelineStats 혼동 방지

`recv_stats` 와 비슷한 이름으로 `pipeline.pub_rtp_in` 등이 있다. 이는 별도 카운터(PipelineStats의 필드)이며 Step C1 치환 대상 아님. `pipeline` 은 user-scope (Step E 이주 예정). **`pipeline.xxx` 는 건드리지 않는다**.

### 9.3 `send_stats` 와 혼동 방지

`recv_stats` 는 Pub PC (RTP 수신 통계). `send_stats` 는 Sub PC (RTP 송신 통계). 타입이 다르다:
- `recv_stats: Mutex<HashMap<u32, RecvStats>>` (key = source SSRC)
- `send_stats: Mutex<HashMap<(u32, RoomId), SendStats>>` (key = (송신 SSRC, room_id))

cargo check 가 타입 레벨에서 구분한다. grep 시에도 `recv_stats` vs `send_stats` 문자열이 달라 혼동 없음.

### 9.4 `stream_map` 메서드 체이닝

`member.stream_map.lock().unwrap().intent()` 같은 체이닝이 많다. 치환 후에도 체이닝 자체는 그대로:
```rust
// Before
member.stream_map.lock().unwrap().intent().audio_mid.clone()

// After
member.endpoint.peer.publish.stream_map.lock().unwrap().intent().audio_mid.clone()
```

### 9.5 Endpoint 내부에서의 참조

`endpoint.rs` 내에서 `endpoint.tracks.lock()` 같은 self 참조는 있을 수 있지만, **C1 이주 필드는 Endpoint.tracks 와 무관** — C1 은 Peer.publish 내부, `endpoint.tracks` 는 Step 7 에서 이미 Endpoint 직속. 충돌 없음.

### 9.6 borrow checker

Step B 에서 `register_session(&endpoint, ..., &endpoint.peer.publish.media.ufrag)` 같은 복수 immutable borrow 는 NLL 로 통과했다. Step C1 에서도 같은 패턴이 나올 수 있지만 모두 immutable → 문제 없음 예상.

---

## 10. 테스트 계획

### 10.1 기존 테스트 전량 통과 (회귀 없음)

Step B 후 126/126 pass. Step C1 후에도 126 이상이어야 함. 기존 테스트는 5필드의 존재/위치 자체를 검증하지 않으므로 대부분 무변경 통과.

예외: `participant.rs` 내부 tests 섹션에 `room_member_session_proxy` / `room_member_is_ready_proxy` 가 있다. 이 테스트들은 `member.endpoint.peer.publish.media` 에 접근하므로 여전히 통과.

### 10.2 Step C1 신규 테스트 (선택)

C1 자체에서 고유한 검증 포인트는 적다 (필드 이주만). 다만 설계 원칙 "완료 = 끝까지 동작" 을 지키려면 최소 smoke test:

- `peer_publish_context_holds_rtp_fields` — `PublishContext::new(...)` 생성 후 `rtp_cache.lock().len() == 0`, `recv_stats.lock().is_empty()`, `twcc_extmap_id.load() == 0` 확인.
- 이미 Step A 의 `publish_context_new_smoke` 에서 `recv_stats` / `simulcast_video_ssrc` 초기값은 확인 중. 추가 여부는 구현 시 판단.

실질적 검증은 E2E (conference/voice_radio/video_radio/moderate 4종 시나리오). Step C1 구현 후 부장님이 브라우저에서 실제 RTP 송수신 확인.

---

## 11. Step 경계 엄수

Step C1 에서 하지 않는 것 (정석 원칙).

- **C2 이후 필드 이주 금지** — simulcast_video_ssrc / PLI / 진단 / RTX / DC 를 "한번에 같이" 안 옮긴다. 각 Step 별 cargo check → 테스트 → 커밋 사이클을 지킨다.
- **주석 대대적 정리 금지** — "Step 7: tracks는 Endpoint가 소유. Participant 초기화에서 제거됨" 같은 기존 주석은 의미상 더 이상 맞지 않을 수 있지만 Step C1 에서 건드리지 않는다. Step F 리네임 시 일괄 정리.
- **편의 프록시 신설 금지** — (반복) 정석.
- **SubscribeContext 사용 금지** — Sub PC-scope 5필드 이주는 Step C1 범위 밖. `send_stats` / `subscribe_layers` 등은 여전히 RoomMember 에 남아있다.

---

## 12. 구현 체크리스트

### 12.1 사전

- [ ] 이 설계서 부장님 승인
- [ ] Step B 완료 상태 확인 (`cargo test -p oxsfud` 126/126)

### 12.2 코드 변경

- [ ] `participant.rs` — `RoomMember` struct 에서 5필드 제거 + 주석 블록으로 교체
- [ ] `participant.rs` — `RoomMember::new()` 내부에서 5필드 초기화 라인 제거
- [ ] `cargo check -p oxsfud` → 갈래 B 호출처 에러 목록 확보
- [ ] 에러 목록 → §5.2 규칙 치환 (파일별, write_file vs edit_file 은 반복 빈도로 판단)
- [ ] 재빌드 0 error / 0 warning
- [ ] `cargo test -p oxsfud` 126+/0

### 12.3 검증

- [ ] `cargo build --release` 성공
- [ ] E2E 4종 시나리오 (conference / voice_radio / video_radio / moderate) — 부장님 브라우저 확인
- [ ] admin 스냅샷의 recv_stats / TWCC 카운터 / rtp_cache 카운터가 기존과 동일하게 흐르는지 (텔레메트리 필드 이름 무변경 보장)

### 12.4 문서

- [ ] `context/202604/20260419f_peer_refactor_step_c1_done.md` 세션 컨텍스트
- [ ] `SESSION_INDEX.md` 0419 섹션 추가
- [ ] `PROJECT_MASTER.md` Step C1 ✓ 체크

---

## 13. 예상 파일 변경 범위

### 13.1 수정 필수 (확실)

- `crates/oxsfud/src/room/participant.rs` — RoomMember 필드 제거 + new() 축소
- `crates/oxsfud/src/room/peer.rs` — 사용 시작 (선언은 이미 Step A에서 완료, 변경 최소)

### 13.2 갈래 B cascade 예상 (cargo check 전 추정)

RTP 수신 hot path 에 따른 파일 분포. Step B 의 갈래 B cascade 분포와 유사하게 예상:

- `transport/udp/ingress.rs` — RTP 수신 hot path, 가장 많은 호출 예상 (recv_stats, rtp_cache, stream_map, twcc_recorder, twcc_extmap_id 전부)
- `transport/udp/ingress_subscribe.rs` — Subscribe RTCP 에서 recv_stats 접근 (SR translation + NACK RTX 재전송)
- `transport/udp/egress.rs` — send_rtcp_reports 에서 recv_stats → RR block 생성, send_twcc_to_publishers 에서 twcc_recorder 접근
- `transport/udp/rtcp_terminator.rs` (?) — recv_stats 직접 참조 가능성. 확인 필요.
- `signaling/handler/track_ops.rs` — PUBLISH_TRACKS 에서 stream_map 접근 (intent 저장)
- `signaling/handler/helpers.rs` — collect_subscribe_tracks 에서 stream_map 접근 가능
- `signaling/handler/admin.rs` — 어드민 스냅샷에서 recv_stats / twcc 카운터 접근
- `tasks.rs` — run_stalled_checker 에서 recv_stats 접근 가능 (또는 send_stats 만? 확인 필요)

대략 **8~10 파일 범위**, 치환 **50~100 곳** 예상. Step B 보다 규모는 비슷하거나 조금 크다 (필드 수가 2개 → 5개).

---

## 14. 확정된 결정 사항

### Q1. 편의 프록시 신설? → **금지 (정석)**
Step B 와 동일 원칙. 호출처 전수 풀 경로.

### Q2. `expected_video_pt` / `expected_rtx_pt` Step C1 포함? → **제외 (Step C2 로 미룸)**
이 두 필드는 **subscriber 가 자신의 subscribe SDP 에 선언한 PT 값** 이다. RTP 송신 시 subscriber 별로 PT rewrite 하는 데 사용 (PTT fan-out 경로). 따라서 Sub PC-scope 로 보는 게 정확하며, peer.rs 설계 단계에서 SubscribeContext 의 `expected_video_pt` / `expected_rtx_pt` 로 이미 예약되어 있다. Step D5 이주 예정.

Step C1 peer.rs PublishContext 의 해당 필드는 **사용 시작 보류**. Step D5 에서 SubscribeContext 쪽으로 옮기면서 PublishContext 쪽 선언을 삭제한다.

**수정 사항**: Step A 설계(`peer.rs` 현재)에 PublishContext 에 `expected_video_pt` / `expected_rtx_pt` 가 실수로 선언되어 있지 않은지 재확인. (peer.rs 확인 결과 PublishContext 에는 해당 필드 선언 없음 — OK. Step A 설계가 정확했다.)

### Q3. Step C1 테스트 추가? → **최소 smoke test 1개** (선택적)
위 §10.2 참조. 기존 `publish_context_new_smoke` 에서 이미 일부 확인 중. 추가 여부는 구현 시 판단.

### Q4. 세션 컨텍스트 파일 이름 → `20260419f_peer_refactor_step_c1_done.md`
이전 세션 f 순서 유지.

---

*author: kodeholic (powered by Claude), 2026-04-19*
