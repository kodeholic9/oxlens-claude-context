# trace v2 설계 — 미디어 + 시그널링 통합 디버그 평면

> oxadmin `trace` 확장. 미디어 패킷 전용 → 미디어/gRPC/DC 전 평면 + 동적 와일드 + N-타겟.
> 부장님 통찰(`U01 *` 미리 켜기로 사후 분석 = 코어 무수정) 채택, 내 ring-buffer 제안(C) 폐기.
> author: kodeholic (powered by Claude) · 2026-06-20

---

## 0. 제1원칙 — "정확하지 않은 디버그 도구는 쓰레기"

trace 가 거짓(누락·중복·오정렬)을 주면 디버깅이 오판으로 직행한다(실제로 0620 세션에 trace 0건을
"안 흐른다"로 오판한 사례). 그래서 **모든 항목은 아래 4 정확성 게이트를 통과해야 한다.**

1. **비침습** — trace on/off 가 미디어 동작을 1 bit 도 안 바꾼다. `#[cfg(feature="trace")]` 격리,
   hot-path 는 lock-free pre-filter, emit 실패가 forward 를 막지 않음. 검증 = oxe2e PASS 가 on/off 불변.
2. **무손실·무중복** — trace point 가 실제 경로와 1:1. broadcast lag 로 드롭되면 **드롭을 숨기지 말고
   summary 에 카운트 노출**("이 캡처 불완전" 경고). 누락을 0건으로 오판하지 않게.
3. **단일 시간축** — 모든 평면(미디어/gRPC/DC/클라) 같은 epoch. 오정렬로 인과를 뒤집지 않게.
4. **자기검증** — trace 출력 자체를 단위 + 회귀(oxe2e)로 검증. 정상 시나리오의 기대 IDR/패킷수와 대조.

---

## 1. 핵심 발상 — 부장님 통찰: `*` 동적 와일드 + 미리 켜기

### 폐기: ring buffer(구 C)
"trace 안 켜도 과거를 본다"를 위해 sfu hot-path 에 상시 링버퍼를 두려 했으나 — **과설계**.
**미리 `U01 *` 로 켜두면** 소급 효과는 충분하고, 그게 가능한 이유가 `*` 의 동적성이다.

### 채택: `*` 의 동적 표적성
- `*` 매칭은 emit 마다 `(user, ssrc, dir)` 를 평가 → **publish 안 된 ssrc 도 publish 되는 순간 표적**.
- 0620 고통(republish 마다 ssrc 변경 `0x4753B438→0x6D035B41…`, 매번 `room` 으로 ssrc 재집계,
  간헐 현상 3분 캡처)을 정조준 해결: `U01 *` 한 번이면 현재+미래 ssrc 전부.
- **forward/rewrite 등 코어 로직과 무관** — trace 매칭 *조건*만 넓힘.

### 방향/타겟 의미 (오판 방지 — 가이드 명문화)
- `U01 * --in` = U01 이 **보낸** 모든 track (ingress, emit user=U01).
- `U01 * --out` = U01 이 **받는** 모든 track (egress, emit target=U01).
- U01 이 보낸 게 **U02 가 받는 fan-out** 은 emit target=U02 → `U02 *` 또는 `* *` 로. (`U01 *` 에는 없음)

---

## 2. 현재 제약과 관대화

| 제약 | 강제 위치 | 관대화 |
|---|---|---|
| triple 최대 2 | oxadmin parse + 서버 `keys.len() > 2`(trace.rs:182) | **N(상한 16)** — `keys: Vec` 이미 지원, 가드 ↑ + oxadmin N-parse |
| 동시 1 타겟 | 서버 `ArcSwapOption<Session>` 단일 + `same_target` Conflict | **한 세션 N-타겟**으로 흡수(`U01 * U02 * slot…` 한 번에). 다중 *세션*(여러 oxadmin 독립 타겟)은 보류 |

> 관대해도 가드: ① N 상한(hot-path `keys` 순회 비용) ② broadcast cap ↑ + **드롭 카운트 노출** ③ detail 바이트 제한 연계.

---

## 3. 항목 (확정 / 폐기)

| ID | 항목 | 코어영향 | 비고 |
|---|---|---|---|
| **0** | **ssrc `*` 와일드 (동적 표적)** ★ | trace 매칭만 | `MatchKey.ssrc: Option<u32>` None=any |
| **W** | **triple 2→N (한 세션 다타겟)** ★ | trace 매칭만 | `keys.len()` 상한 16, oxadmin N-parse |
| A | 패킷 생애추적 (origin_seq join) | 출력 가공 | ingress→rewrite→gate→egress/drop 체인 |
| B | 캡처 summary (패킷/IDR/drop/gap **+ 드롭경고**) | 출력 가공 | grep/awk 제거, 정확성 게이트 2 |
| E | 단일 시간축 + NAL/코덱 주석 | 출력 + emit | IDR/SPS/PPS/P 자동 표시 |
| 3 | 덤프 바이트 제한 정비 (per-point) | 출력 + filter | 시그널링(JSON/TLV) 큼 대비 |
| 1 | gRPC 시그널링 trace (hub↔sfud WsMessage) | 신규 point | Phase 2 |
| 2 | DC MBCP 시그널링 trace (floor TLV) | 신규 point | Phase 2 |
| ~~C~~ | ~~ring buffer + 트리거~~ | — | **폐기** (`*` 미리 켜기로 대체) |
| ~~D~~ | ~~다중 세션~~ | — | 보류 (한 세션 N타겟으로 충분) |

---

## 4. 단계

### Phase 1 — 동적 와일드 + 출력 정확 (코어 0 변경, oxadmin 중심)
목표: 0620 같은 미디어 디버깅을 한 도구로 끝낸다. **forward/rewrite 무수정.**
- **0** ssrc `*` : oxadmin `parse_ssrc("*")` → wildcard / proto `Triple.ssrc_any: bool` / 서버 `MatchKey.ssrc: Option`.
- **W** N-타겟 : oxadmin N-triple parse / 서버 `keys.len()` 상한 16 + broadcast cap↑ + 드롭 카운트.
- **E** 시간축+NAL : 클라/서버 epoch 통일 표기 + H264/VP8 NAL 타입 자동 주석(IDR/SPS/PPS/P).
- **A** 생애추적 : `origin_seq` 로 point 체인 재구성(같은 seq 가 ingress→egress 어디까지/어디서 drop).
- **B** summary : 캡처 종료 시 통계 1줄(총/IDR/drop/gap/간격 + **broadcast 드롭 경고**).
- **3** 바이트 : `--bytes` per-point 화 + 시그널링 기본 절단.

### Phase 2 — 시그널링 평면 확장 (서버 trace point 추가)
목표: 한 시간축에서 **시그널링→미디어 인과**(예: PUBLISH_TRACKS 도착 → publisher 등록 → 첫 키프레임 egress).
- **1** gRPC : hub↔sfud `WsMessage`(JSON/binary) 진입/출구에 trace point. user/op 라벨.
- **2** DC MBCP : SCTP DataChannel MBCP(floor TLV) in/out trace point.
- 통합 시간축에서 0620 "republish→재구독 race" 같은 교차평면 인과를 직추적.

---

## 5. 영향 범위

| 파일 | 변경 |
|---|---|
| `oxadmin/src/trace.rs` | `parse_ssrc("*")`, N-triple parse, NAL 주석/summary/seq-join 출력, 시간축 표기 |
| `common` proto (trace) | `Triple.ssrc_any: bool` 추가. (Phase 2) 시그널링 point enum 확장 |
| `oxsfud/src/trace.rs` | `MatchKey.ssrc: Option<u32>`, `matches` None=any, `keys.len()` 상한 16, broadcast cap↑ + 드롭 카운트 |
| `oxsfud` 시그널링/DC (Phase 2) | gRPC dispatch · datachannel/mbcp 경로에 `#[cfg(feature="trace")]` emit point |

> 코어(`subscriber_stream::forward`, `ptt_rewriter`, `publisher_track::broadcast`)는 **Phase 1 에서 0 변경**.
> Phase 2 의 신규 emit point 도 `#[cfg(feature="trace")]` 격리 — 비침습 게이트 1 준수.

---

## 6. 검증 (정확성 게이트 → 시험)

| 게이트 | 시험 |
|---|---|
| 비침습 | oxe2e 5/5 가 trace on/off 불변 (PASS 동일) |
| 무손실·무중복 | 단위: 알려진 패킷열 → `MatchKey` 매칭/NAL 파싱/seq-join 기대값. 드롭 시 summary 카운트 일치 |
| 단일 시간축 | 단위: epoch 변환 round-trip. 통합: 시그널링↔미디어 ts 순서 sentinel |
| 자기검증 | oxe2e 정상 시나리오에서 `U01 *` trace → 기대 IDR/패킷수와 대조(회귀 sentinel) |

---

## 7. 미해결 / 결정 대기
- proto `Triple.ssrc_any` vs `ssrc=0 sentinel` — 명시 플래그(ssrc_any) 권장(0 ssrc 충돌 회피). 부장님 확인.
- N 상한 16 적정값 — hot-path `keys` 순회 비용 측정 후 조정.
- Phase 2 시그널링 point 입도 — 메시지 단위(op) vs 바이트. JSON 큼 → 메타+절단 기본.
