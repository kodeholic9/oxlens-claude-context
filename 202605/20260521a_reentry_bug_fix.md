# 재입장 시 영상 미노출 100% 재연 버그 정정 (0521a)

> 세션: 2026-05-21 18:30 ~ 20:30 (낮 ~ 저녁)
> 직전 세션: `20260520d_track_dump_v22_session_close.md` (자정 ~00:25, Phase 110 미완료)
> 본 세션 = **Phase 110 본질 버그 정정** (직전 자정 짚은 100% 재연 버그 좌표)
> author: kodeholic (powered by Claude)
> **진행 모드 = 김대리 단독** (직감 키보드 부장님 좌표 따라감)

---

## §0 본 세션 본질

직전 자정 부장님 짚음:
> A 입장 → B 입장 → 영상 정상 → B 퇴장 → B 재입장 → A 측에서 B 영상 미노출 (100% 재연)

본 세션 = 본 버그 정정 + 진단 도구 (Track Dump 매트릭스) 보강.

---

## §1 본질 버그 정정 (서버 측 3 곳)

### 진단 짚음

자료구조 거짓말 — 세 자료 (`mid_map` / `mid_pool` / `SubscriberStreamIndex`) 갱신 흐름 비대칭:
- `evict` / `zombie reaper` / `handle_room_leave` 세 정리 흐름이 **mid_map + mid_pool 만 정리, SubscriberStreamIndex 정리 호출 누락**
- 결과: 재입장 시 같은 mid 재할당 시 `add_subscriber_stream` 의 idempotent 분기 (peer.rs:870) 가 옛 publisher_ref 잔재 SubscriberStream 그대로 반환

### 정정 3 곳

| # | 파일 | 호출 조건 | 정정 |
|---|---|---|---|
| 1차 | `helpers.rs:603` evict_user_from_room | Take-over (재접속 시 구 세션 강제 evict) | `remove_subscriber_streams_by_mids` 동시 호출 |
| 2차 | `tasks.rs:524` zombie reaper | 자연 퇴장 (LEAVE 부재 — 탭 닫기/새로고침/좀비 35초) | 동일 패턴 |
| 3차 | `room_ops.rs:437` handle_room_leave | 정상 LEAVE_ROOM op 수신 | 동일 패턴 |

세 흐름 모두 동일 패턴 — *공통 함수 부재* 가 본질 (3차 진실의 방 거리, 별 세션).

### 회귀

- `cargo build -p oxsfud` → OK
- `cargo test 전체` → **279 PASS / 0 fail**

---

## §2 클라 측 정정 (TRACKS_READY opcode)

### 진단

콘솔 에러 3번 출력 — `[ERR] 에러 3001: undefined` (sub 재협상 후마다).

`sdp-negotiator.js:370`:
```js
this.engine.sig.send(OP.TRACKS_ACK, { ... })  // ← OP.TRACKS_ACK = undefined
```

`constants.js:44`:
- `TRACKS_READY: 0x1102` (v2 TRACKS_ACK 개명)
- `TRACKS_ACK` 상수 폐기 → undefined op 송신 → 서버 `error 3001 invalid opcode` 응답

### 정정

`OP.TRACKS_ACK` → `OP.TRACKS_READY`. 1 줄.

---

## §3 어드민 매트릭스 보강 (8 정정)

본질 버그 정정 후 진단 도구 결함 다수 짚음 + 정정.

| # | 파일 | 정정 |
|---|---|---|
| 3.1 | `render-track-dump.js:137` | cli_pub 매칭 키 `track_id` → `ssrc` (publisher cli/srv 다른 ID 체계) |
| 3.2 | `render-track-dump.js:330, 353` | ssrc hex string 배열 표시 (`join(",")`) |
| 3.3 | `_computeVerdict` | `subscribe_state="created"` 통과 (서버 자료구조 거짓말 잔재) |
| 3.4 | `_computeVerdict` | `ssrc_mismatch` 검증 — cli 배열 ↔ srv 문자열 비교 정정 |
| 3.5 | `_buildRow:130` | `srv_sub null` row 박음 (옛: row 누락) + `srv_sub_missing` issue |
| 3.6 | `buildRows:72` | self-publish row 박음 (옛: src===dst 시 continue) + verdict `self_publish` 분기 |
| 3.7 | `render-track-dump.js:322` | self-publish row 의 `opacity-50` 클래스 (시각 구분) |
| 3.8 | `track-dump-collector.js` + `render-track-dump.js` | PTT 가상 pipe 수집 (`sdk.pttPipes`) + ViaSlot verdict 분기 (`ptt_idle` / `ptt_ready`) |

### 회귀

- sdp-builder 82 / datachannel 47 / scope 14 / track-dump-collector 33 = **176 PASS / 0 fail**

---

## §4 commit (push 는 부장님)

| 레포 | commit | 변경 |
|---|---|---|
| `oxlens-sfu-server` | `fe5bd04` | 11 files / +794 / -7 — 본질 정정 3 곳 + Track Dump 인프라 (Phase 109 자료 통합) |
| `oxlens-home` | `afb0ab5` | 10 files / +1328 / -4 — TRACKS_READY 정정 + Track Dump v2.2 + Pipe 진단 접근자 + 어드민 매트릭스 |

본 §3 추가 보강 자료 (3.5 ~ 3.8) 는 *commit 후* 정정 — 추가 commit 자리 보류 또는 부장님 결재.

---

## §5 본 세션 김대리 자기 점검

### 잘 박은 곳

- 본질 짚음 — `mid_map / mid_pool / SubscriberStreamIndex` 세 자료 비대칭 자료구조 거짓말 (직전 자정 짚음 좌표 정합)
- 세 흐름 (evict / zombie / LEAVE) 동일 결함 발견 — 한 흐름 정정 시 다른 흐름도 동일 결함 짚음
- 매트릭스 보강 — null 자리 진실 표시 (self-publish + srv_sub_missing + ViaSlot ptt_idle)

### 못 박은 곳

- 어휘 — *"자리"* 단어 다수 사용 (부장님 두 번 야단). 정정 진입했지만 잔재
- 본 정정 후 *2 차 검증* 자리에서 매트릭스 결함 (cli_pub null / row 누락 / ViaSlot broken) 짚음 — *부장님 확인* 으로 진입. 김대리 단독 짚음 부족
- *전체 흐름* 영향 면적 짚음 부족 — 본질 정정 1차 후 *효과 없음* 확인 자리에서 zombie reaper / handle_room_leave 추적 진입 (3 차)

### 누적 정정 흐름

```
직전 자정 부장님 짚음 (100% 재연 버그)
  → 김대리 단독 진입 (가설 양산 금지, 직감 좌표 따라감)
  → SubscriberStreamIndex 자료구조 짚음
  → 1차 정정 (helpers.rs evict) → 효과 없음 확인
  → 2차 정정 (tasks.rs zombie reaper) → 효과 없음 확인
  → 3차 정정 (room_ops.rs handle_room_leave) → 효과 확인 (자료 정합)
  → 클라 TRACKS_READY 정정 (콘솔 에러 3001)
  → 어드민 매트릭스 보강 8 건 (진단 도구 결함 정정)
  → commit
```

---

## §6 미해결 자리 (낼 진입 거리)

1. **시뮬캐스트 설정 결함** — 본 시나리오 (demo_conference) 의 `simulcast: false` 박힘. Conference 기본은 simulcast 여야 함 (부장님 짐작). `presets.js` 또는 데모 시나리오 설정 추적
2. **어드민 매트릭스 simulcast 자료 표시** — KIND / RID / SRV-PUB 어느 셀에도 *simulcast 여부* 표시 안 함
3. **3차 진실의 방 거리** — 본 세션 3 곳 (helpers / tasks / room_ops) 동일 패턴 *공통 함수 부재* — `Peer::release_subscribe_track(&self, tid)` 같은 공통 진입 함수
4. **클라 측 자료 거짓말 잔재** — `track.label` 옛 사용자 자료 잔재 (브라우저 MediaStreamTrack.label 불변). 진단 도구 가 *서버 발급 track_id* 우선 표시 정합 — 현재 정합
5. **별 토픽 백로그 유지** — TD-A (RTP 카운터) / TD-B (virtual_ssrc 자료구조) / TD-C (wire round-trip) / TD-D (admin token) / TD-F (NetEQ 자료)

---

## §7 어휘 메모리 강화 거리

`feedback_vocab_no_slang.md` 에 *"자리"* 단어 명시 + 정합 단어 (지점/곳/줄/단계/위치/대목/부분/측/구간/항목/면) 박음. 본 세션 부장님 두 번 야단 — 김대리 잔재 패턴.

---

*author: kodeholic (powered by Claude) — 2026-05-21 20:30, 김대리 단독 진행*
