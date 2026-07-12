# 20260712c — GAP 2건 실측 보고 + GAP-S4 수리 설계 초안 (결재용)

> author: kodeholic (powered by Claude)
> 실측: 김대리 (본 세션, 부장님 "실측 먼저" 지시). 서버 HEAD = aa7717c(SRV-0712 포함) 라이브.

---

## §1 GAP-TOPO-crossroom-dynamic-fanout — ★해소 확인 (설계 판단 불요, 종결)

- **실측**: `crossroom_dynamic`(신규 — botD listen=[X,Y] 접속 완료 후 botB 가 Y 에
  join_at 3 동적 publish) → **botD 가 RTP 271pkt 수신(3.5~9.4s)**. 0627n 의
  "통지 O / forward 0" 재현 안 됨.
- **판정**: 0709 fan-out 개편(38ecf5d — 다운스트림 논리 PublisherStream 소유)이
  cross-room 동적 attach 를 함께 해소. 결함 수리가 구조 개편에 흡수된 사례.
- **조치 완료(4ac0876, push 됨)**: 격리 해제 + `crossroom_completeness`(under 등식,
  isolation 의 쌍둥이) + `crossroom_dynamic` 정규 시나리오(재발 가드) + 음성 픽스처 3.
  영향권(conf_crossroom/ptt_multiroom/ptt_scope_relay) 재검증 PASS. run-all 40종 체계.

## §2 GAP-S4-resource-unbound — 재현 확정 + 근인 반절 규명 (수리 설계 필요)

### 실측 (adv_resource 단독, 별 격리 준수)

| 항목 | 결과 |
|---|---|
| 재현 | **확정** — 0627q 와 동일. botADV 300 tracks 전부 수용(에러/경고 로그 0), 같은 방 정상 봇 botB·botC **상호 RTP 0**(위반 1804). 서버 프로세스 생존(restart 0) |
| 상한 부재 좌표 | `track_ops.rs handle_publish_tracks` — tracks 수 무검증(3002 는 codec 만). **MidPool 은 u32 무한 증가**(`peer.rs:253 acquire` — next_mid+=1, 상한 없음). 0627 의 "MID 풀 u8=256 고갈" 가설 **기각**: 고갈조차 안 하고 전부 수용 |
| 시그널링 블로킹 | **기각** — flood 처리(21:01:09.866) 33ms 뒤 botB publish 즉시 처리(09.899) |
| 클라(봇) 한계 | **기각** — 현 봇은 intercept 후킹(트랙 수 무관)이고, 정상 봇 sub PC 에 **RTCP 5건 도착**(ICE/DTLS/SRTP 생존). TRACKS_READY 처리 로그 존재 |
| 절단 마디 | **RTP forward 만 0** — 302 유령 스트림(RTP 없는 등록만) 하에서 정상 스트림의 구독 attach/forward 상태가 오염되는 것으로 좁혀짐. RTCP(SR relay)는 egress_tx 큐 경유라 살아있는 것과 정합. **정확 좌표는 trace 필요**(로그 154k 줄 — 수리 설계의 작업 0) |

### 수리 설계 초안 (결재 대상 — 결정 4)

- **D1 상한 단위·수치**: 요청당 `tracks.len() ≤ 8` + **user 당 활성 트랙 ≤ 16** 이중 가드
  (권고). 근거: 현 정상 최대 = audio + camera(sim 논리 1) + PTT half 조합 — user 당
  2~4 트랙, 여유 4배. 요청당 가드만으론 반복 호출 우회 가능 → user 누적이 본 가드.
  방당 총량은 capacity(1000) 존재 — 트랙 총량 가드는 후속 판단.
- **D2 거부 형식**: 초과분 부분 수용 금지, **요청 전체 Denied**(클라 상태 불일치 방지).
  에러 코드는 기존 체계 충돌 검사 후 신설(0703 감사에서 코드 충돌 이력 — 전수 확인 의무).
  wire 계약 추가이므로 소비자 전수조사(웹 SDK·봇·Android) 후 출하.
- **D3 수리 완료 기준**: `resource_bound` 등식 신설(과다 요청 Denied + 기존 정상 봇
  무영향) + adv_resource 별 격리 해제(run-all 정규 편입).
- **D4 근인 별건**: 상한을 넣으면 flood 재현은 봉쇄되지만, **forward 오염 근인은 미규명**
  — 다른 형태(정상 범위 내 누적·재접속 반복 등)로 재발 가능성. trace 로 절단 마디
  확정하는 규명 작업을 상한과 별건으로 둘지, 상한만으로 종결할지 부장님 판단.

### 우선순위 참고

S4 는 악조건(오사용/공격) 방어라 정상 기능 경로가 아니고, 상한 가드(D1~D3)는 서버
변경 소폭(진입 검증 + 카운터)·클라 무영향(초과는 애초에 비정상 요청). D4(근인 trace)가
실질 비용의 대부분.

## §3 D1~D3 집행 결과 (20260712, 부장님 "진행해" — 같은 세션)

- **서버**(track_ops.rs + config.rs): add 한정 이중 가드 — 요청당 `PUBLISH_MAX_TRACKS_PER_REQ=8`
  / user 활성 논리 스트림 `PUBLISH_MAX_ACTIVE_STREAMS_PER_USER=16`, 초과 = **3003 전체 Denied**
  (부분 수용 없음). 3003 = 미사용 확인(기존 1001/2001/2004/2101/2102/3000/3002), sdk0.2 는
  미지 코드 = 일반 reject 라 additive(2001/2003/2004 만 특수 처리 — 소비자 조사 완료,
  oxrtc/Android 레포는 로컬 부재). 카운트 단위 = 논리 스트림(register_stream 이 (kind,mid)
  분화 — flood 300 audio 도 300 스트림이라 유효. mid 생략 우회는 (kind,source) 병합이라
  트랙이 안 늘어 자체 무해).
- **단위 3 신설**(요청당 초과 / 누적 8+8+1 우회 / remove 반영 재-add) — cargo 273/273.
  remove audio 분기는 kind 전부 제거(기존 동작 — 실서비스 audio 1개와 등가) 재확인.
- **oxe2epy**: `resource_bound` 등식(거부 존재 + 수용 ≤16) + flood 봇 per_req 분할(반복
  우회 축) + adversary ssrc 마커 → 정합 등식 4곳(identity/send_honest/track_id_returned/
  fanout_complete) 악조건 제외 보정(가이드 §3 원칙 정합화) + 픽스처 4. pytest 116/116.
- **라이브**(재기동 후): botADV 단발 300 → Denied 1 / botADV2 8×5 → 16 수용 + 3회 Denied /
  **정상 봇 상호 수신 231pkt(마비 해소)**. `adv_resource` PASS — 별 격리에서 **정규 승격**
  (run-all 40종). 영향권 adv_isolation/adv_authz 무손상.
- 잔여 = **D4 만**(forward 오염 근인 trace — 가드로 재현 봉쇄됐으나 근인 미규명, 별건 결재).

## §4 ★신규 티켓 SRV-0712c — 1PC 3인 video 첫 키프레임 미도달 검은화면 (간헐, 근인 미규명)

> **정정 이력**: 최초 분석 "SRV-0712b dead-h promote 인과"는 **A/B 로 반증·철회**
> (부장님 검증 지시 20260712 밤). auto_layer="off"(promote 부재) 재기동에서도 2/3 재현 —
> promote/전환기계는 원인이 아니다. promote 발생·target 재발화·PLI 폭주 로그는 실측
> 사실이나 검은화면과의 인과 연결이 성급했음(공존 ≠ 인과).

- **증상(확정)**: 3층 ONEPC-CONF-01 간헐 red — U01 이 보는 U02 video **pkts>0 인데
  framesDecoded 0, 15s poll 초과**(가이드 §1 축③). 20260712 저녁부터 빈발(같은 날 아침
  19/19 clean ×2 와 대비 — 차이 원인 미상).
- **소거 확정**: ①auto layer 무관(off 재현) ②오늘 서버 코드 무관(gcc 는 off 에서 경로
  미사용 / S4 가드 무발화 로그) ③서버 진행형 오염 아님(idle 시 무해, 방 정리로 해소 —
  구독 단위 증상) ④서버는 PLI 를 실제 발사(`[DBG:PLI] sent → user=U02 ssrc=0xCE509614`
  — 실패 트랙 ssrc 일치, governor throttle 다수 동반).
- **미규명**: PLI 발사 후에도 키프레임이 수신자에 15s+ 미도달 — 절단이 (a) publisher
  Chrome 의 PLI 응답 부재(1PC RTCP 경로?) (b) 키프레임 forward 유실 (c) PLI 유실 중
  어디인지. 오늘 저녁부터 빈발해진 환경/타이밍 변화도 미상.
- **시험 확대 실측(부장님 지시, 20260712 밤 — 180eee5)**:
  1. 재현율 9/16(≈56%, 단독 연속 실행). **실패는 전량 U02(2번째 joiner) video** —
     U03 은 0회. 순번 고정 경합(U01 의 1PC 초기 협상 창과 U02 첫 publish 의 겹침 의심).
  2. **2층 동형(onepc_conf_video_n3, 3인 1pc audio+video) 5/5 clean** — 전달 축(②) 무결
     확정. 증상은 실브라우저 개입 축(③ 디코딩/키프레임) 한정.
  3. 2pc 동형(CONF-VIDEO-01) 3/3 clean — 1PC 고유 재확인.
  4. **서버 PLI 66회 발사에도 미해소**(governor throttle 496 별도, media_ssrc = U02 실
     pub ssrc 확인) — "PLI 1회 유실" 가설 약화, **publisher Chrome 이 PLI 를 미수신
     또는 미인식** 유력. 시험 위생(방 정리 확인 게이트)도 소거 완료(게이트 후 재현).
- **로그 축 소거(부장님 힌트 — PLI 는 이슈 아님, 로그부터)**: 실패 run(22:26, trace-on
  재현)의 ①클라 콘솔 = **error 0**(전 페이지, 무해 warn 뿐 — setRemote/track 에러 없음)
  ②서버 = **WARN/ERROR 0**, 통과 run 과 정규화 diff 도 유의미 축 없음(TWCC FB 개수 등
  잡음뿐). TRACKS_READY/CAMERA_READY/등록·통지 전부 정상 라인 — **시그널링·서버·클라
  SDK 모두 자기 관점 "정상"인 조용한 실패**. ※[DIAG:SUB_TRACKS] 의 `?(audio)/?(video)`
  2건은 유령 아님 — PTT slot(user 무소속 vssrc, 통과 run 에도 동일) 오판 주의.
- **★심층 계측 성과(진단 스펙 c4d6fe6 — 원 스펙 동일 활동 시퀀스로 재현 포획)**:
  실패 순간 U01 수신 inbound-rtp = `packetsReceived 61 / framesReceived 0 /
  framesDecoded 0 / keyFramesDecoded 0 / pliCount 0 / codecId None`.
  **framesReceived=0 + codecId=None = 축④ — 수신 transceiver 의 코덱 미결정으로
  디코더 배선 자체가 부재**(디코딩 실패·키프레임 문제 아님 — PLI 가 이슈 아니라던
  부장님 판단 적중). PT 세션 갈림 가설은 기각(전 run U01/U02 모두 pt=102 동일).
- **★SDP 캡처 판독(qa.sdpDump 신설 — 재현 포획 2번째)**: 실패 트랙(0xffffbb0c)의
  U01 구독 m-line(mid=35)은 **존재하고 rtpmap = 96 VP8 / 102 H264 (+rtx 97/103) 만**
  선언. 반면 U02 로컬 pub m-line(mid=2)의 H264 후보 PT 는 **98/100/102/107/109/35
  다수(프로파일별)**. 도착 pkts 61 + codecId None = **U02 실 송신 PT 가 96/102 밖**
  (H264 프로파일 PT 갈림)으로 U01 구독 m-line 과 미스매치 — 세션별 Chrome PT 선택이
  갈리는 것이 재현율 ~50%·U02(가장 이른 동적 구독) 고정과 정합.
- **근인 좌표(높은 확신 — 마지막 1% 는 실 송신 PT 실측)**: 1PC 구독 m-line 코덱이
  "구독자 자신의 pub answer PT(96/102) 에코"(sdk `buildUnifiedRemoteOffer`)로 고정 —
  publisher 의 실 송신 PT(프로파일 갈림)를 전제 못 함. **known-gap "1PC cross-browser
  PT"(20260708 발견 4)의 동종 Chrome 재림판** — H264 프로파일이 PT 를 가른다.
- **수리 방향(결재)**: ①근본 = 서버 PT rewrite(known-gap 에 이미 명시된 별 토픽 승격)
  ②클라 완화 = 1PC 구독 m-line 에 H264 전 프로파일 PT 동봉(mirror-offer 확장)
  ③운영 완화 = 1PC video 코덱을 VP8 고정(프로파일 갈림 원천 제거). 잔여 실측 1 =
  U02 outbound 실 PT(진단 스펙 pubStatsRaw 가 빈 배열 — LocalPipe.getStats 한계,
  서버 trace 로 대체). 진단 그물 = DIAG=1 스펙 + qa.sdpDump/trackStatsRaw(커밋됨).
- 임시 상태: poll 승격(8085872)은 seam 만 덮음 — 수리 전까지 ONEPC-CONF-01 간헐 red =
  known 상태. auto_layer 는 v2 원복 재기동 완료(A/B 종료).
