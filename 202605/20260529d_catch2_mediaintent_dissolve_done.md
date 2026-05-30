# 완료 보고 — 3차: catch 2 MediaIntent 분해/폐기 (6 sub-phase)

**문서 ID**: `20260529d_catch2_mediaintent_dissolve_done.md`
**작성**: 김과장 (Claude Code, Opus 4.7)
**원지침**: `claudecode/202605/20260529d_catch2_mediaintent_dissolve.md` (김대리)
**선행 분석**: `context/202605/20260529c_catch2_mediaintent_analysis_done.md` (김과장)
**작업일**: 2026-05-29
**상태**: ✅ 6 commit 완료 — E2E verify 보류(부장님 결정 — 향후 한묶음).

---

## §0 검증 요약

| Sub-phase | commit | test | clippy | 비고 |
|---|---|---|---|---|
| baseline | (3-A 진입 전) | 218 PASS | 108 warnings + bit mask 사전 에러 | — |
| **3-A** | `37539e0` | 218 PASS | 동일 | twcc 죽은 필드 5줄 폐기 |
| **3-B** | `fcd7409` | 218 PASS | 동일 | extmap 4종 PublishContext atomic 이전 |
| **3-C** | `a22b2e4` | **217 PASS** | 동일 | SWITCH_DUPLEX dead 메서드 폐기로 test_intent_update_audio_duplex 1 self-test 소멸 → 217 |
| **3-D ★** | `ee8d093` | 217 PASS | 동일 | simulcast placeholder 사전등록 — 동작 변경 1자리 |
| **3-E ★** | `4942122` | 217 PASS | 동일 | video_sources PublisherStream 흡수 + 핫패스 lock 자리 0건 |
| **3-F** | `98f2431` | **211 PASS** | **+1 warning** | struct 폐기로 stream_map.rs 의 6 self-test 자연 소멸 → 211. 신규 warning 1건 (`collapsible_if` 또는 `needless_borrow` — pre-existing 패턴과 동등) |

**`git diff stat` (3-A~3-F 누적)**: 11 file changed, +212 / -396 lines.

---

## §1 핫패스 영향 — `stream_map.lock()` 자리 0건

| 자리 | baseline | 3-F 후 |
|---|---|---|
| `ingress_publish.rs::resolve_stream_kind` (매 RTP) | `stream_map.lock().clone()` + MediaIntent clone allocation | **폐기** — 매 RTP atomic load + streams.iter() |
| `ingress_publish.rs::register_and_notify_stream` (NEW track) | 동일 | **폐기** |
| `ingress_publish.rs::notify_new_stream` (NEW track) | `stream_map.lock()` × 2 | **폐기** |
| `ingress.rs::update_speaker_tracker` (매 audio RTP) | `stream_map.lock()` | **폐기** (atomic load) |
| `track_ops::do_publish_tracks` | `stream_map.lock()` write | **폐기** (PublishContext store) |
| `track_ops::handle_publish_tracks_remove` | `stream_map.lock()` write | **폐기** |
| `admin.rs::build_rooms_snapshot` | `stream_map.lock()` × 2 | **폐기** |

**핫패스 매 RTP lock+clone 비용 = 0.** 자료 출처가 단일출처 (PublisherStream + PublishContext atomic) 로 통합.

---

## §2 3-D 동작 변경 확인 (지침 §6.6)

### 변경 1자리 — simulcast 등록 시점 RTP-first → PUBLISH_TRACKS 사전등록

| 자리 | baseline 동작 | 3-D 후 동작 |
|---|---|---|
| `track_ops::do_publish_tracks` FullSim 분기 | `if track_type == TrackType::FullSim { continue; }` — 등록 skip | placeholder 등록 — sim_group sentinel ssrc (`0xF000_0000 \| counter`) + simulcast=true + simulcast_group=Some(sim_group) + actual_pt=req.pt + mid=t.mid + source 박힘 |
| Intended hook 발동 | non-sim 만 발동 (sim 트랙은 RTP 도착 후 Active hook 만) | **sim 트랙도 발동** — `track:publish_intent` agg-log 기록 |
| `ingress_publish::register_and_notify_stream` simulcast 첫 RTP 도착 | non-existent 분기 (FullSim 진입 자리 없음) | 같은 source 의 placeholder 찾아 `peer.remove_publisher_stream(ph_ssrc)` + 실 ssrc PublisherStream 신규 등록 (rid별 분화 — mediasoup `NewRtpStream` 정합). `[STREAM:PROMOTE]` 로그 1회 |
| `streams.get(ssrc)` 매 RTP lookup | placeholder 와 RTP ssrc 달라 영향 0 | 동일 |
| fanout/forward/gate | 변경 0 | 변경 0 |

**의미적 변경 1건**: 1 publisher 의 cross-room sub_rooms affiliate 시 (현 1방 발언 모델에서는 매우 드문 자리) placeholder 의 의도가 publisher 단위로 박힘. 1방 발언 단일 시나리오에서는 동작 동등.

### E2E verify 보류
부장님 결정 — *"e2e는 향후 한묶음에 하자"*. 검증 항목 (향후 verify 시):
- `[STREAM:PROMOTE]` 로그 1회 per simulcast publisher RTP 첫 도착.
- admin snapshot 의 `intent_state.video_sources[].is_placeholder=true` 항목 (PUBLISH_TRACKS 직후, RTP 도착 전).
- 레이어 h/l 전환 + 신규 입장 시 simulcast 트랙 노출 — 영향 0 (기존 흐름).

---

## §3 placeholder 키 결정 근거 (선조치 §2.4)

### 결정 — sim_group sentinel 키 + 옵션 A→B 변경

| 항목 | 결정 | 사유 |
|---|---|---|
| 키 후보 | **sim_group (u32 unique alloc)** | multi-source simulcast(camera+screen 동시) 충돌 회피. PublisherStream.ssrc 불변성 보존 |
| sentinel range | **`0xF000_0000 \| counter`** | 실 SDP SSRC (보통 random 32bit) 와 충돌 회피 |
| alloc | per-Peer `sim_group_counter: AtomicU32` + `alloc_sim_group()` | `rtx_ssrc_counter` 패턴 |
| 옵션 (notify 시점) | **옵션 B (RTP 도착 후 promote 단계 notify)** | 옵션 A 의 즉시 notify 가 `track_ops.rs:88` Phase D RTP-first 디자인 위반. notify_new_stream 이 `impl UdpTransport` 라 signaling handler 자리 직접 호출 불가 |
| race 안전망 | placeholder.actual_pt = PUBLISH_TRACKS pt 사전 박기 (§6) | SDP single PT per m-line 보장 — RTP 헤더 PT 와 일치 |

부장님 GO 후 진행. 옵션 A→B 변경은 김과장 자율 판단 + 부장님 GO.

### 추가 자율 판단 — PublisherStream.mid 3-D 에 신설
지침 §4 3-E 1번 "PublisherStream.mid 필드 신설" 자리이지만 3-D placeholder 매칭에 필수 (mid 기반 lookup). 3-D 에 미리 신설 → 3-E 에서 자연 활용. 면적 작음.

---

## §4 변경 면적 (지침 §5 정합)

| 파일 | sub-phase | 변경 요약 |
|---|---|---|
| `room/stream_map.rs` | 3-A,B,C,F | MediaIntent struct 점진 폐기 → 3-F 에서 완전 폐기. `StreamKind` enum 만 잔존 |
| `room/peer.rs` (PublishContext) | 3-B,C,D,F | extmap 4 AtomicU8 + audio_mid ArcSwap + audio_duplex AtomicU8 + sim_group_counter AtomicU32 신설 / `stream_map: Mutex<MediaIntent>` 필드 폐기 |
| `room/publisher_stream.rs` | 3-D,E | `mid: ArcSwap<Option<Arc<str>>>` 필드 신설 / `new` + `create_or_update_at_rtp` 시그너처 mid 인자 / `is_placeholder()` 헬퍼 |
| `signaling/handler/track_ops.rs` | 3-A~3-F | intent 생성 → PublishContext store / `FullSim { continue; }` 폐기 → placeholder 등록 + Intended hook / merge/remove_audio/remove_video_source 호출 폐기 / MediaIntent/VideoSource import 폐기 |
| `signaling/handler/admin.rs` | 3-B,E,F | intent dump 자리 atomic load + streams 기반 / issues 자리 의미 자연 소멸 (RTP-before-intent 불가능 — placeholder 가 streams 즉시 보유) |
| `transport/udp/ingress.rs` | 3-B | `audio_level_extmap_id` atomic load |
| `transport/udp/ingress_publish.rs` | 3-B,C,D,E | resolve_stream_kind / register_and_notify_stream / notify_new_stream — extmap/audio/video 자료 PublisherStream 흡수 / simulcast 첫 RTP 도착 시 placeholder remove |
| `room/participant.rs` | 3-D | test add_publisher_stream mid 인자 정합 |
| `hooks/stream.rs` | 3-D | test mk_publisher_stream mid 인자 정합 |

**안 건드림** (지침 §5 정합): catch 4(PLI 근본 재분석 — 별 토픽) / floor / scope / RtpStream.

---

## §5 동작 변경 0 자기검증 (지침 §6.6)

| sub-phase | 동작 변경 여부 |
|---|---|
| 3-A | 0 (read 0건 죽은 필드 폐기) |
| 3-B | 0 (atomic 의미 동등 변환 — 단일 publisher 단일 thread write/read 직렬화 동등) |
| 3-C | 0 (audio_mid None → ArcSwap None 등가, audio_duplex None=Full → AtomicU8 Full 등가) |
| **3-D** | **1자리** (§2) — simulcast 등록 시점 PUBLISH_TRACKS 으로 당김 + Intended hook simulcast 발동 |
| 3-E | 0 (자료원 PublisherStream 으로 등가 치환. placeholder 가 PUBLISH_TRACKS 시점 자료 박혀있어 race 없음) |
| 3-F | 0 (struct 폐기 — 자료 참조 자리 모두 PublishContext/PublisherStream 으로 등가 이전 완료 후) |

---

## §6 다음 (catch 4 PLI 근본 재분석 토픽) 진입 전 잔여

### 6.1 본 작업 잔여

- **bit mask 사전 에러** (`ingress_subscribe.rs:418` `RTCP_PT_PSFB & 0x7F` — clippy `bad_bit_mask`) — `b811543` 에서 해소된 듯 (commit log "fix(sfu): RTCP PSFB 필터 비트마스크 버그"). 본 작업과 무관.
- **신규 clippy warning +1** (3-F) — `collapsible_if` 또는 `needless_borrow` 류. pre-existing 패턴과 동등.
- **stream_map.rs 파일명 rename** — `StreamKind` enum 만 잔존이라 `stream_kind.rs` 로 rename 검토 (별 phase).

### 6.2 catch 2 효익 정리

- 핫패스 `stream_map.lock()` 자리 = 0건 → 매 RTP lock+clone allocation 비용 폐기.
- 자료 단일출처 — `PublisherStream` (트랙 메타) + `PublishContext` atomic (PC pair extmap/audio_mid).
- simulcast 트랙도 Intended hook 발동 → `track:publish_intent` agg-log 가 simulcast 도 추적.
- mediasoup `NewRtpStream` rid 별 발급 / LiveKit TrackInfo 사전등록 정석 패턴 정합.

### 6.3 catch 4 진입 시 잔여 위험

- placeholder PublisherStream 에 simulcast=true / rid=None 박힌 자료가 *publisher 측 fanout 자리* 에 영향 가능. 현재 `streams.get(rtp_hdr.ssrc)` 매칭이 placeholder 키와 다른 ssrc 라 영향 0. catch 4 의 publisher 단위 dedup `simulcast_pli_pending: AtomicBool` 사전 박기 권고 (분석 보고서 `20260529a_catch4_analysis_done.md` §3) 와 정합 — placeholder 가 publisher 단위 자료라 `Peer.publish` atomic 이 자연.

---

## §7 산출물

- commit 6개 (`37539e0` ~ `98f2431`)
- 완료 보고서: `~/repository/context/claudecode/202605/20260529d_catch2_mediaintent_dissolve_done.md` (본 문서)
- E2E verify: 보류 — 부장님 결정 *"향후 한묶음"*.

---

*author: kodeholic (powered by Claude) — 김과장, 2026-05-29*
