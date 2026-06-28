<!-- author: kodeholic (powered by Claude) -->

# 20260627f — simulcast layer 적응 복원: subscriber 를 논리 Stream(h/l) 전체에 attach (설계, 검사 대기)

> **목적**: simulcast 발신자의 대역 부족(BWE)으로 **h(high) layer 가 기아**되면 수신자가 **l(low) 로 강등(downscale)** 받아야 하는데, 현재 그 layer switch 가 구조적으로 불가능해 수신 영상이 freeze 한다. 이를 **설계 원의도(0528) 복원**으로 닫는다 — 땜빵 아님.
>
> **한 줄 결론**: forward 의 layer 필터(`is_target_layer && keyframe` switch / `is_current_layer` forward / else drop)는 **한 subscriber 가 h/l 양쪽 패킷을 다 받는 전제**로 완성돼 있다(설계서 0528 "PublisherStream.subscribers ─► {High}/{Low}"). 그런데 구현은 subscriber 를 **h 물리 트랙에만** attach 한다(`collect`/`notify` 가 l skip) → l 패킷이 forward 에 영영 도달 못 함 → switch 死. 정석 = **subscriber 를 논리 Stream 의 모든 물리 트랙(h/l)에 attach**(통지 vssrc 1개·forward·2계층 전부 불변). forward 가 가정한 전제를 attach 에서 충족하는 것.
>
> **성격**: 설계. "코딩해" 전. 제 promote 정합 작업(20260627e)과 **별개 축**(그건 track_id 정합 / 이건 layer 적응).
> **근거 우선**: 본 문서는 직관이 아니라 **설계서 0528 원문 + 현 forward 코드 + pcap/RR 실측**에 근거.

---

## 1. 실측 (이 결함이 실재함 — 삼중 교차, 20260627)

라이브 2인(U01 sub ← U02 pub simulcast, U02 `availOut=192k qL=bandwidth`):

| 출처 | 사실 |
|---|---|
| pcap | `in h(0x2772DDB2)=142` / `in l(0xBA979959)=6179` / `eg vssrc=142` — h 기아, 서버는 받은 h 100% forward |
| RR(U01→서버) | h `ext_seq` 정지 + `cum_lost=0` — forward 누락 아님, **h 자체가 정지** |
| oxadmin U01 | sub video `RECEIVED +0 STALL, freeze=14` — h 기아로 영상 정지 |

→ 서버 forward·promote(20260627e) **무죄**. 문제는 **h 기아 시 l 로 못 내려감**.

---

## 2. 근거 — 설계 원의도 vs 구현 갭 (역사)

### 2.1 설계 원의도 (`architecture/20260528_fanout_direction_redesign.md` 7장)
```
Simulcast
  PublisherStream.subscribers ─► SubscriberStream{forwarder=Some(High)}
                              ─► SubscriberStream{forwarder=Some(Low)}
```
**논리 `PublisherStream`(h/l 묶음)이 subscribers 보유 → 한 subscriber 가 stream 전체에 연결 → layer 는 `forwarder` 가 선택.** forward 가 `Forward / Drop / DropAndRequestKeyframe(layer)` 로 layer 를 고른다(설계서 §6.2).

### 2.2 현 forward 코드는 이 전제로 완성 (`subscriber_stream.rs:483-531`)
```rust
let sender_layer = ctx.publisher.rid;            // 이 패킷의 물리 트랙 layer
if is_target_layer && ctx.is_keyframe { switch } // 분기2: target layer keyframe 도착 시 전환
else if is_current_layer { forward }             // 분기3: 현재 layer 통과
else { forward_drop_layer }                       // 분기4: 그 외 layer drop
```
분기2(switch)·분기4(drop)는 **subscriber 가 h/l 양쪽 패킷을 받아야** 의미가 있다. 한 layer 만 받으면 분기4 는 죽고 분기2 는 영영 false.

### 2.3 갭 — 구현이 subscribers 를 물리 Track 으로 내림 (0530~0603)
`PROJECT_SERVER:174` "물리 Track 이 다운스트림 직접 보유"(`PublisherTrack.subscribers`). 방향역전 완성 과정에서 subscribers 가 **논리 Stream → 물리 Track** 으로 내려갔다. 그 결과 attach 경로가:
- `collect_subscribe_tracks`(`helpers.rs:253,305`): `simulcast && rid=="l"` → **continue**(attach·통지 둘 다 skip)
- `notify_new_stream`: `rid=="l"` → mark_notified + return(attach skip)

→ subscriber 는 **h 물리 트랙에만** attach. l 트랙 `subscribers` 는 영영 빔. broadcast 는 물리 트랙 단위(`broadcast(self.subscribers)`)라 **l fanout 이 그 subscriber.forward 를 호출조차 안 함** → 분기2(switch) 死 → layer 적응 불가.

**핵심**: l-skip 의 본래 목적은 "TRACKS_UPDATE 통지를 h(vssrc 1개)만" 이었는데, **attach 까지 함께 skip** 한 것이 갭. 통지 skip 은 옳고, attach skip 이 틀렸다.

---

## 3. 정석 설계 (기존 구조 보존)

물리 `PublisherTrack.subscribers`(방향역전)·2계층·vssrc 1개 통지를 **전부 유지**하고, 설계 원의도("stream 전체 연결")를 물리로 실현:

> **subscriber(SubscriberStream 1개)를 그 논리 `PublisherStream` 의 모든 물리 Track(h·l)의 `subscribers` 에 등록한다.** 통지(TRACKS_UPDATE)는 h 대표 1개(vssrc) 그대로. forward 는 무변경.

이러면 l 패킷도 subscriber.forward 에 도달 → 분기2(`is_target_layer(l) && keyframe`) 작동 → h 기아 시 l 강등 복원. forward 가 이미 가정한 전제를 attach 에서 충족할 뿐 — 새 메커니즘 0.

### 3.1 변경 지점 (2곳, attach 범위만)
- **`collect_subscribe_tracks`** (나중 join 경로): simulcast 트랙 attach 시 h 만이 아니라 **논리 Stream 의 h/l 물리 Track 전부**에 `attach_subscriber`. **통지(tracks.push)는 h 대표 1개 유지**(현 `rid=="l" continue` 의 통지 부분 보존).
- **`notify_new_stream`** (동시/먼저-publish 경로): l rid 도착 시 통지는 skip 유지하되, **그 subscriber 들을 l 물리 트랙에도 attach**. (현재 l 은 mark_notified+return 으로 attach 도 빠짐.)

### 3.2 ★ 구현 주의 — attach 키 충돌 (곰곰히)
`collect` 의 `attach_targets: HashMap<track_id, ...>` 는 **track_id 키**인데, simulcast h/l 물리 트랙은 **같은 논리 track_id(=user_{vssrc})를 공유**한다 → HashMap 키 충돌로 h/l 중 하나만 남는다. 따라서 "l continue 제거"만으로는 부족하다. **attach 는 track_id 키가 아니라 물리 Track 단위로** 해야 한다 — 등록된 SubscriberStream 을 `stream.tracks_load()` 순회하며 각 물리 Track 에 `attach_subscriber`. (통지/식별은 track_id·vssrc 단위 유지, attach 만 물리 단위.)

---

## 4. 원자 사실 5검증 ([[feedback_atomic_truth_design]])

1. **forward 가 양쪽 수신 전제인가?** 분기4 `forward_drop_layer`(타 layer drop) + 분기2(target keyframe switch) = 한 subscriber 가 h/l 다 받고 필터하는 전제. 코드 실측. ✓
2. **양쪽 attach 시 중복 송출 안 하나?** forward 분기3 은 `is_current_layer` 만 통과, 그 외 drop. current=h 면 h 통과/l drop. 한 layer 만 egress(vssrc). ✓
3. **switch 가 실제 발동하나?** l 트랙 attach → l fanout 이 subscriber.forward 호출 → `is_target_layer(l)&&keyframe` → 분기2 switch. l keyframe 은 PLI(분기2 직전 mark_pli_sent / SUBSCRIBE_LAYER need_pli)로 유도. ✓
4. **통지 1개(vssrc) 불변?** tracks.push 는 h 대표만 — subscriber egress_ssrc=vssrc 1개. 물리 attach 가 늘어도 클라가 보는 m-line 1개. ✓
5. **키 충돌 회피?** §3.2 — attach 를 물리 Track 단위(stream.tracks 순회)로, track_id HashMap 키 의존 안 함. ✓

---

## 5. 영향 범위

**변경: attach 범위 2곳** (`collect_subscribe_tracks`, `notify_new_stream`) — simulcast subscriber 를 h/l 물리 트랙 전부에 attach.

**불변(안 건드림):**
- forward(`subscriber_stream.rs` layer 필터) — 이미 완성
- TRACKS_UPDATE 통지(h 대표 vssrc 1개)
- 물리 `PublisherTrack.subscribers` 방향역전 구조 / 2계층 / promote(20260627e)
- non-sim/PTT 경로(simulcast 분기 밖)

**회귀 안전:** non-sim 은 물리 트랙 1개라 변경 무영향. h 충분(BWE 여유) 시 기존과 동일(current=h forward). 변화는 **h 기아 시 l 강등이 살아나는 것**뿐.

---

## 6. 검증 계획 — 왜 oxe2e 가 못 잡았나 + 잡으려면

### 6.1 2층(oxe2epy)이 이 결함을 못 잡은 이유 (3겹)
1. **봇 canned RTP = BWE 제약 없음** → 봇은 h/l 둘 다 꾸준히 송신 → **h 기아 상황 자체가 안 생김** → l 강등 필요 없음 → 결함 미발현.
2. **봇이 `SUBSCRIBE_LAYER h↔l` 미송신** = `GAP-layer-switch`(known_gap 명시) — layer 전환 경로 자체가 미검증.
3. **봇=Fake RTP** → 실제 freeze/디코딩 안 봄([[feedback_layer2_pass_not_final]]).
→ 공리적 한계가 아니라 **시나리오+등식 부재**. `conf_simulcast` 는 "h 정상→h 수신"만 본다.

### 6.2 2층이 잡으려면 (oxe2epy 보강 — 부장님 e2e 영역)
- **시나리오**: 봇 pub 이 **h layer 송신을 도중 중단**(또는 처음부터 l 만) + sub 봇이 **`SUBSCRIBE_LAYER l` 송신**.
- **등식**: "h 기아 후 sub 가 **vssrc 로 l 패킷을 계속 수신**(수신 +0 아님)" = layer 강등 성립. (현 leak_zero/count 에 `simulcast_downscale` 등식 추가.)
- 이게 있으면 attach 반쪽(현 HEAD) 에서 **FAIL**, 본 설계 적용 후 **PASS** — failability 게이트.

### 6.3 3층(최종)
브라우저 실영상 — U02 대역 제한 상태에서 U01 이 **l 화질이라도 끊김 없이** 보이는지. 미디어 변경 완료는 여기까지([[feedback_layer2_pass_not_final]]).

---

## 7. 리스크 / 검사 포인트

1. **l keyframe 유도**: switch(분기2)는 l keyframe 필요. l 트랙 attach 후 PLI 가 l 로 가는지(SUBSCRIBE_LAYER need_pli 경로가 h ssrc 로 PLI 보냄 — l keyframe 유도 정합 확인 필요).
2. **detach 정합**: leave/take-over 시 subscriber 를 h/l 양쪽 트랙에서 detach 해야(현 detach_subscriber 는 subscriber_id 필터라 양쪽 자동 — 확인).
3. **h 회복(l→h upscale)**: BWE 회복 시 h 로 복귀도 같은 메커니즘(target=h)으로 작동하는지 — 대칭 확인.
4. **성능**: subscriber 가 l fanout 도 받아 drop(분기4) — 패킷당 forward 호출+drop 비용. simulcast 본질(서버가 전 layer 받고 선택)이라 허용 범위. 측정으로 확인.
