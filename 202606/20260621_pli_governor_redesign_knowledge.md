# 20260621 — PLI Governor 재설계(오탐 박멸) + knowledge 디렉토리 신설 + PTT republish freeze 조사

> author: kodeholic (powered by Claude)
> 서버 커밋: `cbe8b55` (oxlens-sfu-server, main). context/* 는 미커밋(부장님 검토).

---

## 0. 세션 개요 (주제 흐름)

1. **webrtc-src 로컬 clone** — 디버깅 시 환각 대신 근거 확인용. `~/repository/webrtc-src`(순수 소스, 빌드 의존성 없음, ~596M).
2. **knowledge 디렉토리 신설** — `~/repository/context/knowledge/`. 정적 진실 캐시(추정·휘발성 금지, 캐시 미스 시 webrtc-src grep). `KNOWLEDGE_INDEX.md` 테이블 진입점.
3. **webrtc-internals stats 지식화** — getStats RTCStats 전 객체 의미·진단·중요도 + UI·임계값·파생공식.
4. **PTT republish 영상 4~5분 멈춤 조사** — 원인 후보 12개 + webrtc-src 검증(가설/반증 분리, 단정 회피).
5. **ts_jump_fix 설계 검토** — 부장님 설계(ssrc 변화 감지) 타당성 검토.
6. **SFU 3인방 PLI 전략 심층 비교** — mediasoup/janus/livekit 전체 경로 + 차용 권고.
7. **★ PLI Governor 재설계(코드)** — 오탐 박멸. 커밋 `cbe8b55`.

---

## 1. ★ PLI Governor 재설계 (커밋 cbe8b55)

### 문제 (부장님 지적: "자꾸 오판해서 drop")
구 `judge_subscriber_pli`/`judge_server_pli`는 5개 drop 사유 중 3개가 **추정**:
- `keyframe_recent` — "최근 이 subscriber에 키프레임 relay됨" → republish/화자전환 시 옛 스트림 키프레임을 새 스트림에 적용해 **새 PLI 차단 → freeze**.
- `pli_pending_wait` / `already_pending` — 상태 해제가 키프레임 수신 이벤트 의존 → 이벤트 누락 시 **자기강화 freeze**.
- `judge_server_pli`의 `keyframe_already_arrived` — 과거 봇 GOP 차단 전력(helpers.rs:406 증언, RECON-2 0613f).

### 재설계 원칙 (부장님: "더 추가 말고 덜어내라")
- **drop 사유 = 시간 하나(min_interval).** 추정 전부 제거 → 오판할 대상 없음.
- **drop은 진짜 손실 아님** — 재시도 동력이 외부에 이미 있음(수신측 Chrome의 200ms~3s 주기 PLI 재전송 + 서버 burst 다발). → deferred/sweep 안전망 불요(덜어냄).
- 키프레임 수신은 관측 시각만 기록(판단 미사용).
- 자동 다운/업그레이드 **완전 제거**(부장님 결정 1) — 레이어는 수동 SUBSCRIBE_LAYER(forwarder.current)만.

### 새 거번너 (요지)
```
judge_pli(layer): 마지막 발사 후 min_interval 안 지났으면 Drop("throttled"), 지났으면 Forward.
on_keyframe_received(layer): 진단 시각만 기록.   ← 그게 전부 (~210줄)
```
min_interval: H=300ms / L=100ms(레이어 비용 차등, livekit식).

### 변경 파일 (9, +115 −789)
| 파일 | 변경 |
|---|---|
| `domain/pli_governor.rs` | 전면 재작성 680→~210줄. judge_pli 단일 + on_keyframe_received. 추정 drop·다운/업그레이드·deferred·PliSubscriberState 제거 |
| `transport/udp/ingress_subscribe.rs` | 다운그레이드 블록 ~80줄 → judge_pli 단순 호출 |
| `transport/udp/pli.rs` | burst judge_server_pli→judge_pli, break→continue, bypass에서 GOV:DG/UG 삭제 |
| `transport/udp/egress.rs` | judge_server_pli→judge_pli |
| `domain/subscriber_stream.rs` | pli_state 필드·초기화·on_keyframe_relayed 제거 |
| `signaling/handler/track_ops.rs` | gate resume 시 subscriber pli reset 제거(publisher reset 유지) |
| `tasks.rs` | run_pli_governor_sweep + import 제거 |
| `lib.rs` | sweep spawn 제거 |
| `config.rs` | PLI_RETRY_TIMEOUT/STALE/DOWNGRADE/UPGRADE/SWEEP 삭제, MIN_INTERVAL만 유지 |

### 화자전환/레이어전환 영향 (부장님 질문)
`FLOOR:BRG`(화자전환)·`SIM:PLI`(레이어전환) 둘 다 non-bypass → 거번너 경유. **첫 발은 기존과 동일 발사**. 차이: ①keyframe_already_arrived 취소 제거 ②break→continue. 순효과 = 덜 막고 더 보냄(freeze↓, 후속 발 약간 중복). 부장님 결정: 취소 되살리기(복잡)는 **안 함** — 현재 유지.

### 검증
- cargo test -p oxsfud: **206 PASS**.
- oxe2e: conf_basic / simulcast_basic / duplex_cache / telemetry_collect **PASS**, ptt_rapid는 1회 flaky FAIL(audio fan-out, video PLI 무관) → 재실행 **PASS**.
- **경계(정직)**: oxe2e는 Fake RTP라 라우팅만 검증 — 오탐 제거로 republish freeze가 실제 사라졌는지는 **브라우저 라이브(PTT publish→발화→republish)** 로만 확인 가능. 회귀 PASS ≠ freeze 해소 증명.

---

## 2. knowledge 디렉토리 (context/knowledge/, 미커밋)

| 파일 | 내용 |
|---|---|
| `KNOWLEDGE_INDEX.md` | 테이블 진입점. 원칙(정적 진실만/휴발성 금지/추정 금지) + 라우팅(미스 시 webrtc-src grep) |
| `2026-06-21-webrtc-internals-stats.md` | getStats RTCStats 전 객체 의미·진단·중요도 + UI·품질 임계값·파생 공식 |
| `2026-06-21-webrtc-receiver-timestamp-render.md` | RTP ts→렌더(TimestampExtrapolator), 큰 점프/공백 hard reset 10초, playout cap 10초 |
| `2026-06-21-webrtc-receiver-keyframe-recovery.md` | 수신측 키프레임 자가복구 한계(200ms/3s, 5초 비활성 규칙) |
| `2026-06-21-ptt-republish-freeze-candidates.md` | freeze 원인 후보 12개 + webrtc-src 검증(가설/반증 분리) |
| `2026-06-21-sfu-pli-keyframe-throttle.md` | 3인방 PLI 전략 심층 비교 + 차용 권고 |

> 출처 앵커 원칙: 필드명·상수는 webrtc-src/reference 소스 확인분, 의미·진단은 분석. 라인번호는 휘발성이라 제외.

---

## 3. PTT republish freeze 조사 (미해결, 별도 진행 중)

- 증상: PTT publish→발화→republish 후 수신 영상 4~5분 멈춤(localhost+Chrome).
- SFU 소스 확인: rewriter는 RTP 헤더(seq/ts/ssrc)만 고침, **VP8 pictureId/tl0PicIdx는 안 건드림**. SSRC는 고정 virtual_ssrc.
- 살아남은 가설: VP8면 pictureId 불연속(ref finder stash) — H264면 seq 연속화로 무관. 코덱 확정 필요.
- `ts_jump_fix`(부장님 설계, oxlens-sfu-server/context/design/20260621_*) 검토: 진단(캠 republish가 switch_speaker 미경유 → ts_offset 재계산 누락 → ts 점프 실측 49M ticks) 타당. 머지 전 확인점: RTX 입력단 ssrc 오탐 / "rate 2배"는 일회성 level 점프 표현 / 4~5분 정량 연결.
- **이 freeze 수정은 다른 세션에서 진행 중**(부장님).

---

## 4. 이월 / 다음

- PLI 재설계 라이브 검증(브라우저 PTT republish) — freeze 해소 확인 = 부장님 몫.
- `helpers.rs:406` 옛 동작 언급 주석 잔존(무해, 코드 아님).
- republish freeze 본수정(ts_jump_fix 등) 별 세션.
- knowledge/ 디렉토리 커밋 = 부장님.
