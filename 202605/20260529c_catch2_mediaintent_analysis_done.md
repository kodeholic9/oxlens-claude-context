# 분석 보고서 — catch 2: MediaIntent 분해/폐기 (핫패스 resolve_stream_kind)

**문서 ID**: `20260529c_catch2_mediaintent_analysis_done.md`
**작성**: 김과장 (Claude Code, Opus 4.7)
**원의뢰**: `claudecode/202605/20260529c_catch2_mediaintent_analysis_request.md` (김대리)
**작업일**: 2026-05-29
**성격**: 분석만 — 코드 변경 0. read/grep.

---

## §1 stream_map / MediaIntent 호출처 전수 표

### 1.1 read·write 자리

| # | 파일:라인 | 읽는/쓰는 필드 | 호출 컨텍스트 | **핫패스?** |
|---|---|---|---|---|
| 1 | `track_ops.rs:139` | write — `merge(intent)` | PUBLISH_TRACKS(add) — 1회 | 아니오 |
| 2 | `track_ops.rs:418` | write — `remove_audio()` | PUBLISH_TRACKS(remove,audio) — 1회 | 아니오 |
| 3 | `track_ops.rs:433` | write — `remove_video_source(src)` | PUBLISH_TRACKS(remove,video) — 1회 | 아니오 |
| 4 | `ingress_publish.rs:230` | **clone()** — resolve_stream_kind | **매 RTP** | **✅ 핫패스** |
| 5 | `ingress_publish.rs:359` | clone() — register_and_notify_stream | NEW track 1회 | 아니오 |
| 6 | `ingress_publish.rs:490` | read — vs.pt / vs.rtx_pt (find_by_source) | NEW track notify (subscriber 통지 pt 결정) | 아니오 |
| 7 | `ingress_publish.rs:544` | read — find_video_by_source.simulcast | NEW track notify (`track_json["simulcast"]`) | 아니오 |
| 8 | `ingress.rs:149` | read — `audio_level_extmap_id` | **매 audio RTP** (update_speaker_tracker) | **✅ 핫패스** |
| 9 | `admin.rs:84` | read 전체 — intent dump | admin snapshot | 아니오 |
| 10 | `admin.rs:133` | clone() — issues 검증 | admin snapshot | 아니오 |

### 1.2 MediaIntent 조회 메서드별 호출

| 메서드 | 호출처 | 핫패스? |
|---|---|---|
| `is_any_rtx_pt(pt)` | `ingress_publish.rs:287` (resolve_stream_kind 3차 분기) | ✅ 핫패스 |
| `has_video_mid(mid)` | `ingress_publish.rs:308`, `:374` | ✅ resolve_stream_kind 1회 / register 1회 |
| `is_rtx_pt_for_mid(mid, pt)` | `ingress_publish.rs:309` (resolve 4차 분기) | ✅ 핫패스 |
| `find_video_by_mid(mid)` | `ingress_publish.rs:314`, `:375` | ✅ resolve / register |
| `find_video_by_source(src)` | `ingress_publish.rs:406`, `:547` | 아니오 (register/notify) |
| `source_for_mid(mid)` | `ingress_publish.rs:380` | 아니오 (register) |
| `codec_for_mid(mid)` | `ingress_publish.rs:379` | 아니오 (register) |
| `first_video_source()` | `ingress_publish.rs:380` | 아니오 (register fallback) |

### 1.3 핫패스 read 정합

`resolve_stream_kind` (line 230 `intent.lock().clone()`) 매 RTP — std::Mutex acquire + `MediaIntent` clone:
- Vec<VideoSource> heap allocation (source/mid String 등)
- Option<String> (audio_mid) heap allocation
- 단일 publisher 단일 thread (ingress worker) → contention 없음. **클론 allocation 이 실 비용.**

`update_speaker_tracker` (ingress.rs:149) 매 audio RTP — clone() 없이 lock 안에서 `audio_level_extmap_id` u8 만 읽음 → 비용 작음, 그러나 std::Mutex 가 매 audio RTP × N publisher.

---

## §2 필드별 home 판정 표

| 필드 | 핫패스 read | 진짜 home 후보 | 이중화 확정 |
|---|---|---|---|
| `has_audio` | 아니오 (admin/issues 만) | `streams.iter().any(audio)` (PublisherStream 존재) | ⚠️ 의미 중복 — admin 판단용 dead-weight 후보 |
| `has_video` | 아니오 | `streams.has_video()` (`publisher_stream_index.rs:line N`) — *이미* `resolve_stream_kind:286` 가 `streams.has_video()` 직접 호출 중 | ⚠️ MediaIntent.has_video 는 admin/issues 만 read — dead-weight 후보 |
| `video_codec` | 아니오 | `PublisherStream.video_codec` (이미 등록 후 보유) | ⚠️ register/notify 의 fallback 자리만 — placeholder 면 폐기 가능 |
| `rid_extmap_id` | **✅** | **`PublishContext.rid_extmap_id: AtomicU8`** (twcc 패턴) | — write track_ops:104 + merge → atomic store 대체 가능 |
| `repair_rid_extmap_id` | **✅** | **`PublishContext.repair_rid_extmap_id: AtomicU8`** | 동일 |
| `mid_extmap_id` | **✅** | **`PublishContext.mid_extmap_id: AtomicU8`** + `config::MID_EXTMAP_ID` fallback 보존 | 동일 |
| **`twcc_extmap_id`** | — | **`PublishContext.twcc_extmap_id: AtomicU8` 이미 존재** | **✅ 죽은 필드 확정** (§3) |
| `audio_level_extmap_id` | **✅** (update_speaker_tracker) | **`PublishContext.audio_level_extmap_id: AtomicU8`** | 동일 |
| `audio_mid` | **✅** (resolve audio 분기) | **`PublishContext.audio_mid: ArcSwap<Option<Arc<str>>>`** | merge / remove_audio 가 write — ArcSwap 대체 가능 |
| `audio_duplex` | **✅** (resolve audio 분기 / register) | **`PublishContext.audio_duplex: AtomicU8` (DuplexMode)** 또는 audio PublisherStream 등록 후 그쪽으로 | merge / update_audio_duplex / remove_audio 가 write |
| `video_sources[]` | **✅** (is_any_rtx_pt / has_video_mid / find_by_mid / iter simulcast) | **PublisherStream 흡수** — 단 simulcast RTP-first 의 경우 placeholder 필요 (§4) | source/pt/rtx_pt/simulcast/codec/duplex 모두 PublisherStream 자체 자료와 중복 — register 후 의미 동등 |

### §2 결론
- **단순 이전 가능 (atomic 패턴)**: `rid_extmap_id` / `repair_rid_extmap_id` / `mid_extmap_id` / `audio_level_extmap_id` 4종 → `PublishContext: AtomicU8`
- **ArcSwap/Atomic 이전**: `audio_mid` / `audio_duplex` 2종 → PublishContext
- **죽은 필드 폐기**: `twcc_extmap_id` (§3)
- **PublisherStream 흡수 (placeholder 전제)**: `video_sources[]`, `video_codec`, `has_audio`, `has_video` — §4 simulcast 대안에 종속

---

## §3 twcc_extmap_id 죽은 필드 확정

### 사용 자리 전수
- write:
  - `track_ops.rs:106` — `twcc_extmap_id: req.twcc_extmap_id.unwrap_or(0)` (PUBLISH_TRACKS intent 빌드)
  - `stream_map.rs:141` — `merge()` 내 `if partial.twcc_extmap_id > 0 { self.twcc_extmap_id = partial.twcc_extmap_id; }`
- read: **0건** (`rg -n "twcc_extmap_id" --type rust` 전수 — MediaIntent 의 것 읽는 자리 없음)

### PublishContext 의 진짜 home
- `peer.rs:375` `pub twcc_extmap_id: AtomicU8` (정의)
- `track_ops.rs:59` write — `participant.peer.publish.twcc_extmap_id.store(twcc_id, ...)`
- `ingress_publish.rs:213` **read** — `peer.publish.twcc_extmap_id.load(...)` (collect_rtp_stats 의 twcc 파싱 자리, **핫패스**)

→ `MediaIntent.twcc_extmap_id` 는 **이미 PublishContext atomic 이전 완료된 자리의 잔재 필드**. 폐기 가능.

### §3 결론
**`MediaIntent.twcc_extmap_id` 폐기** = 1차 청소 가장 안전한 자리. 변경 면적:
- 필드 1줄 삭제 (`stream_map.rs:60`)
- write 2자리 삭제 (`track_ops.rs:106`, `stream_map.rs:141`)
- 컴파일 검증 후 218 PASS 확인

---

## §4 simulcast RTP-first 제약 — 대안 비교 (★ 핵심)

### 제약 본질
- `track_ops.rs::do_publish_tracks` (라인 ~170) — `if track_type == TrackType::FullSim { continue; }` → simulcast 트랙은 PublisherStream **미등록**
- → RTP 도착 시 `streams.get(ssrc)` 매칭 X
- → `resolve_stream_kind` 가 **MediaIntent 의 (a) `rid_extmap_id != 0` (b) `video_sources[].simulcast` (c) `find_video_by_mid` 의 `vs.simulcast`** 로 판별
- MediaIntent 가 simulcast 의도/메타의 유일한 보유처

### 대안 A — Placeholder PublisherStream 사전등록

| 설계 | 시점 PUBLISH_TRACKS 도착 시 simulcast 트랙도 `create_or_update_at_rtp` 호출. ssrc=`sim_group` (또는 0), rid=None, simulcast=true 박힘. RTP 도착 시 rid 추출 → 기존 `create_or_update_at_rtp` 의 hot-swap 패턴 (`rid_store` + sim_group 매칭)으로 placeholder 를 실 ssrc 로 promote |
|---|---|
| 면적 | `track_ops.rs` 의 `FullSim { continue; }` 제거 + `create_or_update_at_rtp` 가 simulcast placeholder 처리 분기 (ssrc=0 또는 sim_group 키 매칭) + `notify_new_stream` 의 `!is_notified` 분기 placeholder 가 처음부터 notified 처리 |
| 위험 | (1) `streams.get(ssrc)` 가 RTP 도착 첫 패킷에서는 매칭 못함 — 기존 rid 분기로 resolve → 거기서 promote 호출 자리 새로 박힘. resolve_stream_kind 의 rid 분기를 *placeholder promote 자리*로 재정의 — 핫패스 동작 변경. (2) PublisherStreamIndex 의 ssrc → Arc 매핑이 promote 후 변경됨 — RCU 패턴이라 안전하지만 정합 검증 필요 |
| 핫패스 영향 | streams.get(ssrc) 매 RTP 진입 변경 없음 (lookup 자체 유지). 다만 첫 RTP 마다 rid 분기 → promote 한 번 — 자연스러움 |
| 추가 이득 | simulcast 트랙도 PUBLISH_TRACKS 시점에 PublishState::Intended hook 발동 가능 (현 non-sim 만) — Hook Phase 3 정합 강화 |

### 대안 B — extmap + 의도만 잔존

| 설계 | MediaIntent 를 `{rid_extmap_id, repair_rid_extmap_id, mid_extmap_id, audio_level_extmap_id, audio_mid, audio_duplex, expects_simulcast: bool}` 7~8 필드로 축소. video_sources / video_codec / has_audio / has_video / twcc_extmap_id 폐기. resolve 의 `is_any_rtx_pt` / `has_video_mid` / `find_by_mid` 자리는 PublisherStream 으로 (단 simulcast 등록 전엔 streams 비어있음 → MID 분기는 race 안전망 정도로 축소) |
|---|---|
| 면적 | MediaIntent 축소 + PublishContext atomic 4~6개 추가 + resolve_stream_kind 의 video_sources iter 자리 `streams` 로 이전 (`has_video_rtx_pt` 신설) + register/notify 의 vs.pt/rtx_pt 자리 → PublisherStream.actual_pt/actual_rtx_pt (단 simulcast 등록 전엔 미정) |
| 위험 | simulcast 의 경우 register/notify 자리 자료원 없음 — placeholder(A) 와 결합해야 함 |
| 핫패스 영향 | resolve 의 lock+clone 폐기 — extmap atomic load 만. **큰 효익** |

### 대안 C — 전체 유지 (catch 2 거부)

| 평가 | 핫패스 lock+clone 비용 영구. 자료 단일출처 원칙 위반 영구. 효익(자료 정합 + 핫패스 비용) 이 큰 자리라 **비권고**. |
|---|---|

### §4 결론
**대안 A + B 결합 권고** (placeholder + extmap atomic 이전 + video_sources PublisherStream 흡수). 단계 분할로 위험 완화 (§7).

---

## §5 MID↔kind 매핑 필요성 분석

### 실 도달 시나리오 (resolve_stream_kind 의 MID 분기 — line 299~325)

| 트랙 타입 | streams.get(ssrc) | rid 분기 | MID 분기 |
|---|---|---|---|
| non-sim (등록 완료) | ✅ 매칭 → 즉시 반환 | 도달 X | 도달 X |
| simulcast (rid 정상) | ❌ 미등록 | rid_extmap 설정 + rid 추출 성공 → 반환 | 도달 X |
| simulcast (rid 추출 실패) | ❌ | repair_rid → Rtx 또는 fallthrough | **도달** |
| RTX (pt 매칭) | ❌ | — | `is_any_rtx_pt` 3차 분기에서 잡힘 (도달 안 함) |
| **PUBLISH_TRACKS race (RTP-before-intent)** | ❌ | extmap_id=0 → 미진입 | **도달** — MID 만 안전망 |

### MID 매핑이 진짜 필요한 자리
- `audio_mid` 매칭 (audio 트랙 판별) — race 시 안전망
- `has_video_mid` (video 판별) — race 시 안전망 / non-sim+sim 미등록 fallback

### 폐기/축소 판단
- **`audio_mid` = 잔존 필수** (race 안전망, ArcSwap 으로 home 이전)
- **video MID 매핑 (find_by_mid, source_for_mid, codec_for_mid)** = PublisherStream 흡수 가능. simulcast placeholder(A) 면 placeholder.mid 박혀있음 → resolve 에서 `streams.iter().find(|s| s.mid == mid)` 형태 가능 (단 PublisherStream 에 mid 필드 신설 필요 — 현재 `mid` 는 SubscriberStream 만 보유)

### §5 결론
- `audio_mid` 만 ArcSwap 으로 잔존 (race 안전망)
- video MID 분기 → PublisherStream.mid 신설 + iter find 로 대체 (placeholder 패턴)

---

## §6 register/notify 의존 해소 경로

### register_and_notify_stream (line 342~452)

| MediaIntent 호출 | 라인 | 대체 경로 (PublisherStream/PublishContext) |
|---|---|---|
| `intent.video_codec` (audio fallback) | 370, 379 | `peer.publish.video_codec: ArcSwap<Option<VideoCodec>>` 또는 placeholder PublisherStream.video_codec |
| `intent.mid_extmap_id` | 363 | `peer.publish.mid_extmap_id.load()` |
| `intent.rid_extmap_id` | 365 | `peer.publish.rid_extmap_id.load()` |
| `intent.has_video_mid` / `find_video_by_mid` (vs.rtx_pt, vs.simulcast) | 374, 375 | placeholder PublisherStream — `streams.find_by_mid(mid)` |
| `intent.codec_for_mid` | 379 | placeholder PublisherStream.video_codec |
| `intent.source_for_mid` / `first_video_source` | 380 | placeholder PublisherStream.source |
| `intent.audio_duplex` (Audio) | 403 | `peer.publish.audio_duplex.load()` |
| `intent.find_video_by_source.duplex` | 406 | placeholder PublisherStream.duplex_load() |

### notify_new_stream (line 454~628)

| MediaIntent 호출 | 라인 | 대체 경로 |
|---|---|---|
| `intent.video_sources.find(source).pt / rtx_pt` | 490~498 | placeholder PublisherStream.actual_pt / actual_rtx_pt |
| `intent.find_video_by_source.simulcast` | 547 | placeholder PublisherStream.simulcast |

### 핵심 문제 — subscriber 통지 PT 시점 race
- 현: `notify_new_stream` 의 vpt/rpt = MediaIntent (PUBLISH_TRACKS 시점 박힘) → subscriber 통지에 안전
- placeholder 안: PublisherStream.actual_pt 가 첫 RTP 헤더 PT (= negotiate PT, SDP single pt per m-line 이라 동일) — 실 동등
- 다만 *negotiate 결과* (SDP 협상) 와 *RTP 헤더 PT* 가 다른 경우는 있는가? simulcast 의 경우 단일 PT 강제 (RFC) → 일치. **안전.**
- placeholder PublisherStream 의 `actual_pt` 가 RTP 도착 전엔 0 → notify 가 RTP-1 (`is_notified=false`) 시점 호출이라 actual_pt 박혀있음. placeholder 단계에서 `actual_pt` 를 PUBLISH_TRACKS 의 pt (SDP negotiate) 로 사전 박는 것이 정합.

### §6 결론
- placeholder PublisherStream 이 PUBLISH_TRACKS 시점에 `{source, mid, actual_pt, actual_rtx_pt, simulcast, video_codec, duplex}` 박힘 → notify/register 자리 모두 해소
- PublishContext atomic 이전 후 `audio_mid` + (선택) `expects_simulcast: bool` 만 MediaIntent 에 잔존

---

## §7 김과장 권고 — 완전 폐기 가능 여부 + 분해 골격 + 단계 분할

### 7.1 권고: **축소 잔존 (대안 B + A 결합)**

**완전 폐기 (대안 A 단독)** 는 mid/audio_mid 매핑 race 안전망이 없어져 위험. 
**축소 잔존 (대안 B)** 는 placeholder 없으면 register/notify simulcast 자료 못 채움. 
→ **B 의 골격 + A 의 placeholder = 가장 안전한 분해 경로.**

최종 모습 (모든 phase 완료 후):
- `PublishContext` (atomic/ArcSwap 자리):
  - `rid_extmap_id: AtomicU8` / `repair_rid_extmap_id: AtomicU8` / `mid_extmap_id: AtomicU8` / `audio_level_extmap_id: AtomicU8`
  - `audio_mid: ArcSwap<Option<Arc<str>>>`
  - `audio_duplex: AtomicU8` (DuplexMode)
  - (기존) `twcc_extmap_id: AtomicU8`
- `PublisherStream`: 기존 자료 + `mid: Arc<str>` 신설 (placeholder + RTP 도착 후 자료)
- `MediaIntent` 자체: **폐기**. `stream_map.rs` 는 `StreamKind` enum 만 남기고 (또는 `stream_kind.rs` 로 rename)

### 7.2 단계 분할 (위험순 — 안전 → 위험)

| Phase | 내용 | 위험 | 면적 (예상) |
|---|---|---|---|
| **0차** | (사실 catch 1) — 현 디렉토리 `1차/2차/3차` 명명과 정합 위해 본 catch 2 를 **3차** 로 잡고 내부 sub-phase 로 분할 | — | — |
| **3-A** (catch 2 1차) | `MediaIntent.twcc_extmap_id` 죽은 필드 폐기 (§3) | **0** (read 0건 확정) | 5줄 |
| **3-B** | extmap 4종 atomic 이전 — `rid/repair_rid/mid/audio_level` → `PublishContext: AtomicU8`. fallback (`config::*_EXTMAP_ID`) 정합 보존. resolve_stream_kind 의 lock+clone 폐기 (lock 안 들어가는 자리만 — extmap 외 호출이 남아있어 lock 자체는 아직 잔존) | **작음** (write 단방향, atomic 의미 동등) | 핫패스 read 4자리 → atomic load |
| **3-C** | `audio_mid` → `ArcSwap<Option<Arc<str>>>` + `audio_duplex` → `AtomicU8` 이전. resolve 의 audio 분기 단순화 | **작음** | resolve 의 lock 추가 폐기 |
| **3-D** | simulcast placeholder PublisherStream — `track_ops::do_publish_tracks` 가 `FullSim` 도 등록 (rid=None, ssrc 키 = sim_group 또는 0 — 설계 결정). RTP 도착 시 rid 추출 → hot-swap promote 패턴 활용. notify_new_stream 의 `!is_notified` 분기 placeholder 가 일관 처리 | **중간** (핫패스 동작 변경 — 첫 RTP 시 placeholder→promote. fanout/forward 의 streams.get 매칭 동작 검증 필요) | 큼 |
| **3-E** | `video_sources[]` 폐기 — register_and_notify_stream / notify_new_stream / admin 의 video_sources 자료원 → PublisherStream 으로 이전. `is_any_rtx_pt(pt)` → `streams.has_video_rtx_pt(pt)` 신설. `has_video_mid` → `streams.find_by_mid(mid)` (PublisherStream.mid 신설 후) | **중간** (notify 의 vpt/rpt 자료원 시점 검증 — placeholder.actual_pt 가 PUBLISH_TRACKS pt 와 일치 확인) | 큼 |
| **3-F** | `has_audio`/`has_video`/`video_codec` 폐기 — admin/issues 자리 PublisherStream 존재로 대체. MediaIntent struct 자체 폐기 또는 `audio_mid` 만 보유 microstruct 로 축소 | 작음 (3-A~3-E 후 자연 폐기) | 정리 |

각 Phase 가 **독립 commit + 218 PASS 유지**. 3-D 만 별도 verify 필수.

### 7.3 단계별 자기 검증 기준

| Phase | 검증 |
|---|---|
| 3-A | grep `twcc_extmap_id` 0건 (MediaIntent), `cargo test` 218 |
| 3-B | grep `intent.{rid,repair_rid,mid,audio_level}_extmap_id` 0건, 핫패스 lock count `rg "stream_map.lock"` 1자리 감소 확인 (8 → 7), `cargo test` 218 |
| 3-C | grep `intent.audio_mid` / `intent.audio_duplex` 0건, `cargo test` 218 |
| 3-D | simulcast 트랙 등록 시점 PublishState::Intended hook 발동 (현 non-sim 만 발동), 218 PASS, **CTU verify (Conference simulcast scenario 가 끝까지 동작)** |
| 3-E | register/notify 의 stream_map.lock() 폐기 (read 자리만 — write 는 3-F 에서). 218 PASS |
| 3-F | `MediaIntent` symbol 0건 또는 `microstruct` 잔존 (audio_mid 만), `stream_map.rs` 폐기 또는 rename, 218 PASS |

### 7.4 부장님 결정 요청 사항

1. **완전 폐기 vs 축소 잔존**: 권고 = 축소 잔존 (audio_mid microstruct 또는 atomic 잔존).  
2. **placeholder 키 설계**: ssrc=0 (sentinel) vs sim_group 키 (별 인덱스) — Phase 3-D 진입 전 김대리/부장님 결정.
3. **PublisherStream.mid 필드 신설 합의**: 현재 mid 는 SubscriberStream 만 보유 — PublisherStream 에도 신설 (MID 분기 자료원).
4. **단계 commit 정책**: 각 sub-phase 별 commit (6 commit) vs 3-A/B/C 묶음 + 3-D/E/F 묶음 (2 commit). 위험순상 sub-phase 별 권고.

### 7.5 mediasoup/LiveKit 선례 (prior knowledge)
- **mediasoup `Producer::ReceiveRtpPacket`**: SSRC → `RtpStream` 매핑 단일출처. simulcast 도 미리 등록 (`Producer::NewRtpStream` 자리에서 rid 별 RtpStream 발급) — 대안 A 와 일치 패턴.
- **LiveKit `MediaTrackPublication`**: track 메타가 protobuf TrackInfo 로 한 출처 — placeholder 패턴 (TrackInfo 사전 + RTP 도착 후 binding).
- → **대안 A (placeholder 사전등록)** 가 업계 정석. catch 2 가 그 방향과 일치.

---

## §8 미확인 / 보류

- **PublisherStream.mid 신설** 시 hot-swap 패턴과 정합 (`create_or_update_at_rtp` 의 같은 ssrc 매칭 시 mid 갱신 분기) — Phase 3-D 진입 전 추가 분석 필요 시 재의뢰.
- **`expects_simulcast: bool`** 의 의미 — `rid_extmap_id != 0` 으로 추정 가능 → 별 필드 불필요? 3-B 에서 검증.
- **사이드 효과**: SubscriberStream 의 `forwarder.publisher_user_id` 가 1차 (peer_ref 폐기) 에서 vssrc 역탐색으로 대체된 패턴 — Phase 3-D 의 placeholder 도 유사한 자료 동등성 검증 필요.

---

## §9 시간 사용
1 사이클 내 완료. 6항목 모두 조사. 미확인 §8 3건 — 모두 Phase 3-D 진입 전 별도 사이클로 추가 분석 가능.

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-29*
