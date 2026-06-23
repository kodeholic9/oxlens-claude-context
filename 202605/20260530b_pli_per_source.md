# 작업 지침 — PLI 자료 source 단위 분리 (명제 B + catch 4)

문서 ID: `20260530b_pli_per_source.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: **단일 작업** (나누지 않음). PLI Governor 자료를 publisher-단일 → video source 단위로 분리.
전제: `20260530a_publisher_2layer_phase1.md` (전면 2계층) **폐기** — 롤백됨. 본 지침은 국소 수술로 대체.

---

## §0 의무 점검 (시작 전)

1. 현재 빌드 GREEN + `cargo test` PASS 확인 (기준선 — 211 PASS 예상).
2. 호출처 전수 grep — 본 작업의 영향 면적 전부:
   - `rg "publish\.pli_state" crates/oxsfud/src`
   - `rg "on_keyframe_received|judge_server_pli|judge_subscriber_pli" crates/oxsfud/src`
   - `rg "pli_burst_handle|cancel_pli_burst" crates/oxsfud/src`
   목록을 _done §1 에 첨부. **이 grep 결과가 전환 대상 전부다 — 빠진 자리 없는지 교차 확인.**

---

## §1 컨텍스트

### 결함 (명제 B — 확정)
`PublishContext.pli_state: Mutex<PliPublisherState>` 가 **publisher 당 단일** 인스턴스. `PliPublisherState.layers[High]` 슬롯을 camera-h(simulcast High)와 screen(non-sim → `Layer::High`)이 **공유**. `publisher_stream.rs::fanout` 의 keyframe 블록에서 screen 의 I-Frame 도착이 `on_keyframe_received(High)` 를 호출 → camera-h 의 `pli_pending` 을 거짓 해제. **camera + screen 동시 발행(talker/presenter/moderator 프리셋) 시 PLI 오염**.

### catch 4 (동일 자리)
`simulcast_pli_pending` (신설 예정 dedup 자료) 도 publisher 단일이면 같은 keyframe 블록에서 같은 오염. → 본 작업에서 **함께 source 단위로 신설**.

### 방향 결정 — (b) 국소 수술
- 전면 2계층(Stream 논리 / Track 물리)은 **보류**. SVC/codec 확장이 진짜 트리거일 때 진입.
- 본 작업은 **PLI 자료만 source 단위로** 분리. ingress/rtcp/track_ops/admin 의 SSRC 구조는 **안 건드림**.
- **trade-off (정직)**: source 문자열 키 = "약한 끈" (2계층이 타입으로 없애려던 패턴). 그 깔끔함은 포기. 대신 면적이 호출처 4~5곳으로 국소 → 저위험 + 즉시 결함 차단.

---

## §2 결정된 사항 (확정)

### 자료 변경 (`peer.rs` PublishContext)
- `pli_state: Mutex<PliPublisherState>` → **`pli_states: DashMap<Arc<str>, Mutex<PliPublisherState>>`** (key = source: "camera"/"screen"/...)
- **신설**: `simulcast_pli_pending: DashMap<Arc<str>, AtomicBool>` (catch 4, key = source)
- `PliPublisherState` (pli_governor.rs) **자체는 불변** — `layers[h,l]` 구조 그대로. 인스턴스만 source 별로 분리.

### 진입 헬퍼 (Peer 또는 PublishContext)
```
fn pli_state_for(&self, source: &str) -> entry/ref   // DashMap entry().or_insert_with(|| Mutex::new(PliPublisherState::new()))
fn simulcast_pli_pending_for(&self, source: &str) -> &AtomicBool  // 동일 패턴
```
- 직접 `pli_states.get()` 산재 금지 — 헬퍼 단일 진입 (자료 home 일원화 원칙).

### source 역참조 규칙 (ssrc 만 있는 호출처)
- `spawn_pli_burst(ssrc)` 등: `peer.find_publisher_stream(ssrc).map(|s| s.source.clone())`.
- 역참조 실패(stream 없음/RTX)면 **`"camera"` fallback** (기존 단일 동작과 동치 — 무해).

---

## §3 결정 추천 (★ 정지점 — 부장님 확인)

| 항목 | 추천 | 근거 |
|---|---|---|
| 키 = source vs simulcast_group | **source** | screen 은 non-sim → simulcast_group=None 이라 키 부적합. source 는 camera/screen 모두 커버 |
| `pli_burst_handle` / `cancel_pli_burst` 도 source 별? | **이번엔 단일 유지** | 명제 B 범위 아님. camera/screen 동시 burst 충돌은 별 증상 — 본 작업서 제외, 발견 시 _done 보고만 |
| `pli_state_for` 진입점 위치 | **PublishContext 메서드** | pli_states 소유자가 PublishContext |

→ 부장님 미결 시 추천대로 진행. "바른 위치 찾아가기" — burst_handle source화는 후속에서 필요 드러나면.

---

## §4 단계별 작업 (단일 작업 — GREEN 유지)

호출처가 국소(4~5곳)라 브리지 없이 한 흐름으로 전환. 단 catch 4 만 끝에 분리(검증 경계).

### Phase A — pli_state source 분리 (명제 B 해결) [정지점: GREEN + test]
1. `peer.rs` PublishContext: `pli_state` → `pli_states` 교체 + `pli_state_for(source)` 헬퍼. `new()` 정합.
2. `pli.rs` `spawn_pli_burst`: `p.publish.pli_state.lock()` **2곳**(첫 발 기록 / i>0 governor 체크) → source 역참조 후 `p.publish.pli_state_for(&source).lock()`. source 는 함수 진입부에서 1회 계산.
3. `publisher_stream.rs` `fanout` keyframe 블록: `on_keyframe_received` 호출 자리 → `self.source` 로 `pli_state_for` 조회 후 전달. **여기가 명제 B 진앙** — screen keyframe 이 camera pli_state 못 건드리게 됨.
4. `send_pli_to_publishers` (위치 = grep `judge_subscriber_pli`/`judge_server_pli` 호출처): subscriber 가 보는 publisher video stream 의 `source` 로 pli_state 조회. (subscriber → publisher_stream_arc.source 경로)
5. `admin.rs` Governor dump: `pli_state.dump()` → `pli_states` 순회하여 source 별 dump (admin JSON 키에 source 추가).
6. **정지점**: `cargo build` GREEN + `cargo test` PASS. 부장님 보고.

### Phase B — catch 4 (simulcast_pli_pending source 별) [정지점: GREEN + test]
1. `peer.rs`: `simulcast_pli_pending: DashMap<...>` 신설 + `simulcast_pli_pending_for(source)` 헬퍼 (Phase A 에서 같이 박아도 무방 — 단 사용처는 여기).
2. `publisher_stream.rs` `broadcast_full` SIM:PLI 블록: simulcast keyframe 요청 dedup 을 `simulcast_pli_pending_for(self.source)` 로. (catch 4 분석: `20260529a_catch4_analysis_done.md` 참조 — broadcast_full 메서드 흡수까지는 본 작업 범위 아님, **자료 source화 + 인라인 dedup 만**)
3. **정지점**: GREEN + test. 부장님 보고.

---

## §5 변경 영향 범위

- `room/peer.rs` — PublishContext 자료 + 헬퍼
- `transport/udp/pli.rs` — spawn_pli_burst
- `room/publisher_stream.rs` — fanout keyframe (Phase A) + broadcast_full SIM:PLI (Phase B)
- `send_pli_to_publishers` 소재 파일 (grep) — judge 호출처
- `signaling/handler/admin.rs` — Governor dump
- **건드리지 않음**: ingress_publish/ingress_rtcp/track_ops/helpers/publisher_stream_index — SSRC 구조 그대로.

---

## §6 운영 룰

1. **정지점 2개**: Phase A(명제 B GREEN) / Phase B(catch 4 GREEN). 각각 보고 + GO.
2. **추가 변경 금지**: §5 외 파일 손대지 말 것. SSRC 구조 / 2계층 손대지 말 것.
3. **2회 실패 시 중단**: 같은 컴파일/테스트 실패 2회 → 중단 + 보고.
4. **누락 방지**: §0 grep 목록의 모든 `publish.pli_state` 자리가 Phase A 에서 전환됐는지 _done 에서 1:1 대조.

---

## §7 기각 접근법

- **전면 2계층 (Stream 논리 / Track 물리)** — 보류. 면적 광범위(ingress/rtcp/fanout/tasks/admin/index 전부) + 점진해도 브리지 이중화. 명제 B/catch 4 해결엔 과함. SVC 트리거 때 진입.
- **키 = simulcast_group** — 기각. screen non-sim 은 None → 키 충돌. source 가 정답.
- **pli_state 를 PublisherStream(SSRC)에 귀속** — 기각. camera-h / camera-l 이 별 PublisherStream(SSRC) 이라 같은 `PliPublisherState.layers[h,l]` 공유 불가 (layer 분리됨). source 단위 컨테이너가 정답.
- **빌드 폭발 후 에러 목록 todo** (20260530a 방식) — 기각. Claude Code 가 GREEN 본능이라 안 멈추고 끝없이 고침. GREEN 유지 점진이 정답.

---

## §8 산출물

- 수정: peer.rs / pli.rs / publisher_stream.rs / (send_pli 파일) / admin.rs
- `_done` 보고: §0 grep 결과 + 전환 1:1 대조표 + Phase A/B GREEN + test 수 + §3 추천 적용 여부 + (발견 시) burst_handle 충돌 메모

---

## §9 시작 전 확인

- [ ] 빌드 GREEN + test PASS (기준선)
- [ ] §0 grep 3종 실행 → 호출처 전수 확보
- [ ] §3 추천 — 부장님 GO 또는 "추천 적용" 합의

---

## §10 직전 작업 처리

- 직전: 전면 2계층 시도(`20260530a`) → 빌드 폭발 방식 실패 → **롤백 완료**. 본 지침은 (b) 국소 수술로 대체.
- catch 4 분석 문서 `20260529a_catch4_analysis_done.md` 의 broadcast_full 메서드 흡수(`request_simulcast_keyframe`)는 본 작업 범위 아님 — 본 작업은 **PLI 자료 source화**만. 메서드 흡수는 별 토픽.
- 회귀 시나리오 `camera+screen 동시 + screen keyframe`(명제 B 검증) oxe2e 추가는 본 작업 GREEN 후 별 phase.

---

*author: kodeholic (powered by Claude)*
