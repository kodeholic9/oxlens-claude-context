# 작업 지침 — Publisher 2계층 Stage 3: 명명 청산 (fan-out 전환 폐기)
> 완료 보고 → [20260530d_publisher_2layer_stage3_done](../../202605/20260530d_publisher_2layer_stage3_done.md)

문서 ID: `20260530d_publisher_2layer_stage3.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
원지침: `20260530c_publisher_2layer_roadmap.md` §2 단계 3 — **본 문서가 정정**.
선행: Stage 2 GREEN (논리 PublisherStream + PLI 이주, 명제 B 해결). 커밋 후 진입.

---

## §0 의무 점검

1. 현재 빌드 GREEN + `cargo test -p oxsfud` PASS (Stage 2 커밋 기준선, 211).
2. 본 §1 재평가 숙지 — fanout 구조는 **건드리지 않는다**.

---

## §1 컨텍스트 — 로드맵 §2 단계 3 정정

### 김과장 발견 (정확 — 수용)
fan-out 은 이미 **Track(물리) 진입**이며 그게 옳다:
- `fanout()` 은 `PublisherTrack` 메서드. `ingress` 가 SSRC→Track 으로 호출.
- 각 물리 Track 이 자기 RTP 를 `self.subscribers`(Weak Vec) 에 흘림.
- simulcast layer 선택 = `SubscriberStream.forwarder` 가 `forward()` 안에서 결정.
- "Stream 진입" 으로 바꾸면 = Stream 이 h/l Track 순회하며 forward — **이미 forward() 가 하는 일**. 중복 추상화.

### 정정
- 로드맵 §2 단계 3 "fan-out 을 Track→Stream 진입으로 전환" = **전제 오류, 폐기.** 논리 Stream 은 라우팅 단위가 아니라 **PLI 자료 home** (Stage 2 에서 달성 완료).
- **2계층의 실질은 Stage 2 에서 핵심 완성** (PLI 자료 source 분리 = 명제 B 해결). 라우팅은 Track 진입이 정답.
- Stage 3 = **명명 청산** (구조 변경 0). Stage 4 = recv_stats Track 귀속 + 회귀 (변경 없음).

---

## §2 결정된 사항 — Stage 3 = 명명 청산

**목표**: OxLens 규칙(`Stream`=논리 / `Track`=물리)에 필드·메서드명을 일치시킨다. **순수 rename, 동작 0 변경.** (Stage 1 누락분 + Stage 2 비대칭 정리.)

### rename 목록

**PublishContext 필드 (peer.rs)**
- `streams: ArcSwap<PublisherTrackIndex>` (물리) → **`tracks`**
- `logical_streams: ArcSwap<Vec<Arc<PublisherStream>>>` (논리) → **`streams`**
- 접근부: `peer.publish.streams`(물리) → `peer.publish.tracks`, `peer.publish.logical_streams`(논리) → `peer.publish.streams` 전량 (컴파일러 지목)

**Peer 메서드 (Stage 1 누락분 — 물리 Track 반환인데 stream 이름)**
- `first_stream_of_kind` (물리 반환) → **`first_track_of_kind`**
- `first_stream_of_kind_logical` (논리 반환) → **`first_stream_of_kind`**
- `switch_stream_duplex` → **`switch_track_duplex`**
- `set_stream_muted` → **`set_track_muted`**
- `stream_for_ssrc` / `stream_for_pli_target` (논리 Stream 반환) — **이름 유지** (이미 Stream 반환이 맞음)

**주의 — 충돌 순서**: `first_stream_of_kind_logical → first_stream_of_kind` 와 `first_stream_of_kind → first_track_of_kind` 는 **이름이 겹친다**. 반드시 ① 물리 `first_stream_of_kind` → `first_track_of_kind` **먼저**, ② 그 다음 논리 `first_stream_of_kind_logical` → `first_stream_of_kind`. 순서 뒤집으면 두 메서드가 같은 이름이 됨.

### 유지 (안 바꿈)
- `PublisherTrack` / `PublisherStream` 타입명 (Stage 1·2 확정).
- `fanout` / `broadcast_full` / `subscribers` / `attach_subscriber` — fan-out 구조 일절 불변.
- 지역변수 `stream`/`streams` 는 의미에 맞게 정리 권장(선택, 동작 무관).

---

## §3 결정 추천 (★ 정지점 — 부장님 확인)

### 추천 1 — subscribers Track→Stream 승격: **보류 (측정 먼저)**
김과장은 "simulcast h/l 두 Track 이 같은 subscriber 를 중복 보유"라 했으나, `notify_new_stream` 은 notify 대상(h Track)에만 `attach_subscriber` 하고 rid=l 은 notify skip 으로 보인다. **실태가 갈린다.**

→ **승격 결정 전 김과장이 실태 확정 (Stage 3 진입 시 §4 Phase 0):**
- attach 호출처 2곳(`notify_new_stream` / `collect_subscribe_tracks`)에서 simulcast subscriber 가 **h Track 에만** attach 되는지, **h/l 둘 다** attach 되는지 코드로 확인 + `forward()` 가 layer 를 어떻게 거르는지.
- 결과 보고만. **승격 구현은 본 Stage 3 범위 아님** — 측정 결과로 부장님이 가치 판단.

판단 근거 제공:
- **h 만 attach 라면**: 중복 없음 → 승격 불필요 (현 구조 정답).
- **h/l 둘 다라면**: 중복은 있으나 Weak Vec 두 벌 = 메모리 미미, dead 자연청소라 동작 무해. 승격은 "깔끔함"이지 결함 수정 아님 → YAGNI, 진짜 일관성 문제(detach 누락 등) 확인 시에만.

### 추천 2 — Stage 3 범위 = 명명 청산만
fan-out / subscribers 구조 변경 0. 위험 0 rename.

---

## §4 단계별 작업

### Phase 0 — subscribers 실태 확정 (조사만, 코드 변경 0)
- §3 추천 1 의 attach/forward 실태 확인 → `_done` §보고. **구현 안 함.**

### Phase 1 — 명명 rename [정지점: GREEN + test]
1. §2 rename 목록 — **충돌 순서 준수** (물리 first_stream_of_kind 먼저).
2. `cargo build` — 에러는 누락 치환 자리만. 컴파일러 지목 따라 완결.
3. `cargo test -p oxsfud` PASS — 동작 0 변경이라 그대로 통과. 깨지면 rename 외 변경 섞임 → 점검.
4. **정지점**: GREEN + test → 부장님 보고.

---

## §5 변경 영향 범위

- `room/peer.rs` (PublishContext 필드 + Peer 메서드 rename)
- 물리 `streams` 접근처 전부 (ingress_publish / ingress_rtcp / ingress_subscribe / pli / egress / tasks / track_ops / admin / publisher_track 내부 / broadcast_full 의 `publisher.publish.streams`) → `tracks`
- 논리 `logical_streams` 접근처 (cancel_pli_burst / first_stream_of_kind_logical / attach·detach) → `streams`
- **fan-out 로직 0 변경.**

---

## §6 운영 룰

1. **정지점 1개**: Phase 1 끝 (GREEN + test). 보고 + GO.
2. **순수 rename — 로직 변경 절대 금지.** subscribers 승격·fanout 손대지 말 것.
3. **충돌 순서 준수** (first_stream_of_kind 2-step).
4. **2회 실패 시 중단.**

---

## §7 기각 접근법

- **fan-out 을 Stream(논리) 진입으로 전환** (로드맵 §2 단계 3 원안) — 기각. fanout Track 진입이 물리적으로 옳음(각 Track 이 자기 RTP 흘림). Stream 진입은 forward() 가 이미 하는 layer 선택을 중복 추상화.
- **subscribers Track→Stream 승격을 Stage 3 에서 강행** — 보류. 중복 실태 미확정 + 동작 무해 추정 → 측정 후 부장님 판단.
- **타입명까지 재rename** — 불필요. PublisherStream/PublisherTrack 확정.

---

## §8 산출물

- Phase 0: subscribers 실태 보고 (h-only vs h/l).
- Phase 1: 명명 청산 트리 + GREEN + test.
- `_done`: rename 1:1 대조 + 빌드/테스트 + Phase 0 실태 결론.

---

## §9 시작 전 확인

- [ ] Stage 2 커밋됨 + 빌드 GREEN
- [ ] §3 추천 — 부장님 GO (Stage 3 = 명명만, subscribers 측정만)
- [ ] rename 충돌 순서 숙지

---

## §10 직전 작업 처리

- Stage 2 (명제 B 해결) GREEN 통과 → 커밋. 본 Stage 3 는 그 위.
- **로드맵 `20260530c` §2 단계 3 정정됨** — "fan-out Stream 진입" 폐기, "명명 청산"으로 대체. 로드맵 파일 §2/§7 갱신은 본 Stage 3 GREEN 후 _done 에 반영 또는 부장님 지시.
- 잔여: Stage 4 (recv_stats DashMap → 각 PublisherTrack 귀속 + `simulcast_group` 약한 끈 폐기 + `camera+screen` 회귀 oxe2e). 2계층 마무리.

---

*author: kodeholic (powered by Claude)*
