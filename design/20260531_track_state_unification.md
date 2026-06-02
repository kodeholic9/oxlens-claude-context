// author: kodeholic (powered by Claude)
# Track State 통일 + 식별 계층(track_id / vssrc) 재설계

- 문서 ID: `20260531_track_state_unification`
- 개정: **rev.2.1 (2026-05-31)** — 부장님 검토 확정. rev.2(track_id 불투명 + vssrc 논리 이주) + 보완 3건(PTT 규칙 정정 / 물리 track_id 는 제거가 아닌 Stream 역참조 / PTT 발신·수신 분리).
- 작성: 김대리 (claude.ai) — author: kodeholic (powered by Claude)
- 성격: **설계서** (확정 — 김과장 서버 구현 착수)
- 선행: 서버 Phase 116 Duplex Activeness(`TRACK_STATE_REQ 0x1106`), Publisher 2계층(`PublishContext ⊃ PublisherStream(논리) ⊃ PublisherTrack(물리)`), 클라 Core SDK v2.
- 범위: 서버 `oxsfud` + 클라 `oxlens-home` Core SDK v2. Android SDK·simulcast duplex 전환은 1차 밖(§11).

---

## §0 핵심 원칙 — 식별 3계층 분리, track_id 는 불투명

> **세 평면을 가른다.** ① 시그널링 지목 = `track_id`(불투명) ② egress 라우팅 = `vssrc` ③ ingress 식별 = 실 `ssrc`. 각 식별자는 자기 계층에만 산다. **track_id 에서 ssrc 를 파싱하거나 `{user}_{ssrc}` 로 재조합해 트랙을 찾는 코드는 반칙** — 생성 규칙에 결합되어 형식을 못 바꾸고 캡슐화가 깨진다.

| 평면 | 식별자 | 소유 계층 | 쓰임 |
|---|---|---|---|
| **시그널링(지목)** | **track_id** (불투명) | 논리 `PublisherStream` | MUTE_UPDATE·TRACK_STATE_REQ(발신), TRACK_STATE·TRACKS_UPDATE(통지). **키로 조회, 파싱 금지** |
| egress(라우팅) | vssrc | 논리 `PublisherStream` | subscriber 가 받는 단일 ssrc (simulcast h/l 단일화) |
| ingress(식별) | 실 ssrc | 물리 `PublisherTrack` | publisher RTP 수신 매칭, NACK/RTX |

### 식별 계층 표 (핵심)

| 계층 | 보관 | non-sim | simulcast |
|---|---|---|---|
| 논리 `PublisherStream` | **track_id** | `{user}_{원본ssrc}` | `{user}_{vssrc}` |
| 논리 `PublisherStream` | **vssrc** | 불필요 | 서버 발급 1개 |
| 물리 `PublisherTrack` | **실 ssrc** | 1개 | h, l (2개) |

- **track_id 생성 규칙 = `{user}_{publisher 대표 식별 ssrc}`** — non-sim 은 대표=원본ssrc, simulcast 는 대표=vssrc(서버 발급). **PTT(half) 는 egress 가 방 공유 slot 이라 대표 ssrc 가 아님 → 원본ssrc 기반**(`{user}_{원본ssrc}`). **논리 Stream 생성 시 1회 발급**, 이후 불투명 식별자.
- **조회는 키로** — `find_stream_by_track_id(track_id)` / `find_stream_by_vssrc(vssrc)`. 역추출(`rsplit_once`) 전면 폐기(rev.1 반칙 정정).
- **물리 Track 은 track_id 필드 미보유** — ingress 식별 = 실 ssrc. 진단/admin/agg-log 의 track_id 표기는 `track.stream().track_id`(기존 Weak 역참조) 로 우회(cold-path, 연쇄 붕괴 아닌 참조 1단계).

> **PTT(half) 예외**: egress=방 공유 slot(`ptt-{room}-{kind}`, 방 소유)이라 publisher 대표 ssrc 가 아님. PTT 의 publisher 자기 트랙 식별(발신 track_id) = `{user}_{원본ssrc}`(non-sim 과 동형). **수신(subscriber) track_id 는 방 slot(`ptt-{room}-{kind}`)** — 같은 트랙의 발신/수신 track_id 가 평면별로 다름(§A.0 정합).

---

## §1 배경 — 4축 부정합 (총 21건, rev.1 유지)

### 축 1. 식별자/SSRC 분산 (#1~#5b)
- **#1** send pipe 가 자기 track_id 권위값 미보유 — 발신마다 SDP 재파싱.
- **#2** ssrc 추출 두 갈래: publish `_parseSsrcPair` vs mute `getPublishSsrc`(첫 m-line).
- **#3** `getPublishSsrc(kind)` 가 camera+screen 공존 시 첫 `m=video` 만 잡음 → 오지목.
- **#4** 식별 축 불일치: 클라 임의 track_id / wire ssrc / 서버 track_id.
- **#5** `_parseSsrcPair` 실패 → ssrc=0 → 서버 조용한 등록 누락.
- **#5b** simulcast 가 물리 Track 마다 track_id(h/l/placeholder 3개) — 시그널링 권위 흩어짐.

### 축 2. mute·duplex 발신 분산 (#6~#12)
- **#6** `_notifyMuteServer` `endpoint.js`+`power-manager.js` 중복.
- **#7** mute 발신 진입점 3원화, 전부 `getPublishSsrc` 우회.
- **#8** duplex 발신 API 부재(op=52 폐기 후). `TRACK_STATE_REQ 0x1106` 준비됨.
- **#9~#12** `_onTracksUpdate`·`applyTracksUpdate`·`applyDuplexSwitch`·`duplex:changed` emit — 전부 dead.

### 축 3. TRACK_STATE 수신 미정합 (#13~#16)
- **#13** SDK 에 `TRACK_STATE(0x2102)` 핸들러 0.
- **#14** **버그**: `video-grid.js` 가 `d.muted` 만 읽고 `d.active`(duplex) 무시.
- **#15** 비디오 mute 수신이 `VIDEO_SUSPENDED/RESUMED` + `TRACK_STATE.muted` 이중.
- **#16** 개인 grid ↔ PTT 슬롯 전환 부재.

### 축 4. dead code + 발신 UI 부재 (#17~#21)
- **#17** `floor-fsm.js` `pub_set_id` MUTEX 분기 dead 가능성.
- **#18** dispatch 전환 UI 통째 dead.
- **#19** moderate grant 초기 duplex 만.
- **#20** PROJECT_MASTER 데모 설명 ↔ 현 코드(dead) 불일치.
- **#21** simulcast "placeholder 사전등록" 문서 ↔ 실제(RTP-first) 불일치.

---

## §2 결정 A — 식별 권위 = 논리 `PublisherStream`

### A.0 발신/수신 track_id 비대칭 (정상)
SFU 가 두 독립 세션 종단점이라 발신(publisher 자기)·수신(subscriber)의 식별이 갈리는 건 자연 구조다. **둘 다 키는 track_id 로 통일**하되 값은 평면별로 다를 수 있다.

| 트랙 | 발신 track_id(publisher 자기) | 수신 track_id(subscriber) |
|---|---|---|
| full non-sim | `{user}_{원본ssrc}` | 동일 `{user}_{원본ssrc}` |
| full simulcast | `{user}_{vssrc}` | 동일 `{user}_{vssrc}` |
| **PTT half** | `{user}_{원본ssrc}` | **`ptt-{room}-{kind}`**(방 slot) |

### A.1 자료 귀속
- 논리 `PublisherStream` 신설: `track_id: Arc<str>`(불투명) + `vssrc: AtomicU32`(egress, simulcast 만 의미).
- 물리 `PublisherTrack`: `track_id`·`virtual_ssrc` 필드 제거. 실 `ssrc` 만. 진단은 `stream()` 역참조.
- non-sim/PTT: Stream:Track=1:1, track_id=`{user}_{원본ssrc}`, vssrc 미사용.
- simulcast: Stream 1:Track(h/l) 2, track_id=`{user}_{vssrc}`, vssrc=서버 발급.

### A.2 track_id 불투명 — 키 조회 (역추출 폐기)
- `Peer::find_stream_by_track_id(&str) -> Option<Arc<PublisherStream>>` (Stream `track_id` 필드 비교, publisher 당 2~3개라 선형 탐색 충분, 인덱스 불요).
- `rsplit_once('_')` hex 역추출 = **반칙(캡슐화 위반)**. rev.1 정정.
- ingress(RTP 도착)는 실 ssrc 로 물리 Track 조회 — 시그널링 평면과 별개(§0).

### A.3 vssrc eager 할당 (PUBLISH_TRACKS 시점)
- 논리 Stream 생성 시점(`register_publisher_track` → `attach_track_to_stream`, PUBLISH_TRACKS 안)에 확정:
  - simulcast: `vssrc=rand_u32_nonzero()` 즉시. placeholder→실 h/l 분화로 물리 Track 이 교체돼도 **논리 Stream 생존 → vssrc 보존**(rev.1 first-track lazy 끊김 해소).
  - non-sim/PTT: vssrc 미할당, track_id=`{user}_{원본ssrc}`.
- track_id 도 Stream 생성 시 1회 발급.

### A.4 학습 — transceiver.mid 매칭 + PUBLISH_TRACKS 응답 단일 경로
- 클라 send pipe mid=null → `pipe.transceiver.mid`(publish PC m-line mid, PUBLISH_TRACKS `t.mid` 값)로 매칭.
- **non-sim·simulcast·PTT 통일**: vssrc/track_id 가 PUBLISH_TRACKS 시점에 서므로 **`ok` 응답 `d.tracks=[{mid, track_id}]` 로 학습**. rev.1 simulcast self-unicast **폐기**.
```
PUBLISH_TRACKS { tracks:[{kind, mid(=transceiver.mid), ssrc(non-sim/PTT만), source, duplex, simulcast}] }
  → 서버: 논리 Stream 생성 → vssrc(sim)/track_id 확정 → ok d.tracks=[{mid, track_id}]
  → 클라: pipe.transceiver.mid===mid 인 send pipe → pipe.trackId 학습
  → 발신: pipe.trackId → MUTE_UPDATE/TRACK_STATE_REQ → 서버 find_stream_by_track_id (키 조회)
```

### A.5 효과
`getPublishSsrc` 폐기(#1·#2·#3) / 지목 track_id 단일(#4) / placeholder 3-track 해소(#5b) / self-unicast 제거.

---

## §3 결정 B — trackState 단일 게이트 (서버향)

### B.1 가르는 축 = "서버에 전송하느냐"
- **trackState(서버향)**: muted·duplex. `MUTE_UPDATE`/`TRACK_STATE_REQ` 왕복 + 통지.
- **로컬 속성(§4)**: wire 없음.

### B.2 네이밍
```js
pipe.setTrackState({ muted: true })       // → MUTE_UPDATE      (키: pipe.trackId)
pipe.setTrackState({ duplex: 'half' })    // → TRACK_STATE_REQ  (키: pipe.trackId)
endpoint.setTrackState(source, { muted }) // toggleMute/_muteVideo/_notifyMuteServer 흡수
```

### B.3 attribute 스키마
| attribute | 값 | wire op | 지목 키 | 통지 |
|---|---|---|---|---|
| `muted` | bool | MUTE_UPDATE(0x1103) | track_id | TRACK_STATE{track_id,muted}(+ VIDEO_SUSPENDED/RESUMED) |
| `duplex` | "full"\|"half" | TRACK_STATE_REQ(0x1106) | track_id | TRACK_STATE{track_id,active} / 신규 sub TRACKS_UPDATE(add)+floor/PLI |

### B.4 서버 적용 단위 = 논리 Stream (mute 비대칭 해소)
- track_id → `find_stream_by_track_id` → 논리 Stream. **mute 는 Stream 아래 모든 물리 Track 에 적용**(simulcast h/l 둘 다) — rev.1 "h 만 muted" 비대칭 자연 해소.
- duplex 전환도 Stream 단위. simulcast Stream 은 reject(§11).

---

## §4 결정 C — 로컬 속성 분리 (서버 미전송)

송신 bitrate/fps, 수신 볼륨/`element.muted`(스피커 mute, `pipe._muted`), 미리보기 opacity 등은 게이트 제외. pipe.js G1/G2 로컬 경로 유지.

---

## §5 결정 D — TRACK_STATE 수신 단일 핸들러 (track_id 키 조회)

### D.1 SDK 핸들러
- **실시간**: `TRACK_STATE(0x2102)` `{track_id, muted?|active?}`.
- **폴링/재입장**: ROOM_JOIN/SYNC tracks 의 `active`/`duplex`.
```
on TRACK_STATE { track_id, muted?, active? }
  pipe = resolveByTrackId(track_id)   // 개인: ep.getPipe(track_id) / slot: engine._pttPipes — 키 조회(파싱 0)
  if muted  !== undefined: pipe.muted  = muted
  if active !== undefined: pipe.active = active
  emit('track:state', {...})
```
- muted/active 둘 다 반영 → #14 차단.

### D.2 앱 레이어 경계
개인 pipe(`remoteEndpoints[uid].pipes[track_id]`) ↔ slot pipe(`engine._pttPipes[roomId]`). #16 전환 토글 = 앱 책임. SDK 는 정제 `track:state` + `showVideo()/hideVideo()`.

---

## §6 결정 E — dead 청산 + 데모 복원

- 클라 dead: #9·#10·#11·#12·#17 제거/재배선.
- 데모: dispatch 전환 UI `pipe.setTrackState({duplex})` 복원(#18). moderate 1차 유지(#19).
- 서버: `switch_track_duplex`(peer.rs:895, 호출 0 = dead 확정) 정의 + 단위 테스트(1262~64) 청산.
- 문서: #20·#21 PROJECT_MASTER 정정 블록.

---

## §7 서버 변경 (식별 계층 재설계)

1. **vssrc·track_id 물리 → 논리 이주**: `PublisherStream` 에 `track_id: Arc<str>`(불투명) + `vssrc: AtomicU32` 신설. `PublisherTrack.virtual_ssrc` 논리 이주(물리 제거). **`PublisherTrack.track_id` 필드 제거하되 진단/admin/agg-log 의 track_id 참조는 `track.stream().track_id`(기존 Weak 역참조) 로 우회** — 연쇄 붕괴 아닌 참조 1단계(cold-path). `ensure_simulcast_video_ssrc`(peer)/`first_track_of_kind().ensure_virtual_ssrc` 호출처를 Stream.vssrc 로 전환.
2. **vssrc eager 할당**: 논리 Stream 생성 시 simulcast 면 `rand_u32_nonzero()` 즉시(A.3). track_id 동시 발급.
3. **키 조회 헬퍼**: `Peer::find_stream_by_track_id(&str)` + `find_stream_by_vssrc(u32)` 신설(선형). 역추출 헬퍼 신설 **안 함**.
4. **발신 핸들러 track_id 수용**: `MuteUpdateRequest`/`TrackStateReq` 에 `track_id: Option<String>` 추가(하위호환 ssrc 보존). 핸들러가 `find_stream_by_track_id` → 논리 Stream → mute(Stream 단위 물리 Track 전체) / duplex(Stream 단위).
5. **통지 키 track_id**: `do_track_state_req`/`handle_mute_update` 의 `TRACK_STATE` body 가 Stream.track_id 동봉.
6. **PUBLISH_TRACKS 응답 `d.tracks=[{mid, track_id}]`**: non-sim·simulcast·PTT **통일**. self-unicast 없음.
7. **TRACKS_UPDATE 통지 track_id**: `notify_new_stream` 의 track_id = Stream.track_id(vssrc 기반). wire `ssrc`(=vssrc) 와 track_id 안 ssrc 일치.
8. **simulcast duplex reject 가드**: `do_track_state_req` 가 simulcast Stream 이면 reject(§11).
9. **`switch_track_duplex` dead 청산**(§6).

> 변경: `room/publisher_stream.rs`(track_id+vssrc) · `room/publisher_track.rs`(track_id/virtual_ssrc 제거) · `room/peer.rs`(조회 헬퍼 + ensure 전환 + switch 청산) · `signaling/message.rs`(track_id 필드) · `signaling/handler/track_ops.rs`(응답 tracks + 발신 키 + 통지 + 가드) · `transport/udp/ingress_publish.rs`(notify track_id=vssrc). admin: track_id 출처 = Stream 역참조.

---

## §8 단계 (단일 작업 — 쪼개지 않음)

> rev.1 의 "vssrc 선행 / track_state 후행" 분리 폐기. vssrc 이주가 track_id 근거라 한 몸 — 중간 모순 상태(vssrc 옮겼는데 track_id 원본 기반)를 만들지 않는다.

1. **서버 식별 이주**: vssrc·track_id 물리→논리 + eager + 물리 track_id 제거(역참조 우회) + 키 조회 헬퍼. (cargo test + clippy)
2. **서버 발신/통지/응답**: track_id 수용(Stream 키 조회·Stream 단위) + TRACK_STATE 통지 track_id + PUBLISH_TRACKS 응답 d.tracks(통일) + simulcast 가드 + switch 청산.
3. **클라 토대**: send pipe `transceiver.mid` 매칭 학습 + `getPublishSsrc` 폐기.
4. **클라 trackState 게이트**: `pipe.setTrackState({muted|duplex})` 단일 진입 + mute 흡수 + 로컬 분리.
5. **클라 수신**: TRACK_STATE 단일 핸들러(track_id 키 해소) + 개인/slot pipe.
6. **dead 청산 + 데모 복원 + 문서 정정**.

**서버(1~2) 가 본 지침 범위. 클라(3~6) 는 서버 검증 후 별도 세션.**
**정지점**: Phase 1(식별 이주) 끝 = 위험 phase(물리↔논리 자료 이동, fan-out/notify/admin 광범위 참조). commit + 보고 + GO.

---

## §9 영향 범위

- **서버**: `room/publisher_stream.rs`(track_id+vssrc+ensure) · `room/publisher_track.rs`(track_id/virtual_ssrc 제거) · `room/peer.rs`(find_stream_by_track_id/by_vssrc + ensure 전환 + switch 청산) · `signaling/message.rs` · `signaling/handler/track_ops.rs` · `transport/udp/ingress_publish.rs`. admin 매트릭스(track_id 출처 Stream 역참조).
- **클라**: `core/pipe.js` · `endpoint.js` · `power-manager.js` · `engine.js` · `room.js` · `signaling.js` · `sdp-negotiator.js`. 데모: `dispatch/app.js` · `moderate/app.js` · `components/video-grid.js`.

---

## §10 기각된 접근

- **track_id 에서 ssrc 역추출(`rsplit_once`)** — 생성 규칙 결합 = 캡슐화 위반(반칙). track_id 키 조회가 정공. rev.1 §7-3/§10 정정.
- **simulcast publisher self-unicast 통지** — vssrc eager 로 PUBLISH_TRACKS 응답 학습 가능 → 불요. rev.1 §7-2 폐기.
- **vssrc 를 물리 Track 에 유지(first-track lazy)** — placeholder→실ssrc 분화 시 끊김. 논리 Stream 소유가 정공.
- **물리 Track 에 track_id 유지** — h/l/placeholder 3개 흩어짐(#5b). 식별 권위는 논리 Stream 1개. (단 admin 참조는 stream() 역참조로 흡수 — "제거"가 아닌 "참조 이전".)
- **vssrc 선행 / track_state 후행 분리** — 의존 한 몸, 중간 모순. 단일 작업.
- **track_id = egress ssrc 단일 규칙** — PTT egress(방 slot)가 publisher 소유 아님. "publisher 대표 식별 ssrc"(sim=vssrc/그외=원본)로 정정.
- **send pipe.mid 학습 키** — null. `transceiver.mid` 사용.
- **track_id→Stream HashMap 인덱스** — publisher 당 2~3 Stream, 선형 충분.

---

## §11 미결 / 확인 필요

- **simulcast duplex 전환**: 1차 밖(FullNonSim↔HalfNonSim, half=sim off). Stream 단위 reject 가드(§7-8).
- **PTT 발신/수신 track_id 분리**: 발신=`{user}_{원본ssrc}`(자기 Stream), 수신=`ptt-{room}-{kind}`(방 slot). 발신 핸들러는 `find_stream_by_track_id` 로 publisher Stream 만 해소(slot 은 발신 대상 아님).
- **(구현 시 1줄 확인)** `sdp-negotiator` 가 PUBLISH_TRACKS `t.mid` 에 `transceiver.mid` 를 싣는지.
- **admin 트랙 표기**: track_id(Stream 역참조) + 물리 ssrc 병기 — Track Dump 매트릭스 row 키 정합 확인.
- **`VIDEO_SUSPENDED/RESUMED` ↔ `TRACK_STATE.muted` 일원화**: 2차(#15).

---

*author: kodeholic (powered by Claude)*
