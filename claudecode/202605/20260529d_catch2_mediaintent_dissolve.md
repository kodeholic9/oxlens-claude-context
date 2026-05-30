# 작업 지침 — 3차: catch 2 MediaIntent 분해/폐기 (6 sub-phase)

**문서 ID**: `20260529d_catch2_mediaintent_dissolve.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**선행 분석**: `context/202605/20260529c_catch2_mediaintent_analysis_done.md` (김과장 작성 — **구현 시 §7 단계분할 + §7.4 결정사항 정합**)
**성격**: **가장 위험 — 핫패스 `resolve_stream_kind` / `register_and_notify_stream`.** 6 sub-phase 단계 분할.
**부장님 GO**: 대기

> 백로그 3차. MediaIntent 가 3역할(PC pair extmap / 트랙 메타 / simulcast RTP-first 버팀목)을 한 구조체에 섞어 든 것을 분해. 업계 선례(mediasoup `NewRtpStream` rid별 placeholder / LiveKit TrackInfo 사전등록)와 정합하는 placeholder 방식. **MediaIntent struct 는 폐기하되 알맹이는 PublishContext 로 분산 잔존 (축소 잔존).**

---

## §0 의무 점검 (착수 전)

1. `cargo test -p oxsfud` baseline 확인 (bitmask fix commit 후 수치).
2. **자기 분석 보고서 `20260529c_..._done.md` §7 단계분할 + §7.4 결정사항 재확인** — 본 지침은 김대리가 §7.4 권고를 결정으로 확정한 것. 보고서 세부와 충돌 시 *발견_사항* 보고 후 부장님 컨펌.
3. **필드/메서드 폐기 시 grep 3종 전수** (점검 미흡 5회차 방지) — 폐기 대상마다 read/write 호출처 전수 확인 후 착수.
4. 핫패스라 각 sub-phase 끝마다 `cargo test` + 정지점.

---

## §1 컨텍스트 — 분석 결과 (김과장 §3~7 + 부장님 §7.4 결정)

| # | 발견 | 결정 |
|---|---|---|
| §3 | `MediaIntent.twcc_extmap_id` write 2자리(track_ops:106/merge:141) read 0 — 죽은 필드. 진짜 home = `PublishContext.twcc_extmap_id: AtomicU8` (ingress_publish:213 핫패스 read) | 3-A 폐기 (5줄, 위험 0) |
| §4 | 대안 A+B 결합 — placeholder PublisherStream + extmap atomic 이전 + audio_mid ArcSwap 잔존 + video_sources 흡수 | 채택 |
| §4 | C(거부) 비권고 — 핫패스 lock+clone 영구 + 단일출처 위반 | 기각 |
| §6 | placeholder 에 actual_pt 를 PUBLISH_TRACKS pt 사전 박기 → notify race 없음 (SDP single PT per m-line) | 채택 |
| §7.5 | mediasoup NewRtpStream / LiveKit TrackInfo = placeholder 정석 | 정합 확인 |
| §7.4-1 | 완전 폐기 vs **축소 잔존** | **축소 잔존** (extmap/audio_mid 는 PublishContext 잔존, struct 만 폐기) |
| §7.4-2 | placeholder 키 (ssrc=0 vs sim_group) | **3-D 시점 선조치** — notify_new_stream `!is_notified` + `streams.get(ssrc)` 충돌 여부 보고 후 결정 |
| §7.4-3 | PublisherStream.mid 필드 신설 | **합의 — 신설** (MID↔kind 매핑 단일출처) |
| §7.4-4 | commit 정책 | **6 commit** (핫패스 — 단계별 회귀 추적. 특히 3-D 단독 verify) |

---

## §2 결정된 사항

1. **축소 잔존** — MediaIntent struct 는 3-F 에서 폐기. extmap IDs + audio_mid 는 PublishContext 직접 필드로 잔존.
2. **6 commit** — sub-phase 마다 commit + test. 3-D 는 단독 verify 필수.
3. **PublisherStream.mid 필드 신설** (3-E) — MID↔kind 매핑 단일출처.
4. placeholder 키 — 3-D 진입 시 김과장 선조치 보고 후 결정.

---

## §3 정지점 (핫패스라 4개)

| 정지점 | 자리 | commit |
|---|---|---|
| | 3-A 끝 | `refactor(sfu): catch2 3-A — MediaIntent.twcc_extmap_id 죽은 필드 폐기` |
| | 3-B 끝 | `refactor(sfu): catch2 3-B — extmap 4종 PublishContext atomic 이전` |
| | 3-C 끝 | `refactor(sfu): catch2 3-C — audio_mid/audio_duplex PublishContext 이전` |
| ★ | **3-D 끝** | `feat(sfu): catch2 3-D — simulcast placeholder PublisherStream 사전등록` (★ 단독 verify) |
| ★ | **3-E 끝** | `refactor(sfu): catch2 3-E — video_sources PublisherStream 흡수` |
| | 3-F 끝 | `refactor(sfu): catch2 3-F — MediaIntent struct 폐기` |

★ = GO 사인 대기 정지점. 3-D/3-E 는 부장님 보고 + GO 후 다음 진입. 나머지는 연속 후 통합 리뷰.

---

## §4 단계별 작업

### 3-A — twcc_extmap_id 죽은 필드 폐기 (위험 0)

1. `stream_map.rs`: `MediaIntent.twcc_extmap_id` 필드 제거 + merge 안 `if partial.twcc_extmap_id > 0 {...}` 제거
2. `track_ops.rs`: `do_publish_tracks` 의 intent 생성 시 `twcc_extmap_id: req.twcc_extmap_id.unwrap_or(0)` 제거 (PublishContext.twcc_extmap_id.store 는 유지 — 그게 진짜 home)
3. grep 으로 read 0 재확인 후 제거. `cargo test` + commit.

### 3-B — extmap 4종 PublishContext atomic 이전 (작음)

대상: `rid_extmap_id` / `repair_rid_extmap_id` / `mid_extmap_id` / `audio_level_extmap_id`

1. `peer.rs` PublishContext: `AtomicU8` 4개 신설 (twcc_extmap_id 패턴 그대로). 생성자 init 0.
2. `track_ops.rs`: `do_publish_tracks` 가 req 에서 4종을 PublishContext 에 store (intent 가 아니라).
3. `resolve_stream_kind` / `register_and_notify_stream`: `intent.rid_extmap_id` → `peer.publish.rid_extmap_id.load()` 치환. `config::*_EXTMAP_ID` fallback 로직 유지.
4. `MediaIntent` 에서 4 필드 + merge 분기 제거.
5. grep 전수 (4종 각각 read/write). `cargo test` + commit.

> 핫패스 주의 — `resolve_stream_kind` 맨 위 `intent = stream_map.lock().clone()` 가 extmap 위해 lock 하던 것. extmap 이전 후 그 clone 이 video_sources 만 위해 남는지 확인 (3-E 까지 lock 잔존).

### 3-C — audio_mid / audio_duplex PublishContext 이전 (작음)

1. `peer.rs` PublishContext: `audio_mid: ArcSwap<Option<String>>` + `audio_duplex: AtomicU8`(DuplexMode 인코딩) 신설. (보고서 §4 audio_mid ArcSwap 잔존 권고 정합 — race 안전망)
2. `track_ops.rs`: req → PublishContext store.
3. `resolve_stream_kind` MID 분기: `intent.audio_mid` → `peer.publish.audio_mid.load()`. `intent.audio_duplex` → load.
4. `MediaIntent` 에서 2 필드 + merge/remove_audio/update_audio_duplex 분기 정리.
5. grep + `cargo test` + commit.

### 3-D — simulcast placeholder PublisherStream 사전등록 (★ 중간 — 단독 verify)

**핵심 — MediaIntent 완전 폐기를 막던 자리 해소.**

1. `track_ops.rs::do_publish_tracks`: `if track_type == TrackType::FullSim { continue; }` 제거 → simulcast 트랙도 PublisherStream "placeholder" 등록.
   - **placeholder 키 = 김과장 선조치 결정** (§2.4). `notify_new_stream` 의 `!is_notified` 분기 + `streams.get(ssrc)` 가 placeholder 와 충돌하는지 먼저 grep/분석 → ssrc=0 vs sim_group 결정 + 보고.
   - placeholder 에 `actual_pt` = PUBLISH_TRACKS pt 사전 박기 (§6 — notify race 방지).
   - rid 미정(None), simulcast=true, sim_group 세팅.
2. `resolve_stream_kind`: simulcast RTP 도착 시 rid 파싱 → placeholder 의 ssrc 채움(또는 rid별 분화). 기존 FullSim 분기가 placeholder lookup 으로 전환.
3. **이 단계는 동작 변경 가능성** — simulcast 등록 시점이 RTP-first → PUBLISH_TRACKS 시점으로 당겨짐. notify/gate/fanout 흐름 정합 필수.
4. **★ 단독 verify** — 단일방 simulcast smoke (레이어 h/l 전환 + 신규 입장 시 simulcast 트랙 노출). 부장님 E2E 범위 결정.
5. `cargo test` + commit (★ GO 대기).

> **2회 실패 시 중단** — placeholder 가 fanout/notify 와 충돌해 simulcast 깨지면 즉시 중단 + 보고. 핫패스라 "망가지면 고치면 된다"지만 깨진 채 진행 금지.

### 3-E — video_sources PublisherStream 흡수 (★ 중간)

1. `PublisherStream.mid: ArcSwap<Option<String>>` 필드 신설 (§2.3). 등록 시 MID 세팅.
2. `register_and_notify_stream` / `notify_new_stream`: `intent.find_video_by_*` / `video_sources` 참조 → PublisherStream 자체 자료(source/pt/rtx_pt/simulcast/codec/duplex/mid) 로 치환.
3. `resolve_stream_kind` MID 분기 `has_video_mid` / `find_video_by_mid` → PublisherStream.mid lookup 으로.
4. `is_any_rtx_pt` / `is_rtx_pt_for_mid` — RTX 판별. PublisherStream 의 rtx_pt 로 대체 가능한지 (placeholder 가 rtx_pt 보유).
5. grep 전수 (video_sources 조회 메서드 7종 각 호출처). `cargo test` + commit (★ GO 대기).

### 3-F — MediaIntent struct 폐기 (작음)

1. 3-A~3-E 후 MediaIntent 에 남은 게 `has_audio`/`has_video`/`video_codec` 정도. PublisherStream 존재 여부로 대체 가능한지 최종 확인.
2. `peer.publish.stream_map` 필드 제거. `MediaIntent` / `VideoSource` struct 폐기. `stream_map.rs` → 잔존 `StreamKind` 만 남기고 파일 정리(또는 rename).
3. `.merge()` 호출 (`track_ops.rs`) 제거 — 3-B~3-E 에서 직접 store 로 대체됐으므로 빈 껍데기.
4. grep 전수 (`stream_map` / `MediaIntent` / `VideoSource` 0건 확인). `cargo test` + clippy + commit.

---

## §5 변경 영향 범위

| 파일 | sub-phase | 변경 |
|---|---|---|
| `room/stream_map.rs` | 3-A,B,C,E,F | MediaIntent 필드/메서드 점진 제거 → struct 폐기 |
| `room/peer.rs` (PublishContext) | 3-B,C | extmap 4 atomic + audio_mid ArcSwap + audio_duplex atomic 신설 |
| `room/publisher_stream.rs` | 3-E | mid 필드 신설 + 흡수 |
| `signaling/handler/track_ops.rs` | 3-A,B,C,D | intent 생성 → PublishContext store + FullSim continue 제거 |
| `transport/udp/ingress_publish.rs` | 3-B,C,D,E | resolve_stream_kind / register / notify 의 intent 참조 치환 |

**안 건드림**: catch 4(보류) / bitmask(완료) / floor / scope.

---

## §6 운영 룰

1. **정지점 4개** (§3) — 3-D/3-E 는 ★ GO 대기.
2. **grep 3종 전수** — 필드/메서드 폐기마다 read/write 호출처 전수 (점검 미흡 방지).
3. **핫패스 — 2회 실패 시 즉시 중단** — 특히 3-D placeholder 충돌. 깨진 채 진행 금지.
4. **추가 변경 금지** — §5 외. 별 발견은 *발견_사항* 보고만.
5. **선조치 보고** — 3-D placeholder 키 / PublishContext 생성자 자리 / resolve_stream_kind lock 잔존 범위.
6. **동작 변경** — 3-D(simulcast 등록 시점 당김) 만 동작 변경. 나머지는 등가. 3-D 외 동작 변경 발생 시 보고.

---

## §7 기각 접근법

- **C(MediaIntent 완전 유지)** — 핫패스 lock+clone 영구 + 자료 단일출처 위반. 기각.
- **A 단독 (placeholder 만)** — audio_mid race 안전망 없음. B 결합 필요.
- **B 단독 (extmap 이전만)** — register/notify simulcast 자료원 사라짐. A 결합 필요.
- **완전 폐기 (extmap 까지 제거)** — simulcast RTP-first + audio_mid race 가 잔존 강제. 축소 잔존이 정답.
- **2 묶음 commit** — 핫패스 회귀 추적 불가. 6 commit (특히 3-D 단독).

---

## §8 산출물

- commit 6개 (§3)
- 완료 보고: `context/202605/20260529d_catch2_mediaintent_dissolve_done.md` (**202605/ 자리**)
  - 3-A~3-F 각 test/clippy 수치
  - **3-D 동작 변경 확인** (simulcast 등록 시점 + smoke 결과)
  - placeholder 키 결정 근거 (선조치)
  - 다음 (catch 4 PLI 근본 재분석 토픽) 진입 전 잔여

---

## §9 시작 전 확인

1. baseline test 수치?
2. 보고서 §7 단계분할 + §7.4 재확인 — 충돌 시 보고.
3. 축소 잔존 (struct 폐기 / extmap·audio_mid 잔존) 이해?
4. 6 commit + 3-D/3-E ★ GO 대기.
5. **3-D 가 핵심** — simulcast 등록 시점 당김 + placeholder 충돌 주의. 2회 실패 시 중단.
6. grep 3종 전수 습관.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-29*
