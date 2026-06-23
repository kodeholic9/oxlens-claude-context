# Subscriber egress_ssrc 단일화 — 설계 결정 (2026-06-20)

> 상태: **대명제 확정 / 결정(C안) 확정 / 영향범위 산정 완료 / 코딩 대기**
> 선행 커밋(별개·완료): `8f1308a` unpublish pid / `a1dc6bc` 전송위반 종료+rate limit 폐지 / `2702aa2` active_speaker

---

## 0. 대명제 (설계 기준)

> **egress_ssrc = "그 stream 속성의 origin"**

| stream 속성 | origin = egress_ssrc | 가변성 |
|------------|---------------------|--------|
| Direct · full · non-sim | publisher `ssrc` | **republish 시 변함** |
| Direct · full · sim | `PublisherStream.vssrc` | 불변 (sim 정책) |
| ViaSlot · half | `Slot.virtual_ssrc` | **per-room 고정** |

→ **origin 이 가변인 건 `Direct/publisher` 하나뿐.** ViaSlot(slot)·sim(vssrc)은 고정.
이 대명제로 보면 갱신 대상이 하나로 수렴한다(§3).

---

## 1. 배경 — 오늘 실증한 문제

ssrc 식별이 2중: ★진실(`PublisherTrack.ssrc`/`PublisherStream.vssrc`/`Slot.virtual_ssrc`)을
☆복사본(`SubscriberStream.vssrc`)이 구독 등록(cold-path)에서 1회 복사.

**증상:** U02 캠 unpub→republish 반복 시
- 통보(`helpers.rs:297` `t.ssrc`)는 **새 publisher ssrc**
- fanout 이 쓰는 `SubscriberStream.vssrc`(☆)는 **옛 복사본** → 어긋남

**근본:** ① remove(`PUBLISH_TRACKS remove`)가 `SubscriberStream` 안 지움(잔존) → ② mid_pool 같은 mid recycle → ③ `add_subscriber_stream`(`peer.rs:1036`) idempotent 가 잔존 stream 반환·새 ssrc 무시 → egress 갱신 차단.

`vssrc` 명명도 오독 유발(non-sim 에선 가상이 아니라 origin ssrc).

---

## 2. 결정 — (C안) egress_ssrc 개명 + producer-push 갱신

1. `SubscriberStream.vssrc` → **`egress_ssrc`** 개명
2. **갱신은 Direct(full non-sim) 의 publisher ssrc 가 republish 로 바뀔 때만**, producer(`PublisherStream`)가
   자기 Direct `subscribers`(Weak Vec) 순회하며 `egress_ssrc` + `by_egress_ssrc` 인덱스 갱신(producer-push)
3. `by_vssrc` → `by_egress_ssrc` 역조회 **보존** (SR/NACK/RR 재설계 회피)
4. **ViaSlot(slot)·sim(vssrc)은 고정 — 영원히 손 안 댐**

---

## 3. 케이스 점검 (일관성 — 코드 근거)

| 케이스 | egress_ssrc | 갱신 필요? |
|--------|-------------|-----------|
| full · non-sim (Direct) | publisher `ssrc` | **republish 시 ✓** |
| full · sim (Direct) | `PublisherStream.vssrc` | 불변 |
| half (ViaSlot) | `Slot.virtual_ssrc` | **고정 (무관)** |
| full↔half 전환 | Direct↔ViaSlot **active 전환** | egress 불변 |
| half 시작 → full | Direct **신규 등록**(신규 mid) | 정상 (idempotent 안 걸림) |

**ViaSlot 고정 근거:**
- `slot.rs:65` — *"floor 회전 시 `current_publisher` 만 swap"* → `virtual_ssrc` 불변
- `ptt_rewriter.rs:9` — *"화자 N명이 1개 가상 SSRC로 발화"* → 화자(origin) 전환을 PttRewriter 가 흡수, slot egress 불변
- → floor 회전·publisher republish 모두 ViaSlot egress 에 무영향

**full↔half 가 egress 변경이 아닌 근거:**
- subscriber 는 Direct + ViaSlot 두 stream 보유(`helpers.rs:248~`), 전환은 어느 쪽 active 냐의 통지(`do_track_state_req`)
- full→half: Direct 캐싱 보존(active:false) / half→full: 보존 Weak 재활성(active:true)
- half 로 시작(`helpers.rs:289` "개인 m-line 없음, slot 만 상존")한 경우만 full 전환 시 Direct 신규 등록

**결론:** 갱신 트리거는 **"Direct(full non-sim) 의 publisher ssrc 변경(republish)"** 단 하나.

---

## 4. 기각 / 정책

| 항목 | 결정 | 사유 |
|------|------|------|
| producer-주입 (egress_ssrc 완전제거) | **기각(장기과제)** | `by_egress_ssrc` 역조회(SR/NACK/RR 11곳)를 producer.subscribers 순회로 재설계 필요 → 비용 과다. CLAUDE.md "Track.subscribers 직접 순회 정석"·방향역전 설계와 정합하므로 미래 재검토 가치 |
| sim 가변 | **기각** | WebRTC simulcast = SDP rid publish 시 선언, 중간 토글 비현실적 → **불변 정책** |
| half↔full 을 갱신 트리거로 | **기각** | egress 변경이 아니라 Direct↔ViaSlot active 전환 (§3) |

---

## 5. 영향 범위 (파일·함수)

### 5.1 개명 (vssrc → egress_ssrc) — 기계적
- `domain/subscriber_stream.rs` — `SubscriberStream.vssrc` 필드 + 주석(282~289)
- `domain/subscriber_stream_index.rs` — `by_vssrc` → `by_egress_ssrc`
- `domain/peer.rs:1064` — `find_subscriber_stream_by_vssrc` → `_by_egress_ssrc`
- 읽기 사용처: `admin.rs`(129·348·439) · `tasks.rs`(149·350) · `track_ops.rs`(684·693·778·785) · `subscriber_stream.rs`(446·559) · `hooks/stream.rs`(101)

### 5.2 producer-push 갱신 (신규 — 핵심, **Direct/full non-sim 한정**)
- `PublisherStream`: republish 로 publisher ssrc 변경 시 자기 Direct `subscribers` 순회 →
  각 stream `egress_ssrc` 갱신 + `by_egress_ssrc` 인덱스 **재삽입**(remove old → insert new)
- 트리거 연결: `track_ops` PUBLISH_TRACKS add 경로 (collect 직후) — mid recycle/idempotent 케이스 보강
- **ViaSlot(Slot)·sim 은 제외** (고정)

### 5.3 역조회 보존 확인 (변경 없음, 검증만)
- SR/NACK/RR: `ingress_rtcp.rs`(211·242) · `ingress_subscribe.rs`(248·324·475·497·653) · `egress.rs:234` · `track_ops.rs`(708·1023)
- → `by_egress_ssrc` 키만 정확히 갱신되면 그대로 동작

### 5.4 통보·표시 정합
- `helpers.rs:297` 통보 ssrc = Direct egress_ssrc 와 동일 출처(publisher) 정렬
- `admin.rs` oxadmin 표시 = `egress_ssrc` (개명만)

---

## 6. 작업 단계

1. **개명** `vssrc → egress_ssrc` (필드·인덱스·find·사용처) — 빌드 통과
2. **producer-push 갱신** — PublisherStream republish 시 Direct subscribers `egress_ssrc` + 인덱스 재삽입
3. **idempotent 보정** — `add_subscriber_stream` 재사용(mid recycle) 시에도 push 가 egress 덮도록 순서 보장
4. **회귀시험** `oxe2e` + lab 실측 (republish 후 oxadmin out ssrc == 통보 ssrc)

---

## 7. 리스크

- **idempotent vs push 순서:** 등록 직후 push 가 항상 마지막에 덮는지 보장
- **by_egress_ssrc 재삽입 원자성:** RCU 교체 중 역조회가 옛 키 볼 수 있음 — RTCP 빈도 낮아 무해 추정, 검증
- **producer-주입 이행 경로:** 본 C안은 중간 단계. 미래 by_egress_ssrc 청산 시 본 push 가 fan-out 주입으로 승격 가능

---

## 8. 클라 전달 규약 (TRACKS_UPDATE / TRACK_STATE)

> 핵심: **"트랙 생사(add/remove)"와 "활성 상태(active 토글)"를 구분**한다.
> switch 를 add/remove 로 다루면 m-line 이 매번 출렁이고, half 를 개인 트랙으로 다루면 slot 과 중복된다.

### 8.1 케이스별 발행 (코드 근거)

| 전이 | 클라 메시지 | op | 핵심 필드 | 근거 |
|------|-----------|-----|----------|------|
| full pub | add | TRACKS_UPDATE | `ssrc`=publisher ssrc, `duplex`=full | helpers collect:254 / emit:288 |
| sim pub | add | TRACKS_UPDATE | `ssrc`=vssrc(가상), `simulcast`=true | collect:306 |
| **half pub** | **개인 없음** | (floor/MBCP) | slot 상존, Direct skip | collect:252 `continue` |
| unpub (full/sim) | remove | TRACKS_UPDATE | `track_id`, `mid` | emit:600 |
| **unpub (half)** | **개인 없음** | (floor 퇴장) | `broadcast_tracks = duplex≠Half` 제외 | track_ops:592 |
| full→half | active:false | **TRACK_STATE** | Direct 보존, `active`=false | track_ops:429 |
| half→full (보존) | active:true | **TRACK_STATE** | 보존 Weak 재활성 | track_ops:349 |
| half→full (신규/half시작) | add | TRACKS_UPDATE | `duplex`=full, Direct 신규 | track_ops:272 |
| **sim duplex switch** | **거부** | err | "simulcast duplex switch not supported" | track_ops:400 |

### 8.2 원칙 4가지

1. **add/remove 는 Direct(full/sim) 트랙만.** half 는 `Slot`(per-room 상존) 으로 받으니 개인 add/remove 불필요 — floor/MBCP 가 화자만 통지.
2. **duplex switch 는 active 토글(TRACK_STATE)** — Direct stream 보존, `active:true/false` 만 통지 → 클라 m-line/ssrc 유지, **SDP 재협상 회피.** 예외: half 시작→full 은 Direct 가 없어 **신규 add**.
3. **sim 은 duplex 전환 불가** (track_ops:400 거부). pub/unpub 만.
4. **republish(unpub→pub) 는 add 의 ssrc 가 바뀐다** — 클라엔 새 ssrc 로 add(또는 mid recycle). 서버 egress_ssrc 가 안 따라가면 어긋남 → **본 문서 §2 producer-push 가 해소.**

### 8.3 반복 시나리오

| 반복 | 메시지 흐름 | 비고 |
|------|------------|------|
| `full pub → unpub → full pub …` | add → remove → **add(새 ssrc)** | 매번 m-line recycle, egress_ssrc 갱신 필수 |
| `full ↔ half 반복` | active:false ↔ active:true | **m-line 그대로, 메시지만 토글** (최경량) |
| `half pub/unpub 반복` | 개인 메시지 0 | floor 만 회전 |
| `sim pub → unpub` | add → remove | switch 없음 |
