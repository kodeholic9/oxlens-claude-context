# 20260709b — 런타임 h→l 레이어 전환 미완결 GAP 분석 지침 (신규 세션용)

> author: kodeholic (powered by Claude)
> 작성: 김대리. 집행: 김과장 **신규 세션** (본 건 사전 컨텍스트 없음 전제 — §C 읽기부터).
> 성격: **분석 세션** — 처방 구현이 아니라 원인 좌표 확정이 산출물. 처방은 결재 후 별도.

---

## §0 세션 수칙 (신규 세션 필수)

1. 시킨 것만 한다 — 본 지침 범위 밖 수정 금지. 발견은 *발견_사항* 보고만.
2. 사실과 추측을 문장 단위로 구분한다. 관측 없는 단정 금지.
3. **§D(봉인 부록)는 §B 관측으로 절단 좌표가 확정되기 전에 열지 않는다** — 선입견 방지가
   본 지침의 설계 의도다. 자기 가설을 먼저 세우고, 좌표 확정 후 부록과 대조하라.
4. 코드 수정은 계측(로그/trace/카운터) 목적에 한정 — 동작 변경 금지. 계측 커밋은 별도 분리.
5. 2회 막히면 중단·보고.

## §A 증상 (사실만 — 2026-07-09 확정)

- **GAP**: simulcast 구독이 h를 릴레이하던 중 `Forwarder.target=Low` 를 걸고 target-rid(l)
  실 ssrc 로 PLI 를 반복 전송해도, **l 로의 SWITCH([SIM:SWITCH] 로그/화질 변화)가 발생하지
  않는다**. 20s 폴링 무재개, 2회 재현 (SIM-AUTO-01 step③, 20260709 라이브).
- **대조군(중요)**: "처음부터 l"(current=Low 로 시작하는 구독 — F4 demote 후 신규 구독 등)
  경로는 **정상** — l 미디어 수신·framesDecoded 증가 실증. 즉 l 미디어 파이프 자체는 살아있고,
  **런타임 전환 경로만** 죽어 있다.
- 이력: 기존 `GAP-simulcast-layerswitch`("클라 setQuality('l') 후 frameWidth 640 유지")의
  실체가 이것으로 확정 — 즉 **오늘(0709) auto-layer 이전부터 존재하던 결함일 가능성이 높으나,
  오늘 변경(F4 PLI 동반·tick target 설정·target-rid PLI)이 원인/기여/은폐 중 무엇인지는
  미판정** — §B-0 에서 최우선 판정한다.
- 재현 수단: `ADMIN_DOWNLINK_INJECT`(hub REST `POST /media/admin/rooms/{r}/downlink-inject/{u}`,
  body `{remb_bps, repeat}`) 로 demote 유발 — 확정적 재현. qa `SIM-AUTO-01` step③ 이 그 자리
  (현재 known-gap soft 기록).

## §B 관측 계획 — 결론 전에 좌표부터

전환의 성립 사슬은 5마디다. **어느 마디에서 끊기는지**를 이분 관측으로 확정하는 것이 1차 산출물.

```
[1] publisher 가 l RTP 를 서버에 보내고 있는가 (l track last_rtp/수신 카운터)
[2] l 패킷이 "해당 구독자의 SubscriberStream.forward" 에 도달하는가
    (fanout 이 l 패킷을 이 stream 에 넘기는가 — 도달 자체의 관측)
[3] 도달 시 분기 판정: sender_layer 값 / fwd.target 값 / is_target_layer 성립 여부
[4] is_keyframe 이 l 패킷에서 참이 되는 순간이 오는가 (PLI → 실제 l 키프레임 응답)
[5] 성립 시 [SIM:SWITCH] 실행·rewrite ok
```

- **§B-0 (최우선, 반나절 컷)**: 오늘 변경 연루 판정 — `SIMULCAST_AUTO_LAYER=false` OFF 빌드에서
  **SUBSCRIBE_LAYER(사용자 수동 h→l)** 로 같은 GAP 이 재현되는가. 재현되면 "기존 결함, 오늘
  변경 무관" 확정(기존 GAP 이력과 정합). 미재현이면 오늘 변경 연루 — 수사 방향 전환.
- 계측: 위 [1]~[5] 각 마디에 rate-limited 로그 또는 `--features trace` 활용(runbook §4-D,
  IDR/PLI 타임라인). 기존 METRICS(`forward_drop_layer/forward_drop_rewrite/layer_switched`)
  스냅샷 대조 — 특히 pending 중 `forward_drop_layer` 가 **뛰는지 안 뛰는지**가 [2] 판정
  지표다(뛴다=도달하나 분기서 drop / 안 뛴다=도달 자체가 없음).
- 판정 기준: 각 마디 pass/fail 을 로그 원문과 함께 표로. **fail 첫 마디 = 원인 좌표**.

## §C 읽기 자료 (순서대로)

1. `context/PROJECT_MASTER.md` + `context/PROJECT_SERVER.md` 미디어 아키텍처 절 (전체 지형).
2. `context/202607/20260709_simulcast_auto_layer_design.md` §2(실측 현황) + `_done.md` 전문 —
   오늘 변경의 전모, GAP 확정 기록, 검수 "관찰 2"(stale pending).
3. 소스 (전문 정독):
   - `crates/oxsfud/src/domain/subscriber_stream.rs` — forward 분기(FullSim), Forwarder.
   - `crates/oxsfud/src/domain/publisher_track.rs` + `publisher_stream.rs` — **fanout 이
     어느 track 의 어떤 구독자 목록을 도는지, sim 에서 h/l 트랙별 subscribers 등록 구조**.
   - `crates/oxsfud/src/domain/rtp_rewriter.rs` — prepare_source_switch/키프레임 시맨틱.
   - `crates/oxsfud/src/transport/udp/auto_layer.rs` + `pli.rs` — target 설정·PLI 경로.
   - keyframe 판정 함수(is_keyframe 산출처 — ingress_publish.rs 추정, 실측).
4. qa: `SIM-AUTO-01` spec(step③ known-gap 자리) + runbook §4-D(kf/IDR trace 절차).
5. 대조 정전(좌표 확정 후): `reference/livekit` Forwarder 레이어 전환부 /
   `reference/mediasoup` `SimulcastConsumer.cpp` 전환·키프레임 대기 로직.

## §D 봉인 부록 — 가설 후보 (★§B 좌표 확정 전 열람 금지)

작성자(김대리)의 후보 3 + 검수 관찰 1. **정답 아님 — 대조용.**

<details>
- 후보 H1 [마디 2]: fanout 구독자 등록이 track 단위라면, 구독 등록 시점의 current 레이어
  track(h) 목록에만 이 stream 이 있고 l track 목록엔 없어서 l 패킷이 forward 에 아예 도달하지
  않는 구조 가능성 ("attach 소급" — 대조군 "처음부터 l 은 정상"과 정합: 그땐 l 에 등록됐으니까).
- 후보 H2 [마디 4]: is_keyframe 판정이 l 스트림 페이로드에서 거짓 — 코덱/레이어별 키프레임
  검출 결함, 또는 Chrome 이 per-ssrc PLI 에 l 인코더 IDR 로 실응답하지 않음(응답은 h 로만).
- 후보 H3 [마디 3]: sender_layer 산출이 `ctx.publisher.rid_load()` — l 패킷 인입 시 이 값이
  실제 "l" 인지 (publisher 단위 rid 가 패킷 단위 rid 를 대변하는가, N:1 오염 여부).
- 관찰(검수): target=Low pending 인데 l 트랙 부재 시 영구 pending — 본 GAP 과 별개 현상이나
  같은 조사에서 pending 나이 상한 필요성 판정.
</details>

## §E 산출물·정지점

1. §B-0 판정(오늘 변경 연루 여부) — **즉시 중간 보고**.
2. 마디별 pass/fail 표 + fail 좌표 + 근거 로그 원문 — `20260709b_..._done.md`.
3. §D 대조 결과(적중/기각/신규) + **처방 후보 2안 이상**(각 trade-off) — 구현은 결재 후.
4. 계측 코드는 별도 커밋(동작 변경 0 증빙: cargo 기준선 동수). push 는 결재.
