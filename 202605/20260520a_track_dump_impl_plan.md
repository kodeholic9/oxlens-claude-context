# Track Dump 구현 지침 §0~§10

> 작성: 2026-05-20 (Claude — 김대리+김과장 통합 역할)
> 설계 합의: `context/202605/20260520_track_dump_design.md`
> 정지점 ①: 본 지침 § 결재 → 정지점 ②: 구현 완료 보고
> author: kodeholic (powered by Claude)

---

## §0 배경

트랙 디버깅 시 서버 로그 / 콘솔 로그 / 텔레메트리 스냅샷 3출처를 종합 분석하는 추정 누적 패턴을 한 번의 Pull HTTP 요청 → 한 JSON 응답으로 4-Point 풀 덤프 가져오는 인프라로 환원. 분석 시간 5~6시간 → 5초 판정 목표.

---

## §1 명세 (부장님 결재 완료)

### 1.1 흐름

```
어드민 HTTP GET → hub
                  ↓ WS TRACK_DUMP_REQ (0x2701, broadcast_to_room)
                  방 안 모든 클라
                  ↓ getStats + element/transceiver/pipe 수집 (수백 ms)
                  ↓ WS TRACK_DUMP_REPLY (0x1702)
                  hub fan-in 수집기 (pid 매칭, timeout 5s, 미응답 null)
                  ↓ 서버 admin snapshot 자료와 join
어드민 ← HTTP response (row 단위 4-Point JSON)
```

### 1.2 신규 wire op (v3 카탈로그 hub-local Extension 카테고리)

| op | 이름 | 방향 | 카테고리 | wire ACK |
|---|---|---|---|---|
| `0x2701` | TRACK_DUMP_REQ | S→C broadcast | Extension Event (hub-local) | 클라 즉시 ACK_OK |
| `0x1702` | TRACK_DUMP_REPLY | C→S | Extension Request (hub-local) | 서버 즉시 ACK_OK |

application 매칭: REPLY body 안 `req_pid: u32` 필드 (REQ 의 wire pid). hub fan-in 수집기가 매칭 키로 사용.

### 1.3 응답 JSON 골격 (확정 — row 단위)

```json
{
  "type": "track_dump",
  "version": 1,
  "room_id": "R1",
  "ts": "2026-05-20T12:34:56.789Z",
  "dump_id": 17,
  "deadline_ms": 5000,
  "elapsed_ms": 823,
  "participants": [
    { "user_id": "foo", "role": "publisher", "joined_at": 1747234567, "peer_state": "alive" }
  ],
  "missing_users": [],
  "rows": [
    {
      "src_user": "foo", "dst_user": "bar", "kind": "video", "rid": "h", "track_id": "foo-cam-video",
      "cli_pub":  { ...§1.4-A | null },
      "srv_pub":  { ...§1.4-B },
      "srv_sub":  { ...§1.4-C },
      "cli_sub":  { ...§1.4-D | null },
      "verdict":  "ok|broken|warn",
      "issues":   []
    }
  ]
}
```

**최상위 필드 정합**:
- `type`: 항상 `"track_dump"` (응답 구분 string)
- `version`: 스키마 버전 — 본 작업 = `1`. 향후 break 시 +1
- `dump_id`: `u32` — hub 가 자체 발급한 application 식별자 (counter 또는 random). wire pid 와 분리 — broadcast 시 OutboundQueue 가 user 마다 다른 wire pid 를 재발급하므로 매칭 키로 wire pid 부적합. REQ body / REPLY body 안에 동일 `dump_id` 박혀 hub fan-in 수집기의 matching key 역할
- `deadline_ms`: hub 가 설정한 timeout (5000 고정 — 부장님 결재)
- `elapsed_ms`: 실제 수집 소요 시간 (요청~응답 까지)
- `cli_pub` / `cli_sub` = `null` → 해당 user 가 deadline 안 응답 미수신 → `missing_users[]` 에 등록
- `rows` = `participants` 의 publisher × subscriber × kind 카르테시안 (audience 는 dst 만)

### 1.4 4-Point 필드 명세

**hot-path 카운팅 추가 금지** (부장님 결재) — 서버측은 구조/상태/판정만, RTP packets/bytes/jitter/loss 등 통계는 클라 [1]/[4] 의 getStats() 로만 수집해 양단 대조. 서버 RTCP 카운터 통합은 별도 토픽으로 분리 (§5).

#### A. `cli_pub` — 클라 Publisher (publisher user 만)

| 필드 | 출처 | 비고 |
|---|---|---|
| ssrc, kind, track_id, mid | engine.js Pipe + transceiver | |
| rid (video, simulcast) | sender.getParameters().encodings | |
| codec, bitrate, fps, resolution | getStats outbound-rtp + codec stats | |
| qpSum, framesEncoded, keyFramesEncoded | 동상 | delta 아닌 누적값 |
| qualityLimitationReason, qualityLimitationDurations | 동상 | |
| totalEncodeTime, nackCount, pliCount | 동상 | |
| track.enabled, muted, readyState | MediaStreamTrack | |
| transceiver.direction, currentDirection | RTCRtpTransceiver | |
| pipe.trackState | Pipe._state | INACTIVE/ACTIVE/SUSPENDED/RELEASED |
| self_view | 별 객체 | element_attached, srcObject_set, hasTrack, readyState, paused, currentTime, muted, playsInline, display, visible, videoWidth, offsetWidth, filter_applied |

#### B. `srv_pub` — 서버 Publisher 수신 (admin snapshot 재조립)

| 필드 | 출처 (현재 admin.rs 라인) | 비고 |
|---|---|---|
| ssrc, kind, track_id, duplex, simulcast, rid, source | PublisherStream snapshot (admin.rs:28-50) | |
| publish_state | admin.rs:38 (`snap.phase.as_str()`) | Created/Intended/Active |
| actual_pt, video_codec, rtx_ssrc | admin.rs:36-46 | |
| stream_map_virtual_ssrc | admin.rs:75-79 (simulcast only) | 0 = 미할당 |
| first_seen_ago_ms | admin.rs:73 | |
| intent_received, audio_mid, video_sources | admin.rs:84-103 | |
| pli_governor | admin.rs:107-109 (`gov.dump()`) | freq/duration/paused |
| track_issues | admin.rs:132-165 | intent⟷stream 불일치 등 |

**제외 필드** (hot-path 카운팅 필요 — 별 토픽): packets_received, bytes_received, jitter, packet_loss, last_rtp_arrival_us, pli_received_count, nack_received_count

#### C. `srv_sub` — 서버 Subscriber 송신 (admin snapshot User 축 재조립 + 신규 derive)

| 필드 | 출처 | 비고 |
|---|---|---|
| ssrc (vssrc), mid, kind | admin.rs:351-353 | |
| mode | admin.rs:333-347 | Audio/VideoNonSim/VideoSim/ViaSlot |
| subscribe_state | admin.rs:355 (`sub_snap.phase.as_str()`) | Created/Active |
| current_rid, target_rid, rewriter_initialized | admin.rs:357-359 (VideoSim only) | |
| **is_virtual** | derive (§5) | mode + publisher_ref 조합 → bool |
| **origin** | derive (§5) | non-sim Direct → publisher 원본 ssrc / sim → publisher 가상 ssrc / ViaSlot → Slot.virtual_ssrc + 현 화자 origin |
| **src_user** | derive (신규) | publisher_ref → user_id 역참조 |
| gate (paused, reason, elapsed_ms) | SubscriberGate.dump() (admin.rs:115) | 현재 paused 만 노출 — 본 작업에서 paused=false 도 노출하도록 admin.rs 확장 |

**제외 필드** (hot-path 카운팅 — 별 토픽): packets_sent, bytes_sent, pli_sent_count, nack_sent_count, last_rtp_send_us

#### D. `cli_sub` — 클라 Subscriber (subscriber user 만)

| 필드 | 출처 | 비고 |
|---|---|---|
| ssrc, mid, kind, track_id | engine.js Pipe + transceiver | |
| codec, framesDecoded, keyFramesDecoded, framesDropped | getStats inbound-rtp | 누적값 |
| decodeTime, totalDecodeTime | 동상 | |
| freezeCount, totalFreezesDuration, pauseCount, totalPausesDuration | 동상 | |
| jitterBufferDelay, jitterBufferEmittedCount | 동상 | |
| concealedSamples, silentConcealedSamples | audio only | |
| nackCount, pliCount, firCount | 동상 | |
| jitter, packetsReceived, packetsLost | 동상 | 클라 측 RTCP 통계 (서버 hot-path 비대상) |
| track.enabled, muted, readyState | MediaStreamTrack | |
| transceiver.mid | RTCRtpTransceiver | 서버 할당과 일치 확인용 |
| element | 별 객체 (11+ 필드) | attached, srcObject_set, hasTrack, readyState, networkState, paused, currentTime, played_length, videoWidth, videoHeight, offsetWidth, offsetHeight, display, visible, muted, volume, sinkId, bounding |
| pipe | trackState, mounted | Pipe._state + DOM 일치 |
| audio_extras | audio only | audioLevel, totalAudioEnergy, AudioContext.state, playoutDelayHint, googTargetDelayMs, googCurrentDelayMs |

### 1.5 verdict / issues 산출 규칙

`verdict` 자동 판정 — hub 측 join 단계:

- `ok`: 모든 4-Point 채워짐 + 핵심 단절 없음
- `broken`: gate paused / publish_state≠Active / subscribe_state≠Active / cli_sub.element.videoWidth=0 / cli_sub null
- `warn`: floor idle (PTT 정상 sileence) / pli_governor.paused / pause_reason="kf_pending"

`issues[]` enum (string): `gate_paused`, `kf_pending`, `publish_inactive`, `subscribe_inactive`, `element_zero_size`, `element_not_attached`, `track_muted_recv`, `element_paused_no_autoplay`, `cli_pub_missing`, `cli_sub_missing`, `mid_mismatch`, `ssrc_mismatch`

### 1.6 자료형 규약 (확정)

| 영역 | 표현 | 비고 |
|---|---|---|
| `ssrc` / `virtual_ssrc` / `rtx_ssrc` / `origin.*_ssrc` | hex string `"0x12345678"` | admin.rs 정합 (`format!("0x{:08X}", ssrc)`) |
| `mid` | string | SDP m-line index. `"0"`, `"1"`, ... |
| `track_id` | string | publisher 가 발행한 그대로 |
| `kind` | enum string | `"audio"` / `"video"` |
| `role` | enum string | `"publisher"` / `"audience"` / `"recorder"` |
| `peer_state` | enum string | `"alive"` / `"suspect"` / `"zombie"` |
| `publish_state` / `subscribe_state` | enum string | `"created"` / `"intended"` / `"active"` (publish) / `"created"` / `"active"` (subscribe) |
| `mode` | enum string | `"Audio"` / `"VideoNonSim"` / `"VideoSim"` / `"ViaSlot"` |
| `verdict` | enum string | `"ok"` / `"broken"` / `"warn"` |
| `duplex` | enum string | `"full"` / `"half"` |
| `codec` | string | `"H264"` / `"VP8"` / `"VP9"` / `"AV1"` / `"opus"` (대소문자 admin.rs 정합) |
| `ts` | ISO 8601 string | `"2026-05-20T12:34:56.789Z"` |
| `joined_at` / `last_seen` | unix epoch seconds (u64) | admin.rs 정합 |
| timestamp delta (`*_ago_ms`, `elapsed_ms`, `deadline_ms`) | integer ms | |
| bitrate | integer kbps | 가독성 위해 bps 아님 |
| duration (`encodeTime` / `decodeTime` / `jitter` / `jitterBufferDelay` / `totalEncodeTime` / `totalDecodeTime` / `totalFreezesDuration` / `totalPausesDuration` / `qualityLimitationDurations.*`) | float seconds | getStats 정합 |
| 누적 counter (`framesEncoded` / `framesDecoded` / `packetsReceived` / `packetsLost` / `nackCount` / `pliCount` / `qpSum` 등) | integer | delta 아님, 누적값 |
| nullable | `null` 허용 | `cli_pub` / `cli_sub` 전체 / `audio_extras` (video kind) / `self_view` (subscriber row) / `rtx_ssrc` (audio) / `origin.publisher_origin_ssrc` (ViaSlot) |
| origin 구조 | `{ "kind": "passthrough|simulcast_virtual|via_slot", "wire_ssrc": "...", "publisher_origin_ssrc": "..." | null }` | virtual_ssrc derive 결과 |

**audio_extras / self_view 분기 규약**:
- `cli_pub.self_view` — publisher row 이고 `kind="video"` 에서만 객체. audio publisher = `null`
- `cli_sub.audio_extras` — subscriber row 이고 `kind="audio"` 에서만 객체. video subscriber = `null`

### 1.7 응답 JSON 최종 예시 (1 row 통째)

```json
{
  "type": "track_dump", "version": 1,
  "room_id": "R1", "ts": "2026-05-20T12:34:56.789Z",
  "dump_id": 17, "deadline_ms": 5000, "elapsed_ms": 823,
  "participants": [
    { "user_id": "foo", "role": "publisher", "joined_at": 1747234567, "peer_state": "alive" },
    { "user_id": "bar", "role": "publisher", "joined_at": 1747234580, "peer_state": "alive" }
  ],
  "missing_users": [],
  "rows": [
    {
      "src_user": "foo", "dst_user": "bar", "kind": "video", "rid": "h",
      "track_id": "foo-cam-video",

      "cli_pub": {
        "ssrc": "0x12345678", "mid": "0", "track_id": "foo-cam-video", "rid": "h", "kind": "video",
        "codec": "H264", "bitrate_kbps": 1200, "fps": 30, "width": 1280, "height": 720,
        "qpSum": 84321, "framesEncoded": 9000, "keyFramesEncoded": 30,
        "qualityLimitationReason": "none",
        "qualityLimitationDurations": { "none": 30.0, "bandwidth": 0.0, "cpu": 0.0, "other": 0.0 },
        "totalEncodeTime": 12.34, "nackCount": 2, "pliCount": 0,
        "track": { "enabled": true, "muted": false, "readyState": "live" },
        "transceiver": { "direction": "sendonly", "currentDirection": "sendonly" },
        "pipe": { "trackState": "ACTIVE" },
        "self_view": {
          "element_attached": true, "srcObject_set": true, "hasTrack": true,
          "readyState": 4, "paused": false, "currentTime": 12.34,
          "muted": true, "playsInline": true,
          "display": "block", "visible": true,
          "videoWidth": 1280, "offsetWidth": 320,
          "filter_applied": false
        }
      },

      "srv_pub": {
        "ssrc": "0x12345678", "kind": "video", "track_id": "foo-cam-video",
        "duplex": "full", "simulcast": true, "rid": "h", "source": "camera",
        "publish_state": "active", "actual_pt": 102, "video_codec": "H264",
        "rtx_ssrc": "0x12345679", "stream_map_virtual_ssrc": "0xAAAA0001",
        "first_seen_ago_ms": 8421,
        "intent": {
          "received": true, "audio_mid": "1", "rid_extmap_id": 14, "mid_extmap_id": 4,
          "video_sources": [
            { "source": "camera", "mid": "0", "pt": 102, "rtx_pt": 103,
              "simulcast": true, "codec": "H264", "duplex": "full" }
          ]
        },
        "pli_governor": { "freq_hz": 0.5, "paused": false, "last_pli_ago_ms": 1234 },
        "track_issues": []
      },

      "srv_sub": {
        "ssrc": "0xAAAA0001", "mid": "0", "kind": "video",
        "mode": "VideoSim", "subscribe_state": "active",
        "current_rid": "h", "target_rid": "h", "rewriter_initialized": true,
        "is_virtual": true,
        "origin": {
          "kind": "simulcast_virtual",
          "wire_ssrc": "0xAAAA0001",
          "publisher_origin_ssrc": "0x12345678"
        },
        "src_user": "foo",
        "gate": { "paused": false, "reason": null, "elapsed_ms": 0 }
      },

      "cli_sub": {
        "ssrc": "0xAAAA0001", "mid": "0", "track_id": "foo-cam-video", "kind": "video",
        "codec": "H264",
        "framesDecoded": 8980, "keyFramesDecoded": 29, "framesDropped": 0,
        "decodeTime": 11.20, "totalDecodeTime": 11.20,
        "freezeCount": 0, "totalFreezesDuration": 0.0,
        "pauseCount": 0, "totalPausesDuration": 0.0,
        "jitterBufferDelay": 0.045, "jitterBufferEmittedCount": 8980,
        "nackCount": 0, "pliCount": 0, "firCount": 0,
        "jitter": 0.003, "packetsReceived": 9000, "packetsLost": 0,
        "track": { "enabled": true, "muted": false, "readyState": "live" },
        "transceiver": { "mid": "0" },
        "element": {
          "attached": true, "srcObject_set": true, "hasTrack": true,
          "readyState": 4, "networkState": 2,
          "paused": false, "currentTime": 12.34, "played_length": 1,
          "videoWidth": 1280, "videoHeight": 720,
          "offsetWidth": 640, "offsetHeight": 360,
          "display": "block", "visible": true,
          "muted": false, "volume": 1.0, "sinkId": "default",
          "bounding": { "x": 0, "y": 0, "w": 640, "h": 360 }
        },
        "pipe": { "trackState": "ACTIVE", "mounted": true },
        "audio_extras": null
      },

      "verdict": "ok", "issues": []
    }
  ]
}
```

---

## §2 영향 범위

### 2.1 서버 (`oxlens-sfu-server`)

| 파일 | 변경 |
|---|---|
| `crates/oxsig/src/opcode.rs` | `0x2701 TRACK_DUMP_REQ` / `0x1702 TRACK_DUMP_REPLY` 추가 + 단위 테스트 |
| `crates/oxhubd/src/rest/admin.rs` | `GET /media/admin/rooms/{room_id}/track-dump` 라우트 신설 |
| `crates/oxhubd/src/ws/mod.rs` | TRACK_DUMP_REPLY 수신 분기 (handle_client_message) + fan-in 수집기로 라우팅 |
| `crates/oxhubd/src/track_dump/mod.rs` (신규) | PendingDump 수집기 (DashMap<dump_id, oneshot::Sender<...>> + timeout) |
| `crates/oxhubd/src/state.rs` | `track_dump: TrackDumpRegistry` 필드 추가 |
| `crates/oxsfud/src/signaling/handler/admin.rs` | derive 헬퍼 (`is_virtual_for`, `origin_for`, `src_user_for`) + SubscriberGate paused=false 도 노출 (admin.rs:115 본문 변경) |

### 2.2 클라 SDK (`oxlens-home/core`)

| 파일 | 변경 |
|---|---|
| `core/constants.js` | `OP.TRACK_DUMP_REQ` / `OP.TRACK_DUMP_REPLY` 추가 |
| `core/signaling.js` | `_handleEvent` 안 TRACK_DUMP_REQ case (collectTrackDump 호출 → REPLY 송신) |
| `core/track-dump-collector.js` (신규) | 한 번에 4-Point [1]/[4] 풀 덤프 수집 함수 (`collectTrackDump(media, pipes): Promise<TrackDumpPayload>`) |
| `core/engine.js` | track-dump-collector 가 호출할 수 있도록 pubPc/subPc + pipes + transceiver 접근자 노출 (기존 접근자 재사용 가능 — 확인 후) |

### 2.3 어드민 화면 (`oxlens-home/demo/admin`)

| 파일 | 변경 |
|---|---|
| `demo/admin/index.html` | 메인 헤더 아래 탭 row 신설 ([Live] [Track Dump]), 신규 패널 컨테이너 `<section id="track-dump-panel" hidden>` |
| `demo/admin/app.js` | 탭 전환 핸들러 + Dump/Copy 버튼 핸들러 + `fetch('/media/admin/rooms/{room_id}/track-dump')` |
| `demo/admin/render-track-dump.js` (신규) | 4-Point 매트릭스 렌더 + 행 클릭 상세 펼침 + 색상/판정 규칙 |
| `demo/admin/state.js` | `currentDump: { room_id, ts, rows[], ... }` 필드 |

### 2.4 문서

| 파일 | 변경 |
|---|---|
| `context/design/wire_v3_catalog.md` | §7 Request — Data / Extension 표 + §14 Event — Extension 표에 신규 op 추가 |
| `context/design/20260516_signaling_v3.md` | §5 opcode 카탈로그에 동일 (필요 시) |

---

## §3 변경 면적 추정

- 서버: 신규 모듈 1개 (`track_dump/mod.rs`, ~300줄) + 5개 파일 부분 변경 (~150줄 net 추가)
- 클라 SDK: 신규 모듈 1개 (`track-dump-collector.js`, ~400줄) + 3개 파일 부분 변경 (~80줄)
- 어드민: 신규 모듈 1개 (`render-track-dump.js`, ~500줄) + 3개 파일 부분 변경 (~120줄)
- 문서: 카탈로그 + 설계서 갱신 (~30줄)
- **합계**: 약 1600줄 추가 / 50줄 변경

---

## §4 자체 검증 기준

| 항목 | 합격 기준 |
|---|---|
| 단위 테스트 | 서버 252 PASS 유지 + opcode 카탈로그 신규 2 op invariant PASS + 클라 sdp-builder 82/82 + datachannel + scope 유지 |
| wire round-trip | 신규 op REQ/REPLY 각각 encodeFrame ↔ decodeFrame + req_pid 매칭 |
| Fan-in timeout | 5s timeout 시 미응답 user 가 `missing_users[]` 에 정확히 포함 |
| 4-Point JSON 검증 | 시나리오 1방 + 3 user (publisher 2 + audience 1) → row 수 = (pub × sub × kind), 각 cell 의 ssrc/mid 일치 |
| virtual_ssrc derive | non-sim Direct → `is_virtual: false`, `origin: publisher 원본 ssrc` / sim → `is_virtual: true`, `origin: 가상 ssrc` / ViaSlot → `is_virtual: true`, `origin: Slot.virtual_ssrc + 현 화자` |
| 어드민 화면 | Dump 버튼 → 5s 안 매트릭스 표시, 정상 row 초록 / gate paused row 빨강 / floor idle row 노랑 |
| 회귀 | Conference / PTT(DC bearer) / PTT(WS bearer) / SCOPE / Admin Live 탭 시나리오 정상 유지 |

---

## §5 발견 사항 (별도 토픽 분리)

1. **virtual_ssrc 자료구조 (§8 악의 축)** — 본 작업에서 비건드림. 응답 JSON 에서 derive only (`is_virtual_for` / `origin_for` 헬퍼). 부장님 결정 정합.
2. **서버 RTP packets/bytes/jitter 카운터 부재** — hot-path 카운팅 거부 (부장님 결재). Track Dump 에서는 클라 양단 getStats() 로만 흡수. 서버측 RTCP 통계가 필요해지면 *별도 토픽* (예: RTCP RR 처리 자리에서만 누적, hot-path 우회).
3. **`subscriber_stream.rs:336-340` self-confessed virtual_ssrc 거짓말** — 본 작업이 derive 헬퍼로 우회. 자료구조 정정은 §8 별도 토픽.

---

## §6 Phase 1: 서버 구현

### 6.1 oxsig opcode 카탈로그 갱신

`crates/oxsig/src/opcode.rs`:
- `pub const TRACK_DUMP_REQ: u16 = 0x2701;` (Extension Event)
- `pub const TRACK_DUMP_REPLY: u16 = 0x1702;` (Extension Request)
- `ALL_OPS` 배열 + `extension_category` / `request_category` / `event_category` 테스트 케이스 갱신
- `catalog_size` 40 → 42

### 6.2 fan-in 수집기 (`crates/oxhubd/src/track_dump/mod.rs` 신규)

```rust
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Instant;
use dashmap::DashMap;
use tokio::sync::oneshot;

pub struct TrackDumpRegistry {
    pending: DashMap<u32, PendingDump>,
    next_id: AtomicU32,
}

struct PendingDump {
    room_id: String,
    expected: HashSet<String>,
    received: HashMap<String, serde_json::Value>,  // user_id → { cli_pub_tracks, cli_sub_tracks }
    started_at: Instant,
    completion: Option<oneshot::Sender<HashMap<String, serde_json::Value>>>,
}

impl TrackDumpRegistry {
    pub fn new() -> Self {
        Self {
            pending: DashMap::new(),
            next_id: AtomicU32::new(1),
        }
    }

    /// dump_id 발급 + PendingDump 등록 + (Sender 보유, Receiver 반환).
    /// expected 가 비면 즉시 finalize 시도 (audience 만 있는 방 등).
    pub fn start(
        &self, room_id: String, expected: HashSet<String>,
    ) -> (u32, oneshot::Receiver<HashMap<String, serde_json::Value>>) {
        let dump_id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        let dump = PendingDump {
            room_id, expected,
            received: HashMap::new(),
            started_at: Instant::now(),
            completion: Some(tx),
        };
        let needs_immediate_finalize = dump.expected.is_empty();
        self.pending.insert(dump_id, dump);
        if needs_immediate_finalize {
            self.try_finalize(dump_id);
        }
        (dump_id, rx)
    }

    /// 클라 REPLY 도착 시 호출. user_id 가 expected 에 없거나, 중복이면 무시.
    /// expected == received 면 즉시 finalize.
    pub fn deposit(&self, dump_id: u32, user_id: String, payload: serde_json::Value) {
        let should_finalize = {
            let Some(mut entry) = self.pending.get_mut(&dump_id) else { return };
            if !entry.expected.contains(&user_id) { return; }
            if entry.received.contains_key(&user_id) { return; }  // 중복 무시
            entry.received.insert(user_id, payload);
            entry.received.len() == entry.expected.len()
        };
        if should_finalize {
            self.try_finalize(dump_id);
        }
    }

    /// timeout 도착 시 REST handler 가 호출. 받은 만큼만 반환.
    pub fn finalize_on_timeout(&self, dump_id: u32) -> HashMap<String, serde_json::Value> {
        self.pending.remove(&dump_id)
            .map(|(_, d)| d.received)
            .unwrap_or_default()
    }

    fn try_finalize(&self, dump_id: u32) {
        if let Some((_, mut dump)) = self.pending.remove(&dump_id) {
            if let Some(tx) = dump.completion.take() {
                let _ = tx.send(dump.received);
            }
        }
    }
}
```

**자료구조 결정**:
- `next_id: AtomicU32` — counter 방식. random uuid 보다 단순 + 디버깅 가독성. wrap 시 충돌 가능하나 4_294_967_295 회 / 진단 빈도 감안 시 실무 무관
- `expected: HashSet<String>` — 사전 user 목록. deposit 시 멤버 검증 + 중복 응답 차단 두 역할
- `received: HashMap` — 응답 누적
- `oneshot::Sender` — 완료 시 한 번만 발사. timeout 경로는 별 finalize_on_timeout 으로 처리 (Sender drop → Receiver 가 RecvError → REST handler 가 finalize_on_timeout 호출)

### 6.3 REST handler (`crates/oxhubd/src/rest/admin.rs`)

```rust
async fn track_dump_handler(
    State(state): State<HubState>,
    Path(room_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<serde_json::Value>, AdminError> {
    verify_admin(&headers, &state.config)?;
    let t0 = Instant::now();

    // ── 단계 1: sfud snapshot fetch (단일 방) ──
    //   ROOM_LIST 의 변형이 아니라, 신규 admin op (ADMIN_ROOM_SNAPSHOT) 또는
    //   기존 admin snapshot 의 한 방 필터. handler/admin.rs::build_room_snapshot(state, room_id) 신설.
    let snap = sfu_handle(&state, opcode::ADMIN_SNAPSHOT, json!({ "room_id": &room_id })).await?;
    let participants = snap["rooms"][0]["participants"].as_array()
        .ok_or(AdminError::not_found("room not found"))?;
    let expected: HashSet<String> = participants.iter()
        .filter_map(|p| p["user_id"].as_str().map(String::from))
        .collect();

    // ── 단계 2: fan-in 시작 (dump_id 발급) ──
    let (dump_id, completion_rx) = state.track_dump.start(room_id.clone(), expected.clone());

    // ── 단계 3: WS broadcast TRACK_DUMP_REQ ──
    let req_body = json!({ "dump_id": dump_id, "room_id": &room_id });
    let req_body_bytes = serde_json::to_vec(&req_body).unwrap_or_default();
    //   pid=0 은 broadcast 발신 자리 — OutboundQueue 가 user 마다 새 wire pid 재발급.
    //   클라가 ACK 회신할 때 본 wire pid 를 사용. application 매칭은 body.dump_id.
    let req_wire = WireHeader::new_msg(opcode::TRACK_DUMP_REQ, 0).frame(&req_body_bytes);
    state.broadcast_to_room(&room_id, &[], &req_wire, opcode::TRACK_DUMP_REQ);

    // ── 단계 4: timeout 5s 대기 ──
    let cli_payloads = match tokio::time::timeout(
        Duration::from_secs(5), completion_rx,
    ).await {
        Ok(Ok(map)) => map,
        Ok(Err(_recv_err)) => HashMap::new(),  // Sender drop = 비정상 (방어)
        Err(_timeout) => state.track_dump.finalize_on_timeout(dump_id),
    };

    let missing: Vec<String> = expected.iter()
        .filter(|u| !cli_payloads.contains_key(u.as_str()))
        .cloned().collect();

    // ── 단계 5: join + verdict 산출 ──
    let dump = build_track_dump_json(
        &room_id, dump_id, snap, cli_payloads, missing,
        /* elapsed_ms */ t0.elapsed().as_millis() as u64,
    );
    Ok(Json(dump))
}
```

**ADMIN_SNAPSHOT (op=0x3002)** 의 현재 dead op 자리 활용 — 단일 방 snapshot fetch 용으로 박... 본 작업에서 살림. 기존 broadcast_admin 의 *type=snapshot* 자료가 이미 build_rooms_snapshot 결과를 그대로 직렬화하니, 동일 함수에 `room_id` 필터를 추가하여 단일 방 추출.

### 6.4 클라 → 서버 reply 수신 (`crates/oxhubd/src/ws/mod.rs::handle_client_message`)

```rust
if header.op == opcode::TRACK_DUMP_REPLY {
    // body schema: { dump_id: u32, room_id: String, cli_pub_tracks: [...], cli_sub_tracks: [...] }
    let body: serde_json::Value = if body_bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(body_bytes).unwrap_or(serde_json::Value::Null)
    };
    let dump_id = body["dump_id"].as_u64().map(|v| v as u32);
    if let Some(dump_id) = dump_id {
        let user_id = session.user_id().to_string();  // session 신뢰 — 클라 body 의 user_id 무시
        state.track_dump.deposit(dump_id, user_id, body);
    }
    // wire ACK_OK 즉시 회신 (전송단 통보)
    return Some(build_ack_ok(opcode::TRACK_DUMP_REPLY, header.pid, b"{}"));
}
```

**보안 정합**: user_id 는 `session.user_id()` 가 단일 출처. 클라 REPLY body 안 user_id 필드는 무시 (impersonation 방어). room_id 도 hub-local 검증 — `state.shadow.room_members(&body.room_id).contains(&user_id)` 로 멤버십 확인 가능 (선택 — 본 작업에서는 미적용, 향후 보안 강화 시).

### 6.5 REQ / REPLY body 스키마 (확정)

**`0x2701 TRACK_DUMP_REQ`** body:
```json
{ "dump_id": 17, "room_id": "R1" }
```

**`0x1702 TRACK_DUMP_REPLY`** body:
```json
{
  "dump_id": 17,
  "room_id": "R1",
  "cli_pub_tracks": [ { ...§1.4-A row per track... } ],
  "cli_sub_tracks": [ { ...§1.4-D row per track... } ]
}
```

클라가 `cli_pub_tracks` / `cli_sub_tracks` 두 배열로 자기 발행 트랙 + 수신 트랙을 한꺼번에 보고. hub join 단계에서 row 매칭 시 `track_id` + `ssrc` 기준 (src_user 의 publisher track 과 dst_user 의 subscriber track 이 동일 origin 으로 묶임).

### 6.6 derive 헬퍼 + admin snapshot 확장

`crates/oxsfud/src/signaling/handler/admin.rs`:
- `is_virtual_for(stream: &SubscriberStream, publisher_streams: &[Arc<PublisherStream>]) -> bool` 신규
- `origin_for(stream, publisher_streams) -> OriginDto` 신규 — `{ kind, wire_ssrc, publisher_origin_ssrc? }` (§1.6 정합)
- `src_user_for(stream, peers) -> Option<String>` 신규 — subscriber_stream → publisher_ref → user_id 역참조
- `build_room_snapshot(state, room_id) -> serde_json::Value` 신규 — `build_rooms_snapshot` 의 단일 방 필터 변종 (코드 중복 회피 위해 inner 헬퍼 분리 후 양쪽 재사용)
- SubscriberGate paused=false 도 노출 — 현재 `admin.rs:115` 의 `if paused` 분기를 `dump()` 결과 전체 노출로 변경

### 6.7 verdict / issues 자동 산출 (`build_track_dump_json` 안)

각 row 별:

```rust
fn compute_verdict(row: &TrackDumpRow) -> (Verdict, Vec<String>) {
    let mut issues = Vec::new();
    let mut worst = Verdict::Ok;

    // broken 우선순위
    if row.cli_pub.is_none() { issues.push("cli_pub_missing"); worst = Verdict::Broken; }
    if row.cli_sub.is_none() { issues.push("cli_sub_missing"); worst = Verdict::Broken; }
    if row.srv_pub.publish_state != "active" { issues.push("publish_inactive"); worst = Verdict::Broken; }
    if row.srv_sub.subscribe_state != "active" { issues.push("subscribe_inactive"); worst = Verdict::Broken; }

    // gate paused 분기 — reason="kf_pending" 은 warn, 그 외는 broken
    if row.srv_sub.gate.paused {
        if row.srv_sub.gate.reason.as_deref() == Some("kf_pending") {
            issues.push("kf_pending"); worst = worst.max(Verdict::Warn);
        } else {
            issues.push("gate_paused"); worst = Verdict::Broken;
        }
    }

    // cli_sub element 검사 (video only)
    if let Some(cs) = &row.cli_sub {
        if row.kind == "video" {
            if cs.element.videoWidth == 0 { issues.push("element_zero_size"); worst = Verdict::Broken; }
            if !cs.element.attached     { issues.push("element_not_attached"); worst = Verdict::Broken; }
            if cs.element.paused && !cs.element.muted {
                issues.push("element_paused_no_autoplay"); worst = Verdict::Warn.max(worst);
            }
        }
        if cs.track.muted { issues.push("track_muted_recv"); worst = Verdict::Warn.max(worst); }

        // mid / ssrc 양단 일치 검증
        if let Some(cp) = &row.cli_pub {
            if cp.transceiver.currentDirection == "sendonly" {
                // mid 일치는 row 단위에서 의미 없음 (publisher mid ≠ subscriber mid)
                // ssrc 일치 = srv_sub.origin.publisher_origin_ssrc == cli_pub.ssrc (Passthrough)
            }
        }
        if cs.transceiver.mid != row.srv_sub.mid {
            issues.push("mid_mismatch"); worst = Verdict::Broken;
        }
        // ssrc derive 검증: cli_sub.ssrc == srv_sub.wire_ssrc (= ssrc 필드)
        if cs.ssrc != row.srv_sub.ssrc {
            issues.push("ssrc_mismatch"); worst = Verdict::Broken;
        }
    }

    (worst, issues)
}
```

verdict 우선순위: `Broken > Warn > Ok`. `worst.max(other)` 단방향 갱신.

---

## §7 Phase 2: 클라 SDK 구현

### 7.1 신규 op 등록

`oxlens-home/core/constants.js`:
```js
OP = {
  ...,
  TRACK_DUMP_REQ:   0x2701,
  TRACK_DUMP_REPLY: 0x1702,
}
```

### 7.2 수집기 (`core/track-dump-collector.js` 신규)

```js
export async function collectTrackDump(sdk, dumpId, roomId) {
  const pubStats = await sdk.media.pubPc.getStats();
  const subStats = await sdk.media.subPc.getStats();
  const cli_pub_tracks = sdk._collectCliPubTracks(pubStats);  // §1.4-A
  const cli_sub_tracks = sdk._collectCliSubTracks(subStats);  // §1.4-D
  return {
    req_pid: dumpId,
    user_id: sdk.userId,
    room_id: roomId,
    cli_pub: cli_pub_tracks,
    cli_sub: cli_sub_tracks,
  };
}
```

`_collectCliPubTracks` / `_collectCliSubTracks` 는 engine.js 안 헬퍼 — 기존 telemetry.js 의 `_collectPublishStats` / `_collectSubscribeStats` 와는 분리 (Pull 전용, delta 없음, 누적값만, element/transceiver/pipe/self_view 풀 덤프).

### 7.3 signaling.js 분기

`_handleEvent` 의 default 위에 추가:

```js
case OP.TRACK_DUMP_REQ: {
  this.ack(op, pid);  // wire ACK 즉시
  const body = d;     // { dump_id, room_id }
  collectTrackDump(this.sdk, body.dump_id, body.room_id).then(payload => {
    this.send(OP.TRACK_DUMP_REPLY, { req_pid: body.dump_id, payload });
  });
  break;
}
```

---

## §8 Phase 3: 어드민 화면

### 8.1 index.html 구조 변경

#### 8.1.1 탭 row 신설 (메인 헤더 `<header>` 직후)

```html
<nav id="tab-nav" class="flex border-b border-white/10 px-5 flex-none bg-brand-surface">
  <button data-tab="live" class="tab-btn active px-4 py-2 text-sm font-medium text-white border-b-2 border-brand-rust">📊 Live</button>
  <button data-tab="track-dump" class="tab-btn px-4 py-2 text-sm font-medium text-gray-400 hover:text-white border-b-2 border-transparent">🔍 Track Dump</button>
</nav>
```

활성 탭: `border-brand-rust + text-white`. 비활성: `border-transparent + text-gray-400`.

#### 8.1.2 Live 탭 (기존 보존)

기존 `<div class="flex-grow flex gap-3 px-4 py-3 ...">` (index.html:95) 를 `<section id="tab-live">` 로 감싸기만. 내부 구조 변경 없음 → 기존 render-overview / render-detail / render-panels 그대로 동작.

#### 8.1.3 Track Dump 탭 (신규 section)

```html
<section id="tab-track-dump" hidden class="flex-grow flex flex-col gap-3 px-4 py-3 min-h-0 overflow-hidden">
  <!-- (1) 컨트롤 바 -->
  <div class="td-control-bar flex items-center gap-3 bg-brand-surface rounded-lg border border-white/10 px-3 py-2 flex-none">
    <label class="text-[10px] text-gray-500 uppercase tracking-wider font-mono">Room</label>
    <select id="td-room" class="bg-brand-dark border border-white/10 rounded px-2 py-1 text-xs text-white font-mono min-w-[120px]">
      <option value="">(방 선택)</option>
    </select>
    <button id="td-dump" class="px-3 py-1 bg-brand-rust hover:bg-brand-rust/80 text-white text-xs font-medium rounded">🔍 Dump</button>
    <button id="td-copy" disabled class="px-3 py-1 bg-white/5 hover:bg-white/10 text-gray-400 text-xs rounded border border-white/10 disabled:opacity-40">📋 Copy JSON</button>
    <span class="text-[10px] text-gray-500 uppercase tracking-wider font-mono ml-3">Last:</span>
    <span id="td-last" class="text-xs text-white font-mono">—</span>
    <label class="flex items-center gap-1 ml-auto text-[10px] text-gray-500 font-mono">
      <input type="checkbox" id="td-auto"> Auto 5s
    </label>
    <label class="flex items-center gap-1 text-[10px] text-gray-500 font-mono">
      <input type="checkbox" id="td-detail-mode"> Detail
    </label>
  </div>

  <!-- (2) 메인 = 좌 사이드 + 매트릭스 -->
  <div class="flex gap-3 flex-grow min-h-0">
    <!-- (2a) 좌 — Room Summary -->
    <aside class="w-[260px] bg-brand-surface rounded-lg border border-white/10 flex flex-col flex-none min-h-0">
      <div class="px-3 py-2 border-b border-white/10 flex-none">
        <h2 class="text-sm font-semibold text-white">Room Summary</h2>
      </div>
      <div id="td-summary" class="overflow-y-auto flex-grow p-3 text-xs space-y-3">
        <div class="text-gray-500 italic text-center py-8">Dump 버튼을 눌러 시작</div>
      </div>
    </aside>

    <!-- (2b) 우 — 4-Point 매트릭스 -->
    <div class="flex-grow bg-brand-surface rounded-lg border border-white/10 flex flex-col min-h-0">
      <div class="px-3 py-2 border-b border-white/10 flex-none flex items-center justify-between">
        <h2 class="text-sm font-semibold text-white">4-Point Matrix</h2>
        <div class="flex items-center gap-3 text-[10px] font-mono text-gray-400">
          <span class="flex items-center gap-1"><span class="w-2 h-2 rounded-full bg-green-500"></span>OK</span>
          <span class="flex items-center gap-1"><span class="w-2 h-2 rounded-full bg-yellow-500"></span>WARN</span>
          <span class="flex items-center gap-1"><span class="w-2 h-2 rounded-full bg-red-500"></span>BROKEN</span>
          <span class="flex items-center gap-1"><span class="w-2 h-2 rounded-full bg-gray-500"></span>NULL</span>
        </div>
      </div>
      <div class="overflow-auto flex-grow">
        <table class="w-full text-left border-collapse text-[11px] font-mono whitespace-nowrap">
          <thead class="sticky top-0 bg-brand-dark z-10">
            <tr class="border-b border-white/10 text-[10px] font-medium text-gray-500 uppercase">
              <th class="py-2 px-2">src→dst</th>
              <th class="py-2 px-2">kind</th>
              <th class="py-2 px-2">rid</th>
              <th class="py-2 px-2">[1] cli-pub</th>
              <th class="py-2 px-2">[2] srv-pub</th>
              <th class="py-2 px-2">[3] srv-sub</th>
              <th class="py-2 px-2">[4] cli-sub</th>
              <th class="py-2 px-2 text-center">판정</th>
            </tr>
          </thead>
          <tbody id="td-rows" class="divide-y divide-white/5"></tbody>
        </table>
      </div>
    </div>
  </div>
</section>
```

### 8.2 app.js — 탭/Dump/Copy/Auto/Mode 핸들러

```js
import { renderTrackDump, copyDumpJson } from './render-track-dump.js';
import { state } from './state.js';

// (1) 탭 전환 (Live ↔ Track Dump)
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => {
      const active = (b === btn);
      b.classList.toggle('active', active);
      b.classList.toggle('text-white', active);
      b.classList.toggle('border-brand-rust', active);
      b.classList.toggle('text-gray-400', !active);
      b.classList.toggle('border-transparent', !active);
    });
    const tab = btn.dataset.tab;
    document.getElementById('tab-live').hidden = (tab !== 'live');
    document.getElementById('tab-track-dump').hidden = (tab !== 'track-dump');
    if (tab === 'track-dump') refreshTdRoomSelect();
  });
});

// (2) Room 드롭다운 — 최신 snapshot 의 rooms 에서 추출
function refreshTdRoomSelect() {
  const select = document.getElementById('td-room');
  const current = select.value;
  const rooms = (state.latestSnapshot?.rooms || []).map(r => r.room_id);
  select.innerHTML = '<option value="">(방 선택)</option>' +
    rooms.map(r => `<option value="${r}">${r}</option>`).join('');
  if (rooms.includes(current)) select.value = current;
}

// (3) Dump 버튼
document.getElementById('td-dump').addEventListener('click', async () => {
  const roomId = document.getElementById('td-room').value;
  if (!roomId) { alert('방을 선택하세요'); return; }
  const btn = document.getElementById('td-dump');
  btn.disabled = true;
  btn.textContent = '⏳ Collecting...';
  try {
    const baseUrl = state.serverHttpUrl();  // ws://host:port → http://host:port 변환
    const resp = await fetch(`${baseUrl}/media/admin/rooms/${roomId}/track-dump`, {
      headers: { Authorization: `Bearer ${state.adminToken}` },
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${await resp.text()}`);
    const dump = await resp.json();
    state.currentDump = dump;
    renderTrackDump(dump);
    document.getElementById('td-last').textContent =
      `${new Date(dump.ts).toLocaleTimeString()} (${dump.elapsed_ms}ms, ${dump.rows.length} rows)`;
    document.getElementById('td-copy').disabled = false;
  } catch (e) {
    alert(`Dump 실패: ${e.message}`);
  } finally {
    btn.disabled = false;
    btn.textContent = '🔍 Dump';
  }
});

// (4) Copy 버튼
document.getElementById('td-copy').addEventListener('click', async () => {
  if (state.currentDump) await copyDumpJson(state.currentDump);
});

// (5) Auto-refresh 5s
let tdAutoTimer = null;
document.getElementById('td-auto').addEventListener('change', e => {
  if (e.target.checked) {
    tdAutoTimer = setInterval(() => document.getElementById('td-dump').click(), 5000);
  } else if (tdAutoTimer) {
    clearInterval(tdAutoTimer); tdAutoTimer = null;
  }
});

// (6) Detail mode 토글 — render-track-dump.js 가 currentDump 로 다시 그림
document.getElementById('td-detail-mode').addEventListener('change', e => {
  const sec = document.getElementById('tab-track-dump');
  sec.classList.toggle('detail-mode', e.target.checked);
  if (state.currentDump) renderTrackDump(state.currentDump);
});
```

### 8.3 render-track-dump.js (신규 모듈)

#### 8.3.1 진입점

```js
export function renderTrackDump(dump) {
  renderSummary(dump);
  renderRows(dump);
}
```

#### 8.3.2 좌 사이드 summary

- Room 헤더 (`room_id`)
- Dump 메타 (`dump_id`, `elapsed_ms`, `ts` 로컬 시간)
- Participants 목록 (`user_id`, `role`, `peer_state`) + `missing_users` 인 경우 빨강 ⚠ no reply
- Tracks 카운터 (✅ N / ⚠ N / ❌ N)
- Issues 목록 — `dump.rows` 의 `issues[].length > 0` row 만 추출, `src→dst kind: issue1, issue2` 형식

#### 8.3.3 매트릭스 row 렌더

**Compact mode (기본)** — row 1줄 + verdict badge, cell 은 핵심 1~2 필드만:
- [1] cli-pub cell: ssrc + `fps={fps} {bitrate}k`
- [2] srv-pub cell: ssrc + `{publish_state}` + (pli paused 시 `PLI⏸`)
- [3] srv-sub cell: vssrc + `{subscribe_state}` + (gate paused 시 `GATE⏸ reason`)
- [4] cli-sub cell: ssrc + `fps={fps} freeze={freezeCount}`
- 판정 cell: VERDICT_BADGE (ok 초록 / warn 노랑 / broken 빨강)

**Detail mode (toggle)** — row 클릭 없이도 모든 row 의 detail 펼침 본문 함께 표시 + 컴팩트 row 의 cell 에 더 많은 필드 (codec, mid, state 두 줄 등)

#### 8.3.4 행 클릭 → 상세 펼침 (Compact mode 에서만)

```js
tbody.querySelectorAll('tr.row-main').forEach(tr => {
  tr.addEventListener('click', () => {
    const idx = tr.dataset.rowIdx;
    const detail = tbody.querySelector(`tr.row-detail[data-row-idx="${idx}"]`);
    detail.classList.toggle('hidden');
  });
});
```

상세 패널 내용 — 4 객체를 grid 4 컬럼 `<pre>JSON.stringify(row[k], null, 2)</pre>` + 마지막에 `issues[]` 빨강 텍스트.

#### 8.3.5 색상 규칙 (Tailwind 클래스)

| verdict | row 배경 | badge |
|---|---|---|
| `ok` | `(default)` | `bg-green-500/20 text-green-300` ✅ |
| `warn` | `bg-yellow-500/5` | `bg-yellow-500/20 text-yellow-300` ⚠ |
| `broken` | `bg-red-500/5` | `bg-red-500/20 text-red-300` ❌ |

cell 안 *null* (cli_pub/cli_sub 미응답) — `text-gray-500 italic` "null"
가상 ssrc 강조 — `srv_sub.is_virtual=true` 일 때 ssrc 글자색 `text-orange-300` (한눈에 가상/원본 구분, 설계 §5.3 정합)
issues 안 핵심 키워드 — `gate_paused` / `kf_pending` 등 빨강 `text-red-300`

#### 8.3.6 Copy 동작

```js
export async function copyDumpJson(dump) {
  await navigator.clipboard.writeText(JSON.stringify(dump, null, 2));
  const btn = document.getElementById('td-copy');
  const orig = btn.textContent;
  btn.textContent = '✅ Copied!';
  setTimeout(() => { btn.textContent = orig; }, 1500);
}
```

### 8.4 state.js 추가 필드

```js
// 기존 state 객체에 추가
currentDump: null,         // 마지막 Dump 결과 (§1.3 골격 JSON)
adminToken: null,          // 기존 admin WS 인증과 동일 token (Bearer Auth)
serverHttpUrl: () => {     // ws:// → http://, wss:// → https:// 변환 헬퍼
  const wsUrl = document.getElementById('srv-url').value;
  return wsUrl.replace(/^wss?:\/\//, m => m === 'wss://' ? 'https://' : 'http://')
              .replace(/\/media\/admin\/ws$/, '');
},
```

### 8.5 화면 모드 (§5.6 설계 정합)

| 모드 | 토글 | 동작 |
|---|---|---|
| **Compact** | `td-detail-mode` 미체크 (기본) | row 1줄 + verdict badge, 클릭 시 상세 펼침 |
| **Detail** | `td-detail-mode` 체크 | 모든 row 의 상세 패널 항상 표시 (스크롤 길어짐), Copy 친화적 |

CSS 분기는 `<section id="tab-track-dump" class="detail-mode">` 의 클래스 토글:
```css
#tab-track-dump.detail-mode tr.row-detail { display: table-row !important; }
```

### 8.6 회귀 영향

- 기존 Live 탭의 render-overview / render-detail / render-panels / snapshot 모듈은 **무변경**
- index.html 의 기존 layout 안 콘텐츠도 무변경 — 단지 `<section id="tab-live">` 로 감싸기만
- WS 흐름 (`app.js:handleAdminMessage`) 변경 없음 — Track Dump 는 HTTP fetch 단독 경로

---

## §9 회귀 시나리오

1. **Conference 라이브** — 기존 Telemetry 탭 정상 작동, Push 3초 흐름 유지
2. **PTT (DC bearer)** — voice_radio → FLOOR_REQUEST/GRANTED/RELEASE 정상
3. **PTT (WS bearer)** — bearer='ws' → FLOOR_MBCP(0x2400) 정상
4. **SCOPE** — cross-room affiliate/select/deaffiliate 정상
5. **Admin Live 탭** — 기존 어드민 데이터 (snapshot/telemetry/sfu_metrics/agg_log) 정상 표시
6. **Track Dump 신규 탭** — Dump 버튼 → 5s 안 4-Point 매트릭스 표시, 누락 user 가 `missing_users` 에 표시, Copy 버튼이 JSON 클립보드 복사

---

## §10 정지점 + 부장님 결재

- **정지점 ①** = 본 지침 §1 명세 결재 (현재 자리)
- **정지점 ②** = Phase 1 완료 (서버) — 단위 테스트 + 신규 op 카탈로그 통과 후 보고
- **정지점 ③** = Phase 2 완료 (클라 SDK) — 수집기 단위 테스트 통과 후 보고
- **정지점 ④** = Phase 3 완료 (어드민 화면) + §9 회귀 시나리오 6/6 통과 후 보고

각 정지점에서 부장님 GO 사인 대기. 자율 진행 모드는 미적용 (큰 변경 면적).

---

*author: kodeholic (powered by Claude) — Claude (김대리+김과장 통합), 2026-05-20*
