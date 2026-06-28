# 설계서 — PublisherStream 메타 소유권 일원화 + placeholder 폐기 (simulcast 정체성/검은화면 근본 해소)

> author: kodeholic (powered by Claude) / created: 2026-06-28
> 대상: oxlens-sfu-server (oxsfud) / 기준 커밋: **main = ea74985** (4a97825 폐기 후 재출발)
> 검증: 제3자 (사전 지식 0 가정, 구현 가능 수준까지 자기완결)
> 상태: **설계 (미구현)** — 본 문서 승인 전 코드 한 줄도 변경 금지.

---

## §0. 이 문서의 사용법 — 그리고 왜 이렇게 두껍나

직전 시도가 실패한 근본 원인은 **"방향만 잡고 코드로 들어간 것"**이다. 함수 시그니처 before→after, 등록 흐름의 단계별 상태, 깨질 소비처 전수, 밟을 함정을 *미리* 적지 않아 — 구현 중 즉흥 결정(`first_track_ssrc` 누락, `None` drop 처리, 메타 결손 강등, race)을 했고, 회귀가 깨지면 사후 땜빵을 쌓았다.

이 문서는 그 실패의 역상이다. **구현자가 이 문서만 보고 즉흥 결정 0으로 코딩**할 수 있어야 한다. 그래서:
- §3 AS-IS는 *실측 캡처*(추측 아님). §5 TO-BE는 *필드·인자 단위* before→after.
- §6은 sim/non-sim/half **세 경우의 단계별 상태 전이**(어느 시점에 뭐가 생성·확정되는지).
- §9는 **내가 실제로 밟은 함정 5종**을 사전 박제 — 구현자가 같은 데 빠지지 않게.
- §10은 **작은 단위 분할 + 각 단위 검증 게이트**(빌드 에러 폭탄 금지).

**검증자가 답할 질문 3개**(결론 §11 체크리스트):
1. TO-BE 자료구조/흐름이 §1의 두 증상(검은화면·정체성 불일치)을 **구조적으로** 봉쇄하는가?
2. §8 소비처 전수가 빠짐없고, 각 처리가 §5 소유권과 일관되는가?
3. §9 함정 5종이 설계에서 각각 막혀 있는가(사후 패치 아니라 구조로)?

---

## §1. 배경 — 무엇을, 왜 고치나

### 1.1 두 증상

**증상 A — republish 검은화면 (3층 실측, 2026-06-28)**
브라우저가 simulcast publish → 1분 뒤 unpublish → republish 시 영상 0(검은화면). 서버 로그:
```
[STREAM:PROMOTE] placeholder 0xF0000001 -> real 0xF875FB9F rid=l   (정상)
[STREAM:PROMOTE] placeholder 0xF875FB9F -> real 0xF875FB9F rid=l   (★자기 제거)
[STREAM] MID=3 no matching track, ssrc=0xF875FB9F  (이후 매 33ms 무한)
```
real ssrc `0xF875FB9F`의 상위 4비트가 `0xF` → `is_placeholder()`(=`ssrc & 0xF000_0000 == 0xF000_0000`)가 **placeholder로 오판** → 방금 등록한 real Track을 자기 제거. **확률 1/16**(브라우저 랜덤 ssrc). 봇(oxe2epy) ssrc는 고정값이라 2층이 못 잡는 GAP.

**증상 B — simulcast 정체성 불일치 (SRV-0625, 2층 격리 중)**
PUBLISH_TRACKS 응답 track_id(placeholder 발급분)와 TRACKS_UPDATE add track_id(promote 후 재발급분)가 불일치. 클라가 받은 track_id가 죽은 placeholder를 가리켜 setTrackState 불가. 현재 `simulcast_track_id_match` 등식으로 XFAIL 격리 중.

### 1.2 두 증상의 공통 뿌리 — "논리 속성이 물리 계층에 박혀 있다"

OxLens 2계층: **PublisherStream(논리, m-line=camera/screen) ⊃ PublisherTrack(물리, SSRC)**.
그런데 *한 논리 미디어의 협상 속성*(codec/pt/rtx_pt/simulcast/mid/duplex/muted)이 물리 Track마다 흩어져 있다. 그래서:
- simulcast가 SDP에 ssrc가 없는데 "등록하려면 ssrc가 필요" → 가짜 **sentinel ssrc(placeholder)** 발급 → 증상 A(비트 충돌).
- placeholder가 메타 보관처라 promote가 "메타 복사 + 정체성 재발급" → 증상 B(track_id 불일치).

→ **근본 해소 = 메타를 논리 계층(Stream)이 단일 소유. 물리 Track은 ssrc/rid/캐시/통계만.** 그러면 placeholder가 불필요(빈 Stream으로 대체), sentinel 비트 충돌도 정체성 재발급도 원천 소멸.

### 1.3 simulcast / RTP 표준 (사전 지식 0)

- **SSRC**: RTP 물리 스트림 식별자, 매 패킷 존재.
- **MID** (RFC 8843): SDP m-line 식별자. RTP에는 **초기 몇 패킷에만** 실리고 이후 빠짐(transceiver 산물). 한 MID = 한 논리 미디어.
- **RID**: simulcast 레이어("h"/"l") 이름. 한 MID 아래 RID가 레이어 수만큼. **RID는 stream 식별이 아니라 layer 식별.**
- **simulcast**: 한 카메라를 여러 화질 동시 송신. SDP에 ssrc 없이 RID로 구분 → 서버가 **첫 RTP에서 ssrc를 학습**해야 한다.
- **레퍼런스 정석**(§4): mediasoup `RtpListener`는 ssrc 없이 `ridTable[rid]=producer`/`midTable[mid]=producer` 등록 후 첫 RTP에서 `ssrcTable[ssrc]=producer` 학습. sentinel 같은 가짜 ssrc가 없다. LiveKit은 MID를 `transceiver.Mid()`(시그널링)에서 얻고 cid(=SDP msid)로 promote, MID 없으면 보류·재시도.

---

## §2. 범위 — 무엇을 하고 무엇을 안 하나

| 포함 (이번) | 제외 (별도) |
|---|---|
| MID: Track→Stream 이주 | (없음 — MID는 placeholder 매칭 키라 필수) |
| 메타: simulcast/codec/pt/rtx_pt Track→Stream 이주 | duplex/muted Track→Stream (PTT 영향 큼 — §12 후속) |
| placeholder(sentinel) 폐기 → 빈 Stream | audio_duplex 이중 통합 (duplex 이주에 종속 — 후속) |
| 등록/promote 흐름 통일 (sim/non-sim/half) | SUBSCRIBE_LAYER / twcc 등 무관 GAP |
| SRV-0625 해소 + 검은화면 봉쇄 | — |

> **경계 근거**: duplex는 가변(TRACK_STATE 전환)이고 핫패스(`track_type`=derive(duplex,simulcast))이며 audio_duplex 이중까지 얽혀 — 이번 묶음과 분리해야 한 단위가 검증 가능하다. 이번은 **불변 메타(simulcast/codec/pt/rtx_pt) + mid**만. duplex/muted는 다음 설계서.

---

## §3. AS-IS — 현재 구조 정밀 캡처 (main=ea74985, 실측)

### 3.1 자료구조

**PublisherStream** (`domain/publisher_stream.rs`) — 메타 **없음**:
```
user_id, source, kind, track_id, vssrc(AtomicU32), tracks(ArcSwap<Vec<Arc<Track>>>),
pli_state, pli_burst_handle, last_pli_relay_ms, simulcast_pli_pending
```
`new(user_id, source, kind, simulcast, first_track_ssrc)` — simulcast면 vssrc=rand+track_id=vssrc기반, 아니면 vssrc=0+track_id=first_track_ssrc기반.

**PublisherTrack** (`domain/publisher_track.rs`) — 메타 **보유**:
```
ssrc, user_id, kind, source, duplex(AtomicU8), original_duplex,
★simulcast(bool), ★video_codec, clock_rate, ★actual_pt, rtx_ssrc, repair_for, ★actual_rtx_pt,
rid(ArcSwap), ★mid(ArcSwap), muted, rtp_cache, nack_generator, rr_stats, notified,
phase, first_seen, subscribers, stream(Weak<Stream>), pub_pipeline_stats
```
(★ = 이번에 Stream으로 옮길 메타. `mid`도 ★.)

### 3.2 핵심 시그니처

```
PublisherTrack::create_or_update_at_rtp(
    peer, ssrc, kind, rid, video_codec, actual_pt, actual_rtx_pt,
    intent_rtx_ssrc, source, duplex, simulcast, mid
) -> (Arc<Self>, bool)

Peer::add_publisher_track(self, ssrc, kind, rid, video_codec, actual_pt, actual_rtx_pt,
    rtx_ssrc, source, duplex, simulcast, mid)
Peer::register_publisher_track(self, track)           // tracks 색인 + attach_track_to_stream(track)
Peer::attach_track_to_stream(track)                   // (kind,source) 매칭, 없으면 Stream 생성
Peer::alloc_sim_group() -> u32                        // 0xF000_0000 | counter (sentinel)
PublisherTrack::is_placeholder() -> bool              // ssrc & 0xF000_0000 == 0xF000_0000
```

### 3.3 등록/promote 흐름 (AS-IS)

**attach_track_to_stream 본문** (핵심 — Stream이 Track에 종속):
```rust
fn attach_track_to_stream(&self, track) {
    if let Some(s) = streams.find(|s| s.kind==track.kind && s.source==track.source) {
        s.add_track(track); track.set_stream(s); return;   // 기존 Stream 재사용
    }
    let stream = PublisherStream::new(.., track.simulcast, track.ssrc);  // ★Stream을 Track에서 생성
    stream.add_track(track); track.set_stream(&stream); streams.push(stream);
}
```

- **non-sim/half**: PUBLISH_TRACKS → `add_publisher_track`(실 ssrc) → `create_or_update_at_rtp`(2번 분기 신규) → `PublisherTrack::new`(메타) → `register_publisher_track` → `attach_track_to_stream`(Stream 신설, track.ssrc로 track_id 발급). 첫 RTP는 ssrc 매칭(`is_new=false`) → 바로 fanout.
- **sim**: PUBLISH_TRACKS → `alloc_sim_group()` sentinel ssrc로 placeholder Track 등록(메타 보유) → attach로 Stream 신설(랜덤 vssrc track_id). 첫 RTP(rid) → `resolve_stream_kind`가 `intent_has_sim`(placeholder 존재)+rid로 `is_new=true,FullSim` → `register_and_notify_stream`: **placeholder remove → 실 ssrc Track 신규**(또 Stream 신설, 또 랜덤 vssrc) → 정체성 갈림(증상 B) + sentinel 비트 오판(증상 A).

### 3.4 소비처 규모 (실측 grep)
- 메타(simulcast/video_codec/actual_pt/actual_rtx_pt) 직접 접근: **11개 파일** (ingress_publish 18·helpers 10·admin 10·publisher_track 9·subscriber_stream 8·track_ops 5·peer 4·room 1·egress 1·rtcp 1·metrics 1). ※metrics의 `.simulcast`는 METRICS 카운터(무관).
- mid(Track) 접근: **4건**. placeholder/sentinel: **10건**.

---

## §4. 레퍼런스 정석 (mediasoup / LiveKit)

**mediasoup `RtpListener::GetProducer`** (raw C++ SFU — 우리와 동급):
```
1. ssrcTable[ssrc] 히트 → 반환 (학습 후 정상 경로)
2. ssrc 미스 → MID 읽어 midTable → 찾으면 ssrcTable[ssrc]=producer 학습 + 반환
3. MID 없으면 → RID 읽어 ridTable → 학습 + 반환
4. 다 미스 → nullptr (패킷 drop, producer 안 건드림)
```
- producer(=논리 트랙) 정체성은 `produce()`(시그널링) 1회 발급. **GetProducer는 ssrcTable 엔트리만 추가, producer 재생성/제거 없음.**
- RID는 transport 내 유일할 때만 단독 매칭, 충돌 시 MID 필수.

**LiveKit**: MID를 `transceiver.Mid()`(SDP 산물, RTP 아님)에서 얻음. 트랙 안정 ID(cid=msid)는 AddTrack 시 1회. MID 못 얻으면 **보류 후 재시도**(`pendingRemoteTracks`). 추측/랜덤 발급 안 함.

**교훈(공통)**: 발급은 시그널링 1회 → 정체성 불변 → RTP-first는 "찾아서 ssrc 학습"만. 우리도 동형으로 간다.

---

## §5. TO-BE — 메타 = Stream, 물리 = Track (필드·인자 단위)

### 5.1 소유권 (이번 범위)

| 값 | AS-IS 소유 | TO-BE 소유 | 비고 |
|---|---|---|---|
| track_id, vssrc | Stream | Stream | (0603 완료, 유지) |
| **mid** | Track(ArcSwap) | **Stream** (`Option<Arc<str>>`, 불변) | RTP-first 매칭 1차 키 |
| **simulcast** | Track(bool) | **Stream** (bool, 불변) | h/l 묶음 성질 |
| **video_codec** | Track | **Stream** (불변) | m-line 협상 |
| **actual_pt** | Track | **Stream** (불변) | m-line 협상 |
| **actual_rtx_pt** | Track | **Stream** (불변) | m-line 협상 |
| duplex, muted | Track | Track (이번 유지) | 다음 설계서 |
| ssrc, rid, rtx_ssrc, 캐시, 통계, phase | Track | Track | 물리 |

### 5.2 PublisherStream 필드 (추가)
```
+ pub mid:           Option<Arc<str>>   // 불변, register 시 1회
+ pub simulcast:     bool               // 불변
+ pub video_codec:   VideoCodec         // 불변
+ pub actual_pt:     u8                 // 불변
+ pub actual_rtx_pt: u8                 // 불변
+ pub fn mid_load(&self) -> Option<&str>
+ pub fn is_simulcast(&self) -> bool    // = self.simulcast (★vssrc 추론 금지 — §9 함정3)
```

### 5.3 PublisherTrack 필드 (제거)
```
- simulcast, video_codec, actual_pt, actual_rtx_pt, mid   // 5필드 제거
+ pub fn is_simulcast/video_codec/actual_pt/actual_rtx_pt(&self)  // stream() 위임 헬퍼
  // RTX(repair_for=Some)/미배선 Track 은 stream None → default (라우팅 대상 아님, §9 함정4)
```

### 5.4 시그니처 before → after
```
PublisherStream::new(user_id, source, kind, simulcast, first_track_ssrc)
  → new(user_id, source, kind, simulcast, first_track_ssrc, mid, video_codec, actual_pt, actual_rtx_pt)
     // ★first_track_ssrc 유지필수 — non-sim track_id=user_ssrc 기반 (§9 함정1)

+ Peer::register_stream(mid, source, kind, simulcast, first_track_ssrc, video_codec, actual_pt, actual_rtx_pt)
     -> Arc<PublisherStream>   // 멱등((kind,mid)→(kind,source) 폴백). 메타 보유 빈 Stream 등록.
+ Peer::find_stream_for_attach(mid: Option<&str>, source: &str, kind) -> Option<Arc<Stream>>
     // MID(1차) → (kind,source) 폴백. ★Stream 생성 안 함 — 못 찾으면 호출처가 drop (§9 함정2)
+ Peer::register_track_to_stream(track, stream: &Arc<Stream>)
     // tracks 색인 + (repair_for.is_none() 이면) stream.add_track + set_stream

PublisherTrack::create_or_update_at_rtp(peer, ssrc, kind, rid, video_codec, actual_pt,
    actual_rtx_pt, intent_rtx_ssrc, source, duplex, simulcast, mid) -> (Arc, bool)
  → create_or_update_at_rtp(peer, ssrc, kind, rid, intent_rtx_ssrc, source, duplex, mid)
       -> (Option<Arc<Self>>, bool)   // ★메타 인자 제거(물리만). Stream 미확정이면 None (§9 함정2)

Peer::add_publisher_track(.. 메타 12인자 ..)
  → add_publisher_track(self, ssrc, kind, rid, rtx_ssrc, source, duplex, mid)   // 물리만

- Peer::alloc_sim_group / sim_group_counter / PublisherTrack::is_placeholder   // 전부 삭제
- Peer::attach_track_to_stream / register_publisher_track   // find_stream_for_attach + register_track_to_stream 로 대체
```

---

## §6. 등록/promote 통일 흐름 (단계별 상태 전이) — 세 경우

> 통일 원칙: **PUBLISH_TRACKS는 항상 register_stream(메타)로 논리 Stream을 먼저 확정. 물리 Track은 ssrc를 알면(non-sim/half) 즉시, 모르면(sim) 첫 RTP에서.**

### 6.1 sim (FullSim)
```
PUBLISH_TRACKS(t.ssrc=0, t.mid="1", codec, pt, rtx_pt):
  register_stream(mid="1", source="camera", Video, simulcast=true, first_track_ssrc=0, codec, pt, rtx_pt)
    → 빈 Stream 생성: vssrc=rand, track_id=user_vssrc, 메타 보유, tracks=[]
    → resp track_id = Stream.track_id              [상태: Stream O, Track 0]
첫 RTP (rid="h", real ssrc=0xC1):
  resolve_stream_kind: ssrc 미스 + sim Stream 존재(streams.any(is_simulcast)) + rid → (Video, is_new=true, FullSim)
  create_or_update_at_rtp(0xC1, .., mid):
    1. ssrc 미스
    2. find_stream_for_attach(mid="1"/source) → 위 빈 Stream 확정 (없으면 drop)
    3. PublisherTrack::new(0xC1, 물리만) → register_track_to_stream(track, stream)
       → Stream.tracks=[0xC1], track.stream()=Stream    [상태: Stream O, Track 1, 정체성 보존]
  notify_new_stream: track.stream().track_id() = resp와 동일  → add==resp ✓ (증상 B 해소)
둘째 RTP (rid="l", 0xC2): find_stream_for_attach → 같은 Stream 재사용 → add_track  [Stream O, Track 2]
```
**placeholder/sentinel 없음 → 증상 A 원천 소멸. remove 루프 없음 → 자기제거 불가.**

### 6.2 non-sim (FullNonSim)
```
PUBLISH_TRACKS(t.ssrc=0xA1(실값), t.mid="0", codec, pt, rtx_pt):
  register_stream(mid="0", source, Audio/Video, simulcast=false, first_track_ssrc=0xA1, codec, pt, rtx_pt)
    → Stream: vssrc=0, track_id=user_A1(★실 ssrc 기반), 메타 보유, tracks=[]
  add_publisher_track(0xA1, 물리) → create_or_update_at_rtp:
    find_stream_for_attach → 위 Stream → Track(0xA1) attach   [Stream O, Track 1]
  resp track_id = Stream.track_id = user_A1.  early-register add(build_track_add_core)도 user_A1 → 일치
첫 RTP: ssrc 매칭(is_new=false) → 바로 fanout (promote 안 거침)
```

### 6.3 half (HalfNonSim, PTT) — 6.2와 동일, duplex=Half
```
register_stream(.., simulcast=false, first_track_ssrc=t.ssrc, ..) + add_publisher_track(물리, duplex=Half)
  → PTT slot 경로(현행 유지). add 통지 없음(Unified Model). track_id=Stream.track_id(user_ssrc).
```

### 6.4 ingress 메타 흡수 (register_and_notify_stream / notify_new_stream)
- 메타(codec/source/simulcast/rtx_pt) 흡수를 **Stream에서** 읽음(`streams.find(mid/source).is_simulcast()/.video_codec/...`). 빈 Stream도 보유 → promote 강등 없음(§9 함정5).
- placeholder remove 루프 **삭제**.
- intent_has_sim = `streams.any(kind==Video && is_simulcast())` (Track 색인 아님).

---

## §7. 불변식 (깨지면 설계 실패 — 각 증상 동반)

- **I1 — Stream 먼저, Track은 나중**: `create_or_update_at_rtp`은 `find_stream_for_attach`로 Stream을 *먼저 확정*. **없으면 `None`(RTP drop)** — 메타 없는 Track·고아 Track을 만들지 않는다.
  - *깨질 때 증상*: 메타 없는 Track → FullNonSim 강등(simulcast가 non-sim으로) / track_id None.
- **I2 — 메타 단일 출처(Stream)**: PublisherTrack은 메타 필드를 *물리적으로 보유하지 않음*. 소비처는 `stream()` 위임.
  - *깨질 때 증상*: fallback `unwrap_or(self.field)` 같은 땜빵이 가능해짐(이중 진실). → 필드 제거로 *구조적 봉쇄*.
- **I3 — 발급 1회 불변**: track_id/vssrc/mid/메타는 register_stream(PUBLISH) 1회 발급, unpublish까지 불변. promote는 "찾아서 attach"만(재발급 없음).
  - *깨질 때 증상*: 증상 B(resp≠add).
- **I4 — RTX/미배선 Track은 stream None 허용**: RTX(repair_for=Some)는 Stream 무관(메타 default). media Track은 I1으로 항상 stream Some.
- **I5 — sim Stream은 RTP보다 먼저 streams 확정**: register_stream이 PUBLISH 시점 등록 → 첫 RTP의 메타 흡수가 race 없음.
  - *깨질 때 증상*: 동시 publish race로 메타 흡수 미스 → 강등(§9 함정5).

---

## §8. 소비처 전수 + 처리 (구현 시 이 grep으로 재확인)

### 8.1 분류
| 분류 | 처리 | 대표 위치 |
|---|---|---|
| **snapshot 경유** (`PublisherTrackSnapshot.simulcast/video_codec/actual_pt`) | `PublisherTrack::snapshot()`을 Stream 기반(stream() 위임, RTX는 default)으로 1곳 수정 → helpers/room/admin-snapshot 자동 정합 | helpers collect_subscribe, room:331 |
| **직접 Track 접근** (`t.simulcast` 등) | `.is_simulcast()`/`.video_codec()` 헬퍼로 치환 | ingress resolve_stream_kind, egress(PLI skip), ingress_rtcp(SR), admin(stream_map/intent dump), track_ops(SUBSCRIBE_LAYER/TRACKS_READY) |
| **핫패스** (`track_type()`=derive(duplex,simulcast), 매 RTP fanout) | `self.stream().is_simulcast()` 역참조 (duplex는 이번 Track 유지) — fanout 진입 1회 | publisher_track::track_type |
| **메타 흡수 (ingress)** | Stream에서 읽기(§6.4) | register_and_notify_stream, notify_new_stream |
| **req intent** (`req.tracks[].simulcast`) | PublishTracksRequest 필드 — 무관(유지) | track_ops PUBLISH 입구 |
| **metrics** (`m.simulcast.xxx`) | METRICS 카운터 — 무관 | sfu_metrics, subscriber_stream |

### 8.2 합격 grep (구현 후)
```
grep -rn "is_placeholder\|alloc_sim_group\|sim_group\|0xF000" crates/oxsfud/src  → 0건(주석 포함)
grep -n "pub simulcast\|pub video_codec\|pub actual_pt\|pub actual_rtx_pt\|pub mid" \
   crates/oxsfud/src/domain/publisher_track.rs  → 0 (Snapshot 구조체는 값 컨테이너라 별개)
```

---

## §9. ★함정 박제 — 내가 실제로 밟은 것 (사후 패치 아니라 설계로 막는다)

> 직전 시도에서 *구현 중 즉흥으로* 발견·땜빵한 것들. 설계에 못 박아 구현자가 같은 데 빠지지 않게 한다.

| # | 함정 | 증상 | 설계상 차단 |
|---|---|---|---|
| **1** | `register_stream`에 **first_track_ssrc 누락** | non-sim track_id가 `user_0`(0 기반) → resp≠add **대량 회귀** (audio/video 다 깨짐) | §5.4·§6.2: non-sim은 `first_track_ssrc=t.ssrc` **필수 인자**. sim은 0(vssrc 기반 무관). |
| **2** | `create_or_update`이 Stream 없을 때 **메타 없이 Track 생성** | FullNonSim 강등 / 고아 Track 누수 | §7-I1: Stream 미확정이면 **`None`(drop)**. media Track은 PUBLISH register_stream 선행이라 None 불가. |
| **3** | `is_simulcast()`를 **vssrc≠0 추론**으로 구현 | sentinel 비트 추론과 같은 류의 땜빵 | §5.2: `is_simulcast()`=명시 필드 `self.simulcast`. vssrc 추론 금지. |
| **4** | RTX/미배선 Track의 메타 접근 | stream None에서 panic 또는 잘못된 fallback | §7-I4: RTX는 stream None 허용, 헬퍼가 default. media Track은 I1으로 stream Some 보장. |
| **5** | 메타 흡수를 **Track 색인(tracks)** 에서 (빈 Stream엔 Track 0) | 동시 publish race / promote 시 `is_sim_source=false` → **강등** | §6.4·§7-I5: 메타 흡수는 **Stream에서**. register_stream이 RTP보다 먼저 streams 확정 → race 없음. |
| **6**(메타) | 경고 회피용 `let _ = (x, y)` / 죽은 방어 경고 | 죽은 코드 누적 (더 똥) | §10 규칙: 경고 나오면 `let _` 금지 — **계산/변수 자체 제거**. 못 하면 멈추고 설계 재검토. |

---

## §10. 작업 분할 + 검증 게이트 (작은 단위, 빌드 에러 폭탄 금지)

> 각 단계 = (빌드 통과 + 1층 통과) 게이트. 단계 간 부장님 보고/승인 체크포인트. 한 단계가 깨지면 **다음으로 안 넘어가고 설계로 복귀**.

| 단계 | 내용 | 게이트 |
|---|---|---|
| **S1** | PublisherStream에 mid 필드 + new 인자 + mid_load. `register_stream`/`find_stream_for_attach`/`register_track_to_stream` 신설(미사용 OK). attach/register_publisher_track은 *유지*(병행). | 빌드 0경고, 1층 218 |
| **S2** | MID만 Track→Stream: create_or_update/add_publisher_track가 mid를 register 사슬로. ingress mid 매칭/notify track_id를 Stream.mid로. Track.mid 제거. | 빌드, 1층, **2층 회귀 0**(MID 이주는 동작 중립) |
| **S3a** | Stream에 메타 필드(simulcast/codec/pt/rtx_pt) + `register_stream`/`new`/`is_simulcast` 신설. attach가 첫 Track 메타 복사. | 빌드 0경고, 1층 (동작 중립) |
| **S3b** | **소비처 읽기만** Stream화: snapshot Stream 기반, 직접 소비처(egress/rtcp/admin/track_ops) 헬퍼 치환, fanout `track_type` 헬퍼. **메타 흡수·등록 흐름은 안 건드림**(Track 메타 유지). | 빌드, 1층, **2층 회귀 0**(동작 중립 — Stream=Track 값) |
| **S4** | **한 묶음**(I1·I5): 등록 흐름 통일(§6: PUBLISH→register_stream(메타) → non-sim/half add_publisher_track 물리), create_or_update Stream확정/drop·메타 인자 제거, **ingress 메타 흡수 Stream**, placeholder(sentinel) 폐기(FullSim→register_stream 빈 Stream, sentinel/is_placeholder/alloc_sim_group·remove 루프 삭제, intent_has_sim Stream), 빈 Stream 회수, **PublisherTrack 메타 필드 제거 + 헬퍼**. | sentinel grep 0, §8 grep(메타) 0, **conf_simulcast×3 race**, **2층 전체 회귀 0**(non-sim track_id·강등·race), `simulcast_track_id_match` XPASS |
| **S5** | sentinel-대역 republish **2층 시나리오 추가**(봇 ssrc=0xF8…, publish→unpublish→republish). | 현행이면 빨강, S4 후 **PASS** (1/16 GAP 봉쇄 가드) |

각 단계 커밋 분리. **S2(MID)→S3(메타 필드+읽기)→S4(등록흐름+흡수+placeholder+Track필드제거)→S5 순서**.
★경계 근거(직전 실패 교훈): **메타 흡수를 Stream에서 읽는 것은 register_stream 선행(빈 Stream이 RTP보다 먼저 확정)과 *반드시 한 묶음***(I5). placeholder가 살아있는데 흡수만 Stream화하면 attach 지연으로 동시 publish race(=직전 conf_simulcast 깨짐). 그래서 흡수·등록흐름·placeholder폐기·Track메타제거를 **S4 한 단위**로 묶어 atomic하게 전환한다.

---

## §11. 검증 계획 + 체크리스트

### 11.1 등식/시나리오 사전 매핑 (회귀는 예측 확인용 — §0)
| 변경 | 건드리는 등식/시나리오 | 예상 |
|---|---|---|
| MID→Stream(S2) | (없음 — 동작 중립) | 전 시나리오 회귀 0 유지 |
| 메타→Stream(S3) | `identity_5point`(non-sim track_id), conf_video/audio/n3/duplex, ptt | 회귀 0 (강등·track_id 불일치·race 0) |
| placeholder 폐기(S4) | `simulcast_track_id_match`(XPASS), `identity_5point`(conf_simulcast*) | XPASS + 회귀 0, race 0 |
| sentinel 시나리오(S5) | 신규 republish 시나리오 | 현행 빨강 → PASS |

### 11.2 명령
```
1층: cargo test -p oxsfud                           # 기준 218 passed
2층: oxadmin stop/load sfud1·sfud2 → python -m oxe2epy run <scenario>
     (전체: conf_simulcast(×3)·_seq·video·audio·n3·duplex·ptt(·_seam)·crossroom·floor·adv_*)
     conf_audio_fault 는 FAIL 이 정상(failability)
검증기: python -m pytest tests/                     # 78 passed
3층: 부장님 브라우저(이 작업의 최종 게이트 — republish 검은화면 실측)
```

### 11.3 체크리스트
- [ ] §7 불변식 I1~I5 각각 코드에서 성립
- [ ] §9 함정 1~6 각각 설계로 차단(사후 패치 아님)
- [ ] sentinel grep 0, PublisherTrack 메타/mid 필드 0
- [ ] non-sim track_id = user_ssrc (resp==add), conf_simulcast×3 race PASS
- [ ] half/PTT/mute 회귀 0
- [ ] 빈 Stream unpublish 누수 0 (remove_empty_stream_by_source)
- [ ] sentinel-대역 republish 2층 PASS
- [ ] 1층/2층/검증기 전부 녹색, 3층 검은화면 소멸

---

## §12. 미해결 리스크 + 후속

- **R1 (MID 첫 패킷 보장)**: sim 첫 RTP가 rid-only(mid 없음)면 메타 흡수가 source 폴백. 단일 source는 OK, 다중 source(camera+screen 동시 simulcast)만 MID 필요 — SDP 시점 mid는 register_stream이 이미 보유하므로 streams.find(mid)로 해결. 다중 source simulcast 실존 여부 testlogs로 확인.
- **R2 (빈 Stream 누수)**: RTP 미도착 채 unpublish/disconnect 시 빈 Stream 회수 — `remove_empty_stream_by_source(kind, source)` 신설(unpublish video 분기 + disconnect 정리).
- **R3 (핫패스 비용)**: track_type의 stream() 역참조(매 RTP fanout). 진입 1회. 측정 필요(없으면 Track에 simulcast read-only 캐시는 *최후* 수단 — 단일 진실은 Stream).
- **후속 설계서**: duplex/muted Track→Stream + audio_duplex 통합(가변·핫패스·PTT 영향 — 별도 단위).

---

## §13. 롤백 / 체크포인트 원칙

- 각 단계(S1~S5) 커밋 분리. 단계 게이트 실패 시 **즉시 롤백 + 설계 복귀**(즉흥 패치 금지).
- SRV-0625는 현재 좁게 격리(XFAIL)되어 게이트 통과 중 — 무리한 부분 수정으로 빨강 내느니 격리 유지가 낫다.
- 부분 성공(예: 단일 source는 되나 다중 source 미해결) 시 **조용한 skip 금지** — known_defects에 잔여 GAP 명시.

---

> **이력**: 2026-06-28 3층 발굴(republish 검은화면 1/16 sentinel 비트 충돌) + SRV-0625(정체성 불일치) → 근본은 "논리 메타가 물리 Track에 오배치". 정석 = 메타 Stream 단일 소유(mediasoup RtpListener / LiveKit transceiver-MID 동형) + placeholder 폐기. 직전 즉흥 구현 실패(4a97825 폐기)의 함정 5종을 §9에 박제. 기준 main=ea74985.
