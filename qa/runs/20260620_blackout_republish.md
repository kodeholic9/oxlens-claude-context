# 검은화면 정밀 재현 — half republish 사이클 (2026-06-20)

> 발언권 잡은 채 camera half unpublish→republish 반복 시 간헐 검은화면.
> 측정: Playwright 2탭(U01 송신/U02 수신) + oxadmin trace(slot egress) + oxsfud 로그.
> 도구: 신규 qa(`oxlens-home/qa/qa.js`, sdk 기반).

## 설정
- U01(half mic+camera) ↔ U02(half mic), 방 R01(sfu-1), U01 발언권 무중단 유지.
- U01 `camera` unpublish → 2s → republish, **27회 반복**(180초).
- 측정축:
  - U02 `RemoteStream.getStats()` 150ms 폴링 → kf/fd/pkts/pliCount 타임라인.
  - `oxadmin trace U02 0x4A9BE4B1 --out --detail` (slot egress, IDR 패킷 덤프).
  - oxsfud 로그 (U02 PLI 수신, REWRITE keyframe, PUBLISH_TRACKS).

## 결과
| 항목 | 값 |
|---|---|
| 검은화면(첫 키프레임까지) | 간헐 — c2=**13.9s**, c3=**7.6s**, 정상 평균 ~0.9s |
| U02 PLI 재요청(서버 ingress, 200초) | **8회** (republish당 0.3회) — 거의 안 보냄 |
| 그 중 dropped(publisher not found) | 4회 |
| REWRITE keyframe arrived (publisher→rewriter) | **64회** |
| slot egress IDR(`7c 85`, 실제 U02 송출) | **2개** |

## 두 모순 규명 (부장님 제기)
1. **"못 받으면 브라우저가 PLI 재요청 안 하나?"**
   → U02 PLI 8회뿐. **키프레임 못 받아도 재요청 거의 안 함.** c3은 7.6초 검은인데 PLI 0회.
2. **"키프레임이 slot까지 나갔다는데(REWRITE keyframe arrived) U02는 왜 못 받나?"**
   → REWRITE 인식 64회 vs egress IDR 2개. **키프레임의 97%가 slot egress_rtp로 송출 안 됨.**
   → `[PTT:REWRITE] keyframe arrived`(rewriter 인식) ≠ 실제 egress 송출.

## 근본 (확정)
체인:
1. U01 camera **republish → 서버가 U02에게 새 트랙 통지 → U02 재구독**(TRACKS_READY **27회 = republish 27회와 1:1**).
2. U02 재구독 = slot `SubscriberStream` **Arc 재생성** + subscribe re-nego.
3. 그 race 동안 `slot.subscribers`의 옛 Weak가 dead(`upgrade()` 실패) 또는 `is_subscribe_ready=false`
   (`participant.rs:91` = subscribe PC media ready) → U01 키프레임 **broadcast→forward 에서 skip**(`publisher_track.rs:922/936`).
4. → `ptt_rewriter.rewrite` 는 키프레임 prefan **64개 성공**(`keyframe arrived`)인데 **egress_rtp IDR 2개**만 송출(62 skip).
5. + **U02 PLI 재요청 부재**(200초 8회) → 키프레임 영영 미수신 → 검은화면.
- 0620b RECON-2(재구독 키프레임 사이클) 정합. "framesDecoded=0, pkts 정상, 키프레임만 차단"의 정체.

## 해결 방향
- **half slot 은 vssrc 고정** → republish 가 U02 **불필요 재구독을 유발하지 않게**(slot 구독은 유지, 트랙만 교체).
- 또는 재구독 완료 후 `slot.subscribers` 갱신과 키프레임 broadcast 를 **동기**(재구독 직후 키프레임 강제 재송출).

## 측정 한계
- U02 탭이 background → `setInterval` throttle 가능. U02 클라 pkts/fd 정지(c5~)는 측정 artifact일 수 있음.
- **서버측(egress IDR 2 / PLI 8 / REWRITE 64)은 throttle 무관 신뢰.**

## 덤프 (raw)
- `/tmp/blackout_dump/slot_egress.log` — slot egress trace 3736패킷, IDR 2개 (`7c 85` ×2, 시각 22:04:43.3 / 22:06:04.9)
- `/tmp/blackout_dump/server_events.log` — 479줄 (PLI/REWRITE/PUBLISH_TRACKS/TRACKS_READY/RTP:GAP)

## 다음 (근본 확정)
- `ptt_rewriter.rs:288` keyframe arrived → `subscriber_stream::forward` egress_rtp 경로에서 **왜 IDR 64→2로 드롭되는지** 코드 분석.
- U02 PLI 미발행 원인 — half slot 재구독 시 디코더 keyframe-wait 상태 점검.
