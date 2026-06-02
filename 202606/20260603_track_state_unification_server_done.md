# 완료 보고 — Track State 통일 + 식별 계층 재설계 (서버 Phase A·B)

> 지침: `claudecode/202605/20260531f_track_state_unification_server_p1.md` (rev.3)
> 설계서: `design/20260531_track_state_unification.md` (rev.3)
> 선행: `8b0627a` 직전 = 0602e(Phase 121 scope 래퍼 폐기) 위 적층.
> 상태: **서버 Phase A·B 완료 · 커밋 · 회귀 4/4 PASS. 클라(§8-3~6) 별도 세션.**

---

## 1. commit

| Phase | commit | 내용 |
|---|---|---|
| A (식별 이주) | `8b0627a` | track_id·vssrc → 논리 PublisherStream, 물리 Track 필드 제거 |
| B (발신/통지/응답/가드) | `208a498` | track_id 키 발신 + Stream 단위 mute/duplex + 응답 d.tracks + 통지 track_id |

전 구간 cargo build **0 warning** / cargo test **204** / clippy 신규 0 / oxe2e **4/4 PASS** (conf/ptt/duplex/simulcast).

---

## 2. ★ 정지점 (Phase A 끝)

지침 §3/§6-1 의 단일 정지점. Phase A 커밋(`8b0627a`) + 보고 + 부장님 GO("진행해") 후 Phase B 진입. 위험 phase(물리↔논리 자료 이동 + vssrc 라우팅 함수 + snapshot/admin 광범위 참조) — 회귀로 검증.

---

## 3. 식별 3평면 분리 (달성)

| 평면 | 식별자 | 소유 (이주 후) |
|---|---|---|
| 시그널링(지목) | **track_id**(불투명) | 논리 `PublisherStream` |
| egress SSRC(값) | **vssrc** | 논리 `PublisherStream` (eager, simulcast만) |
| ingress(식별) | 실 ssrc | 물리 `PublisherTrack` |

- track_id 생성 `{user}_{대표 ssrc}` — non-sim/PTT=원본ssrc, simulcast=vssrc. `PublisherStream::new` 1회 발급, 불투명.
- vssrc EAGER (Stream 생성 시 simulcast 면 `rand_u32_nonzero`, non-sim/PTT=0). 구 lazy CAS-on-Track 폐기.
- 조회 = 키: `find_stream_by_track_id` / `find_stream_by_vssrc`. 역추출 금지.

---

## 4. Phase A — 식별 이주 (`8b0627a`)

- **publisher_stream.rs**: `track_id: Arc<str>` + `vssrc: AtomicU32` 신설. `new(.., simulcast, first_track_ssrc)` 확장. `track_id()`/`vssrc_load()`. `rand_u32_nonzero` pub(crate) 재사용.
- **publisher_track.rs**: `track_id`·`virtual_ssrc` 필드 + `ensure_virtual_ssrc`/`virtual_ssrc_load` 제거. `new()` track_id 인자 제거. create_or_update track_id 생성 제거. `snapshot().track_id` = `stream()` 역참조(미배선 ssrc fallback).
- **peer.rs**: `attach_track_to_stream` 가 `PublisherStream::new` 에 simulcast/track.ssrc 전달(발급 단일 자리, §9 register→attach 순서 확인). `find_stream_by_track_id`/`find_stream_by_vssrc` 신설. `simulcast_video_ssrc`/`ensure_simulcast_video_ssrc` → `first_stream_of_kind(Video).vssrc_load()`(eager 흡수). `stream_for_pli_target` → `find_stream_by_vssrc`. `switch_track_duplex` dead 청산(+테스트).
- **room.rs**: `find_publisher_by_vssrc`/`find_publisher_track_by_vssrc` → Stream.vssrc 매칭.
- participant/ingress_rtcp/ingress_publish ensure 호출처 → `peer.ensure_simulcast_video_ssrc`. admin vssrc → stream() 역참조.

§9 확인 완료: register→attach 순서 track.ssrc 가용 ✓ / collect_subscribe_tracks vssrc 정합(ensure 경유 자동) ✓.

---

## 5. Phase B — 발신/통지/응답/가드 (`208a498`)

- **message.rs**: `MuteUpdateRequest`/`TrackStateReq` 에 `#[serde(default)] track_id: Option<String>`.
- **peer.rs**: `set_track_muted`(ssrc 1개) → **`mute_stream(track_id?, ssrc, muted)`** — Stream 의 모든 물리 Track `set_muted`(h/l 비대칭 해소). 반환 `(kind, stream.track_id)`.
- **handle_mute_update**: `mute_stream` 경유 + TRACK_STATE body `track_id` 동봉.
- **do_track_state_req**: track_id→`find_stream_by_track_id`(없으면 ssrc→track→stream) + **simulcast Stream reject**(vssrc!=0, err 3003) + Stream 단위 duplex_store + 통지 body track_id(구 `format!` 역추출 폐기).
- **do_publish_tracks**: `ok` 응답 `d.tracks=[{mid, track_id}]` — req 트랙별 transceiver mid + 등록 Stream.track_id. non-sim·simulcast(vssrc)·PTT 통일. self-unicast 폐기.
- **notify_new_stream**: 통지 track_id = 논리 Stream.track_id(simulcast=vssrc, wire ssrc=vssrc 일치).

---

## 6. 무변경 (설계 §5)

ingress 라우팅(`find_publisher_track`/실 ssrc) · fan-out(`subscribers` Weak Vec 직접 순회 — 방향 역전) · `PublisherTrackIndex`(track_id 인덱스 불요) · `rr_stats`/`pub_pipeline_stats`(트랙 직속). vssrc 는 hot-path 무관(SubscriberStream.virtual_ssrc 복사본 사용).

---

## 7. baseline 변동 — 205 → 204

- Phase A: `peer_switch_duplex_excludes_simulcast_layers` 테스트 폐기(switch_track_duplex dead 청산) = −1.
- `room_member_ensure_simulcast_video_ssrc_delegates_to_peer` 테스트는 **재작성**(vssrc-on-Track lazy CAS → simulcast Stream eager 검증, find_stream_by_vssrc). 수 불변.
- → **이후 단위테스트 baseline = 204.**

---

## 8. 회귀 (oxe2e)

| 시나리오 | Phase A | Phase B |
|---|---|---|
| conf_basic | ✓ | ✓ |
| ptt_rapid | ✓ | ✓ |
| duplex_cache | ✓ | ✓ |
| simulcast_basic | ✓ | ✓ |

서버 재기동 2회(부장님 — Phase A 후 / Phase B 후). 단위 204 + 회귀 4/4 합격.

---

## 8.5 사후 정정 (부장님 적발) — `bf51697`

- **do_track_state_req active 통지 2곳 track_id 누락**: full→half(active:false) / half→full(active:true) TRACK_STATE 통지에 track_id 빠짐. 클라가 track_id 키로 pipe 해소(설계 §5 D.1)하는데 없으면 못 찾음. 키만 추가(ssrc 하위호환 유지).
- **회귀 충실도 한계 노출 → 회귀 강화**(`4efaf4a`): oxe2e 가 통지 JSON 필드(track_id 키)를 미판정해(REGRESSION_GUIDE §4 — 봇은 라우팅/active-flag 만, wire 페이로드 필드 X) 이 누락을 통과시켰다. Phase B 의 "oxe2e 4/4 PASS"는 시그널링 필드 정합을 보증하지 못한 것. **부장님 지시 = 회귀를 강화하라**(건너뛰라 아님 — 김과장 1차 오독):
  - `judge::evaluate_caching` 에 full→half(active:false)·half→full(active:true) 통지 **track_id 동봉 검증** 추가 — 누락 시 FAIL + 사유(§5 D.1).
  - judge 단위 테스트 2종(서버 의존 0): 양성(track_id 있음→PASS) + **음성(없음→FAIL)** — bf51697 회귀를 영구 고정. `cargo test -p oxe2e` 2/2.
  - 교훈: 시그널링 wire 필드는 봇 RTP 판정 밖 → judge 가 통지 페이로드를 직접 단언해야 잡힌다.

---

## 9. 의도된 동작 변경 / 발견_사항

- **simulcast track_id 통일**(#5b): 구 물리 Track 별 `{user}_{h_ssrc}`/`{user}_{l_ssrc}` → 논리 Stream `{user}_{vssrc}` 단일. 클라 1 Pipe(1 trackId) 정합. wire 변경(subscribe track_id·notify·응답) — 클라(oxlens-home/Android) 정합 필요.
- **응답 d.tracks 신설** — 클라 transceiver.mid → track_id 학습용. 현 클라 미소비(클라 작업 별도 세션 §8-3~6).
- **simulcast duplex 전환 reject**(err 3003) — 1차 밖(§11). non-sim/PTT만 duplex 전환.
- 잔여 로그 track_id: `ingress_publish.rs:430` register 로그 문자열은 `{user}_{ssrc}` reconstruction 유지(wire 아님, 진단 로그) — 차후 정리 후보.

---

## 10. 남은 일 (클라 — 별도 세션, §8-3~6)

- `sdp-negotiator`: PUBLISH_TRACKS `t.mid` 에 `transceiver.mid` 적재.
- transceiver.mid + 응답 d.tracks 로 send pipe track_id 학습.
- `pipe.setTrackState({muted|duplex})` 단일 게이트 + TRACK_STATE 수신(track_id 키, muted/active 둘 다 — #14 차단).
- dead 청산(#9~12,17) + 데모 dispatch UI 복원 + 문서(#20·21).

---

*author: kodeholic (powered by Claude)*
