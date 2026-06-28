# oxe2e 봇 악조건 확장(S/L 축) — 완료 보고

- author: 김과장 (Claude Code)
- 작성: 2026-06-27 (세션 0627r)
- 근거 설계: `20260627q_oxe2e_bot_adversary_design.md` (B1~B6, 안전성 축 채우기 30→90)
- 분업: B4 서버 자살 관문만 부장님 협조 영역 — 나머지 자율 진행(준자율).

---

## 6묶음 결과

| 묶음 | 등식 | 축 | 결과 | 커밋 |
|---|---|---|---|---|
| **B2** 무권 op | authz_denied | S2 권한 | ✅ | f78a3bd |
| **B1** 악조건 송신 | isolation_baseline | S1 격리 | ✅ | 39c055b |
| **B3** RTCP 종단 | rtcp_terminate(RR+SR) | S3 누설 | ✅ | 52cd4d2·b44b59e |
| **B6** L4 복구 | recovery_signal | L4 복구 | ✅ | 7388a7a |
| **B5** 급사 회수 | floor_failover | L1 급사 | ✅ | cfe581b |
| **B4** 과다 자원 | (서버 결함 발견) | S4 자원 | ⚠ 서버 결함 | ea74985 |

pytest 78 passed. 안전성 축(S1·S2·S3) + 생명성(L1 경합·급사, L4) 채움 — 설계 낙관 90 근접.

## 핵심 — 봇 RTCP 송신 토대(분수령 돌파)

설계가 "막힐 공산 -10"이라던 **B3·B5 두 분수령 모두 통과**:
- **B3**: aiortc `_send_rtp` 가 `is_rtcp` 판별로 RTCP 도 SRTCP protect → 봇 RR/SR/NACK 송신 가능. `transport.send_rtcp` 신설.
- **B5**: `FLOOR_PING_TIMEOUT_MS=5s` 확인 → 급사 회수는 서버 정상(영구점유 아님), 8초 run 이 timeout 직전이라 미관측이었을 뿐.

이 토대로 **known-gap 4개 실제 해제**(GAP-rtcp-sr, GAP-S3, GAP-L4, GAP-L1) — 회피 아닌 실해제.

## 봇 능력 신설(공리1 유지 — 송신 사실만 dump, 판정은 verifier)

- `publish_audio_unauth`(미가입 방 publish, B2) / `send_adversary_rtp`(미약속 RTP, B1)
- `send_receiver_report`(RR) / `send_sender_report`(SR) / `send_nack`·`send_nack_probe`(B3·B6)
- `kill`(ROOM_LEAVE 없는 급사, B5) / `publish_flood`(tracks 300개, B4)
- loader: unauth_ssrcs / adversary_ssrcs / rtcp_detail(RR·SR 내용) / rtx_ssrcs

## ★서버 결함 2개 발견 (다음 세션 서버 수정 — 부장님 분업)

1. **GAP-S4-resource-unbound** (B4): 서버가 과다 publish(300 tracks) 거부 없이 전부 수용 → 같은 방 정상 봇 sub PC 마비(정상 fan-out RTP 0). 서버 생존하나 기존 봇 무영향 깨짐 = 자원 유계 가드 부족. adv_resource 별 격리.
2. **GAP-TOPO-crossroom-dynamic-fanout** (0b): cross-room affiliate 동적 publish forward 누락(통지 O / RTP 0).

둘 다 "봇이 시험 쳤는데 서버가 떨어짐" = 서버 오류. 서버 가드 수정 후 등식(resource_bound / under) 정합.

## 작업 규율 (부장님 지적 반영)

- B5 미커밋 보류 지적 → 분별(ping_timeout 실측)로 "서버 정상" 확인 후 완성 커밋. 막힘은 보류 말고 실패/격리/GAP 명시 처리([[feedback_no_uncommitted_blocked_work]]).
- B4 도 보류 없이 서버 결함 발견 + GAP-S4 등록 + 토대 커밋으로 실패 처리.

## 백로그
- 서버 수정(부장님 분업): GAP-S4 자원 유계 가드 + GAP-TOPO cross-room forward + SRV-0625 simulcast track_id.
- 서버 수정 후: resource_bound(S4) + under(cross-room) 등식 정합.
- 0c cross-sfu(보류), 봇 twcc-seq(GAP-twcc), SUBSCRIBE_LAYER(GAP-layer-switch).
