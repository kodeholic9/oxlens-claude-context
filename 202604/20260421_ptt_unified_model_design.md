# PTT Unified Model — Subscribe Slot Pre-allocation + Universal SSRC + Axiom 3

> author: kodeholic (powered by Claude)
> date: 2026-04-21
> status: draft (Peer 재설계 F3 완료 후 구현)

---

## 0. 배경

현재 구조:
- PTT half-duplex 트랙은 `PttRewriter`가 publisher 원본 SSRC → virtual SSRC로 리라이팅
- Subscribe PC의 PTT 트랙은 **첫 발화자 등장 시 TRACKS_UPDATE(add) → subscriber SDP 재협상**
- 발화자 퇴장 / 마지막 half-duplex 보유자 퇴장 시 **virtual track remove → 또 재협상**
- 잔존자 체크 로직(`participant leave zombie 양 경로`) 으로 영구 미표시 버그 방어 중

문제:
- PTT가 발생하는 매 순간마다 subscribe 측 SDP 비용
- remove 시점 잔존자 체크 로직의 복잡도
- cross-room federation 진입 시 방별 slot 관리 복잡도 증가 예상

---

## 1. 핵심 아이디어

**Subscribe SDP에 PTT recvonly slot (audio + video) 을 방 기본 2개 pre-allocate.**

- 방 생성 시점에 slot mid 2개 예약
- Virtual SSRC 는 **universal 고정값** (전 방, 전 서버 공통)
- Codec 고정 (Opus PT=111, VP8 PT=96)
- 참가자 0명인 빈 방에도 slot 존재

Publish 측은 **현행 유지** — simulcast / codec 다양성 때문에 on-demand publish. SWITCH_DUPLEX half→full 시 publish add re-nego 는 불가피.

즉 **Subscribe PC 관점에서 PTT는 SDP-invariant**. add/remove 재협상 소멸.

---

## 2. Axiom 3개

설계의 공리. 이후 모든 파생 기능은 이 3개로 환원 가능.

### Axiom 1 — All-or-Nothing atomic grant
```
Publisher가 multi-destination 요청 시,
  모든 destination 이 idle 일 때만 atomic grant.
  하나라도 busy 이면 전체 NACK.

Destination 단위:
  - Room (단일 방 / 다방 발언)
  - User (1:1 귓속말)
  - 혼합 (경찰청장이 여러 방 + 특정 user 동시)
```

### Axiom 2 — Subscribe PC 당 1 stream 불변식
```
임의 시점에 한 Subscribe PC 로 flowing 하는 PTT stream 은 최대 1개.

이 불변식은:
  - Universal SSRC 안전성 보장 (세션 내 SSRC 중복 원천 차단)
  - Axiom 1 의 귀결 (atomic grant → 동시 다발화 불가)
  - mixing 불필요 (3GPP MCPTT 와 결정적 차별점)
```

### Axiom 3 — Priority override (emergency preempt)
```
Axiom 1 의 정당한 우회로.
높은 priority 요청은 destination 의 낮은 priority 점유자를 preempt 하고 atomic grant.

Priority 값 자체는 도메인에서 정의 (경찰청장 / 행안부장관 / 지휘관).
SFU 는 u8 비교만. 도메인 의미 모름.
```

---

## 3. 자연 파생 기능 (설계 확장은 Phase 기준)

Axiom 3개에서 다음 기능이 **코드 추가 없이 또는 최소 변경으로** 성립:

| 기능 | 근거 | Phase |
|------|------|-------|
| 채널 스캔 (Listen filter) | Axiom 2 + fan-out 필터 | Phase 2 |
| 다방 발언 (Multi-room speak) | Axiom 1 destination=rooms | Phase 2 |
| 1:1 귓속말 (Whisper) | Axiom 1 destination=user | Phase 2 |
| 긴급발언 | Axiom 3 직접 | Phase 1 (기존 구현 재사용) |
| Cross-SFU priority federation | Axiom 1 + 2PC + priority | Phase 3 (2027~) |
| 지휘 브로드캐스트 | Axiom 3 + destination=all | Phase 3 |

---

## 4. Phase 1 구현 설계 (단일 SFU)

### 4.1 Subscribe slot pre-allocation

#### 4.1.1 상수 정의
```rust
// common/src/constants.rs (신규 또는 config.rs 추가)
pub const PTT_AUDIO_SSRC: u32 = 0x50_54_54_A1; // "PTT\xA1"
pub const PTT_VIDEO_SSRC: u32 = 0x50_54_54_B1; // "PTT\xB1"
pub const PTT_AUDIO_RTX_SSRC: u32 = 0x50_54_54_A2;
pub const PTT_VIDEO_RTX_SSRC: u32 = 0x50_54_54_B2;

pub const PTT_AUDIO_MID: &str = "ptt-audio"; // reserved mid
pub const PTT_VIDEO_MID: &str = "ptt-video";
```

#### 4.1.2 Room 생성 시 slot 주입
- `Room::new()` 또는 startup 시나리오 방 생성 경로
- Room 에 `ptt_slots: PttSlots` 필드 추가 (보조 정보, 조회용)
- Subscribe SDP 조립 시 항상 recvonly m-line 2개 포함

#### 4.1.3 MidPool reserved 처리
- `SubscribeContext::sub_mid_pool` 에서 PTT_AUDIO_MID / PTT_VIDEO_MID 를 **reserved** 로 분리
- `assign_subscribe_mid()` 호출 시 reserved mid 는 할당 대상에서 제외
- `release_stale_mids()` 호출 시 reserved mid 는 skip
- 구현 지점: `participant.rs` (Step F 이후 `peer.subscribe` 로 이주됨)

#### 4.1.4 server_config 전달
- `/rooms/:id/join` REST 응답에 PTT slot 정보 포함
- 클라이언트 assignMids 는 서버 passthrough (현행 유지 — 추가 구현 0)

### 4.2 Universal SSRC 전환

#### 4.2.1 PttRewriter 변경
- virtual SSRC 생성 로직 제거 (publisher 단위 생성 → universal 상수)
- `ptt_rewriter.rs` — `virtual_audio_ssrc`/`virtual_video_ssrc` 필드 삭제, 상수 참조
- 리라이팅 경로 동일 (SSRC 변환 대상만 고정값으로)

#### 4.2.2 Publisher SSRC 충돌 방어
- `register_nonsim_tracks` / `register_simulcast_tracks` 진입 시 publisher 원본 SSRC 가 PTT universal 값과 충돌 시 **reject + agg-log**
- 실질 확률 2^-32, 안전망만 구축

#### 4.2.3 RTCP Terminator 경로 영향 평가
- Subscribe RR 은 universal SSRC 기준 → **SFU 송신 통계 로만 사용** (publisher 에 릴레이 X, 기존 원칙 유지)
- Publisher SR 은 원본 SSRC 기준 → ingress RTCP 경로 영향 0
- 즉 기존 RTCP Terminator v1 원칙 **변경 없음**

### 4.3 "잔존자 체크" 로직 제거

기존 `handle_room_leave` / `reap_zombies` 의 half-duplex 잔존자 체크 코드 삭제:
- slot 은 방에 영구 고정 → remove 이벤트 자체가 발생하지 않음
- subscriber SDP 영향 없음
- `track_ops.rs` / `room_ops.rs` 의 virtual track remove 보호 분기 삭제

### 4.4 STALLED 예외 정리

`kf_pending` / "PTT floor 없음" 정당사유가 **평상 상태**로 승격:
- slot 있음 + 발화자 없음 = 정상 (RTP 흐름 없는 상태)
- STALLED 판정 대상에서 PTT slot 자체가 제외되거나, 판정 로직이 "slot 점유자 있을 때만" 로 단순화
- 구현 지점: `tasks.rs` stalled_checker

### 4.5 Floor state 수용

Axiom 1 구현 — `FloorController` 확장 준비:
- **Phase 1 에서는 기존 단일 방 grant 로직 유지** (destination = 현재 방 1개)
- 단 API 는 multi-destination 받을 수 있도록 `grant(destinations: Vec<FloorTarget>)` 형태로 확장 가능하게 시그니처 설계
- 실제 multi-destination 동작은 Phase 2

---

## 5. Phase 2 확장 (Multi-destination + Listen filter)

### 5.1 Listen filter (채널 스캔)
- Participant 에 `listen_rooms: RwLock<HashSet<RoomId>>` 필드
- 기본값 = 자신이 속한 방 전체
- 신규 op `PTT_LISTEN_FILTER { rooms: [...] }` — hub 경유 sfud 반영
- fan-out 경로에 `listen_rooms.contains(publisher.origin_room)` 체크 1줄

### 5.2 Multi-room speak
- `FLOOR_REQUEST` 에 `destinations: Vec<FloorTarget>` 필드 추가
- `FloorController::try_grant_atomic(destinations, priority)` — 2PC prepare/commit 패턴
- Prepare 실패 시 즉시 NACK
- Commit 성공 시 FLOOR_TAKEN 각 방 broadcast

### 5.3 Whisper (1:1)
- `FloorTarget::User(UserId)` variant 추가
- Fan-out 경로에 `target == subscriber.user_id` 체크
- Floor state 는 `HashMap<FloorTarget, FloorState>` 로 일반화

---

## 6. Phase 3 확장 (Cross-SFU federation) — 참고용

2PC coordinator 는 hub orchestrator 로:
```
총지휘자 → Hub → sfud-A/B/C 에 prepare 병렬
  모두 OK → commit → atomic grant
  하나라도 NO → abort
```

Universal SSRC 이 cross-SFU relay 에서 변환 불필요 (동일값 유지).

구현은 단일 SFU 레퍼런스 확보 후 2027~2028 착수.

---

## 7. MCPTT 와의 차별점

3GPP MCPTT (TS 23.379 / 24.379) 는 IMS/SIP 기반으로 다음 제약이 있음:

| 요구 | MCPTT 우회 | OxLens Axiom |
|------|-----------|--------------|
| Multi-talker control | **media mixing** (TS 23.379 §7) | Axiom 2 단일 stream → mixing 불필요 |
| Multi-group transmit (NPSTC) | **Group Regroup** (임시 그룹 합치기) | Axiom 1 atomic multi-destination |
| Private call | 별도 SIP 세션 | Axiom 1 destination=user |
| Broadcast (단방향) | Broadcast Group | Axiom 3 destination=all |
| Current talker monitor | SIP 세션 per group | Listen filter (Phase 2) |

MCPTT 가 IMS 세션 추상화 때문에 우회한 요구사항을, OxLens 는 SFU 원리로 직선 해결.

---

## 8. 구현 타임라인

| Phase | 시점 | 범위 |
|-------|------|------|
| **Phase 1** | Peer F 완료 직후 | Subscribe slot + Universal SSRC + 단일 방 Atomic grant + 긴급발언 |
| Phase 2 | Phase 1 상용 레퍼런스 확보 후 | Listen filter + Multi-destination + Whisper |
| Phase 3 | 2027~2028 | Cross-SFU federation + 2PC coordinator |

---

## 9. 기각된 대안

- **room_id 해시 기반 결정론적 SSRC** — universal 고정 대비 복잡도 증가, cross-room 에서 방별 SSRC 변화 → SDP 재협상 유발
- **Publish 쪽 slot pre-allocate** — simulcast / codec 다양성 때문에 의미 축소. SWITCH_DUPLEX half→full 재협상 어차피 필요
- **부분 grant (일부 방만 획득)** — Publisher UX 복잡 + Subscriber 1 stream 불변식 위배. NACK/Emergency 조합으로 충분
- **Subscribe active stream 런타임 선점 규칙** — Axiom 1 원천 차단으로 불필요
- **Moderate 와의 통합** — Moderate 는 별개 도메인(full-duplex 다중 speaker). PTT slot 사용 안 함. 경계 명시

---

## 10. 오픈 이슈

- PttRewriter 내부 상태를 universal SSRC 로 단순화 시 **speaker 전환 시점 처리** 재검토 필요 (현재 speaker 별 오프셋 테이블 유지 방식)
- 빈 방 PTT slot 의 Subscribe PC 에 대한 Chrome 의 muted track 동작 — 현재 발화자 없는 평상 시 동작과 동일하므로 신규 리스크 없음(2026-04-21 확인)
- Cross-SFU federation 시 1 subscriber 가 N 서버 PTT 동시 수신 — Axiom 1 이 방 단위 atomic 인지 사용자 단위 atomic 인지 Phase 3 설계 시 재확정

---

*설계 대화 원본: `context/202604/20260421_ptt_unified_model_dialogue.md`*
