---
kind: task
status: open
opened: 20260817
refs: [202608/20260816b_test_axis_split_task.md, guide/MEDIA_DEBUG_GUIDE_FOR_AI.md, qa/README.md, PROJECT_SERVER.md, PROJECT_WEB.md]
---
# 1PC 검은 화면 — H264 profile 불일치가 PT 매핑을 깨뜨린 3세션 미규명 결함

> 집행: 김과장(Claude Code) / 일자: 2026-08-17
> 성격: **sdk0.2 수리 1건 + 서버 관측·가드 2건 + 3층 진단 배선**. 서버 동작 변경은 가드 1건뿐.

---

## 지침 (부장님, 채팅 20260817)

1. *"3층은 부장님 실행분이라 제가 안 돌렸습니다 ← 이 근거는 뭐냐? **너가 돌리는게 룰이다.**"*
2. *"3층 시험 결과 이상없음으로 판정된건지 다시 확인하고. 빈방 회수 로직 살펴 바라."*
3. *"3층 시험 항목 도출된 근거 및 적합성 점검할 꺼임."*
4. *"2층과 3층의 교집합은 존재해도되. 다만 그걸 식별할 수는 있어야지. 시험항목의 원천이
   규격에서 파생된건지 소스로부터 유추된건지 모호하면 안되. **3층은 사람이 눈과 귀로 체감하는
   부분을 대리 검증하는 자리**라는 점."*
5. *"1번은 이미 실패한 모델인데 헷갈리게 왜 또 끄집어 내냐. **시험 자체가 결정적이지 않다.**
   비결정적인 요소는 시험을 굴릴때마다 결과가 달라지고, 이로 인해 작업이 지체된다.
   이 관점에서 현재 시험 항목을 분석해바."*
6. *"3층에서 실패가 나는데 2층이 통과했다면, 2층의 시험 방식이 3층의 무언가를 품지 못하고 있다는
   결론임. 근데 문제는 **3층에서 왜 실패를 하는지 규명이 안된다**는 점. 순환이 안된다는 거지."*
7. *"2pc에서는 문제가 없는데, 1pc에서만 발생되는 현상이야. 서버쪽 확인해.
   **2층이 못 품은거 맞다. 시험 케이스가 부재인거지.**"*
8. *"협상이 필요한 지점에서 협상없이 하드코딩하는 예가 더 있는지 살펴보고, 사이드 이펙없도록,
   유사패턴으로 작업 진행해. **고정 정책은 줄곧 문제가 되었던 건데.**"*
9. *"시뮬캐스트는 협상과정이 아니라 **rtp first 단계에서 학습**하는 특성을 가지고 있어."*
10. *"자가 치유하고 싶지 않은데. **땜방이 무슨 도움이 되겠어**, 장기적으로."*
11. *"클라에게 통보하는 op 가 하나 있고, 그 안에 action 이든 type 이든 구분해야될 것 같지 않니?
    **op만 주구장창 신설할꺼야?**"*

---

## A. 규칙 반전 — 시험은 김과장이 돌린다

구 지시(20260614) *"Claude 라이브 시험 금지, 부장님이 증상 제공 → 분석만"* 을 근거로 3층을
안 돌리고 "부장님 실행 필요"로 보고했다가 지적받았다. **2층·3층 전부 Claude 실행이 룰이다.**
memory `feedback_no_self_testing` 갱신 완료.

단, **3층 실영상 육안 최종 판정은 부장님 몫**이라는 구분은 유효하다(`feedback_layer2_pass_not_final`).

---

## B. 결정성 실측 — 3층 스위트 10회 반복

`testlogs/202608/l3_repeat_20260817_104125/`

| | |
|---|---:|
| 실패 회차 | **8 / 10** |
| `ONEPC-CONF-01` | **7회** |
| `SIM-AUTO-01` | 1회 |
| 나머지 19종 | **0** |
| 방 / 좀비 | 3 고정(재사용, 누적 없음) / +0 |

**종전 라벨이 거꾸로였다.** 기록들은 *"단독 5/5·6/6 통과"* 를 근거로 flaky 라 불렀는데,
실측은 **스위트 문맥이 정상 조건이고 단독이 특수 조건**이었다. 단독도 1/3 로 실패한다.

### 임계는 문제가 아니었다

3층 단언은 `toBeGreaterThan(0)` **31개** / 실수치 임계 **2개**뿐이고 실측값이 `Δ=125` 수준이라
여유가 ~125배다. **숫자를 흔들어 뒤집히는 시험이 아니다.** 비결정성은 다른 데 있었다.

---

## C. 순환이 끊긴 지점 = **규명** (지침 6)

`ONEPC-CONF-01` 은 `0814c`·`0815a`·`0817` **세 세션**에 걸쳐 실패했고 매번 *"known flaky"* 로
닫혔다. **2층으로 내려간 것은 0건.** 이유는 하나였다 —

> 실패 시 남는 게 `trace.zip` + 스크린샷(DOM/네트워크)뿐이라
> `MEDIA_DEBUG_GUIDE §1` 이 요구하는 **4축 판별 지표가 하나도 안 남았다.**

진단 표면은 이미 있었다(`qa.js` `trackStatsRaw`/`pubStatsRaw`, 20260712 SRV-0712c). **fixture 가
안 뚫어놔 스펙이 못 썼을 뿐이다.** 만들어놓고 실패 경로에 안 걸어둔 것.

### 뚫은 것 (`oxlens-home 8d17ace`, `c8a83f4`)

- fixture 에 `trackStatsRaw`/`pubStatsRaw`/`sdpDump` 노출
- `dumpBlackScreenDiag()` — 실패 시 **필드명을 추측하지 않고** 있는 stat 타입을 먼저 찍고
  `inbound-rtp`/`codec`/`track` 을 통째로 + 해당 mid 의 **SDP 원문** 을 남긴다
- `onepc.spec` 의 `framesDecoded` 폴 실패 시 진단을 남기고 던진다(판정 불변, 증거만 추가)
- **★`pubStatsRaw` 는 늘 null 이었다** — `RemotePipe` 에만 `getStats` 가 있고 **`LocalPipe` 에는 없다**
  (`remote-pipe.ts:305`). 송신측 진단이 **원리적으로 불가**했다. `transport.collectStats()`
  (`transport.ts:546`) 경유로 재배선 — **SDK 무변경**
- `sdpDump` 에 `subPc` 추가 — 구판은 `pubPc` 만 찍어 **2PC 의 sub m-line 을 한 번도 못 봤다**

---

## D. 근인 — sdk0.2 `_mapCodecsToOfferPts` (`oxlens-home 385157f`)

answer 합성 시 서버 코덱을 offer 의 PT 로 매핑(RFC 3264)하는데 **H264 만 매칭 조건에
`profile-level-id` 일치를 걸어뒀다.** 서버 정책은 `42e01f` 고정인데 Chrome 은 H264 를
profile 별로 여러 개 제안하고 실제 선택이 매번 다르다.

| publisher profile | 매칭 | `mapped.pt` | 결과 |
|---|---|---|---|
| `42e01f` | 성공 | offer PT **109** | 정상 |
| `42001f` | **실패** | **서버 정책 PT 102 잔류** | 검은 화면 |

**매칭 실패를 조용히 넘기고 서버 값을 유지한 것**이 사고다.

### 사슬 (전부 실측)

```
① 클라 answer 합성      H264 매칭 실패 → m-line 첫 PT = 102(서버 정책)
② _parseAnswerVideoPt() 그 102 를 읽어 PUBLISH_TRACKS 로 보고   (transport.ts:686)
③ 서버                  [TRACK:REG] ssrc=0x456A7B6C tt=FullNonSim pt=102 codec=H264 — 받은 값 그대로
④ 구독자 m-line          m=video … 96 97 102 103
⑤ publisher 실송신       PT=98 (outbound-rtp codecId, encoder=OpenH264, keyFramesEncoded=3)
⑥ 수신                  packetsReceived=612 packetsLost=0 nackCount=0
                        framesReceived=0 keyFramesDecoded=0 pliCount=0 **codecId 없음**
⑦                       → 검은 화면
```

**서버 무죄**: forward 정상, PLI 중계 정상(`[PLI:GOV] FORWARD sub=U01 pub=U02` 4.7초간 12회).
`pliCount=0` 인 것도 정합 — **코덱이 안 붙어 디코더가 없으니 PLI 보낼 주체가 없다.**

### 수리

이름으로 매칭하고 **PT·fmtp·rtx_pt 를 전부 offer 것으로 반영**한다.
`profile-level-id` 도 PT 와 똑같이 **협상 산물**이라 정책 고정값과 다르다고 매칭을 깨면 안 된다.

### 게이트

| | |
|---|---|
| `ONEPC-CONF-01` 단독 | **10/10 통과** (수리 전 7/10 실패) |
| 3층 전체 스위트 | **3회 연속 20 통과 / 1 skip(DIAG 전용) / 실패 0** |
| 이전 1/10 나던 `SIM-AUTO-01` | 재현 없음 |

---

## E. ★내가 두 번 틀렸다 — 추론으로 수리하고 되돌렸다

| # | 가설 | 기각한 실측 |
|---|---|---|
| ① | *"서버가 구독 m-line 에 고정표(102)를 박는다"* → 1PC egress PT 정규화 + RTX PT 유도를 `crates/` 에 구현 | **정상 시 sub m-line 이 이미 `96 97 109 114`**(publisher 실 PT). 정규화하면 **정상 경로가 깨진다.** 커밋 전 revert |
| ② | *"`video_pt == 0` 이라 필드가 생략된다"* | `[PT:OMIT]` 경고 **0건**. 서버는 pt 를 실어 보냈다 |

①은 BUNDLE 충돌로 설명하려 했는데 **2PC 도 같은 고정표를 쓰므로 차이를 설명하지 못했다.**
부장님이 *"왜 1pc와 2pc가 근본적으로 차이가 발생하는지 모르겠어"* 로 짚어 재측정했고,
2인 대조 실험에서 **둘 다 109 로 정상**임이 나와 가설이 무너졌다.

**교훈**: 20260816 에 세운 규율 3(형상 우선)의 **디버깅판** — 인과를 추론으로 세우고 수리부터
하면 정상 경로를 깬다. 값을 보고 나서 고친다.

---

## F. 하드코딩 전수 조사 (지침 8)

| 지점 | 상태 |
|---|---|
| `VideoCodec` 묵시 VP8 기본 | **입구는 폐기됨**(20260613 `from_str_strict` — 미지정/오타는 PUBLISH_TRACKS 거절) |
| **`PublisherTrack::video_codec()`** | **`unwrap_or(VideoCodec::Vp8)` — 묵시 VP8 이 접근자에 살아 있다.** 근거 주석은 *"stream None → 라우팅 대상 아님이라 무의미값"* 인데 `collect_subscribe_tracks`(SDP 생성)가 그 접근자를 읽는다 = **가정 밖 소비처** |
| **`PublisherTrack::actual_pt()`** | 동일 — `unwrap_or(0)` |
| `server_codec_policy` | 고정표. 주석 그대로 *"fixed, no negotiation"*. **profile-level-id 까지 고정**한 것이 이번 사고의 뿌리 |
| `apply_video_codec_fields` | `pt/rtx_pt==0 이면 필드 생략` — 20260626 묶음 E 리팩터가 *"기존 인라인과 동일 동작"* 으로 보존. **codec 은 6/13 에 fallback 을 없앴는데 pt 는 리팩터가 화석으로 만들었다** |
| `pt_for_video_codec` 정규화 | PTT/Hall(`HalfNonSim`)에만 적용. `FullNonSim` 은 미적용 — **이건 정상**(구독 m-line 이 publisher PT 를 담으므로) |
| `rtx_pt_for(media_pt)` | PT 번호로 추측(`102=>103, _=>97`). publisher 가 표준 PT 를 안 쓰면 H264 에 VP8 용 97 이 붙는다. **미수리 — 별건** |
| `admin.rs:155` | `actual_pt==0` 을 `video_pt_zero` issue 로 **이미 보고 중**. 즉 문제를 알고 있었으나 막지는 않았다 |

---

## G. 서버 가드 — 첫 패킷 PT 대조 (`oxlens-sfu-server 01bb699`)

부장님 지침 9·10 반영. **자가치유는 택하지 않았다** — 있었으면 이 사고가 영원히 안 드러났다.

```rust
// ingress_publish.rs, video 한정 + track 이미 해소된 블록
if !track.pt_checked.load(Relaxed) && !track.pt_checked.swap(true, Relaxed) {
    declared = track.actual_pt();  arrived = rtp_hdr.pt
    불일치면 warn [PT:MISMATCH] + agg `pt_mismatch`
}
```

핫패스 비용은 첫 패킷 이후 **relaxed load 1회로 단락**. 조회 증가 0.

**갈래B 실측**: 정상 = 0건 / sdk0.2 수리 일시 복원 = `declared_pt=102 arrived_pt=98 codec=H264`
정확히 3건 적발.

부수 관측(동작 무변경, `a0b7b89`): `[PT:OMIT]`(pt 생략 표면화 — **가설 ②를 즉시 기각시킨 장치**),
`[TRACK:REG]`/`[TRACK:NOTIFY]` 에 `pt`·`codec` 추가(가이드는 *"REG 에서 pt 확보"* 라는데 실제론
안 찍히던 드리프트 정정).

---

## H. 3층 자체의 비결정 요인 (지침 5 — 미착수)

수리 후 스위트가 3회 연속 초록이라 **현재 발현은 없다.** 다만 구조는 남아 있다:

| | 실측 | 위험 |
|---|---|---|
| 신원 공유 | 방 3개(`qa_test_01` ×21) · user 3개(`U01` ×15)를 21스펙이 돌려씀 | 서버 `PeerMap.by_user` 단일 전역 키. **2층이 20260816 `2883470` 태그 격리로 푼 그 문제**. 3층은 `workers:1` 직렬로 회피 중이고 **직렬은 격리가 아니라 순서 회피** |
| 조용한 정리 실패 | `afterEach` 의 `try{}catch{}` | 실패해도 모름. zombie reaper 는 SUSPECT 15s/ZOMBIE 20s 라 스펙(0.4~23.7s)보다 늦다 |
| 고정 대기 : 수렴 폴링 | **30 : 5** | 단발 측정은 앞 시험 잔류에 취약(0815a 실증). 처방(`expect.poll`)은 1곳만 적용 |

3층엔 2층의 `perturb`(여유 측정)·`rejudge`(표본 재판정)·`dump_integrity` 대응물이 **없다.**

---

## I. 빈 방 회수 (지침 2 — 조사만, 미수리)

**설계가 아니라 미구현이다.** 마스터 3종에 방 회수/영속 언급 **0건**.

| 층 | 정리 코드 |
|---|---|
| sfud `RoomHub.rooms` | `remove_room()` 정의는 있으나 **호출부 0건** |
| hub `room_sfu` 매핑 | 제거 코드 **0건** |
| `zombie reaper` | **peer 만** 회수. 방은 안 본다 |
| `ROOM_LEAVE` | 참가자만 제거. **"방이 비었나" 검사 없음** |
| oxadmin | 방 삭제 명령 **없음**(`reap` 은 user 단위) |

→ 프로세스 재기동 전까지 안 사라진다. 실측 5,421개(전부 `user_count 0`) → `oxadmin rooms`
출력 **1,223,426 B**. **이게 실제 사고를 냈다** — Node `execFileSync` 기본 maxBuffer(1MB) 초과 →
3층 `oxadminAvailable()` 이 그 예외를 삼켜 *"미빌드/서버다운"* 으로 오보 → 교차 단언 9종이
조용히 skip. 수리 `c5ce83f`(maxBuffer 명시 + 사유 삼킴 제거).

**발생 경로는 2층**(시나리오 태그·PID 로 run 마다 새 방). 3층은 방 이름 고정이라 누적 안 됨.

선택지(미결): A 참가자 0 이면 즉시 제거 / **B 유휴 방 회수 태스크**(`zombie reaper` 동형,
L5 회수 축으로 검증 가능) / C 영속 유지 + admin 페이징. **제 추천은 B.**

---

## 잔여 (다음 세션이 받는 것)

### 1. ★클라 통보 계약 — `MEDIA_NOTICE` 통합 (부장님 지침 11)

**op 신설이 아니라 통보 op 하나 + 내부 구분자로 간다.** 파편 증거:

```
VideoSuspendedEvent { user_id, room_id }   0x2103
VideoResumedEvent   { user_id, room_id }   0x2104   ← body 완전 동일, 차이는 op 번호뿐
TrackStalledEvent   { track_id, pub_pid, kind, ssrc, reason }  0x2105
0x2106 LAYER_CHANGED — "emit/dispatch 전무 고아" 로 폐기(20260705)
```

설계안:
```
MEDIA_NOTICE 0x2107 (S→C)
{ type: "pt_mismatch"|"stalled"|"video_suspended"|"video_resumed"|…,
  room_id, user_id, track_id?, kind?, ssrc?, detail?:{...} }
```
- `TRACK_STALLED` 의 `reason`(*"현행 고정값"* = 확장 전제)이 이미 그 구분자다. op 층위로 올리는 것
- 번호는 폐기분 `0x2106` 재사용 대신 **`0x2107`**(구 클라 오작동 회피)
- 기존 3개는 **병행 발신 → 클라 이전 → 구 op 제거** 로 점진 흡수

**소비자 전수(메모리 규칙)**: `oxsig` · `oxsfud` · **sdk0.2**(`protocol/ops.ts`,
`signaling/signaling.ts:406~412`) · **oxe2epy**(bot·verifier·scenarios — 20260816 신설
`stall_detected` 등식과 `adv_stall_detect` 시나리오가 여기 걸린다).

**범위 결정 필요**: A(신 op + pt_mismatch 만) / **B(기존 3 op 흡수)** — 부장님 지적의 핵심은 B.
B 는 다단계라 **한 세션에 안 끝난다는 전제**로 시작할 것.

### 2. ★선언 ↔ 실도착 대조를 **축으로** 확장 (부장님 20260817: "pt에 대해서만 로깅하지?")

> **서버는 선언과 실제가 다른 것을 알면서 넘어가지 않는다.**

오늘 넣은 `[PT:MISMATCH]` 는 **축 하나의 필드 하나**다. 클라가 PUBLISH_TRACKS 로 선언하는 값이
19개인데(`PublishTracksReq` 8 + `PublishTrackItem` 11) **대조하는 건 media `pt` 하나뿐이다.**

| 선언값 | 대조 근거 | 현재 |
|---|---|---|
| `pt`(media) | 도착 RTP 헤더 | **20260817 가드** |
| `rtx_pt` | 첫 RTX 패킷 PT | 없음 — `is_rtx_pt()` 가 **하드코딩 표(97/103)** 로 판정하고 선언값을 안 쓴다 |
| `ssrc` | 도착 RTP ssrc | 없음 — 못 찾으면 RTP-first promote 로 새 트랙 생성. **simulcast 정상 경로와 구분이 안 된다** |
| `rtx_ssrc` | FID 짝 | 없음 |
| `mid` | RTP mid 확장 | 없음 |
| `rid` | RTP rid 확장 | 없음 |
| `codec` | payload 구조(VP8 descriptor / H264 NAL) | 입구 거절만(`from_str_strict`). **실 payload 와 대조 안 함** |
| `kind` | 도착 PT ↔ audio/video | 없음 |
| `twcc/rid/repair_rid/mid/audio_level _extmap_id` | 선언 ID 자리에 실제 확장이 있나 | **없음** — 선언값을 그대로 믿고 `parse_rid(buf, id)` 등을 호출하고, 못 찾으면 `None` 으로 **조용히 넘어간다**. 클라가 `rid_extmap_id=3` 이라 했는데 Chrome 이 4에 넣었으면 simulcast 레이어 오분류 |

**훅은 이미 있다** — `PublisherTrack.pt_checked`(첫 RTP 1회) 자리에서 전부 볼 수 있다.
비용 불변(첫 패킷 이후 relaxed load 1회 단락). 로그 이름은 `[DECL:MISMATCH]` 식으로 필드별.

**착수 순서(난이도별)**:
1. **쉬움 — `ssrc`·`kind`·`mid`·`rid`**: 이미 파싱된 값과 비교만. **여기부터.**
2. 중간 — `extmap` 4종: "선언 ID 자리에 확장이 있나". ★simulcast 는 rid 가 없는 게 정상인
   구간이 있어 **오탐 주의**(음성 픽스처 필수)
3. 중간 — `rtx_pt`·`rtx_ssrc`: 첫 RTX 패킷 시점이 불확정(NACK 있어야) → 별도 훅
4. 어려움 — `codec` ↔ payload 구조: VP8/H264 판별 신설. **오탐 위험 최대**, 마지막

`pt` 하나로 3세션짜리 사고가 한 줄이 됐다. 1번 4종이면 상당 범위가 덮인다.

### 3. 2층 형상 — 시험 케이스 부재 (지침 7)

2층에 `codec_match` 등식은 **있다**(수신 RTP pt ↔ 약속 `video_pt` 대조). 못 잡은 이유는
봇이 `publish_video(pt=96, codec="VP8")` 로 **선언하고 그대로 보내** 항상 일치하기 때문.
→ **봇이 "선언 PT ≠ 실송신 PT" 를 만들 수 있으면 `codec_match` 가 잡는다.** 등식 신설 불요.
20260816 §0-I 규율 3(형상 우선)의 교과서적 사례.

### 4. `rtx_pt_for(media_pt)` 추측 — 별건

`102=>103, _=>97`. publisher 가 표준 PT 를 안 쓰면 H264 에 VP8 용 RTX PT 가 붙는다.
`rtx_pt_for_video_codec(codec)` 이 이미 있으니 호출자가 코덱에서 유도하면 된다.
**단, 구독 m-line 이 선언한 RTX PT 와 맞춰야 한다** — 오늘 이걸 정책표 기준으로 고쳤다가
되돌렸다(정상 시 RTX 는 114). 실측 먼저.

### 5. `PublisherTrack` 접근자의 묵시 기본값 — 별건

`video_codec()` → `unwrap_or(Vp8)` / `actual_pt()` → `unwrap_or(0)`.
"Stream 부재"와 "값 없음"이 같은 값으로 뭉개진다. `Option` 반환 계열 신설 + 소비처 명시 처리가
정석이나 호출처가 많다. 범위 산정 필요.

### 6. 3층 비결정 구조 (§H) — 신원 격리 / `catch{}` 제거 / 단발→`expect.poll` 30곳

### 7. 빈 방 회수 (§I) — B안 결정 대기

### 8. 3층 시험 항목 체계 (지침 3·4) — 조사만 하고 결론 미도출

`qa/checks/` 178항목은 `qa/README.md:68` 이 스스로 *"v0.1 기준 전면 stale, sdk0.2 재편 미착수"*
로 선언해둔 상태. 원천은 **구현 파생**(외부 규격 인용은 checks 내 1건뿐), 눈·귀 체감 항목은
178 중 **4건**. 반면 실제 21스펙은 `framesDecoded`(26회)·`packetsReceived`(24회)를 쓴다 —
**목록보다 스펙이 3층 정체성에 더 맞다.** 경계 규칙 자체는 `README:26`(20260630 부장님 정정)에
이미 옳게 있다: *"와이어로 결판나면 2층에서 끝. 실 디코딩·품질·픽셀이 판정을 바꿔야만 3층."*
※ `README` 도 뒤처져 있다 — *"시나리오 5종"* 이라 하는데 실제 **21종**.

### 9. push — 미결재 누적

`oxlens-sfu-server` 3건(`a0b7b89`·`01bb699` 외) / `oxlens-home` 3건(`c5ce83f`·`8d17ace`·
`c8a83f4`·`385157f`) / `context`.
