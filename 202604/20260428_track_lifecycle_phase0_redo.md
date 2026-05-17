# 20260428 Track Lifecycle Phase 0 재작성 + 종합 우선순위 확정

> 세션 일자: 2026-04-28
> 영역: 서버 (oxsfud) 자료구조 신설 — 4/27 산출물 원복 후 재작성
> 산출물:
>   - `crates/oxsfud/src/room/publisher_stream.rs` (+220L)
>   - `crates/oxsfud/src/room/subscriber_stream.rs` (+210L)
>   - `crates/oxsfud/src/room/slot.rs` (+140L)
>   - `crates/oxsfud/src/room/mod.rs` (+5L)
> 빌드 결과: **부장님 환경 `cargo build --release` 성공 (14.66s)**

---

## 0. 세션 개요

직전 세션 (Phase 69 LiveKit 컨닝, Hall 모델, RtpRewriter 일반화) 후속. 부장님이 4/27 Phase 0 산출물을 원복하고, 어제 + 오늘 세 의제 (Track Lifecycle / RtpRewriter 일반화 / Hall) 를 종합해서 재설계하라고 지시.

세션 흐름:

1. **소스 검증** — 원복 후 현재 상태 확인. Phase 0 산출물 사라짐. 단 4/23 T1~T7 (TrackIndex, atomic 추상화, Cross-Room rev.2 평탄 키) 토대 60~70% 살아있음 발견
2. **3 layer 위계 도출** — rev.3 (자료구조 골격) / Hall (사용 패턴) / RtpRewriter 일반화 (hot-path 메커니즘) 가 같은 골격에 다른 색
3. **부장님 명시 — LMR 다중 채널 송출 안 함** → Pan-Floor 사용처 dormant 결정 (자료구조만 보존)
4. **우선순위 확정** — Track Lifecycle 우선. 거주지 확정 후 RtpRewriter 일반화. Hall 은 영업 시점
5. **Phase 0 재작성** — 4/27 산출물의 정확한 코드 없으므로 rev.3 §3.2 기반 신규 작성. 4/28 변경 4건 반영
6. **빌드 검증** — 부장님 Mac 환경 cargo build release 14.66s 성공

---

## 1. 핵심 결정 (10년 결정 분기점, 4/27 + 4/28 종합)

### 1.1 우선순위 확정 (4/28 부장님 결재)

```
① Track Lifecycle Phase 0   ✅ 완료 (본 세션)
② Track Lifecycle Phase 1   PTT slot 이주
③ Track Lifecycle Phase 2   PublisherStream 도입
④ Track Lifecycle Phase 3   SubscriberStream 도입
⑤ RtpRewriter 일반화        거주지 확정 후
⑥ Track Lifecycle Phase 4   fan-out 분기 제거
⑦ Track Lifecycle Phase 5   duplex P3 (op=52 폐기)
⑧ Hall 모델                  영업 시점에
```

### 1.2 4/27 D-1~D-4 그대로 유효

| 항목 | 결정 | 변경 |
|---|---|---|
| D-1 PublisherRef variant | enum 3종 (Direct/ViaSlot/None) | 그대로 |
| D-2 Slot 생성 정책 | audio + video 2개 고정 | **enum 확장형으로 보존** (4/28 변경) |
| D-3 send_stats 위치 | SubscriberStream.room_stats[RoomId] | 그대로 |
| D-4 Phase 6 (BWE Forwarder) | 보류 | 그대로 |

### 1.3 4/28 변경 4건 (4/27 산출물 대비)

| # | 변경 | 이유 |
|---|---|---|
| 1 | `SlotKind` enum 확장형 (`{ Audio, Video }`) | 장래 Hall 슬롯 추가 시 비파괴 확장 가능. D-2 의 의미를 *현재 사용 범위* 로 재해석 |
| 2 | Pan-Floor 자료구조 dormant 마킹 | 부장님 명시 — LMR 다중 채널 송출 안 함. 자료구조만 살리고 호출 보류. Hall 시점 재활용 |
| 3 | `RtpMunger` placeholder 추가 | Phase F (RtpRewriter 일반화) 에서 본격 확장. 현재는 virtual_ssrc 만 보유 + 향후 도입 필드 4종 주석 |
| 4 | `Forwarder` placeholder 추가 | LiveKit 차용 자료구조. current_layer / target_layer / last_kf_at 만. Phase F 에서 본격 확장 |

### 1.4 Pan-Floor 처리 — 옵션 A (dormant 유지) 확정

부장님 명시 후 두 갈래에서 옵션 A 채택:
- **옵션 A**: `pan_coordinator.rs` + `datachannel/pfloor.rs` 코드 유지, `engine.scope.panRequest()` API 미사용 → Hall 도입 시 재활용
- 옵션 B (코드 제거) 기각 — Hall 시점에 거의 동일한 코드 다시 작성 비용

---

## 2. Phase 0 산출물 매핑

### 2.1 PublisherStream (현재 → Phase 2 흡수 대상)

13개 보조 필드 흡수 매핑 (rev.3 §3.5, 본 세션 stream_map.rs 정밀 검증 완료):

| § rev.3 §3.5 | 현재 위치 | PublisherStream 필드 |
|---|---|---|
| ssrc | `Track.ssrc` + `RtpStream.ssrc` | `ssrc: u32` |
| user_id | `Peer.user_id` | `user_id: Arc<str>` |
| kind | `Track.kind` + `RtpStream.kind` (StreamKind) | `kind: TrackKind` |
| source | `Track.source: Option<String>` + `RtpStream.source` | `source: Arc<str>` |
| duplex / original_duplex / simulcast | `Track.duplex` (atomic) + `Track.original_duplex` + `Track.simulcast` | 동일 |
| video_codec / actual_pt / actual_rtx_pt / rtx_ssrc | `Track.*` | 동일 |
| clock_rate | `RtpStream.clock_rate` | `clock_rate: u32` |
| repair_for | `RtpStream.repair_for` | `repair_for: Option<u32>` |
| rid / simulcast_group | `Track.rid: ArcSwap<Option<Arc<str>>>` + `Track.simulcast_group` | 동일 |
| muted / rtp_cache / virtual_ssrc | `Track.*` (T1~T3 atomic) | 동일 |
| notified | `RtpStream.notified: bool` → atomic 격상 | `notified: AtomicBool` |
| first_seen | `RtpStream.first_seen: Instant` | 동일 |
| peer_ref | (신규) | `peer_ref: Weak<Peer>` |

### 2.2 SubscriberStream (현재 → Phase 3 흡수 대상)

| 현재 위치 (`SubscribeContext`) | SubscriberStream 흡수 |
|---|---|
| `layers: HashMap<(u32, RoomId), SubscribeLayerEntry>` | `room_stats[RoomId].forwarder` |
| `send_stats: DashMap<(u32, RoomId), Mutex<SendStats>>` | `room_stats[RoomId].send_stats` |
| `stalled_tracker: DashMap<(u32, RoomId), Mutex<StalledSnapshot>>` | `room_stats[RoomId].stalled` |
| `gate: Mutex<SubscriberGate>` (PC 단위) | `gate: Mutex<SubscriberGate>` (Stream 단위로 이주) |
| `mid_pool` / `nack_suppress` / `rtx_budget` / `expected_pt` | SubscribeContext 잔존 (PC 단위 자산) |

### 2.3 Slot (현재 → Phase 1 흡수 대상)

| 현재 위치 | Slot 흡수 |
|---|---|
| `Room.audio_rewriter: PttRewriter` | `Room.slots[0]: Slot { kind: Audio, rewriter: PttRewriter::new_audio() }` |
| `Room.video_rewriter: PttRewriter` | `Room.slots[1]: Slot { kind: Video, rewriter: PttRewriter::new_video() }` |
| (현재 평탄 호출) | `Slot.set_publisher / release / prepare / commit / cancel` 단일 진입점 (Phase 1) |

---

## 3. 빌드 검증

부장님 Mac 환경:
```
tgkang:~/repository/oxlens-sfu-server $ cargo build --release
   Compiling oxsfud v0.6.24
    Finished `release` profile [optimized] target(s) in 14.66s
```

위험 후보 4건 모두 통과:
1. `ArcSwap<Option<Weak<T>>>` — 통과
2. `SubscriberGate::new()` 시그니처 — 인자 없음, 일치
3. placeholder 자료구조 (RtpMunger / Forwarder / RoomScopedStats) — dead_code 로 통과
4. `getrandom::fill` — participant.rs 패턴 동일

---

## 4. 기각된 접근법 (반복 위험 높은 것)

### 4.1 종합 우선순위 차원

- **9 Phase 부풀리기 (A→B→C→F→D→E→G→H→I)** — 김대리가 RtpRewriter 일반화 + Hall 을 Track Lifecycle 시리즈에 끼워넣음. 부장님 정정: "트랙 라이프사이클이 우선이야". 본질은 rev.3 의 6 Phase (0~5)
- **Pan-Floor 가 Hall 로 흡수된다고 단정** — 부분만 정확. LMR 시나리오 살아있다고 가정 시 Pan-Floor 는 별도. 부장님 명시로 LMR 안 함 → Pan-Floor 가 Hall 로 자연 흡수. 김대리 frame 잘못 매핑 사례
- **RtpRewriter 일반화 먼저** — 거주지 미확정 시 PttRewriter / SimulcastRewriter 가 두 번 이주. 부록 E.1 자산 8건이 두 번의 이동을 견뎌야 함. 회귀 위험 2배

### 4.2 자료구조 차원

- **4/27 산출물 정확한 코드 모르면서 "그대로 재작성"** — rev.3 §3.2 설계 기반 신규 작성. 의미 동일 표현 다를 수 있음 명시 필요
- **`SlotKind` 닫힌 enum** (Audio/Video 만) — D-2 의 의미를 *현재 사용 범위* 가 아닌 *enum 자체 닫힘* 으로 잘못 해석. 확장형으로 보존이 정합
- **Pan-Floor 코드 제거 (옵션 B)** — Hall 시점 재작성 비용. 옵션 A (dormant) 가 정합

### 4.3 의제 처리 차원

- **김대리가 옵션 1/2/3 제시 후 부장님 결정 대기** — 부장님 "모해야되는데?" 응답 = 결정 부담. 김대리가 다음 해야 할 일을 명확히 좁혀서 제시해야 함. 본 세션 종료 프로토콜이 자연스러운 다음 행동

---

## 5. 오늘의 지침 후보 (반복 방지)

### 5.1 종합 우선순위 결정 시 — **부장님 직관 먼저, 김대리 부풀리기 금지**

- 부장님 "트랙 라이프사이클 우선" 직관에 즉시 정합
- 의제 종합 = 의제 추가 아님. 본질 (rev.3 6 Phase) 유지하고 다른 의제는 *의존 관계* 로 표현
- 트리거: "Phase A~I" 같이 9~10 단계 부풀리는 표현 나오면 "이게 진짜 본 시리즈에 속하나?" 자문

### 5.2 부장님 명시 변경 시 — **즉시 정합, 의존 관계 재계산**

- 부장님 "LMR 안 함" 명시 → Pan-Floor 사용처 사라짐 → 자료구조 처리 옵션 갈래 다시 → 옵션 A 합리
- 부장님 발언 변경 시 김대리가 무게 자동 이동 ≠ 부장님 의도 명확화. 명시 변경은 의존 그래프 재계산 트리거
- 트리거: 부장님 "X 안 함" 명시 시 → X 가 어디서 살아있나 재확인 → 사용처 사라지면 dormant / 코드 제거 양갈래 재평가

### 5.3 부장님 "모해야되는데?" 응답 시 — **김대리 옵션 좁히기**

- 옵션 1/2/3 제시 = 결정 부담 → 부장님 통제권 상실
- 김대리가 다음 행동 1개로 좁혀서 제시 (자연스러운 의무 행동 우선: 세션 종료 프로토콜 / 빌드 검증 / 의존 작업 등)
- 트리거: 부장님 단답형 "모해야?" / "그래서?" / "그다음?" → 옵션 좁히기 + 자연스러운 다음 행동 제시

### 5.4 산출물 재작성 시 — **정확한 원본 없으면 정직 고지**

- 4/27 산출물의 정확한 코드 없으므로 rev.3 §3.2 기반 신규 작성. 의미 동일 표현 다를 수 있음 사전 고지
- 빌드 위험 영역 사전 고지 (ArcSwap / SubscriberGate / placeholder / getrandom 등)
- 트리거: "원복 후 재작성" / "그대로 다시" 표현 시 정확한 원본 보유 여부 먼저 확인 → 없으면 설계서 기반 + 차이 가능성 명시

---

## 6. 부장님 행동 패턴 학습

### 6.1 "현재 pan-floor는 hall로 흡수될 것" 표현

- 직관 = "사용처가 Hall 의 부분집합" 의미. 정확함 (LMR 안 함 전제)
- 김대리는 처음에 "부분만 맞다 — LMR 별도" 응답 → 부장님 정정 "LMR 안 할꺼라구"
- 정정 의미 = 김대리 가정 잘못. 부장님 직관이 옳다는 추가 정보. 즉시 정합 필요

### 6.2 "내가 설계를 정확히 몰라. 너에게 의존하는 거거든" 발언

- 의미 = 김대리가 잘못 종합하면 부장님이 보호망 없음. 신중하게 + 의도 명확화 + 정직 고지
- 김대리 실수 가능성을 부장님이 사전 인지 → 정직 보고 + 빈 칸 명시 의무

### 6.3 빌드 결과 단답 보고

```
$ cargo build --release
... Finished `release` profile [optimized] target(s) in 14.66s
```

- 의미 = "결과 알려줬으니 다음 진행 알아서 정해" 신호
- 김대리가 옵션 1/2/3 제시 = 결정 부담. 자연스러운 다음 행동 제시가 정답

### 6.4 한국어 스타일

- 평서형 단정 ("~다" 체)
- 비유 불필요 시 제거
- 단답형 단어 ("동의", "진행해", "맞니?", "모해야?") 시 김대리가 의도 추론 + 명확화

---

## 7. 다음 세션 — Phase 1 진입 준비

### 7.1 Phase 1 작업 범위 (위험도 중, ±400L)

rev.3 §6 Phase 1 + §4.4 정합:

1. `Room.audio_rewriter` / `Room.video_rewriter` → `Room.slots: Vec<Arc<Slot>>`
2. `Slot` 의 5개 메서드 본체 구현
   - `set_publisher(new_pub: Arc<PublisherStream>)` — Floor Granted 단일 진입점
   - `release() -> Vec<EgressPacket>` — silence flush 자동 흡수 (Audio Slot 만)
   - `prepare(pan_seq, candidate) -> PrepareResult` — Pan 2PC Phase 1 (dormant)
   - `commit(pan_seq)` — Pan 2PC Phase 2a (dormant)
   - `cancel(pan_seq)` — Pan 2PC Phase 2b (dormant)
3. `apply_floor_actions` (floor_broadcast.rs) 가 새 메서드 호출
4. PanCoordinator 가 `slot.prepare/commit/cancel` 경유 (dormant 유지)
5. silence flush 흐름이 `slot.release() → Vec<EgressPacket>` 반환값 처리

### 7.2 부록 E.1 보존 의무 8건 (단순화 절대 금지)

PttRewriter 의 자산을 Slot 안으로 그대로 이주. 단순화 한 줄도 금지:

| 자산 | 보존 의무 |
|---|---|
| `last_relay_at: Option<Instant>` | 절대 보존. 매 전환 +43ms drift 누적 회피의 핵심 |
| arrival-time 기반 `virtual_base_ts` 확정 | 절대 보존 |
| Audio `ts_guard_gap=960` (Opus 48kHz, 20ms) | 보존. NetEQ 연속성 |
| Video `ts_guard_gap=3000` (VP8 90kHz, ~33ms) | 보존. freeze 회피 |
| Opus silence flush 3프레임 (`OPUS_SILENCE = [0xf8, 0xff, 0xfe]`) | 보존. NetEQ 연속성 |
| `clear_speaker()` 멱등성 (speaker=None 시 silence 안 보냄) | 보존. jb_delay 폭증 회피 |
| `pending_keyframe` (video 키프레임 대기) | 보존 |
| Video pending_compensation (카메라 구동 지연) | 보존 (arrival-time 기반에 자연 흡수) |

### 7.3 QA 항목

- PTT 시나리오 6종 회귀 (voice_radio / video_radio / dispatch / support / moderate / conference)
- arrival-time drift 자산 보존 (147초 부하 시 +43ms drift 미발생)
- silence flush 정상 동작 (Opus 3프레임 NetEQ 연속성)
- `slot.release()` 후 다음 grant 까지 jb_delay spike 없음

### 7.4 새 세션 로드 순서

```
1. context/SESSION_INDEX.md (1분)
2. context/202604/20260428_track_lifecycle_phase0_redo.md (본 파일)
3. context/design/20260427_track_lifecycle_redesign.md rev.3
   - §6 Phase 1 작업 흐름
   - §3.2 Slot/PreparedHold 자료구조
   - §4.4 prepare/commit/cancel 본체 시그니처
   - 부록 E.1 PttRewriter 자산 보존 체크리스트
4. Phase 0 산출물 (본 세션) — room/{publisher_stream,subscriber_stream,slot}.rs
5. Phase 1 수정 대상
   - room/floor_broadcast.rs (apply_floor_actions)
   - room/floor.rs (FloorController)
   - room/ptt_rewriter.rs (clear_speaker → Slot.release 흡수)
   - room/room.rs (audio_rewriter / video_rewriter 폐기 → slots)
   - room/pan_coordinator.rs (slot.prepare/commit/cancel 호출 경유 dormant)
```

---

## 8. 미해결 / 보류 항목

### 8.1 보류 (부장님 결정)

- **Phase 6 LiveKit Forwarder BWE 차용** — 의미 내재화 이후 진행. rev.3 D-4. 본 시리즈 범위 밖
- **Hall 모델** — 영업 시점 (Webinar 1만 청중 / 대형 행사). Slot 일반화 + RoomType enum 추가. Phase 5 종료 후
- **RtpRewriter 일반화** — 거주지 확정 후 (Phase 3 후). LiveKit 컨닝 적용 (uint64 seq / RangeMap / RTX gate / secondLast / Cold Start 4종)

### 8.2 다음 세션 결정 필요

- Phase 1 착수 일정 (부장님 결재)
- 운영 환경 회귀 검증 1~2회 (Phase 0 의 사용처 0 보장 검증)

---

*author: kodeholic (powered by Claude)*
