// author: kodeholic (powered by Claude)
# Track State 통일 + 식별 계층(track_id / vssrc) 재설계

- 문서 ID: `20260531_track_state_unification`
- 개정: **rev.3 (2026-06-03)** — **0602e 코드 기준 전면 재정초**. rev.2.1(0531 기준)이 ① `room/`→`domain/` 디렉토리 재편 ② enum `domain/types.rs` 이동 ③ stats 트랙 직속(0602b~c) ④ **fan-out 방향 역전(0528~0601)** 을 미반영 → 재작성. 설계 사상(track_id 불투명 / vssrc·track_id 논리 Stream 이주 / self-unicast 제거)은 유지, 코드 전제만 0602e로 교체.
- 작성: 김대리 (claude.ai) / 구현: 김과장 (Claude Code)
- 성격: **설계서** (확정 — 서버 구현 착수)
- 범위: 서버 `oxsfud` + 클라 `oxlens-home` Core SDK v2. Android·simulcast duplex 전환 1차 밖(§11).

---

## §0 핵심 원칙 — 식별 3평면 분리 (0602e 방향 역전 반영)

> **세 평면을 가른다.** track_id 에서 ssrc 파싱·재조합은 **반칙**(캡슐화). 라우팅은 0528 방향 역전으로 **`PublisherTrack.subscribers`(Weak Vec) 직접 순회** — vssrc 역탐색(`find_subscriber_stream_by_vssrc`) 폐기됨. vssrc 는 "키"가 아니라 "값"이다.

| 평면 | 식별자 | 소유 | 쓰임 |
|---|---|---|---|
| **시그널링(지목)** | **track_id** (불투명) | 논리 `PublisherStream` | MUTE_UPDATE·TRACK_STATE_REQ(발신), TRACK_STATE·TRACKS_UPDATE(통지). **키 조회, 파싱 금지** |
| **egress SSRC(값)** | **vssrc** | 논리 `PublisherStream` | subscriber 가 받는 단일 SSRC 의 **publisher측 원천**. subscribe 등록(cold-path)에서 `SubscriberStream.virtual_ssrc` 로 **복사**됨. hot-path rewrite 는 그 복사본 사용 — **라우팅 키 아님** |
| **ingress(식별)** | 실 ssrc | 물리 `PublisherTrack` | publisher RTP 수신 매칭, NACK/RTX. `PublisherTrackIndex.by_ssrc` |

### 식별 계층 표 (0602e 실제 구조)

| 계층 | 신규/이주 | 기존 직속 (0602e) |
|---|---|---|
| 논리 `PublisherStream` | **+ track_id: Arc<str>** (불투명), **+ vssrc: AtomicU32** (simulcast egress 원천) | `pli_state`/`pli_burst_handle`/`last_pli_relay_ms`/`simulcast_pli_pending`, `tracks: ArcSwap<Vec<PublisherTrack>>` |
| 물리 `PublisherTrack` | **− track_id 제거**, **− virtual_ssrc 제거** | 실 `ssrc`, `rr_stats`, `pub_pipeline_stats`, `rtp_cache`, `nack_generator`, `subscribers`(방향역전 Weak Vec), `duplex/muted/rid` atomic |

- **track_id 생성 규칙 = `{user}_{대표 ssrc}`** — non-sim/PTT=원본ssrc, simulcast=vssrc. **PTT 는 원본ssrc 기반**(egress=방 slot 은 대표 아님). **`attach_track_to_stream` 의 `PublisherStream::new` 에서 1회 발급**, 이후 불투명.
- **vssrc 발급** — 논리 Stream 생성 시 simulcast 면 `rand_u32_nonzero()` eager. non-sim/PTT 는 0(원본 ssrc 가 egress).
- **조회는 키로** — `Peer::find_stream_by_track_id(&str)` / `find_stream_by_vssrc(u32)` (`publish.streams` 선형, publisher 당 2~3 Stream). 역추출 금지.
- **물리 Track 은 track_id 미보유** — 진단/admin 의 track_id 는 `track.stream().map(|s| s.track_id)` 역참조(cold-path).

> **PTT(half) 발신/수신 분리**: publisher 자기 발신 track_id = `{user}_{원본ssrc}`(자기 Stream). subscriber 수신 track_id = `ptt-{room}-{kind}`(방 slot). 발신 핸들러는 `find_stream_by_track_id` 로 publisher Stream 만 해소(slot 은 발신 대상 아님).

---

## §1 배경 — 4축 부정합 (총 21건, 유지)

### 축 1. 식별자 분산 (#1~#5b)
- **#1** send pipe 자기 track_id 미보유 — 발신마다 SDP 재파싱.
- **#2~#3** ssrc 추출 두 갈래(`_parseSsrcPair` vs `getPublishSsrc` 첫 m-line), camera+screen 오지목.
- **#4** 식별 축 불일치(클라 임의/wire ssrc/서버 track_id).
- **#5** `_parseSsrcPair` 실패 → ssrc=0 → 조용한 등록 누락.
- **#5b** simulcast 물리 Track 마다 track_id(h/l/placeholder 3개) — 흩어짐. **클라 1 Pipe(1 trackId) ↔ 서버 다수 = 계층 불일치.**

### 축 2~4 (mute·duplex 발신 분산 / TRACK_STATE 수신 미정합 / dead code)
- #6~#8 mute·duplex 발신 진입 3원화 + duplex API 부재(`TRACK_STATE_REQ 0x1106` 준비됨).
- #9~#12 클라 duplex dead 핸들러 4종.
- #13~#16 SDK `TRACK_STATE` 핸들러 0 / **#14 video-grid `d.muted`만 읽고 `d.active` 무시(버그)** / VIDEO_SUSPENDED 이중 / 개인↔slot 전환 부재.
- #17~#21 floor-fsm pub_set_id dead / dispatch 전환 UI dead / moderate 초기만 / 문서 불일치.

---

## §2 결정 A — 식별 권위 = 논리 `PublisherStream` (클라 Pipe 계층 정합)

### A.0 정합 근거 (1번 정석)
서버 주석: `PublisherStream`=클라 `MediaStream` 정합 / `PublisherTrack`=클라 `MediaStreamTrack` 정합. 클라 식별 단위는 `Endpoint.pipes: Map<trackId, Pipe>` 이고 **simulcast video = 1 Pipe = 1 trackId**(sender 1개, encodings h/l). → track_id 를 논리 Stream 에 두면 `1 Stream = 1 track_id = 클라 1 Pipe` 계층 일치. 물리 Track 에 두면 서버 다수 ↔ 클라 1개 매핑 꼬임(#5b).

### A.1 발신/수신 track_id 비대칭 (정상)
| 트랙 | 발신(publisher) | 수신(subscriber) |
|---|---|---|
| full non-sim | `{user}_{원본ssrc}` | 동일 |
| full simulcast | `{user}_{vssrc}` | 동일 |
| PTT half | `{user}_{원본ssrc}` | `ptt-{room}-{kind}`(방 slot) |

### A.2 자료 귀속 (0602e 코드)
- 논리 `PublisherStream`(`domain/publisher_stream.rs`): **`track_id: Arc<str>` + `vssrc: AtomicU32`** 신설.
- 물리 `PublisherTrack`(`domain/publisher_track.rs`): **`track_id`·`virtual_ssrc` 필드 제거**. 진단은 `stream()` 역참조.
- non-sim/PTT: Stream:Track=1:1, track_id=`{user}_{원본ssrc}`, vssrc=0.
- simulcast: Stream 1:Track(h/l) 2, track_id=`{user}_{vssrc}`, vssrc=eager.

### A.3 발급 자리 = `attach_track_to_stream`
`Peer::register_publisher_track` → `attach_track_to_stream`(peer.rs:720)이 논리 Stream 생성 단일 자리. `PublisherStream::new` 확장:
```
PublisherStream::new(user_id, source, kind, simulcast, first_track_ssrc):
  vssrc    = if simulcast { rand_u32_nonzero() } else { 0 }
  track_id = if simulcast { "{user}_{vssrc:x}" } else { "{user}_{first_track_ssrc:x}" }
```
- simulcast placeholder(sentinel ssrc)로 Stream 생성돼도 track_id=vssrc 기반이라 sentinel 무관. RTP 분화로 물리 Track 교체돼도 **논리 Stream 생존 → vssrc/track_id 보존**.

### A.4 vssrc 평면 (방향 역전 정합 — 중요)
- publisher vssrc 는 **subscribe 등록 시(`collect_subscribe_tracks`, cold-path) 1회** 읽혀 `SubscriberStream.virtual_ssrc` 로 복사.
- egress hot-path rewrite/forward 는 그 복사본(`SubscriberStream.virtual_ssrc`) 사용 — publisher Stream.vssrc 위치는 **hot-path 무관**(이주 비용 0).
- 라우팅은 `PublisherTrack.subscribers`(Weak Vec) 직접 순회 — vssrc 로 라우팅 대상 안 찾음.

### A.5 track_id 불투명 — 키 조회
- `Peer::find_stream_by_track_id(&str)` (`publish.streams` 선형, Stream.track_id 비교).
- 역추출(`rsplit_once`) **금지**. ingress 라우팅(실 ssrc → `find_publisher_track`)은 시그널링 평면과 별개.

### A.6 학습 — transceiver.mid + PUBLISH_TRACKS 응답 단일
- 클라 send pipe mid=null → `transceiver.mid`(PUBLISH_TRACKS `t.mid`)로 매칭.
- non-sim·simulcast·PTT **통일**: `ok` 응답 `d.tracks=[{mid, track_id}]`. vssrc eager 라 simulcast 도 응답 시점 track_id 확정. **self-unicast 폐기**.

---

## §3 결정 B — trackState 단일 게이트 (서버향)

### B.1~B.3 (rev.2.1 유지)
- `pipe.setTrackState({ muted | duplex })` 단일 진입(키=`pipe.trackId`). `endpoint.setTrackState(source,{muted})` 흡수.
- muted → MUTE_UPDATE(0x1103), duplex → TRACK_STATE_REQ(0x1106). 통지 TRACK_STATE(0x2102).

### B.4 서버 적용 단위 = 논리 Stream
- track_id → `find_stream_by_track_id` → 논리 Stream. **mute 는 `stream.tracks` 모든 물리 Track `set_muted`**(simulcast h/l 비대칭 해소 — 0602e `set_track_muted` ssrc 1개를 Stream 단위로 교체).
- duplex 전환도 Stream 단위. simulcast Stream 은 reject(§11).

---

## §4 결정 C — 로컬 속성 분리 (서버 미전송)
송신 bitrate/fps, 수신 볼륨/`element.muted`(스피커), 미리보기 opacity 등 게이트 제외(wire 없음).

---

## §5 결정 D — TRACK_STATE 수신 단일 핸들러 (track_id 키)
```
on TRACK_STATE { track_id, muted?, active? }   // 또는 ROOM_JOIN/SYNC tracks[i] (폴링/재입장)
  pipe = resolveByTrackId(track_id)   // 개인: ep.getPipe(track_id) / slot: engine._pttPipes — 키 조회
  if muted  !== undefined: pipe.muted  = muted
  if active !== undefined: pipe.active = active
  emit('track:state', {...})          // muted/active 둘 다 → #14 차단
```
개인 pipe ↔ slot pipe 전환 토글(#16) = 앱 책임. SDK 는 정제 이벤트 + `showVideo()/hideVideo()`.

---

## §6 결정 E — dead 청산 + 데모 복원
- 클라 dead: #9·#10·#11·#12·#17.
- 데모: dispatch 전환 UI `pipe.setTrackState({duplex})` 복원. moderate 초기 유지.
- 서버: **`switch_track_duplex`(peer.rs:832, 호출처 테스트 3줄 1239~41 뿐 = dead 확정) 정의 + 테스트 청산**.
- 문서: #20·#21 PROJECT_MASTER 정정.

---

## §7 서버 변경 (0602e `domain/` 기준)

1. **논리 Stream 자료 신설** — `domain/publisher_stream.rs`: `track_id: Arc<str>` + `vssrc: AtomicU32` + 발급 로직(`PublisherStream::new` 확장, A.3). `vssrc_load()`/`track_id()` 헬퍼.
2. **물리 Track 자료 제거** — `domain/publisher_track.rs`: `track_id`·`virtual_ssrc` 필드 + `ensure_virtual_ssrc`/`virtual_ssrc_load` 제거. `create_or_update_at_rtp` 의 track_id 생성 라인 제거. `snapshot().track_id` = `stream()` 역참조.
3. **발급 배선** — `domain/peer.rs` `attach_track_to_stream`(720): `PublisherStream::new` 에 simulcast/first_track_ssrc 전달해 vssrc/track_id 발급.
4. **조회 헬퍼** — `domain/peer.rs`: `find_stream_by_track_id(&str)` + `find_stream_by_vssrc(u32)` (`publish.streams` 선형). 역추출 헬퍼 신설 **안 함**.
5. **ensure 전환** — `ensure_simulcast_video_ssrc`/`simulcast_video_ssrc`(peer.rs:910·917)를 Stream.vssrc 참조로. `collect_subscribe_tracks` 가 SubscriberStream.virtual_ssrc 채울 때 Stream.vssrc 읽도록.
6. **발신 핸들러 track_id 수용** — `signaling/message.rs`: `MuteUpdateRequest`/`TrackStateReq` 에 `track_id: Option<String>`(ssrc 하위호환). `signaling/handler/track_ops.rs`: `find_stream_by_track_id` → Stream → mute(Stream 단위 물리 Track 전체) / duplex(Stream 단위). `set_track_muted`(peer.rs:845)를 Stream 단위로 교체.
7. **통지 키 track_id** — `track_ops.rs` `do_track_state_req`/`handle_mute_update` 의 TRACK_STATE body 가 Stream.track_id 동봉.
8. **응답 d.tracks** — `do_publish_tracks` `ok` 응답 `d.tracks=[{mid, track_id}]`(non-sim·simulcast·PTT 통일). self-unicast 없음.
9. **TRACKS_UPDATE 통지 track_id** — `transport/udp/ingress_publish.rs` `notify_new_stream` 의 track_id = Stream.track_id(vssrc 기반). wire `ssrc`(=vssrc) 와 일치.
10. **simulcast duplex reject 가드** — `do_track_state_req` 가 simulcast Stream 이면 reject(§11).
11. **`switch_track_duplex` dead 청산** — 정의(832) + 테스트(1239~41).

---

## §8 단계 (단일 작업 — 쪼개지 않음)

1. **서버 식별 이주** — 논리 Stream track_id/vssrc 신설 + `attach_track_to_stream` 발급 + 물리 Track 필드 제거(snapshot 역참조) + ensure 전환 + 조회 헬퍼. (cargo test + clippy + oxe2e 4/4)
2. **서버 발신/통지/응답** — track_id 수용(Stream 키·Stream 단위 mute/duplex) + 통지 track_id + 응답 d.tracks + simulcast 가드 + switch 청산.
3~6. **클라** — transceiver.mid 학습 / setTrackState 게이트 / TRACK_STATE 수신 / dead·데모·문서. (서버 검증 후 별도 세션)

**본 지침 = 서버 1~2.** **정지점**: Phase 1(식별 이주) 끝 = 위험 phase(물리↔논리 자료 이동, fan-out 방향 역전 구조 + snapshot/admin 광범위 참조). commit + 보고 + GO.

---

## §9 영향 범위 (0602e `domain/`)

- **서버**: `domain/publisher_stream.rs`(track_id+vssrc+발급) · `domain/publisher_track.rs`(track_id/virtual_ssrc 제거, snapshot 역참조) · `domain/peer.rs`(attach_track_to_stream 발급 + find_stream_by_track_id/by_vssrc + ensure 전환 + set_track_muted Stream 단위 + switch 청산) · `signaling/message.rs` · `signaling/handler/track_ops.rs` · `transport/udp/ingress_publish.rs`. admin(`build_*_snapshot`/track dump) track_id = stream() 역참조. `PublisherTrackIndex` 무변경(track_id 인덱스 불요 — Stream 선형).
- **클라**: `core/pipe.js`·`endpoint.js`·`power-manager.js`·`engine.js`·`room.js`·`signaling.js`·`sdp-negotiator.js`. 데모 3.

---

## §10 기각된 접근

- **track_id 역추출(`rsplit_once`)** — 캡슐화 위반(반칙). 키 조회.
- **track_id/vssrc 물리 Track 유지** — 클라 Pipe(논리) ↔ 서버 계층 불일치(#5b). 논리 Stream 이 정석(부장님 1번).
- **vssrc 를 라우팅 키로** — 0528 방향 역전으로 `Track.subscribers` 직접 순회. vssrc 는 값(복사본 hot-path).
- **simulcast self-unicast 통지** — vssrc eager 로 응답 학습. 불요.
- **vssrc 선행 / track_state 후행 분리** — 의존 한 몸. 단일 작업.
- **track_id = egress ssrc 단일 규칙** — PTT egress(방 slot)는 publisher 소유 아님. "publisher 대표 식별 ssrc".
- **track_id→Stream HashMap 인덱스** — publisher 당 2~3 Stream, 선형 충분.
- **(rev.2 폐기) room/ 경로·find_by_vssrc 라우팅·PublisherTrack=실ssrc만** — 0602e 미반영분.

---

## §11 미결 / 확인

- **simulcast duplex 전환**: 1차 밖. Stream 단위 reject 가드(§7-10).
- **PTT 발신/수신 track_id 분리**: 발신=`{user}_{원본ssrc}`(자기 Stream), 수신=`ptt-{room}-{kind}`(방 slot).
- **(구현 시 확인)** `attach_track_to_stream` 가 first_track_ssrc 를 아는 시점인지(track add 후 호출이라 track.ssrc 가용 — peer.rs:946 register 순서 확인).
- **(구현 시 확인)** `collect_subscribe_tracks` 가 publisher Stream.vssrc 를 SubscriberStream.virtual_ssrc 로 복사하는 경로 정합.
- **`sdp-negotiator`** 가 PUBLISH_TRACKS `t.mid` 에 `transceiver.mid` 싣는지.
- **`VIDEO_SUSPENDED/RESUMED` ↔ `TRACK_STATE.muted` 일원화**: 2차.

---

*author: kodeholic (powered by Claude)*
