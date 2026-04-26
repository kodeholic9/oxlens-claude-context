# 20260425c — Step 4c FLOOR_REQUEST pub_set_id ↔ destinations MUTEX 완료

**버전**: v0.6.24 유지
**선행**: `20260423_scope_model_step1_through_7_done.md` (Scope rev.2 Step 1~7), `20260422b_destinations_phase1_impl.md` (destinations TLV Phase 1)
**후속**: MBCP 규격 정합성 조치 (별도 세션 예정)

---

## 착수 배경

Scope rev.2 Step 1~7 완료 후 연기된 **Step 4c — FLOOR_REQUEST 에서 `pub_set_id` 와 `destinations` 호환**.

Scope 모델에서 발화 대상 방을 지정하는 경로가 두 갈래로 갈라졌음:

| 경로 | 의미 | 사용 시점 |
|---|---|---|
| `destinations=["room_a"]` TLV (id=12) | ad-hoc 방 직접 지정 | 기존 destinations Phase 1 (4/22) |
| `pub_set_id="pub-user123"` TLV (id=13) | `Peer.pub_rooms` scope 참조 | Scope rev.2 Step 4c |

부장님 확정 — **MUTEX 원칙** ("묶음은 묶음 id 로, 안 묶인 경우 room-id 로", 공존 없음). LMR Harris P25 SAID / MCPTT Talkgroup ID vs Channel List 패턴.
단독 설계서 미작성 (부장님 지시) — destinations 설계서(`20260422_destinations_message_design.md`) + Scope 설계서 rev.2 사이에 얹는 보완분.

---

## 확정 설계

- **TLV id**: `FIELD_PUB_SET_ID = 0x0D` (서버/클라 동일, 기존 미점유)
- **MUTEX 위반**: Denied 응답 + `cause_text="mutex_violation"` + agg-log warn
- **Phase 1 제약**: destinations 경로 `count==1` 강제 (기존 유지) + pub_set_id 경로도 `pub_rooms.len()==1` 강제
- **stale 체크**: pub_set_id 가 현재 `Peer.pub_set_id` 와 다르면 Denied (`pub_set_id_stale`)
- **empty 체크**: `pub_rooms` 가 비었으면 Denied (`pub_set_empty`)
- **클라 기본 동작**: 단일 방 = 기존 destinations 경로 유지 (하위 호환), 명시적 호출 시만 pub_set_id 사용

---

## 서버 구현 (4파일)

### 1. `crates/oxsfud/src/datachannel/mbcp_native.rs`

- `FIELD_PUB_SET_ID: u8 = 13` 상수 추가
- `MbcpNative.pub_set_id: Option<String>` + `MbcpFields.pub_set_id` 필드
- parse/build 로직 (empty string omit — 의도적 "없음" 취급)
- 단위 테스트 5개 추가

### 2. `crates/oxsfud/src/room/peer.rs`

**핵심 리팩터** — 방 선택 검증 로직 helper 로 추출:

```rust
pub enum FloorRouteDeny {
    MutexViolation,          // destinations + pub_set_id 동시
    MissingDestinations,     // 둘 다 없음
    MultiDestinationPhase1,  // destinations.len() >= 2
    DestinationNotJoined,    // destinations[0] ∉ Peer.joined_rooms
    PubSetIdStale,           // 요청 pub_set_id ≠ Peer.pub_set_id
    PubSetEmpty,             // Peer.pub_rooms.len() == 0
    PubSetPhase1MultiRoom,   // Peer.pub_rooms.len() >= 2
}

impl FloorRouteDeny {
    pub fn cause_text(&self) -> &'static str;
    pub fn agg_key_suffix(&self) -> &'static str;
}

impl Peer {
    pub fn resolve_floor_target(
        &self,
        destinations: &[String],
        pub_set_id: Option<&str>,
    ) -> Result<RoomId, FloorRouteDeny>;
}
```

단위 테스트 12개 추가 (7 variant × 정상 케이스 커버).

### 3. `crates/oxsfud/src/datachannel/mod.rs::handle_mbcp_from_datachannel`

기존 분산 검증 3곳 → helper 1곳 호출로 통합.

### 4. `crates/oxsfud/src/signaling/handler/floor_ops.rs::handle_floor_binary`

WS fallback 경로에도 동일 helper 적용. 이전에는 envelope `room_id` 만 참조하고 TLV 를 무시하는 버그가 있었음 — **동시 수정**.

---

## 클라 구현 (2파일)

### 1. `oxlens-home/core/datachannel.js`

- `FIELD.PUB_SET_ID = 13` 상수
- `buildMsg` / `parseMsg` pub_set_id roundtrip (empty string omit)
- `buildRequest(priority, destinations, pubSetId)` 시그니처 확장
- **클라측 MUTEX throw** — 서버 도달 전 사전 방어 (`Error("...MUTEX...")`)

### 2. `oxlens-home/core/ptt/floor-fsm.js`

`request({ pub_set_id })` / `request({ pubSetId })` 오버로드. 클라측 MUTEX 가드 `code=4032`.

---

## agg-log 신규 key 7종

| key | 의미 |
|---|---|
| `floor:mutex_violation` | destinations + pub_set_id 동시 |
| `floor:missing_destinations` | 둘 다 없음 |
| `floor:multi_destination_phase2` | `destinations.len() >= 2` (Phase 2 대기) |
| `floor:destination_not_joined` | destination 방에 참가 중 아님 |
| `floor:pub_set_id_stale` | 구 pub_set_id 참조 |
| `floor:pub_set_empty` | `pub_rooms` 비어있음 |
| `floor:pub_set_phase1_multi_room` | `pub_rooms.len() >= 2` (Phase 2 대기) |

---

## 빌드 / 테스트 결과

### 서버

```
cargo test --workspace:  180 passed, 0 failed
```
기존 163 + 신규 17 (mbcp_native 5 + peer 12).

### 클라 단위 테스트 확장 — `datachannel.test.mjs`

4/22 destinations Phase 1 시 만든 기존 7 테스트 유지 + **33 추가 → 총 40 passed, 0 failed**.

추가 카테고리:

| 카테고리 | 개수 | 핵심 |
|---|---:|---|
| 상수 대칭 (서버 `mbcp_native.rs` 와의 MSG/SVC 값) | 2 | 회귀 시 즉시 빨간불 |
| Frame codec (`buildFrame`/`parseFrame`) | 6 | roundtrip / ArrayBuffer / too-short / truncated / trailing bytes / empty |
| **Step 4c pub_set_id** | **6** | **roundtrip / empty 생략 / unicode / TLV id=13 wire 검증 / destinations(id=12) wire 검증 / 둘 다 wire 공존 파싱** |
| 기타 메시지 필드 | 7 | GRANTED+duration / DENY / QUEUE_INFO / IDLE / too-short / unknown TLV 무시 / ACK_REQ bit |
| **buildRequest MUTEX** | **6** | **dest only / pubSetId only / neither / dest+pubSetId throw / empty string no-op / priority only** |
| Release/Ack | 2 | 정확한 type + ACK 비트 |
| Speakers payload | 4 | basic / count=0 / null / truncated |

**핵심 가치 2가지**:
1. **TLV id 12/13 byte-level wire 검증** — 서버 `FIELD_DESTINATIONS=12` / `FIELD_PUB_SET_ID=13` 과 대칭 보장. 어느 한쪽이 상수 바꾸면 즉시 빨간불.
2. **MUTEX throw** — 클라 사전 방어. 서버 `FloorRouteDeny::MutexViolation` 도달 전 차단.

---

## 부가 작업 — MBCP 규격 정합성 조사 (보고만)

Step 4c 마무리하면서 부장님이 "예전부터 확인하고 싶던" MBCP vs TS 24.380 규격 정합성을 교차 검증.

### 핵심 발견

**우리 MBCP 는 TS 24.380 정식 규격이 아닌 자체 포맷**이다. Wireshark MCPTT dissector (nemergent, TS 24.380 v13.0.2 기반) Table 8.2.2-1 과 교차:

| Type | 정식 | OxLens |
|---:|:---|:---|
| 2 | **Floor Taken** | FLOOR_DENY ✗ |
| 3 | **Floor Deny** | FLOOR_RELEASE ✗ |
| 4 | **Floor Release** | FLOOR_IDLE ✗ |
| 5 | **Floor Idle** | FLOOR_TAKEN ✗ |
| 8 | **Floor Queue Position Request** | FLOOR_ACK ✗ |
| 9 | Floor Queue Position Info | (없음) ✗ |
| 10 | Floor Ack | (없음) ✗ |
| 12 | (없음) | FLOOR_QUEUE_INFO ✗ |

메시지 코드가 교차 충돌 (Taken↔Deny, Release↔Idle 쌍이 뒤섞임). TLV 필드 코드도 전면 불일치 (정식 0=Priority, OxLens 1=Priority 등). 타이머 명명도 의문 — 우리 T101 이 정식 T100 에 해당할 가능성.

### 해석 및 권고

실운영 영향 없음 (외부 MCPTT 단말과 통신하지 않음). 하지만 코드/문서의 "TS 24.380 §8.2.2 기반" 표기는 오해 소지.

**권고 = 옵션 B (자체 포맷 명시 + 문서 정정)** — 코드는 그대로, 주석/문서만 "OxLens 자체 포맷 (TS 24.380 참조)" 로 정정. 누락된 Queue Position Request 는 우리 번호 체계로 필요 시 추가.

### 부장님 결정

"다른 세션에서 mbcp 는 조치할께" — **본 세션 추가 작업 없음**. 별도 MBCP 정리 세션에서 문서 정정 + 필요 시 Queue Position Request 추가 다룰 예정.

---

## 오늘의 지침 후보

1. **부장님 번호 참조 해석은 최근 목록 기준** — "② 진행해" 같은 지시에서 번호 해석이 갈리면 일단 바로 직전 내 목록의 해당 번호로 해석. 이번에 내가 "T4~T7 진행해"로 오해해서 시간 낭비. "지금 하라는 건 ①" 정정 받음.
2. **byte-level wire 검증 = 서버/클라 대칭 보증의 유일한 확실한 방법** — `FIELD.PUB_SET_ID=13` 같은 상수 일치는 각 언어 상수 조회만으론 불충분. 실제 `buildMsg()` 출력 바이트를 `assertEq(v[2], 13)` 식으로 직접 확인해야 양쪽 변경에도 즉시 감지. datachannel.test.mjs 에 "wire symmetry" 테스트 패턴으로 고정.
3. **helper 추출로 분산 검증 재사용** — `Peer::resolve_floor_target` 하나를 DC 경로와 WS fallback 경로에서 모두 호출. 이전에는 WS fallback 경로가 TLV 무시하던 잠재 버그도 동시 수정됨. "같은 도메인 검증이 여러 전송 경로에 걸친다" 패턴에서는 helper 가 기본.
4. **완료된 세션의 파일 존재는 SESSION_INDEX 와 별개 진실** — 이전 압축 요약에서 "SESSION_INDEX 미기재 → T4~T7 미완"으로 잘못 해석. 실제 파일 확인이 정답. 앞으로 "완료됐는지" 의심 시 get_file_info + read_text_file 확인을 SESSION_INDEX 조회보다 우선.
5. **MBCP 표준 준수 표방은 조사 후 확정** — "TS 24.380 §8.2.2 기반" 같은 주석은 실제 규격과 비교 안 하고 쓰면 오류. 향후 RFC/표준 참조 주석 달 때는 최소 Wireshark dissector 같은 공개 구현 1종과 교차 확인.

---

## 오늘의 기각 후보

1. **MBCP 옵션 A (표준 준수 재정렬)** — 메시지 타입 2/3/4/5 교차 재매핑 + TLV 코드 전면 재매핑 + 타이머 명명 정정. 배포 비용 대비 표준 단말 상호운용 이득이 없음 (웹 브라우저 PTT 가 핵심 타겟). 옵션 B 로 확정.
2. **destinations + pub_set_id 공존 허용** (일부 팀은 "둘 다 있으면 pub_set_id 우선" 처리) — 의미가 이중화됨. 위 MUTEX 원칙(LMR SAID / MCPTT Talkgroup ID 패턴)과 충돌. 확정 기각.
3. **클라측 MUTEX 체크 생략하고 서버에만 의존** — 서버 Denied 받는 것도 정상 경로지만 토글 가능성 높은 API 라 clientside throw 로 오용 원천 차단이 UX 가치 있음. `buildRequest()` 시점 throw 채택.
4. **empty string `pub_set_id` 를 MUTEX 위반으로 간주** — "빈 문자열=명시적 없음" 의미로 destinations 와 공존 가능. buildMsg 에서 `pubSetId.length > 0` 체크 + 테스트 `buildRequest(0, ["r1"], "")` 통과 검증.
5. **`datachannel.test.mjs` 를 scope.test.mjs 처럼 test runner 없이 재작성** — 기존 파일이 이미 동일 스타일 (빈손 script + passed/failed 카운트) 이라 그대로 확장.

---

## 남은 과제

- **E2E QA** — Claude in Chrome 으로 10 시나리오 smoke test. 특히 Step 4c 의 pub_set_id 경로는 Scope rev.2 가 실제로 발현되는 시점에 확인 필요 (현재는 cascade 로 sub=pub=joined 라 단일 방 데모에선 destinations 경로로 갈음). `engine.scope.select()` 명시 호출 시 pub_set_id 기반 floor request 발동을 관찰 가능.
- **Track 리팩터 T7 cosmetic cleanup** — 본 세션에서 부분 적용 (아래 "T7 cosmetic (본 세션 추가)" 섹션 참조).
- **MBCP 규격 정합성 조치** — 별도 세션에서. 주석/문서 "TS 24.380 §8.2.2" 표기 정정 + Queue Position Request 추가 여부 + 타이머 명명 정정 범위 결정.
- **PROJECT_MASTER.md 업데이트** — "프로토콜" 섹션 FIELD_PUB_SET_ID(0x0D) 반영, "핵심 학습 & 원칙" 에 MUTEX 원칙 한 줄 추가 (부장님 직접).

---

## T7 cosmetic (본 세션 추가)

세션 끝무리로 T7 cosmetic 작업 일부 적용. `cargo check -p oxsfud` 통과, 런타임 동작 영향 0.

| 파일 | 작업 | 결과 |
|---|---|---|
| `crates/oxsfud/src/room/room_id.rs` | docstring 에 T5 (2026-04-23) subscribe_layers key `(String,RoomId) → (u32,RoomId)` 변경 한 줄 반영. tests 의 `room_id_tuple_key_lookup` 주석에도 "T5 이후 실제 key 는 (u32, RoomId)" 명시. | ✅ |
| `crates/oxsfud/src/room/participant.rs` | 중복된 Step E3 주석 한 쌍(2번 반복) 삭제. | ✅ |
| `crates/oxsfud/src/room/participant.rs` | `publish_intent` dead doc 블록(12줄) 한 줄 tombstone 으로 압축. | ⚠️ skip |

**skip 사유**: `participant.rs` 에 깨진 UTF-8 byte (replacement char `�`) 다수 발견 — Track enum `/// 판사 불가`, DTO `/// 값 복사`, SubscribeLayerEntry `/// subscriber N △에게 공유`, `ensure_virtual_ssrc /// 트랙△서` 등. edit_file 가 "글자는 같아 보이는데 byte 는 다름" 상태로 매칭 실패. write_file 전체 재작성은 2100+ 줄 오류 위험 대비 이득 미미 → 부장님 "오타 같은거는 그냥 넘어가" 지시로 skip.

**남은 cleanup 후보** (별도 cosmetic 세션):
- `participant.rs` 깨진 UTF-8 byte 4건 정리 (투도구로 `grep -P '[\xEF\xBF\xBD]'` 같은 식으로 위치 펠친 후 직접 교체)
- `publish_intent` dead doc 블록 압축 (위 깨진 byte 정리 이후 개설)

---

## 시간 소요

세션 내 실 코딩: Step 4c 서버/클라 + datachannel.test.mjs 확장 = 약 2시간.
MBCP 규격 조사 + 보고 = 약 30분.
번호 해석 오해로 Track 리팩터 상태 확인 = 약 15분 (순소모, 덤으로 T7 남은 cosmetic 존재 재확인).

---

*author: kodeholic (powered by Claude)*
