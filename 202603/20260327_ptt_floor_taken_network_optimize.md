# 세션 컨텍스트: PTT FLOOR_TAKEN unicast + 네트워크 비용 최적화
**날짜**: 2026-03-27
**범위**: oxlens-sfu-server (mod.rs) + oxlens-home (client.js, power-fsm.js, sdp-builder.js)

---

## 완료 항목

### 1. PTT 정적 import (경쟁조건 제거)

**문제**: `await import("./ptt/ptt-controller.js")` 동적 import 중 서버 FLOOR_TAKEN unicast 도착 → `this.ptt === null` → 이벤트 drop

**수정**: `client.js` 상단에 `import { PttController } from "./ptt/ptt-controller.js"` 정적 import. join 핸들러에서 `await import()` + try/catch → 동기 `new PttController(this)` + `attach(d)`.

Conference-only 모드에서도 모듈 로딩되지만 `if (mode === "ptt")` 분기에서 인스턴스 미생성 → 부담 없음.

### 2. FLOOR_TAKEN unicast — sub SRTP ready 시점 삽입

**문제**: 발화 중 신규 참여자 입장 시 FLOOR_TAKEN을 못 받음. 기존 코드는 USE-CANDIDATE 분기에 있었으나 dead code (ICE-Lite 서버에서 해당 분기 미실행).

**서버 로그 대조로 확인**: 20:06:22 U528 발화 중 → 20:06:25 U848 입장 → `[PTT] subscribe STUN latch → FLOOR_TAKEN unicast` 로그 없음 → U848은 FLOOR_TAKEN 못 받고 IDLE 상태로 운용 → 20:06:52에야 FLOOR_IDLE로 U528 발화 사실 인지.

**수정**: `mod.rs` — sub DTLS SRTP ready 직후 (EGRESS spawned + PLI 요청 바로 다음)에 FLOOR_TAKEN unicast 삽입.

```
sub DTLS handshake OK
  → SRTP keys installed
  → SRTP ready
  → egress task spawned
  → send_pli_to_publishers()
  → ★ FLOOR_TAKEN unicast (여기)
```

이 시점이면 subscribe PC 미디어 수신 가능 + 클라이언트 FloorFsm attach 완료. 경쟁조건 없음.

**빌드 에러 수정**: `crate::room::room::RoomMode::Ptt` → `config::RoomMode::Ptt` (RoomMode는 config.rs에 정의, room.rs에서 re-export 안 됨)

**테스트 결과**: "딱 그 자리였다. 비틈없이 화면 바로 나온다" — 발화 중 입장 즉시 음성+영상 수신 확인.

### 3. Publisher 네트워크 비용 최적화 — HOT-STANDBY replaceTrack(null)

**문제**: `track.enabled = false`로 해도 브라우저가 Opus silence RTP를 계속 송출. 비발화 구간 업링크 데이터 비용 발생.

**수정 (power-fsm.js)**:

| 구분 | 기존 | 변경 |
|------|------|------|
| HOT-STANDBY 진입 | `track.enabled = false` | `replaceTrack(null)` + track 변수 보관 |
| HOT 복귀 | `enabled = true` | `replaceTrack(savedTrack)` |
| savedTrack dead 시 | — | `readyState !== 'live'` → getUserMedia fallback |
| COLD 진입 | 기존 | savedTrack stop 후 정리 |
| detach | 기존 | savedTrack stop (leak 방지) |

기각된 WARM 방식과의 차이: WARM은 `track.stop()`으로 영구 파괴 → getUserMedia 필요 → hang 위험. 이번 방식은 track live 상태 유지 → hang 없음.

**텔레메트리 검증**:
- `pkts_delta=0, bitrate=0kbps` — RTP 송출 완전 제로
- `audio=replaceTrack(14ms) video=replaceTrack(1ms) total=16ms` — getUserMedia 없이 즉시 복원
- `hasTrack=false, readyState=(no track)` — sender에 track 없음 확인

### 4. Subscriber NACK 제거 — PTT audio SDP

**문제**: floor idle 시 서버 RTP gate → 브라우저 seq gap 판단 → NACK 반복 발사. PTT virtual SSRC에 RTX SSRC 없어 복구 불가 (`nack_no_rtx_ssrc`로 폐기). 양쪽 네트워크 비용만 소모.

**수정 (sdp-builder.js)**: `buildPttSubscribeSdp()`에서 audio codec의 `rtcp_fb`에서 `'nack'` 필터링. Conference 모드는 기존 그대로.

**텔레메트리 검증**:
- `nack_sent=0, nack_delta=0` — NACK 완전 제로
- `[trend:sub_nack] 0,0,0,0,0,0,0,0,0,0` — 전 구간 제로
- `nack_recv=0, nack_remap=0` — 서버측도 NACK 수신 없음

---

## 미디어 라이프사이클 정리 (PTT 방, 서버 관점)

| # | Phase | 시점 | hook 가능 시점 |
|---|-------|------|--------------|
| 1 | 시그널링 입장 | ROOM_JOIN(WS) → server_config 응답 | 초기 상태 전달 |
| 2 | Publish PC 수립 | STUN latch(pub) → DTLS → SRTP ready | pub 준비 완료 |
| 3 | RTP Stream Discovery | 첫 RTP → stream_map → TRACKS_UPDATE broadcast | track 등록 (녹음 등) |
| 4 | Subscribe PC 수립 | STUN latch(sub) → DTLS → SRTP ready → EGRESS spawned → PLI | **★ FLOOR_TAKEN unicast** |
| 5 | Floor 전이 | FLOOR_REQUEST/RELEASE → switch/clear speaker | 화자 전환 부수 작업 |
| 6 | 다른 참여자 입퇴장 | TRACKS_UPDATE add/remove, subscribe re-nego | 발화 중 입장 → FLOOR_TAKEN |
| 7 | 퇴장 | ROOM_LEAVE → floor release → tracks cleanup → egress shutdown | 정리 작업 |

---

## 변경 파일

### oxlens-sfu-server

| 파일 | 변경 |
|------|------|
| `src/transport/udp/mod.rs` | USE-CANDIDATE dead code 제거 → sub SRTP ready에 FLOOR_TAKEN unicast 삽입, `config::RoomMode::Ptt` 경로 수정 |

### oxlens-home

| 파일 | 변경 |
|------|------|
| `core/client.js` | PTT 동적 import → 정적 import, `await import()` 제거 |
| `core/ptt/power-fsm.js` | HOT-STANDBY: `enabled=false` → `replaceTrack(null)` + track 보관, 복원 시 `replaceTrack(savedTrack)`, COLD/detach에서 savedTrack 정리 |
| `core/sdp-builder.js` | `buildPttSubscribeSdp()` audio codec에서 `nack` rtcp-fb 필터링 |

---

## 기각된 접근법

- **USE-CANDIDATE 분기에서 FLOOR_TAKEN unicast** — ICE-Lite 서버에서 USE-CANDIDATE + `!dtls_map.has` 분기가 실행되지 않음 (dead code). 서버 로그에서 확인.
- **ROOM_JOIN 응답에 floor 필드 활용 (클라이언트 방식)** — "서버에서 입장을 인지했을 때 taken을 던져주는 게 일반적인 원칙" (부장님 판단). 서버에서 적절한 타이밍에 보내는 것이 정석.
- **WARM 방식 (track.stop())** — track 영구 파괴 → getUserMedia 필요 → hang 위험. replaceTrack(null) + track 보관이 정답.
- **enabled=false (기존 HOT-STANDBY)** — Opus silence RTP 계속 송출. 네트워크 비용 절감 효과 없음.

---

## 확정된 원칙

- **FLOOR_TAKEN unicast 시점**: sub DTLS SRTP ready (EGRESS spawned + PLI 직후). 이 시점이 subscribe PC 미디어 수신 가능 + 클라이언트 FloorFsm attach 완료.
- **PTT 모듈 로딩**: 정적 import 필수 (동적 import 경쟁조건). Conference-only에서 로딩 부담 무시 가능.
- **HOT-STANDBY = replaceTrack(null)**: track 보관(live) + sender null → RTP 송출 완전 중단. 복원은 replaceTrack(savedTrack) 수ms.
- **PTT subscribe audio NACK 비활성**: SDP에서 `a=rtcp-fb:111 nack` 제거. RTX SSRC 없으므로 복구 불가 → 불필요 트래픽 차단.

---

## 장기 과제 (미구현)

### RTCP Terminator v2 — 세션별 독립 복구
| 구간 | 역할 | 구현 |
|------|------|------|
| ingress (Publisher→SFU) | 서버가 수신자 | seq gap 감지 → 서버가 publisher에 NACK → RTX 수신 |
| egress (SFU→Subscriber) | 서버가 송신자 | RTX cache 보유 → subscriber NACK에 서버가 직접 응답 |

이 구조가 들어가면 subscriber NACK 다시 활성화 가능 + publisher↔subscriber 간 역매핑 불필요 + Conference에도 적용.

---

## 다음 세션 TODO

### P0: SKILL_OXLENS.md 업데이트
- FLOOR_TAKEN unicast 시점 원칙 추가
- PTT 정적 import 원칙 추가
- 네트워크 비용 최적화 (replaceTrack(null), NACK 제거) 추가
- 미디어 라이프사이클 hook 시점 표 추가
- 기각 사항 반영

### P1: CHANGELOG.md 업데이트
- v0.6.8 ~ 현재: FLOOR_TAKEN unicast, 정적 import, replaceTrack(null), NACK 제거

### P2: 안드로이드 SDK 동일 최적화 적용
- replaceTrack(null) 상당: libwebrtc sender.setTrack(null, false)
- NACK 제거: SDP 조립 시 audio rtcp-fb nack 제외

### P3: 재입장 시 _visibleThumbs 비어서 pause 문제 (3/26 미해결)

---

*author: kodeholic (powered by Claude)*
