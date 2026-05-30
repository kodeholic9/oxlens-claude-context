# 분석 의뢰 — catch 2: MediaIntent 분해/폐기 (핫패스 resolve_stream_kind)

**문서 ID**: `20260529c_catch2_mediaintent_analysis_request.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**성격**: **분석만 — 코드 변경 0.** 조사 후 보고서 작성.
**부장님 GO**: 김과장 분석 → 보고 → 김대리 구현 지침 박음

> 백로그 3차 (가장 위험 — 핫패스 `ingress_publish::resolve_stream_kind`). catch 2 = MediaIntent 폐기. 단 김대리 사전 분석 결과 *단순 폐기가 아니라 "분해 후 흡수"* 일 가능성이 높음. 김과장이 전체 호출처 + 필드별 home + simulcast 제약을 조사 → 완전 폐기 가능 여부 / 분해 대안을 보고.

---

## §0 컨텍스트 — 김대리 사전 분석 (이 그림을 출발점으로)

### MediaIntent 의 3가지 이질적 역할

MediaIntent(`stream_map.rs`)는 한 구조체에 성격이 다른 3종 자료를 섞어 들고 있다:

**역할 1 — PC pair 단위 메타 (extmap IDs)**
- `rid_extmap_id` / `repair_rid_extmap_id` / `mid_extmap_id` / `twcc_extmap_id` / `audio_level_extmap_id`
- SDP 협상 결과 → publish PC 전체 적용 (트랙 단위 아님)
- **★ 결정적 단서**: `twcc_extmap_id` 는 *이미* `PublishContext.twcc_extmap_id: AtomicU16` 로 **별도 존재**. `collect_rtp_stats` 는 `peer.publish.twcc_extmap_id.load()` 만 사용. → MediaIntent 의 `twcc_extmap_id` 는 **죽은 필드 의심**. extmap 이전이 일부 시작됐고 잔재 남은 정황.

**역할 2 — 트랙 단위 메타 (video_sources)**
- `video_sources[]`: source / mid / pt / rtx_pt / simulcast / codec / duplex
- **PublisherStream 이 등록 후 이미 보유하는 정보와 중복** (`stream.source`, `stream.actual_pt`, `stream.rtx_ssrc`, `stream.simulcast`, `stream.video_codec`, `stream.duplex_load()` 등)

**역할 3 — simulcast RTP-first 의 유일한 버팀목**
- non-sim: PUBLISH_TRACKS 시점에 `add_publisher_stream` 으로 PublisherStream 등록 (ssrc 보유)
- simulcast: `track_ops.rs::do_publish_tracks` 가 `if track_type == TrackType::FullSim { continue; }` 로 **PublisherStream 등록 건너뜀** (RTP-first, rid 동적 매핑)
- → RTP 도착 시 ssrc 가 `streams` 에 없음 → `resolve_stream_kind` 가 `intent.rid_extmap_id` + `intent.video_sources[].simulcast` 로 판별
- **이게 MediaIntent 완전 폐기를 막는 자리.** simulcast 의도가 PublisherStream 엔 없고 MediaIntent 에만 있음.

### resolve_stream_kind 의 MediaIntent 의존 (핫패스)

판별 순서 (RTP 도착, ssrc 미등록 시):
1. `intent.rid_extmap_id != 0` + `intent.video_sources[].simulcast` → rid 파싱 → FullSim
2. `intent.repair_rid_extmap_id` → repair_rid 파싱 → Rtx
3. `intent.is_any_rtx_pt(pt)` → Rtx
4. `intent.mid_extmap_id` → MID 파싱 → `intent.audio_mid` 매칭(Audio) / `intent.has_video_mid` 매칭(Video) / `intent.is_rtx_pt_for_mid`(Rtx)
5. fallthrough → Unknown

→ MediaIntent 의 핫패스 의존 = **extmap IDs (파싱 키) + simulcast 의도 + MID↔kind 매핑 + rtx_pt 판별**.

### 추정되는 본질 (김과장이 검증/반박할 것)

- extmap IDs → `PublishContext` 직접 필드로 이전 (twcc 가 이미 그 패턴)
- video_sources 트랙 메타 → PublisherStream 으로 흡수 (이미 중복 보유)
- has_audio/has_video → PublisherStream 존재 여부로 대체
- **남는 문제 = simulcast RTP-first + MID↔kind 매핑.** 이 둘이 "완전 폐기 vs 축소 잔존" 을 가른다.

---

## §1 조사 항목

### 1.1 MediaIntent / stream_map 호출처 전수 grep

```bash
grep -rn "stream_map\|MediaIntent\|\.intent\b\|VideoSource" crates/oxsfud/src/
```

각 호출처: 파일/라인 + 어떤 필드 읽는지/쓰는지 + 핫패스 여부. 특히:
- `stream_map.lock()` 호출 전수 (read vs write)
- `.merge()` / `.remove_video_source()` / `.remove_audio()` / `.update_audio_duplex()` 호출처
- MediaIntent 조회 메서드 (`is_any_rtx_pt`/`has_video_mid`/`find_video_by_mid`/`codec_for_mid`/`source_for_mid`/`first_video_source`/`find_video_by_source`) 각 호출처

### 1.2 필드별 진짜 home 판정

MediaIntent 각 필드에 대해 — "이 자료의 자연스러운 home 은 어디인가" + "이미 다른 곳에 같은 정보가 있는가(이중화)":

| 필드 | 후보 home | 이중화 여부 (grep 확인) |
|---|---|---|
| `rid_extmap_id` | PublishContext? | resolve_stream_kind 외 사용처? |
| `repair_rid_extmap_id` | PublishContext? | |
| `mid_extmap_id` | PublishContext? | `config::MID_EXTMAP_ID` fallback 과 관계 |
| `twcc_extmap_id` | **PublishContext.twcc_extmap_id 이미 존재** | **죽은 필드? — MediaIntent.twcc_extmap_id 를 읽는 곳이 있나** |
| `audio_level_extmap_id` | PublishContext? | speaker_tracker 사용처 |
| `has_audio` / `has_video` | PublisherStream 존재로 대체? | 순수 boolean 판별에만 쓰이는지 |
| `video_codec` | PublisherStream.video_codec 중복? | |
| `audio_mid` | ? (MID↔kind 매핑 — §1.5) | |
| `audio_duplex` | PublisherStream.duplex 중복? | register 시점에만? |
| `video_sources[]` | PublisherStream 중복? | simulcast 의도만 예외? |

### 1.3 twcc_extmap_id 이중화 확정

- `PublishContext.twcc_extmap_id: AtomicU16` 와 `MediaIntent.twcc_extmap_id: u8` 둘 다 존재
- `track_ops.rs::do_publish_tracks` 가 **둘 다** 세팅하는지 확인
- `MediaIntent.twcc_extmap_id` 를 *읽는* 곳이 있는가 → 없으면 죽은 필드 (catch 2 의 가장 쉬운 1차 청소 대상)

### 1.4 simulcast RTP-first 제약 — 완전 폐기 가능 여부 (★ 핵심)

simulcast 트랙은 PUBLISH_TRACKS 시점 PublisherStream 미등록 → RTP 도착 시 MediaIntent 로 판별. **이 제약을 우회하는 대안 조사:**

- **대안 A**: simulcast 트랙도 PUBLISH_TRACKS 시점 PublisherStream "예약" 등록 (placeholder — rid 미정, ssrc 미정 or sim_group 만). RTP 도착 시 rid→ssrc 채움. → `track_ops.rs` 의 `if track_type == FullSim { continue }` 제거 가능?
- **대안 B**: extmap IDs + simulcast 의도(`expects_simulcast: bool` + `rid_extmap_id`)만 PublishContext 에 남기고, MediaIntent 의 나머지(video_sources 트랙 메타) 폐기. → MediaIntent 가 "PC pair 협상 메타"로 축소
- **대안 C**: MediaIntent 완전 유지 (catch 2 거부 — 분해 가치 < 비용)

각 대안의 면적 + 핫패스 영향 + 위험 보고. simulcast placeholder PublisherStream 이 기존 fanout/notify 흐름과 충돌하는지 (notify_new_stream 의 `!is_notified` 분기 등).

### 1.5 MID↔kind 매핑 — MediaIntent 없이 가능한가

`resolve_stream_kind` 4번 분기: MID 파싱 → `intent.audio_mid` 매칭(Audio) / `intent.has_video_mid`(Video). 이 MID↔kind 매핑이:
- non-sim 은 PublisherStream 이 이미 등록돼서 1번 분기(`streams.get(ssrc)`)에서 끝남 → MID 분기 도달 안 함?
- MID 분기가 실제로 필요한 경우는? (simulcast? 첫 RTP 가 rid 없이 도착? RTX?)
- PublishContext 에 `audio_mid` + video mid↔source 맵만 남기면 되는가

### 1.6 register_and_notify_stream / notify_new_stream 의 MediaIntent 의존

이 두 함수도 MediaIntent 를 광범위하게 읽음 (codec/source/rtx_pt/simulcast/pt). PublisherStream 흡수 후 이 함수들이 어디서 메타를 얻을지. 특히:
- `notify_new_stream` 의 `intent.video_sources.find(source).pt/rtx_pt` (subscriber 통지용 pt) — PublisherStream 에 pt 는 있으나 **subscriber 통지용 negotiated pt** 가 PublisherStream 에 있는지
- `create_or_update_at_rtp` 인자가 MediaIntent 에서 오는데, 이게 PublisherStream 자체 자료로 대체 가능한지

---

## §2 산출물

**보고서 자리**: `~/repository/context/202605/20260529c_catch2_mediaintent_analysis_done.md` (**202605/ 자리**)

**구조:**
```
§1 MediaIntent/stream_map 호출처 전수 표 (파일/라인/필드/read·write/핫패스)
§2 필드별 home 판정 표 (§1.2 — 후보 home + 이중화 확정)
§3 twcc_extmap_id 죽은 필드 여부 (§1.3)
§4 simulcast RTP-first 대안 A/B/C 비교 (면적/핫패스/위험) — ★ 핵심
§5 MID↔kind 매핑 필요성 분석 (§1.5)
§6 register/notify 의존 해소 경로 (§1.6)
§7 김과장 권고 — 완전 폐기 가능 여부 + 분해 설계 골격 + 단계 분할 제안 (위험 핫패스라 Phase 잘게)
```

§7 에 **"완전 폐기 / 축소 잔존 / 거부" 중 권고 + 근거**. 위험 핫패스라 한방 말고 *단계 분할* (예: 1단계 죽은 필드 청소 → 2단계 extmap PublishContext 이전 → 3단계 video_sources PublisherStream 흡수 → 4단계 simulcast placeholder) 제안.

---

## §3 운영 룰

1. **코드 변경 0** — read/grep 만. write 금지.
2. **2회 막히면 보고** — 어떤 자리 불명확하면 §2 보고서에 "미확인" 명시.
3. **시간 한도** — 1~2 사이클. 핫패스라 충실히. 길면 부분 보고.
4. **업계 선례** — mediasoup `Producer::ReceiveRtpPacket` 의 SSRC/MID/RID 매핑 패턴 prior knowledge 있으면 §7 참조. web fetch 금지.
5. **본 분석은 "어떻게 폐기/분해할지" 설계가 아니라 "현황 + 제약 + 대안"** — 최종 설계는 김대리가 보고 받고 부장님 결재 후.

---

## §4 시작 전 확인

1. catch 2 = MediaIntent 분해/폐기. 핫패스 resolve_stream_kind.
2. §0 김대리 그림 (3역할 + twcc 이중화 단서 + simulcast RTP-first 제약) 이해?
3. 코드 변경 0.
4. §1 6항목 조사. 미확인은 보고서 명시.
5. **simulcast RTP-first (§1.4) 가 본 분석의 핵심** — 완전 폐기를 막는 자리. 대안 충실히.

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-29*
