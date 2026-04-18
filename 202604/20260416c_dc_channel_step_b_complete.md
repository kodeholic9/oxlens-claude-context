# 2026-04-16c — DC Channel Phase 1 Step B 완료 (label "unreliable" + readiness 버퍼링)

**영역**: 서버 + SDK (Rust 3파일 + JS 3파일)
**전 세션**: `20260416b_ptt_virtual_remove_mbcp_queue_dc_design` (Step A 완료 + Step B 4/6)

---

## 요약

Phase 1 Step B 6파일 rename + 구조 확장 완료. DC label `"mbcp"` → `"unreliable"` 원샷 교체, `Participant.dc_tx` → `dc_unreliable_tx` + 신규 `dc_unreliable_ready: AtomicBool` + `dc_pending_buf: Mutex<VecDeque<Vec<u8>>>` 도입. DCEP Open 이전 발생한 floor 이벤트를 pending_buf에 누적하고 Open 시점에 drain (D5 readiness 버퍼링). 락 순서 통일(buf → tx)로 broadcast/Open 간 race 차단. 미지 label은 `dc:unknown_label` warn agg-log + ACK 미전송. 부장님 재입장 반복 검증 시 `[DC] unreliable channel open/closed` 정상 순환 확인.

---

## 완료 파일 (6)

### 서버 (3)

**1. `crates/oxsfud/src/room/participant.rs`**
- 필드 rename: `dc_tx: Mutex<Option<mpsc::Sender<Vec<u8>>>>` → `dc_unreliable_tx`
- 신규: `dc_unreliable_ready: AtomicBool` — DCEP Open 수신 완료 플래그
- 신규: `dc_pending_buf: Mutex<VecDeque<Vec<u8>>>` — Open 전 메시지 누적 버퍼
- 상수: `pub const DC_PENDING_BUF_MAX: usize = 64;` (FIFO, 초과 시 oldest drop)
- import 추가: `AtomicBool`, `VecDeque`

**2. `crates/oxsfud/src/datachannel/mod.rs`**
- `const DC_LABEL_UNRELIABLE: &str = "unreliable";`
- DCEP Open label 매칭: `"unreliable"`만 accept. 미지 label은 `[DC] dc:unknown_label label=X user=Y` warn + ACK 미전송
- 신규 함수 `drain_pending_buf_and_mark_ready(participant)`:
  1. `dc_pending_buf` 락 획득
  2. 락 하에서 `dc_unreliable_tx` 락 획득 → `while let Some(pkt) = buf.pop_front()` try_send
  3. `dc_unreliable_ready.store(true, Ordering::Release)` (여전히 buf 락 보유 중)
  4. buf 락 해제
- `handle_dc_binary` label 매칭: `"mbcp"` → `DC_LABEL_UNRELIABLE`
- run_sctp_loop 종료: `dc_unreliable_tx = None` + `dc_unreliable_ready.store(false, Release)`
- `participant.dc_tx` 전수 → `participant.dc_unreliable_tx`

**3. `crates/oxsfud/src/room/floor_broadcast.rs`**
- import: `Ordering`, `DC_PENDING_BUF_MAX`
- 신규 헬퍼 `send_dc_wrapped(p, wrapped)` — broadcast/unicast 공통:
  ```rust
  let buf_guard = p.dc_pending_buf.lock()?;
  if p.dc_unreliable_ready.load(Ordering::Acquire) {
      drop(buf_guard);  // ★ 락 해제 후 tx 락
      if let Some(tx) = p.dc_unreliable_tx.lock()?.as_ref() { tx.try_send(...) }
  } else {
      // pending 적재, MAX 초과 시 pop_front
      buf.push_back(...)
  }
  ```
- `broadcast_dc` / `send_dc_to_participant` 모두 `send_dc_wrapped` 경유

### 클라 (3)

**4. `core/engine.js`**
- constructor 2줄만 변경:
  - `this._mbcpChannel = null;` → `this._unreliableCh = null;`
  - `this._dcReady = false;` → `this._dcUnreliableReady = false;`

**5. `core/sdp-negotiator.js`**
- `_setupDataChannel`:
  - `createDataChannel("mbcp", ...)` → `createDataChannel("unreliable", ...)`
  - 로그 `"[DC] mbcp channel open/closed/error"` → `"[DC] unreliable channel ..."`
  - `this.engine._mbcpChannel` / `_dcReady` → `_unreliableCh` / `_dcUnreliableReady`
- `teardown`: DC 정리 필드명 변경
- `_handleDcMessage` 경고 로그 "Phase 1 Step A" → "Phase 1 Step B"

**6. `core/ptt/floor-fsm.js`**
- `_sendDc(pkt)` 내부:
  - `this.sdk._mbcpChannel` → `this.sdk._unreliableCh`
  - `this.sdk._dcReady` → `this.sdk._dcUnreliableReady`

---

## 핵심 설계: readiness 동시성

### 문제
`floor_broadcast`가 `dc_unreliable_ready=false` 로드한 후 pending_buf 락을 잡는 사이에, DCEP Open이 drain + ready=true 완료하면, broadcast가 잡은 pending_buf에 적재한 메시지는 stuck(영영 tx로 전달 안 됨).

### 해법 — 락 순서 통일 (buf → tx)

**broadcast (`send_dc_wrapped`)**:
1. `dc_pending_buf` 락 획득
2. 락 하에서 `dc_unreliable_ready.load()` 체크
3. `ready=true` → buf 락 해제 → `dc_unreliable_tx` 락 → try_send
4. `ready=false` → buf에 적재 → 락 해제

**Open (`drain_pending_buf_and_mark_ready`)**:
1. `dc_pending_buf` 락 획득
2. 락 하에서 `dc_unreliable_tx` 락 → drain → tx 락 해제
3. 여전히 buf 락 보유 중 `dc_unreliable_ready.store(true)`
4. buf 락 해제

**핵심**: `ready` 값이 전환되는 크리티컬 섹션이 반드시 `dc_pending_buf` 락으로 보호됨. broadcast가 ready 상태를 관찰하는 순간에도 동일 락을 쥐고 있으므로 Open이 끼어들지 못한다.

### 락 중첩 안전성
- broadcast: buf 먼저, 필요 시 buf 해제 후 tx → 동시 보유 없음
- Open: buf → tx → tx 해제 → ready store → buf 해제 → 중첩 허용되지만 순서 동일
- 두 경로 모두 `buf → tx` 순서 유지 → deadlock 없음

---

## 미지 label 방어 (D1)

기존: label `"mbcp"`만 알고 있음. 다른 label 도착 시 동작 미정의.

변경 후: `DC_LABEL_UNRELIABLE`만 accept. 그 외 label은:
- `warn!("[DC] dc:unknown_label label=X user=Y")` agg-log
- DCEP ACK 미전송 (peer에 "채널 수락 안 함" 신호)
- channels 리스트 미등록 → 후속 binary 수신 시 "unknown stream" 경고

이렇게 하면 향후 클라/서버 업그레이드 비대칭 상황에서 조용한 오작동 대신 명시적 경고가 남는다.

---

## 검증

부장님 실시험 — 클라 콘솔:
```
[DC] unreliable channel open
[DC] unreliable channel closed
[DC] unreliable channel open
[DC] unreliable channel closed
```

나가기/입장 반복 패턴 = 정상. 이전 바이너리 잔존이나 open→close 비정상 반복이 아님.

**서버 빌드**: Rust rename 통과. `dc_tx` 다른 파일 잔존 참조 없음 (helpers/admin/tasks/room_ops 모두 clean).

---

## 오늘의 지침 후보

1. **락 순서 통일이 atomic race 방어의 정석** — atomic 플래그만 믿고 lock-free로 가려다 broadcast가 stuck pending을 만드는 함정 반복. 전환(store)과 관찰(load)이 같은 mutex 내부에 있어야 한다. 원자 플래그는 "안정 상태" 표현용이지 "전환 순간" 보호용이 아님.
2. **rename은 컴파일러에 맡긴다** — `grep` 돌릴 수 없는 환경에서 dc_tx 참조처 모두 추적하려다 시간 낭비. 확실한 경로 3~4곳만 먼저 고치고 `cargo build` 에러를 내비게이션으로 쓰면 누락 없이 완료. Rust의 강점을 활용.
3. **미지 입력은 조용히 무시하지 말고 agg-log로 남긴다** — Phase 전환 중에는 클라/서버 버전 불일치가 흔함. 안 보이는 오작동보다 눈에 띄는 warn이 낫다. `dc:unknown_label`처럼 카테고리 prefix 붙여 어드민에서 필터 가능하게.

---

## 오늘의 기각 후보

1. **pending 버퍼링 없이 ready 전에 floor broadcast는 무조건 drop** — 처음 검토에서 "DC open 전 이벤트는 누락돼도 괜찮다"로 갔지만, 실제로는 DCEP 핸드셰이크 수~수십 ms 사이에 발생하는 Granted/Taken이 유실되면 첫 발화자 화면이 늦게 뜬다. 64개 FIFO 버퍼가 정석.
2. **DC reliable 채널을 Step B에 함께 도입** — label 전환하는 김에 reliable도 추가하자는 유혹. 그러나 reliable은 Chat/State Sync가 생길 Phase 2에서 필요. 지금 도입하면 검증 대상만 늘어나고 유스케이스 없음. Phase 2까지 미룸.
3. **admin 스냅샷에 `dc_unreliable_ready` / `dc_pending_buf_len` 즉시 추가** — Step C에서 DcMetrics와 함께 묶어서 설계하는 게 일관성. 단독 추가하면 admin JS 쪽이 Step C에서 두 번 고쳐야 함.

---

## 다음 세션 진입 지점

**Step C — DcMetrics + admin 스냅샷 확장**

1. `common::telemetry` + `metrics_group!` 기반 `DcMetrics` 생성 (설계서 §4):
   - 서비스별 송수신 카운터 13개 (tx_mbcp, rx_mbcp, tx_speakers, rx_speakers 등)
   - 표준 svc 고정 + `_app` 버킷 (0x10+ 사용자 정의) + `_unknown` 버킷 (스펙 위반 수신)
   - invalid_frame, pending_drop (MAX 초과 시 oldest drop 건수), unknown_label 카운트
2. `oxsfud/metrics/sfu_metrics.rs`에 `pub dc: DcMetrics` 추가
3. floor_broadcast.rs의 `send_dc_wrapped`에 카운터 inc 호출 (pending_drop 포함)
4. datachannel/mod.rs에 invalid_frame / unknown_label 카운터 inc
5. admin 스냅샷 `participants[].dc = { unreliable_ready, pending_buf_len }` 추가
6. admin JS 패널에 SFU → DC 섹션 추가

**Step D — Active Speakers DC 전환 (svc=0x02)**

1. 서버 tasks.rs active_speaker_task에서 WS broadcast(op=144)와 동시에 DC svc=0x02 broadcast 추가 (병행 전송)
2. 바이너리 포맷 간단: N entries × (ssrc(4B) + level(1B) + user_id_len(1B) + user_id)
3. 클라 sdp-negotiator `_handleDcMessage`에서 `SVC.SPEAKERS` 분기 추가 → Room에 emit
4. 클라 moderate.js가 WS 대신 DC 이벤트 우선 수신 (fallback으로 WS 유지)
5. 검증 후 WS op=144 제거는 Phase 2 이후

우선순위: **Step C → Step D**. C에서 깔아둔 카운터로 D 검증이 바로 됨.

---

## PENDING 목록

- [ ] Step C: DcMetrics 13개 + admin 스냅샷 확장 (dc_unreliable_ready, dc_pending_buf_len)
- [ ] Step D: Active Speakers DC 전환 (svc=0x02, WS 병행)
- [ ] DC Phase 2: reliable 채널 + Chat/State Sync
- [ ] DC Phase 3: WS binary fallback + event_bus binary + gRPC oneof
- [ ] 세션 타임라인 텔레메트리 설계 (별도 세션)
- [ ] MBCP 큐 갱신 현장 재검증 (3인+, 부장님 실시험에서 이번 세션 대상 아님 — 별도)
- [ ] `IDENTIFY` token validation (long-standing)
- [ ] NetEQ collapse fix (libwebrtc, deferred)

---

*author: kodeholic (powered by Claude)*
