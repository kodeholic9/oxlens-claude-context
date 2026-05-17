# 작업 지침 — 묶음 8: 운영성 마무리 (axis4 + 백로그 청산)

> 작성: 2026-05-19 (김대리, claude.ai)
> 담당: 김과장 (Claude Code)
> 검토: 부장님 (kodeholic) — 옵션 6건 + 백로그 처리 5건 모두 결재 (2026-05-19)
> 기반:
>   - `context/design/20260517g_work_order.md` (묶음 8)
>   - `context/design/20260517g_axis4_operability.md` (전체)
>   - 백로그 F25 / F26 / F27 (F24 / F19 는 별 토픽)
> 완료 보고: `context/202605/20260520a_operability_wrapup_done.md`

---

## §0 의무 점검

```bash
cd /Users/tgkang/repository/oxlens-sfu-server

cargo test --release -p oxsfud 2>&1 | tail -5
# → 194 tests PASS 확인 후 진입 (묶음 7 + 미니 정정 완료 상태)

# 사전 grep
grep -n "mod ingress_mbcp\|ingress_mbcp" crates/oxsfud/src/transport/udp/mod.rs
grep -n "process_association_events\|_peer_map\|_socket:" crates/oxsfud/src/datachannel/mod.rs
grep -rn "^//! " crates/oxsfud/src/ | wc -l   # 현재 모듈 doc 주석 수
```

---

## §1 컨텍스트

### 부장님 결재 (2026-05-19)

| 자리 | 결정 |
|------|------|
| §3.1 PROJECT_MASTER 편집 주체 | **C** — 김대리 명세 + 김과장 적용 (분업) |
| §3.3 state dump 통합 도구 | **C** 현행 유지 + 별 토픽 |
| §3.4 trace_id 분산 추적 | **D** 현행 유지 — 별 토픽 |
| §3.5 wire op 카탈로그 | **A** — `context/design/wire_v3_catalog.md` 신설 |
| §3.6 모듈 README | **B** — 각 모듈 `//!` 시작 주석 표준화 |
| F26 ingress_mbcp.rs dead 파일 | **본 묶음 청소** |
| F25 process_association_events chain | **본 묶음 정리** |
| F24 Audio/ViaSlot pli_state Mutex | 별 토픽 (측정 후) |
| F27 hooks/floor.rs dead_code allow | 현행 유지 (의도된 자리) |
| F19 render-detail.js 분리 | 별 토픽 (oxlens-home) |

### 위험도 / 면적

| 항목 | 값 |
|------|-----|
| 코드 변경 | **중** (F26 -470줄 / F25 시그너처 정리 / 주석 표준화) |
| 문서 신설/갱신 | **중** (wire 카탈로그 + PROJECT_MASTER) |
| 위험도 | **낮** (dead 청소 + 주석 + 문서) |
| 클라 wire 영향 | **0** |

---

## §2 결정된 사항

1. `ingress_mbcp.rs` 파일 완전 삭제 + `transport/udp/mod.rs:20` 의 모듈 구조 주석에서 해당 줄 제거
2. `datachannel/mod.rs::process_association_events` chain 안 underscored `_peer_map`/`_socket` 인자 정리
3. 주요 모듈 `//!` 시작 주석 표준화 — 책임 / 핵심 자료구조 / 호출처 3섹션
4. `context/design/wire_v3_catalog.md` 신설 — v3 wire op 전체 카탈로그
5. `PROJECT_MASTER.md` 갱신 — 묶음 1~7 산출 반영 (김대리가 명세 작성, 김과장이 적용)
6. F27 `hooks/floor.rs::on_floor_event` `#[allow(dead_code)]` — **현행 유지** (변경 없음)

---

## §3 정지점

**없음**. Phase 단위 commit 분리 권장.

다만 **Phase B (F25) 면적 점검** 후 *너무 큼* 판단 시 김과장이 부장님께 보고 + 별 토픽 분리 가능. 면적 임계: 김과장 *분석 후 ~3 파일 + 100줄 초과* 시 판단 자리.

---

## §4 단계별 작업

### Phase A — F26 `ingress_mbcp.rs` dead 파일 청소

**파일**: `crates/oxsfud/src/transport/udp/ingress_mbcp.rs` (삭제)

#### A-1. 파일 자체 삭제
```bash
rm crates/oxsfud/src/transport/udp/ingress_mbcp.rs
```

#### A-2. `transport/udp/mod.rs:20` 모듈 구조 주석에서 줄 제거
```rust
// 변경 전
//!   ingress.rs       — publish RTP 수신 (hot path) + TrackType fan-out + SR translation
//!   ingress_mbcp.rs  — MBCP Floor Control (RTCP APP 기반)   ← 제거
//!   ingress_subscribe.rs — subscribe RTCP + NACK 처리

// 변경 후
//!   ingress.rs       — publish RTP 수신 (hot path) + TrackType fan-out + SR translation
//!   ingress_subscribe.rs — subscribe RTCP + NACK 처리
```

#### A-3. 빌드 + grep 검증
```bash
cargo build -p oxsfud
grep -rn "ingress_mbcp" crates/oxsfud/src/
# → 0
```

---

### Phase B — F25 `process_association_events` chain underscored 인자 정리

**파일**: `crates/oxsfud/src/datachannel/mod.rs`

#### B-1. 면적 점검 (김과장 사전 분석)

`process_association_events` chain 안 `_peer_map`/`_socket` underscored 인자 자리 식별. 0516d 보고서에서 *"chain 최상위 — underscored (`_peer_map` / `_socket`, 면적 큼 별도 토픽)"* 명시. 면적 점검 후 처리:

- **~3 파일 + 100줄 이내**: 본 묶음 처리
- **그 이상**: 부장님 보고 + 별 토픽 분리 (Phase B 자체를 건너뛰고 Phase C 진입)

#### B-2. 정리 작업 (면적 적합 시)

옛 묶음 5 (Floor hook 화) 원복 후 잔존 자리. apply_floor_actions 의 `peer_map` / `socket` 인자가 chain caller 시그니처에서 사용 안 되는 underscored 자리로 남아있음. 호출 시점부터 시그니처 정리.

빌드: `cargo build -p oxsfud`

---

### Phase C — §3.6 주요 모듈 `//!` 시작 주석 표준화

각 모듈 시작 주석에 다음 3섹션 명시 (Rust convention `//!` 활용):

```rust
//! <모듈 이름> — <한 줄 책임>
//!
//! ## 책임
//! - <항목 1>
//! - <항목 2>
//!
//! ## 핵심 자료구조
//! - <구조체 1>: <역할>
//! - <구조체 2>: <역할>
//!
//! ## 호출처
//! - <호출자 1>: <시점>
//! - <호출자 2>: <시점>
```

#### C-1. 적용 대상 (우선 6개 모듈, 면적 점검 후 확장)

| 모듈 | 우선순위 | 현재 상태 |
|------|---------|----------|
| `room/peer.rs` | ★ | 일부 (페이지 헤더만) |
| `room/publisher_stream.rs` | ★ | 일부 |
| `room/subscriber_stream.rs` | ★ | 일부 |
| `room/floor.rs` | ★ | 일부 |
| `transport/udp/mod.rs` | ★ | 양호 (이미 모듈 구조 명시) |
| `signaling/handler/mod.rs` | ★ | 부재 추정 — 확인 |

#### C-2. 우선순위 외 모듈 (시간 여유 시)
`room/floor_broadcast.rs`, `room/slot.rs`, `transport/udp/ingress.rs`, `signaling/handler/track_ops.rs`, `hooks/stream.rs`, `datachannel/mod.rs`.

빌드: `cargo build -p oxsfud` (주석만이라 영향 0)

---

### Phase D — §3.5 `wire_v3_catalog.md` 신설

**파일**: `context/design/wire_v3_catalog.md` (신규)

#### D-1. 카탈로그 구조

```markdown
# Wire v3 카탈로그 — Client ↔ Server 명세

> 작성: 2026-05-19 (묶음 8 운영성 마무리)
> 단일 출처: 각 op 의 (요청 body / 응답 body / broadcast 이벤트) 스키마

## 0. 공통 wire frame

`[8B WireHeader][body JSON]`

## 1. 시그널링 op 카탈로그

### 1.1 Client → Server (요청)

| op | 이름 | 요청 body | 응답 body | 비고 |
|---|---|---|---|---|
| 1  | HEARTBEAT | — | — | hub 전용 |
| 3  | IDENTIFY  | `{token, extra?}` | `{ok}` | JWT |
| ... | ...     | ... | ... | ... |

### 1.2 Server → Client (이벤트)

| op | 이름 | 이벤트 body | 발생 시점 | 비고 |
|---|---|---|---|---|
| 0   | HELLO | `{heartbeat_interval}` | 연결 직후 | — |
| 100 | ROOM_EVENT | `{type, room_id, user_id, ...}` | participant_joined/left/etc | — |
| ... | ... | ... | ... | ... |

## 2. Floor / PTT (MBCP)

(DC svc=0x01, TS 24.380 native TLV — PROJECT_MASTER L240-260 참조)

## 3. 어드민 / Telemetry

(op 110, op 30 — PROJECT_MASTER L240-260 참조)
```

#### D-2. 데이터 출처
- `crates/oxsig/src/opcode.rs` — op 카탈로그
- `crates/oxsfud/src/signaling/message.rs` — body 스키마
- `crates/oxsfud/src/signaling/handler/` — 각 op 처리 자리

#### D-3. 작성 분량 가이드
- 한 op 당 1행 — 짧고 명확
- 상세 명세 (예: PTT MBCP TLV) 는 PROJECT_MASTER 또는 별 design doc 링크
- 200~400줄 예상

---

### Phase E — §3.1 PROJECT_MASTER 갱신 (분업)

#### E-1. 김대리 명세 (지침에 직접 포함 — 김과장은 그대로 적용)

PROJECT_MASTER.md 갱신 항목 (묶음 1~7 산출 반영):

| 자리 | 갱신 내용 |
|------|----------|
| §시그널링 프로토콜 (L185 부근) | Floor Control (40/41/42): *"WS JSON Floor path 완전 삭제됨"* 표현 정합 확인 |
| §시그널링 프로토콜 (L218 부근) | op=53 SCOPE_UPDATE 설명에 *"pub_add/pub_remove 폐기"* 명시 (Phase A 묶음 1) |
| §미디어 아키텍처 — Cross-Room scope (L496-571) | *"sub_rooms 전용 의미 축소"* 명시. `pub_rooms: ArcSwap<RoomSet>` → `pub_room: ArcSwap<Option<RoomId>>` 정합 (묶음 3 산출) |
| §마일스톤 (L490-496 부근) | 묶음 1~7 마일스톤 5건 추가:<br>- 묶음 1: 모델 단순화 (Pan-Floor + Cross-Room publish 폐기, 2026-05-18, bfeb987)<br>- 묶음 2: 코드/주석 청결성 (-777줄, 2026-05-18, bfeb987)<br>- 묶음 3: 자료구조 일관성 ① pub_room 단수 정합 (2026-05-18, 4a5b7f3)<br>- 묶음 4: PLI Governor 통합 + F8 해소 (2026-05-18, 7 commits)<br>- 묶음 6: Hook 본문 + State 천이 agg-log + hooks/floor.rs 빈 틀 (2026-05-19, 5 commits) |
| §핵심 학습 & 원칙 (L633-755 부근) | 신규 원칙 추가:<br>- *"hook 분류 = 횡단 관심사 fire-and-forget 만. 주 흐름은 자기 도메인 모듈"* (묶음 5 분류 오류 정합)<br>- *"표현 정확도 — 폐기/이주/마이그/통합 동사 검증"* (묶음 2 반성 정합) |
| §기각된 접근법 (L757-833 부근) | 신규 항목 추가:<br>- *"MBCP 주 흐름을 hook 으로 이주 — 분류 오류"* (묶음 5)<br>- *"미리 만들어둔 빈 placeholder + TODO — YAGNI 위반"* (묶음 7)<br>- *"on_peer_phase 본문에 agg-log 이주 — metadata 손실 vs 시그니처 확장 trade-off"* (묶음 6) |
| §세션 컨텍스트 (L877 부근) | *"분업 체계 (2026-05-17~)"* 본문 강화 — 묶음 1~7 실증 |

#### E-2. 김과장 적용 작업

E-1 명세를 그대로 PROJECT_MASTER.md 에 적용. 김대리 명세 외 *자의적 갱신 금지* — 발견 자리는 *발견_사항* 으로 보고만.

빌드: 영향 없음 (md 파일).

---

### Phase F — 최종 검증 + 보고

```bash
cargo build --release -p oxsfud
cargo test --release -p oxsfud
# 194 PASS 유지 확인

# 잔존 검사
grep -rn "ingress_mbcp" crates/oxsfud/src/   # 0
grep -n "_peer_map\|_socket:" crates/oxsfud/src/datachannel/mod.rs   # 0 (Phase B 처리 후)

# 신규 파일 확인
ls -la context/design/wire_v3_catalog.md

# PROJECT_MASTER 갱신 확인
git diff PROJECT_MASTER.md | head -50
```

리뷰 보고:
1. git diff --stat 통계
2. 주요 변경 파일 5개 선별
3. 잔존 grep 결과
4. F25 면적 점검 결과 (본 묶음 처리 vs 별 토픽 분리)
5. `context/202605/20260520a_operability_wrapup_done.md` 작성

---

## §5 변경 영향 범위

| 파일 | 변경 종류 |
|------|----------|
| `transport/udp/ingress_mbcp.rs` | **파일 삭제** (Phase A) |
| `transport/udp/mod.rs` | 모듈 구조 주석 1줄 제거 (Phase A) + §3.6 `//!` 표준화 (Phase C, 이미 양호) |
| `datachannel/mod.rs` | `process_association_events` chain 시그너처 정리 (Phase B) |
| `room/peer.rs`, `room/publisher_stream.rs`, `room/subscriber_stream.rs`, `room/floor.rs`, `signaling/handler/mod.rs` | `//!` 시작 주석 표준화 (Phase C) |
| `context/design/wire_v3_catalog.md` | **신규** (Phase D) |
| `PROJECT_MASTER.md` | E-1 명세 적용 (Phase E) |

**oxlens-home / oxlens-sdk-core**: 범위 외.

---

## §6 운영 룰

1. 정지점 없음 — Phase A→F 자유 진행. Phase 단위 commit 분리
2. **Phase B 면적 점검 의무** — 김과장 분석 후 적합/부적합 판단 + 부장님 보고
3. **PROJECT_MASTER 갱신은 E-1 명세 그대로** — 자의적 추가 금지. 발견 자리는 *발견_사항* 으로 보고만
4. 추가 변경 금지 — §5 영향 범위 외 파일 손대지 말 것
5. 2회 실패 시 중단
6. 완료 보고 필수 — `context/202605/20260520a_operability_wrapup_done.md`

---

## §7 기각 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| F26 `ingress_mbcp.rs` 보존 (역사 자료) | mod 등록 없는 dead 파일. git history 가 역사 자리 — 작업 디렉토리에 dead 보존 불필요 |
| §3.3 state dump 통합 도구 본 묶음 처리 | 도구 신설 = 큰 자리. 본 묶음 *문서 위주* 정합 안 됨 |
| §3.4 trace_id 본 묶음 처리 | axis4 자체 *별 토픽 권고*. 큰 작업 |
| §3.5 wire 카탈로그를 PROJECT_MASTER 흡수 | PROJECT_MASTER 이미 862줄. 외부 클라 참조 자리는 design/ 가 자연 |
| §3.6 디렉토리별 README.md 파일 | 검색 부담. Rust convention `//!` 이 자연 |
| F27 dead_code allow 제거 (호출처 임시 추가로 회피) | 미래 채움 자리 의도 명시 — 인위 호출 추가는 *false 호출처* 자리 |
| PROJECT_MASTER 자의적 갱신 (김과장이 발견 자리 직접 추가) | 분업 위반. 명세는 김대리 영역 |

---

## §8 산출물

- git commit 5~7건 (Phase 단위 분리)
- `cargo test --release -p oxsfud` PASS (194 유지)
- 신규 파일 1건: `context/design/wire_v3_catalog.md`
- 갱신 파일: `PROJECT_MASTER.md`
- 완료 보고: `context/202605/20260520a_operability_wrapup_done.md`

---

## §9 시작 전 확인

```bash
cargo test --release -p oxsfud 2>&1 | tail -3   # 194 PASS
grep -n "mod ingress_mbcp" crates/oxsfud/src/transport/udp/mod.rs   # 0 (이미 미등록 확인)
ls -la crates/oxsfud/src/transport/udp/ingress_mbcp.rs   # 존재 확인 (삭제 대상)
grep -n "process_association_events" crates/oxsfud/src/datachannel/mod.rs   # 자리 파악
grep -c "^//! " crates/oxsfud/src/room/peer.rs   # 현재 doc 주석 줄수
wc -l PROJECT_MASTER.md   # 862줄 추정 — 갱신 후 +20~50줄 예상
```

---

## §10 직전 작업 처리

직전: 묶음 7 (scope 통지 흔적 제거) 완료 + 미니 정정 1건 (hooks/media.rs:23 scope 단어) 완료. HEAD = 194 PASS 유지.

본 묶음 8 = 운영성 마무리. 코드 동작 변경 0 (dead 청소 + 주석 + 문서 위주). 클라 wire 영향 0.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-19*
