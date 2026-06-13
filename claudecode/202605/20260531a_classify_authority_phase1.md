# 작업 지침 — Duplex Activeness Phase 1: 분류 권위 단일화 (TrackType 복원)
> 완료 보고 → [20260531a_classify_authority_phase1_done](../../202605/20260531a_classify_authority_phase1_done.md)

문서 ID: `20260531a_classify_authority_phase1.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: fan-out 분류 권위를 `TrackType` 단일로 수렴. **동작 보존 리팩터** (분기 기준만 교체, 라우팅 결과 불변). 전환/캐싱(Phase 2)·통지(Phase 3)는 본 지침 범위 아님.
설계서: `context/design/20260531_duplex_activeness.md` §3 결정 A + §4 Phase 1.

---

## §0 의무 점검 (시작 전)

1. `PROJECT_MASTER.md` "자료구조 단일 출처" + 설계서 §3 A 재독.
2. grep 3종 (현 분산 면적 확인, _done §1 첨부):
   - `rg "is_half|is_simulcast_video" crates/oxsfud/src/room/publisher_track.rs`
   - `rg "via_slot|forwarder" crates/oxsfud/src/room/subscriber_stream.rs`
   - `rg "track_type\(\)" crates/oxsfud/src` ← 현 호출처 (대부분 0 예상 — 죽은 권위 확인)
3. **불변 확인 (전제)**: `Half ⇒ simulcast=false`. `track_ops` PUBLISH_TRACKS 처리에서 Half 트랙은 simulcast 강제 off 인지 grep 확인. 이 불변이 깨지면 §2 동치가 성립 안 함 → 2회 실패 룰 전에 보고.

---

## §1 컨텍스트 — 왜

fan-out 분류("이 트랙이 HalfNonSim/FullSim/FullNonSim 중 무엇이냐")가 세 곳에 분산:
- `PublisherTrack::fanout`: `is_half = duplex_load()==Half && !simulcast`, `is_simulcast_video = simulcast && kind==Video` 즉석 재조합.
- `SubscriberStream::forward`: `via_slot` / `forwarder.is_some()` / `kind` 자료 분기.
- `TrackType` (`PublisherTrack::track_type()`): "single source of truth" 선언만, 핫패스 호출 0 (죽은 권위).

이를 `TrackType` 단일 권위로 수렴한다. **자료(duplex/simulcast/via_slot/forwarder)는 옮기지 않는다** — 분기 *판단*만 `track_type()` 으로 통일 (행위 분산 해소, 자료 재배치 아님).

### 동작 보존 근거 (중요)
- `is_half` ⇔ `track_type()==HalfNonSim`: `derive(Half,_)=HalfNonSim`. `Half⇒!simulcast` 불변(§0-3) 하에 `Half && !simulcast == Half` 이므로 동치.
- `is_simulcast_video` ⇔ `track_type()==FullSim` (video): simulcast=true ⇒ duplex=Full(Half는 sim off) ⇒ FullSim. 동치.
- forward 진입 시점에 **fanout 이 이미 모드별로 다른 SubscriberStream 을 넘긴다**: fanout Half 경로 → slot stream(publisher Half 확정), broadcast_full → 개인 stream(publisher Full 확정). 따라서 `ctx.publisher.track_type()` 과 SubscriberStream 종류(slot/개인)는 forward 진입 시 항상 정합 → `self.via_slot/forwarder` 분기와 결과 동일.

→ 결론: 분기 기준 교체만으로 라우팅 결과 불변. 회귀 PASS 가 검증 기준.

---

## §2 결정된 사항 (확정)

### Phase A — `fanout` 분기 기준 교체
`PublisherTrack::fanout` 의 `is_half` / `is_simulcast_video` 로 가르던 sub 순회 분기를 `match self.track_type()` 로 교체.

- `HalfNonSim` → 기존 is_half 경로 본문 (subscribers_snapshot + slot vssrc lookup + prefan).
- `FullSim` / `FullNonSim` → `broadcast_full` (현 else 경로).
- **순회 메커니즘 본문은 그대로** (방향 역전 미완 = 별 토픽, 본 지침 범위 아님).
- `prefan_out_via_slot` 호출 조건(`is_half`), keyframe gov_layer 의 `is_simulcast_video` 도 `track_type()` 파생값으로 정리 (지역 변수 `let tt = self.track_type();` 1회 계산 후 재사용).
- simulcast 메트릭 블록(`self.simulcast && kind==Video`)은 `tt==FullSim` 으로 정리 (동치).

### Phase B — `forward` 분기 기준 교체
`SubscriberStream::forward` 의 `via_slot` / `forwarder.is_some()` 분기를 `match ctx.publisher.track_type()` 로 교체.

- 진입부 `let tt = ctx.publisher.track_type();` 1회.
- payload_base: `if tt == HalfNonSim { prefan_payload (None → return false) } else { plaintext }`.
- gate 검사: `if tt != HalfNonSim && kind==Video && !gate.is_allowed() { return false }`.
- 본 분기:
  - `HalfNonSim` → 구 via_slot 본문 (PT rewrite).
  - `FullSim` → 구 forwarder 본문. **`self.forwarder` 는 simulcast rewriter 상태 보관소로 그대로 접근** (분기 판단은 tt, 자료는 self). `tt==FullSim` 인데 `self.forwarder==None` 인 경우 = 정합 깨짐 방어: `else { (Some(payload_base.to_vec()), false) }` fallback + `tracing::warn!` 1회.
  - `FullNonSim` → 구 else 본문 (그대로).

### 손대지 않는 것
- `self.via_slot` / `self.forwarder` **필드 자체는 유지** — 분기에서만 빠진다 (자료 보관 역할 잔존). 필드 거취는 §3 추천.
- `broadcast_full` / `prefan_out_via_slot` 본문 로직.
- fanout 의 순회 방향(broadcast_full vs subscribers_snapshot) — 방향 역전 미완은 별 토픽.

---

## §3 결정 추천 (★ 정지점 — 부장님 GO)

**`via_slot: bool` 필드 거취.** Phase B 후 `via_slot` 은 forward 분기에서 빠져 거의 dead (`SubscriberStream::new` 인자 + 등록 시점 세팅만 잔존). 

- 추천: **유지** (제거 보류). Phase 2(전환 캐싱)에서 slot stream 식별자로 재평가 — 전환 시 "이 stream 이 slot 이냐 개인이냐" 판별에 쓸 여지. 지금 제거하면 Phase 2 에서 되살릴 위험.
- `forwarder` 는 자료(rewriter 상태)라 거취 논쟁 없음 — 유지.

→ 부장님 결정. 미결 시 추천대로(유지) 박고 _done 명시.

---

## §4 단계별 작업

### Phase A — fanout [정지점: GREEN + 회귀]
1. `publisher_track.rs::fanout` 진입부 `let tt = self.track_type();`.
2. `is_half` / `is_simulcast_video` 지역 변수 → tt 파생으로 교체. sub 순회 분기를 `match tt`.
3. `cargo test` + `cargo run -- --suite regression` (또는 oxe2e conf_basic + ptt_rapid) PASS 확인.
4. **정지점**: commit + 부장님 보고 + GO.

### Phase B — forward [정지점: GREEN + 회귀]
1. `subscriber_stream.rs::forward` 진입부 `let tt = ctx.publisher.track_type();`.
2. payload_base / gate / 본 분기를 `match tt` 로 교체 (§2 Phase B).
3. `cargo test` + 회귀 PASS.
4. **정지점**: commit + 보고.

---

## §5 변경 영향 범위

- `room/publisher_track.rs`: `fanout` (분기 기준).
- `room/subscriber_stream.rs`: `forward` (분기 기준).
- **그 외 파일 손대지 말 것.** track_ops / helpers / collect 는 Phase 2.

---

## §6 운영 룰

1. **정지점 2개** (Phase A 끝 / Phase B 끝). 각 commit + 보고 + GO.
2. **추가 변경 금지** — §5 범위 외 손대지 말 것. via_slot/forwarder 필드 제거 = 범위 위반(§3 정지점 전).
3. **동작 보존 검증** — 회귀(conf_basic + ptt_rapid + gating) 가 분기 교체의 정합 검증. FAIL 시 = §1 동치 가정 깨짐 → 중단 + 보고.
4. **2회 실패 시 중단** — 같은 컴파일/회귀 실패 2회 후 미해결 → 보고.

---

## §7 기각 접근법

- **active 플래그 신설** — fanout 의 track_type 분기가 그 역할 (Phase 2). 본 지침 무관.
- **순회 방향 통일 (Half 도 self.subscribers)** — 방향 역전 미완, 별 토픽. 본 지침은 분기 기준만.
- **via_slot/forwarder 필드 즉시 제거** — §3 정지점. 지금 제거 시 Phase 2 되살림 위험.
- **자료 재배치 (TrackType 을 SubscriberStream 에 캐싱 등)** — 자료 안 옮긴다. publisher.track_type() 직참이 정답 (행위 분산 해소지 자료 이동 아님).

---

## §8 산출물

- `publisher_track.rs` / `subscriber_stream.rs` 수정.
- `_done` 보고: §0 grep 결과 + Half⇒!simulcast 불변 확인 + Phase A/B 각 회귀 PASS + §3 추천 적용 여부.

---

## §9 시작 전 확인

- [ ] PROJECT_MASTER 자료구조 단일 출처 재독 + 설계서 §3 A.
- [ ] §0-3 불변(Half⇒simulcast=false) 확인.
- [ ] 현재 빌드 GREEN + 211 PASS 기준선.

---

## §10 직전 작업 처리

- 직전: Publisher 2계층 Stage 1~4 완료 (`PublishContext ⊃ PublisherStream(논리) ⊃ PublisherTrack(물리)`, commit `dadc342`+`96ded24`, 211 PASS). fanout = `PublisherTrack` 메서드.
- 본 작업은 그 위에서 시작. fanout/forward 가 2계층 후 PublisherTrack 참조로 이미 정합 — 본 지침은 그 위에 분기 기준만 교체.

---

*author: kodeholic (powered by Claude)*
