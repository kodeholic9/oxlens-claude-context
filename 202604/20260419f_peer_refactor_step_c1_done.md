# Peer 재설계 Step C1 완료 — Pub PC-scope RTP 필드 이주

**날짜**: 2026-04-19
**영역**: 서버 리팩터 (Peer 재설계)
**선행**: `20260419c_peer_refactor_direction`, `20260419d_peer_refactor_step_a_done`, `20260419e_peer_refactor_step_b_done`
**설계서**: `design/20260419_peer_refactor_step_c1.md`

---

## 목표

Peer 재설계 Step C1. **RTP 수신 hot path 에 귀속되는 Pub PC-scope 5필드를 `RoomMember` 에서 `PublishContext` 로 이주**.

| 필드 | 성격 |
|------|------|
| `rtp_cache: Mutex<RtpCache>` | NACK → RTX 재전송 원본 |
| `stream_map: Mutex<RtpStreamMap>` | SSRC ↔ kind/rid 자동발견 + MediaIntent |
| `recv_stats: Mutex<HashMap<u32, RecvStats>>` | RTCP Terminator 수신 통계 |
| `twcc_recorder: Mutex<TwccRecorder>` | TWCC sequence 기록 (BWE feedback) |
| `twcc_extmap_id: AtomicU8` | Chrome offerer 할당 TWCC extension ID |

Step B와 구조적 차이: 치환 경로가 한 단계 짧음. Step B는 `member.endpoint.peer.publish.media.xxx` (MediaSession은 `media` 필드로 감쌈), C1은 `member.endpoint.peer.publish.xxx` (PublishContext 직속 필드).

---

## 구현

### 파일별 변경

| 파일 | 변경 내용 |
|------|-----------|
| `room/participant.rs` | `RoomMember` struct 에서 5필드 제거 + 주석 블록으로 교체. `new()` 내부 5개 초기화 라인 제거 (통합 주석으로 교체). `use` 문 3개 정리: `TwccRecorder`, `RecvStats`, `RtpStreamMap` 제거 → `SendStats` 만 남김 |
| `transport/udp/ingress.rs` | **17곳** 풀 경로 치환 — stream_map ×11, recv_stats ×2, rtp_cache ×1, twcc_extmap_id ×1, twcc_recorder ×1, 그 외 (L310 SR 처리, L399 per-packet stats, L407 cache.store, L421 twcc_id 조회, L425 twcc recorder, L625 sim_video rid 조회, L754 PLI ssrc lookup, L806 resolve_stream_kind, L1048 register_and_notify stream 조회, L1081 PROMOTED rid 반영, L1113 register_and_notify duplex 파생, L1130 track_type 보정, L1169 mark_notified, L1208 notify_new_stream 정보 수집, L1283 is_sim 체크, L1363 mark_notified batch) |
| `transport/udp/ingress_subscribe.rs` | 2곳 — `publisher.stream_map` (PLI governor downgrade), `publisher.rtp_cache` (NACK → RTX 재전송) |
| `transport/udp/egress.rs` | 2곳 — `publisher.twcc_recorder` (TWCC feedback 빌드), `publisher.recv_stats` (RR block 생성) |
| `tasks.rs` | 1곳 — `publisher.stream_map` (PLI Governor sweep, l→h upgrade 시 h SSRC lookup) |
| `signaling/handler/track_ops.rs` | 7곳 — `participant.twcc_extmap_id.store()` 1개 + `participant.stream_map` 6곳 (PUBLISH_TRACKS intent merge, sim 사전등록, remove audio intent, remove audio SSRC, remove video source, SWITCH_DUPLEX duplex 갱신) |
| `signaling/handler/admin.rs` | 3곳 — `p.stream_map` 전수 치환 (stream_map dump, intent state, Track Identity issues). **write_file** 로 파일 전체 재작성 (동일 라인 3회 반복, 안전 선택) |

### 치환 통계

- **총 32곳 / 6 파일** (설계서 §13 추정 8~10 파일, 50~100곳 대비 실측 작음)
- 분포 편중: `ingress.rs` 가 17곳 = 53%. RTP 수신 hot path 특성
- `rtcp_terminator.rs`, `helpers.rs` 는 **치환 대상 0** — `send_stats` 만 사용하고 `recv_stats` 는 안 씀 (예상 빗나감)

### 갈래 A/B 구성

- **갈래 A (기존 공개 API 내부 위임)**: 0건. 이 5필드에 대한 `RoomMember` wrap 메서드가 애초에 없어 전부 갈래 B.
- **갈래 B (필드 직접 참조)**: 32곳 모두. cargo check 가 완벽하게 전수 식별.

### 검증

- `cargo build --release`: 0 error, 0 warning
- `cargo test -p oxsfud`: **126/126 pass** (Step B 때와 동일. Step C1 자체 신규 테스트 없음 — 필드 이주만이라 기존 smoke test 로 충분)

테스트 세부:
- 기존 126개 전량 통과 (endpoint smoke 4 + peer smoke 5 + RoomMember proxy 2 + 그 외 115)
- Peer 쪽 smoke 테스트 (`publish_context_new_smoke`) 가 `rtp_cache` / `recv_stats` / `simulcast_video_ssrc` 초기값을 이미 검증 중. Step C1 후 이 테스트가 **실제 사용 경로와 맞물려** 통과. Step A~B 설계서가 이 지점을 미리 예약해둔 것.

---

## 반성 — 이번 세션은 순조로움

Step B 때 헤맸던 3가지 원인(Korean 주석 매칭 실패, cargo+grep 이중 확인, write_file 전환 지체) 이 **재발하지 않았다**. Step B 후 남긴 지침 5건이 실제로 작동.

관찰:

1. **Korean 주석 포함 edit 0 실패** — 이번엔 Korean 주석 영역을 oldText 에 포함시키더라도 코드 라인의 context 가 충분히 유일해서 매칭 성공. Step B 반성 지침 1 "Korean 주석 영역은 oldText 축소" 가 기본 원칙으로 정착하니 실패 포인트가 자연스럽게 제거.
2. **cargo 단일 통로로 전량 잡힘** — 사전 grep 시도도 하지 않음. Step B 반성 지침 2 "정적 grep 은 cargo 가 못 잡는 경우에만" 이 자리잡음. 결과: cargo 에러 63건 (E0609 32 + E0282 31) → 치환 32곳 → 재빌드 0 error 로 한 번에 수렴.
3. **edit_file vs write_file 판단이 빠르고 정확** — 작은 파일 3개(egress, ingress_subscribe, tasks) 는 edit_file 2건 묶음으로, ingress.rs 17곳은 context 유일성 확인 후 edit_file 17 edits 한 번에 성공. admin.rs 3곳은 **동일 라인 `p.stream_map.lock()` 반복** 이라 안전차원에서 write_file 선택.

**추가로 깨달은 것**: Step B 반성 지침 3 ("동일 라인 3회 이상 → write_file") 의 정확한 의미는 "동일 라인 + **oldText 유일성 확보 불가**" 의 AND 조건. 같은 라인이라도 직전/직후 context 로 구분 가능하면 edit_file 유지. ingress.rs 17 edits 경험으로 이 기준이 명확해짐.

---

## 기각된 후보

이번 세션에서는 기각할 만한 "유혹" 자체가 별로 없었음. 설계서에서 Q들을 사전에 전부 확정했기에 치환 중 판단 갈림길이 사라짐.

### 1. C2 필드(`simulcast_video_ssrc`) 를 C1 에 끼워넣기

**기각**: 설계서 §11 Step 경계 엄수. `simulcast_video_ssrc` 도 PublishContext 필드이고 RTP hot path 근처지만, PLI burst / reverse_seq / sub_layers 와 엮여 있어 분리 Step 이 명확. 유혹 없이 skip.

### 2. `expected_video_pt` / `expected_rtx_pt` 를 C1 에서 옮기기

**기각**: 설계서 §14 Q2 에서 Sub PC-scope 로 확정. peer.rs Step A 설계도 `SubscribeContext.expected_video_pt` 로 이미 예약 중. **cargo 에러에도 등장하지 않음** — track_ops.rs 내부에 `participant.expected_video_pt.store()` 가 있긴 하지만 이 필드는 아직 RoomMember 에 남아있어 에러 없음. Step D5 에 가서야 다룸.

### 3. 주석 대대적 정리

**기각**: Step C1 범위 밖. 예: "Step 7: tracks 는 Endpoint 가 소유" 같은 기존 주석이 맥락상 희석되지만 건드리지 않음. Step F 리네임 단계에서 일괄 정리 예정.

---

## 지침 후보 (Step C2 이후 반영)

### 1. 순수 필드 이주는 cargo check 단일 통로로 충분

**맥락**: Step B 는 MediaSession 이주 + ROOM_JOIN credential 재사용 + STUN 인덱스 정리 가 묶여 구조/흐름 변경이 함께 일어났다. Step C1 은 순수 필드 이주. 이 경우 cargo check 한 통로로 전수 식별이 완전하며, grep 교차 검증이 불필요.

**규칙**:
- 순수 필드 이주 Step (C2~C6, D3~D5 대부분): cargo check → 에러 목록 → 치환 → 재빌드. grep 선제 검증 생략.
- 구조 변경 포함 Step (Step B, Step D1 egress_spawn_guard, Step E user-scope 이주 등): cargo check 가 모든 것을 잡지 못할 가능성 → 보조 grep 필요.

### 2. `write_file` 전환 임계값 — AND 조건 명확화

**맥락**: Step B 지침 "동일 라인 3회 이상 → write_file" 은 단순 빈도 기준으로 오해하기 쉬움. 실제 기준은 "oldText 유일성 확보 불가능한 경우".

**규칙**:
- 동일 라인이 반복되더라도 **직전/직후 context 1~2 줄 추가로 유일성 확보 가능** → edit_file 유지
- **동일 라인 + 동일 context** (예: 연속된 중복 블록) → write_file 전환
- 판단 기준: "oldText 에 넣을 수 있는 코드 라인 수 × 매칭 시도" 의 예상 비용 vs write_file 전체 재작성 비용

### 3. 설계서 Q들을 사전에 전부 확정하고 구현 착수

**맥락**: Step C1 설계서 §14 에서 Q1 (편의 프록시), Q2 (expected_pt 위치), Q3 (테스트 필요성) 를 모두 확정한 뒤 구현 착수. 치환 중 판단 갈림길이 사라져 순조로움.

**규칙**:
- 설계서에 Q 섹션이 있으면 **구현 전 전량 Close** 해야 함
- Q 하나라도 "구현 중 결정" 으로 남기면 치환 중 흐름 끊김 + 일관성 위험
- Close 기준: 설계서에 "확정 이유" + "미루는 경우 어느 Step 담당" 까지 명시

### 4. 설계 추정치와 실측의 편차를 Step 완료 시 기록

**맥락**: 설계서 §13 에서 8~10 파일 / 50~100곳 예상. 실측은 6 파일 / 32곳. **예상 편차가 컸던 이유** 는 다음 Step 의 설계 정확도에 피드백.

**규칙**:
- 각 Step 완료 시 "추정 vs 실측" 표 세션 컨텍스트에 기록
- 편차 원인 분석: `rtcp_terminator.rs` / `helpers.rs` 는 왜 치환 대상 0 이었나? → `send_stats` 만 쓰고 `recv_stats` 는 안 씀
- 다음 Step 추정 시 이 경험을 반영: "PublishContext vs SubscribeContext 필드는 파일별 사용 분포가 다를 수 있음"

---

## 다음 Step — Step C2 (Simulcast + PT)

설계서 `20260419c_peer_refactor_direction` Step C2 범위:

- `simulcast_video_ssrc: AtomicU32` → `peer.publish.simulcast_video_ssrc`

단일 필드. Step C1 대비 훨씬 작은 규모 예상 (~10곳 내외). `ensure_simulcast_video_ssrc()` 공개 API 가 있으므로 **갈래 A + B 혼합**:
- 갈래 A: `RoomMember::ensure_simulcast_video_ssrc()` 내부만 위임. 외부 호출자 무변경.
- 갈래 B: `participant.simulcast_video_ssrc.load()` 직접 필드 접근 치환.

Q: `expected_video_pt` / `expected_rtx_pt` 를 C2 에 끼워넣을까? → 여전히 **Step D5** (Sub PC-scope 분류 유지). C2 는 simulcast 단일 필드만.

---

## E2E 검증 상태

§12.3 체크리스트 중:
- [x] `cargo build --release` 0 error / 0 warning
- [x] `cargo test -p oxsfud` 126/126
- [ ] E2E 4종 시나리오 (conference / voice_radio / video_radio / moderate) — 부장님 브라우저 별도 확인
- [ ] admin 스냅샷 (stream_map / recv_stats / twcc_recorder 카운터 정상 흐름)

E2E 결과가 이상하면 세션 컨텍스트 후속 업데이트 예정. 현재는 코드 레벨 검증만 완료 상태로 기록.

---

*author: kodeholic (powered by Claude), 2026-04-19*
