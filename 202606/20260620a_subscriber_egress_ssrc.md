# 세션 기록 2026-06-20a — subscriber egress_ssrc 단일화

> lab 디버깅(3 버그) → ssrc 2중 관리 발견 → egress_ssrc 단일화 설계·구현·검증 → half pub 누적 증상 발견(미해결).

---

## 1. 한 일

### 1-1. lab 디버깅 → 3 버그 수정 (선행, 별개 커밋)
캠 unpub/republish timeout 추적에서 연쇄 발견:
- **unpublish 응답 pid=0** — `handle_publish_tracks_remove` 가 pid 파라미터를 안 받아 `Packet::ok(.., 0, ..)` 하드코딩 → 클라 OutboundQueue 가 요청 pid 매칭 못 해 영구 inflight → republish 질식. (`8f1308a`)
- **전송 위반 3종 + rate limit** — frame too large / header decode / body parse 는 신뢰 불가 피어 → **연결 종료**. rate limit(60/s) 영구 폐지(클라 흐름제어 신뢰). telemetry 70KB(SDP 4개 통째) frame too large 의 진짜 원인. (`a1dc6bc`)
- **ROOM_CREATE active_speaker 플래그** — 방 단위 active-speaker 전송 토글(기본 꺼짐), 디버깅 로그 노이즈 제어. (`2702aa2`)

### 1-2. ssrc 2중 관리 발견 → egress_ssrc 단일화 (본 세션 핵심)
- 신원표 "통보 ssrc ≠ fanout ssrc" 어긋남 추적 → **근본: `SubscriberStream.vssrc`(☆복사본)가 `PublisherStream.vssrc`(★진실)의 cold-path 복사이고, republish 시 `add_subscriber_stream` idempotent(mid recycle)가 갱신을 차단**.
- 대명제 확정: **egress_ssrc = "그 stream 속성의 origin"** (Direct/full→publisher ssrc, ViaSlot/half→Slot.virtual_ssrc, sim→PublisherStream.vssrc). 갱신 트리거는 **Direct republish 하나**로 수렴.
- 구현(`e94339e`):
  - 1단계: `vssrc → egress_ssrc` 개명 (필드/함수 `by_egress_ssrc`/인덱스/주석).
  - 2단계: `egress_ssrc` AtomicU32 가변화 + `add_subscriber_stream` idempotent 보정 (egress 다르면 in-place store + `reindex_subscriber_egress`. stream 보존 → gate/stats/attach 유지 = A안).

---

## 2. 커밋 (oxlens-sfu-server, main)

| 해시 | 내용 |
|------|------|
| `8f1308a` | unpublish 응답 pid=0 → 요청 pid |
| `a1dc6bc` | 전송 위반 3종 연결 종료 + rate limit 폐지 + max 1MB |
| `2702aa2` | ROOM_CREATE active_speaker 플래그 (기본 꺼짐) |
| `e94339e` | **subscriber egress_ssrc 단일화 (1+2단계)** |

## 3. 설계 문서 (context, 부장님 commit 대기)

- `design/20260620_subscriber_egress_ssrc_design.md` — §0 대명제 / §3 케이스 점검 / §8 클라 전달 규약(TRACKS_UPDATE vs TRACK_STATE)
- `design/20260620_half_republish_substream_leak_symptom.md` — **미해결 증상**

## 4. 검증

- **oxe2e 5/5 PASS**: conf_basic / duplex_cache / ptt_rapid / simulcast_basic / telemetry_collect.
- **lab 실측**: republish 시 U01 out egress `0x01A18AEF → 0xF16B3399` 갱신 + trace forward origin_seq 연속 = 버그 해소. full↔half egress 불변 확인.

## 5. 미해결 (다음 세션 1순위)

**half pub → SubscriberStream Direct 누적** (SUB_STREAMS 4→5, Direct video 2개).
- `full→unpub→republish→half switch→half unpub→half pub` 흐름 6단계에서 발견.
- 증상/절차/단서: `design/20260620_half_republish_substream_leak_symptom.md`.
- ⚠ **egress_ssrc 수정 부작용 여부 미확인** — git stash 후 재현 비교가 최우선.

## 6. 교훈 (김과장 디버깅 실패 — 반복 금지)

- **신원표 ssrc(정적)로 forward(동적) 단정 금지** → trace 패킷 실증 먼저. 본 세션에서 "검은 화면/dangling/리라이팅" 등 환각을 수차례 냄. trace 5초면 끝날 걸 코드 추론으로 헛다리.
- **`vssrc` 명명 함정** — non-sim 에선 가상이 아니라 실 ssrc. 변수명에 휘둘려 오독 → `egress_ssrc` 개명으로 해소.
- **부장님 반증 신호 무시 금지** — "정상일 수도/잘 나온다/pub인데 sub 왜" 가 다 맞았는데 신원표 숫자 고집.
- CLAUDE.md 행동원칙 `AGG LOG → TRACK IDENTITY → 코드 경로` 에서 **TRACK IDENTITY(신원표) 다음 패킷 실증(trace)을 건너뛰지 말 것**.
