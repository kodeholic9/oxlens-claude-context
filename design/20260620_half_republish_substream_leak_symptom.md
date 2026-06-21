# [증상] half republish → SubscriberStream Direct 누적 (2026-06-20)

> 상태: **미해결 / 새 세션 디버깅 대상.** 증상·절차·단서만 기록 (원인 단정 안 함).
> 발견: `20260620_subscriber_egress_ssrc` 1+2단계 수정 후 lab 검증 중.
> ⚠ 본 egress_ssrc 수정의 **부작용 여부 미확인** — 새 세션 1순위로 git stash 후 재현 비교.

---

## 0. 한 줄 요약

U02 가 캠을 `full → unpub → republish → half switch → half unpub → half pub` 순으로 토글하면,
구독자 U01 의 **Direct video SubscriberStream 이 정리 안 되고 누적**(SUB_STREAMS 4→5, Direct 2개)된다.

---

## 1. 환경

- 서버: 1+2단계 egress_ssrc 수정 반영 바이너리. R01 = sfu-2.
- U01(구독자, 캠 안 켬) / U02(발행자, 캠 토글).
- 검증 도구: `oxadmin room R01` (신원표) + `oxadmin trace <user> <ssrc> <dir> --sfu sfu-2` (패킷 실증).

---

## 2. 절차 (시간순) — ★ 5단계까지는 정상, 6단계가 증상

| # | 동작 | U01 out video egress | 판정 |
|---|------|----------------------|------|
| 1 | U01/U02 R01 입장, mic/cam **full pub** | — | |
| 2 | U02 캠 **unpub** | `0x01A18AEF` 보존(RTP 0) | 정상(caching) |
| 3 | U02 캠 **republish**(`0xF16B3399`) | `0x01A18AEF` → **`0xF16B3399` 갱신** | ✓ 2단계 보정 작동 (trace forward origin_seq 연속) |
| 4 | U02 **full→half switch** | `0xF16B3399` **불변** | ✓ §3 (Direct 보존, active 전환) |
| 5 | U02 캠 **half unpub** | `0xF16B3399` 보존(RTP 0) | ✓ §8 (half unpub 개인통지 없음) |
| 6 | U02 캠 **half pub**(`0xCDD461AC`) | **`0xF16B3399` + `0xCDD461AC` 2개 누적** | ✗ **증상** |

---

## 3. 현상 (6단계 직후 `oxadmin room R01`)

```
U02   0xCDD461AC  --in   video  half          ← U02 현재 video (half, 새 ssrc)
U01   0xF16B3399  --out  video  VideoNonSim    ← 옛 Direct (RTP 0)
U01   0xCDD461AC  --out  video  VideoNonSim    ← 새 Direct (RTP 0)
```
- **SUB_STREAMS U01 = 4 → 5** (Direct video 2개 누적)
- 둘 다 **VideoNonSim(Direct)** — half publisher 인데 ViaSlot 이 아님
- `trace`: 두 ssrc 모두 **forward 0** (half 미발화 → RTP 송출 없음. **검은 화면 아님** — 애초에 송출 전)

---

## 4. 의문 (단정 안 함 — 두 갈래)

1. **half pub 인데 Direct(VideoNonSim) 생성** — `collect_subscribe_tracks`(helpers.rs:252) `if duplex==Half { continue }` (half=Direct skip 예상)와 어긋남.
2. **옛 Direct(`0xF16B3399`) 미정리** — full→half→unpub→half pub 흐름에서 보존 stream 이 정리 안 되고 누적.

가능 시나리오:
- (A) 클라가 **full pub → 즉시 half switch** 순서면 → full pub 이 Direct 생성 후 half 전환으로 NOTE 만 half = §3 정상. 단 옛 보존 누적은 별개.
- (B) 클라가 **직접 half pub** 이면 → collect:252 skip 위반.

---

## 5. 디버깅 단서 (새 세션 1순위 순)

1. **egress_ssrc 수정 부작용 여부 — git stash 후 재현 비교** (최우선). 수정 전 동일 흐름에서 누적됐는지.
2. **클라 pub 시퀀스** — lab 콘솔에서 6단계가 `full pub→half switch` 인지 직접 half 인지. `mid` recycle vs 새 m-line. (TRACKS_UPDATE/TRACK_STATE/SUBSCRIBE_LAYER 순서)
3. **`collect_subscribe_tracks` half 경로** — helpers.rs:252 skip + tracks JSON push(284) 에서 half 트랙이 Direct `attach_targets` 에 들어가는지.
4. **SubscriberStream 보존 정리 누락** — `track_ops` PUBLISH_TRACKS remove 가 `release_subscribe_track` 미호출(stream 안 지움). full→half(§3 보존) + unpub(보존) 가 겹쳐 누적.
5. **2단계 보정과의 관계** — `add_subscriber_stream` idempotent 보정은 **mid 동일** 시 egress in-place 갱신(1개 유지). **mid 다르면** 새 stream(누적). 6단계 mid 가 3단계와 다른지 = 누적 직접 원인 후보.

---

## 6. 재현 절차

- R01, U01 구독(캠 off) / U02 캠 토글:
  `full pub → unpub → republish → full→half switch → half unpub → half pub`
- 각 단계 `oxadmin room R01` + 의심 ssrc `trace`.
- SUB_STREAMS 증가 = 누적 신호.

---

## 7. 관련 문서

- `20260620_subscriber_egress_ssrc_design.md` — egress_ssrc 단일화 (1+2단계, 본 증상의 직전 작업)
- §3 케이스 점검 / §8 클라 전달 규약 — full↔half / half pub 기대 동작


oxadmin trace U01   0xE194429D  --out --sfu sfu-1 --detail