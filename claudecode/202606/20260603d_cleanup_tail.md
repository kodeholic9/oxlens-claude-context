# 작업 지침 — naming_cleanup 꼬리 청소 (streams 변수 잔존 + dead 확정)

> 작성: 김대리 / 결재: 부장님 / 구현: 김과장
> 토픽: cleanup_tail · 일자: 2026-06-03(d) · 직전: 20260603b naming_cleanup(`fa365f8`) / 20260603c vssrc 정합(`6775b06`)

---

## §0 의무 점검

- [ ] **시작 전 `cargo test` GREEN 수 실측** — 본 작업 behavior 0. 종료 시 같은 수(204 추정) 유지가 유일 검증
- [ ] `git status` clean
- 본 작업 = **변수 rename(#5) + dead 코드 제거(#4)만**. 로직/제어흐름/자료구조 변경 금지.

---

## §1 컨텍스트

20260603b naming_cleanup의 **못 끝낸 꼬리 2건**:

- **#5**: 그룹②(`streams`→`tracks` 변수)가 broadcast만 잡히고 **ingress_publish/ingress_rtcp/egress의 `let streams = peer.publish.tracks.load()`는 누락**. `publish.tracks`는 물리 `PublisherTrackIndex`인데 변수를 `streams`로 받아 2계층 명명(streams=논리/tracks=물리) 위반.
- **#4**: `floor.rs`의 `ping()` 메서드 + `FloorAction::PingOk`/`PingDenied`/`NotPttRoom` variant가 **dead 의심**(FLOOR_PING wire op 폐기 후 호출처/생성처 없을 가능성). naming_cleanup Phase A에서 `Prepared` 죽은 주석은 지웠으나 이 dead 코드 자체는 미확인.

---

## §2 결정된 사항

### #5 — streams 변수 rename (behavior 0, 컴파일러 검증)

| 자리 | 현재 → | 위치 |
|---|---|---|
| `let streams = peer.publish.tracks.load()` 받는 변수 | `streams` → `tracks` | ingress_publish.rs(`process_rtx_packet`/`resolve_stream_kind`/`register_and_notify_stream`의 `streams_for_meta`/`notify_new_stream`), ingress_rtcp.rs, egress.rs(`send_nack_to_publishers`/`send_pli_to_publishers`) |
| `publish.tracks.load().get()` 등으로 얻은 개별 `PublisherTrack` 변수 | `stream` → `track` | 위 파일들 + 핫패스 |

> ⚠️ **건드리지 말 것 (도메인 어휘 — stream/track 변수 아님)**: `StreamKind` enum, `stream_kind`(StreamKind 값), `resolve_stream_kind`/`register_and_notify_stream`/`notify_new_stream` 함수명, `PublisherStream`(논리)/`SubscriberStream` 타입. 이들은 변수가 아니라 도메인 식별자. **`publish.tracks.load()`를 받는 변수와 그 원소(PublisherTrack)만** 교정.

### #4 — dead 확정 후 제거 (조건부)

대상: `floor.rs`의 `ping()` 메서드, `FloorAction::PingOk`/`PingDenied`/`NotPttRoom` variant.

- grep으로 **호출처/생성처 전수 확인**:
  - `ping(` / `.ping()` — `Floor::ping` 메서드 호출처 (floor_ops.rs 등)
  - `PingOk` / `PingDenied` / `NotPttRoom` — variant 생성처 (match arm의 *소비*는 dead 판정과 무관, *생성*이 0인지가 기준)
- **dead 확정(생성·호출 0) → 제거.** 메서드 + variant + 관련 match arm 정리.
- **하나라도 live → 제거하지 말고 *발견_사항*으로 보고만.** (잘못 제거 시 컴파일 에러로 드러나지만, 불확실하면 손대지 않는다.)
- **`last_ping` / `ping_timeout_ms`(check_timers 타이머)는 live — 절대 건드리지 말 것.** FLOOR_PING wire op은 폐기됐어도 이 타이머는 RTP liveness revoke 로직으로 살아 있음. ping() 메서드(요청 핸들러)와 별개.

---

## §3 결정 (확정 — 미결 없음)

- #5 = 변수만, #4 = dead 확정 시 제거(아니면 보고). 정지점 없음(behavior 0 + 컴파일러 검증) — 통합 리뷰.

---

## §4 단계별 작업

> behavior 0. 종료 시 `cargo test` GREEN 수 불변. 컴파일 통과 = 정합 완료.

### Phase A — #5 streams 변수 (정지점 없음)
- ingress_publish.rs / ingress_rtcp.rs / egress.rs의 `streams`(=`publish.tracks.load()`) → `tracks`, 개별 `stream`(PublisherTrack) → `track`.
- §2 ⚠️ 도메인 어휘(StreamKind/resolve_stream_kind/PublisherStream 등) 무차별 치환 금지 — 타입/함수명 보존.
- **검증**: `cargo build` + `cargo test` GREEN 불변.

### Phase B — #4 dead 확정·제거 (정지점 없음)
- grep `ping(`/`PingOk`/`PingDenied`/`NotPttRoom` 전수.
- 생성·호출 0 확정분만 제거. live·불확실분은 *발견_사항* 보고만, 손대지 말 것.
- `last_ping`/`ping_timeout_ms` 보존 확인.
- **검증**: `cargo build`(제거 후 미사용 경고 0) + `cargo test` GREEN 불변.

---

## §5 변경 영향 범위

- **transport/udp/**: ingress_publish.rs, ingress_rtcp.rs, egress.rs (#5)
- **domain/**: floor.rs (#4)
- **클라 wire 영향 = 0** — 서버 내부 변수/dead 제거. opcode·wire 불변.
- 범위 밖 손대지 말 것. 별 발견은 *발견_사항* 보고만.

---

## §6 운영 룰

1. **정지점**: 없음(behavior 0). 통합 리뷰.
2. **동작 0 불변식**: `cargo test` GREEN 수 = 시작 실측값. 변하면 중단·보고.
3. **#4 불확실 시 제거 금지** — dead 확신 없으면 보고만. 잘못된 제거보다 잔존이 안전.
4. **2회 실패 시 중단**.

---

## §7 기각 접근법

- **#5에서 StreamKind/resolve_stream_kind 등 도메인 어휘까지 치환** — 변수 아닌 타입/함수명. 무차별 sed 금지.
- **#4 live·불확실분 추정 제거** — dead 확정(생성·호출 0)만 제거. 의심은 보고.
- **`last_ping`/타이머 제거** — live 로직. ping() 메서드와 혼동 금지.

---

## §8 산출물

- 코드: #5 변수 rename + #4 dead 제거(또는 보고)
- 완료 보고: `~/repository/context/202606/20260603d_cleanup_tail_done.md` — 변경 파일·라인, 시작/종료 `cargo test` GREEN 수(불변), #4 dead 판정 결과(제거/유지+근거)

---

## §9 시작 전 확인

- [ ] `cargo test` GREEN 수 실측·기록
- [ ] `git status` clean (vssrc 정합 commit 이후)
- [ ] #5 도메인 어휘 보존 / #4 last_ping 보존 숙지

---

## §10 직전 작업 처리

- 20260603b/c 직후. 본 작업이 naming_cleanup 그룹②(#5)의 마지막 꼬리 + Phase A dead 확인(#4) 마무리.
- 잔여 백로그(transport 파일명·SCOPE op→AFFILIATE·room.rs dead enum)는 본 작업 비대상 — 결정/별세션 거리.

---

*author: kodeholic (powered by Claude)*
