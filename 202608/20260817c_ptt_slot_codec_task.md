---
kind: task
status: done
opened: 20260817
refs: [202608/20260817b_codec_table_removal_task.md, PROJECT_SERVER.md, guide/MEDIA_DEBUG_GUIDE_FOR_AI.md]
---
# PTT slot 코덱 — 선언과 재기록을 한 출처로

> 지시: 부장님(kodeholic) 20260817 — *"PTT 를 위해 고정 코덱 제약이 서버에 있어야 되나?
> `slot_pt` 에서 냄새가 난다. full/half 에서 쓰는 코덱에 차이가 있어야 되니?"* →
> 실증 후: *"지침을 새로 쓰고 작업해야 될 것 같다. 보이지 않는 함정이 많을 것 같다."*
> 집행: 김과장(Claude Code)

---

## 0. 원칙 (20260817 승계)

> **정합하지 않으면 뭉개거나 보정하지 않는다. 그 자리에서 드러나게 한다.**

`20260817b` 가 클라 협상 경로에 적용한 것을 **slot(무전) 경로**에 적용한다.

---

## 1. 결함 — 실증됨 (`20260817b §6-6`, `SRV-0817-ptt-slot-fixed-codec`)

무전(half)은 **N:1 공용 slot m-line 하나**를 화자들이 돌려쓴다. 그 m-line 의 코덱을 정하는
두 지점의 출처가 다르다.

| | 값 | 좌표 |
|---|---|---|
| 구독자 slot m-line **선언** | `pt 96 / VP8` **하드코딩** | `helpers.rs:411` `// video slot (VP8 고정)` |
| egress PT **재기록** | `pt_for_video_codec(화자 코덱)` | `subscriber_stream.rs:480` |

H264 화자가 무전 영상을 쏘면 **선언 96 / 실도착 102**. 가드 없음.
실측: `codec_match [botB] 수신 [102] != 약속 96` (`scenarios/ptt_video_h264.yaml`).

**질문에 대한 답**: full/half 에 코덱 차이가 필요한 게 아니다. 제약의 정체는 duplex 가 아니라
**N:1 공용 m-line** 이다 — 화자가 바뀌어도 구독자 SDP 를 재협상하지 않으려면 그 m-line 의
PT/코덱이 고정이어야 하고, 따라서 **그 방의 half 화자들끼리 같은 코덱**이어야 한다.
`"half 는 VP8"` 은 그 제약의 결론이 아니라 **값을 정하기 귀찮아 박아둔 것**이다.

---

## 2. 함정 — 착수 전 확인한 것 (전부 소스 근거)

### T1. slot m-line 은 **JOIN/SYNC 에서만** 선언되고 갱신 경로가 없다

`collect_subscribe_tracks` 호출부는 `room_ops.rs:273`(ROOM_JOIN) · `:375`(ROOM_SYNC) **둘뿐**.
slot entry 를 다시 통지하는 `TRACKS_UPDATE` 경로는 **없다.**

→ **"첫 화자로 확정" 모델은 성립하지 않는다.** 이미 JOIN 한 구독자의 m-line 을 바꾸려면
재통지 + 클라 재협상이 필요한데, 클라는 slot 신원 변경을
*"slot identity change (**server invariant broken**)"* 로 취급한다(`virtual.ts:111`).
기존 불변식과 싸우는 설계다.

### T2. 다방 청취 — 한 구독자가 여러 방의 slot 을 동시에 갖는다

`collect_subscribe_tracks` 가 `sub_rooms` 전 방의 slot 을 수집한다. 방마다 코덱이 달라도
되어야 한다 → **방 단위 확정이면 자연 충족**(slot 은 방 소유).

### T3. cross-room 발언 — 화자와 목적지 방이 다르다

`talk_in_room`(SCOPE op) 로 A 방에 있으면서 B 방으로 발언한다. 코덱 판정은 "화자가 publish
할 때"가 아니라 **그 slot 에 붙는 시점**이어야 한다. publish 시점 판정만 두면 cross-room 이
샌다.

### T4. ★오디오 slot 은 "재기록이 없다"가 아니라 **서버가 opus 를 합성한다**

`ptt_rewriter.rs:63` `const OPUS_PT: u8 = 111;` — 서버가 priming/release 용
**opus silence 프레임을 스스로 만들어 PT 111 로 찍는다**(`:213`, `:286`, `:562` 3곳).

→ 오디오 slot 은 코덱 축이 없는 게 아니라 **opus 에 구조적으로 묶여 있다.**
RoIP(G.711)는 "코덱 축 신설"만으로 안 되고 **silence/priming 합성기까지 코덱별**로 필요하다
(μ-law silence = `0xFF`, A-law = `0xD5`). `20260817b §6-4` 의 전제 2번이 이것이며,
**규모가 예상보다 크다.**

### T5. `PttRewriter` 는 손대면 안 되는 자산이 있다

`slot.rs:78` **부록 E.1 보존 의무** — arrival-time 자산 / Opus silence flush / ts_guard_gap /
멱등 `clear_speaker` / `pending_keyframe`. *"단순화 절대 금지"*.
→ PT 재기록은 **rewriter 바깥**(현재 위치인 `subscriber_stream.rs` 분기)에서 끝낸다.

### T6. 영상 무전은 보류 상태다 (20260624)

video slot 은 3층 라이브 경로가 아니다 → **이 결함은 2층에서만 잡힌다.**
반대로 회귀 가드도 2층에만 둘 수 있다.

---

## 3. 설계 — 방 단위 확정 (A안)

| | A: 방 정책으로 확정 | B: 첫 화자로 확정 |
|---|---|---|
| slot m-line 선언 시점 | JOIN 시점에 이미 값이 있다 | 화자 등장 후 → **재통지 필요(T1)** |
| 기존 불변식 | 유지 | slot identity 불변식과 충돌(T1) |
| 화자 전환 비용 | 0 | 코덱 다르면 전원 재협상 |
| 코덱 불일치 화자 | **거절**(드러냄) | 재협상 또는 무음 |

→ **A안.** 방이 slot 코덱을 갖고, 선언·재기록·거절이 **그 하나**를 본다.

값의 출처는 이번 범위에서 **서버 기본값(VP8)** 이다. 방별 지정은 `ROOM_CREATE` 에 필드 한 개를
더하면 열리는 자리로 남긴다 — **지금 열지 않는다**(수요 없이 wire 를 늘리지 않는다).

---

## 4. 작업

### W1. `Slot` 이 코덱을 갖는다
`domain/slot.rs` — `Slot { codec: VideoCodec, pt: u8, rtx_pt: u8 }`(video slot).
`Room::new` 이 서버 기본값으로 확정. 오디오 slot 은 T4 때문에 이번 범위 밖(opus 고정 유지).

### W2. 선언을 slot 에서 파생
`helpers.rs:411` 의 `VP8_PAYLOAD_TYPE`/`"VP8"` 하드코딩 3줄 → `room.video_slot()` 의 값.

### W3. 재기록 대상을 slot 값으로
`subscriber_stream.rs:480` `pt_for_video_codec(ctx.publisher.video_codec())` →
**slot 이 가진 pt**. 화자 코덱 추종 폐기.

### W4. 불일치 화자는 **거절** — 드러내기
half video publish 의 코덱이 slot 코덱과 다르면 `PUBLISH_TRACKS` 거절(3002 계열 신설 코드).
판정 위치는 **slot 결합 시점**(T3 — cross-room 포함).

### W5. 능력표 정리
W3 이후 `pt_for_video_codec` / `rtx_pt_for_video_codec` 의 소비처가 사라지면
`codec_registry` 의 `slot_pt`/`slot_rtx_pt` 필드도 **함께 제거**한다.
그 필드는 처방이 아니라 증상을 옮겨 적은 것이었다(20260817b §6-5 자기 정정).

### W6. 회귀 가드 전환
`scenarios/ptt_video_h264.yaml` 을 **거절 판정**으로 바꾸고 `SRV-0817` 격리 해제.
거절이 안 나면 빨강이 되도록.

---

## 4-1. ★남은 구멍 — `full → half` 전환 (20260817 부장님 지적, 미수리)

> *"full → half 전환이 가능해서, 코덱 불일치면 전환도 실패해야 되고. 고민할 것이 상당히
> 많아 보임. 고급지게 해결할 수 있는 방법을 답하게 설계하고 진행해야겠어. **not today!**"*

**실재한다.** `do_track_state_req`(`track_ops.rs:407`)는 simulcast 만 거절(2102)하고
**코덱은 보지 않는다.** 따라서:

```
H264 로 video full publish (정상 — full 은 slot 제약 없음)
  → TRACK_STATE_REQ duplex=half  → 전환 "성공" 응답
  → floor grant 시 floor_broadcast 가드가 불일치를 잡아 slot **미결합**
  → 영상이 안 흐르는데 클라는 전환 성공으로 안다 = 조용한 실패
```

W4 의 publish 시점 가드는 이 경로를 지나지 않는다. **§0 원칙 기준 전환 시점에 거절했어야 한다.**

**지금 안 터지는 이유**: 영상 무전 보류(T6). 3층 `ONEPC-DUPLEX-01`(camera full→half→full)은
H264 로 이 전환을 실제로 밟는데 무전 영상이 안 흘러도 판정에 안 걸려 초록이다.
**또 우연히 안 밟고 있는 자리.**

### 설계 시 결정할 것 (착수 전 부장님 판단 필요)

1. **전환 거절 vs 사전 재협상** — 거절이면 클라가 half 로 못 간다. 허용하려면 화자가 코덱을
   바꿔 pub m-line 만 재협상(slot 재통지보다 싸다 — 화자 한쪽).
2. **방 코덱 확정 시점** — 방 생성 시 정하면 "이 방은 H264 무전"이 되고 VP8 클라의 입장/발언
   가부가 갈린다. 입장 시점 거절이냐 발언 시점 거절이냐.
3. **full·half 혼재 방** — full 은 코덱 자유, half 만 방 코덱 고정. 한 사람이 full 로 H264 를
   쓰면서 half 전환만 막히는 게 자연스러운가.
4. **오디오 확장(RoIP)** — T4 의 합성기 코덱화에 full→half 축이 곱해진다.
5. **cross-room 발언** — 목적지 방마다 코덱이 다르면 한 화자가 방마다 다른 코덱을 요구받는다.

## 5. 범위 밖 (명시)

- **오디오 slot 코덱 축** — T4. silence/priming 합성기가 opus 고정이라 별건이며, RoIP 착수와
  같은 묶음이다.
- **방별 코덱 지정 wire** — 수요 시 `ROOM_CREATE` 필드 하나.
- `config::is_rtx_pt` 하드코딩(97/103) — 선언 `rtx_pt` 를 안 쓰는 별건.

## 6-1. 집행 결과 (20260817 당일 완료)

**커밋**: `oxlens-sfu-server 74d8f04` (서버 + 봇/등식 일괄)

| 작업 | 결과 |
|---|---|
| W1 `Slot.video_codec` | `Room::new` 이 `config::PTT_SLOT_VIDEO_CODEC`(VP8)로 확정. `Slot::video_pt()/video_rtx_pt()` |
| W2 선언 파생 | `helpers.rs` slot entry 의 VP8 하드코딩 3줄 → slot 값 |
| W3 재기록 대상 | `subscriber_stream.rs:480` 화자 코덱 추종 → **slot 값** |
| W4 거절 | 불일치 half video publish **3004**(`track_ops`) + cross-room floor 결합 미결합(`floor_broadcast`, T3) |
| W5 정리 | `config::pt_for_video_codec` / `rtx_pt_for_video_codec` **삭제**(소비처 소멸) |
| W6 가드 전환 | `ptt_slot_codec_enforced` 등식 신설 · `ptt_video_h264` 판정 반전 · **SRV-0817 격리 해제** |

**시험**: 서버 단위 **284/284** · 2층 `run-all` **49종 OK 49 / 격리 0** · 3층 2회 22통과/1skip/실패 0.
**갈래B**: 거절 가드를 제거하면 `ptt_slot_codec_enforced` 가 빨강(+`leak_zero` 동반) — 확인.

### ★W5 예측이 틀렸다 (자기 정정)

지침 W5 는 *"`codec_registry` 의 `slot_pt`/`slot_rtx_pt` 도 함께 사라진다"* 고 봤다. **틀렸다.**
slot m-line 은 **화자가 등장하기 전(ROOM_JOIN)** 에 선언되므로 협상값이 있을 수 없고 서버가
골라야 한다. 그 필드는 "코덱별 정책표"가 아니라 **서버가 저작하는 m-line 의 번호**다.
사라진 것은 `config::pt_for_video_codec` — *화자 코덱으로 egress 를 재기록하던* 소비처다.
필드 주석에 정정 기록.

### 부수 — 2층에 "거절이 정상"을 표현하는 수단이 생겼다

`recorder.record_denied_expected` + `loader.denied_ssrcs`. 종전엔 거절 시나리오를 쓰면
약속-송신(`send_honest`)·`track_id_returned` 가 "약속만 하고 안 보냈다"고 잡아 표현이 불가능했다
(B2 무권 op 만 예외 처리돼 있었다). 이제 시나리오가 `expect_denied: true` 로 선언한다.

## 6. 검증

1층 무관 · **2층이 주 게이트**(T6) — `ptt_video_h264` 거절 판정 + `run-all` 전량 ·
3층은 회귀 없음 확인용(무전 영상 비활성이라 이 축을 못 본다).
