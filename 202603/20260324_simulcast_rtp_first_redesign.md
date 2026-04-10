# 세션 컨텍스트: RTP-First Stream Discovery — Phase A~C + PTT 수정

> 날짜: 2026-03-24 (새벽 + 저녁)
> 서버 버전: v0.7.0
> 이전 세션: `20260323_simulcast_pt_hardcoding_root_cause.md`

---

## 성과 요약

### 새벽 세션: Simulcast Conference 완성
- `is_video_pt` / `is_audio_pt` / `is_rtx_pt` → `stream_kind` 전환 (ingress 12곳)
- `resolve_stream_kind()`: Opus PT → rid → repaired-rid → RTX PT → Unknown
- fanout_simulcast_video: stream_map 기반 rid/codec 조회
- 키프레임 감지: codec 미확정 시 VP8+H264 양쪽 시도
- 클라이언트 `_sendPublishIntent`: SSRC=0 즉시 전송
- **결과: simulcast 영상 붙는 속도 대폭 향상 (3초→즉시)**

### 저녁 세션: PTT 수정 3건
1. **RTX PT fallback에 `has_video()` 가드** — H264 PT=103 == H264_RTX_PT=103 충돌 방지
2. **4차 heuristic 제거** — non-simulcast에서 intent/PT만으로 video/RTX 구별 불가 (RTX PT=104,108,114도 Opus 아님)
3. **stream_map.insert Unknown 덮어쓰기** — PUBLISH_TRACKS가 Unknown→Video 교정
4. **Unknown 재평가 heuristic 제거** — 같은 이유 (PUBLISH_TRACKS가 교정)

---

## 최종 resolve_stream_kind 판별 순서

```
1차: Opus PT=111 → Audio (전 브라우저 고정, ssrc-audio-level ID=4 충돌 방지)
2차: rid extension → Video (simulcast)
3차: repaired-rid extension → RTX
4차: [제거됨] — non-simulcast video/RTX 구별 불가
5차: is_rtx_pt() && has_video() → RTX (video 미등록 시 skip)
나머지: Unknown → PUBLISH_TRACKS stream_map.insert가 교정
```

### 모드별 동작

**Simulcast**: rid → 즉시 Video (PUBLISH_TRACKS 무관)
**Non-simulcast (PTT/Conference)**: rid 없음 → Unknown → PUBLISH_TRACKS SSRC 매핑 (~40ms 후 교정)
**비용**: ~40ms video loss (기존 is_video_pt 시절과 동일)

---

## 3모드 테스트 결과

| 모드 | 결과 | 비고 |
|------|------|------|
| Conference Simulcast | ✅ 정상 | 4명, 이전보다 빠르게 붙음 |
| Conference Non-sim | ✅ 정상 | 4명, loss=0, sr_relay=84 |
| PTT | ✅ 정상 | 2명, 발화권 정상, rewrite 정상 |

---

## 변경 파일

### 서버 (oxlens-sfu-server)
| 파일 | 변경 |
|------|------|
| `src/transport/udp/rtp_extension.rs` | **신규** — rid/repair-rid 파서 |
| `src/room/stream_map.rs` | **신규** — RtpStreamMap + insert Unknown 덮어쓰기 |
| `src/transport/udp/ingress.rs` | resolve_stream_kind + 12곳 stream_kind 전환 + 4차 제거 + 5차 has_video() 가드 + Unknown 재평가 제거 + 키프레임 양쪽 시도 + fanout stream_map 조회 + PLI stream_map 조회 |
| `src/room/participant.rs` | stream_map 필드 |
| `src/signaling/handler/track_ops.rs` | MediaIntent + stream_map SSRC 등록 + ssrc=0 스킵 |
| `src/signaling/handler/helpers.rs` | collect_subscribe_tracks tracks 기반 유지 (과도기) |
| `src/signaling/message.rs` | rid_extmap_id, repair_rid_extmap_id |
| `src/config.rs` | RID_EXTMAP_ID, REPAIR_RID_EXTMAP_ID |

### 클라이언트 (oxlens-home)
| 파일 | 변경 |
|------|------|
| `core/media-session.js` | _sendPublishIntent + _parseExtmapId |

---

## 기각된 접근법 (이번 세션 확정)

1. **Opus 체크를 rid 뒤에** → ssrc-audio-level ID=4 충돌
2. **codec 확정까지 키프레임 보류** → pending 지옥
3. **collect_subscribe_tracks stream_map** → rtx_ssrc/track_id 포맷 차이
4. **ingress notify + PUBLISH_TRACKS broadcast 동시** → 이중 TRACKS_UPDATE
5. **4차 intent.has_video 없이 Opus 아닌 모든 PT를 Video** → RTX(PT=114) 오판
6. **4차 intent.has_video 포함** → RTX(PT=114)도 intent.has_video=true 시 오판
7. **Unknown 재평가 heuristic** → 위 5,6번과 동일 문제

---

## Phase D (다음 세션)

1. getStats 폴링 삭제 → intent만 전송
2. PUBLISH_TRACKS에서 SSRC 제거
3. ingress notify_new_stream 활성화
4. collect_subscribe_tracks → stream_map 전환
5. 클라이언트: video TRACKS_UPDATE 수신 시에만 타일 생성

**선행 조건**: non-simulcast에서 Unknown→Video 교정이 PUBLISH_TRACKS 없이도 동작해야 함 (현재는 PUBLISH_TRACKS SSRC에 의존)

---

*author: kodeholic (powered by Claude)*
