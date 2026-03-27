# 세션 컨텍스트: MID Extension 추가 + Simulcast 마지막 참여자 영상 미출력 버그

> 날짜: 2026-03-24 (저녁~밤)
> 서버 버전: v0.6.8 → v0.7.0 (MID 추가 후)
> 이전 세션: `20260324_simulcast_rtp_first_redesign.md`

---

## 성과 요약

### MID Extension 추가 (Phase D 준비)
- RFC 8843 BUNDLE demux 표준 메커니즘으로 non-simulcast video/audio 식별
- 업계 조사: Janus/pion/mediasoup 모두 SDP 기반 SSRC 사전 매칭 사용. OxLens는 2PC+SDP-Free라 MID header extension이 유일한 표준 경로
- `rtp_extension.rs`: `parse_mid()` 추가
- `stream_map.rs`: MediaIntent에 `mid_extmap_id`, `audio_mid`, `video_mid` 추가
- `message.rs`: PublishTracksRequest에 동일 필드 추가
- `track_ops.rs`: intent 생성 시 MID 필드 설정
- `ingress.rs`: resolve_stream_kind 5차 MID 판별 추가
- `media-session.js`: `_sendPublishIntent` + `_sendPublishTracks`에 MID 전송, `_parseMids()` 헬퍼 추가
- `config.rs`: `MID_EXTMAP_ID = 1` 상수 추가

### resolve_stream_kind 최종 판별 순서
```
1차: Opus PT=111 → Audio              (전 브라우저 고정)
2차: rid extension → Video             (simulcast, RFC 8853)
3차: repaired-rid extension → RTX      (simulcast RTX)
4차: is_rtx_pt + has_video → RTX       (non-sim, video 등록 후 PT fallback)
5차: MID extension → audio_mid/video_mid 매칭  (non-sim, RFC 8843)
나머지: Unknown → PUBLISH_TRACKS가 교정 (과도기 fallback)
```

### 모드별 경로 (교차 없음)
- **Simulcast**: Audio→1차, Video→2차(rid), RTX→3차(repaired-rid)
- **Non-sim Conference**: Audio→1차(Opus), Video→5차(MID), RTX→4차(PT+has_video)
- **PTT**: Audio→1차(Opus), Video→5차(MID), RTX→4차(PT+has_video)

---

## 버그 발견: Simulcast 마지막 참여자 영상 미출력

### 증상
- 3~4인 simulcast conference에서 **항상 마지막 입장 참여자의 영상만** 다른 전원에게 안 나옴
- `recv_delta=568` (패킷 전달됨) + `decoded_delta=0` (디코딩 0) + `jb_delay=?`
- 5번 중 4번 재현 (높은 재현율)
- H264, VP8 모두 동일 증상
- D 입장 시 → C 영상 복구 + D 영상 안 나옴 (항상 마지막만)

### 근본 원인: 키프레임이 subscriber SDP re-nego 완료 전에 소비됨

**타이밍 레이스:**
1. C 입장 → ROOM_JOIN
2. 기존 참여자(A,B)가 `participant_joined` 이벤트 수신 → `redistributeTiles()` → SUBSCRIBE_LAYER 전송
3. C의 DTLS 완료 → 첫 RTP 도착 → `resolve_stream_kind` → PUBLISH_TRACKS → TRACKS_UPDATE broadcast
4. TRACKS_UPDATE → 기존 참여자(A,B) subscribe SDP re-nego 시작
5. **그 사이에** `fanout_simulcast_video`가 rewriter 초기화 + 키프레임 전달
6. 키프레임이 Chrome에 도착했을 때 해당 vssrc의 m-line이 아직 SDP에 없음 → Chrome 무시
7. 이후 P-frame만 → `decoded_delta=0` 영원히

**D 입장이 C를 복구하는 이유:**
- D `participant_joined` → `redistributeTiles()` → 모든 타일(A,B,C,D)에 대해 SUBSCRIBE_LAYER 재전송
- C는 이미 tracks 등록 완료 → PLI 성공 → 이 시점에 subscriber SDP 준비 완료 → 키프레임 정상 디코딩
- D는 아직 tracks 미등록 → Ghost PLI → D 영상 안 나옴

### 진단 로그 확인 결과

**Ghost PLI 확인 (SUBSCRIBE_LAYER에서):**
```
[DIAG:SUB_PLI] PLI FAILED (no ssrc/addr) subscriber=U113 publisher=U339 rid=h video_ssrc=None pub_addr=None tracks=0
```
→ 마지막 참여자에게 PLI를 보내려 하지만 아직 DTLS도 안 됐고 tracks도 없어서 실패

**SSRC 매핑 자체는 정상:**
```
[DIAG:TRACK_MAP] user=U339 new_video_ssrc=0x0FE56A8C rid=h vssrc=0x61AE010F stream_map=[audio:0xDAB5956D, video:0x0FE56A8C(h), rtx:0xB915DCE1(l)]
```
→ audio/video/rtx 구분 정상, vssrc 할당 정상 (부장님 의심은 아니었음)

**PLI retry (자가 치유) 미발동:**
- `[DIAG:PLI_RETRY]` 로그 전혀 없음 → 2초 후 retry가 동작하지 않았음
- 하지만 이건 부차적 문제. retry가 발동돼도 근본 원인(subscriber SDP 미준비)은 해결 안 됨

### 수정 방향

**정석: TRACKS_UPDATE broadcast 후 subscriber SDP re-nego 완료 시점에 PLI 전송**

방안 A: TRACKS_ACK 수신 시 해당 publisher에 PLI 전송 (subscriber가 준비됐다는 확인)
방안 B: TRACKS_UPDATE broadcast 후 일정 딜레이(~200ms) 후 PLI burst
방안 C: subscriber가 re-nego 완료 후 자발적으로 PLI 요청 (클라이언트 주도)

방안 A가 가장 정석 — TRACKS_ACK는 이미 구현되어 있고, subscriber SDP 완료를 보장하는 시점.

---

## 진단 로그 (제거 필요 — 버그 수정 후)

| 태그 | 파일 | 용도 |
|------|------|------|
| `[DIAG:TRACK_MAP]` | ingress.rs | resolve_stream_kind vid 발견 시 stream_map 덤프 |
| `[DIAG:SUB_TRACKS]` | helpers.rs | collect_subscribe_tracks 출구 SSRC 덤프 |
| `[DIAG:SUB_PLI]` | track_ops.rs | SUBSCRIBE_LAYER PLI 성공/실패 |
| `[DIAG:VSSRC]` | ingress.rs | fanout vssrc 불일치 검출 |
| `[DIAG:REWRITE]` | ingress.rs | rewriter 미초기화 상태 추적 |
| `[DIAG:PLI_RETRY]` | ingress.rs | PLI retry 발동 여부 |

---

## 변경 파일

### 서버 (oxlens-sfu-server)
| 파일 | 변경 |
|------|------|
| `src/config.rs` | `MID_EXTMAP_ID = 1` 상수 추가 |
| `src/transport/udp/rtp_extension.rs` | `parse_mid()` 함수 + 테스트 추가 |
| `src/room/stream_map.rs` | MediaIntent에 `mid_extmap_id`, `audio_mid`, `video_mid` + 테스트 반영 |
| `src/signaling/message.rs` | PublishTracksRequest에 MID 필드 추가 |
| `src/signaling/handler/track_ops.rs` | intent MID 설정 + SUBSCRIBE_LAYER 진단 로그 |
| `src/signaling/handler/helpers.rs` | collect_subscribe_tracks 진단 로그 + `use tracing::info` |
| `src/transport/udp/ingress.rs` | resolve_stream_kind 5차 MID + 진단 로그 4개 |

### 클라이언트 (oxlens-home)
| 파일 | 변경 |
|------|------|
| `core/media-session.js` | `_sendPublishIntent` + `_sendPublishTracks`에 MID 전송, `_parseMids()` 헬퍼 |

---

## 기각된 접근법 (이번 세션)

1. **resolve_stream_kind 4차에 intent.has_video + !map.has_video() heuristic** → MID가 표준이므로 불필요
2. **Ghost PLI가 근본 원인** → 아님. 키프레임이 subscriber SDP 준비 전에 소비되는 타이밍 레이스
3. **SSRC → vssrc 매핑 오류** → 진단 로그로 확인: 매핑 자체는 정상
4. **키프레임 감지(is_h264_keyframe) 실패** → recv_delta=568인데 decoded_delta=0이므로, 패킷은 전달됨. 감지 문제가 아님

## 다음 세션 작업

1. **Simulcast 마지막 참여자 버그 수정** — TRACKS_ACK 수신 시 PLI 전송 (방안 A)
2. **진단 로그 제거** — 버그 수정 확인 후
3. **Phase D 계속** — getStats 폴링 삭제, TRACKS_UPDATE를 RTP 도착 시점으로 이동
4. **SKILL_OXLENS.md 업데이트** — rtp_extension.rs, stream_map.rs, MID extension 반영

---

*author: kodeholic (powered by Claude)*
