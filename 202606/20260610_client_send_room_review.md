# 20260610 클라 SDK 송신/방관리 구조 검토 (설계 아님 — 검토 기록)

> 검토 세션. 확정 사항만 기록. 미해결·제안·이견 대기는 "확정 안 됨" 섹션으로 분리.
> 후속 설계서/작업지침은 별 세션 산출.

## 확정 사항

1. 방 목록 권위 = `engine.talkgroups` (코어 1급, user-scope)
   - `Map<roomId, Room>` 직접 보유. 별도 TalkGroup wrapper 계층 두지 않음
     (클라 Room 은 애초에 1인칭 객체 — '관계' wrapper 는 담을 게 없는 빈 껍데기, YAGNI)
   - 무전/컨퍼런스 도메인 구분 없이 단일 권위. duplex switch 시 방 소속 이주 방지
     (서버 RoomMode 폐기 = "방은 빈 그릇, duplex 는 트랙 속성" 결정의 클라 대칭)
   - 어휘 출신(무전)으로 역할 범위를 제약하지 않음 (talkgroup = 다방 관리 일반 어휘)

2. 구 `scope/scope.js` 의 문제 = 권위 아닌 '서기'
   - roomId 문자열만 보유, Room 핸들 목록 없음 → 다방 이벤트 room 동봉 불가
   - SCOPE_EVENT(0x2200) 수신 경로(applyEvent) 부재 → 강제 변경 시 영구 부정합
   - 상태 mutate 진입점 5곳 분산 + 서버 auto-select 규칙 클라 복제(추측)
   → 전이 단일 진입 `applyEvent()` 로 교체 (SCOPE ok / SCOPE_EVENT 합류)

3. LocalEndpoint 소유 = engine (1개, user-scope, 전 sfu 관통)
   - 담는 것: 장비 + 송신 의도 (track / constraints / muted / kind·source·duplex)
   - 방·talkgroup 소유 아님. select(R1→R2) 시 송신 장비 이사 방지
     (서버 pub_room = ArcSwap 포인터 스왑 대칭)

4. 논리/물리 scope 분리 (서버 Peer 재설계의 클라판)
   - 논리(LocalPipe): 장비+의도만. sender/transceiver 무지
   - 물리(Transport, sfu별): transceiver/sender/mid/ssrc 보유. pipe 객체 무지
     (서버 PublishContext 와 1:1 대칭, user×sfud = PC pair 1쌍)

## 확정 안 됨 (다음 세션 이월)

- "join 없이 청취만"(presence 축) 상용 인정 여부 — [질문] 미응답
- floor 다방 라우팅 / select→reconcile 파생 규칙 / applyEvent-Room 생명주기 계약
- 송신 reconcile 경계 채택 여부 (검토 중 제안, 미결재)
- scope → talkgroups rename 작업지침

## 부수 발견 (별 토픽 검토 대기, 본 검토 범위 밖)

> **처리 (2026-06-10 묶음1+2, 부장님 지시 — "track 멤버 폐기 포함 진지하게")**: ①②③④ + sender setter
> 우회로 해소, ⑤는 주석 정정(getBitrate 이동은 보류). 송출 상태축 5→2(trackState FSM + _heldTrack),
> track=파생 getter(직접 대입 즉사), _upstreamPaused 폐기→device-mute 는 suspend/resume 갈음,
> 종단 epoch 로 lock 큐 잔여 무력화, RTP 차단 holdRtp() 게이트화. 0609 §6.6 절충(ACTIVE 하위 플래그)은
> 본 단일화로 대체.
> **+묶음3 (부장님 지적 — "base 가 너무 많이 들고 있다")**: base 합집합 해체 — 전용 멤버 강하.
> send(_sender/sender getter/getRtpSender)→LocalPipe, recv(rtx_ssrc/video_pt/rtx_pt/_muted/_volume/
> _pendingShow)→RemotePipe + 死 fallback 2곳 제거. base = 식별/intent + transceiver + element 출력만.

- transport.js `deactivatePublishTrack` 에 `pipe.sender = null` 직접 대입 잔존
  (local-pipe.js unbindSender 게이트 원칙 위반 — Phase 정합 어긋남)
- transport.js `addPublishTrack` 의 `tx.sender.replaceTrack(null)` 직접 호출
  (Pipe 유일 게이트 원칙 위반 + LocalPipe `_trackLock` 직렬화 밖)
- LocalPipe "송출 여부" 축 5개(trackState/muted/_upstreamPaused/_savedTrack/sender.track)
  → 부정합 표현 가능. 서버 TrackType 단일권위화와 동형 문제
- LocalPipe `release`/`deactivate`(동기 종단)가 `_trackLock` 관통 → 큐 잔여 작업이
  RELEASED/INACTIVE 를 되살릴 수 있음 (interleaving 구멍)
- transport 헤더 "webrtc 종속 단일 응집처" 거짓 — 실제 2분할(PC/SDP/DC=Transport,
  sender/track=Pipe). 단 LocalPipe `getBitrate()` 의 sender.getStats() 는 틈⑫ 충돌

---
author: kodeholic (powered by Claude)
