---
title: Scope 모델 설계 — Cross-Room 라우팅 기본 모델
author: kodeholic (powered by Claude)
date: 2026-04-23
revision: rev.2 (그룹 A~E 해결 반영)
status: DRAFT (§10.1 미결정, 그룹 F 프리셋 추후 조정)
related:
  - context/design/20260416_cross_room_federation_design.md (rev.2)
  - context/design/20260418_cross_room_phase1_step4_stun_index.md
  - context/design/20260418_cross_room_phase1_step9c_publish_intent.md
  - context/design/20260419_subscribe_rtcp_cross_room.md
  - context/design/20260419_register_notify_room_scope.md
  - context/design/20260409_moderated_floor_design.md
  - context/design/20260410_moderated_floor_design_v2.md
changelog:
  - rev.0 (2026-04-23): 초안
  - rev.1 (2026-04-23): 검토 의견 반영 (§4.6 배치 검증, §9.2 벤치, §9.3 coalesce 명세, §10.1 근거 보강, §14 시퀀스, §15 시나리오)
  - rev.2 (2026-04-23): 그룹 A~E 해결 반영
    - 용어 확정: pub_scope→pub_rooms, sub_scope→sub_rooms
    - set_id 도입 (§3.2, 추적/페이로드 경량화)
    - **대원칙 확정**: 방/트랙은 scope 모름, 필요시 scope 등장 (§0, §3.5)
    - vssrc user 단위 재해석 (§3.6 신규)
    - SubscriberIndex 도입 (§9.1 신규)
    - 충돌 처리 대폭 단순화 (§5 재작성): 방별 독립 판정, 집계 정책 폐기
    - FLOOR_TAKEN 전달은 user 단위 (§5.5 재작성)
    - RTP fan-out은 user 단위 (§9.2 재작성)
    - STALLED 관측 user 단위 전환 (§9.4 신규)
    - Admin 뷰 user 중심 탭 추가 (§9.5 재작성)
    - LMR Patch/Multi-Select 업계 선례 (§2.4 신규)
    - §14 시퀀스 재작성 (user 단위 fan-out 반영)
    - §15 시나리오 매핑 재작성
    - 그룹 F(프리셋) 보류 명시 (§11.3)
    - Ducking primitive 원칙 추가 (§3.8, SDK는 gain primitive만, 정책은 도메인)
---

# Scope 모델 설계 — Cross-Room 라우팅 기본 모델

## 0. TL;DR

- **핵심 아이디어**: cross-room 멀티룸 라우팅을 **"방 여러 개 join"이 아니라 "user의 pub/sub 방 집합 2개"** 로 재프레임.
- **대원칙**: **방/트랙은 scope를 모른 채 기존대로 동작. Scope는 필요한 지점(라우팅·전달·관측 축)에만 등장한다.**
- **선례**: 3GPP MCPTT의 Affiliation/Selection + LMR P25 Patch / Multi-Select Transmit. 수십 년 상용 검증된 패턴.
- **적용 범위**: PTT에 국한되지 않음. Full duplex에서도 동일 구조.
- **Peer 재설계와 정합**: "user × SFU = PC pair 1쌍" 원칙 위에 `pub_rooms`/`sub_rooms` 필드 + `set_id` 얹음.
- **SFU는 dumb 유지**: SFU는 scope "의미"를 모름. 클라가 명시하고 서버는 라우팅만.
- **기존 단일 방 동작 0 변경**: 집합 원소 1개 = 현재와 완전 동일. 하위호환 자연.

---

## 1. 배경 및 동기

### 1.1 현재 Cross-Room Phase 1의 구조적 약점

Phase 1 암묵 가정은 "여러 방에 join = 모든 방에 균일하게 pub+sub"이지만, 실사용은 **비대칭이 기본**:

- **지휘관**: A방에 명령 방송 + B,C방은 청취만
- **상담원**: 여러 고객방에서 수신 + 응답은 선택한 방 하나만
- **관제사**: 여러 현장방 모니터링 + 지시는 관제방만

기존 모델로 풀려면 "트랙마다 target room 리스트" 또는 "방마다 publish_intent 복제" — 방 중심 사고의 흔적이 지저분.

### 1.2 모델의 본질

사용자 관점 두 개의 독립 집합:

- **pub_rooms**: "내가 이 방들에 송출하겠다"
- **sub_rooms**: "내가 이 방들에서 수신하겠다"

교집합도 포함관계도 아닌 독립 집합. **개인의 서사**이지 다른 사용자와 공유 안 됨.

### 1.3 용어

- 내부 용어: `pub_rooms`, `sub_rooms`, `joined_rooms`
- 부장님/비즈니스 용어: "그룹" 사용 가능
- MCPTT 매핑:
  - `sub_rooms` ↔ Affiliated Groups (여러 개 가능)
  - `pub_rooms` ↔ Selected Group (MCPTT는 1개, 우리는 집합)

> **SDK 공개 API 명명 별도 결정** (§10.5). 본 문서는 내부 용어만 확정.

---

## 2. 업계 선례

### 2.1 3GPP MCPTT (TS 22.179 §4.3)

> *"If an MCPTT User is only **affiliated** to a group this is so that they can receive from the group, however if an MCPTT User has a **Selected** MCPTT Group this is their group for transmitting on. The differences in states enable an MCPTT User to **receive from multiple MCPTT Groups**, but specify which MCPTT Group they would like to transmit on."*

- **Affiliation ≠ Selection** 명시적 분리
- N2 = 동시 affiliate 최대, MaxSimultaneousCallsN6 = 동시 call 최대
- Implicit vs Explicit Affiliation
- Functional Alias (역할 선택)

### 2.2 DMR (Digital Mobile Radio)

- **Talk Group**: 송신 대상 ID (선택된 1개)
- **Scan List / RX Group List**: 수신만 할 TG 집합 (여러 개)
- 하드웨어 레벨 "송신 1, 수신 다수" 비대칭

### 2.3 주/부채널 개념

무전기 사용자 관점:
- **Selected Group** = 주채널 = 지금 돌려놓은 채널 (PTT 누르면 송신)
- **Affiliated** = 부채널 = 스캔으로 감시하는 채널들 (수신만)

우리는 주채널을 **집합으로 확장** (pub_rooms N 가능) — MCPTT에서 벗어난 지점.

### 2.4 LMR Console Patch / Multi-Select Transmit (rev.2 신규)

LMR/P25/MCPTT 콘솔의 표준 기능. NPSTC 문서:

> *"Next Generation consoles must support the ability to **interconnect talkgroups and channels** from different networks, commonly called **'patching'**."*

> *"**Multi-select transmit** in which an MCPTT console needs to **transmit a message over several MCPTT talkgroups at the same time**."*

**Harris P25 방식** (SAID = System Assigned ID):
- Patch 생성 시 시스템이 pool에서 sequential ID 할당
- Voice Grant에 **Patch ID만** 실음 (원본 TG 리스트 아님)
- 구독 radio들이 mapping으로 풀어냄
- Dynamic 생성/해제

**Patch vs MCPTT User Regroup 차이**:

| | User Regroup | **Patch / Multi-Select** |
|---|---|---|
| 묶는 대상 | 사람 (MCPTT ID) | **채널/talkgroup (방)** |
| 결과 | 새 임시 그룹 | **채널들의 연결** |
| 멤버들이 새 그룹 인식 | 예 | **아니오** (기존 방에서 수신) |
| 주 사용자 | 그룹 멤버 | **콘솔/디스패처** |

**Patch가 우리 pub_rooms와 정확히 매핑**. 우리 `set_id`는 Harris SAID 모델과 동일.

### 2.5 3GPP MCPTT의 Group ID 참조 패턴

TS 24.379 §6.3.3: Call 요청 SIP INVITE에 **Group ID만** 담음. 서버가 group document에서 멤버 풀어냄.

> *"if the group identity in the SIP INVITE request for controlling MCPTT function of an MCPTT group is an MCPTT group ID: shall determine the members to invite..."*

**§6.3.5 "Retrieving and processing a group document"** — 서버 측 멤버 해석 절차 표준 정의.

큰 리스트 필요 시 `application/resource-lists+xml` MIME body (RFC 5366) 분리 첨부. 모두 **ID/URI 참조 + 서버 풀어내기** 패턴.

### 2.6 차용/미차용

| 차용 O | 차용 X |
|---|---|
| Affiliation vs Selection 분리 | SIP INVITE (gRPC passthrough 유지) |
| N2/MaxN6 상한 (policy.toml) | Pre-established session (이미 connect/publish 분리) |
| Implicit/Explicit Affiliation | MCPTT "Selected=1개" 제약 |
| Functional Alias (role 재사용) | — |
| Per-group floor independence | — |
| Server-side arbitration | — |
| **Patch ID 참조 방식 (SAID)** | — |
| **MCPTT Group ID 참조 (body 인라인 대신 ID)** | — |

---

## 3. 핵심 모델

### 3.1 데이터 구조

```rust
// Peer는 user × SFU = PC pair 1쌍에 귀속 (Peer 재설계 원칙)
Peer {
    joined_rooms: HashSet<RoomId>,           // "입장한 방들"  — Affiliation 상위 집합
    sub_rooms:    ArcSwap<RoomSet>,          // "받을 방들"    — Affiliated
    pub_rooms:    ArcSwap<RoomSet>,          // "보낼 방들"    — Selected (집합 확장)
    // ... 기존 Peer 필드 (publish context, subscribe context, dc state 등)
}

struct RoomSet {
    set_id: RoomSetId,                       // 고유 ID (추적/페이로드 경량화)
    rooms:  HashSet<RoomId>,
}
```

### 3.2 set_id — 고유 식별자 (rev.2 신규)

**목적**:
1. **텔레메트리 추적**: 로그/스냅샷에서 set_id로 scope 컨텍스트 즉시 식별
2. **페이로드 경량화**: FLOOR_REQUEST 등에 방 리스트 대신 set_id 참조 (MTU 압박 해소)
3. **오독 방지**: AI/운영자가 set_id 존재로 "scope 모델 컨텍스트" 인지

**발급**:
- 서버가 Peer 생성 시 `sub_rooms`/`pub_rooms` 각각에 부여
- 세션 수명 (reconnect 시 shadow에서 복원)
- 형식: `"sub-{user_id}-{seq}"`, `"pub-{user_id}-{seq}"` 등 가독성 있는 문자열

**업계 선례 정합**: Harris P25 SAID (Patch ID pool sequential 할당), MCPTT Group ID 참조 패턴과 동일.

**참조 동작**:
```
클라: FLOOR_REQUEST { pub_set_id: "pub-U123-5" }
서버: set_id로 RoomSet 조회 → 방별 FloorFsm에 dispatch
```

1000방 시나리오에서도 페이로드 일정. MTU/fragmentation 고민 해소.

### 3.3 불변식

```
pub_rooms ⊆ sub_rooms ⊆ joined_rooms
```

단, `pub ⊆ sub` 강제 여부는 **§10.1에서 미결정** (CCTV/드론 송출 시나리오 지원 여부).

### 3.4 PTT와 Full의 관계

scope와 duplex는 **직교하는 두 축**:

- **duplex** = 트랙 속성 (half면 floor 필요)
- **scope** = 라우팅 속성

| 모드 | pub_rooms 의미 |
|---|---|
| Full | "상시 송출되는 방 집합" |
| Half (PTT) | "floor 잡으면 송출될 방 집합" |

**모델 동일, 활성화 시점만 다름.**

### 3.5 대원칙 (rev.2 명시)

> **방/트랙은 scope를 모른 채 기존대로 동작한다.**
> **Scope는 필요한 지점(라우팅 대상 판정, 전달 대상 수집, 관측 축 통일)에만 등장한다.**

**방 레이어** (scope 모름):
- Room.members (참여 메타)
- FloorFsm 상태 관리, 판정
- 방별 트랙 등록/제거

**User(scope) 레이어**:
- pub_rooms / sub_rooms (set_id)
- SubscriberIndex (라우팅 역인덱스)
- vssrc 슬롯 관리
- Fan-out 대상 판정
- FLOOR_TAKEN 전달 대상

**Admin/관측 레이어**:
- 방 뷰 (방 단위 정보만)
- User 뷰 (user 단위 정보, scope 포함)

각 레이어는 자기 축에서만 일하고, 교차점은 **명시적 인터페이스** (SubscriberIndex 조회 등)로 통신.

### 3.6 vssrc의 user 단위 재해석 (rev.2 신규)

**기존 해석 (방 단위)**:
```
PTT_AUDIO_SSRC = 0x50_54_54_A1
→ "이 방의 PTT 채널 vssrc"
```

**개정 해석 (user 단위)**:
```
PTT_AUDIO_SSRC = 0x50_54_54_A1
→ "이 subscriber가 수신 중인 현재 화자 슬롯"
```

**물리 동작 동일, 의미만 전환**. 코드 변경 0.

**결과**:
- Subscriber X의 vssrc 슬롯은 X의 sub PC 하나에 귀속 (방 무관)
- X의 sub_rooms 크기와 무관하게 vssrc m-line = audio 1 + video 1 (기존 그대로)
- **동시 두 방 PTT 수신 불가 = 구조적 정의**. 한 슬롯 = 한 화자

**LMR Scan 방식과 동일**: 수신자는 한 번에 한 채널 active. 사람 귀 인지 한계와 일치.

**Axiom 2 (Subscribe PC single-stream invariant) 자연 보존**: single-stream 의미가 "subscriber 슬롯 1개"로 명확해짐.

### 3.7 기존 프리셋과의 관계

기존 프리셋 대부분은 scope 원소 1개로 자연 표현 (§11.3). 상세는 그룹 F 추후 조정.

### 3.8 Ducking Primitive (rev.2 추가)

> **SDK는 per-publisher gain 제어 primitive만 제공. 더킹 정책(언제/얼마나/누구를)은 도메인 책임.**

**배경**: full + half 혼재 수신 시 "half 치고 들어오면 나머지 duck" 같은 UX 요구 존재. 그러나 full/full/half/full 등 **조합과 정책은 시나리오별로 다름** — SDK가 정책 내장하면 도메인 제약.

**원칙**:
- SDK: per-publisher gain 제어 API만 노출 (클라이언트 Web Audio GainNode 기반)
- 도메인/앱: FLOOR_TAKEN/IDLE 이벤트 수신 + 원하는 정책으로 gain API 호출
- **SDK는 트랙 조합 혼용(full/half 혼재 등)에 관여하지 않는다**

**API 표면 (개념 수준)**:
```javascript
engine.audio(publisherId).setGain(0.2, { rampMs: 200 });
engine.audio(publisherId).gain;  // 조회
```

**대원칙 정합**:
- SFU 변경 0 (클라 Web Audio 로컬 동작)
- SDK dumb 원칙 강화 (정책 안 가짐)
- 도메인이 시나리오 책임

**상세 설계는 본 문서 범위 밖**. SDK API 설계 문서에서 다룸.

---

## 4. 라이프사이클 연산

### 4.1 연산 대칭성

| 레이어 | 추가 | 제거 |
|---|---|---|
| joined_rooms | `join(R)` | `leave(R)` |
| sub_rooms | `affiliate(R)` | `deaffiliate(R)` |
| pub_rooms | `select(R)` | `deselect(R)` |

배치 연산(`SCOPE_UPDATE`, `SCOPE_SET`)은 6개 primitive로 분해.

### 4.2 Join (방 입장)

```
클라 → ROOM_JOIN(R)
server:
  1. 권한 검증 (Hub Extension: moderate 등)
  2. RoomMember 생성 (role, joined_at)
  3. joined_rooms += {R}
  4. 기본 scope 적용 (초기 initial_scope 옵션)
  5. SubscriberIndex 업데이트 (sub_rooms에 추가된 방만)
  6. ROOM_EVENT(joined) 브로드캐스트
  7. server_config + ROOM_SYNC 전달
```

**JOIN 기본 scope**:
- 옵션 A (implicit): `join(R) → sub += {R}, pub += {R}` — 단일 방 기존 동작 호환
- 옵션 B (explicit): `joined_rooms += {R}` 만, scope 변화 0 — 관제 시나리오

**결정: A 기본, `initial_scope: {sub, pub}` 옵션으로 override.**

### 4.3 Leave (방 퇴장)

```
클라 → ROOM_LEAVE(R)
server:
  1. 방 내부 정리 (FloorFsm release 등, 방 레이어)
  2. pub_rooms -= {R}  ← cascade
  3. sub_rooms -= {R}  ← cascade
  4. SubscriberIndex[R].remove(self)
  5. joined_rooms -= {R}
  6. RoomMember 제거
  7. ROOM_EVENT(left) 브로드캐스트
  8. SCOPE_UPDATE 이벤트 (변경 있었으면)
```

**원칙**: scope 정리 후 방 나감 (리소스 역순 해제).

### 4.4 Affiliate / Deaffiliate

```
AFFILIATE(R):
  1. R ∈ joined_rooms 검증
  2. sub_rooms += {R}
  3. SubscriberIndex[R].insert(self)
  4. R의 publisher들 → self에게 SUBSCRIBE_TRACKS 추가 (MidPool 할당)
  5. sub PC transceiver + SDP re-negotiation (coalesce)

DEAFFILIATE(R):
  1. R ∈ pub_rooms이면 자동 cascade: deselect(R) 먼저
  2. sub_rooms -= {R}
  3. SubscriberIndex[R].remove(self)
  4. TRACKS_UPDATE(remove), MidPool 반환
  5. transceiver inactive + re-negotiation (coalesce)
```

### 4.5 Select / Deselect

```
SELECT(R):
  1. R ∈ sub_rooms 검증 (아니면 affiliate 자동 cascade)
  2. pub_rooms += {R}
  3. self의 publish 트랙들 publish_intent에 R 추가
  4. R의 구독자들에게 TRACKS_UPDATE(add, user=self)
  5. floor 상태 불변 (select는 "말할 권리" 추가만)

DESELECT(R):
  1. R의 floor를 self가 보유 중이면 해당 방 floor release (다른 방 무관)
  2. pub_rooms -= {R}
  3. R의 구독자들에게 TRACKS_UPDATE(remove, user=self)
```

**PTT와 Full의 유일한 실질 차이**:
- Full: fan-out 라우팅 중단
- PTT: 해당 방 floor만 release (방별 독립 원칙)

### 4.6 Batch 연산

```json
{
  "op": "SCOPE_UPDATE",
  "d": {
    "change_id": "chg_abc",          // 추적용
    "sub_add":    ["R4", "R5"],
    "pub_add":    ["R4"],
    "pub_remove": ["R1"],
    "sub_remove": ["R2"]
  }
}
```

**서버 처리 순서 (불변식 보존)**:
```
1. sub_add     (새 방 sub 먼저)
2. pub_add
3. pub_remove  (pub 먼저 끊고)
4. sub_remove
```

**Partial Success**: 방별 권한 개별 판정. 실패 방만 제외, 성공 방은 반영.

**구현 검증 요구**:
- 4단계 찰나 불변식 fuzz test
- 동일 user 동시 SCOPE_UPDATE race (Peer 단위 단일 task 처리 권고)
- Cascade 연쇄 crash 일관성

### 4.7 Server-side 강제 변경

| 상황 | 연산 |
|---|---|
| 관리자 kick | forced leave(R) → scope cascade |
| moderate 회수 | forced deselect(R) |
| 방 폐쇄 | 모든 멤버 leave(R) 강제 |
| reconnect | scope 복원 (shadow) |

모든 강제 변경은 `SCOPE_EVENT(cause: ...)` 로 통보.

### 4.8 Cascade 규칙

| 연산 | 자동 cascade |
|---|---|
| `leave(R)` | deselect(R) → deaffiliate(R) → 방 퇴장 |
| `deaffiliate(R)` with R∈pub_rooms | deselect(R) 먼저 |
| `select(R)` with R∉sub_rooms | affiliate(R) 먼저 |
| `deselect(R)` with floor 보유 | 해당 방 floor release |
| Disconnected (SessionPhase) | scope 보존 (reconnect 대비). 20초 Suspect → 35초 leave |

---

## 5. Floor Control — 방별 독립 (rev.2 재작성)

### 5.1 원칙

> **Floor 판정은 방별 독립**. 각 방의 FloorFsm이 자기 시점에 granted/queued/denied 판정.
> **집계 레이어 없음.** Hub/SFU 어느 쪽에도 cross-room 조율자 없음.

### 5.2 왜 방별 독립인가

**대원칙 정합**:
- FloorFsm은 방 레이어 (scope 모름)
- 방별 queue, priority, preemption 모두 기존 로직 그대로

**시간/공간 독립성**:
- R1의 granted 시점 ≠ R2의 granted 시점 (각자 자기 화자 사정)
- 한 트랜잭션으로 묶을 근거 없음 (무전 UX상 자연)

**업계 정합**:
- MCPTT는 per-group floor independence
- LMR Patch도 각 TG 독립 Voice Grant

### 5.3 FLOOR_REQUEST 흐름

```
클라: FLOOR_REQUEST { pub_set_id }
  ↓
서버: set_id → RoomSet 조회 → 각 방 FloorFsm에 Request dispatch
  ↓
각 방별 독립 판정 (기존 로직 그대로):
  R1 → granted (즉시)
  R2 → queued (다른 화자 발화 중)
  R3 → denied (권한 없음 등)
  ↓
각 방별 개별 결과 회신:
  R1 → FLOOR_TAKEN(R1, speaker=self, rooms, via)
  R2 → FLOOR_QUEUED(R2, queue_position)
  R3 → FLOOR_DENIED(R3, reason)
```

**결과는 시간차 도착**. 클라 UI가 각 방 상태 실시간 표시 — 사용자가 상태 보고 priority 상승/재시도 판단.

### 5.4 방별 피드백 스키마

```json
// Granted 시
{
  "op": "FLOOR_TAKEN",
  "room": "R1",
  "speaker": "U123",
  "rooms": ["R1", "R2", "R3"],       // 발화자 pub_rooms (UI "어디 출처")
  "via": "R1"                          // 수신자 관점 경유 방
}

// Queued 시
{
  "op": "FLOOR_QUEUED",
  "room": "R2",
  "position": 2,
  "current_speaker": "V",
  "revokable_with_priority": true      // 우선권 상승 가능성 힌트
}

// Denied 시
{
  "op": "FLOOR_DENIED",
  "room": "R3",
  "reason": "moderate_not_granted"
}
```

### 5.5 FLOOR_TAKEN 전달은 user 단위 (rev.2 재작성)

**기존**: `room.members` 순회 브로드캐스트  
**개정**: `SubscriberIndex[R]` 기반 user 단위 전달

**이유**:
- FLOOR_TAKEN 수신자 = "그 방을 듣는 사람"
- `sub_rooms ∋ R` 인 user만 의미 있음
- room.members에 있지만 sub_rooms에 없는 user는 UI 알림 불필요 (안 듣는 방)

**페이로드 메타**:
- `rooms`: 발화자의 pub_rooms (UI "U가 R1,R2,R3에 송출 중" 표시)
- `via`: 수신자 관점 진입 방 (UI "내 R1에서 들림" 표시)
- 수신자가 pub_rooms ∩ sub_rooms 여러 개일 때 via 여러 개 가능

**RTP와 같은 대상 판정 로직** (§9.2): SubscriberIndex 기반. FLOOR_TAKEN 전달과 RTP fan-out 대상 일치 → UI/미디어 동기 보장.

### 5.6 우선순위 / Preemption

**정책**:
- 우선권 상승 요청 = 기존 방별 FloorFsm의 preemption 경로 재사용
- 사용자가 UI에서 "R2에 우선권으로 재요청" → `FLOOR_REQUEST { pub_set_id, priority: high, target_rooms: [R2] }` 또는 전체 재요청
- preemption 권한/대상 선정은 방 단위 기존 로직

**변경 없음**. 방 단위 FloorFsm이 알아서 처리.

### 5.7 중간 진입

U가 R1 granted로 발화 중, R2가 나중에 queued → granted 되면 U는 R2에도 송출 시작. R2 수신자는 **문장 중간부터** 수신.

**처리**: "무전/multi-room의 본질" 로 수용. LMR Scan/Patch도 동일. UI가 FLOOR_TAKEN(R2)로 "U가 R2에 합류" 명시.

오디오는 연속, 비디오는 PLI burst로 I-frame 요청.

---

## 6. Hub의 역할 — scope 무관 유지

### 6.1 원칙

> sfud가 상태 마스터 (Room/Participant/Floor + 미디어 엔진).  
> Hub는 투명 프록시 + 정책 Extension.

### 6.2 Scope가 Hub에 추가 로직 부과하나?

**rev.1 설계**: Hub Extension `scope_coordinator` (집계 + 정책 적용).  
**rev.2 수정**: **불필요.**

이유:
- Floor 판정이 방별 독립 (집계 레이어 없음)
- 방별 결과가 직접 클라에 전달
- Hub는 기존처럼 passthrough 유지

**scope_coordinator 취소.** moderate Extension만 기존대로 동작.

### 6.3 왜 Hub에 Floor 안 올리나

1. Hot path 이탈 = PTT 레이턴시 재앙
2. 분산 트랜잭션 지옥
3. Hub 장애 blast radius 폭발

(rev.1 §6.4 동일, 기각된 접근 계승)

---

## 7. SFU 다중화 (Phase 2)

본 문서는 단일 SFU 내 scope에 집중. SFU-SFU relay는 Phase 2 (cross-room federation 합류).

**Phase 2 의존 항목**:
- SFU-SFU relay channel 수립
- Hub routing plane 승격
- Cross-SFU scope 집계

Phase 1 설계에서는 "나중에 집계 가능한 구조" 예비만 (Peer.sub_rooms 변경 시 Hub 훅 남김, Phase 2 활성화).

---

## 8. 시그널링 프로토콜 변경

### 8.1 추가 op

| op | 이름 | 방향 | d |
|---|---|---|---|
| 53 | SCOPE_UPDATE | C→S | `{change_id?, sub_add, sub_remove, pub_add, pub_remove}` |
| 54 | SCOPE_SET | C→S | `{sub: [...], pub: [...]}` (diff로 분해) |
| 107 | SCOPE_EVENT | S→C | `{sub_set_id, pub_set_id, sub, pub, cause, change_id?}` |

**cause**: `"user"` / `"moderate"` / `"kick"` / `"room_closed"` / `"implicit"` / `"reconnect_restore"`

### 8.2 기존 op 변경

| op | 변경 |
|---|---|
| 11 ROOM_JOIN | `initial_scope: {sub: bool, pub: bool}` 옵션 (기본 `{true, true}`) |
| 12 ROOM_LEAVE | scope cascade 처리 (클라 투명) |
| 15 PUBLISH_TRACKS | (변경 없음 — 트랙 단위 scope override는 Phase 2) |
| 101 TRACKS_UPDATE | `target_rooms`, `via` 필드 추가 (UI 메타) |

### 8.3 Floor 관련

| op | 변경 |
|---|---|
| FLOOR_REQUEST | `pub_set_id` 필드 추가 (set_id 참조), `scope` 배열 사용 안 함 |
| FLOOR_TAKEN | `rooms`, `via` 필드 추가 (발화자 pub_rooms, 수신자 경유 방) |
| FLOOR_QUEUED | 방별 개별 이벤트, `position`, `current_speaker` 등 |
| FLOOR_DENIED | 방별 개별 이벤트, `reason` |

**set_id 참조**: 페이로드 경량화. 1000방 시나리오에서도 페이로드 일정.

---

## 9. 서버 내부 구조

### 9.1 SubscriberIndex (rev.2 신규)

**목적**: Fan-out 핫패스에서 방 순회 제거, user 단위 직접 조회.

```rust
// DashMap 기반 역인덱스
SubscriberIndex: DashMap<RoomId, DashSet<Arc<Peer>>>
```

**갱신 타이밍** (scope 변경 시):
```rust
fn affiliate(peer: &Peer, r: RoomId) {
    peer.sub_rooms.insert(r);
    subscriber_index.get_mut(&r).insert(peer.clone());
}

fn deaffiliate(peer: &Peer, r: RoomId) {
    peer.sub_rooms.remove(r);
    subscriber_index.get_mut(&r).remove(peer);
}
```

**조회** (fan-out 핫패스):
```rust
fn fan_out_receivers(publisher: &Peer) -> Vec<Arc<Peer>> {
    publisher.pub_rooms.load().iter()
        .flat_map(|r| subscriber_index.get(r).iter().cloned())
        .filter(|x| x.user_id != publisher.user_id)  // 자기 제외
        .collect::<HashSet<_>>()                      // union (중복 제거)
        .into_iter()
        .collect()
}
```

**원자성**: scope 변경 시 ArcSwap 교체 + SubscriberIndex 업데이트가 동일 tick 내. coalesce (§9.3)와 통합.

**비용**:
- 메모리: 방 수 × 평균 sub 수. 1000방 × 30명 = 30,000 엔트리 (가벼움)
- 쓰기: scope 변경 시만 (핫패스 대비 저빈도)
- 읽기: DashMap O(1) + HashSet union

### 9.2 RTP Fan-out은 user 단위 (rev.2 재작성)

**기존 (방 순회)**:
```
for room in publisher.pub_rooms:
  for member in room.members:
    if member.sub_rooms ∋ room:
      send(member)
```

**개정 (SubscriberIndex 기반)**:
```
receivers = fan_out_receivers(publisher)   // SubscriberIndex union
for X in receivers:
  if X.vssrc_slot.available_or_owned_by(publisher):
    rewrite_and_send(publisher.rtp → X.vssrc)
    X.vssrc_slot.claim(publisher)
  else:
    drop  // X가 다른 화자 수신 중
```

**핵심**:
- 방 개념이 fan-out 로직에서 사라짐
- "같은 화자가 계속 보내는 동안" vssrc 슬롯 점유 유지
- 다른 화자 RTP가 오면 슬롯 점유자 확인 → 기존 화자 유지, 신규 drop

**vssrc 슬롯 관리**:
```rust
struct VssrcSlot {
    current_owner: ArcSwap<Option<PublisherRef>>,
    // publisher 발화 종료 (floor release 또는 silence flush) 시 clear
}
```

발화 종료 시 slot clear, 다음 화자 claim 가능.

**Publisher 자기 제외**: 발화자 본인이 subscriber 집합에 있을 수 있음 (pub ⊆ sub 모델에서). `X.user_id != publisher.user_id` 체크.

### 9.3 원자성 + Coalesce (rev.1 유지)

Scope 변경 + SubscriberIndex 업데이트 + re-nego를 원자 묶음으로:

```rust
async fn renego_coalesce_loop() {
    loop {
        tokio::time::sleep(policy.scope.coalesce_interval_ms).await;
        let pending = coalesce_queue.drain();
        for user_id in pending {
            let peer = get_peer(user_id);
            if peer.pending_renego.swap(false, Ordering::AcqRel) {
                tokio::spawn(perform_renego(peer));
            }
        }
    }
}
```

**Policy**:
```toml
[scope.coalesce]
interval_ms         = 50
max_batch_users     = 200
renego_timeout_ms   = 5000
```

**벤치 기준**: 1000명 방 폐쇄 시 1초 내 모든 re-nego 완료. Storm 테스트 10배 감소 검증.

### 9.4 STALLED 관측은 user 단위 (rev.2 신규)

**원칙**:
> **방별 packets_sent 관측 폐기.** User 단위 관측으로 대체.
> **STALLED checker는 scope를 모른다.** 정당사유는 관측 가능한 사실 기반.

**기존**:
```
for room in rooms:
  for (member, track) in room.tracks:
    if packet_count_at_ack delta == 0 for 5s: STALLED
```

**개정**:
```
for subscriber X:
  if X.packets_received_delta == 0 for 5s:
    justified = (
      X.vssrc_slot.occupied_by_other or    // 다른 화자 수신 중
      X.fan_out_publishers.is_empty() or   // 나에게 보낼 publisher 0명
      X.mute or
      ...기존 정당사유
    )
    if !justified: STALLED
```

**정당사유 확장** (관측 사실 기반, scope 조회 불필요):
- `X.vssrc_slot.occupied_by_other`: 슬롯 관측 상태
- `X.fan_out_publishers.is_empty()`: SubscriberIndex 역조회로 관측 가능
- 기존 사유 (mute, floor 없음 등) 그대로

**scope 컨텍스트 접근 불필요**: 관측 가능한 팩트가 있으면 추론 안 함.

**agg-log**:
```
subscriber:idle_normal user=X reason=vssrc_slot_occupied by=U123
subscriber:idle_normal user=X reason=no_publishers
subscriber:stalled    user=X (정당사유 모두 해당 없음)
```

### 9.5 Admin 뷰 — 축 분리 (rev.2 재작성)

**원칙**:
> 방 뷰는 방 정보만. User 뷰(신규)는 user 정보만. 축 혼재 제거.

**방 뷰** (기존 유지):
- 참가자 목록 (user_id, phase)
- FloorFsm 상태 (현재 화자, queue)
- 트랙 메타 (kind, duplex, publish_intent)
- 방 단위 설정

**User 뷰** (신규):
```json
{
  "user_id": "U123",
  "phase": "active",
  "joined_rooms": ["R1", "R2", "R3"],
  "sub_rooms": {
    "set_id": "sub-U123-17",
    "rooms": ["R1", "R2"]
  },
  "pub_rooms": {
    "set_id": "pub-U123-5",
    "rooms": ["R1"]
  },
  "vssrc_slot": {
    "audio": { "owner": "V456", "since": "..." },
    "video": { "owner": null }
  },
  "packets_received_delta": 125,
  "packets_sent_delta": 0,        // publisher면 집계
  "active_publishers": ["V456"],  // fan_out_publishers
  "mid_pool": { "audio_active": 3, "audio_recycled": 1, ... }
}
```

**agg-log 이벤트** (scope 추적):
- `scope:changed user=U change_id=c1 cause=user sub_delta=+R5 pub_delta=+R5`
- `scope:coalesced user=U change_id=[c1,c2] merged=2`
- `scope:reconnect_restore user=U set_ids=[sub-U-3, pub-U-1]`
- `subscriber_index:updated room=R changed_user=U op=add`

**set_id는 AI 오독 방지 핵심 시그널**: set_id 있으면 scope 모델 컨텍스트 → packets=0, vssrc 슬롯 상태 등 자동 정상 해석 가능.

### 9.6 자원 상한 (policy.toml)

```toml
[scope]
max_joined_rooms        = 20
max_sub_rooms           = 15
max_pub_rooms_ptt       = 5
max_pub_rooms_full      = 3
```

**수치는 추측값, 1000인 벤치 전 잠정**. 실측 기반 조정.

### 9.7 Shadow 복구

Hub `shadow/` 모듈에 scope + set_id 포함. Reconnect 시 Peer 재구성 후 `SCOPE_EVENT(cause: "reconnect_restore")` 통보.

---

## 10. 열린 질문

### 10.1 A1 — 불변식 완화 ⭐ 가장 중요

**Q**: `pub ⊆ sub` 강제 vs `pub, sub ⊆ joined_rooms` 독립?

**강제 (MCPTT 준용)**:
- 장점: 대화 UX 일관성, 규칙 단순
- 단점: CCTV/드론 "송출만" 시나리오 지원 불가

**독립**:
- 장점: 방송/감시 시나리오 기본 지원, server-side recording 자연
- 단점: 규칙 추가, UX 가드레일 SDK 상위 책임

**기술적 관찰**:
MCPTT가 Selection ⊆ Affiliation 강제한 이유는 **UX 인지 안전**. 이는 UX 계층 원칙이지 라우팅 계층 원칙이 아님.

OxLens 원칙 "SFU/SDK = dumb and generic / UX 가드레일은 상위"에 따르면:
- 라우팅 계층: 독립 모델 유지
- UX 계층: SDK UI 헬퍼에서 경고/아이콘

**김대리 권고**: 독립 모델 + SDK UX 경고. 이유:
1. 기존 설계 원칙(SFU/SDK dumb)과 일관
2. 미래 시나리오(recording/broadcasting) 흡수
3. UX 안전은 상위 레이어 책임

**결정 부장님 영역**. DRAFT 유지.

### 10.2 A4 — Cross-SFU 예비 구조

Phase 2 SFU-SFU relay 대비 `Peer.sub_rooms` 변경 시 Hub 훅 남김. 지금 Hub는 무시, Phase 2 활성화.

### 10.3 B1 — Scope 지속성

**결정**: 세션 수명 기본. 프로필 영속은 앱 레이어(JWT claim, 외부 DB). Hook system에 `scope.changed` webhook 포함.

### 10.4 B4 — Moderate 상호작용

Moderate grant = implicit select. `SCOPE_EVENT(cause: "implicit")` 로 UI 구분.

송출 조건 (3중 AND):
```
R ∈ pub_rooms 
  AND moderate.is_granted(U, R) 
  AND (duplex=full OR floor_held(R))
```

**pub_rooms가 moderate 결과 반영**: grant 시 자동 추가, revoke 시 제거. Fan-out 판정 로직 변경 없음 (기존 AND 자연 성립).

### 10.5 B5 — SDK 공개 API 명명

후속 문서 `20260424_scope_sdk_api_design.md`. 본 설계는 내부 용어만.

### 10.6 B7 — 트랙별 scope override

Phase 1: user 단위만. Phase 2에서 트랙 override. 시나리오 B(half+full 혼재) 지원은 Phase 1 축소 버전(PUBLISH_TRACKS에 `publish_scope`) 검토 가능 — §15.2 참조.

### 10.7 조사 필요

| ID | 항목 | 영향 |
|---|---|---|
| C1 | sctp-proto 0.9.0 scope-aware MBCP | DC 구현 |
| C2 | Peer 재설계 Step F 실제 상태 | 리팩터 순서 |
| C3 | cross-room federation rev.2 정합성 | Phase 2 |

---

## 11. 마이그레이션 / 하위호환

### 11.1 기존 단일 방 동작

- JOIN 기본 `{sub: true, pub: true}` → 100% 기존 동작
- scope 패킷 미사용 클라 → scope = `{current_room}` 원소 1개
- FLOOR_REQUEST에 `pub_set_id` 미포함 → 기본 set (= current pub_rooms)
- SubscriberIndex는 내부 자료구조 (클라 불가시)

### 11.2 점진 도입 순서

1. **Step 1**: Peer 재설계 F 완료 + Peer에 `pub_rooms`, `sub_rooms`, `set_id` 필드 추가 (초기 `{current}`)
2. **Step 2**: SubscriberIndex 구축 + fan-out 로직 교체 (기능 변화 0, 구조만)
3. **Step 3**: SCOPE_UPDATE/SCOPE_EVENT op + coalesce
4. **Step 4**: FLOOR_REQUEST set_id 확장, FLOOR_TAKEN user 단위 전달
5. **Step 5**: STALLED 관측 user 단위 전환
6. **Step 6**: Admin User 뷰 추가
7. **Step 7**: SDK `affiliate/select` API
8. **Step 8**: Phase 2 SFU-SFU relay

각 Step 기존 E2E 통과 유지.

### 11.3 데모 시나리오 영향

- **conference, voice_radio, video_radio, support**: 영향 0 (scope 1원소)
- **dispatch, moderate**: 향후 조정 (그룹 F 보류, 프리셋 스키마 추후)

**프리셋 재정의는 본 문서 범위 밖**. 별도 조정.

---

## 12. 결정 사항 요약

| # | 결정 | 근거 |
|---|---|---|
| 1 | 용어 `pub_rooms` / `sub_rooms` / `joined_rooms` | RoomId 타입과 직관 일치, joined_rooms와 통일성 |
| 2 | **set_id 부여** | 추적/페이로드 경량화, LMR SAID 선례 |
| 3 | **대원칙: 방/트랙은 scope 모름, 필요시 scope 등장** | 레이어 분리, 기존 자산 보존 |
| 4 | **vssrc user 단위 재해석** | Axiom 2 보존, LMR Scan 정합 |
| 5 | JOIN 기본 `{sub: true, pub: true}` | 100% 하위호환 |
| 6 | Cascade 자동 | API 일관성 |
| 7 | Batch 연산 partial success | MCPTT, 무전 UX |
| 8 | **Floor 판정 방별 독립** | 집계 레이어 불필요, 기존 FloorFsm 보존 |
| 9 | **SubscriberIndex 도입** | Fan-out user 단위, 방 순회 제거 |
| 10 | **FLOOR_TAKEN 전달 user 단위** | RTP와 대상 일치, UI 일관성 |
| 11 | Scope ArcSwap | 원자성, policy.toml 패턴 |
| 12 | Re-nego coalesce 50ms | storm 방어 |
| 13 | **STALLED user 단위, scope 무관** | 관측 사실 기반 판정 |
| 14 | **Admin 뷰 축 분리 (방/User)** | 혼재 제거, 디버깅 명확 |
| 15 | 세션 수명 scope | SDK dumb 원칙 |
| 16 | SFU-SFU relay Phase 2 | Phase 1은 예비 |
| 17 | 트랙 override Phase 2 | YAGNI (시나리오 B 예외) |
| 18 | **Hub scope_coordinator 불필요** | 방별 독립 판정, 집계 없음 |
| 19 | 자원 상한 policy.toml | 1000인 검증 의무 |

---

## 13. 다음 단계

### 13.1 리뷰 항목

- [ ] §10.1 (A1) — 불변식 완화 결정 (부장님)
- [ ] §10.5 (B5) — SDK API 명명 (별도 문서)
- [ ] §10.7 (C1/C2/C3) — 조사 후 재확인

### 13.2 후속 문서

- `20260424_scope_sdk_api_design.md` — SDK 공개 API
- `20260425_scope_server_impl_plan.md` — Step 1-8 구현 상세
- `2026MMDD_scope_phase2_sfu_relay.md` — Phase 2

### 13.3 Gemini 리뷰 권고

- MCPTT/LMR 해석 정확성
- 불변식 완화 케이스
- ArcSwap + SubscriberIndex hot path
- Coalesce edge case (zombie + scope 겹침)
- vssrc 슬롯 재해석 동의 여부

---

## 14. 부록 — 시퀀스 다이어그램 (rev.2 재작성)

### 14.1 Affiliate 성공

```
X가 R2에 새로 subscribe (joined_rooms ∋ R2 이미 있음)

 클라(X)       Hub          sfud                   R2 publishers    SubscriberIndex
   │            │             │                        │                  │
   ├─AFFILIATE(R2)─>            │                        │                  │
   │            ├─passthrough─>│                         │                  │
   │            │             │  1. joined_rooms ∋ R2 검증                 │
   │            │             │  2. sub_rooms += {R2} (ArcSwap)             │
   │            │             │  3. SubscriberIndex[R2].insert(X) ───────> │
   │            │             │  4. R2 publisher 조회                       │
   │            │             │  5. MidPool 할당 (per-subscriber)           │
   │<─TRACKS_UPDATE(add)─────────                                          │
   │   target_rooms=[R2]      │                                              │
   │            │             │                                              │
   │  [SDP re-nego, coalesce 경유]                                          │
   │            │             │                                              │
   ├─SDP offer─>│─────────────>│                                              │
   │<───answer──┤<─────────────┤                                              │
   │            │             │                                              │
   │  [ICE/DTLS 새 m-line]      │                                              │
   │            │             │  6. RTP fan-out 시작                         │
   │<═══════════════════════════│═════ RTP ═════                              │
   │            │             │                                              │
   │<─SCOPE_EVENT(cause=user)──                                              │
   │  sub_set_id, sub=[..,R2] │                                              │

핵심:
  - ArcSwap 원자 교체 (§9.3)
  - SubscriberIndex 업데이트로 fan-out 대상 즉시 반영
  - MidPool은 per-subscriber 기존 방식 (변경 없음)
```

### 14.2 FLOOR_REQUEST 방별 독립 판정

```
U의 pub_rooms = {R1, R2, R3}, PTT 버튼 누름
R2는 V가 이미 발화 중, R3은 권한 없음

 클라(U)      sfud           R1.FloorFsm  R2.FloorFsm  R3.FloorFsm  SubscriberIndex
   │           │                │            │            │              │
   ├─FLOOR_REQUEST──────>        │            │            │              │
   │  pub_set_id=pub-U-5│        │            │            │              │
   │           │                │            │            │              │
   │           │  set_id → RoomSet 조회       │            │              │
   │           │  → {R1, R2, R3} 추출          │            │              │
   │           │                │            │            │              │
   │           ├─Request(U)────>│            │            │              │
   │           ├─Request(U)─────────────────>│            │              │
   │           ├─Request(U)──────────────────────────────>│              │
   │           │                │            │ (V 발화중) │  권한 체크   │
   │           │                │            │            │              │
   │           │<─Granted───────┤            │            │              │
   │           │<─Queued(pos=1)──────────────┤            │              │
   │           │<─Denied(no_permission)──────────────────┤              │
   │           │                │            │            │              │
   │<─FLOOR_TAKEN(R1)───────────                                          │
   │   speaker=U, rooms=[R1,R2,R3], via=R1                                │
   │<─FLOOR_QUEUED(R2, pos=1, revokable=true)                            │
   │<─FLOOR_DENIED(R3, moderate_not_granted)                             │
   │           │                │            │            │              │
   ├─RTP 송출 시작─>│           │            │            │              │
   │           │                │            │            │              │
   │           │  fan_out_receivers:        │            │              │
   │           │    SubscriberIndex[R1] (R2,R3 granted 아님) ──> user 집합│
   │           │  각 X에 대해 vssrc 슬롯 확인 → rewrite & send           │
   │           │                │            │            │              │
   │           │═══> R1 수신자들 (X in SubscriberIndex[R1])               │
   │           │                │            │            │              │
   │           │         ...V 발화 종료...                 │              │
   │           │<─Idle──────────────────────┤            │              │
   │           │  R2.FloorFsm queue promote → U granted  │              │
   │<─FLOOR_TAKEN(R2)───────────                                          │
   │   speaker=U, rooms=[R1,R2,R3], via=R2                                │
   │           │═══> R2 수신자들도 합류 (fan-out 대상 확장)               │
   │           │                │            │            │              │

핵심:
  - 방별 FloorFsm 완전 독립 (집계 없음)
  - 각 방 결과 시간차 도착
  - Fan-out 대상은 granted 방의 SubscriberIndex union
  - FLOOR_TAKEN/RTP 대상 일치 (둘 다 SubscriberIndex 기반)
  - 중간 진입(R2 늦게 합류) 자연 발생, UI가 FLOOR_TAKEN(R2)로 알림
```

---

## 15. 부록 — 시나리오 매핑

### 15.1 시나리오 A — half × 2방

**기존 실패**: 단일 방 PTT 전제라 multi-room에서 floor/track 꼬임.

**Scope 모델**:
```
U:
  joined_rooms = {R1, R2}
  sub_rooms    = {R1, R2}, set_id=sub-U-1
  pub_rooms    = {R1, R2}, set_id=pub-U-1
  audio.duplex = half, video.duplex = half

PTT 버튼:
  FLOOR_REQUEST { pub_set_id: "pub-U-1" }
  → R1 granted, R2 granted (둘 다 비어있음)
  → U의 RTP = SubscriberIndex[R1] ∪ SubscriberIndex[R2] 대상 fan-out

U 수신자 X (sub_rooms ∋ R1):
  X의 vssrc_slot 비어있음 → claim → 수신 시작
  X의 FLOOR_TAKEN(R1) 수신 → UI "R1에서 U 발화"
```

**기존 대비 깔끔**:
- "PTT 모드" 개념 없음 (pipe.duplex 자연 분기)
- 방별 FloorFsm 독립으로 충돌 없음
- SubscriberIndex 기반 user 단위 fan-out
- 특수 분기(`isFirstJoin`, `_hasFullPublish`) 불필요

### 15.2 시나리오 B — half + full 혼재

**기존 실패**: 방=duplex 속성 혼동.

**Scope 모델 (Phase 1 한계)**:
```
U 트랙:
  Track A (audio, half)  — PTT용
  Track B (audio, full)  — Conference용
  Track C (video, full)  — Conference용

U:
  pub_rooms = {R1, R2}  (user 단위)
```

**Phase 1 문제**: user 단위 pub_rooms면 모든 트랙이 모든 방에 송출 → A가 R2에도, B/C가 R1에도.

**해결**: PUBLISH_TRACKS 시점 per-track `publish_scope` 명시 (축소 버전, Phase 1 포함 가능):
```json
{
  "tracks": [
    { "id": "audio_ptt",  "duplex": "half", "publish_scope": ["R1"] },
    { "id": "audio_conf", "duplex": "full", "publish_scope": ["R2"] },
    { "id": "video_conf", "duplex": "full", "publish_scope": ["R2"] }
  ]
}
```

`publish_scope ⊆ user.pub_rooms` 제약. 보안상 user 권한 넘어선 송출 방지.

**결정 필요**: Phase 1 포함 vs Phase 2 연기.

### 15.3 교훈

두 시나리오 모두 **특수 분기 → 기본 primitive 자연 조합**으로 전환.
- A: 완전 해결 (Phase 1)
- B: per-track publish_scope 필요 (Phase 1 축소 또는 Phase 2)

Scope 모델 도입의 정당성 근거.

---

## 16. 부록 — 대원칙 적용 매트릭스

| 레이어/컴포넌트 | scope 관여 | 기존 로직 변경 |
|---|---|---|
| Room.members (참여 메타) | 모름 | 없음 |
| FloorFsm (방별 상태/판정) | 모름 | 없음 |
| 트랙 duplex 속성 | 모름 | 없음 |
| MidPool (per-subscriber) | 모름 | 없음 |
| PttRewriter | 모름 | 없음 |
| SimulcastRewriter | 모름 | 없음 |
| STALLED checker | 모름 | 관측 단위 user로 전환 |
| ROOM_SYNC | 모름 | 없음 |
| Peer | user scope 소유 | 필드 추가 |
| SubscriberIndex | 역인덱스 관리 | 신규 |
| Fan-out 로직 | SubscriberIndex 조회 | 방 순회 → user 직접 |
| FLOOR_TAKEN 전달 | SubscriberIndex 조회 | 방 순회 → user 직접 |
| vssrc 슬롯 관리 | user 단위 | 신규 |
| SCOPE_UPDATE/EVENT | 본질 | 신규 |
| Admin 방 뷰 | 없음 | 일부 지표 user 뷰로 이동 |
| Admin User 뷰 | 본질 | 신규 |
| agg-log scope:* | 본질 | 신규 |
| Hub (moderate Ext 외) | passthrough | 없음 |
| sfud 상태 마스터 역할 | 유지 | 없음 |

**방/트랙 레이어는 15개 항목 중 scope 직접 관여 0.**  
**Scope는 8개 신규/확장 지점에만 등장.**

---

*author: kodeholic (powered by Claude)*  
*rev.2 — 그룹 A~E 해결 반영. 대원칙 "방/트랙은 scope 모름, 필요시 scope 등장" 확정. §10.1 불변식 결정 대기 중 DRAFT.*
