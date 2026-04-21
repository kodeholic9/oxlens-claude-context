# Peer 재설계 Step C3~C6 완료 — Pub PC-scope 나머지 10필드 일괄 이주

**날짜**: 2026-04-19
**영역**: 서버 리팩터 (Peer 재설계)
**선행**: `20260419c_peer_refactor_direction`, `20260419d_peer_refactor_step_a_done`, `20260419e_peer_refactor_step_b_done`, `20260419f_peer_refactor_step_c1_done`, `20260419g_peer_refactor_step_c2_done`
**설계서**: `design/20260419_peer_refactor_step_c3_c5.md`, `design/20260419_peer_refactor_step_c6.md`

---

## 목표

원 지시는 Step C3~C6 통합이었으나 C2 거짓 보고 사건(`20260419g` §반성) 교훈 + Tool-use 한계 고려로 **2단계 분할 왕복**으로 진행:

1. **1회차 (C3~C5)**: 순수 필드 이주 — 갈래 A/B 혼합. **7필드**.
2. **2회차 (C6)**: 구조 리팩터 — 갈래 C 단독. **3필드 + DcState 묶음 타입**.

**최종 10필드** `RoomMember` → `PublishContext` 이주.

| Sub-Step | 필드 | 갈래 | 치환 건수 |
|------|------|------|-----------|
| **C3** | `pli_pub_state` → `pli_state` (리네임), `pli_burst_handle`, `last_pli_relay_ms` | A 1건 (cancel_pli_burst) + B 9곳 | 9 / 6파일 |
| **C4** | `last_video_rtp_ms`, `last_audio_arrival_us`, `rtp_gap_suppress_until_ms` | 순수 B | 6 / 3파일 |
| **C5** | `rtx_seq` | A 1건 (next_rtx_seq) + B 0곳 | 0 / 0파일 |
| **C6** | `dc_unreliable_tx`/`_ready`/`_pending_buf` → `dc.unreliable_tx`/`_ready`/`pending_buf` | **갈래 C 신규 분류** | 11 / 3파일 |
| **통합** | 10필드 | A 2건 + B 15곳 + C 11곳 | **26곳 / 7 고유 파일** |

---

## 구현

### C3~C5 1회차 구현 (14곳 치환)

1. **participant.rs** (7필드 제거 + 초기화 7라인 제거 + 메서드 2건 위임):
   - 제거: `pli_pub_state`, `pli_burst_handle`, `last_pli_relay_ms`, `last_video_rtp_ms`, `last_audio_arrival_us`, `rtp_gap_suppress_until_ms`, `rtx_seq`
   - 위임: `cancel_pli_burst()` → `endpoint.peer.publish.pli_burst_handle`, `next_rtx_seq()` → `endpoint.peer.publish.rtx_seq`
   - use 정리: `AtomicU16`, `PliPublisherState` 제거
   - 신규 테스트: `room_member_next_rtx_seq_delegates_to_peer` (127 → 128)

2. **cascade 치환 15건 / 5파일**:
   - `ingress.rs`: 6건 (C3 L508/573/669, C4 L191/195/374)
   - `ingress_subscribe.rs`: 2건 (C3 L358, C4 L620)
   - `track_ops.rs`: 1건 (C3 L647)
   - `admin.rs`: 1건 (C3 L96, E0282 L97 자동 해소)
   - `tasks.rs`: 2건 (C4 L65/66)
   - `pli.rs`: 3건 (C3 L74/84/114) — **★ grep scope 확장으로 발견**

3. **부장님 cargo 왕복 2회**:
   - 1차: 15 E0609 + 2 warnings 감지
   - 2차: 0 error / 0 warning, 128/128 pass

### C6 2회차 구현 (11곳 치환, 갈래 C)

1. **participant.rs** (3필드 제거 + 초기화 3라인 제거):
   - 제거: `dc_unreliable_tx`, `dc_unreliable_ready`, `dc_pending_buf`
   - use 정리: `VecDeque` 제거 (`DC_PENDING_BUF_MAX` 상수는 유지, Step F 재고)

2. **cascade 치환 11건 / 3파일**:
   - `datachannel/mod.rs`: 6건 (L134, L243+244, L474, L481, L496)
   - `floor_broadcast.rs`: 3건 (`send_dc_wrapped` L266/271/273)
   - `admin.rs`: 2건 (L159+160)

3. **부장님 cargo 왕복 2회**:
   - 1차: 11 E0609 + 7 E0282(연쇄) + 1 warning
   - 2차: 0 error / 0 warning, 128/128 pass, release 빌드 11.93s

### 실측 vs 예측 대조표

| Sub-Step | 예측 곳수 | 실측 곳수 | 예측 파일 수 | 실측 파일 수 | 편차 원인 |
|---|---|---|---|---|---|
| C3 | 6 | **9** | 5 | **6** | ★ `pli.rs` 누락 (grep scope 실패) |
| C4 | 6 | 6 | 3 | 3 | 정확 |
| C5 | 0 | 0 | 0 | 0 | 정확 |
| C6 | 11 | **11** | 3 | **3** | 정확 (★ floor_broadcast.rs 사전 포함) |

**C3 누락 교훈**이 C6에서 작동한 실증: "필드 도메인(PLI/DC) 기준 grep scope"를 엄격 적용 → C6의 `floor_broadcast.rs` 사전 포함 성공.

---

## 검증

### 자동 (cargo / test)

- `cargo check -p oxsfud`: **0 error / 0 warning**
- `cargo test -p oxsfud`: **128/128 pass** (127 → 128, 신규 `next_rtx_seq` 위임 검증)
- `cargo build --release`: **11.93s 성공**

### 수동 (spot check — 부장님 "제대로 고쳤나" 질문 대응)

C3~C5 완료 후 부장님 직관적 확인 요청에 대응하여 **3층위 검증 체계** 정립:

1. **타입 차원** (컴파일): cargo ✓
2. **구조 차원** (치환이 목표 구조): 15건 전부 `endpoint.peer.publish.<field>` 경로로 spot check ✓
3. **의미 차원** (런타임 동작): **E2E 유예** (Step F 이후 일괄, 부장님 지시)

cargo pass는 1번 증거이지 2/3번 증거 아님. 3층위 구분 명시가 중간 보고 정직성의 핵심.

---

## ★ 이번 세션 새 지침 후보 (6건)

### 1. 갈래 C 신규 분류 정의

**C6에서 최초 도입**. 기존 갈래 A/B에 추가하여:
- **A**: 기존 공개 API 내부 위임 (시그니처 불변)
- **B**: 필드 직접 참조 치환 (이름 유지)
- **C (신규)**: 필드 **리네임 + 묶음 타입 + 경로 추가** 3중 변경

갈래 C는 cargo 치환 후 **"묶음 타입 내부 상태 원자성"이 E2E 없이 검증 불가**. Step 이후 기능 회귀 위험이 상대적으로 높다.

### 2. grep scope는 "필드 도메인" 기준 (C3 교훈)

`transport/udp/pli.rs` 누락 사건. 파일 카테고리(handler/transport 등)가 아니라 **필드 도메인(PLI, DC, RTP-cache)** 기준으로 grep scope를 잡는다.

| 도메인 | 포함할 파일 |
|---|---|
| PLI | `transport/udp/pli.rs`, `pli_governor.rs` (+ hot path) |
| DC | `datachannel/`, `floor_broadcast.rs`, `admin.rs` |
| RTP | `transport/udp/ingress*.rs`, `egress.rs` |

C6는 이 교훈 반영 → 0 누락.

### 3. cargo-guided 왕복은 관문, 생략 금지 (C2 지침 재확인)

C6에서도 1차 cargo 없이 치환 들어갔다면 `pli.rs`나 `floor_broadcast.rs`에서 또 놓쳤을 것. **부장님 cargo 왕복 자체가 grep 누락 방어선**.

### 4. E0282 연쇄는 E0609의 그림자

C6에서 E0282 7건이 떴지만 E0609 11건의 타입 추론 실패 연쇄. **E0609 치환만으로 E0282 자동 해소**. 치환 건수 카운트 시 E0609만 세면 됨.

### 5. "제대로 고쳤나" 질문에는 3층위로 답 (C3~C5 반성)

부장님의 "제대로 고쳤나" 질문은 단순 cargo pass 보고로 부족. **타입/구조/의미 3층위**로 구분하여 "무엇이 검증됐고 무엇이 보류됐는지" 명시.

특히 의미 차원(런타임 동작)은 cargo가 못 잡으므로 E2E 유예 상태임을 명시해야 정직.

### 6. 갈래 C 필드 리네임 시 peer.rs와 일치 필수 (C3/C6)

- C3: `pli_pub_state` → `pli_state` (peer.rs Step A 예약)
- C6: `dc_*` → `dc.*` (DcState 묶음)

peer.rs Step A 예약 이름으로 **치환과 동시에 리네임**해야 컴파일 성공. 이름 유지 방침은 갈래 C에서 무효.

---

## 기각된 후보 (이번 세션)

### 1. `last_pli_relay_ms` 제거 (deprecated)
grep 0건 확인. 주석에도 "Governor 도입 후 deprecated" 명시. 그러나 **Step 경계 엄수** 원칙상 이번엔 이주만, 제거는 Step F 이후 재고.

### 2. `DC_PENDING_BUF_MAX` 상수 → `DcState` 내부로 이동
participant.rs 상단 `pub const` 유지. `floor_broadcast.rs`에서 `use crate::room::participant::DC_PENDING_BUF_MAX` 그대로. Step F 재고.

### 3. C3 통합 왕복 (C6까지 한번에)
**C6 분리가 정답**이었음. 갈래 C 특수성(구조 리팩터 + 리네임 + 경로 추가)이 C3~C5 순수 필드 이주와 경계가 흐려질 위험. 분리해서 cargo 왕복 2번 구조 → Step 경계 선명.

### 4. `cancel_pli_burst()` / `next_rtx_seq()` 본문까지 Peer로 이동
메서드 시그니처 유지 + 내부만 위임 (Step B/C2 확립 패턴). 호출처 수정 0, 기존 공개 API 불변. "편의 프록시 신설 금지" 원칙과 별개.

### 5. C6 신규 테스트 추가
`DcState::new()`는 peer.rs Step A의 `dc_state_new_smoke`로 이미 검증됨. RoomMember 갈래 A 없음. 신규 테스트 ROI 낮음.

---

## Peer 재설계 전체 진행 상황 (업데이트)

- ✓ Step A 완료 (0419d) — peer.rs 스켈레톤
- ✓ Step B 완료 (0419e) — MediaSession 이주 + credential 재사용
- ✓ Step C1 완료 (0419f) — RTP 수신 hot path 5필드
- ✓ Step C2 완료 (0419g) — Simulcast 가상 SSRC 1필드
- ✓ **Step C3 완료 (이번 세션)** — PLI 3필드 (pli_state 리네임 포함)
- ✓ **Step C4 완료 (이번 세션)** — 진단 3필드
- ✓ **Step C5 완료 (이번 세션)** — rtx_seq 1필드
- ✓ **Step C6 완료 (이번 세션)** — DC 3필드 → DcState 묶음 (갈래 C 신규)
- ○ Step D1~D6 — Sub PC-scope 필드 배치별 + egress_spawn_guard CAS
- ○ Step E — user-scope 메타 이전 + zombie reaper를 PeerMap 순회로 재작성
- ○ Step F — Endpoint → Peer, EndpointMap → PeerMap 리네임 + E2E 일괄

---

## 다음 세션 — Step D 착수 준비

Step D는 Sub PC-scope 필드 6배치:
- D1: Egress 채널 (egress_tx, egress_rx) + **egress_spawn_guard CAS 도입** (신규)
- D2: 게이트/레이어 (subscriber_gate, subscribe_layers)
- D3: 통계 (send_stats, stalled_tracker)
- D4: NACK/RTX 제어 (nack_suppress_until_ms, rtx_budget_used)
- D5: SDP 결과 (expected_video_pt, expected_rtx_pt)
- D6: mid 관리 (Endpoint 직속 → SubscribeContext로 이사)

D1에는 **egress task spawn CAS 가드 신규 도입** 포함 → 갈래 C 성격 (구조 변경). 나머지는 순수 B 예상.

설계서는 Step D 진입 시 별도 작성.

---

## E2E 검증 상태

- [x] `cargo check -p oxsfud` 0 error / 0 warning
- [x] `cargo test -p oxsfud` **128/128**
- [x] `cargo build --release` 11.93s 성공
- [x] **E2E 유예 확정** — Step F 완료 후 일괄 진행 (부장님 지시)

---

## 통계

- **총 이주 필드**: 10개 (C3: 3 + C4: 3 + C5: 1 + C6: 3)
- **총 치환 건수**: 26곳 / 7 고유 파일
- **edit_file 호출 수**: ~12회
- **cargo 왕복 수**: 4회 (1회차 2 + 2회차 2)
- **추가 테스트**: 1개 (127 → 128)
- **삭제 라인**: ~50줄 (필드 + 초기화 + use)

---

*author: kodeholic (powered by Claude), 2026-04-19*
