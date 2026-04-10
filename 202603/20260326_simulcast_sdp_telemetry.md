# 세션 컨텍스트: 2026-03-26 Simulcast 안정화 + 텔레메트리 강화

## 현재 상태: SDP 에러 근본 수정 완료 — 테스트 필요

### 근본 원인 (mediasoup-client 소스 역분석으로 확정)
`Failed to process the bundled m= section with mid='4'`

- inactive m-line을 port=0으로 처리 + BUNDLE에서 제외 → BUNDLE 태그(첫 번째 mid) 이동 → Chrome transport 불일치
- mediasoup-client의 3단계 m-line 상태: active(port=7) / disabled(port=7,inactive,BUNDLE유지) / closed(port=0,BUNDLE제외)
- 우리는 disabled를 close 수준으로 처리하고 있었음 (port=0, ICE/DTLS 제거, BUNDLE 제외)
- mid 재활용 금지 후 inactive 누적 → 첫 mid가 inactive → BUNDLE 태그 이동 → 에러
- simulcast 자체 문제가 아님 — mid 재활용 금지가 동시에 들어가서 발현된 것

### 수정 내용 (sdp-builder.js)
1. buildMediaSection inactive 분기: port=0→7, c=0.0.0.0→127.0.0.1, ICE/DTLS/코덱/extmap 유지, SSRC만 제거
2. buildSubscribeRemoteSdp BUNDLE 필터: active만 → 모든 mid 포함 (closed 개념 없으므로)

---

## 이번 세션 해결 완료

1. **Subscribe PC 큐 직렬화** ✅ — setup()에서 _queueSubscribePc() 경유
2. **mid 재활용 금지** ✅ — 항상 새 mid 할당
3. **본인 타일 IO 추적 제외** ✅ — _visibleThumbs 오염 방지
4. **IO observer 누수 수정** ✅ — room:left에서 정리
5. **_doRedistribute 안전망** ✅ — noVisibleInfo fallback
6. **텔레메트리 강화** ✅ — pushCritical API + video_recv_stall 감지
7. **inactive m-line 최소화** ✅ — ICE/DTLS 속성 제거 (이전 BUNDLE 충돌 해결했으나 새 에러 미해결)

## 서버 SR Translation — 빌드 완료, 동작 확인

- `participant.rs`: SimulcastRewriter.ts_offset → pub(crate)
- `ingress.rs`: SR Translation — 구독 레이어 SR만 릴레이 + ts_offset 적용
- sr_relay=53 확인, jb_delay 정상 범위 (대부분 8~37ms)

## 변경 파일

| 파일 | 변경 |
|---|---|
| `demo/client/app.js` | IO observer 정리, noVisibleInfo 안전망, 본인 타일 IO 제외 |
| `core/media-session.js` | 큐 직렬화, mid 재활용 금지, SDP 에러 critical 보고+덤프 |
| `core/sdp-builder.js` | mediasoup disabled 패턴 (port=7, ICE/DTLS/코덱 유지, BUNDLE 잔류) |
| `core/telemetry.js` | pushCritical API, video_recv_stall 감지 |
| `demo/admin/render-detail.js` | critical_error/video_recv_stall/decoder_stall 표시 |
| `src/room/participant.rs` | ts_offset pub(crate) ✅ |
| `src/transport/udp/ingress.rs` | SR 레이어 필터+ts_offset ✅ |
| `src/transport/udp/mod.rs` | PTT subscribe STUN latch → FLOOR_TAKEN unicast (**빌드 필요**) |

## 기각된 접근법 (이번 세션)

- inactive m-line port=0 + BUNDLE 제외 → BUNDLE 태그 이동 → "Failed to process bundled m= section" (**근본 원인**)
- inactive m-line port=0 + ICE/DTLS 제거 + BUNDLE 제외 → 동일 원인 (이전 세션 시도)
- inactive m-line port=0 + ICE/DTLS 포함 + BUNDLE 포함 → Chrome "should be rejected" (port=0이 RFC 8843 reject)
- inactive mid 재활용 → SSRC demux 실패 + BUNDLE 재추가 reject
- **정답**: mediasoup 패턴 — port=7 + inactive + ICE/DTLS/코덱 유지 + BUNDLE 잔류 (disabled ≠ closed)
- setup()에서 subscribe PC 직접 호출 → TRACKS_UPDATE 레이스
- Simulcast SR rtp_ts 원본 유지 → NTP↔RTP 매핑 파괴 → jb_delay 폭등
- 양쪽 레이어 SR을 같은 virtual_ssrc로 릴레이 → NTP↔RTP 혼입
- 본인 타일을 IO에 등록 → noVisibleInfo 안전망 오동작 → thumb pause
- inactive m-line에 ICE/DTLS 포함 → Chrome이 같은 transport로 인식 → BUNDLE 충돌
