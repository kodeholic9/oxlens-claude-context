# Track Dump 재설계 — 설계서 v2.2

> 작성: 2026-05-20 (Claude — 김대리)
> 정지점 ① 결재 완료 (부장님 "진행해" 사인)
> v2.1 패치 (2026-05-20 김과장 반박 7건 평가 후 5건 정정): #2 대칭 표현 / #4 simulcast pending / #5 verdict 3단계 / #7 정지점 ② 검증 보강 / #8 김대리 단독 진행 명시. + TD-E 흡수
> **v2.2 패치 (2026-05-20 실 시험 자료로 결정적 결함 발견)**: publisher 측 식별자 1차 원천을 `getParameters().encodings[].ssrc` → **`getStats() outbound-rtp`** 로 정정. WebRTC W3C 표준 검색으로 확정 — getParameters 는 브라우저 자동 발급 ssrc 미노출 (W3C webrtc-pc #1174 — ORTC 와 모호). RTCOutboundRtpStreamStats / RTCInboundRtpStreamStats 의 ssrc 가 required, RTP 헤더와 일치 보장.
> 직전 작업: `20260520a_track_dump_impl_plan.md` (v1, 본 설계로 폐기)
> author: kodeholic (powered by Claude)
> **본 v2.2 진행 모드 = 김대리 단독 (김과장 통합 모드 미적용)** — v1 자율주행 회귀 방지

---

## §0 작업 범위

### 폐기 (v1 의 결함)
- carteasian row (`participants × participants × kind`) — 10인 방 200 row 폭증
- verdict 13종 (element_zero_size / gate_paused / kf_pending 등 비식별자 영역까지 verdict 결정에 포함)
- `_buildCliPubRow` / `_buildCliSubRow` 비대칭 두 벌
- getStats() 가 식별자 추출의 1차 출처 — 통계 보강 역할로 강등
- pt 누락 (4축 핵심 누락) / rid 항상 null

### 정정
- pt 채움 (식별자 핵심 축)
- rid 채움 ([1] cli_pub simulcast)
- **대칭 수집 함수 1벌** — `collectTrackIdentity(transceiver, pipe, role)`
- track 단위 row 모델 (carteasian 폐기)
- identity 정합 7건 verdict (비식별자 영역은 issues 만, verdict 미변경)

### 별 토픽 분리 (본 작업 손대지 않음)
- TD-A 서버 [2][3] RTP 카운터 (hot-path 결재 정합)
- TD-B virtual_ssrc 자료구조 정정 (`subscriber_stream.rs:336-340` 거짓말 청산) — derive 헬퍼 유지 (v2.1 결재: B 노선, 면적 크고 별 세션 거리)
- TD-C wire round-trip 테스트 재작성 (0x2701/0x1702)
- TD-D admin token Bearer 경로 통일
- ~~TD-E Pipe·element 접근자 캡슐화 검토~~ → **v2.1 흡수** (#3/#6 정정, B 노선 결재)
- TD-F NetEQ 자료 노출

---

## §1 원천 단일화 — `getStats()` 1차 (v2.2 정정)

**v2.2 결정적 정정**: `RTCRtpSender.getParameters().encodings[].ssrc` 는 W3C 표준 모호 (#1174) — 브라우저 자동 발급 ssrc 미노출. 실 시험 자료로 cli_pub.ssrc=[] 확인. **canonical source = `getStats()` 의 `RTCOutboundRtpStreamStats` / `RTCInboundRtpStreamStats`** (ssrc/mid/kind/codecId 모두 required, RTP 헤더 일치 보장).

### [1] cli_pub — 5축 (Publisher)

| 축 | 원천 (1차 — `getStats()` outbound-rtp) | 보조 (의도값) | 매칭 키 |
|---|---|---|---|
| track_id | 서버 발급값 (별 원천) | `Pipe.trackId` | — |
| ssrc | **`RTCOutboundRtpStreamStats.ssrc`** (required, RTP 헤더 일치) | `sender.getParameters().encodings[].ssrc` (지정값만) | mid 매칭 |
| mid | **`RTCOutboundRtpStreamStats.mid`** | `transceiver.mid` (동등) | — |
| pt | **`RTCCodecStats.payloadType`** (`codecId` 매핑) | `sender.getParameters().codecs[0].payloadType` (협상값) | — |
| rid | **`RTCOutboundRtpStreamStats.rid`** (simulcast layer) | `sender.getParameters().encodings[].rid` (의도) | — |

**simulcast 면 layer 마다 별도 outbound-rtp report** — 다중 ssrc/rid 자연 추출.

### [4] cli_sub — 4축 (Subscriber)

| 축 | 원천 (1차 — `getStats()` inbound-rtp) | 매칭 키 |
|---|---|---|
| track_id | 서버 발급값 (`Pipe.trackId`) | — |
| ssrc | **`RTCInboundRtpStreamStats.ssrc`** (required) | mid 매칭 |
| mid | **`RTCInboundRtpStreamStats.mid`** | — |
| pt | **`RTCCodecStats.payloadType`** (`codecId` 매핑) | — |

### Publisher pipe ↔ outbound-rtp 매칭 — `mid` 기준

```
for outbound-rtp report:
  if report.mid === pipe.transceiver.mid → 매칭 (simulcast 다중 layer 누적)
```

### Subscriber pipe ↔ inbound-rtp 매칭 — `mid` 기준

```
for inbound-rtp report:
  if report.mid === String(pipe.mid) → 매칭
```

**[1] [4] 대칭** — 양쪽 모두 `getStats()` 의 *-rtp report 가 1차 식별자 원천. mid 매칭 패턴 동일.

---

## §2 단일 진입 수집 함수 (원천 비대칭 → isPub 분기 흡수)

**대칭 표현 정정 (#2)**: 함수 시그니처는 단일 진입이지만, 원천 자료 흐름은 비대칭 (publisher 측 = `sender.getParameters().encodings[].ssrc` 브라우저 발급 / subscriber 측 = `pipe.ssrc` 서버 통보). 비대칭은 함수 내 `isPub` 분기로 흡수 — 호출자는 단일 패턴.

```js
// 단일 진입 — publisher / subscriber 양쪽 호출
function collectTrackIdentity(transceiver, pipe, role /* 'pub' | 'sub' */) {
  const isPub = (role === 'pub');
  const rtp   = isPub ? transceiver.sender : transceiver.receiver;
  const params = rtp.getParameters() ?? {};

  const ssrcList = isPub
    ? (params.encodings ?? []).map(e => e.ssrc).filter(s => s != null)
    : [pipe._ssrc];

  const ridList = isPub
    ? (params.encodings ?? []).map(e => e.rid).filter(Boolean)
    : null;

  return {
    track_id: pipe._trackId,
    ssrc:     ssrcList,
    mid:      transceiver.mid ?? null,
    pt:       params.codecs?.[0]?.payloadType ?? null,
    rid:      ridList,
    kind:     pipe.kind,
  };
}
```

비대칭 부수 자료 (self_view / element / 통계) 는 별 함수 부착.

---

## §3 row 스키마 — track 단위

```json
{
  "src_user": "foo",
  "kind": "video",
  "track_id": "foo-cam-video",
  "cli_pub":  { "track_id":"...", "ssrc":["0x..."], "mid":"0", "pt":102, "rid":["h","m","l"] },
  "srv_pub":  { "track_id":"...", "ssrc":["0x..."], "mid":"0", "pt":102, "rid":["h","m","l"] },
  "srv_subs": [
    {
      "dst_user": "bar",
      "srv_sub": { "track_id":"...", "ssrc":"0xAAAA0001", "mid":"0", "pt":102 },
      "cli_sub": { "track_id":"...", "ssrc":"0xAAAA0001", "mid":"0", "pt":102 },
      "verdict": "ok", "issues": []
    }
  ],
  "stats_pub":  { "bitrate_kbps":1200, "fps":30, ... },
  "stats_subs": [ { "dst_user":"bar", "framesDecoded":..., "freezeCount":..., ... } ]
}
```

식별자 자료 vs 통계 자료 분리.

---

## §4 verdict — identity 정합 7건 + 3단계 판정

### 정합 검증 7건

| # | 검증 | simulcast pending 분기 (#4 정정) |
|---|---|---|
| 1 | `cli_pub.track_id == srv_pub.track_id == srv_sub.track_id == cli_sub.track_id` | — |
| 2 | non-sim: `cli_pub.ssrc[0] == srv_pub.ssrc[0]` / sim: `cli_pub.ssrc ⊇ srv_pub.ssrc` **and** `srv_pub.ssrc.length ≥ 1` | **`srv_pub.ssrc.length === 0 && simulcast` → `pending` (RTP-First Discovery 시점 race — 공집합 부분집합 통과 함정 회피)** |
| 3 | `cli_pub.rid 집합 == srv_pub.rid 집합` (sim 만) | sim 인데 `srv_pub.rid.length === 0` → `pending` |
| 4 | `srv_sub.ssrc == cli_sub.ssrc` | — |
| 5 | `srv_sub.mid == cli_sub.mid` | — |
| 6 | `cli_pub.pt == srv_pub.pt` | `srv_pub.pt === null` (RTP 도착 전) → `pending` |
| 7 | `srv_sub.pt == cli_sub.pt` | — |

### verdict 3단계 (#5 정정 — 면죄부 자리 차단)

| 단계 | 의미 | 분석가 행동 |
|---|---|---|
| **ok** | 식별자 7건 정합 + 비식별자 issues 0 | 패스 |
| **degraded** | 식별자 7건 정합 but 비식별자 issues ≥ 1 (element zero size / gate paused / kf_pending / pli_governor_paused 등) | **5초 판정에서 확인 필수** — 사용자 체감 broken 가능 |
| **broken** | 식별자 정합 검증 mismatch ≥ 1 | 즉시 진단 |
| **pending** | 위 simulcast pending 분기 (RTP 도착 전) | 재시도 자리 |
| **unknown** | `cli_pub` 또는 `cli_sub` null (5s 미응답) | timeout 진단 |

어드민 화면 색상: ok=초록 / degraded=**노랑** / broken=빨강 / pending=회색 / unknown=흐림.

비식별자 영역 issues 라벨: `element_zero_size`, `element_not_attached`, `element_paused_no_autoplay`, `track_muted_recv`, `gate_paused`, `kf_pending`, `pli_governor_paused`.

---

## §5 흐름 (v1 와 동일 — 손대지 않음)

```
admin HTTP → hub → WS TRACK_DUMP_REQ broadcast
                ↓
              클라 collectTrackIdentity + getStats 보강
                ↓
              WS TRACK_DUMP_REPLY
                ↓
              hub fan-in (5s timeout, dump_id 매칭)
                ↓
              서버 admin snapshot 과 join + verdict 산출
                ↓
              HTTP response
```

---

## §6 영향 면적

| 영역 | 파일 | 변경 |
|---|---|---|
| 클라 SDK | `core/track-dump-collector.js` | 전면 재작성 (~340줄 → ~180줄) |
| 클라 SDK | `core/engine.js` / `core/pipe.js` | transceiver / pipe 접근자 점검 |
| 서버 hub | `oxhubd/src/track_dump/mod.rs` | row 스키마 + verdict 정정 |
| 서버 hub | `oxhubd/src/rest/admin.rs` | 응답 JSON 골격 |
| 서버 sfud | `oxsfud/.../admin.rs` | srv_pub.rid 노출 점검 |
| 어드민 화면 | `demo/admin/render-track-dump.js` | row 구조 + srv_subs 펼침 |
| 어드민 화면 | `demo/admin/index.html` | 매트릭스 컬럼 조정 |

**총 ≈ +50줄 / -270줄 (net -220줄)**

---

## §7 정지점

| # | 시점 | 보고 |
|---|---|---|
| ① | **결재 완료** (부장님 "진행해") | 본 설계서 |
| ② | 클라 SDK §2 §3 완료 | diff + **Conference 3인 실 시험 → sample row JSON 1개 캡처 (실 트래픽 결과, 가공 X)** + collectTrackIdentity 단위 테스트 PASS (#7 정정) |
| ③ | 서버 hub §4 verdict + row 스키마 완료 | diff + 단위 테스트 PASS (3단계 verdict + simulcast pending 분기 검증 포함) |
| ④ | 어드민 + 회귀 통과 | 화면 캡처 (3단계 색상 표시) + 회귀 6/6 |

자율주행 미적용. **본 v2.1 진행 모드 = 김대리 단독 (김과장 통합 모드 미적용)** (#8 정정).

---

## §8 검증 기준

- 식별자 7건 정합 — Conference 3인 정상 시나리오 → 모든 row verdict=ok
- pt 채움 — null 아님
- rid 채움 — simulcast publisher row 에 `["h","m","l"]`
- 대칭성 — 식별자 4 필드 키 동일
- 자료 폭 — pub × sub 폭증 없음, row 수 = 트랙 수
- 회귀 — Conference / PTT(DC) / PTT(WS) / SCOPE / Admin Live 정상

---

*author: kodeholic (powered by Claude) — 2026-05-20 정지점 ① 결재 통과*
