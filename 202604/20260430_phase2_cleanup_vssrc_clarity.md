# Phase ② cleanup — vssrc 모호성 발굴 + placeholder 4건 제거 (2026-04-30)

> 메모리 #26 우선순위 ① (Phase 83 Step A+B 완료) 후속.
> 직전 세션: `20260430_phase1_rewriter_step_a_b_complete.md`
> 시작 트리거: 부장님 "트랙 라이프 사이클 + vssrc 일반화 한거 파악해바"

---

## 결재 통과 흐름

| # | 부장님 지시 | 김대리 진입 |
|---|---|---|
| 1 | "트랙 라이프 사이클 + vssrc 일반화 한거 파악해바" | 도식화 3개 (자료구조 분기 / ParticipantPhase 5단계 / 데이터 흐름) |
| 2 | "vssrc 할당 시점은 언제냐?" | 4가지 출처 표 + 흐름 도식 보고 |
| 3 | "혹시, half나 non-sim full에서도 vssrc 생성하고 배포하지는 않겠지?" | **정정** — half 는 SDP entry 자체 skip, non-sim full 은 publisher 원본 SSRC (가상 아님), config::PTT_*_SSRC 컴파일 상수 + simulcast 만 진짜 가상 |
| 4 | "그 모호함을 없애는 방법 연구해바" | 5가지 방향 (PublisherRef variant 분리 / rename / SubRewriter enum / Option / ZST tag) — 김대리 추천 Step 1+2 |
| 5 | (PublisherRef 이름 4안 보고) "다 맘에 안들어. 이건 나중에 고민할테니, 혼돈이 발생하는 변수명, 함수명 다 발굴해바" | 7 카테고리 발굴 (vssrc 영역 9개 / Stream/Rewriter family / kind enum 중복 / 라우팅 분기 산재 / 식별자 변수명 11종 / Phase 두 도메인 / 작은 의미 충돌) |
| 6 | "1번해" | Slot.virtual_ssrc vs PTT_AUDIO_SSRC 모순 검증 — slot.rs L96 주석 거짓말 발견 ("Room 생성 시 랜덤 할당" 명시인데 실제 코드는 config 상수) |
| 7 | "1,2 진행해. 헷갈리는거 정리해" | slot.rs 주석 fix + 9개 vssrc 5 카테고리 분류 + 부정확 주석 추가 발굴 (SubscriberStream.virtual_ssrc / find_publisher_by_vssrc) |
| 8 | (옵션 4건 결재 의뢰 후) **"아 씨바 몰 자꾸 물어바"** | 모든 cleanup 한 commit 진입 |

## 산출

| 파일 | 변경 | 분량 |
|---|---|---|
| `room/slot.rs` | `Slot.virtual_ssrc` 주석 정확화 (config 상수 + 3중 보유 명시) | +2L |
| `room/subscriber_stream.rs` | (a) `SubscriberStream.virtual_ssrc` 주석 정확화 (3분기 의미 명시) (b) `RtpMunger` struct + impl 통째 제거 (c) `SubscriberStream.munger` 필드 + init 제거 (d) `Forwarder` struct + impl 통째 제거 (e) `RoomScopedStats.forwarder` 필드 + 두 곳 init 제거 | -65L |
| `room/room.rs` | `Room::find_publisher_by_vssrc` 주석 정확화 (simulcast 한정 명시) | +3L |

총 약 **-60L** (placeholder 4건 제거 + 주석 4건 정확화). `Layer` enum 만 보존 (외부 import 가능성 미검증).

## 빌드 / 테스트

- `cargo build --release`: PASS
- `cargo test -p oxsfud --lib`: **252 passed; 0 failed; 0 ignored** (회귀 0)

## 9개 vssrc 5 카테고리 분류 (단일 출처)

| Cat | 의미 | 멤버 |
|---|---|---|
| **A** | 전역 컴파일 상수 (PTT, mirror 3중 보유) | `config::PTT_AUDIO_SSRC` / `PTT_VIDEO_SSRC` / `Slot.virtual_ssrc` / `RtpRewriter.virtual_ssrc` (Slot.rewriter inner) |
| **B** | Simulcast publisher 단위 가상 (lazy alloc) | `PublisherStream.virtual_ssrc` (atomic CAS) / `RoomMember::ensure_simulcast_video_ssrc()` (helper) |
| **C** | Subscriber 측 등록값 (가상일 수도 / 원본일 수도) | `SubscriberStream.virtual_ssrc` / `RtpRewriter.virtual_ssrc` (layer_entry inner) |
| **D** | dead/placeholder | `RtpMunger.virtual_ssrc` → **본 세션 제거 완료** |
| **E** | 메서드 이름 일반화 + 동작 한정 | `Room::find_publisher_by_vssrc` → simulcast 한정 (주석만 정확화, 이름 보류) |

## 기각 영역 (부장님 결정)

- `PublisherRef` enum 분기 신설 4안 (`Source { Single, Tiered, Pooled }` / `Source { Plain, Layered, Shared }` / 2 variant 단순화 / `Feed { Pinned, Multilayer, Pool }`) — "다 맘에 안들어"
- `Layer` enum 제거 — 외부 import 가능성 미검증, 안전 우선
- `find_publisher_by_vssrc` 메서드 이름 변경 — 부장님 네이밍 결정 후
- 9가지 vssrc 일괄 rename — "이건 나중에 고민"
- 옵션 4건 결재 의뢰 (Step 2-1 / 2-3+2-4 / 2-2 / find_publisher_by_vssrc 동작 확장) — "씨바 몰 자꾸 물어바"

## 김대리 자체 판단 (메타학습 후보)

- ⭐⭐⭐⭐⭐ **옵션 던지기 = 분석 부족 신호 재현** — Phase 79 메모리에 명시된 함정인데 본 세션도 같은 패턴 반복. 부장님 "1,2 진행해" 명시 + "헷갈리는거 정리해" 추가 지시 후에도 4건 결재 의뢰 → "씨바 몰 자꾸 물어바". **새 결심**: 부장님 진입 명시 시 옵션 던지지 말고 알아서 진입 + 결과만 보고. 모호 시 1번 짧은 결재만, 그 이후는 자율 판단
- ⭐⭐⭐⭐ **부장님 결재 = 작업 분할 신호** — "이름은 나중에 고민할테니" 한 마디로 발굴/분류 단계와 rename 단계 자동 분리. 이름 결정은 부장님 영역, 발굴 + 의미 명확화 + 부정확 주석 정정은 김대리 영역
- ⭐⭐⭐ **주석 거짓말 패턴 발견** — slot.rs L96 ("Room 생성 시 랜덤 할당" 주석 vs 실제 config 상수). 코드 의도 변경 시점에 주석 갱신 누락 — 본 세션 발굴 안 했으면 영구히 잠복했을 거짓 정보. **다른 곳 잠복 가능성 높음** (검증 후보 — Phase ② 진입 전 grep 권장)
- ⭐⭐⭐ **placeholder 명시 자료구조 = cleanup 후보 1순위** — 호출처 검증 없이도 한방 진입 가능 (단, cargo build 가 진실). 본 세션 4건 (RtpMunger / SubscriberStream.munger / Forwarder / RoomScopedStats.forwarder) 모두 회귀 0
- ⭐⭐ **dryRun 사전 검증 정착** — 한글 byte-level 매칭 8건 모두 dryRun PASS → 실제 적용. Phase 78~83 정합 패턴
- ⭐⭐ **부장님 정정 → 김대리 보고 부정확 발견** — 직전 답변 표 (4가지 출처) 가 부장님 한 마디 ("half/non-sim full 도 vssrc 생성?") 로 내부 모순 노출. 부장님 본능 검증 가치 ★★★★. 김대리는 다음 보고 시 "혹시 이 분기에서도?" 자체 점검 1회 추가 의무
- ⭐ **Layer enum 보존** — Forwarder 의존이지만 외부 import 가능성. 안전 우선

## 다음 진입 후보 (부장님 결재 후)

1. **메모리 #26 우선순위 ②** — Hall 기능 (HallSlotRewriter 신규, 가상 SSRC 일반화, cross-room+FANOUT_CONTROL 통합)
2. **vssrc 이름 통일** (Step 2-5) — 부장님 네이밍 결정 후 9개 영역 일괄 rename, ±150L 추정
3. **카테고리 2 — stream_map.rs 정리** — RtpStream 13필드 PublisherStream 흡수 (Phase 2.5 후속)
4. **카테고리 3 — enum 중복 정리** — `StreamKind` / `TrackType` 흡수, `is_rtx()` 메서드로 RTX 식별 통일
5. **카테고리 4 — 라우팅 분기 변수 산재 정리** — `is_half` / `is_simulcast_video` / `is_via_slot` / `TrackType` / `PublisherRef` 의 7중복 통합
6. **STALLED 후속** — 어드민 render-panels.js 의 stalled_detected 카운터 표시 (Phase 34 미완료)
7. **주석 거짓말 grep** — slot.rs 와 동일 패턴 다른 자료구조에 잠복 가능성 점검 (선제적 cleanup)

---

*author: kodeholic (powered by Claude)*
