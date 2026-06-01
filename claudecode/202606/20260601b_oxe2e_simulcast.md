# 작업 지침 — oxe2e simulcast publish 시나리오 추가

> 김대리(분석/설계) → 김과장(구현). 부장님 GO 후 진행.
> 토픽: oxe2e 회귀 시험에 simulcast publish 커버 추가. **봇(시뮬레이터) 송출만** 손댄다. 서버 0 변경.

---

## §0 의무 점검

1. **회귀시험 가이드 로드** — `context/guide/REGRESSION_GUIDE_FOR_AI.md`. oxe2e 자체가 본 작업 대상이므로 필수.
2. **config.rs 자기선언 철학 숙지** — 봇이 송신하는 PT/SSRC/extmap id 는 "봇이 PUBLISH_TRACKS 로 서버에 *선언*하는 값" (config.rs 상단 주석). 하드코딩 아니라 자기선언.
3. **baseline 확인** — 착수 전 `conf_basic` / `ptt_rapid` 현재 PASS 인지 1회 돌려 기준선 확보. 봇 공통 코드(media.rs/config.rs/mod.rs)를 건드리므로 회귀 필수.

---

## §1 컨텍스트

- oxe2e = 헤드리스 회귀 gate. 봇이 oxrtc(v3)로 서버에 붙어 Fake RTP 송수신 + **약속↔이행** 판정. 현재 conf_basic / ptt_rapid 커버.
- **목표** = simulcast publish 를 봇이 표준대로 송출 → 서버가 placeholder→promote→fan-out 하는지 검증. 이는 **catch 2 verify**(simulcast placeholder 등록 시점을 RTP-first→PUBLISH_TRACKS 로 옮긴 변경, 2026-05-29)의 회귀 닫기를 겸한다.
- **왜 지금** — catch 2 가 E2E verify 미완 상태. simulcast 가 현재 gate 미커버. 둘을 한 번에.

---

## §2 결정된 사항 (설계 확정 — 변경 금지)

### 2-1. 봇 송출 = 표준 rid-based simulcast. 서버 역산 금지

봇 송출 스펙의 근거는 **RFC 표준 + 봇 자기선언**이다. 서버 핸들러(`resolve_stream_kind` / `decide_rid_promotion` / `notify_new_stream`)를 참조해 봇을 맞추는 것은 **금지**(§7-1 사유). 봇은 실제 브라우저(Chrome rid-simulcast)가 하는 대로 표준 송출하고, 서버가 그걸 처리하는지가 시험 대상이다.

표준 근거:
- **RFC 8852** §3.1 — `urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id` (rid). RTP 헤더 확장으로 운반, ASCII 인코딩.
- **RFC 8285** — one-byte header ext (0xBEDE). 여러 element. 확장 세트는 32비트 경계 패딩.
- **RFC 8851 / 8853** — `a=rid:X send` + `a=simulcast:send` 로 송신측이 레이어 선언. **rid-based 는 SDP/시그널링에 SSRC 를 넣지 않는다** (rid 로만 구분, 서버가 RTP rid 로 동적 매핑).

### 2-2. 레이어 = 2개 (h / l)

- 레이어 개수는 표준상 **송신측이 선언**(서버가 안 줌). oxlens `ServerConfig`(signal_client.rs) 에도 레이어 필드 없음 — ICE/DTLS 좌표뿐. → 봇이 2개로 자기선언.
- rid 토큰 = `"h"`, `"l"` (한 글자. ASCII. 표준이 토큰값 강제 안 함 — 봇 선언).

### 2-3. 검증 = 기존 judge `evaluate` 무변경

- simulcast video 는 promote 후 **h 레이어만** `TRACKS_UPDATE(add)` 통지되고, 약속 ssrc = **virtual ssrc**(`ensure_virtual_ssrc`). 서버 fan-out 이 SimulcastRewriter 로 실 h ssrc → virtual ssrc 로 rewrite 하므로 **봇 수신 ssrc = 약속 ssrc**. 기존 `evaluate`(약속↔이행 ssrc 단순 비교)가 그대로 성립.
- **virtual ssrc 도착 자체가 promote 성공의 증거** → catch 2 verify 닫힘. judge 코드 손대지 않는다.

### 2-4. 범위 제외 (이번 작업 아님)

- **SUBSCRIBE_LAYER 레이어 전환(h↔l) 검증 제외** (부장님 결정). judge 레이어 판정 신설 안 함. 봇 SUBSCRIBE_LAYER 발신 안 함.
- RTX(rrid) 송출 제외 — 봇이 RTX 안 보냄. `repaired-rtp-stream-id` ext 미삽입.
- 서버 코드 0 변경.

### 2-5. 운영 — run_secs 마진

- simulcast 약속은 RTP·promote 후 도착 + `notify_new_stream` 의 `gate.pause(5000)` → 봇 TRACKS_READY → resume → 다음 keyframe 부터 fan-out. 봇 keyframe 주기 2초(`KEYFRAME_INTERVAL_FRAMES=60`).
- → simulcast 시나리오 `run_secs` 는 **8~10초**로 잡는다 (conf_basic 6초보다 길게).

---

## §3 결정 추천 (★ 정지점 1개)

위험도 낮음(봇만, 서버 0 변경)이라 정지점 최소.

- **★ 정지점 1 — simulcast 시나리오 PASS**
  봇 2레이어 송출 + 서버 promote + h fan-out → `evaluate` PASS. **여기서 commit 보류 + 보고 + GO 대기.**
  사유: "봇이 표준대로 쐈는데 서버가 promote 하나"가 본 작업의 유일한 실질 리스크. 여기 서면 끝.
- conf_basic / ptt_rapid 회귀 PASS 는 정지점 아님 — 통합 보고에 포함.

---

## §4 단계별 작업

### Phase A — config.rs: rid 상수

- `RID_EXTMAP_ID: u8` 신설 (MID_EXTMAP_ID=1 과 다른 값, 예 `4`). 봇 자기선언값.
- `RID_HIGH: &str = "h"` / `RID_LOW: &str = "l"`.
- (repair_rid 는 §2-4 RTX 제외라 상수 불요.)

### Phase B — media.rs: RtpSender rid 삽입

- `RtpSender` 에 `rid: Option<&'static str>` 필드 추가. `audio()` / 기존 `video()` 는 `None`(현행 유지). simulcast 레이어용 생성자(예 `video_sim(ssrc, rid)`) 추가 — `rid: Some(...)`.
- `next_packet()` 의 ext 블록: `rid` 가 `Some` 이면 MID element 옆에 RID element 추가.
  - 현행: `[0xBE,0xDE,0x00,0x01]` (1 word) + MID(2B: `(MID_ID<<4)|0`, mid 첫글자) + 패딩 2B.
  - rid 1글자면: MID(2B) + RID(2B: `(RID_ID<<4)|0`, rid 첫글자) = **정확히 4B = 1 word**. `ext_len_words=1` 유지, 패딩 0.
  - `None` 이면 현행 그대로(MID만 + 패딩).
- VP8 keyframe 판정은 현행 더미(`0x10` descriptor + frame_byte bit0=0)가 서버 `is_vp8_keyframe` 통과 확인됨 — 페이로드 변경 불요.

### Phase C — mod.rs build_tracks: simulcast 2-SSRC 분기

- video 트랙이고 `track.simulcast == true` 이면:
  - SSRC 2개 생성 (h/l). `ssrc_for` 충돌 회피 — layer 를 salt 에 섞는다 (예 `ssrc_for(VIDEO_SSRC_BASE, &format!("{id}-{rid}"))`). 같은 id 로 2 SSRC 가 같은 값 나오는 것 방지.
  - `RtpSender::video_sim(ssrc_h, "h")`, `video_sim(ssrc_l, "l")` 둘 다 senders 에 push.
  - **PUBLISH_TRACKS video entry 는 1개** — rid-based 라 SSRC 미선언(또는 의미 없음). `simulcast=true`. (서버가 sentinel placeholder 등록.)
- non-sim video(현행)는 1 SSRC + `RtpSender::video`(rid None) 유지.
- PUBLISH_TRACKS body 에 **`rid_extmap_id: config::RID_EXTMAP_ID`** 추가 (mid_extmap_id 옆). 봇 자기선언.

### Phase D — scenario: simulcast 시나리오 TOML

- `scenarios/simulcast_basic.toml`(이름 자유) 신설. 참여자 2~3명, 각 `[[participants.tracks]]` 에 video `simulcast = true` (audio full 동반).
- `run_secs` 8~10 (§2-5). meta.name/desc 기입. 타임라인 전환 없음(레이어 전환 제외).

### Phase E — 검증

- `oxe2e scenario scenarios/simulcast_basic.toml` → `evaluate` PASS 확인 (★정지점 1).
- 회귀: `conf_basic` / `ptt_rapid` 재실행 PASS (봇 공통 코드 회귀 무손상 확인).
- 서버 로그에서 `[STREAM] NEW video rid=h ... tt=FullSim` + `[STREAM:PROMOTE]` 관측되면 promote 정상.

---

## §5 변경 영향 범위

- `crates/oxe2e/src/config.rs` — 상수 3개 추가.
- `crates/oxe2e/src/bot/media.rs` — RtpSender rid 필드/생성자 + next_packet ext.
- `crates/oxe2e/src/bot/mod.rs` — build_tracks simulcast 분기 + PUBLISH_TRACKS body rid_extmap_id.
- `crates/oxe2e/src/scenario/` 하위 — simulcast TOML 신규.
- **서버(oxsfud/oxhubd/oxrtc/oxsig) 0 변경. judge/mod.rs 0 변경.** 이 범위 밖 파일 손대지 말 것 (별 발견 시 *발견_사항* 보고만).

---

## §6 운영 룰

1. **정지점 1개** (§3). 통합 진행 후 정지점에서 commit 보류 + 보고 + GO.
2. **시그너처 선조치 후 보고** — RtpSender 생성자/필드 시그너처는 김과장이 호출처 보고 박은 뒤 사후 보고.
3. **추가 변경 금지** — §5 범위 외 금지.
4. **2회 실패 시 중단** — 같은 컴파일 에러/테스트 실패 2회 후 미해결 → 중단 + 보고.

---

## §7 기각 접근법 (이번 세션 부장님 정정 — 반드시 준수)

1. **서버 코드 역산해서 봇 맞추기 = 거울/동어반복 (금지)** — 회귀 시험은 서버 검증인데 시뮬레이터를 서버 구현(`resolve_stream_kind`/`decide_rid_promotion`/sentinel/gate 타이밍)에 맞추면 서버 버그도 같이 따라가 PASS 가 난다. 봇은 **표준대로** 송출, 서버는 검증 대상.
2. **home(JS) 봐서 wire 알아내기 (헛수고)** — JS 는 `addTransceiver`/`setParameters` 고수준 API 만. rid extmap id/SSRC 배치/ext 포맷은 libwebrtc 가 만듦. 코드에 wire 없음. 표준(RFC)이 출처.
3. **실측 캡처부터 뜨기 (보조로만)** — 표준이 정하는 부분(rid wire 포맷)은 RFC 우선. 실측은 표준이 자유 주는 부분(레이어 수/토큰) 확인용 보조 — 이번엔 봇 자기선언이라 불요.
4. **ssrc-group(SIM) 방식 (레거시)** — Chrome 구방식, 비표준. rid-based(RFC 8853)가 표준. SDP 에 SSRC 안 넣는 게 정석.
5. **서버 기본값에 기대 봇 동작 생략** — 예 "fwd.current=High 기본이니 SUBSCRIBE_LAYER 생략". 서버 내부값 의존 = §7-1 변종. (이번엔 레이어 전환 자체 제외라 무관하나 원칙 기록.)

---

## §8 산출물

- 코드 4곳(§5) + simulcast TOML.
- 완료 보고: `context/202606/20260601b_oxe2e_simulcast_done.md` (변경 파일 + simulcast PASS + 회귀 결과).
- SESSION_INDEX.md 한 줄 추가.

---

## §9 시작 전 확인

- conf_basic / ptt_rapid baseline PASS (§0-3).
- 서버 기동 상태 + auth 토큰 발급 경로(`127.0.0.1:1974`) 정상.

---

## §10 직전 작업 처리

- 신규 작업. 직전 의존 없음.
- 단 같은 6/1 `20260601_slot_subscribers.md`(broadcast 방향 역전, fan-out Phase C)가 서버 fan-out 을 건드렸으니, simulcast fan-out(broadcast 본문 FullSim arm)이 그 변경 위에서 정상인지 §4-E 서버 로그로 확인.

---

*author: kodeholic (powered by Claude)*
