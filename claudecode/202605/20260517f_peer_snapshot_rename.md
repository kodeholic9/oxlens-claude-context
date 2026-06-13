# 작업 지침: PeerSnapshot DTO 신설 + set_phase → set_phase_state rename
> 완료 보고 → [20260517f_peer_snapshot_rename_done](../../202605/20260517f_peer_snapshot_rename_done.md)

> Claude Code 작업 지침. 본 파일이 단일 출처. 별도 설계서 없음.
> 작성: 2026-05-17 (claude.ai 김대리, admin cleanup (`20260517e`) 종결 후 즉시 진입)
> 검토자: 부장님 (kodeholic)
> 클라이언트 wire 변경: **0** (admin JSON 필드 변경 없음, 함수 rename 은 내부)

> **본 작업은 *Hook Phase 3 후속 cleanup 묶음 2*** — 위험도 낮음. 정지점 없음. 통합 리뷰. 두 토픽 (PeerSnapshot 신설 + 함수 rename) 한 묶음 sfu-server 1 commit.

---

## 0. 작업 시작 전 의무 점검

```bash
cd ~/repository/oxlens-sfu-server
git status
git diff --stat HEAD
git log --oneline -5  # 직전 commit = admin cleanup (01e0456) 일 것

# 직전 회귀 확인
cargo test --release -p oxsfud  # 252+ tests, FAIL 시 작업 진입 금지
```

### 추가 사전 점검

```bash
# 1. set_phase 호출처 전수 grep (rename 대상)
grep -rn "\.set_phase(" crates/oxsfud/src/ | wc -l  # 호출처 수 확인
grep -rn "\.set_phase(" crates/oxsfud/src/

# 2. set_phase 정의 자리 3개 확인
grep -n "pub fn set_phase" crates/oxsfud/src/room/peer.rs crates/oxsfud/src/room/publisher_stream.rs crates/oxsfud/src/room/subscriber_stream.rs

# 3. Peer.phase 직접 접근 자리 (admin.rs:272 외에 더 있는지)
grep -rn "peer\.phase\.load\|\.phase\.load" crates/oxsfud/src/ | grep -v "set_phase_state\|set_phase\|publish_state\|subscribe_state"

# 4. Peer 의 다른 캡처 후보 필드 — last_seen / suspect_since / sub_rooms / pub_rooms / is_recorder
grep -n "last_seen\|suspect_since\|sub_rooms:\|pub_rooms:\|is_recorder" crates/oxsfud/src/room/peer.rs

# 5. Hook 함수 이름 — on_*_phase 자리 (§3.3 결정에 따라 rename 여부)
grep -rn "fn on_peer_phase\|fn on_publisher_phase\|fn on_subscriber_phase\|on_peer_phase(\|on_publisher_phase(\|on_subscriber_phase(" crates/oxsfud/src/
```

---

## 1. 컨텍스트

### 1.1 직전 작업 (`20260517e`, admin cleanup) 결과

- TrackSnapshot 에 `phase: PublishState` 필드 추가
- SubscriberStreamSnapshot 신설 (F17 흡수)
- admin.rs 직접 접근 3자리 제거
- hooks::ctx() OnceLock 1회 warn

### 1.2 본 작업이 푸는 2개

1. **F18 — PeerSnapshot DTO 신설** — `Peer.phase.load(...)` 직접 접근 잔존 (admin.rs:272). Peer 만 snapshot DTO 없음. PublisherStream / SubscriberStream 패턴 완성을 위해 신설
2. **set_phase → set_phase_state rename** — 부장님 결정 (2026-05-17 세션): *"단계라는 종류의 상태"* 의미를 함수 이름에 명시. 부장님 메모리의 *향후 리팩터 시 현행화* 자리 실행

### 1.3 부장님 결정 (2026-05-17 세션)

| 항목 | 결정 |
|------|------|
| F18 진입 | 옵션 B 묶음 — *위험도 낮은 mechanical* 두 토픽 묶어 1 commit |
| 함수 이름 변경 | `set_phase` → `set_phase_state` |
| hook 함수 이름 | ★ §3.3 결정 자리 (rename 통일 vs 유지) |

---

## 2. 결정된 사항 (확정, 변경 금지)

1. **PeerSnapshot 신설** — Peer 의 atomic / 잠금 필드 시점 캡처
2. **set_phase → set_phase_state rename** — 3 정의 자리 + 모든 호출처 일괄
3. **admin.rs:272 직접 접근 제거** — PeerSnapshot 경유로 통일
4. **클라 wire 영향 0** — admin JSON 필드 무변경, 함수 rename 은 서버 내부

---

## 3. 결정 추천 (Claude Code 선조치 자리)

### 3.1 ★ PeerSnapshot 캡처 필드

기본 후보 (사전 점검 §0 #4 grep 결과 보고 Claude Code 가 결정):

```rust
pub struct PeerSnapshot {
    pub peer_state:    PeerState,       // 현재 admin.rs:272 자리 — 최우선
    pub last_seen_ms:  u64,             // STALLED / liveness 분석 자리
    pub suspect_since_ms: Option<u64>,  // Suspect 천이 시점 (option)
    pub sub_set_id:    String,          // scope 추적
    pub pub_set_id:    String,          // scope 추적
    pub is_recorder:   bool,            // recorder 분기
}
```

**Claude Code 선조치 자리**:
- admin.rs 의 *현재 다른 직접 접근* 자리 grep 결과 보고 *실제로 필요한 필드만* 채택
- 과잉 캡처 회피 — *지금 안 쓰는 필드는 신설하지 말 것* (부장님 §3.6 *"호출처 grep 후 결정"* 정합)
- 최소 `peer_state` 1 필드만 박아도 OK. 다른 필드는 *별 작업에서 호출처 발생 시* 추가

→ 추천: **admin.rs 현재 사용 자리만 채택**. 미래 후보는 주석으로만 명시.

### 3.2 ★ snapshot 메서드 패턴 — PublisherStream / SubscriberStream 와 일관

```rust
impl Peer {
    pub fn snapshot(&self) -> PeerSnapshot {
        PeerSnapshot {
            peer_state: PeerState::from_u8(self.phase.load(Ordering::Relaxed)),
            // ... 다른 필드 캡처 패턴
        }
    }
}
```

다른 atomic 필드 (last_seen, suspect_since) 의 캡처는 `Ordering::Relaxed` 일관. lock 필드 (sub_set_id, pub_set_id) 는 `ArcSwap` 경유 — 시점 race 자연 회피.

### 3.3 ★ hook 함수 이름 — 결정 자리

함수 이름이 `set_phase_state` 로 변경되면 hook 핸들러 이름도?

| 옵션 | hook 이름 |
|------|----------|
| **A** (추천) | `on_peer_phase` / `on_publisher_phase` / `on_subscriber_phase` *유지* — 내부 모듈 함수명. 외부 API rename 과 분리 |
| B | `on_peer_phase_state` 등 *통일 rename* — *이름이 의미를 표현* 정합. 변경 면적 약간 늘어남 |

저는 옵션 A 추천. **이유**:
- hook 핸들러는 *내부 통신 함수*. 외부 API (set_phase_state) 와 *대칭 의무 없음*
- 직전 set_phase ↔ enum `*State` 단어 불일치 패턴과 일관 (set_phase ↔ PeerState 정합)
- hook trigger 호출 자리 (set_phase_state 본문 안) 만 1자리 변경 — `on_peer_phase(prev, curr, ...)` 그대로

부장님이 옵션 B 결정 시 — Claude Code 가 사후 보고 자리에 *hook 이름 변경 자리* 명시.

---

## 4. 단계별 작업

### Phase A: PeerSnapshot DTO 신설

**대상 파일**:
- `crates/oxsfud/src/room/peer.rs`
- `crates/oxsfud/src/signaling/handler/admin.rs`

**작업**:
1. `peer.rs` 에 `PeerSnapshot` struct 정의 — §3.1 채택 필드만 (최소: `peer_state`)
2. `impl Peer::snapshot()` 메서드 신설 — 캡처 패턴 §3.2
3. `admin.rs:272` 의 `PeerState::from_u8(peer.phase.load(Ordering::Relaxed)).as_str()` → `peer.snapshot().peer_state.as_str()` 로 변경
4. 사전 점검 §0 #3 grep 결과로 *추가 직접 접근 자리* 발견 시 — 함께 정리 OR 발견_사항 으로 보고 (운영 룰 §6.2)

**검증**:
```bash
cargo build --release
grep -n "peer\.phase\.load" crates/oxsfud/src/signaling/handler/admin.rs  # 0건
```

### Phase B: set_phase → set_phase_state rename

**대상 파일**:
- 정의 자리 3개: `peer.rs` / `publisher_stream.rs` / `subscriber_stream.rs`
- 호출처: 사전 점검 §0 #1 grep 결과 모든 자리

**작업**:
1. 정의 자리 3개 함수 이름 변경: `set_phase` → `set_phase_state`
2. 호출처 일괄 rename — sed 또는 IDE refactor. 다음 자리 예상:
   - `track_ops.rs` (PUBLISH_TRACKS / TRACKS_ACK 핸들러)
   - `peer_map.rs` (reaper Suspect/Zombie/Alive)
   - `ingress.rs` (PublishState::Active "first_rtp")
   - 테스트 자리 (peer_map.rs / peer.rs 내 #[test] 함수들)
3. hook trigger 호출 자리 (각 set_phase_state 본문 안) — §3.3 옵션 A 채택 시 *hook 함수 이름 유지*. 옵션 B 채택 시 *hook 함수 이름도 rename*

**검증**:
```bash
grep -rn "\.set_phase(" crates/oxsfud/src/  # 0건
grep -rn "fn set_phase\b" crates/oxsfud/src/  # 0건 (set_phase_state 만 남음)
cargo build --release
cargo test --release -p oxsfud  # 252+ tests PASS
```

### Phase C: 검증

```bash
# 빌드 + 회귀
cargo build --release
cargo test --release -p oxsfud

# 잔존 참조 grep
grep -rn "\.set_phase(\b" crates/oxsfud/src/                          # 0건 (set_phase_state 만 남음)
grep -rn "peer\.phase\.load" crates/oxsfud/src/signaling/handler/admin.rs  # 0건

# 함수 이름 변경 누락 확인
grep -rn "fn set_phase\b" crates/oxsfud/src/                          # 0건
```

---

## 5. 변경 영향 범위

| 파일 | 변경 종류 | 예상 줄수 |
|------|---------|------|
| `crates/oxsfud/src/room/peer.rs` | PeerSnapshot struct + snapshot() 메서드 + set_phase_state rename | +35 / -3 |
| `crates/oxsfud/src/room/publisher_stream.rs` | set_phase_state rename | +1 / -1 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | set_phase_state rename | +1 / -1 |
| `crates/oxsfud/src/signaling/handler/admin.rs` | PeerSnapshot 사용 (272 자리 정리) + 추가 직접 접근 정리 (있을 시) | +3 / -3 |
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | set_phase_state 호출처 rename (PUBLISH_TRACKS / TRACKS_ACK / Intended) | +3 / -3 |
| `crates/oxsfud/src/room/peer_map.rs` | set_phase_state 호출처 rename (reaper 3자리 + 테스트 4자리) | +7 / -7 |
| `crates/oxsfud/src/transport/udp/ingress.rs` | set_phase_state 호출처 rename (first_rtp 자리) | +1 / -1 |
| `crates/oxsfud/src/hooks/stream.rs` | (§3.3 옵션 B 채택 시만) hook 함수 이름 rename | +0 또는 +5 / -0 또는 -5 |

**총 +51 / -19** (옵션 A) 또는 +56 / -24 (옵션 B). 신규 struct 1개 (PeerSnapshot). 클라 wire 영향 0.

---

## 6. 운영 룰 — 직전 `20260517e` 동일 (경량)

### 6.1 정지점 없음

Phase A / B / C 자유 진행. 통합 리뷰.

### 6.2 추가 변경 — 부장님 컨펌 후 진행

§5 영향 범위 외 파일 손대지 말 것. 단:
- Phase A 의 *추가 직접 접근 자리* 발견 시 — *PeerSnapshot 신설의 자연 연장* 으로 정합. 진행 OK + 사후 보고 (직전 F17 흡수 패턴)
- 그 외 별 문제 — 발견_사항으로 보고만

### 6.3 "2회 실패 중단"

같은 컴파일 에러 2회 시도 후 미해결 → 즉시 중단.

### 6.4 부장님 작업 중 파일 회피

oxlens-home 자리는 본 작업 영역 외. 손대지 말 것.

---

## 7. 기각된 접근법

1. **PeerSnapshot 필드 과잉 캡처** — *현재 안 쓰는 필드 박지 말 것*. 부장님 §3.6 *"호출처 grep 후 결정"* 정합
2. **hook 함수 이름 자동 rename (Claude Code 임의 결정)** — §3.3 부장님 결정 자리. 임의 진행 금지
3. **set_phase 일부만 rename** — 정의 자리 + 호출처 전수 *일괄* 처리. 부분 처리는 일관성 깨짐
4. **별 commit 분리 (PeerSnapshot 1 + rename 1)** — 묶음으로 1 commit. 사이클 깨끗

---

## 8. 작업 후 산출물

1. **변경된 파일** — 위 §5 표대로
2. **세션 파일** — `~/repository/context/202605/20260517f_peer_snapshot_rename_done.md`
   - 본 지침 기준 실제 변경 내역
   - §3.1 캡처 필드 확정 결과 + §3.3 hook 이름 결정 결과
   - Phase A 의 *추가 직접 접근 자리* 발견 사항
   - 검증 결과
   - 발견_사항: 별 문제 발견했지만 본 작업에 박지 않은 항목들
   - 오늘의 기각 후보 / 지침 후보
   - 다음 토픽 후보 (on_publisher_phase / on_peer_phase 본문 — 큰 토픽 / F19 render-detail.js 분리 / F8 GATE:PLI / handle_scope_announce_for_room / PTT 비시뮬 RTP 흐름 분석)
3. **SESSION_INDEX.md 갱신** — 한 줄 요약 (`~/repository/context/202605/` 저장)

---

## 9. 시작 전 부장님 확인 사항

- [x] §3.1 PeerSnapshot 캡처 필드 — Claude Code 호출처 grep 후 최소 채택
- [ ] §3.3 hook 함수 이름 — 옵션 A (유지) 추천, 부장님 결정
- [x] §6 운영 룰 (정지점 없음, 직전 동일)

§3.3 옵션 한 가지만 정해주시면 진입.

---

*author: kodeholic (powered by Claude) — 김대리, claude.ai 분석 세션 2026-05-17*
