<!-- author: kodeholic (powered by Claude) -->

# 20260627e — simulcast 정합: promote 시 vssrc/track_id 승계 (설계, 검사 대기)

> **목적**: simulcast 발행에서 PUBLISH_TRACKS 응답으로 회신한 `track_id`(=placeholder vssrc 기반)가 첫 RTP promote 후 **stale 되는 정합 결함**을 닫는다. placeholder 메커니즘(0626d 가드 `!FullSim` + 봇 ssrc=0)은 **보존**하고, promote만 identity 를 승계하도록 고친다.
>
> **한 줄 결론**: 현재 promote 는 placeholder 물리 트랙을 **먼저 remove**(→빈 논리 Stream 폐기→vssrc 증발) → 실 ssrc 트랙을 **나중에 create**(→새 Stream→새 vssrc). 순서를 뒤집어 **실 트랙을 placeholder 의 논리 Stream 에 먼저 합류(vssrc 승계)** → placeholder 물리 트랙만 detach(Stream 은 실 트랙이 남아 유지). vssrc/track_id 가 PUBLISH_TRACKS→promote 내내 불변.
>
> **성격**: 설계. "코딩해" 전. 0625 거대 리팩토링(sentinel 폐기) stash 는 폐기됨 — 본 설계는 placeholder 를 **안 건드리는** 최소 변경.
> **선행/교훈**: [[feedback_layer2_pass_not_final]](2층 PASS≠끝, 3층 실영상 최종), 0625 실패(placeholder=`intent_has_sim` 부트스트랩 — 폐기하면 rid-only 분류 죽어 영상 깨짐).

---

## 0. 현 상태 (정독 실측, HEAD 9059ce6)

### 0.1 이미 된 것 (0626d 묶음 A, 커밋 e142aa1)
- `track_ops.rs:167` 가드 = `if t.ssrc == 0 && track_type != FullSim { continue }`. → web 클라(ssrc=0) simulcast 가 placeholder 경로(`alloc_sim_group` sentinel) 통과. **warn `no track_id` 해소.**
- 봇 simulcast entry `ssrc=0` 정직화. placeholder 메커니즘·`intent_has_sim` 부트스트랩(`ingress_publish.rs:252` 물리 tracks 기반) **그대로 보존**.

### 0.2 남은 결함 — promote 후 identity stale
- PUBLISH_TRACKS: placeholder 논리 Stream `S(vssrc_A)` 생성 → 응답 `track_id = user_{vssrc_A}` 회신 → 클라 `pipe.trackId = vssrc_A` 학습.
- 첫 RTP(promote, `ingress_publish.rs:479-505`): placeholder 물리 트랙 **remove 먼저** → `remove_publisher_track` → `detach_track_from_streams`(`peer.rs:742-758`) → S 의 트랙 0 → **S 폐기(vssrc_A 증발)** → 실 ssrc 트랙 **create 나중** → `attach_track_to_stream` (camera,video) Stream 없음 → **새 Stream S'(vssrc_B)**.
- 결과: subscriber 는 promote **후** notify/collect 로 vssrc_B 구독 → **영상 forward 정상**(보임). 그러나 **publisher 본인 trackId = vssrc_A(stale)**.

### 0.3 증상 (정합 깨짐의 실효)
- **simulcast 카메라 mute 실패**: 클라 `setTrackState({muted})` → `TRACK_STATE_REQ{track_id: vssrc_A}` → 서버 `find_stream_by_track_id(vssrc_A)` → **없음(S 폐기됨)** → mute 무전파. 상대는 계속 영상 수신.
- **race window**: PUBLISH_TRACKS~첫 RTP 사이 join 한 subscriber 는 collect 로 vssrc_A(아직 placeholder S) 구독 → promote 후 vssrc_B → 그 subscriber forward 깨짐. (창 좁음, 드묾)

---

## 1. 근본 (코드 실측)

`detach_track_from_streams` 는 트랙 제거 후 **remaining==0 이면 Stream 폐기**(`peer.rs:750`). promote 가 placeholder 를 **먼저** 제거하므로 그 순간 S 의 트랙은 0 → S 폐기 → vssrc 증발. 이후 create 가 (camera,video) Stream 부재 상태에서 **새 vssrc 발급**. 즉 **promote 가 논리 identity(vssrc/track_id)를 버리고 재발급**하는 게 근본.

---

## 2. 설계 — promote 순서 뒤집기 (identity 승계)

`ingress_publish.rs` register_and_notify_stream 의 simulcast promote 블록:

**현재(증발):**
```
1. placeholder 물리 트랙 remove   // → 빈 S 폐기 → vssrc_A 증발
2. create_or_update_at_rtp(real)  // → 새 S'(vssrc_B)
```

**설계(승계):**
```
1. create_or_update_at_rtp(real)  // → attach_track_to_stream (camera,video) 매칭 → 기존 S 에 합류
                                  //   S = {placeholder, real} (vssrc_A 유지)
2. placeholder 물리 트랙 remove    // → detach: S 에서 placeholder 만 제거, real 남음(remaining=1>0)
                                  //   → S 유지, vssrc_A 보존
```

핵심 = **실 트랙을 먼저 S 에 합류시킨 뒤** placeholder 를 빼면, detach 시 S 에 실 트랙이 남아 폐기되지 않는다. vssrc_A 가 곧 실 Stream 의 vssrc 가 된다(승계).

### 메타 의존성 (순서 뒤집어도 안전)
- 메타(codec/rtx_pt/duplex/source)는 `tracks_for_meta`(placeholder 물리 트랙) 에서 **promote 블록 이전**(`ingress_publish.rs:420`)에 읽는다. placeholder remove 를 create 뒤로 미뤄도 메타 읽기는 그대로 앞이라 무영향.
- rid h/l: h 첫 도착 → create(h) attach S → placeholder remove. l 도착 → placeholder 이미 없음(빈 루프) → create(l) attach S(같은 source). h/l 한 S 공유, vssrc_A. (현행과 동일, 순서만 변경)

---

## 3. 원자 사실 5검증 ([[feedback_atomic_truth_design]])

1. **placeholder Stream 과 실 트랙이 같은 (source,kind)?** placeholder source = intent "camera", 실 트랙 source = ingress 가 메타에서 읽은 placeholder.source = "camera". 동일 → `attach_track_to_stream:724` 매칭. ✓
2. **create 가 attach 시 기존 Stream 재사용?** `attach_track_to_stream` (kind,source) find → 있으면 `add_track`(신규 Stream 생성 안 함). ✓
3. **detach 가 remaining>0 이면 Stream 유지?** `detach_track_from_streams:750` remaining==0 만 폐기. real 남으면 유지. ✓
4. **vssrc 일관?** PUBLISH_TRACKS resp = S.track_id(vssrc_A) / promote 후 S 유지 → 동일 / notify `subscriber_ssrc = simulcast_video_ssrc() = S.vssrc = vssrc_A` / collect 동일. 전부 vssrc_A. ✓
5. **편한 방향(type 불일치·체인) 회피?** ssrc 키는 u32 동일 비교, track_id 는 불투명 키 조회(파싱 없음). placeholder 식별은 기존 `is_placeholder`(sentinel range) 그대로. ✓

---

## 4. 영향 범위

**변경: 단 1곳** — `ingress_publish.rs` simulcast promote 블록의 **두 문장 순서**(placeholder remove ↔ create) 뒤집기. (+ 주석)

**보존(안 건드림):**
- placeholder 생성/sentinel/`alloc_sim_group` (track_ops, 0626d)
- `resolve_stream_kind` `intent_has_sim` rid-only 부트스트랩 (0625 영상버그의 근본 — 절대 보존)
- notify_new_stream / collect_subscribe_tracks / SimulcastRewriter / forward hot-path
- `detach_track_from_streams` remaining 로직 (그대로 활용)

**회귀 안전:**
- non-sim/PTT: promote 블록은 `if track_sim` 안 → 무영향.
- bot(VP8)/web(H264): 순서만 바뀌므로 코덱 무관.

---

## 5. 검증 계획 (2층 PASS ≠ 끝 — [[feedback_layer2_pass_not_final]])

- **2층 (py oxe2e, 1차 게이트)**: `conf_simulcast` — ① 봇 entry **ssrc=0**(web 계약) ② **rid 매 패킷·mid 생략**(rid-only 분류 실증) ③ **순차 join**(collect 경로) ④ **vssrc 로 수신 패킷 수>0**(forward 생존) + leak_zero. **추가 등식: promote 전후 vssrc 불변**(약속 track_id == 최종 vssrc). failability: 순서 안 뒤집은 서버에서 race/mute 케이스 FAIL.
- **3층 (브라우저, 최종 게이트 — 부장님)**: simulcast 영상 표시 + **mute 가 상대에게 실제 반영**(trackId 정합의 실효) + republish/toggle. 미디어 변경의 완료는 여기까지.

---

## 6. 0625 교훈 반영

- 0625 실패 = placeholder(물리, `intent_has_sim`) 폐기 → rid-only 분류 죽어 영상 깨짐. **본 설계는 placeholder 를 일절 안 건드린다.** promote 순서 한 가지만 바꿔 identity 만 승계 → forward 부트스트랩 무손상.
- 2층 PASS 를 "끝"으로 보고하지 않는다. mute 실효는 3층에서만 확정.

---

## 7. 미결 / 검사 포인트

- **Q.** promote 후 vssrc 불변을 2층 등식으로 박을 때, "약속(PUBLISH_TRACKS resp track_id) == 최종(상대가 수신한 vssrc)" 대조가 py verifier identity 5점에 분기로 들어가야 한다 — py 측 반영 필요(부장님 e2e 영역).
- **Q.** race window 를 2층으로 재현할지(순차 join 타이밍을 promote 전에 끼워넣기) — 어렵다면 3층/코드리뷰로 갈음.
