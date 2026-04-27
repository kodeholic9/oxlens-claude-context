# 20260427 Track Lifecycle 자료구조 재설계 (rev.3) + Phase 0 완료

> 세션 일자: 2026-04-27
> 영역: 서버 (oxsfud) 자료구조 리팩토링 설계 + Phase 0 신규 모듈 작성
> 산출물:
>   - `context/design/20260427_track_lifecycle_redesign.md` (rev.1→2→3, 46KB)
>   - `crates/oxsfud/src/room/publisher_stream.rs` (신규, ~210L)
>   - `crates/oxsfud/src/room/subscriber_stream.rs` (신규, ~310L)
>   - `crates/oxsfud/src/room/slot.rs` (신규, ~135L)
>   - `crates/oxsfud/src/room/mod.rs` (+5L)
> 빌드 결과: **부장님 환경 cargo build 성공 확인**

---

## 0. 세션 개요

이번 세션은 **10년 갈 자료구조 결정**을 목표로 시작. `TrackType` enum 본문 분기의 잘못된 추상화를 제거하고, `(sub, pub)` 페어 객체를 명시화하는 자료구조 재설계.

세션 흐름:
1. 부장님 출발점 결론 4개 재확인 (직전 세션)
2. half-duplex 도메인 본질 정밀 조사 (MCPTT TS 24.380, P25, 삼성/Cisco 특허)
3. mediasoup / LiveKit / Janus 코드 직접 조사
4. **Janus videoroom 모델 채택 결정** — `publisher_stream/subscriber_stream + switch + dummy_publisher` 가 우리 PTT 자동화의 정합 모델
5. duplex 전환 P3 원칙 합의 (ssrc 동일성으로 hot-swap 판단)
6. 부장님 지적: rev.1 이 user 자원을 Room 안에 둠 → rev.2 정정 (Peer 소유)
7. 다른 모델의 크로스 체크 결과 반영 → rev.3 (8 항목 보강 + 자체 발견 2)
8. Phase 0 착수 → 신규 파일 3개 작성 → 빌드 성공

---

## 1. 설계 핵심 결정 (rev.3 단일 출처: `context/design/20260427_track_lifecycle_redesign.md`)

### 1.1 자료구조

```rust
Peer {
    publish:   PublishContext { streams: ArcSwap<Vec<Arc<PublisherStream>>>, ... },
    subscribe: SubscribeContext { streams: ArcSwap<Vec<Arc<SubscriberStream>>>, ... },
}

PublisherStream { ssrc, user_id, kind, source, duplex, simulcast, ..., peer_ref: Weak<Peer> }
SubscriberStream { mid, virtual_ssrc, publisher_ref: ArcSwap<PublisherRef>,
                   room_stats: DashMap<RoomId, Arc<RoomScopedStats>>, gate, munger, ... }

enum PublisherRef { Direct(Weak<PublisherStream>), ViaSlot(Weak<Slot>), None }

Room {
    members: DashMap<UserId, Weak<Peer>>,   // 멤버십만, 자원 소유 X
    slots: Vec<Arc<Slot>>,                   // PTT 인프라 (audio + video 2개 고정 — D-2)
    floor: FloorController,
}

Slot {
    kind, virtual_ssrc, room_id,
    current_publisher: ArcSwap<Option<Weak<PublisherStream>>>,
    prepared_publisher: ArcSwap<Option<PreparedHold>>,   // Pan-Floor 2PC
    rewriter: PttRewriter,                                // Phase 1 이주
}
```

### 1.2 부장님 결정 (10년 결정 분기점)

| 항목 | 결정 |
|---|---|
| D-1 PublisherRef variant | enum 3종 유지 (Direct/ViaSlot/None) |
| D-2 Slot 생성 정책 | **현재안 유지: audio + video 2개 고정 (이유 있음)** |
| D-3 send_stats 위치 | SubscriberStream.room_stats[RoomId] (cross-room 분리 필수) |
| D-4 Phase 6 (BWE Forwarder) | **보류 — 의미 내재화 이후 진행** |

### 1.3 duplex 전환 원칙 — P3 합의

- 서버 단일 진입점: PUBLISH_TRACKS (action=add/remove) 만
- 같은 ssrc → hot-swap (속성만 변경, RTP cache 보존, **Arc 단일 인스턴스 유지 의무**)
- 다른 ssrc → 옛 stream remove + 새 stream create
- **SWITCH_DUPLEX op=52 삭제** (Phase 5)
- 클라 SDK 는 다음 세션 (부장님 영역)

---

## 2. Phase 0 완료 — 신규 자료구조 4개 파일

### 2.1 산출물

| 파일 | 라인 | 핵심 내용 |
|---|---|---|
| `room/publisher_stream.rs` | ~210 | PublisherStream + new() + atomic helpers (set_duplex/set_simulcast/set_rid/mark_notified/ensure_virtual_ssrc) |
| `room/subscriber_stream.rs` | ~310 | SubscriberStream + RoomScopedStats + PublisherRef + Layer + Forwarder + RtpMunger |
| `room/slot.rs` | ~135 | Slot + PreparedHold + new_audio()/new_video() + has_publisher()/current_publisher_strong() |
| `room/mod.rs` | +5 | 신규 모듈 등록 |

### 2.2 안전성 검증

- 모든 신규 코드 `#![allow(dead_code)]` — warning 폭발 회피
- 어디에서도 사용 안 됨 → 기존 코드 동작 영향 0
- 기존 코드 0줄 수정 (mod.rs 만 +5)
- 부장님 환경 cargo build 성공 확인

### 2.3 검토자 우려 사전 반영

- **Pan-Floor 2PC**: `Slot.prepared_publisher: ArcSwap<Option<PreparedHold>>` 자료구조 도입
- **Cross-room stats 분리**: `SubscriberStream.room_stats: DashMap<RoomId, Arc<RoomScopedStats>>`
- **arrival-time drift 보존**: `Slot.rewriter: PttRewriter` 그대로 차용 (단순화 안 함)

---

## 3. rev.3 보강 항목 (10개)

### 3.1 크로스 체크 의견 8개 (다른 모델 검토자)

| # | 항목 | 위치 |
|---|---|---|
| 1 | Pan-Floor 2PC prepare/commit/cancel 흐름 | §3.2 + §4.4.2 |
| 2 | SubscriberStream cross-room stats 분리 | §3.2 |
| 3 | PC 단위 자산 거주지 명시 (gate/nack_suppress/rtx_budget/expected_pt/mid_pool) | §3.1 |
| 4 | stream_map → PublisherStream 보조 필드 매핑 | §3.5 |
| 5 | Slot.release() 에 silence flush 흡수 | §4.4.1 |
| 6 | Floor 진입점 의존성 (옵션 b: Slot 메서드 + 외부 broadcast) | §4.4 |
| 7 | Hot-swap PublisherStream Arc 단일 인스턴스 의무 | §4.6 |
| 8 | PttRewriter arrival-time drift 자산 보존 체크리스트 | 부록 E.1 |

### 3.2 자체 발견 2개

| # | 항목 |
|---|---|
| 9 | Take-over (Peer evict + 새 Peer) 흐름 명시 (§4.7) |
| 10 | "충돌" → "명시 누락" 표현 정정 |

### 3.3 검토자 주장 반박 (무비판 수용 회피)

| 항목 | 반박 |
|---|---|
| 자산 손실 ③ Take-over evict broadcast | §4.5 가 이미 "TRACKS_UPDATE remove broadcast 발사" 명시. 단 Peer 전체 evict 는 §4.7 신설로 보강 (절반 정당) |
| Pan-Floor "의미 충돌" 표현 | 충돌 아닌 누락. 양립 불가능 ≠ 명시 누락. 표현 정정 |

검토자 9/10 정당, 1/10 (자산 ③) 부분 반박, 표현 1군데 정정.

---

## 4. 기각된 접근법 (반복 위험 높은 것)

### 4.1 자료구조 차원

- **`Room.publishers: DashMap<UserId, Arc<Publisher>>` (rev.1 실수)** — PROJECT_MASTER §"Peer 재설계 원칙" 위반. cross-room 시 user 자원이 방마다 복제될 위험. user×sfud=Peer 추상이 위 계층
- **LiveKit DownTrack 1:1 페어 모델 직접 차용** — PTT N:1 multiplexing 표현 불가. 발화자 회전마다 DownTrack 재생성 → re-nego 폭발
- **mediasoup Consumer 다형성** — Consumer = Producer 1:1. PTT 동적 publisher 교체 불가
- **TrackType enum 다형성 (Track 안 trait impl)** — half-duplex 의 두 정체성 (Publisher track + Room slot) 한 객체에 안 담김
- **publisher.subscribers 양방향 참조** — Janus issue #1362 owner cycle 재현
- **SubscriberStream eager cleanup** — race window. lazy (weak upgrade None) 정석
- **SubscriberStream 단일 send_stats** — cross-room 분리 표현 못 함 (rev.2 빈 칸, rev.3 보강)
- **SubscriberStream identity = (sub, mid, RoomId)** — m-line 폭증 (RFC 8843 위반). 방별 분리는 내부 room_stats 가 자연
- **Floor controller 안에 socket/event_tx/peer_map 의존성 주입 (옵션 a)** — over-engineering. Slot 메서드 + 외부 broadcast (옵션 b) 가 단순
- **Pan-Floor 를 별도 PanFloorController 객체로 분리** — Slot 의 prepare/commit/cancel 메서드로 흡수가 자연

### 4.2 시점 차원

- **Janus C 코드 직접 포팅** — Janus 자신이 lock race 로 issue #1362, #1761, #2050, #2087 고생. Rust+ArcSwap 으로 더 안전한 구조 가능
- **현재 구조 유지 + lock 정리만** — 결론 ① 추상화 깨짐 미해결. 10년 갈 결정엔 부적합

---

## 5. 오늘의 지침 후보 (반복 방지)

### 5.1 다른 SFU 모델 차용 시 — **소유 구조까지 무비판 차용 금지**

- 자료구조의 **의미** 만 가져오고 **소유 위치** 는 우리 추상화에 정합
- Janus 는 cross-room 약함 → Room.participants 안에 두기 충분
- 우리는 cross-room 1급 시민 → Peer (user×sfud) 추상이 위 계층
- 같은 모델이라도 cross-room 1급 시민일 때 user×sfud 추상이 위 계층이 된다는 것을 이름 차용에 묻혀 놓치지 말 것
- 트리거: "Janus 모델 차용", "LiveKit DownTrack 차용" 같은 표현 나오면 PROJECT_MASTER §"Peer 재설계 원칙" 재확인 의무

### 5.2 "정합" 이라고 결론낼 때 — **빈 칸 점검 필수**

- "정합" 이라는 단어가 "보강 필요 없음" 으로 해석되면 위험
- 검증 항목: 새 자료구조에서 기존 자산이 어디로 가는가? 매핑이 1:1 인가?
- 트리거: 설계서에 "정합" 이라고 적기 전에 매핑 표 작성. 빈 칸이면 "보강 필요" 라고 명시

### 5.3 다른 모델의 크로스 체크 결과 반영 시 — **무비판 수용 / 무비판 반박 둘 다 위험**

- 항목별 정밀 평가 필수. 코드 직접 확인이 답
- 정당한 지적은 즉시 수용, 잘못된 지적은 명확히 반박
- 트리거: 검토 의견 받으면 항목별로 코드 확인 → 반박/수용/유보 분류

---

## 6. 부장님 행동 패턴 학습

### 6.1 "10년 결정" 강조 시

- 자료 충분히 조사 (web_search + 코드 직접 확인)
- 한 번에 끝내지 말고 단계별 review
- 빈 칸 두고 "정합" 이라고 안일하게 결론내지 말 것

### 6.2 "크로스 체크" 지시 시

- 다른 모델에 검토 시킨 결과를 그대로 받지 말 것
- 항목별 반박/수용/유보 분류 후 정직 보고
- 부장님 의도 = "무비판 수용 막으려는 것"

### 6.3 "착수해" 시

- 추가 질문 없이 바로 시작
- 단 위험도 / 작업 흐름은 사전 정리 후
- 토큰 효율 — 한 번에 정확히

---

## 7. 다음 세션 — Phase 1 (PTT slot 이주)

### 7.1 작업 범위 (위험도 중, ±400L)

1. `Room.audio_rewriter` / `Room.video_rewriter` 폐기 → `Room.slots: Vec<Arc<Slot>>` 활성화
2. `Slot` 의 5개 메서드 본체 구현
   - `set_publisher(new_pub)` — 새 화자 grant
   - `release() -> Vec<EgressPacket>` — silence flush 자동 흡수
   - `prepare(pan_seq, candidate) -> PrepareResult` — Pan 2PC Phase 1
   - `commit(pan_seq)` — Pan 2PC Phase 2a
   - `cancel(pan_seq)` — Pan 2PC Phase 2b
3. `apply_floor_actions` (floor_broadcast.rs) 가 새 메서드 호출
4. PanCoordinator 가 `slot.prepare/commit/cancel` 경유 (기존 직접 갱신 폐기)
5. silence flush 흐름이 `slot.release() → Vec<EgressPacket>` 반환값 처리

### 7.2 새 세션 로드 순서

```
1. context/SESSION_INDEX.md (1분)
2. context/design/20260427_track_lifecycle_redesign.md rev.3
   - §6 Phase 1 작업 흐름
   - §3.2 Slot/PreparedHold 자료구조
   - §4.4 prepare/commit/cancel 본체 시그니처
   - 부록 E.1 PttRewriter 자산 보존 체크리스트
3. Phase 0 산출물 — room/{publisher_stream,subscriber_stream,slot}.rs
4. Phase 1 수정 대상
   - room/floor_broadcast.rs (apply_floor_actions)
   - room/floor.rs (FloorController)
   - room/ptt_rewriter.rs (clear_speaker → Slot.release 흡수)
   - room/room.rs (audio_rewriter / video_rewriter 폐기)
   - room/pan_coordinator.rs (slot.prepare/commit/cancel 호출 경유)
```

### 7.3 QA 항목 (Phase 1 완료 후)

- PTT 시나리오 6종 회귀 (voice_radio / video_radio / dispatch / support / moderate / conference)
- Pan-Floor 시나리오 (멀티 방 동시 발화 prepare → commit / cancel)
- floor 회전 시 silence flush 정상 동작 (Opus 3프레임 NetEQ 연속성)
- arrival-time drift 자산 보존 (147초 부하 시 +43ms drift 미발생, 부록 E.1 체크리스트)

### 7.4 검증 의무 (부록 E.1)

PttRewriter 이주 시 단순화 절대 금지:
- `last_relay_at: Option<Instant>` — 매 전환 +43ms drift 누적 회피의 핵심
- arrival-time 기반 `virtual_base_ts` 확정
- `OPUS_SILENCE = [0xf8, 0xff, 0xfe]` 3프레임
- `clear_speaker()` 멱등성 (speaker=None 시 silence 안 보냄)
- video `pending_keyframe` 키프레임 대기
- Audio ts_guard_gap=960, Video ts_guard_gap=3000

---

## 8. 미해결 / 보류 항목

### 8.1 보류 (부장님 결정)

- **Phase 6 LiveKit Forwarder BWE 차용** — 의미 내재화 이후 진행. 본 설계서 범위 밖.
- **클라 SDK duplex 전환 처리 (P3 원칙 전제)** — 다음 세션 별도. 서버 도움 없이 클라에서.

### 8.2 다음 세션 결정 필요

- Phase 1 착수 일정
- Phase 1 완료 후 Phase 2 (PublisherStream 도입) 즉시 착수 vs 다른 의제 우선

---

*author: kodeholic (powered by Claude)*
