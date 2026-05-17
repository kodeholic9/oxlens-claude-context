# Hook 시스템 Phase 1 — Media Ready (4종 횡단 관심사 분리)

> 작업 지침: `~/repository/context/claudecode/202605/20260517_hook_phase1_media_ready.md`
> 빌드 + 252 tests 회귀 PASS. smoke test 는 부장님 환경 수동.

---

## 한 줄 결과

- `MediaState` enum 격상 + `start_dtls_handshake` 천이 보강 + `crate::hooks::media::on_subscribe_ready` 4종 핸들러 분리. `udp/mod.rs` 의 60+줄 인라인 블록이 1줄 트리거로 축소.

---

## 변경 파일 일람

| 파일 | 변경 종류 | 줄수 |
|------|---------|------|
| `crates/oxsfud/src/room/participant.rs` | `MediaState` enum 신설 + `media_ready: AtomicBool` → `media_state: AtomicU8` 격상 + `media_state()` / `set_media_state()` accessor | +57 / -10 |
| `crates/oxsfud/src/transport/udp/mod.rs` | `start_dtls_handshake` 천이 보강 (Handshaking/Failed) + Subscribe Ready 블록을 hook 1줄로 교체 + egress 함수 `pub(crate) use` 재노출 | +18 / -55 |
| `crates/oxsfud/src/hooks/mod.rs` | 신규 — `pub mod media; pub mod stream;` + 패턴 원칙 doc | +14 |
| `crates/oxsfud/src/hooks/media.rs` | 신규 — `on_subscribe_ready` + 3 handler (egress spawn / PLI / FLOOR_TAKEN) | +88 |
| `crates/oxsfud/src/hooks/stream.rs` | 신규 — Phase 2 자리 잡기 (빈 모듈) | +5 |
| `crates/oxsfud/src/lib.rs` | `pub mod hooks;` 등록 | +1 |

총 **+183 / -65**, 신규 모듈 1개 (`hooks`).

---

## 정정 내용 상세

### Phase A — MediaState enum + media_state 격상

- 신규 enum `MediaState { Idle, Handshaking, Ready, Failed }` (`#[repr(u8)]`, from_u8/as_str/Display)
- `MediaSession.media_ready: AtomicBool` 폐기 → `media_state: AtomicU8` 단일 필드
- `is_media_ready()` 시그너처 유지, 내부만 `state == Ready as u8` 비교로 교체 (호출처 무수정)
- 신규 accessor: `media_state(&self) -> MediaState` / `set_media_state(&self, s)` (Release ordering)
- `install_srtp_keys()` 마지막 store 한 줄 `self.set_media_state(MediaState::Ready)` 로 교체
- import: `AtomicBool` 제거 / `AtomicU8` 추가 — 사용처 없음 확인 후 정리

### Phase B — start_dtls_handshake 천이 보강

- `dtls_map.insert()` 직후 Handshaking 마킹 (한 줄)
- spawn task 실패 분기 3종 모두 Failed 마킹:
  - `Ok(Err(_))` DTLS 핸드셰이크 실패
  - `Err(_)` 10s timeout
  - `Err(e)` SRTP key export 실패 — **지침 §4 Phase B 명세 외 추가 1줄** (부장님 사전 승인). 의미상 동일 (handshake 자체 OK 지만 key 추출 실패 → Ready 천이 불가). 마킹 없으면 admin 에서 영원히 Handshaking 으로 보임
- 행동 변화 0 (Ready 천이 자체는 `install_srtp_keys` 안에서 그대로 발생)

### Phase C — hooks 모듈 신설

- 신규 디렉토리 `crates/oxsfud/src/hooks/` 와 `mod.rs` / `media.rs` / `stream.rs`
- `lib.rs` 18번째 모듈로 `pub mod hooks;` 등록
- `hooks/mod.rs` 모듈 doc 에 Hook 시스템 4 원칙 명시 (천이/실패 격리/주관심사 분리/Dispatcher 패턴)
- `hooks/stream.rs` 는 Phase 2 자리 잡기용 빈 모듈

### Phase D — Hook 4종 분리

- `udp/mod.rs` 의 line 497~553 (60+ 줄) → 9줄 트리거로 축소:
  ```rust
  if pc_type == PcType::Subscribe {
      crate::hooks::media::on_subscribe_ready(
          Arc::clone(&peer),
          Arc::clone(&room_hub),
          Arc::clone(&socket),
      );
  }
  ```
- `on_subscribe_ready` 안에서 `tokio::spawn` 1개로 3 handler 순차 실행 (fire-and-forget):
  - `handle_egress_spawn`: `egress_spawn_guard` CAS + `run_egress_task` spawn
  - `handle_pli_burst`: hint_room 룩업 + `send_pli_to_publishers`
  - `handle_floor_taken`: `room.floor.current_speaker()` + `build_taken` + `send_dc_to_participant`
- 4번째 handler `handle_scope_announce` 는 Phase 2 자리 (TODO 주석으로 보존)
- `egress::{run_egress_task, send_pli_to_publishers}` 를 `udp/mod.rs` 에서 `pub(crate) use` 로 재노출 — hooks 모듈에서 호출 가능. egress 모듈 자체 가시성은 그대로 (private mod)
- TODO 주석은 udp/mod.rs 에서 제거되고 hooks/media.rs 의 각 handler 위 주석으로 이주:
  - PLI 명세 정밀화 (simulcast h-only, video, Audio/PTT no-floor 제외)
  - FLOOR_TAKEN 트리거 위치 `sub_insert(R)` 시점 이동 (SCOPE_UPDATE/SET 경로 누락 해소)
  - cross-room: `peer.sub_rooms` 순회

### 행동 변화

- **로직 변화 0** — 핸들러 본문은 udp/mod.rs 의 이전 인라인 코드를 그대로 이주만 (단일 if let chain 을 if-else early return 패턴으로 평탄화한 정도)
- **천이 표현 보강** — admin/log 에서 PC 상태가 `idle/handshaking/ready/failed` 로 관찰 가능 (이전엔 `bool ready` 만)
- **실패 격리** — 한 handler 실패 (예: build_taken panic) 가 다음 handler 를 막지 않음 (별 spawn 안 쓰고 순차지만, 본문이 모두 `if let Some(...)` 패턴이라 자연스럽게 흡수)

---

## 검증 상태

- ✅ `cargo build -p oxsfud` (Phase A/B/C/D 각각 후)
- ✅ `cargo build --release` (Phase E)
- ✅ `cargo test --release -p oxsfud` — **252 passed; 0 failed**
- ✅ `grep "media_ready"` — 메서드 이름 (`is_media_ready`) 만 잔존, 필드/store 0건
- ✅ `grep "임시 스텁\|구컴파일용"` — 0건
- ⏳ smoke test — 부장님 환경 수동 1회 (단일방 conference 3인 / voice_radio PTT 회전 + admin FLOOR_TAKEN 수신 확인)

---

## 0516d 보류 토픽 매핑

지침 §1.3 "포함/제외" 기준으로 본 작업은 0516d 의 보류 토픽 #1 (C3 본정정) 의 절반을 처리:

| 0516d 보류 | 이번 세션 처리 | 비고 |
|-----------|-------------|------|
| #1 C3 본정정 — Subscribe SRTP ready PLI/FLOOR_TAKEN 분리·재배치 | **부분 처리** — 분리 (hooks/media.rs) 까지 끝. 재배치 (트리거 위치 이동, cross-room sub_rooms 순회) 는 Phase 2 자리 | 분리만 해도 udp/mod.rs 가 60줄 가벼워짐 |
| #2 PanCoordinator 제거 | 미처리 | |
| #3 pub_rooms 단일화 | 미처리 | |
| #4 Peer 헬퍼 메서드 통합 | 미처리 | |
| #5 sub_stats 위치 재검토 | 미처리 | |
| #6 ingress_mbcp.rs dead code 제거 | 미처리 | |

---

## 보류 토픽 (다음 세션 후보)

지침 §1.3 "제외" 항목들이 다음 토픽 후보:

1. **Hook Phase 2 — handle_scope_announce 구현 + 트리거 위치 이동**
   - PLI 명세 정밀화 (simulcast h-only / Audio·PTT no-floor 제외)
   - FLOOR_TAKEN 트리거를 `sub_insert(R)` 시점으로 이동 → SCOPE_UPDATE/SET 누락 해소
   - cross-room: `peer.sub_rooms` 순회 (현재는 첫 입장 방 hint)
2. **PC liveness 자리 — Suspect / Zombie 를 ParticipantPhase 에서 분리**
   - 본 작업은 stream/media 천이만 다룸. liveness 는 별도 토픽
3. **ParticipantPhase enum 자체 분해** — `PeerState` / `PublishState` / `SubscribeState` 3계층 모델
   - 본 작업이 첫 발이지만 enum 분해는 추가 토픽
4. **Floor 천이 hook 화** — claim/grant/release 의 통지/로깅 부분
5. **Hot-swap (duplex 변경) hook 화**
6. **Publisher remove hook 화**
7. **on_publish_ready / on_dtls_failed hook 추가** (hooks/media.rs 의 module doc 에 명시한 자리)

---

## 오늘의 기각 후보

1. **egress 모듈 자체 가시성 격상 (`pub(crate) mod egress;`)** — 처음엔 모듈 단위로 열까 했으나, hooks 가 필요한 건 두 함수뿐이라 `pub(crate) use egress::{run_egress_task, send_pli_to_publishers};` re-export 1줄로 좁힘. 모듈 가시성은 그대로 private 유지.
2. **handle 마다 별 `tokio::spawn`** — fire-and-forget 격리를 spawn 단위로 갖추려 했으나, 순서 의존 (egress spawn 먼저 → 그 다음 PLI/FLOOR_TAKEN) 이 있어서 1 spawn 안 순차 + 본문 `if let Some(...)` 자연 흡수로 처리. handler 함수 자체는 `?` 전파 없음 → 한 handler panic 외엔 다음 handler 계속.
3. **`Ok(Err(e))` 만 Failed 마킹** — 지침 §4 Phase B 본문에는 SRTP key export 실패 분기가 빠져 있었음. 부장님께 사전 확인 후 1줄 추가.
4. **MediaState 에 `Display` / `from_u8` 미구현** — 처음엔 admin/log 에서 굳이 안 쓸 것 같아 빼려 했으나, ParticipantPhase 스타일에 맞춰 함께 박음. 향후 admin snapshot 노출 시 자연 사용.

---

## 오늘의 지침 후보

1. **지침서 §4 의 명세 누락은 짧게 사전 확인** — Phase B 의 SRTP key export 실패 케이스처럼 의미상 자명한 누락도 §6 의 "지침 외 변경 금지" 와 충돌. AskUserQuestion 으로 30초 컨펌 받고 박는 패턴이 깔끔. 추측으로 박지 말 것.
2. **모듈 가시성은 `pub(crate) use` 재노출이 모듈 단위 격상보다 좁다** — egress 모듈을 통째로 열기 전에, 필요한 함수만 상위 모듈에서 re-export 하는 패턴 우선 시도.
3. **신규 모듈 한 번에 등록 + 채우기 보다는 빈 자리 → 본문 분리** — 본 작업처럼 Phase C (자리 잡기) + Phase D (본문) 분리가 단계별 cargo build 회귀 확인에 자연. 컴파일 단위가 작아지면 디버깅도 좁아짐.
4. **fan-out lock-free 게이트 격상 시 시그너처 유지** — `is_media_ready()` 같은 hot path 메서드는 시그너처 유지하고 내부만 교체 → 호출처 N곳 무수정. 본 작업의 ingress.rs 2곳 + RoomMember accessor 2곳 + test 2곳 모두 자동 통과.

---

## 다음 세션 진입 시 참고

- `crate::hooks::media::on_subscribe_ready` 가 본 PR 의 핵심 신규 API. cross-room / Phase 2 작업 진입 시 이 함수 안에서 `peer.sub_rooms` 순회로 확장.
- `MediaState` enum 은 `room::participant` 에서 export. admin/log 에서 PC 상태 노출 시 사용.
- `start_dtls_handshake` spawn task 의 트레이싱은 변화 없음. `[DBG:DTLS] handshake OK/FAILED/TIMEOUT` 라인은 그대로. 다만 `[DBG:DTLS] SRTP ready` 직후 hook 트리거 1줄이 들어감.

---

*author: kodeholic (powered by Claude)*
