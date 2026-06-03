# 작업 지침 — SubscriberStream.virtual_ssrc → vssrc 어휘 정합 (0603 식별 계층 마무리)

> 작성: 김대리 / 결재: 부장님 ("정석대로 해") / 구현: 김과장
> 토픽: subscriber_vssrc_align · 일자: 2026-06-03(c) · 직전: 20260603b_naming_cleanup(commit 완료) / 0603 식별 계층 A·B(`8b0627a`/`208a498`)

---

## §0 의무 점검

- [ ] `PROJECT_SERVER.md` 식별 계층 절(3평면 track_id/vssrc/실ssrc) 통독
- [ ] **시작 전 `cargo test` GREEN 수 실측** — 동작 변경 0이므로 종료 시 같은 수 유지가 유일 검증
- [ ] `git status` clean
- 본 작업은 **단일 필드 rename + 읽는 자리 + 주석만**. 로직/제어흐름/자료구조 변경 절대 금지.

---

## §1 컨텍스트

0603 식별 계층 재설계가 egress SSRC 평면을 **`vssrc`로 통일**하면서 publisher측(`PublisherStream.vssrc`/`vssrc_load`/`find_stream_by_vssrc`/`find_publisher_track_by_vssrc`/`find_publisher_by_simulcast_vssrc`) + 인덱스(`SubscriberStreamIndex.by_vssrc`/`with_removed_by_vssrc`) + 조회(`find_subscriber_stream_by_vssrc`)는 전부 정리했다. 그런데 **`SubscriberStream.virtual_ssrc` 필드 하나만 옛 이름으로 남았다** — 미아.

### 어휘 체계 직교 (정석의 근거)

같은 SSRC 값이라도 **관점에 따라 이름이 다른 게 정석**이다. 두 체계가 직교한다:

| 관점 | 어휘 | 의미 | 해당 자료 |
|---|---|---|---|
| **식별 평면** | `vssrc` | subscriber가 **받는** egress SSRC 값 (방향/평면) | `PublisherStream.vssrc`, `SubscriberStreamIndex.by_vssrc`, `SubscriberStream.virtual_ssrc`(← 미아) |
| **rewriter 토대** | `virtual_ssrc` | 원본을 바꿔 넣는 **가상** SSRC (변환 대상/출력) | `RtpRewriter`/`PttRewriter`/`SimulcastRewriter.virtual_ssrc`, `Slot.virtual_ssrc` |

`SubscriberStream.virtual_ssrc`는 **subscriber 수신 관점(egress 평면)인데 rewriter 어휘(`virtual`)를 빌려 쓴 것**이 오류다. 필드 주석 자체가 자백: "subscriber SDP에 노출되는 SSRC ... Direct+non-sim → publisher 원본 SSRC 그대로(**가상 아님**) ... 필드 이름이 모든 경로에서 virtual 의미를 보장하지 않음." non-sim에선 rewrite조차 안 하고 원본 ssrc 그대로라 `virtual`이 명백히 거짓.

→ `SubscriberStream.virtual_ssrc` → `vssrc` (평면 어휘로 정합).

---

## §2 결정된 사항

### 대상 (vssrc 로 rename)

- **`SubscriberStream.virtual_ssrc`** 필드 → `vssrc`
- `SubscriberStream::new` 파라미터 `virtual_ssrc` → `vssrc`
- 필드 읽는 자리 전부 (grep 위임 — §4):
  - `subscriber_stream_index.rs`: `with_added`(`stream.virtual_ssrc`), `with_removed_by_vssrc`(`x.virtual_ssrc`/`s.virtual_ssrc`), `with_removed_by_mid`(`s.virtual_ssrc`) + doc("virtual SSRC" 표현)
  - `subscriber_stream.rs`: `::new` 본문 `SrStats::new(virtual_ssrc, ..)` + 필드 주석
  - `peer.rs`: `add_subscriber_stream` 파라미터/전달, `find_subscriber_stream_by_vssrc` 내부
  - `track_ops.rs`: `record_stalled_snapshot`의 `sub_stream.virtual_ssrc` (다자리)
  - `egress.rs`: `run_egress_task`의 SubscriberStream 경로
  - `ingress_subscribe.rs` / `ingress_rtcp.rs`: `find_subscriber_stream_by_vssrc` 결과 사용 자리에서 `.virtual_ssrc` 접근 있으면

### 비대상 (rewriter 토대 어휘 — 손대지 말 것) ⚠️

- `RtpRewriter.virtual_ssrc` / `PttRewriter` / `SimulcastRewriter.virtual_ssrc` — rewriter 관점("출력 가상 SSRC"). `virtual` 의미 정확.
- `Slot.virtual_ssrc` (필드 + `virtual_ssrc()` getter) — 주석 명시대로 `RtpRewriter.virtual_ssrc`와 동일값(rewriter 토대). PTT slot 발급 가상 SSRC.
- 이들을 vssrc로 바꾸면 **관점 어휘를 뭉개는 무지성 통일** = 정석 아님. 기각(§7).

### 주석 보강

- `SubscriberStream.vssrc` 필드 doc: "egress SSRC 평면값(식별 계층 vssrc 평면). non-sim=원본 ssrc, sim/PTT=rewriter 출력 가상값 — *어느 경우든* subscriber가 수신하는 SSRC. publisher측 `PublisherStream.vssrc`의 subscribe 등록 시 복사본."

---

## §3 결정 (확정 — 미결 없음)

- 대상 = `SubscriberStream.virtual_ssrc` → `vssrc` **단일 필드** + 읽는 자리. rewriter/Slot 비대상.
- 정지점 = Phase 끝 1개.

---

## §4 단계별 작업 (단일 Phase, ★정지점 1: 끝)

> 동작 0. 종료 시 `cargo test` GREEN 수 불변 확인. 컴파일 통과 = 미반영 자리 정합 완료(컴파일러가 필드 rename 미반영을 전부 잡음).

1. `SubscriberStream` 구조체 필드 `virtual_ssrc` → `vssrc` + `::new` 파라미터.
2. `cargo build` → 컴파일 에러로 뜨는 모든 읽는 자리 정합 (필드 접근이라 컴파일러가 전수 안내).
3. **grep 분리 주의**: `virtual_ssrc` grep 시 **자료구조 타입으로 구분** — `SubscriberStream`/`SubscriberStreamIndex` 맥락만 바꾸고, `*Rewriter`/`Slot`/`RtpRewriter` 맥락은 **건드리지 말 것**. `.virtual_ssrc` 표기가 같아도 소유 타입이 다름.
   - 바꿈: `sub_stream.virtual_ssrc`, `stream.virtual_ssrc`(index 안 `Arc<SubscriberStream>`), `SubscriberStream::new(.., virtual_ssrc, ..)`
   - 유지: `slot.virtual_ssrc` / `slot.virtual_ssrc()` / `fwd.rewriter.virtual_ssrc` / `SimulcastRewriter::new`의 `virtual_ssrc` / `RtpRewriter` / `PttRewriter`
4. 주석/doc 정합 (§2 주석 보강 + index doc "virtual SSRC" → "vssrc").
5. **검증**: `cargo build` + `cargo test` GREEN 불변. → **정지점: commit + 부장님 보고 + GO**.

---

## §5 변경 영향 범위

- **domain/**: `subscriber_stream.rs`(필드+new+주석), `subscriber_stream_index.rs`(읽는 자리+doc), `peer.rs`(add_subscriber_stream/find_subscriber_stream_by_vssrc)
- **signaling/handler/**: `track_ops.rs`(record_stalled_snapshot)
- **transport/udp/**: `egress.rs`(run_egress_task), `ingress_subscribe.rs`/`ingress_rtcp.rs`(find_subscriber_stream_by_vssrc 결과 .virtual_ssrc 접근 시)
- **비대상**: `slot.rs`, `ptt_rewriter.rs`, `rtp_rewriter.rs`, SimulcastRewriter(subscriber_stream.rs 안이지만 rewriter 영역) — 손대지 말 것
- **클라(oxlens-home) wire 영향 = 0** — 서버 내부 필드명만. wire SSRC 값·opcode 불변.

---

## §6 운영 룰

1. **정지점**: Phase 끝 1개.
2. **동작 0 불변식**: `cargo test` GREEN 수 = 시작 실측값. 변하면 중단·보고.
3. **추가 변경 금지**: rewriter/Slot virtual_ssrc 손대지 말 것 (§2 비대상). 로직 변경 금지.
4. **2회 실패 시 중단**.
5. **rename ≠ 동작**: rename이 제어흐름/자료를 바꿔야 하면 멈추고 보고.

---

## §7 기각 접근법

- **`egress_ssrc`로 rename** — egress가 의미는 명확하나, 일관성 위해 publisher측 vssrc + by_vssrc 인덱스 + 식별 계층 표까지 전부 역명명하는 대공사. 0603이 vssrc로 정리한 걸 거꾸로 되돌림. 기각.
- **rewriter/Slot.virtual_ssrc까지 vssrc 통일** — rewriter 토대 어휘(출력 가상 SSRC)를 평면 어휘로 뭉개는 무지성 통일. 관점 직교 무시. 기각.
- **subscriber만 vssrc, 나머지 안 봄** — 이미 publisher/인덱스/조회는 vssrc라 추가 작업 없음. 본 작업이 곧 그것.

---

## §8 산출물

- 코드: `SubscriberStream.virtual_ssrc` → `vssrc` + 읽는 자리 + 주석
- 완료 보고: `~/repository/context/202606/20260603c_subscriber_vssrc_align_done.md` — 변경 파일·라인, 시작/종료 `cargo test` GREEN 수(불변), rewriter/Slot 비대상 준수 확인, 클라 wire 무영향
- master 반영: PROJECT_SERVER.md 식별 계층 표의 "SubscriberStream.virtual_ssrc로 복사" 표현 → "SubscriberStream.vssrc로 복사" 현행화 (적용은 김대리 판단)

---

## §9 시작 전 확인

- [ ] `cargo test` GREEN 수 실측·기록
- [ ] `git status` clean (naming_cleanup commit 이후 상태)
- [ ] 어휘 직교 숙지 — vssrc(평면) vs virtual_ssrc(rewriter). **타입으로 grep 분리.**

---

## §10 직전 작업 처리

- 0603 식별 계층 A·B + 20260603b naming_cleanup(commit 완료) 직후. 본 작업은 그 식별 계층 vssrc 통일의 **마지막 미아 청산**.
- naming_cleanup이 손댄 `subscriber_stream*.rs`는 A1(virtual_ssrc) 제외로 비대상이었음 — 본 작업이 그 제외분을 vssrc 방향으로 처리(egress_ssrc 아님).

---

*author: kodeholic (powered by Claude)*
