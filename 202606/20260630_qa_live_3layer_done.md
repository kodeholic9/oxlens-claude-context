<!-- author: kodeholic (powered by Claude) -->

# 20260630 — 3층 라이브 회귀(qa/live) 신설: 멀티피어 실브라우저 × 트랙단위 3권위 교차

> **한 줄**: 2층 oxe2epy(헤드리스 봇) 위에 **3층(브라우저 실영상 회귀)**를 `oxlens-home/qa/live`(Playwright)로 세웠다. 멀티피어 실브라우저 × **트랙단위 신원** × 3권위 교차(클라 인지/getStats Δ/oxadmin) × 결정적 회귀 — 클라 SDK 업계(mediasoup-client/jitsi/livekit) 미답 영역. 화상회의·simulcast·republish·duplex PASS(3회 결정적), 다방청취 home 수신 PASS. **SDK 결함 2종 발견(GAP).**
>
> **데이터**: `oxlens-home/qa/live/` (playwright). **선행**: [[20260629b_oxe2e_scope_select_done]], [[project_3layer_live_playwright]], [[project_multiroom_ptt_only]]. 커밋 `756f90f`(브랜치 `qa-live-3layer`).

---

## 0. 층의 경계 (부장님 정정: "2·3층은 구분되어야")
- **시나리오가 아니라 검증 축으로 구분.** 2층=와이어(패킷/seq/신원/라우팅/안전성·생명성, canned RTP). 3층=실 미디어(디코딩/jb/conceal/freeze/픽셀/레이어 체감, 실 인코더).
- 경계 한 줄: **와이어로 결판나면 2층에서 끝. 실 디코딩·품질·픽셀이 판정을 바꿔야만 3층.** 같은 시나리오라도 단언이 다르니 중복 아님. "2층 항목을 다 녹인다"는 부적격 — adv_*(악조건 와이어)는 봇 전용, 3층은 그 위 "실제 디코딩되어 보이/들리는가"만.
- 남들 조사(Explore): 클라 SDK 누구도 멀티피어 실브라우저 E2E·미디어 검증 안 함(전부 모의 단위 or 부하). 우리 3층은 베낄 선례 없어 우리가 정의.

## 1. 인프라 — qa/live (Playwright)
- **정적 서버**: Playwright `webServer`가 `http-server`(5599) 자체기동. ★VS Code Live Server 금지 — node_modules/test-results 파일변경 감지로 무한 라이브리로드 → "execution context destroyed by navigation"(반나절 오진의 정체). `workers=1` 직렬(SDP race·서버 상태 공유).
- **제어** = `window.qa`(page.evaluate). 단일 page=단일 user, 멀티=page N개(controller/iframe 폐기 구조 그대로). createRoom 멱등(default rooms 폐기 — 첫 참가자 생성).
- **관측 = 트랙단위 3권위 교차**(신원=트랙, 사람 아님 — 부장님 정정): ① `qa.tracks()` STREAM_SUBSCRIBED raw(클라 인지) ② `qa.trackStats()` receiver.getStats Δ(실수신·품질, 2초+ 간격=collectStats 캐시 회피) ③ `oxadmin room`(서버 사실, 권위). `qa.remotes()` user-key 거울은 육안 UI용만(같은 user의 audio/video 뭉갬 — 시험 단언 금지).

## 2. 시나리오 결과 (5 spec, run-all GREEN)
- **CONF-VIDEO-01**: 3인 full-duplex, 상호 fan-out(non-slot 트랙 4개 = 상대2×av) 트랙단위 검증 + getStats Δ + oxadmin passthrough. 3회 결정적.
- **SIMULCAST-01**: camera simulcast → 서버 h/l 2레이어(rid h/l, simulcast:true) publish 확정 ✓. ★봇 불가(canned).
- **REPUBLISH-01**: camera unpublish→republish 후 재구독·재디코딩(Δ>0=검은화면 아님). track_id 신규 발급=정상(완전 재발행).
- **DUPLEX-01**: full→half→full. half=floor 없는 PTT라 수신 정지(oxadmin active=false + 클라 트랙 제거), full 복귀 흐름 재개. forward 토글 검증.
- **MULTIROOM-01**: U03 home RA + listen RB. home(RA) slot 수신 ✓(Δ=126). 청취방(RB)은 GAP(아래).

## 3. ★ qa.js 발견·수정 (관측 표면만 신설, 제어 facade·remotes 거울 보존)
- **publish simulcast 미전달 버그**: `engine.source.camera()`만 호출하고 `item.simulcast`를 안 채워 항상 단일레이어. → `if(simulcast) item.simulcast=true`(engine.publish가 `it.simulcast`→sendEncodings h/l).
- 트랙단위 관측: `tracks()`/`trackStats()`/`recvTracks`(trackId 키)/`pickInbound`(frame 크기 포함). remotes user-key 거울과 별개.
- multiroom 제어: `roomPolicy`(URL ?policy=multi) + `affiliate`(청취 추가=engine.joinRoom 직접)/`select`(발언방 전환) + `recvTracks.roomId`(트랙 방 식별).

## 4. ★ 발견 GAP 2종 (서버·인프라 무결, 3층이 잡음)
- **GAP-simulcast-layerswitch**: setQuality('l') 다운스위치 수신 검증 미확립. oxadmin이 vssrc rewrite(VideoSim)라 레이어 선택이 안 드러나고 수신 frameWidth 무변. 전환 미동작 vs 관측한계 미판별 → **trace(§4-T egress) 또는 SUBSCRIBE_LAYER wire 송신 확인** 필요. publish 2레이어는 단언 확정.
- **GAP-multiroom-xsfu-slot-recv**: RA/RB가 RR 라우팅으로 **cross-sfu**(RA@19741 / RB@19740)일 때, 청취방(affiliate) slot 미디어가 클라에 안 올라옴.
  - SDK 배선 OK(런타임 DBG: rooms 2 / virtual._slots 2[RB 포함] / transports 2), 서버 OK(oxadmin RB out>0 forward).
  - BUT RB slot STREAM_SUBSCRIBED 안 옴 + inbound null → 클라 RB 수신 0.
  - **의심**: `engine.onMediaTrack → rooms.get(d.roomId).onSlotMedia` 체인이 cross-sfu RB transport 에서 끊김(slot pipe·transport는 있는데 미디어 adopt 누락).
  - 2층 봇은 SFU별 sub transport 직접 물어 양방 수신(97+97)하지만, 실 SDK는 cross-sfu 청취방 slot을 못 올림 → **SDK 결함으로 규정.** 다음: transport ontrack→engine.onMediaTrack→onSlotMedia 체인 런타임 추적.

---

## 백로그
- **GAP-multiroom-xsfu-slot-recv 추적**(부장님 "SDK면 잡아야지"): engine.onMediaTrack cross-sfu slot 라우팅. 정정 시 MULTIROOM-01 ④ 단언 승격(`expect(d).toBeGreaterThan(0)`).
- **GAP-simulcast-layerswitch**: trace로 다운스위치 실증 후 단언 확정.
- 2층→3층 추가 이행 후보: audio conceal/jb(순수), floor 손바뀜 첫음절. (adv_* 악조건은 2층 전속.)
- qa.js는 부장님 코드 — 커밋 `756f90f`(brانch). README/catalog의 구 `__qa__` 표면은 stale(실제 얇은 `window.qa`) — qa 가이드 갱신에 반영.
