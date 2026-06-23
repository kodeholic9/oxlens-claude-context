# 축 2 — 코드/주석 청결성

> 작성: 2026-05-17 (김과장, Phase 0 사전 자료)
> 검토자: 김대리 (심층 검토 + 옵션 결정 + 지침 작성)
> 부장님 결정: *"현재 주석이 안맞는 부분 및 deadcode 정리도 필요"*

---

## 0. 부장님 요구사항 정합

| 결정 | 출처 |
|------|------|
| 주석 부정합 정리 | 부장님 직접 명시 |
| dead code 정리 | 부장님 직접 명시 |
| 유지보수성 / 신규 진입 비용 | 부장님 *"유지 보수에 유의한지"* 의문 + 김과장 *"신규 개발자 진입 비용 큼"* 지적 동의 추정 |

s/w 정석: **Dead Code Removal** + **KISS** + **Documentation Consistency**

---

## 1. 수정 대상 파일 ★ 김대리 grep 회피용

### 1.1 시간순 누적 주석 (총 177자리, 파일별 분포)

| 파일 | 시간순 주석 수 | 비고 |
|------|--------------|------|
| `crates/oxsfud/src/room/participant.rs` | **39** | Step E/F 이주 흔적 다수. 이미 *RoomMember rename* (Step 8b), *Endpoint 폐기* 흔적 |
| `crates/oxsfud/src/room/peer.rs` | **16** | Phase 2.2 / Step C/D 이주 흔적 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | 11 | Phase 5 hot-swap, Phase 2.6 등 |
| `crates/oxsfud/src/datachannel/mbcp_native.rs` | 11 | MBCP 진화 흔적 |
| `crates/oxsfud/src/signaling/handler/room_ops.rs` | 6 | |
| `crates/oxsfud/src/room/subscriber_stream.rs` | 5 | Phase ② cleanup, Phase ①.5 |
| `crates/oxsfud/src/room/publisher_stream.rs` | 5 | Phase 2.x 다수 |
| `crates/oxsfud/src/datachannel/mod.rs` | 5 | |
| `crates/oxsfud/src/signaling/handler/admin.rs` | 4 | |
| `crates/oxsfud/src/room/slot.rs` | 4 | Phase 1, Phase ①.5 |
| `crates/oxsfud/src/room/room.rs` | 3 | Phase 1 Step 4 |
| `crates/oxsfud/src/transport/udp/mod.rs` | 2 | |
| `crates/oxsfud/src/transport/udp/egress.rs` | 2 | |
| `crates/oxsfud/src/room/stream_map.rs` | 2 | |
| `crates/oxsfud/src/room/room_id.rs` | 2 | Cross-Room Federation Phase 1 Step 8a |

### 1.2 dead_code allow (21 자리)

| 파일 | 줄 | 사유 추정 |
|------|----|---------|
| `crates/oxsfud/src/room/slot.rs` | 27, 31 | `#![allow(dead_code)]` 모듈 전체 — *Phase 0 신설, 사용 안 함* (현재는 *사용 중* — 검증 필요) |
| `crates/oxsfud/src/room/publisher_stream_index.rs` | 27 | 모듈 전체. *현재 Peer.publish.streams 사용 중* — 검증 |
| `crates/oxsfud/src/room/subscriber_stream_index.rs` | 31 | 모듈 전체. *현재 사용 중* — 검증 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | 27, 31 | 모듈 전체. *현재 사용 중* — 검증 |
| `crates/oxsfud/src/room/publisher_stream.rs` | 25, 44 | 모듈 전체. *현재 사용 중* — 검증 |
| `crates/oxsfud/src/room/floor_broadcast.rs` | 290 | 단일 함수 |
| `crates/oxsfud/src/room/ptt_rewriter.rs` | 134, 474 | 단일 함수 2건 |
| `crates/oxsfud/src/room/participant.rs` | 197, 202, 205 | 단일 함수 3건 |
| `crates/oxsfud/src/transport/udp/mod.rs` | 175 | `from_socket` (사용 안 함) |
| `crates/oxsfud/src/datachannel/pfloor.rs` | 73 | **축 1 폐기와 동시 제거** |
| `crates/oxsfud/src/transport/udp/rtcp_terminator.rs` | 319, 361 | 단일 함수 2건 |
| `crates/oxsfud/src/signaling/handler/helpers.rs` | 419, 424 | 단일 함수 2건 |

→ 모듈 전체 `#![allow(dead_code)]` 5 자리는 *Phase 0 신설 시 활성화 안 됨* 의미. **현재는 활성화** 됐을 가능성 높음 — *attribute 제거 후 컴파일 확인*.

### 1.3 이주 흔적 주석 (20+ 자리, 대표만)

| 자리 | 패턴 |
|------|------|
| `room/mod.rs:12` | "Phase 2.2 에서 Peer.tracks 필드가 PublisherStreamIndex 로 이주하면서" |
| `room/peer.rs:57-58` | "Phase 2.2 (2026-04-28): TrackIndex re-export 제거 — Peer.tracks 필드 폐기와 동기. 호출처는 ... 로 이주" |
| `room/peer.rs:154` | "Phase 2.2 (2026-04-28): Peer.tracks: ArcSwap<TrackIndex> 를 이곳으로 이주" |
| `room/publisher_stream.rs:297` | "Phase 2.5 stream_map 폐기 후에도 admin/agg-log 가 같은 DTO 로 출력 유지" |
| `room/publisher_stream.rs:449` | "Peer scope 의 Active 천이 폐기 — PublisherStream 자기 자신 의 천이로 이주" (Hook Phase 3 자리, 신규) |
| `room/subscriber_stream.rs:244-246` | "PC 단위 자산 중 SubscriberStream 으로 이주 (rev.3 §3.1 검토자 빈 칸 ②). 현재 SubscribeContext.gate (PC 단위 1개) 에서 Phase 3 시점 이주" |
| `room/ptt_rewriter.rs:132` | "SWITCH_DUPLEX op=52 잔재. Phase 5 폐기 후 호출처 0" — **호출처 0인데 보존 중** |

### 1.4 polluted/잔재 주석 패턴 (대표)

- `room/room.rs:43`: *"virtual_ssrc 는 방마다 random alloc (Phase ①.5, 2026-05-02) — universal 상수 폐기"*
- `room/room.rs:44`: *"PttRewriter 는 Slot.rewriter 안으로 이주 — 부록 E.1 자산 8건 보존"*
- `room/peer.rs:212`: *"universal reserved (mid 0/1 PTT 고정) 폐기 — cross-room affiliate 시 방마다..."*
- `room/peer.rs:213`: *"PTT mid 가 다른 위치 받음. collect_subscribe_tracks 가 매번 sub_rooms 의 모든..."*
- `room/participant.rs` 의 *Step E1 / E2 / E3 / E4 / B / C1-C6 / D1-D5 / F2 / F3 ...* — **39 자리** *Endpoint 폐기* 이주 흔적

---

## 2. 폐기/정리 대상 — 분류

### 2.1 *완전 폐기* (역사 가치 0)

**A. 축 1 폐기와 동시**:
- `datachannel/pfloor.rs:73` `#[allow(dead_code)]` — 모듈 전체 삭제
- Pan-Floor 관련 시간순 주석 *대부분* — 자리 자체 삭제

**B. 호출처 0 의 SWITCH_DUPLEX 잔재**:
- `ptt_rewriter.rs:132` — *"SWITCH_DUPLEX op=52 잔재. Phase 5 폐기 후 호출처 0"* — 함수 자체 폐기 자리. 검증 후 삭제.

**C. *Endpoint 폐기* 이주 흔적** (participant.rs 39 자리):
- Step E1-E4 / B / C1-C6 / D1-D5 / F2-F3 등 *이주 후 빈 자리 명시* 주석
- 옵션:
  - (a) **완전 삭제** (git log + 세션 파일 의존)
  - (b) *현재 자리 한 줄로 압축* (예: *"Phase E4: phase/suspect_since → Peer 소유 (2026-04-19 이주)"*)
  - (c) HISTORY 섹션 분리 (파일 끝)

### 2.2 *역사 보존 가치 있음* (현재 결정 사유 의존)

**A. 부장님 *기각된 접근법* 매핑 주석**:
- *"universal 상수 (PTT_AUDIO_SSRC) 폐기 — cross-room affiliate 시..."* — *왜* 폐기됐는지 명시. **다만 cross-room affiliate 가 축 1에서 정정** — 의미 정정 필요
- *"PttRewriter 는 Slot.rewriter 안으로 이주 — 부록 E.1 자산 8건 보존"* — *왜 이주* 명시. 보존 가치 있음

**B. *현재 의미* 가 *Phase 표기* 에 의존하는 자리**:
- "Phase ②.5 cross-room PTT slot 일반화" — *현재 코드의 *per-room virtual_ssrc* 가 *Phase ①.5 산물*. 의미 보존 가치
- "Phase ① Step C — RTP 도착 = ParticipantPhase::Active 진입" — *PublishState::Active 천이 자리* (Hook Phase 3 후 의미 정정 — 이미 *2026-05-17* 갱신됨)

### 2.3 *모듈 활성화 검증 필요* (5 자리, `#![allow(dead_code)]`)

`#![allow(dead_code)]` 모듈 전체 attribute 가 *Phase 0 신설 시* 들어감. **현재는 활성화** — attribute 제거 후 컴파일 확인:

| 파일 | 현재 사용 자리 |
|------|--------------|
| `room/slot.rs` | `Room::audio_slot()` / `video_slot()` 호출 다수 (room.rs) |
| `room/publisher_stream.rs` | `Peer.publish.streams` (peer.rs:156) + `fanout` hot path |
| `room/subscriber_stream.rs` | `Peer.subscribe.streams` (peer.rs:805) + `forward` hot path |
| `room/publisher_stream_index.rs` | `PublisherStreamIndex` 모든 자리 |
| `room/subscriber_stream_index.rs` | `SubscriberStreamIndex` 모든 자리 |

→ 5 파일 모두 attribute 제거 가능. 단일 함수 dead_code 9 자리는 *함수 호출처 0 검증* 후 결정.

---

## 3. 옵션 후보

### 3.1 시간순 주석 청산 방식 ★ 김대리 결정 자리

| 옵션 | 방식 | trade-off |
|------|------|----------|
| **A** | 완전 삭제 (역사 = git log + 세션 파일) | 코드 가독성 최대. *복원 비용* 매번 git blame |
| **B** | 한 줄 압축 (현재 자리 의미만) | 가독성 + 컨텍스트 일부 보존. 작업 면적 큼 (177자리) |
| **C** | *현재 결정 사유* 만 남김 + *Phase 표기 / Step 표기 제거* | 부장님 *기각된 접근법* 매핑 자리 보존. 가독성 *중간* |
| **D** | HISTORY 섹션 분리 (파일 끝 또는 별 파일) | 코드 본문 청결. *역사 검색* 한 자리 집중 |

**김과장 추천 — 옵션 C**:
- *현재 결정 사유* (예: *"per-room random alloc — universal 상수 폐기 (cross-room 자연 분리 위함)"*) 는 보존
- *Phase / Step 표기* (*"Phase ①.5 (2026-05-02)"*) 제거 — git log 가 대체
- 부장님 *기각된 접근법* 리스트 (CLAUDE.md) 와 정합. *왜* 가 본문, *언제* 는 git

### 3.2 dead_code allow 처리 ★

| 옵션 | 처리 |
|------|------|
| **A** | `#![allow(dead_code)]` 모듈 전체 attribute 제거 후 *cargo build 워닝 검토*. 워닝 자리만 *함수/필드 폐기 또는 attribute 단일 함수로 좁힘* |
| **B** | 단일 함수 `#[allow(dead_code)]` 9 자리 — *grep + 호출처 0 검증* 후 폐기 |

옵션 A + B 묶음 진행 추천.

### 3.3 *Endpoint 이주 흔적* 39 자리 (participant.rs) ★

| 옵션 | trade-off |
|------|----------|
| **A** | 완전 삭제 | 가독성 + 청결. participant.rs 길이 -200줄 추정 |
| **B** | Step 번호 제거하고 *현재 자리 의미* 한 줄 | -100줄. 의미 부분 보존 |
| **C** | 파일 끝에 *HISTORY* 섹션 모음 | 코드 본문 청결. 외부 참조 가능 |

옵션 A 추천. *Endpoint 폐기* 자체가 *완료된 큰 변경* — 역사는 git + 세션 파일 충분.

### 3.4 *역사 보존 가치 있는 주석* 분리 처리 ★

부장님 *기각된 접근법* (CLAUDE.md 의 11건) + *현재 결정 사유* 매핑:

| 옵션 | 처리 |
|------|------|
| **A** | 본문 주석 그대로 유지 + *현재 의미* 명시 | 코드 자리에서 의미 즉시 확인 |
| **B** | *기각된 접근법* 리스트 (CLAUDE.md) 확장 — 코드 자리는 단순 *참조 링크* | 단일 출처. 가독성 ↑ |

옵션 A 추천 — 부장님 CLAUDE.md *기각된 접근법* 은 *대분류*. 코드 자리의 *세부 결정* 은 본문 가치.

---

## 4. 폐기 후 효과

### 4.1 파일 길이 축소 (추정)

| 파일 | 현재 | 예상 후 | 축소 |
|------|------|--------|------|
| `room/participant.rs` | ~1200 | ~1000 | -200 (Endpoint 이주 흔적 39자리) |
| `room/peer.rs` | ~1290 | ~1100 | -190 (축 1 폐기 -180 + 청결 -10) |
| `signaling/handler/track_ops.rs` | ~900 | ~870 | -30 |
| `signaling/handler/room_ops.rs` | ~500 | ~480 | -20 |
| `room/publisher_stream.rs` | ~640 | ~620 | -20 |
| `datachannel/mbcp_native.rs` | ~600 | ~570 | -30 |

**총 ~ -550줄** (축 2 단독, 축 1 폐기 별도)

### 4.2 신규 진입 비용 감소

*Phase / Step 표기 제거 후*:
- *"이 코드 의미가 뭔가"* 파악 시 *Phase 컨텍스트 검색* 비용 0
- *"왜 이렇게 됐는가"* 는 git blame + 세션 파일 (단발 검색)

### 4.3 부정합 주석 정정

**축 1 폐기 의존**:
- *"cross-room affiliate 시 방마다..."* (peer.rs:212) — Cross-Room publish 폐기 후 *N 방 청취* 로 정정
- *"universal 상수 (PTT_AUDIO_SSRC) 폐기 — cross-room affiliate..."* (room.rs:66) — 동일

---

## 5. 위험도 + 의존성

### 위험도: **낮음**

이유:
- 주석 변경만 — runtime 영향 0
- dead_code attribute 제거 — *컴파일 검증* 즉시 가능
- 회귀 안전망 (252 tests) 그대로

완화:
- 의미 변경 자리는 *축 1 폐기와 동시* 진행 (cross-room 주석 정정)

### 의존성

```
축 1 (모델 단순화) — 선행
   │
   └─→ 축 2 (본 작업) — 축 1 의 자연 연장 + 시간순 주석 일괄 청산
        │
        └─→ 축 3, 4 — 청결한 면적에서 진입 자연
```

축 1 commit 직후 *동일 PR 또는 별 PR* 로 축 2 진행 가능. 분리 시 *축 1의 새 주석 자리* 도 정합 검증 자리.

---

## 6. s/w 정석 원칙 매핑

| 원칙 | 본 축 적용 |
|------|----------|
| **Dead Code Removal** | dead_code allow 21 자리 + 호출처 0 함수 폐기 |
| **Documentation Consistency** | 주석 부정합 정리 (Cross-Room publish 폐기 후 의미 정정) |
| **Single Source of Truth** | 역사 = git + 세션 파일. 코드 주석 = *현재 결정 사유* 만 |
| **KISS** | Phase / Step 표기 제거 — 가독성 우선 |

---

## 7. 진행 추천

**Phase 분해**:

| Phase | 범위 | 위험도 |
|-------|------|-------|
| **A** | `#![allow(dead_code)]` 모듈 전체 attribute 제거 (5 파일) + cargo build 워닝 검토 | 낮 |
| **B** | 단일 함수 `#[allow(dead_code)]` 9 자리 — 호출처 0 검증 후 폐기 | 낮 |
| **C** | `participant.rs` 의 Endpoint 이주 흔적 39 자리 일괄 삭제 | 낮 (주석만) |
| **D** | `peer.rs` 의 Phase 2.2 이주 흔적 16 자리 정리 | 낮 |
| **E** | 다른 파일들 (track_ops 11 / mbcp_native 11 / 등) 시간순 주석 일괄 청산 | 낮 |
| **F** | 축 1 의존 — cross-room affiliate 주석 의미 정정 (축 1 진행 후) | 낮 |
| **G** | SWITCH_DUPLEX 잔재 (`ptt_rewriter.rs:132`) 등 호출처 0 함수 폐기 | 낮 |
| **H** | 회귀 검증 (cargo build + cargo test 252 PASS) | — |

**총 8 Phase**. 정지점 없음 (낮은 위험). 단일 commit 또는 묶음 commit 가능.

---

## 8. 김대리 검토 자리

1. 옵션 3.1 (시간순 주석 청산 방식) A/B/C/D 결정
2. 옵션 3.3 (Endpoint 이주 흔적 39자리) A/B/C 결정
3. 옵션 3.4 (역사 보존 가치 주석) A/B 결정
4. *모듈 전체 `#![allow(dead_code)]`* 5 자리 제거 — 검증 후 *attribute 제거 vs 단일 함수만 좁힘* 결정
5. Phase 분해 정합 검토
6. 축 1 (모델 단순화) 와의 묶음 commit vs 분리 결정

---

*author: 김과장 (powered by Claude Code Opus 4.7) — Phase 0 사전 자료 2026-05-17*
