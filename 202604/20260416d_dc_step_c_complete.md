# 2026-04-16d — DC Phase 1 Step C 완료 (DcMetrics 19 + AssociationLost break + admin 가시화)

**영역**: 서버 + 홈 (Rust 4파일 + JS 2파일)
**전 세션**: `20260416c_dc_channel_step_b_complete`

---

## 요약

DC 메트릭 19개 신설, admin 스냅샷 가시화, 서버 SCTP `AssociationLost` 시 silent fail → 명시 break 전환, 클라 `_setupDataChannel`을 LiveKit RTCEngine 패턴으로 프로화.

무전/컨퍼런스 회귀 통과. 간접 증거(`pli_server_FLOOR:DC` agg-log)로 DC 경로 정상 동작 확인. 실측 카운터 수치는 admin 렌더러 패치 후 다음 스냅샷에서 확정.

---

## 완료 파일 (6)

### 서버 (4)

**1. `crates/oxsfud/src/metrics/sfu_metrics.rs`** — `DcMetrics` 19 카운터
- send 4 (mbcp/speakers/app/unknown) + recv 4 + fail 3 (mbcp/speakers/app) + lifecycle 3 (open/close/association_lost) + pending 2 (buffered_on_join/buffer_overflow) + 검증 3 (invalid_frame/unknown_label/dc_error)
- `SfuMetrics.dc` + `new()` / `flush()` JSON 통합

**2. `crates/oxsfud/src/datachannel/mod.rs`**
- `process_association_events() -> bool` (AssociationLost 시 true)
- `association_lost` flag → drain 완료 후 loop break
- 카운터 주입 7지점 (dc_open/dc_close/unknown_label/invalid_frame/unreliable_recv_*/dc_association_lost)

**3. `crates/oxsfud/src/room/floor_broadcast.rs`**
- `dc_send_inc(svc)` / `dc_send_failed_inc(svc)` 헬퍼
- `send_dc_wrapped(p, wrapped, svc)` svc 파라미터 추가 (Step D 대비)
- try_send Ok/Err match → 성공/실패 분기, pending 적재/overflow 카운트

**4. `crates/oxsfud/src/signaling/handler/admin.rs`**
- participant JSON에 `"dc": { unreliable_ready, pending_buf_len }`

### 클라 (2)

**5. `core/sdp-negotiator.js` `_setupDataChannel`** — LiveKit 패턴
- recreate 시 이전 callback null
- `bufferedAmountLowThreshold = 65535` (기본 0 버그 해소)
- `onbufferedamountlow` 핸들러
- `onerror` ErrorEvent 분해 + `tel.pushCritical("dc_error", ...)` 승격
- `logCtx` (user/room) 구조화

**6. `demo/admin/snapshot.js`** — 렌더러 2곳
- 새 섹션 `--- DC ---`: `[DC:{uid}] ready=X buf=Y`
- SFU SERVER 섹션에 `[server:dc] send=[...] recv=[...] fail=[...] open=N close=N assoc_lost=N pending=[...] errs=[...]`

---

## 설계 판단

- **`send_failed`는 3종 (app 포함)** — 설계서 초안 2종에서 확장. app/unknown 통합 버킷.
- **AssociationLost 즉시 break가 아닌 flag** — `tokio::select!` arm 내부 break 불가. drain 플러시 후 loop 상단 체크.
- **admin 렌더러 추가는 범위 확장 감수** — 서버가 JSON 내려도 렌더러가 안 그리면 검증 자체 불가. 최소 한 줄만.
- **클라 bufferedAmount 샘플링은 범위 밖** — onbufferedamountlow 이벤트 점화까지만, 주기 샘플링은 실측 후 결정.

---

## 간접 증거 (2026-04-16 21:23 스냅샷)

- `pli_server_FLOOR:DC pub=U575` agg-log → `apply_floor_actions` 실행 확인
- PTT 라이프사이클 정상 (granted ×3, released ×2, revoked ×1)
- PIPELINE STATS `rewritten` 증가 → DC Granted 수신 후 rewriter switch 정상
- SDP `mid=2 application` 전 참가자 존재

---

## 오늘의 지침 후보

1. **렌더러 없는 카운터는 "없는 것"** — 서버 JSON 내려도 admin 렌더링 안 되면 검증 불가. 관측 인프라는 서버+렌더러 동시에 "완료".
2. **`tokio::select!` arm에서 loop break 불가** — flag 패턴으로 drain 보장 후 상단 break. 중간 break는 미처리 이벤트 유실.
3. **`bufferedAmountLowThreshold`는 0 기본이 함정** — 설정 안 하면 `onbufferedamountlow` 영영 미발동. 안전한 기본처럼 보이지만 "백프레셔 감지 꺼짐". 64KB가 실질 표준.
4. **svc 파라미터는 호출자가 명시** — bytes 첫 byte에서 추출 가능해도 규약 의존. Step D에서 svc 늘어날 때 시그니처 명시가 안전.
5. **말을 줄여라** — 옵션 나열/비교표 남발/과잉 확인 금지. 코딩 전 확인은 1회, 보고는 변경 파일 + 한 줄 요약 + 다음 액션만.

## 오늘의 기각 후보

1. **bufferedAmount 주기 샘플링 Step C에 포함** — 이벤트 관측부터. 주기 샘플링은 실측 후.
2. **클라 `ensurePublisherConnected` 즉시 도입** — PC state vs DC state 관계 설계 선행 필요. 단독 도입 시 `_dcUnreliableReady`와 의미 중복.
3. **admin JS 정식 DC 대시보드 섹션** — 차트/레이아웃 판단 필요. Step C는 텍스트 스냅샷 한 줄까지만.
4. **서버 DC 단독 재생성** — LiveKit/mediasoup 공통 기각. PC 재연결 경로 경유.

---

## PENDING

- [ ] Step C 검증 스냅샷 (admin 렌더러 패치 후 첫 스냅샷)
- [ ] Step D: Active Speakers DC 전환 (svc=0x02, WS 병행)
- [ ] 클라 bufferedAmount 주기 샘플링 (실측 후)
- [ ] 클라 `ensurePublisherConnected` 패턴
- [ ] admin JS 정식 DC 대시보드
- [ ] DC Phase 2: reliable 채널
- [ ] DC Phase 3: WS binary fallback + gRPC oneof
- [ ] `IDENTIFY` token validation
- [ ] NetEQ collapse fix

---

## 다음 세션 진입 지점

**Step C 검증** (5분): Cmd+Shift+R → 스냅샷 → `[server:dc]`/`[DC:{uid}]` 실측. PASS 시 **Step D 진입**.

Step D 작업:
1. `tasks.rs` active_speaker_task → WS(op=144) 병행 DC `broadcast_dc(svc=0x02)` 추가
2. payload: `count(1B) + [uid_len(1) + uid + level(1)] × N`
3. `send_dc_wrapped`가 svc 받음 → `dc_send_inc(0x02)` 자연 집계
4. 클라 `_handleDcMessage` SVC.SPEAKERS 분기 → Room emit
5. 앱 DC 우선, WS fallback 유지

---

*author: kodeholic (powered by Claude)*