# Phase ①.5 inner SSRC 정합 보강 — 일반 commit 완료

> 작성: 2026-05-09
> 위치: `context/202605/20260509_phase1_5b_inner_ssrc_cleanup.md`
> 선행: `20260502b_phase1_5_complete.md` (5/2 한방 commit, push 됨)
> 후속: 본 cleanup 일반 commit (push 됨)

---

## 요약 (1줄)

부장님 grep 한 번이 5/2 commit 의 부분 적용 영역 (PttRewriter inner 가 universal SSRC default 호출) 잡음 → 3 파일 ~12L 코드 + ~10L 주석 cleanup → wire-level per-room SSRC 정합 회복.

---

## 발단 — 부장님 grep

```bash
$ grep -rn PTT_AUDIO_SSRC crates
crates/oxsfud/src/room/slot.rs:97:    /// 가상 SSRC = `config::PTT_AUDIO_SSRC` / `PTT_VIDEO_SSRC` 컴파일 상수 (영원 불변, `Room::new` 가 주입).
crates/oxsfud/src/room/subscriber_stream.rs:211:    ///   - ViaSlot          → `config::PTT_AUDIO_SSRC` / `PTT_VIDEO_SSRC` (가상, 영원 불변)
crates/oxsfud/src/room/room.rs:66:        // universal 상수 (PTT_AUDIO_SSRC / PTT_VIDEO_SSRC) 폐기 — cross-room affiliate
crates/oxsfud/src/room/ptt_rewriter.rs:103:        Self::new(crate::config::PTT_AUDIO_SSRC, TS_GUARD_GAP_AUDIO, false, 48)
crates/oxsfud/src/config.rs:85:pub const PTT_AUDIO_SSRC: u32 = 0x50_54_54_A1;
```

부장님 질문 한 줄: "**이거 이 세션에서 작업한건가?**"

→ 김대리가 5/2 세션 파일 (`20260502b_phase1_5_complete.md`) 직접 read 하고 변경 영역 7 파일 list 확인 → **`ptt_rewriter.rs` / `slot.rs` / `subscriber_stream.rs` 모두 본 세션 변경 영역 외**. 5/2 세션 파일 §"잔여" §1 에 박힌 표현 발견:

> **config.rs PTT_AUDIO_SSRC / PTT_VIDEO_SSRC / PTT_AUDIO_MID / PTT_VIDEO_MID 제거** — **사용 0 추정**. 별도 cleanup PR (warning 발견 시 즉시 처리)

→ "사용 0 추정" 이 잘못. 실제로는 `ptt_rewriter.rs::new_audio/new_video` 의 default 호출에서 사용 중.

---

## 본질적 결함

### Slot 자료구조 vs PttRewriter inner 불일치

```rust
// slot.rs::new_audio (5/2 commit 영역, 4/28 결정에서 이미 박힘)
pub fn new_audio(virtual_ssrc: u32, room_id: RoomId) -> Self {
    Self {
        kind: SlotKind::Audio,
        virtual_ssrc,                        // ⭐ per-room random ✓
        room_id,
        rewriter: PttRewriter::new_audio(),  // ⭐ universal SSRC ✗ (인자 안 넘김)
        ...
    }
}

// ptt_rewriter.rs::new_audio (5/2 commit 영역 외, 옛 default)
pub fn new_audio() -> Self {
    Self::new(crate::config::PTT_AUDIO_SSRC, TS_GUARD_GAP_AUDIO, false, 48)
}
```

→ **Slot.virtual_ssrc** (per-room random) ≠ **Slot.rewriter.inner.virtual_ssrc** (universal `0x50_54_54_A1`).

RTP rewrite 시 `PttRewriter::rewrite_in_place` 가 inner.virtual_ssrc 박음 → **wire-level SSRC 가 universal 그대로**.

설계서 `20260502_phase1_5_cross_room_ptt_slot.md` §1.2 의 의도:
> 두 방 발언이 같은 buffer 에 들어가면 인터리빙 깨짐
> → vssrc 자연 키 = `(room_id, kind)`. **방마다 다른 vssrc**

→ 의도는 wire-level per-room. 그러나 실제 코드는 wire-level universal.

### 6/6 단일방 스모크 통과의 의미

```
✓ spawn           {"alice":"ready","bob":"ready"}
✓ client_data     isMapLike=true size=1 hasAudio=true hasVideo=true
✓ track_id        audio="ptt-qa_test_01-audio" video="ptt-qa_test_01-video"
✓ press           alice=talking bob=listening
✓ release         alice=idle bob=idle
✓ cleanup         _pttPipes.size=0
```

**단일방 = Slot 1개** → universal SSRC 이어도 충돌 0 → 동작 OK. 클라가 mid + track_id 매칭이라 SSRC 가 universal 이어도 단일방 동작 OK. **검출 불가 영역 = cross-room 시나리오 (두 방 affiliate + 동시 발언)**.

→ 6/6 통과를 "회귀 0건 확정" 으로 결론 내린 김대리 미스.

---

## 변경 영역 (3 파일)

| # | 파일 | 변경 |
|---|------|------|
| A | `ptt_rewriter.rs::new_audio/new_video` | 인자로 `virtual_ssrc: u32` 받기 시그너처 변경 |
| B | `slot.rs::new_audio/new_video` | `PttRewriter::new_audio(virtual_ssrc)` 인자 전달 |
| C-1 | `slot.rs:97` 주석 | "config::PTT_AUDIO_SSRC ... 영원 불변" → "Room::new 의 alloc_ptt_vssrc() per-room random alloc (Phase ①.5, 2026-05-02)" |
| C-2 | `subscriber_stream.rs:211` 주석 | "ViaSlot → PTT_AUDIO_SSRC ... 영원 불변" → "ViaSlot → Slot.virtual_ssrc (Phase ①.5 per-room random alloc)" |
| C-3 | `ptt_rewriter::rand_u32` 주석 | "Axiom 2 Universal SSRC ... 잔재" → "Phase ①.5 에서 per-room random 으로 회귀, alloc_ptt_vssrc() 가 getrandom 직접 호출. 이 함수는 경유 안 함" |

**누계 ~12L 코드 + ~10L 주석**.

### 핵심 동작 결과

```
Room::new 시점:
  alloc_ptt_vssrc() → random u32
    ↓
  Slot::new_audio(virtual_ssrc, room_id)
    ↓ Slot.virtual_ssrc 박힘
    ↓ 같은 인자 전달
  PttRewriter::new_audio(virtual_ssrc)
    ↓
  PttRewriter::new(virtual_ssrc, ...)
    ↓ inner RtpRewriter.virtual_ssrc 박힘

→ Slot.virtual_ssrc == Slot.rewriter.inner.virtual_ssrc (3중 보유 일관성)
→ Wire-level RTP SSRC = per-room random (설계 §1.2 의도 정합)
```

---

## 회귀 검증

### `cargo check` + `cargo test`

부장님 빌드/테스트 OK 보고:
- **252 tests PASS** 회귀 0
- 빌드 깨짐 0 (호출처는 slot.rs 만, test 코드 없음 사전 확인)

### 단일방 동작 보존

- universal 1개 → per-room random 1개: 단일방 = Slot 1개 → 충돌 0
- 효과 동일

### Cross-room 동작 보장

- 방 X 의 Slot.audio.virtual_ssrc = random_X
- 방 Y 의 Slot.audio.virtual_ssrc = random_Y (다른 값)
- subscriber 가 두 방 affiliate → 두 RTP 가 다른 SSRC = 다른 stream
- WebRTC NetEQ 가 SSRC 별 jitter buffer → 두 방 발언 분리
- = 설계 §1.2 의도 정합

---

## 김대리 행동 학습

### ⭐⭐⭐⭐⭐ "사용 0 추정" 박지 말 것

5/2 세션 파일 §"잔여" §1 에:
> "config.rs PTT_AUDIO_SSRC ... 제거 — **사용 0 추정**"

이 표현이 잘못. 실제로는 `ptt_rewriter.rs::new_audio` 의 default 호출에서 사용 중. **grep 검증 의무**:

- `grep -rn PTT_AUDIO_SSRC crates` 1초 작업
- 사용처 0 확인 후 "사용 0 박음" 표현
- 추정 박는 순간 회귀 위험

### ⭐⭐⭐⭐⭐ 단일방 스모크의 한계

6/6 통과 → "회귀 0건 확정" 결론 내린 미스. 본 PR 의 본질 (cross-room PTT slot 일반화) 검증을 단일방 시험으로 한 건 처음부터 부적격.

**검증 영역과 검출 가능 회귀의 매칭 의무**:
- 단일방 시험 = 자료구조 표면 회귀만 검출
- cross-room 시험 = wire-level 정합 + multi-channel mixing 검출

본 PR 처럼 cross-room 영역 PR 은 **cross-room 시험이 회귀 0 검증의 충분 조건**. 단일방으로는 부족.

### ⭐⭐⭐⭐ wire-level 자료구조 정합 = 표면만 보지 말 것

본 미스의 근원은 "Slot.virtual_ssrc 가 per-room 박혔다" 표면만 본 것. 실제 RTP rewrite 시 inner 가 박는 SSRC 까지 전파 검증 안 함.

**자료구조 정합 검증 영역 (wire-level 까지)**:
1. 조직 구조 (Slot, PttRewriter, RtpRewriter) — 객체 차원
2. 메타데이터 (track_id, mid) — 시그널링 차원
3. RTP rewrite 경로 (inner.virtual_ssrc) — wire 차원

3개 모두 일관성 검증 의무.

### ⭐⭐⭐ 부장님 grep 한 번의 가치

본 세션 흐름:
1. 김대리: "Phase ①.5 회귀 0건 확정"
2. 김대리: 6/6 스모크 시험 통과 보고
3. 김대리: "push 추천"
4. 부장님: `grep -rn PTT_AUDIO_SSRC crates` 한 번
5. 김대리 보고 3개 모두 무너짐

**보고 신뢰도 의심**. 김대리가 "확정" 표현을 박는 순간 부장님은 검증 동기 잃음. 김대리는 "검증 영역 명시 + 검출 가능 회귀 명시 + 그 외 영역 미검증" 표현이 정답.

### ⭐⭐ "warning 확인 후 제거" 패턴 경계

5/2 세션 파일 §"다음 세션 entry" 의:
> "config.rs cleanup — PTT_AUDIO_MID/VIDEO_MID/AUDIO_SSRC/VIDEO_SSRC unused warning 확인 후 제거"

이 패턴이 잘못. `#[allow(dead_code)]` 붙은 함수 (예: `ptt_rewriter::rand_u32`) 또는 default 호출 (예: `PttRewriter::new_audio()`) 는 unused warning 안 뜨. **명시 grep** 이 정답.

---

## 잔여 영역 (별도 결재)

### D. config.rs PTT 상수 4개 폐기

| 상수 | 사용처 검증 | 폐기 결정 |
|------|------------|----------|
| `PTT_AUDIO_SSRC` | A+B 적용 후 0 추정 | 부장님 grep 후 결정 |
| `PTT_VIDEO_SSRC` | A+B 적용 후 0 추정 | 부장님 grep 후 결정 |
| `PTT_AUDIO_MID` | 별도 검증 의무 | 검증 후 결정 |
| `PTT_VIDEO_MID` | 별도 검증 의무 | 검증 후 결정 |
| `PTT_AUDIO_RTX_SSRC` | Phase 2 RTX 대비 | **유지** (0502b 명시) |
| `PTT_VIDEO_RTX_SSRC` | Phase 2 RTX 대비 | **유지** (0502b 명시) |

→ 부장님 grep 의뢰 후 결과 따라 다음 cleanup commit 진입.

### E. Cross-room 시험 (운영 중 영역)

본 cleanup 후 cross-room 시나리오 시험 의무. 옵션:
- 새 자동 실행 페이지 (`test_phase15_crossroom.html`) 작성
- 기존 시나리오 (dispatch / voice_radio) 에 affiliate 흐름 추가
- QA_GUIDE 에 cross-room case 등록

→ 부장님 결재 후 진입.

---

## 다음 세션 entry

부장님 한 줄로 김대리 자동 회복:
- "D 진행" → config.rs cleanup PR (grep 의뢰 부터)
- "cross-room 시험" → test_phase15_crossroom.html 작성
- "다음 우선순위" → ③ STALLED 후속 또는 다른 영역

---

*author: kodeholic (powered by Claude)*
