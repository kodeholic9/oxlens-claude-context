# 작업 지침 — Publisher 2계층 (Stream 논리 / Track 물리) Phase 1: 타입 정의
> 완료 보고 → [20260530a_publisher_2layer_phase1_done](../../202605/20260530a_publisher_2layer_phase1_done.md)

문서 ID: `20260530a_publisher_2layer_phase1.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: 자료구조 신설 + 빌드 에러 목록 확보. **호출처 수정은 Phase 2** (본 지침 범위 아님).

---

## §0 의무 점검 (시작 전)

1. `PROJECT_MASTER.md` 의 "Peer 재설계 원칙" + "자료구조 단일 출처" 절 재독.
2. 본 지침 §2 결정사항 + §3 결정추천을 **부장님 GO 없이 변경 금지**.
3. grep 3종 (현재 상태 파악, 변경 전 면적 확인):
   - `rg "PublisherStream" crates/oxsfud/src | wc -l`  ← 현 SSRC-단위 참조 총량
   - `rg "publish\.recv_stats" crates/oxsfud/src`      ← recv_stats 호출처
   - `rg "publish\.pli_state|pli_burst_handle" crates/oxsfud/src`  ← pli 자료 호출처
   목록을 _done 보고 §1 에 첨부 (Phase 2 todo 규모 산정용).

---

## §1 컨텍스트

### 왜 (근거)
- **명제 B 확정** (본 세션 코드 확인): `PublishContext.pli_state: Mutex<PliPublisherState>` 가 publisher 단위 *단일*. `fanout` keyframe 블록에서 camera-h(simulcast High)와 screen(non-sim → `Layer::High`) 이 같은 `layers[High]` 슬롯 공유 → screen keyframe 이 camera-h 의 pending 을 거짓 해제. camera/screen 동시 발행(talker/presenter/moderator 프리셋) 시 PLI 오염.
- **catch 4 동일 병**: 신설 예정 `simulcast_pli_pending` 도 publisher 단위 단일이면 같은 자리(`fanout` keyframe 블록)에서 같은 오염.
- **근본 해결**: PLI 자료를 *video track 단위* 로 내림. 그 "video track" 계층이 현재 부재 (`simulcast_group: Option<u32>` 약한 끈으로만 흉내). 2계층 도입으로 해소.

### OxLens 명명 규칙 (확정)
- **`Stream` = 논리 계층** (camera/screen 같은 1 미디어). 클라이언트 `MediaStream` 정합.
- **`Track` = 물리 최소 단위** (SSRC). 클라이언트 `MediaStreamTrack` 정합.
- 포함: `PublishContext ⊃ PublisherStream(논리) ⊃ PublisherTrack(물리)`.
- 주의: mediasoup(`Producer`/`RtpStreamRecv`) / RFC("RTP stream"=SSRC) 와 단어가 다름. **OxLens 내부 규칙**이며 클라이언트 WebRTC 와 통일하기 위한 선택. 혼동 방지 위해 각 struct doc 에 명시할 것.

### subscribe 는 단일 계층 (변경 없음)
- subscriber 는 합성된 단일 virtual_ssrc 만 수신 → 논리=물리 1:1 → `SubscriberStream` 그대로 유지. `SubscriberTrack` 신설 금지.
- layer 선택은 `SubscriberStream.forwarder` 가 publisher 의 어느 `PublisherTrack` 을 고르는지 가리키는 것 (subscriber 하위 계층 아님).

---

## §2 결정된 사항 (확정 — 변경 금지)

### 자료 분류

**PublisherTrack (물리, SSRC 단위) — 신설 struct**
- `ssrc: u32` / `rid: ArcSwap<Option<Arc<str>>>` / `clock_rate: u32`
- `actual_pt: u8` / `actual_rtx_pt: u8` / `rtx_ssrc: Option<u32>` / `repair_for: Option<u32>`
- `recv_stats: Mutex<RecvStats>`   ← 현 `PublishContext.recv_stats: DashMap<u32,..>` 를 Track 1:1 로 분산
- `rtp_cache: Option<Mutex<RtpCache>>` / `nack_generator: Option<Mutex<NackGenerator>>`
- `first_seen: Instant`
- 메서드: `is_rtx()` / `is_placeholder()` 이전

**PublisherStream (논리, camera/screen 단위) — 현 PublisherStream 재정의**
- `source: Arc<str>` / `kind: TrackKind` / `track_id: Arc<str>` / `mid: ArcSwap<Option<Arc<str>>>`
- `duplex: AtomicU8` / `original_duplex: DuplexMode` / `simulcast: bool` / `video_codec: VideoCodec`
- `pli_state: Mutex<PliPublisherState>`        ← PublishContext 에서 이동 (명제 B 해결)
- `simulcast_pli_pending: AtomicBool`          ← 신설 (catch 4 — fast path dedup)
- `pli_burst_handle: Mutex<Option<AbortHandle>>` ← PublishContext 에서 이동
- `virtual_ssrc: AtomicU32` / `subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` / `notified: AtomicBool`
- `phase: AtomicU8` (§3 결정 대기 — 아래 참조)
- `tracks: ArcSwap<Vec<Arc<PublisherTrack>>>`  ← 물리 계층 컨테이너
- **`simulcast_group` 폐기** — Stream 이 곧 h/l 묶음. `tracks` 가 직접 소유.

**PublishContext 유지 (PC pair scope)**
- `media` / `twcc_recorder` / `twcc_extmap_id` / `rid_extmap_id` / `repair_rid_extmap_id` / `mid_extmap_id` / `audio_level_extmap_id`
- `audio_mid` / `audio_duplex` (race 안전망)
- `last_video_rtp_ms` / `last_audio_arrival_us` (9b — PC pair liveness, 이동 금지)
- `rtx_seq` (F1 영역, 이동 금지)
- `dc` / `pub_room` / `pub_stats`
- `streams: ArcSwap<PublisherStreamIndex>` ← 의미가 "논리 Stream 컨테이너" 로 전환 (인덱스 내용물은 Phase 2)
- `tracks_by_ssrc: DashMap<u32, Arc<PublisherTrack>>` ← 신설 (hot path: SSRC→Track 직참)

### half(PTT) 특수
- `PublisherStream(ptt-mic, Half)` → `tracks: [1개, non-sim]`. `virtual_ssrc` / `subscribers` 는 비움 (방 Slot 이 대신). Half 면 해당 필드 미사용 — Phase 1 에선 그대로 둠 (정리는 별 토픽).

---

## §3 결정 추천 (★ 정지점 — 부장님 GO 필요)

### 추천 1 — 검토 4건 계층 귀속

| 자료 | 추천 | 근거 | 비고 |
|---|---|---|---|
| `last_pli_relay_ms` | **Stream(논리)** | `pli_state` 짝 (PLI relay 타이밍) | pli 자료와 같이 이동 |
| `muted` | **Stream(논리)** | mute 는 미디어 단위 (camera 전체) | 현 SSRC별 → 의미상 Stream |
| `rtp_gap_suppress_until_ms` | **Track(물리)** | gap 은 SSRC별 seq 끊김 | 동작 규명 후 확정 가능 |
| `phase` (Created/Intended/Active) | **Stream(논리)** | "이 미디어 발행 시작" 의미 | 단 Active 트리거는 물리 RTP(SSRC) 도착 → set_phase 호출 자리는 Phase 2 |

→ 부장님 결정 4건. 미결정 시 Phase 1 은 위 추천대로 박되 _done 에 "추천 적용, 미결재" 명시.

### 추천 2 — 빌드 전략 (부장님 컴파일러-todo 전략 정합)
- Phase A 는 GREEN 정지점 (신설 dead code).
- **Phase B 는 의도적 빌드 폭발** — 타입 전환으로 호출처 수백 곳이 컴파일 에러. **이 에러 목록이 Phase 2 의 todo 리스트**다. 고치려 들지 말 것.
- → Phase B 산출물 = `cargo build 2>&1 | rg "^error" | sort -u` 결과 (_done 에 전량 첨부).

---

## §4 단계별 작업

### Phase A — PublisherTrack(물리) 신설 [정지점: GREEN]
1. `crates/oxsfud/src/room/publisher_track.rs` 신규. 파일 상단 `// author: kodeholic (powered by Claude)`.
2. §2 PublisherTrack 필드로 struct 정의 + `new()` + `is_rtx()`/`is_placeholder()` 이전.
   - `RtpCache` / `NackGenerator` 는 현 `publisher_stream.rs` 에 있음 → `pub use` 또는 이동 (이동 시 Phase A 안에서 함께, GREEN 유지).
3. `#[allow(dead_code)]` — 아직 호출처 없음.
4. `room/mod.rs` 에 `pub mod publisher_track;` 등록.
5. **정지점**: `cargo build` GREEN + `cargo test` 기존 PASS 유지 확인 → 부장님 보고.

### Phase B — PublisherStream 논리 전환 + PublishContext 정리 [정지점: 에러 목록]
1. `publisher_stream.rs` 의 `PublisherStream` 에서 **물리 필드 제거** (§2 Track 으로 간 것들): `ssrc`/`rid`/`clock_rate`/`actual_pt`/`actual_rtx_pt`/`rtx_ssrc`/`repair_for`/`rtp_cache`/`nack_generator`/`first_seen`.
2. **논리 필드 추가**: `tracks: ArcSwap<Vec<Arc<PublisherTrack>>>`, `simulcast_pli_pending: AtomicBool`. `pli_state`/`pli_burst_handle`/`last_pli_relay_ms`/`muted`/`phase` 는 §3 추천대로 Stream 잔류/이동.
3. `simulcast_group` 필드 삭제.
4. `PublishContext` (peer.rs): `recv_stats`/`pli_state`/`pli_burst_handle`/`last_pli_relay_ms` 제거 + `tracks_by_ssrc: DashMap<u32, Arc<PublisherTrack>>` 추가. `new()` 정합.
5. `cargo build` **시도** → 빌드 깨짐 정상.
6. **정지점**: `cargo build 2>&1 | rg "^error" | sort -u` 전량 + 파일별 에러 수 (`rg "^error" -A1 | rg "src/" | sed 's/:.*//' | sort | uniq -c`) → _done 에 첨부. **고치지 말 것.**

---

## §5 변경 영향 범위

- 신규: `room/publisher_track.rs`
- 수정: `room/publisher_stream.rs` (PublisherStream), `room/peer.rs` (PublishContext)
- **Phase 2 폭발 예상 (수정 금지)**: `publisher_stream.rs::{broadcast_full, fanout}`, `transport/udp/ingress*.rs`, `signaling/handler/track_ops.rs`, `signaling/handler/admin.rs`, `signaling/handler/helpers.rs`, `room/publisher_stream_index.rs`, `tasks.rs`. 이들이 Phase B 에서 컴파일 에러 → Phase 2 지침에서 처리.

---

## §6 운영 룰

1. **정지점 2개**: Phase A 끝(GREEN) / Phase B 끝(에러 목록). 각 정지점 부장님 보고 + GO 대기.
2. **추가 변경 금지**: §5 범위 외 파일 손대지 말 것. Phase B 빌드 에러를 *고치는* 행위 = 범위 위반 (그건 Phase 2).
3. **시그니처 선조치 후 보고**: Phase A 의 `RtpCache`/`NackGenerator` 이전 방식(이동 vs pub use)은 김과장 판단 후 _done 에 보고.
4. **2회 실패 시 중단**: Phase A 가 GREEN 안 되면(타입 정의 자체 컴파일 실패) 2회 시도 후 중단 + 보고. Phase B 폭발은 실패 아님 (의도된 산출).

---

## §7 기각 접근법

- **새 타입 병렬 신설 후 점진 마이그(기존 유지)** — 기각. 컴파일러-todo 전략(부장님)이 작동하려면 Phase B 에서 기존 PublisherStream 을 *교체*해 폭발시켜야 호출처가 드러남. 병렬 유지하면 dead code 만 늘고 호출처 안 드러남.
- **PublisherStream 이름 유지 + 필드만 이동(rename 안 함)** — 기각. 같은 이름이 SSRC→논리 의미 전환되면 컴파일러가 의미 오류 못 잡음. 타입을 갈라야(PublisherTrack 신설) 의미 오류가 타입 에러로 전환됨.
- **subscribe 대칭 SubscriberTrack 신설** — 기각. subscriber 는 1 vssrc 합성이라 물리 layer 없음. 단일 계층 유지.

---

## §8 산출물

- `room/publisher_track.rs` (신규)
- `publisher_stream.rs` / `peer.rs` 수정
- `_done` 보고: §0 grep 결과 + Phase A GREEN 확인 + Phase B 에러 목록(파일별 집계) + §3 추천 적용 여부

---

## §9 시작 전 확인

- [ ] PROJECT_MASTER Peer 재설계 원칙 재독
- [ ] §3 결정 4건 — 부장님 GO 또는 "추천 적용" 합의
- [ ] 현재 빌드 GREEN + 테스트 PASS (기준선)

---

## §10 직전 작업 처리

- 직전: catch 2 MediaIntent 폐기 완료(`20260529d`, 211 PASS) + oxe2e 회귀 gate(`20260530`, conf/ptt/gating PASS).
- 본 작업은 그 위에서 시작. catch 4(simulcast_pli_pending)는 본 2계층에 흡수 — 별도 catch 4 지침 폐기.
- 회귀 시나리오 `camera+screen 동시 + screen keyframe`(명제 B 검증) 추가는 자료 이주 완료 후 별 phase.

---

*author: kodeholic (powered by Claude)*
