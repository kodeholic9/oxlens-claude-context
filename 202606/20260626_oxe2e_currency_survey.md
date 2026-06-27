// author: kodeholic (powered by Claude)

# 작업지침 — oxe2e 회귀 강화: 현행 소스 실측 (조사 전용)

> **작성**: 김대리 (claude.ai) / **수행**: 김과장 (Claude Code) / **결정**: 부장님 (kodeholic)
> **성격**: ★조사 전용 — 코드 한 줄도 바꾸지 않는다.★ 산출물 = 사실 보고서 1개.
> **배경 문서**: `context/202606/20260626_oxe2e_regression_requirements.md` (요구사항 — 참조 배경, 이 지침이 그 §G-1 을 수행).
> **자리 메모**: 작업지침은 `context/YYYYMM/` 로 통합됨(구 `claudecode/` 폐기). PROJECT_MASTER 현행화 미반영 — 별 토픽.

---

## §0 의무 점검 (시작 전 반드시)

1. **이 작업은 조사다. 수정/리팩터/테스트 추가 일절 금지.** 발견은 보고만, 손대지 않는다.
2. 배경 요구문서(`20260626_oxe2e_regression_requirements.md`) §F(현행 실측)·§G-1 을 먼저 읽는다. 본 지침은 그 §G-1 의 미해소분을 채우는 것.
3. **판단하지 않는다.** "이게 좋다/나쁘다/이렇게 고쳐야" 금지. **있는 그대로의 사실만** 수집. 해석은 김대리/부장님 몫.
4. 2회 같은 막힘(파일 못 찾음/grep 0건 반복) → 즉시 중단 + 보고.

---

## §1 컨텍스트 (왜 이 조사가 필요한가 — 1문단)

oxe2e 회귀 게이트가 "너무 잘 뚫린다". 두 세션 설계 논의로 방향(3층 피라미드 + 무게중심 하향 + 갈래 B 등식)은 섰으나, **그 설계가 기댄 전제 일부가 현행 코드에서 미확인.** 설계를 굳히기 전에 "지금 코드가 실제로 어떻게 돼 있나"를 사실로 확정해야 한다(부장님 원칙: 측정 → 설계). 본 조사가 그 측정.

---

## §2 결정된 사항 (이미 김대리가 실측 — 김과장은 재확인 불요, 전제로 깔 것)

> 아래는 김대리가 2026-06-26 직접 read 로 확인한 사실. 김과장은 이걸 **출발 전제**로 쓰되, 조사 항목과 겹치면 교차 확인만.

- oxe2e 봇 = Rust(oxrtc v3), 단일 프로세스 N-peer(barrier 동기화). 위치 `crates/oxe2e/src/bot/{mod,media}.rs`.
- **봇 수신 기록 = `BotResult.received: HashMap<u32,u64>` (ssrc별 누적 카운트만). seq/ts 버림.** (`media.rs::spawn_subscriber` 가 `parse_rtp_mini` 로 까서 `rtp.ssrc` 만 사용.)
- **봇 송신 = canned** (`RtpSender::next_packet` 고정 ts_inc·seq 단조·고정 페이로드 — live encode 아님).
- judge 판정 최소 단위 = **`count == 0`** (`judge::evaluate` 이행 = 1패킷이라도 오면 PASS). seq 연속성·개수 등식·ts 단조 안 봄.
- oxe2e 내 `#[cfg(test)]` = `judge/mod.rs` 의 caching 검증 2개뿐(김대리 확인).
- 도메인 소스 = `crates/oxsfud/src/domain/` (21파일). 핸들러 = `crates/oxsfud/src/signaling/handler/` (8파일).

---

## §3 조사 항목 (★본체 — 각 항목 = 질문 + 어디를 볼지 + 보고 형식★)

> 각 항목은 **"질문 → 조사 지점(김대리가 미리 박음) → 보고 형식"** 3단. 김과장은 조사 지점에서 시작해
> 사실을 수집하고 정해진 형식으로 보고. **추론·제안 금지, 사실만.**

### 조사 1 — 현행 테스트 전수 지도 (1층 빈칸 확정)

- **질문**: 현재 `#[cfg(test)]` 가 어느 파일에 몇 개, 무엇을 검증하나?
- **조사 지점**:
  ```
  grep -rn "#\[cfg(test)\]" crates/oxsfud/src crates/oxe2e/src crates/oxsig/src crates/oxrtc/src crates/common/src
  ```
  추가로 `tests/` 디렉토리(통합 테스트) 존재 여부: `find crates -type d -name tests`
- **보고 형식** (표):
  | crate | 파일 | 테스트 함수명 | 한 줄 요약(무엇을 검증) | §23 영역 매핑 |
  |---|---|---|---|---|
  - §23 영역 = ①식별/통지 ②상태전이 ③자료구조정합 ④scope/라우팅 ⑤rewrite / **해당 없으면 "기타"** 로 표기.
  - 매핑이 애매하면 "애매: 사유" 로 적고 **임의 분류 금지**(판단은 김대리).

### 조사 2 — §23 5영역별 "유닛화 가능 함수" 인벤토리 (REQ-1.1·1.3 토대)

- **질문**: 각 영역에서 "디코더·전송 없이 순수하게 부를 수 있는 함수"가 무엇이고, 그게 **이미 분리돼 있나 / 핸들러 인라인에 묻혀 있나**?
- **조사 지점** (영역별 파일 — 김대리가 박음):
  - **① 식별/통지**: `domain/publisher_stream.rs`(track_id/vssrc 발급, `PublisherStream::new`), `domain/peer.rs`(`find_stream_by_track_id`/`find_stream_by_vssrc`), `signaling/handler/helpers.rs`(`collect_subscribe_tracks`, TRACKS_UPDATE 조립), `signaling/handler/track_ops.rs`.
  - **② 상태 전이**: `domain/state.rs`(ParticipantPhase), `domain/subscriber_gate.rs`(pause/resume/is_allowed), `signaling/handler/track_ops.rs`(TRACK_STATE_REQ full↔half), `domain/peer_map.rs`(mid_pool).
  - **③ 자료구조 정합**: `domain/subscriber_stream_index.rs`(by_vssrc/by_mid RCU), `domain/publisher_track_index.rs`(by_ssrc/by_rtx_ssrc), `domain/peer.rs`(`release_subscribe_track` 본문 순서), `domain/peer_map.rs`(SubscriberIndex detach).
  - **④ scope/라우팅**: `domain/peer.rs`(sub_rooms/pub_room/publish_room), `signaling/handler/scope_ops.rs`(SCOPE batch 순서).
  - **⑤ rewrite**: `domain/rtp_rewriter.rs`, `domain/ptt_rewriter.rs`(translate_rtp_ts), `domain/publisher_track.rs`(NackGenerator/seq), `domain/slot.rs`.
- **보고 형식** (영역별):
  | 영역 | 함수 시그니처 | 위치(파일:줄) | 순수성 | 분리 상태 |
  |---|---|---|---|---|
  - **순수성** = `순수`(입력→출력, I/O·전역상태·시각 의존 없음) / `준순수`(약간의 의존 — 무엇인지 명시) / `비순수`(I/O·태스크·시각).
  - **분리 상태** = `독립함수`(이미 따로 부를 수 있음) / `인라인`(핸들러/메서드 본문에 묻힘 — 추출 선결) / `메서드`(struct 메서드, self 의존).
  - ★특히 **`build_tracks_update` 류(TRACKS_UPDATE 페이로드 조립)와 `collect_subscribe_tracks` 가 독립함수냐 핸들러 인라인이냐**를 명확히 — REQ-1.3 선결조건의 핵심.

### 조사 3 — promote 두 경로 실측 (REQ-1.2 trigger≠transform)

- **질문**: simulcast placeholder 사전등록(PUBLISH_TRACKS 시점)과 RTP-first promote(첫 rid RTP 시점) — 이 **두 경로가 합류하는 "최종 상태"를 만드는 코드**가 어디고, 그 상태로부터 TRACKS_UPDATE 페이로드를 만드는 부분이 **두 경로 공통 함수냐, 경로별로 갈리냐**?
- **조사 지점**: `signaling/handler/track_ops.rs`(PUBLISH_TRACKS 처리), `transport/udp/ingress_publish.rs`(`decide_rid_promotion`, `[STREAM:PROMOTE]` 로그 자리), `domain/publisher_stream.rs`(`attach_track_to_stream`).
- **보고 형식** (서술 + 코드 인용):
  - 경로 A(early-register) 가 최종 상태를 세팅하는 지점: `파일:줄` + 코드 5~10줄 인용.
  - 경로 B(RTP-first promote) 가 최종 상태를 세팅하는 지점: `파일:줄` + 인용.
  - **두 경로가 같은 함수로 페이로드를 만드나?** Yes/No + 근거(같으면 그 함수, 다르면 각 갈래).
  - ★판단 금지 — "동치다/아니다"는 김대리가 판정. 김과장은 **"같은 함수를 부른다/다른 함수를 부른다"는 사실만.**

### 조사 4 — 봇 수신 원료 확장 가능 지점 (REQ-2.2)

- **질문**: 봇이 seq/ts 를 기록하려면 어디를 만져야 하나? `parse_rtp_mini` 가 seq/ts 를 **이미 까는가**(반환 구조에 있나), 아니면 ssrc 만 까는가?
- **조사 지점**: oxrtc `parse_rtp_mini` 정의(`grep -rn "fn parse_rtp_mini" crates/oxrtc/src`), 그 반환 타입 struct 필드 전수. `oxe2e/src/bot/media.rs::spawn_subscriber` 의 사용부.
- **보고 형식**:
  - `parse_rtp_mini` 반환 struct 필드 목록 (seq/ts/marker/pt 포함 여부 ✓/✗).
  - 현재 봇이 사용하는 필드 (ssrc 만? 그 외?).
  - seq/ts 기록하려면 바꿀 지점: `RecvLog` 구조(`media.rs`) + 사용처. **변경 제안 금지 — "여기를 바꾸면 됨" 위치만.**

### 조사 5 — 시나리오 .toml 실물 (REQ-2.3 케이스 빈칸)

- **질문**: 현재 어떤 시나리오 .toml 이 있고, §F 의 9케이스(정적5+전이4) 중 무엇이 커버되나?
- **조사 지점**: `find crates/oxe2e -name "*.toml"` + oxe2e 가 .toml 을 어디서 로드하는지(`main.rs`/`config.rs`). 레포 내 다른 위치 가능성도 `find . -name "*.toml" -path "*e2e*"` `find . -name "*.toml" -path "*scenario*"`.
- **보고 형식** (표):
  | .toml 파일 | participants 조합 | timeline 액션 | 커버 케이스(§F 9개 중) |
  |---|---|---|---|
  - 9케이스 = ①음성full ②영상full ③영상full-sim ④음성half ⑤영상half ⑥레이어전환 ⑦화자전환 ⑧full→half ⑨half→full.
  - **빈 케이스(.toml 없는 것)도 명시** — "⑥⑦ 커버, ⑧⑨ 없음" 식.

### 조사 6 — judge 음성 검증 현황 (REQ-4.4 / P-7)

- **질문**: 현재 judge 의 음성(negative)·교차검증 함수 전수와, 각각 **검증기 자체 테스트(`#[cfg(test)]`)가 있나**?
- **조사 지점**: `judge/mod.rs` 전수 — `evaluate`/`evaluate_caching`/`evaluate_gating`/`evaluate_telemetry`/`evaluate_rtx_learned`/`evaluate_gate_resume`/`evaluate_floor_granted` + `#[cfg(test)] mod tests`.
- **보고 형식** (표):
  | judge 함수 | 검증 종류(양성/음성/교차) | 자체 테스트 유무 | 자체 테스트가 음성 픽스처인가 |
  |---|---|---|---|

---

## §4 변경 영향 범위

**없음 — 조사 전용. 코드 변경 0.** 산출물은 보고서 1개뿐.

---

## §5 운영 룰

1. **수정 금지.** 발견한 결함/개선점은 보고서 말미 "발견_사항" 절에 *사실로만* 적고 손대지 않는다.
2. **판단 금지.** 분류 애매하면 "애매: 사유"로 남기고 임의 분류 안 함.
3. **추론 금지.** "아마 이럴 것"이 아니라 "코드가 이렇다"만. 못 찾으면 "못 찾음".
4. 조사 지점(김대리가 박은 파일)에서 **시작**하되, 거기 없으면 grep 으로 확장하고 **실제 위치를 보고**(김대리 지점이 틀렸을 수 있음 — 그것도 사실 보고).

---

## §6 산출물

- **단일 보고서**: `context/202606/20260626a_oxe2e_currency_survey_done.md`
- 구조: 조사 1~6 각각의 보고 형식(표/서술) + 말미 "발견_사항"(사실만) + "미해소"(못 찾은 것).
- SESSION_INDEX_202606.md 에 한 줄 추가(20~40자 + 파일명).

---

## §7 기각 (이 조사에서 하지 말 것)

- 테스트 코드 작성 (다음 작업 — 이번 아님).
- 리팩터(함수 추출 등) (REQ-1.3 선결이라 해도 이번엔 "인라인이다"만 보고).
- 판정 로직 수정.
- 봇 seq 기록 추가.
- "이렇게 고치면 좋겠다" 제안 (보고서에 넣지 말 것 — 김대리/부장님이 설계).

---

## §8 시작 전 확인 (김과장 self-check)

- [ ] 배경 요구문서 §F·§G 읽음.
- [ ] 이 작업이 조사 전용임을 인지(코드 변경 0).
- [ ] 보고 형식 6개 표/서술 골격 준비.
- [ ] grep/find 명령 6개 세트 확인.

---

## §9 직전 작업 처리

직전 = 김대리가 요구문서(`20260626_oxe2e_regression_requirements.md`) 작성 완료. 본 조사는 그 §G-1 수행. 충돌·중복 없음.

---

*author: kodeholic (powered by Claude)*
*조사 전용 작업지침. 코드 변경 0. 산출물 = 현행 사실 보고서 1개.*
