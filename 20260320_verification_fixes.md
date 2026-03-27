# SESSION_CONTEXT — 기능 검증 + 버그 수정 (2026-03-20)

> date: 2026-03-20
> author: kodeholic (powered by Claude)
> server: v0.6.2 → v0.6.3 (수정 사항 반영)

---

## 완료 사항

### Fix 1: PLI 유령 카운팅 수정 (ingress.rs)

**문제**: `pli_sent` 글로벌 카운터가 publisher 매칭 전에 증가 → publisher를 못 찾아 드롭된 PLI도 카운트 → 스냅샷에 44/3s 유령 PLI 표시.

**수정**:
- `relay_subscribe_rtcp_blocks()`에서 PSFB 사전 카운트 제거
- publisher 매칭 성공 + 전송 성공 시에만 `pli_sent` 증가 (pub_pli_received와 동일 시점)
- publisher not found + PLI 포함 시 warn 로그 출력 (`[RTCP:PLI] dropped`)

**파일**: `src/transport/udp/ingress.rs`

### Fix 2: 스냅샷 방 필터링 + 좀비 데이터 정리

**문제**: 어드민 스냅샷이 모든 방/퇴장 유저 데이터를 혼재 출력. Map이 절대 안 지워짐.

**수정 (snapshot.js)**:
- `selectedRoom` 기준 전 섹션 필터 (SDP/Encoder/Session/Publish/Subscribe/Network/Loss/Timeline/PTT/Pipeline/AggLog)
- 스냅샷 헤더에 `room: 방이름 (room_id) 인원/용량` 표시
- 방 미선택 시 기존 전체 출력 유지

**수정 (app.js)**:
- `snapshot` 메시지 수신 시 활성 유저/방 셋 구성
- 비활성 엔트리 삭제: latestTelemetry, sdpTelemetry, joinedAtMap, eventHistory, telemetryHistory, roomCreatedAtMap, pipelineRing, snapshotRing (8개 Map)

**파일**: `demo/admin/snapshot.js`, `demo/admin/app.js`

### Fix 3: Simulcast PLI 자가 치유 (ingress.rs + participant.rs)

**문제**: SUBSCRIBE_LAYER가 PUBLISH_TRACKS보다 먼저 도착 → subscribe_layers entry가 이미 존재 → fanout에서 `created=false` → `need_pli=false` → PLI 영원히 안 감 → video 영원히 안 뜸.

**수정 (participant.rs)**:
- `SimulcastRewriter`에 `pli_sent_at: Option<Instant>` 필드 추가
- `needs_pli_retry()`: initialized 전 + 2초 경과 시 true
- `mark_pli_sent()`: PLI 전송 시각 기록

**수정 (ingress.rs — fanout_simulcast_video)**:
- `need_pli = created || retry_pli` (rewrite 실패 + 쿨다운 경과 시)
- PLI 보낼 때 `mark_pli_sent()` 호출

**수정 (track_ops.rs — SUBSCRIBE_LAYER)**:
- PLI 보낼 때 `mark_pli_sent()` 호출 → ingress 중복 재시도 방지

**파일**: `src/room/participant.rs`, `src/transport/udp/ingress.rs`, `src/signaling/handler/track_ops.rs`

### Fix 4: 퇴장/재입장 시 subscribe_layers stale entry 정리

**문제**: 퇴장 시 다른 참가자의 `subscribe_layers`에 이전 세션의 entry가 잔존 → 재입장 시 old rewriter(initialized=true + 구 vSSRC) → PLI 안 보냄 + SSRC 불일치 → video fan-out 실패.

**수정 (helpers.rs)**:
- `purge_subscribe_layers(room, leaving_user)` 공통 함수 추가
- 퇴장 유저의 entry를 남은 모든 참가자의 subscribe_layers에서 제거 (멱등)

**수정 (room_ops.rs)**:
- ROOM_JOIN: 재입장 방어 (cleanup 실패/크래시 시 stale entry 대응)
- ROOM_LEAVE: 정상 퇴장 시 정리
- cleanup: WS 끊김 시 정리

**파일**: `src/signaling/handler/helpers.rs`, `src/signaling/handler/room_ops.rs`

### Fix 5: 3건 추가 수정

**(a) inactive mid 재활용 (media-session.js)**:
- TRACKS_UPDATE(add) 시 같은 kind의 inactive entry 재활용 → SDP m-line 무한 증식 방지

**(b) Pipeline 음수 delta 방지 (app.js)**:
- `since` 변경 감지 시 prev 초기화 + `Math.max(0, delta)` 클램프

**(c) audio NACK nack_no_rtx_ssrc 노이즈 억제 (ingress.rs)**:
- audio track인 경우 카운트/로그 스킵 (audio에 RTX 없는 건 정상)

**파일**: `core/media-session.js`, `demo/admin/app.js`, `src/transport/udp/ingress.rs`

### Fix 6: 개발 서버 IP 변경

- `192.168.0.29` → `192.168.0.25`, 라벨 "개발 서버 (ws)"
- 4개 파일: admin/index.html, client/index.html, admin/app.js, client/app.js

---

## 변경 파일 요약

### oxlens-sfu-server
| 파일 | 변경 |
|------|------|
| `src/transport/udp/ingress.rs` | PLI 카운팅 수정, PLI 자가 치유, audio NACK 노이즈 억제 |
| `src/room/participant.rs` | SimulcastRewriter pli_sent_at + needs_pli_retry + mark_pli_sent |
| `src/signaling/handler/track_ops.rs` | SUBSCRIBE_LAYER mark_pli_sent |
| `src/signaling/handler/helpers.rs` | purge_subscribe_layers 추가 |
| `src/signaling/handler/room_ops.rs` | ROOM_JOIN/LEAVE/cleanup purge 호출 |

### oxlens-home
| 파일 | 변경 |
|------|------|
| `demo/admin/snapshot.js` | 방 필터링 전 섹션 |
| `demo/admin/app.js` | 좀비 정리, Pipeline 음수 클램프, 개발 서버 IP |
| `demo/admin/index.html` | 개발 서버 IP |
| `demo/client/index.html` | 개발 서버 IP |
| `demo/client/app.js` | 개발 서버 IP |
| `core/media-session.js` | inactive mid 재활용 |

---

## 검증 결과

| 시나리오 | 결과 |
|----------|------|
| Conference 3인 (simulcast OFF, RPi) | ✅ loss 0, fps 23~25, jb_delay <100ms |
| PLI 유령 수정 확인 | ✅ pli_sent 44→0 |
| 좀비 데이터 정리 | ✅ 현재 방 참가자만 표시 |
| Simulcast 4인 (localhost) | ✅ 전원 SimulcastEncoderAdapter, h 1.6Mbps |
| Simulcast 재입장 video fan-out | ✅ purge + PLI 자가 치유 동작 |
| PTT 4인 기본 동작 | ✅ granted/released/revoked 정상 |

---

## 미해결 (다음 세션)

### PTT 방치 후 영상 복구 실패 (CRITICAL)

**증상**: PTT 방에서 1분 이상 방치 → 탭 hidden → Chrome video encoder suspend → floor_request 시 영상 안 뜸 + PLI 폭풍 재발 (45/3s).

**원인 분석**:
- Chrome 백그라운드 탭 throttling: video encoder가 suspend → bitrate=0, fps=0
- floor granted → PLI burst → 하지만 encoder 꺼져있어서 키프레임 생성 불가
- 전원 audio_concealment 3초마다 무한 반복

**필요 수정 (클라이언트)**:
- floor_request 직전에 video encoder 명시적 wake-up (track.enabled toggle 또는 replaceTrack)
- 또는 CAMERA_READY(op=18)를 PTT floor_granted 후에도 트리거
- hidden→visible 전환 시 encoder 상태 확인 + 필요 시 재시작

**필요 수정 (서버)**:
- PLI 응답 타임아웃: 일정 시간(5초?) 내 키프레임 미도착 시 VIDEO_SUSPENDED 이벤트 발송
- 클라이언트가 avatar 전환으로 UX 커버

**관련 파일**:
- `core/client.js` — floor FSM, _applyPttMediaState
- `core/media-session.js` — track enabled 제어
- `src/signaling/handler/floor_ops.rs` — floor granted PLI
- `src/transport/udp/pli.rs` — PLI burst 타임아웃 감지

### 추가 개선 사항 (비긴급)

- **Contract 체크 강화**: subPc state != connected 시 FAIL 추가
- **Loss cross-reference simulcast 대응**: active layer의 pub_delta 매칭 (현재 l 레이어 delta가 잡힘)
- **시그널링 재연결 (상용 필수)**: WS 끊김 시 미디어 세션 유지 + grace period + session resume
- **서버 PLI per-room 분리**: 글로벌 카운터 → room별 분리 (진단 정확도)

---

## 서버 버전

v0.6.2 → 수정 사항 반영 후 실질적으로 v0.6.3 수준.
CHANGELOG.md 업데이트 필요.

---

*author: kodeholic (powered by Claude)*
