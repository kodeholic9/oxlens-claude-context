# 설계서 — half ↔ full Duplex Activeness (전환 = 캐싱 + 분류 권위 단일화)

문서 ID: `20260531_duplex_activeness.md`
작성: 김대리 (claude.ai)
성격: **서버 설계**. 클라 구현 문서가 아니다 — 클라가 서버에 무엇을 기대하는지(기대값)를 상상해, 그 기대를 **서버가 내보내는 출력 스펙**으로 녹인다. 클라 SDK/UI 코드는 본 설계 범위 밖.
선행: Publisher 2계층 Stage 1~4 완료 (`PublishContext ⊃ PublisherStream(논리) ⊃ PublisherTrack(물리)`, commit `dadc342`+`96ded24`, 211 PASS).

---

## §1 배경 — 무엇을, 왜

half ↔ full duplex 전환을 **상태 통지 수준의 가벼운 전환**으로 만든다. mute 가 SDP 를 안 건드리고 sender 만 토글하듯, duplex 도 m-line 생명주기를 안 건드리고 송출 경로만 토글하는 것이 목표.

### 현재 (republish) 의 문제

`track_ops.rs` 의 hot-swap 이 전환마다 개인 SubscriberStream 을 **부수고 다시 만든다**:
- full→half: `emit_per_user_tracks_update("remove")` + mid 회수 + `remove_subscriber_stream_by_vssrc`.
- half→full: `floor.release` + FullNonSim 경로 자연 재진입 (개인 stream 신규 생성).

문제는 두 겹이다.

1. **표면**: 가벼워야 할 전환이 SDP/mid 자원을 부수고 재생성한다.
2. **근본**: fan-out 분류가 세 곳에 분산돼 있다 —
   - `PublisherTrack::fanout`: `is_half = duplex_load()==Half && !simulcast` 즉석 재조합.
   - `SubscriberStream::forward`: `via_slot` / `forwarder` (subscriber 측 자료) 분기.
   - `TrackType`: "single source of truth" 라 선언만 되고 fanout 이 안 부름 (죽은 권위).

   전환 시 이 분산된 분류를 손으로 맞추는 행위가 곧 republish 다. **분류가 한 곳에 안 모여서, 자료를 통째로 갈아끼워 강제 정합**시키는 것.

> 함정 경고 (부장님): 이 증상을 "자료 부정합" 으로 진단하면 또 자료를 옮기게 된다. 본 건은 자료 부정합이 아니라 **행위(분류 판단) 분산** 이다. 처방은 자료 재배치가 아니라 **분류 판단을 단일 주체로 모으는 것**.

---

## §2 클라 기대값 — 서버 설계의 출발점

서버는 클라 UI 를 모른다. 그러나 **클라가 무엇을 기대하는지**를 상상하지 않으면 서버가 무엇을 내보내야 하는지 정할 수 없다. 본 설계는 그 기대값을 서버 출력 스펙으로 번역한다.

### 수신 클라의 두 패러다임 (현물 확인됨)

같은 사람(예: 현장요원)의 영상을 수신 클라는 모드에 따라 **완전히 다른 UI 패러다임**으로 다룬다:

| | full | half (PTT) |
|---|---|---|
| 수신 트랙 | userId 별 개인 (track_id `{user}_{ssrc}`) | 방 슬롯 1개 (track_id `ptt-{room}-video`) |
| 발화자 식별 | userId 고정 | floor speaker (동적) |
| UI 모델 | 개인 grid 타일 (상시) | PTT 슬롯 + show/hideVideo |

→ full↔half 전환은 트랙 교체가 아니라 **수신측 UI 패러다임 전환**(개인 grid ↔ PTT 슬롯)이다. track_id 가 다른 것(SDP 2 라인)은 이 패러다임 차이의 표현일 뿐.

### 그래서 클라가 서버에 기대하는 것

1. **"누가, 어느 source 가, 어느 모드로 바뀌었나"** 를 명확히 받기 — 그래야 그 userId 의 자리를 grid 타일 ↔ PTT 슬롯으로 옮긴다.
2. **개인 트랙과 슬롯 트랙을 같은 userId 로 묶을 단서** — 두 track_id 가 다르므로, 묶는 키(userId + source)를 서버가 일관되게 실어줘야 한다.
3. **half 슬롯의 현재 발화자** — 이미 floor(FLOOR_MBCP speaker) 로 받고 있음. 추가 자산 불필요.

> 경계: UI 레이아웃 전환(grid ↔ 슬롯)은 **앱 레이어 책임**이다 (프리셋이 모델 결정, SDK 는 primitive — 기존 원칙). 서버는 위 1·2 신호만 충실히 내면 된다. 본 설계는 그 **신호 스펙**까지가 범위.

---

## §3 설계 결정

### 결정 A (전제) — 분류 권위 단일화 ★ 동의됨

`TrackType` 을 fan-out 분류의 단일 진실로 **복원**한다.

- `PublisherTrack::fanout`: `is_half` / `is_simulcast_video` 즉석 재조합 폐기 → `self.track_type()` 의 `match` 로 경로 선택.
- subscriber 의 `via_slot` / `forwarder` 는 **독립 축이 아니라 TrackType 의 파생** — publisher 가 Half 면 subscriber 는 반드시 slot 경유, FullSim 이면 forwarder=Some, FullNonSim 이면 둘 다 비움. 등록 시점에 publisher TrackType 을 보고 결정한다.
- 효과: "이 트랙이 무슨 모드냐" 결정이 **한 자리(TrackType)** 로 수렴. 전환은 그 한 값의 변경이 되고, 분산 정합을 손으로 맞추던 republish 가 소멸.

### 결정 B (본체) — 전환을 republish → 캐싱

- full→half: 개인 stream **제거 폐기**. 개인 stream 은 inactive 캐싱(보존).
- slot stream: 늘 상존 (현행 유지 — `collect_subscribe_tracks` 무조건 push).
- half→full: 개인 stream **재활성** (보존돼 있으면 재생성 아님).
- fanout 은 결정 A 위에서 publisher TrackType 으로 자동 선택. (별도 active 플래그 불필요 — fanout 경로 분기가 그 역할.)

### 결정 C — 생명주기 기준 변경 (캐싱 보호 + 두 inactive 구분)

SDP `a=inactive` 는 의미를 안 담는다. "screen 삭제(슬롯 recycle)" 와 "full→half 캐싱(슬롯 보존)" 이 wire 상 똑같이 inactive 다. **둘을 가르는 단일 진실은 서버 mid_map 보유 여부** — 클라·SDP 가 아니라 `SubscribeContext` 가 책임진다.

- mid_map 보유 = 캐싱(보존). 미보유 = 제거(recycle).
- `release_stale_mids`: 회수 기준을 "현재 duplex" → **"subscriber mid_map 보유"** 로. half 라는 이유로 개인 mid 를 회수하지 않는다.
- `collect_subscribe_tracks`: half 트랙의 개인 m-line 을 `continue` 로 빼지 말고 **inactive 로 계속 그린다** (current_track_ids 포함 → ROOM_SYNC 가 release 대상으로 안 봄).

> 결정 B·C 는 한 묶음. C 없이 B 만 하면 ROOM_SYNC 한 번에 캐싱이 무너진다.

### 결정 D — 전환 통지 (서버 출력 스펙) ★ §2 기대값의 번역

전환은 **한 종류가 아니다.** 서버가 subscriber 별로 "개인 mid 보유 여부" 를 보고 분기한다. 클라는 이 통지로 UI 패러다임을 전환한다.

| 케이스 | subscriber 개인 mid | 서버 출력 | 클라 측 효과 |
|--------|---------------------|-----------|--------------|
| **half→full 최초** | 없음 | **TRACKS_UPDATE(add)** + mid + userId/source/duplex | 개인 grid 타일 신설 (SDP renego) |
| **full→half** | 있음(캐싱) | **TRACK_STATE** (개인 inactive) + userId/source/duplex | 개인 타일 거두고 slot+floor 로 |
| **full↔half 왕복** | 있음(보존) | **TRACK_STATE** 토글 | 같은 타일 SUSPENDED↔ACTIVE |

- **불변 1: 모든 전환 통지에 `userId + source + duplex` 동반.** 두 track_id(개인/슬롯)가 다르므로, 클라가 같은 userId 의 두 모드로 묶는 단서를 서버가 보장한다 (§2 기대값 2).
- **불변 2: "트랙 최초 등장" 은 TRACKS_UPDATE, "이미 아는 트랙의 상태 변경" 은 TRACK_STATE.** mute 를 TRACK_STATE 로, 신규 발행을 TRACKS_UPDATE 로 가르는 경계와 동일. 최초 진입은 mid 할당 + SDP renego 가 필요하므로 TRACK_STATE 로 못 한다.
- half 슬롯 ↔ 발화자 매핑은 기존 floor(FLOOR_MBCP speaker) 가 이미 제공 — 추가 없음.
- 전환 신호(C→S): `TRACK_STATE_REQ` (신규 op, body attr 분기 muted/duplex). duplex 를 `PUBLISH_TRACKS` 에서 분리(이중화 금지). 범위는 muted + duplex 만 (YAGNI). 기존 `TRACK_STATE(0x2102)` event 재활용.

---

## §4 단계 (Phase)

| Phase | 내용 | 위험 | 정지점 |
|-------|------|------|--------|
| **1 (전제)** | 분류 권위 단일화. fanout `is_half`/`is_simulcast_video` → `track_type()` match. forward 분기를 TrackType 파생으로 정렬. | 높음 (핫패스) | ★ commit + 회귀 |
| **2 (본체)** | republish → 캐싱. 개인 stream 보존 + 결정 C (release_stale_mids + collect 생명주기 기준). | 중 | ★ commit + 회귀 |
| **3 (통지)** | TRACK_STATE_REQ 신설 + 결정 D 출력 스펙 (add/state 분기 + userId/source/duplex 동반). duplex 를 PUBLISH_TRACKS 에서 분리. | 중 (wire) | ★ |

Phase 1 이 본체보다 먼저인 이유: 분산된 분류 위에 캐싱을 얹으면 전환이 또 분산 정합을 손으로 맞추게 된다 (함정 재현). 분류를 먼저 모아야 본체가 "한 값 변경" 으로 깔끔해진다.

---

## §5 기각 접근법

- **active 플래그 신설 (SubscriberStream.direct_active)** — fanout 의 duplex 경로 분기가 이미 그 역할. 중복 자료 + 시점 race.
- **republish 유지** — 자원 부수기/재생성 + 분산 분류 위에 얹힘.
- **클라측 필요사항을 별도 문서로 정리** — 기각 (부장님). 클라 구현이 아니라 **클라 기대값을 서버 출력 스펙(결정 D)으로 녹이는 것**이 본 설계의 일.
- **두 inactive 를 SDP/클라가 구분** — SDP 는 의미를 안 담는다. 구분은 서버 mid_map (결정 C) 단일 책임.
- **cross-room 동시 설계** — 단일방 한정. cross-room 은 slot 이 방 청취 여부로 add/remove 되어 "slot 늘 상존" 전제가 흔들린다. 별 토픽.
- **TrackType 폐기 + 자료 분기 유지** — 분류 권위 분산의 직접 원인 (catch 6 가 SubscribeMode enum 을 via_slot/forwarder 로 쪼갠 전례). 자료 단순화가 분류 권위를 흩는 안티패턴.

---

## §6 영향 범위 (서버)

- `room/publisher_track.rs`: `fanout`, `broadcast_full` (분류 match).
- `room/subscriber_stream.rs`: `forward` (via_slot/forwarder 를 TrackType 파생으로 정렬).
- `signaling/handler/track_ops.rs`: hot-swap republish 폐기 + duplex 분리 + 결정 D 분기(add/state, subscriber 별 mid 보유 판단).
- `signaling/handler/helpers.rs`: `collect_subscribe_tracks` (half 개인 m-line inactive) + 전환 통지에 userId/source/duplex 적재.
- `release_stale_mids` 호출처: 생명주기 기준 변경.
- `oxsig::opcode`: TRACK_STATE_REQ 신설.

---

## §7 미결 / 후속

- **forward 2계층 후 정확한 형태 확인** — 구현 지침 단계에서 `subscriber_stream.rs::forward` 현물 재동기화 (PublisherTrack 참조 반영).
- **simulcast 트랙의 duplex 전환** — half 는 sim 강제 off 이므로 FullSim↔Half 는 sim 해제 동반. 1차 범위는 FullNonSim↔HalfNonSim.
- **단일방 전제 하 cross-room 전환** — 향후.

---

*author: kodeholic (powered by Claude)*
