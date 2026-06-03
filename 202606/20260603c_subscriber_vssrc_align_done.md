# 완료보고 — SubscriberStream.virtual_ssrc → vssrc 어휘 정합 (20260603c)

지침: `context/claudecode/202606/20260603c_subscriber_vssrc_align.md`
작업: 0603 식별 계층 vssrc 통일의 **마지막 미아 청산** — `SubscriberStream.virtual_ssrc` 단일 필드 → `vssrc`.
**behavior 0** (로직·제어흐름·자료구조 무변경, 단일 필드 rename + 읽는 자리 + 주석).

---

## 결과 요약

| 항목 | 값 |
|------|-----|
| 변경 파일 | 8개 (crates/oxsfud/src) |
| diff | +30 / −29 |
| cargo build | 통과 (0 error) |
| **cargo test** | **시작 204 → 종료 204** (불변 → behavior-0 입증) |
| 클라 wire 영향 | 없음 (서버 내부 필드명만; wire SSRC 값·opcode 불변) |

---

## 변경 내역

### 대상 rename (SubscriberStream 필드 + 읽는 자리)
- `SubscriberStream.virtual_ssrc` → **`vssrc`** (필드 def, subscriber_stream.rs)
- `SubscriberStream::new` 파라미터 `virtual_ssrc` → `vssrc` + 본문 + `SrStats::new(vssrc, ..)`
- `Peer::add_subscriber_stream` 파라미터 `virtual_ssrc` → `vssrc` + `SubscriberStream::new` 전달
- 필드 읽는 자리 (컴파일러가 E0609로 전수 안내 — 12건):
  - `subscriber_stream_index.rs`: with_added(`stream.vssrc`), with_removed_by_vssrc(`x.vssrc`), with_removed_by_mid(`s.vssrc`)
  - `track_ops.rs`: record_stalled_snapshot 3자리(`sub_stream.vssrc`)
  - `tasks.rs`: 2자리(`sub_stream.vssrc`)
  - `admin.rs`: 3자리(`sub_stream.vssrc` / `s.vssrc`) — JSON 출력 **키 문자열**("vssrc"/"stream_vssrc")은 wire라 미변경, 값(필드 접근)만 정합
  - `hooks/stream.rs`: 1자리(`stream.vssrc`)

### 주석/doc 정합 (§2 보강)
- `SubscriberStream.vssrc` 필드 doc: "egress SSRC 평면값... non-sim=원본 ssrc, sim/PTT=rewriter 출력 가상값 — 어느 경우든 subscriber 수신 SSRC. PublisherStream.vssrc 복사본." ("virtual 거짓말 보장 못함" 자백 주석 제거)
- subscriber_stream.rs 모듈 doc, subscriber_stream_index.rs 모듈 doc, publisher_stream.rs:45, track_ops.rs:668, hooks/stream.rs:184 위치주석

---

## 비대상 준수 확인 ⚠️ (핵심 함정 — 타입으로 grep 분리)

`.virtual_ssrc` 표기가 같아도 **소유 타입이 다른** rewriter 토대 어휘는 **전부 미변경**:
- **`SimulcastRewriter.virtual_ssrc`** (subscriber_stream.rs:122/134/137) — 같은 파일 내 다른 구조체, rewriter 출력 가상 SSRC. **유지** ✓
- `RtpRewriter.virtual_ssrc` (rtp_rewriter.rs 5건), `PttRewriter`(ptt_rewriter.rs 17건), `Slot.virtual_ssrc`/`virtual_ssrc()` (slot.rs 12건) — 카운트 원본 불변 = 무손상 ✓
- `room.audio_slot().virtual_ssrc()` / `video_slot().virtual_ssrc()` (track_ops/admin/helpers/ingress_subscribe) — Slot 메서드 호출, 유지 ✓

**검증**: cargo build 시 E0609 에러 12건이 **전부 `SubscriberStream` 타입**에만 발생 (SimulcastRewriter/Slot/Rewriter 0건) → 타입 분리 clean 입증.

---

## 별 토픽 (이번 비대상)
- rewriter/Slot.virtual_ssrc vssrc 통일 = 관점 어휘 뭉개는 무지성 통일 → 기각(지침 §7). 어휘 직교(vssrc=평면 / virtual_ssrc=rewriter 토대) 유지가 정석.

---

## master 반영 제안 (적용은 김대리 판단)
- PROJECT_SERVER.md 식별 계층 표 "SubscriberStream.virtual_ssrc 로 복사" → "**SubscriberStream.vssrc 로 복사**" 현행화

---

## 정지점
CLAUDE.md 작업절차 1단계 — **보고서 작성 완료, 커밋 안 함**. 부장님 diff 검토 후 GO 시 커밋.
behavior-0(테스트 204 불변)이라 회귀시험은 부장님 판단(서버 동작 무영향).
