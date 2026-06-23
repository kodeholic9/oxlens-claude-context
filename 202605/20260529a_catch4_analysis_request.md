# 분석 의뢰 — catch 4 옵션 D 면적/dedup 자리

**문서 ID**: `20260529a_catch4_analysis_request.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**성격**: **분석만 — 코드 변경 0.** 조사 후 보고서 작성.
**부장님 GO**: 김과장 분석 → 보고 → 김대리 옵션 D 구현 지침 박음

> 본 의뢰는 *구현 전 분석 사이클*. catch 4 옵션 D (forward 안에서 publisher PLI 직접 호출, bool 반환 폐기) 가 채택될 자리인데, 면적/dedup 자리가 미확인. 김대리가 read 만 반복하면 비효율 — 김과장이 grep/read 빠르게 + 정확히 보고.

---

## §0 컨텍스트

**catch 4 옵션 D 채택 (부장님 결정, 2026-05-29):**
- `subscriber_stream::forward` 의 `need_pli: bool` 반환 폐기 → `()` 반환
- forward 의 simulcast 분기 안에서 *발생 지점 직접 호출* (publisher 측 PLI 요청 메서드)
- `broadcast_full` 의 `pli_sent` flag + `need_pli` 분기 제거
- dedup = PLI Governor (이미 spawn_pli_burst 첫 발에 `judge_server_pli` 호출 → `pli_pending`/`min_interval`/`keyframe_already_arrived` 자연 dedup)

**미확인 자리 (본 분석 대상):**
1. forward 본문에서 publisher 측 socket/transport 접근 경로
2. `spawn_pli_burst` 호출처 전수 (catch 4 흡수 범위 결정)
3. dedup 비용 (매 sub forward × 매 RTP 호출 시 lock contention)
4. publisher 측 메서드 시그너처 후보

---

## §1 조사 항목

### 1.1 spawn_pli_burst 호출처 전수 grep

```bash
grep -rn "spawn_pli_burst" crates/oxsfud/src/
```

각 호출처에 대해:
- 파일/라인
- `log_prefix` (CAMERA_READY / FLOOR / SIM:PLI / GATE:PLI / RTP_GAP / NACK_ESC / RESYNC / GOV:UG/DG / 그 외)
- 호출 컨텍스트 (어떤 이벤트에 trigger 되는가)
- socket/transport 인자 출처 (`state.udp_socket` / `self.socket` / `transport.socket` 등)

**catch 4 흡수 대상 식별** — `SIM:PLI` (broadcast_full 의 simulcast PLI) 만 흡수. 나머지 (CAMERA_READY/FLOOR/GATE:PLI 등)는 catch 4 와 무관, 흡수 안 함. 분석 시 명시 구분.

### 1.2 forward 본문에서 publisher 측 socket 접근 경로

현재 `PacketContext` 가 `transport: &UdpTransport` 안 가짐 (publisher / target / room / plaintext / rtp_hdr / is_keyframe / sender_user_id 만). forward 안에서 `spawn_pli_burst` 호출하려면 socket 필요.

**옵션 분석:**
- **A. PacketContext 에 `transport: &UdpTransport` 추가** — forward 시그너처 영향, broadcast_full/Half fanout 호출처 정합
- **B. publisher 메서드가 자체 해결** — `PublisherStream::request_simulcast_keyframe()` 안에서 socket 어떻게 확보하는가? (peer.publish.media 에 socket 있는가? 없으면 fanout 호출처가 transport 가지고 있는가?)
- **C. 다른 경로** — `crate::hooks::ctx()` 같은 전역 (subscriber_stream hook 에서 사용 중) — publisher_stream 에서도 가능한지

각 옵션의 *실제 가능성* (compile 가능 여부) + 면적 보고.

### 1.3 매 RTP × 매 sub 호출 시 dedup 비용

옵션 D 면 `broadcast_full` 안 sub 순회마다 (각 sub forward → publisher PLI 호출) Governor lock + `cancel_pli_burst` lock 매번.

조사:
- `peer.publish.pli_state: Mutex<PliPublisherState>` — Mutex 종류 (std vs parking_lot)
- `peer.publish.pli_burst_handle: Mutex<Option<AbortHandle>>` — 동일
- 폭주 시나리오: 1 방 30 sub × 30 RTP/초 × 1 simulcast publisher = 900 lock/초 (Governor + handle 2 lock). std::Mutex 면 contention 어느 수준?
- **publisher 측 `AtomicBool` fast path** 추가 가능성 — Governor 진입 전 atomic check. 측정 후 추가 vs 사전 박기 권고

### 1.4 publisher 메서드 시그너처 후보

`PublisherStream::request_simulcast_keyframe` (또는 다른 이름):
- 인자: `&Arc<UdpTransport>` 또는 `socket: Arc<UdpSocket>` + `publisher: &Arc<Peer>` 등 — §1.2 결과 정합
- 반환: `()` (옵션 D 정합)
- 본문: 현재 broadcast_full 의 simulcast PLI 블록 (find_ssrc_by_rid + spawn_pli_burst) 이주
- 호출처: forward 1곳 (broadcast_full 의 pli_sent flag 제거 후)

`publisher` 인자가 `&Arc<Peer>` 인지 `&PublisherStream` 인지 — forward 의 `ctx.publisher: &PublisherStream` 인데 spawn_pli_burst 는 `&Arc<Peer>` 받음. 변환 가능 여부 / 추가 인자 필요 여부 보고.

### 1.5 Half fanout forward 호출처 영향

`publisher_stream.rs::fanout` 의 `is_half` 분기에서 `let _need_pli = sub_stream.forward(...)` 가 반환값 ignore. 옵션 D 면 `forward` 가 `()` 반환 → `let _ = sub_stream.forward(...)` 또는 `sub_stream.forward(...);` 로 정리. *동작 영향 0 확인.*

---

## §2 산출물

**보고서 자리**: `~/repository/context/202605/20260529a_catch4_analysis_done.md` (**202605/ 자리** — claudecode/ 아님. 분석 산출물이라 일반 context)

**구조:**
```
§1 spawn_pli_burst 호출처 표 (파일/라인/prefix/socket 출처/catch4 흡수 여부)
§2 socket 접근 경로 옵션 A/B/C 비교 (실제 가능성 + 면적)
§3 dedup 비용 측정 (Mutex 종류 + 시나리오 + AtomicBool fast path 권고)
§4 publisher 메서드 시그너처 후보 (인자/반환/본문/호출처)
§5 김과장 권고 (옵션 D 구현 자리 전반)
```

§5 김과장 권고에 *옵션 D 실제 박을 때 정합되는 자리* 선조치 보고. 김대리가 받아서 구현 지침에 반영.

---

## §3 운영 룰

1. **코드 변경 0** — read/grep 만. write 금지.
2. **2회 실패 시 중단** — 어떤 자리 모르겠으면 보고서에 "미확인" 명시 + 재의뢰.
3. **시간 한도** — 1 사이클 (30분 이내). 길어지면 부분 보고 + 재의뢰.
4. **업계 선례 (mediasoup/LiveKit)** — prior knowledge 있으면 §5 권고에 참조. 없으면 *web fetch 금지* (분석 사이클 비대 회피).

---

## §4 시작 전 확인

1. catch 4 옵션 D 이해? (forward 반환 () + simulcast 분기 안 직접 호출 + dedup = Governor)
2. 코드 변경 0 — 이해했는가?
3. §1 5항목 모두 조사. 미확인 항목은 §2 보고서에 명시.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-29*
