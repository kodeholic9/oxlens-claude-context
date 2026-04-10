# SESSION_CONTEXT — Simulcast 세션 2 완료

> date: 2026-03-20
> author: kodeholic (powered by Claude)

## 완료 내용: Phase 1 클라이언트측 (client-offer 전환)

### 변경 파일 3개
| # | 파일 | 변경 |
|---|------|------|
| 1 | `core/media-session.js` | 전체 재작성: addTrack→addTransceiver(sendonly), server-offer→client-offer, getStats SSRC 폴링 |
| 2 | `core/sdp-builder.js` | buildPublishRemoteAnswer() 신규: Chrome offer extmap ID 파싱→answer 조립, simulcast rid/simulcast 라인 |
| 3 | `core/client.js` | _simulcastEnabled 플래그: constructor, _onJoinOk, _resetMute |

### 핵심 설계 결정
- **모든 경우 client-offer**: simulcast ON/OFF 관계없이 동일 flow (addTransceiver + createOffer + buildPublishRemoteAnswer)
- **sendEncodings 차이만**: simulcast ON → `[{rid:'h', maxBitrate:1650000}, {rid:'l', maxBitrate:250000, scaleResolutionDownBy:4}]`, OFF → 없음
- **getStats 폴링**: 200ms × 최대 15회(3초). simulcast ON이면 video 2개(h,l) + audio 1개, OFF이면 video 1개 + audio 1개
- **ICE connected 재시도**: `_pendingPublishTracks` 플래그 → 폴링 실패 시 connected에서 재전송
- **extmap ID 매칭**: Chrome offer의 URI→ID 파싱 → server 지원 URI만 필터링 → answer에 Chrome의 ID로 포함
- **DTLS setup:passive**: answer에서 하드코딩 (서버 ICE-Lite = DTLS server)
- **DTX munging**: offer SDP에 적용 (client-offer이므로 offer가 local)
- **twcc_extmap_id**: Chrome offer에서 추출하여 PUBLISH_TRACKS에 포함

### 테스트 결과
- ✅ 회의실-2 (simulcast OFF) 2인 양방향 정상 — rid 없음, SSRC 2개, client-offer 동작
- ✅ 무전 대화방 (PTT) 정상
- ✅ 대회의실 (simulcast ON) 2인 양방향 정상 — rid:"h"/rid:"l" SSRC 각각 추출, twcc_extmap_id=3

### 서버 버전
- v0.5.5 (Phase 0 + Phase 1 서버측 — 세션 1에서 완료)

### buildPublishRemoteSdp (기존 함수) 상태
- 삭제하지 않음. import만 media-session.js에서 제거. 향후 정리 가능.

---

## 다음 세션: 세션 3 — Phase 3 (가상 SSRC + SimulcastRewriter + 레이어 전환)

### 작업 범위 (서버 + 클라이언트)

**서버측:**
1. participant.rs: simulcast_video_ssrc (AtomicU32 CAS lazy 할당), SimulcastRewriter 구조체
2. room.rs: find_publisher_by_vssrc()
3. handler.rs: TRACKS_UPDATE/ROOM_JOIN/ROOM_SYNC/ROOM_LEAVE에서 가상 SSRC 교체 (체크리스트 10항목)
4. handler.rs: SUBSCRIBE_LAYER (op=51) 핸들러
5. ingress.rs: SimulcastRewriter rewrite (SSRC/seq/ts), PLI/NACK 역매핑
6. PLI 교착 방지: SubscribeLayer 즉석 생성 시 즉시 PLI burst + SUBSCRIBE_LAYER old==new && !initialized → PLI

**클라이언트측:**
1. signaling.js: subscribeLayer(targets) → OP.SUBSCRIBE_LAYER 전송
2. app.js: redistributeTiles() — main→h, thumbs→l
3. app.js: long-press popup — 수동 h/l/pause 선택 + _manualLayerOverride 보호

### 주요 주의사항
- SIMULCAST_REBUILD_GUIDE_20260320.md의 체크리스트 10항목 한번에 수정
- PLI 교착 2중 대책 필수
- SimulcastRewriter: initialized=false + P-frame → 드롭, 키프레임부터만 통과
- `Arc<Room>` move 클로저 금지 → bool Copy 타입 캡처
- 빌드 전 pub 접근성 확인 (SimulcastRewriter.initialized)
