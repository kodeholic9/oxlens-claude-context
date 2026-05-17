# 2026-04-30 b — fan-out 회귀 진단 + vssrc 가드 시도/원복

> 직전 세션: `20260430_phase2_cleanup_vssrc_clarity.md` (vssrc 모호성 발굴 + placeholder 4건 제거)
> 본 세션: Phase 80~83 통합 후 회귀 진단 — 일부는 1회성 race, 일부는 100% 재현. vssrc 가드 시도 후 원복.

---

## 진단 결과 (3건)

### 1. 3명 일반 영상회의 fan-out — 1회성 race (이후 재현 안 됨)

**최초 시험 패턴**:
- alice 만 한 publisher (bob) RTP 못 받음 (`alice.sub.rtp_relayed=50255` ≠ `bob/charlie=100542/100584`)
- alice 화면에 bob video cell 중복 생성 (첫 번째 빈 cell, 두 번째 정상)
- charlie cell 정상 동작

**결정적 데이터 불일치** (admin snapshot):

| 출처 | bob video SSRC | charlie video SSRC |
|------|---------------|---------------------|
| `bob.publisher.stream_map` | `0xAF4F5EB9` | `0x0A76244E` |
| `alice.subscriber_gate.stream_vssrc` | **`0xA7F81ED3`** ❌ | `0x0A76244E` ✅ |

→ **alice 의 SubscriberStream(bob video).virtual_ssrc 만 publisher SSRC 와 불일치**. 다른 5건 (bob 의 alice/charlie, charlie 의 alice/bob, alice 의 charlie) 모두 일치.

**0xA7F81ED3 의 정체**: bob.tracks 에 존재하지 않는 SSRC. alice 클라이언트 receiver.track.id `"bob_a7f81ed3"` 의 hex 부분과 일치. **출처 추적 미완**.

**재현 시도 결과**:
- 직후 동일 시험 (동일 코드, 동일 spawn 시퀀스) → 모든 매핑 정상 (`alice.sub=bob.sub=charlie.sub` 두 명분량)
- 3 round 반복 (2명 → 3명 단계) → 6/6 정상
- → **회귀가 1회성 race**. 재현 안 되면 진단 진척 어렵고, 실제 사용에서도 매우 드물 가능성

### 2. 5명 → 4명 leave 후 SubscriberStream 잔존 — 100% 재현 (3/3 라운드)

**시나리오**: 2명 → +1 → +1 → +1 (5명) → 1인 leave (4명)

**관측**:
- leave 한 user 의 publisher 는 sfud `stream_map` 에서 정상 제거
- 그러나 **다른 4명 모두의 SubscriberStream 에 leave 한 user 의 매핑 잔존** (vssrc 그대로 박혀있음)
- 클라이언트 측 transceiver / subscribe PC 상태는 정상 (leave 한 user 트랙 제거됨)
- → **server 측 SubscriberStream cleanup 누락**, 클라이언트 영향 없음

**의심 위치**: `handle_room_leave` 의 SubscriberStream cleanup 누락. 같은 방의 다른 subscriber 들에 대해 "이 user 를 publisher 로 가졌던 SubscriberStream 제거" 단계가 빠짐.

### 3. 2명 simulcast fan-out 실패 — 재현 (이번 세션 초기 시험)

**Publisher 정상**:
- alice / bob 둘 다 두 layer (h=640×360, l=160×90) 정상 송출
- server stream_map 에 rid=h, rid=l 정상 등록

**Subscriber 회귀**:
- 양쪽 다 inbound video `[]` (0개)
- cell 은 만들어지지만 track dead
- → **simulcast fan-out 자체 실패**

**의심 위치**: Phase 83 (SimulcastRewriter wrapper 재구성, RtpRewriter 신설). inner+mirror 패턴 회귀 가능성.

---

## vssrc 가드 시도 + 원복 (이번 세션의 코딩 작업, 결국 0)

### 시도

부장님 지적 — "일반은 vssrc 발급할 이유가 없자나":

`helpers.rs:184/210` + `track_ops.rs:511` 의 `let vssrc = p.ensure_simulcast_video_ssrc()` 무조건 호출에 simulcast 가드 추가:

```rust
let snapshots = p.peer.publisher_streams_snapshot();
let vssrc = if snapshots.iter().any(|t|
    t.simulcast && t.kind == TrackKind::Video && t.duplex != DuplexMode::Half
) {
    p.ensure_simulcast_video_ssrc()
} else {
    0
};
```

다른 4 호출처 (`publisher_stream.rs:479`, `ingress.rs:389/632/890`, `track_ops.rs:838`) 는 이미 simulcast 분기 안에 있어 수정 안 함.

### 원복 — 이름과 동작 불일치 발견

부장님 의문: "근데, 이게 vssrc 발급이야?"

`participant.rs:989` read 결과:
```rust
pub fn ensure_simulcast_video_ssrc(&self) -> u32 {
    self.peer
        .first_stream_of_kind(TrackKind::Video)
        .map(|t| t.ensure_virtual_ssrc())
        .unwrap_or(0)
}
```

**실제 동작**:
- "발급 로직" 아님. 첫 video PublisherStream 의 `virtual_ssrc` atomic 필드에 lazy CAS 할당
- simulcast 검사 0 — 일반 video 라도 호출되면 박힘
- video track 없으면 0 반환

**중요**: `vssrc` 변수는 어차피 `if t.simulcast && t.kind == Video` 분기에서만 사용. 일반 video 분기에서는 `t.ssrc` 사용. **박혀있어도 unused side effect**. 회귀 직접 원인 아님.

→ 가드 추가의 전제(=발급 막기) 가 무너짐 → 3 위치 모두 원복. **이번 세션 코드 변경 = 0**.

---

## 부장님 일침 패턴 (반복 위반)

이번 세션 핵심 학습. 자동 압축 후에도 같은 패턴 반복:

1. **분석 1원칙 위반** — 텔레메트리/스냅샷 우선 안 보고 서버 로그/코드부터 뒤짐
2. **변수 격리 실패** — 시뮬과 일반 시험 환경 섞은 채로 분석
3. **단정 반복** — 서버 회귀로 단정 후 클라/QA 측 검증 안 함 ("진짜 서버 문제 맞아?")
4. **vssrc 드립** — 특정 hex 값 들고 가서 시선 분산 ("vssrc 드립하지 말고")
5. **렌더링 안 보고 데이터만 봄** — 화면 상태 확인 누락 ("렌더링 문제있는데. 똑바로 안해")
6. **leave() 정상 경로 무시** — `__qa__.reset()` (disconnect) 만 사용해서 zombie 누적 ("leave 하면 되는거 아냐? 그것도 시험의 일부 아냐?")
7. **함수 이름만 보고 단정** — `ensure_simulcast_video_ssrc` 의 실제 구현 read 안 하고 "발급 로직" 으로 단정 후 수정 강행
8. **원복 결심 못 함** — 전제 무너졌을 때 즉시 원복 안 하고 다른 분석으로 옆길 ("니 생각좀 해. 방금전에 고친게 발급 하는 로직이 아니라메. ... 원복해야지!")

---

## 시험 인프라 학습

`__qa__.reset()` vs `handle.leave()`:

| 메서드 | 서버 동작 | cleanup 시간 |
|---|---|---|
| `engine.leaveRoom()` (= `handle.leave()`) | ROOM_LEAVE op=12 → 즉시 `handle_room_leave` | **즉시** |
| `engine.disconnect()` (= `handle.disconnect()` ⊆ `__qa__.reset()`) | WS 끊김 → SESSION_DISCONNECT 통보만 | zombie 경로 **20초** |

라운드 정리 시 `leave()` 우선 호출 → 1.5초 대기 → 그 뒤 `__qa__.reset()` (iframe DOM 정리) 패턴이 정석. zombie reaper 기다릴 필요 없음.

---

## 미해결 회귀 (next-session 인계)

| 회귀 | 재현 | 우선순위 |
|---|---|---|
| 5명 → 4명 leave 후 SubscriberStream 잔존 | 100% (3/3) | 높음 — `handle_room_leave` 의 cleanup 누락 추정 |
| 2명 simulcast fan-out 실패 | 재현 | 높음 — Phase 83 SimulcastRewriter 회귀 의심 |
| 3명 일반 alice ← bob fan-out fail | 1회성 race | 낮음 — race window 격리 필요 |

**다음 세션 진입점 후보**:

A. `handle_room_leave` 코드 read → SubscriberStream cleanup 누락 위치 확정 후 수정
B. SimulcastRewriter wrapper read (`participant.rs:188-273`, `rtp_rewriter.rs`) → 2명 시뮬 회귀 추적
C. 부장님 다른 각도

---

## 오늘의 기각 후보

- **helpers.rs / track_ops.rs:511 vssrc lazy 가드 추가** — `ensure_simulcast_video_ssrc()` 가 발급 로직이 아니라 첫 video PublisherStream.virtual_ssrc 의 lazy CAS 할당. 가드 추가의 전제 무너짐. 3 위치 원복 완료. 코드 변경 0.

---

## 오늘의 지침 후보

- **함수 이름만 보고 단정 금지** — read 후 행동. `ensure_simulcast_video_ssrc` 의 misleading 이름이 좋은 사례.
- **결재 받은 작업이라도 전제 무너지면 즉시 원복** — 옆길로 새지 말 것. 부장님이 "수정한거 원복해야 되는거 아냐?" 물었을 때 즉시 답이 "맞습니다, 원복" 이어야 함.
- **분석 1원칙 우선** — `METRICS_GUIDE_FOR_AI.md` + 스냅샷부터. 서버 로그/코드부터 뒤지지 말 것. 이건 거의 매 세션 반복 위반.
- **렌더링 확인 = 시험의 일부** — 데이터 검증과 화면 검증 둘 다. 한쪽만 봐서 결론 내지 말 것.
- **시험 라운드 정리도 정상 경로로** — `leave()` 가 정석, `disconnect()`/`reset()` 은 zombie 경로. "그것도 시험의 일부".

---

## 메모리 outdated 정정 (다음 세션에서 환류)

PROJECT_MASTER 메모리에 아래 내용이 stale:

- 메모리 #26 "Phase 0, 1, 4, 5 complete (Phases 71–75, 240 tests passing). Phase 2.2 complete..." — **실제로는 Phase 80~83 까지 진행** (Phase 80: SubscriberStream + Index Phase 3 / Phase 81: ingress fanout 단일점 / Phase 82: SWITCH_DUPLEX 폐기 + PUBLISH_TRACKS hot-swap / Phase 83: Rewriter 일반화 ① RtpRewriter + Ptt/Simulcast wrapper)
- "Next: Phase 2.5 — RtpStream struct deprecation" — **이미 Phase 2.5/2.6 완료** (stream_map.rs 헤더 주석 확인됨)

다음 세션 부장님 결재 받아 메모리 갱신 (`memory_user_edits` 도구로 메모리 #26 교체).

---

*author: kodeholic (powered by Claude)*
