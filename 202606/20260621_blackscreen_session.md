# 20260621 검은화면 디버깅 세션 — 미해결 (사실 기록)

> PTT video 일시 멈춤(transient) 디버깅. 근본 미해결. 측정으로 배제/검증한 것과 남은 것만 기록.
> author: kodeholic (powered by Claude) · 2026-06-21

---

## 증상 (확정)
- PTT video 가 수 분간 멈췄다가 **저절로 복원**. audio 는 정상.
- 복원 트리거 = **publisher keyframe 100초 주기** (서버로그 `keyframe arrived c9e5acc1` 간격 ~100초).
- 멈춤 순간 user: video RECEIVED/framesDecoded 정지 + jb 폭증(1889~3496ms), audio RECEIVED 흐름.

## 커밋 (검증됨)
- **517db3c** subscribe SDP m-line 순서 안정화 — `collect_subscribe_tracks` 가 mid 순 정렬.
  - 원인: `other_participants`(DashMap iter)+slot push 순서 비결정 → re-nego m-line 순서 흔들림 →
    클라 `setRemoteDescription` "m-lines order doesn't match" 거부.
  - 검증: 부장님 확인 — 콘솔 에러 사라짐. (단, 검은화면 자체는 별개로 잔존)
- 7386651 half SR Phase 1 (기존). NTP **원본** 유지 = 정상 (now 직접 normalize 가 오히려 해악, 아래).

## 측정으로 배제 (stash = 폐기/재설계 대상)
- **stash@{0} NTP normalize(now 직접 SR NTP)** — **jb 누적 근본, 폐기.**
  - NTP normalize 적용 시 jb 2274ms → stash 후 3.18ms. 명확한 인과(부장님 "한 변경씩 빼라" 방법).
  - half SR 의 NTP **원본**(libwebrtc 상대 origin)이 정답. now 직접이 playout time 망가뜨림.
- **stash@{1} republish 수정(rewrite_in_place ssrc 변화 감지→pending_keyframe)** — **floor 깸, 재설계 필요.**
  - 캠 republish ts 점프는 잡으나, floor 재획득(switch_speaker) 경로도 건드려 회귀.
  - 재설계 방향: switch_speaker 안 불린 캠 republish 만 트리거(캠 한정).
- **PLI governor `keyframe_already_arrived`(judge_server_pli, pli_governor:382)** — 곁가지.
  - 서버는 governor 와 무관하게 keyframe 을 egress 로 이미 relay 중(100초 주기). PLI 막아도 keyframe 은 나감.
  - = governor 고쳐도 keyframe relay↔U01 미수신이면 멈춤 안 풀림. 근본 아님.

## 핵심 미해결
- **멈춤 시작 원인 미확정.** 멈춤 순간:
  - SFU egress emit(c9e5acc1) **흐름** + `[EGRESS] FAIL=0`(send_to Ok).
  - U01 video RECEIVED **정지**, audio RECEIVED **흐름** (같은 BUNDLE socket인데 video만).
- = **SFU egress ↔ U01 수신 사이 video 단절** 인데, **SFU trace 로는 내부 emit(socket.send 직전)까지만** 보임.
  실제 UDP 송신/U01 NIC 도달/U01 디코딩은 SFU trace 사각. "SFU 가 보냈는데 U01 미수신" 단정은 근거 부족.
- 의심 후보(미확정): SFU socket.send_to Ok ≠ 실제 전송(OS sendbuf), video 대역(ENV net=8.2Mbps throttle),
  클라 디코더/jb. **셋 다 측정 안 끝남.**

## 다음 (해야 할 것)
1. SFU **실제 socket.send 카운트**(emit 대비) — video 만 send 누락/적체 되는지 (run_egress_task 계측).
2. 클라 **webrtc-internals**(U01 video inbound) — packetsReceived/nackCount/frameDropped 직접.
3. ENV net throttle(8.2Mbps/50ms) 의 video 대역 영향 — throttle off 시 재현 여부.

## 방법론 교훈 (부장님 지적 — 반드시 지킬 것)
- transient 멈춤은 **복원 후 측정 무의미**. 멈춤 순간에 **user 2회(증상 덤프) + trace 동시**로 잡아야 함.
- 충분히 확인 전 결론 금지. 측정 1~2개로 단정 → 매번 함정(죽은 ssrc / getStats 캐시 / measure 오류).
- "서버" 모호 금지: 미디어=SFU(oxsfud) UDP 직송, 시그널링=hub. video 검은화면은 SFU↔U01 직통.
