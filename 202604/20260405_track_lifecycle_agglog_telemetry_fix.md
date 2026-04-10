# 세션: 트랙 lifecycle agg-log 체계 구축 + 텔레메트리 부정합 수정

**날짜**: 2026-04-05
**영역**: 서버 (track_ops.rs, room_ops.rs, ingress.rs, message.rs) + 클라이언트 (presets.js, voice_radio/app.js)
**서버 버전**: v0.6.16-dev

---

## 목표

PUBLISH_TRACKS add/remove 과정에서 agg-log가 현재 상태를 정확히 반영하는지 전수 점검 + 텔레메트리 부정합 수정.

---

## 작업 내용

### 1. 트랙 lifecycle agg-log 체계 구축

**현황 분석**: track:registered(ingress FullSim)만 있고, HalfNonSim/FullNonSim 사전등록 + remove + cleanup 경로에 agg-log 없음.

**추가한 agg-log 5종**:

| 키 | 위치 | 시점 | src 태그 |
|---|---|---|---|
| `track:registered` | track_ops.rs ×2 | HalfNonSim/FullNonSim 사전등록 | `track_ops:register_nonsim` |
| `track:removed` | track_ops.rs ×1 | PUBLISH_TRACKS(remove) 실제 제거 | `track_ops:publish_remove` |
| `track:cleanup` | room_ops.rs ×2 | leave / disconnect cleanup | `room_ops:leave` / `room_ops:disconnect` |

**정상 lifecycle 체인**: `publish_intent → registered(audio) + registered(video) → ... → publish_remove → removed → cleanup`

### 2. PUBLISH_TRACKS(remove) deserialization 실패 수정 (P0)

**원인**: `PublishTrackItem.ssrc`가 필수 필드(`#[serde(default)]` 없음). 클라이언트 remove 메시지는 ssrc를 보내지 않아 deserialization 실패 → "invalid payload" 에러 반환 → remove 처리 안 됨.

**수정**: `message.rs` — `PublishTrackItem.ssrc`에 `#[serde(default)]` 추가.

**영향**: remove가 정상 동작하면서 intent/stream_map/tracks 정리, track:publish_remove + track:removed agg-log 기록.

### 3. ingress agg-log audio 속성 부정합 수정 (P2)

**원인**: `register_and_notify`에서 audio에도 `video_codec` 기본값(VP8)과 `source.unwrap_or("camera")` 적용.

**수정**: `ingress.rs` — audio일 때 `codec=opus`, `source=-`로 표시. `log_codec`/`log_source` 지역변수 추가.

### 4. agg-log key 충돌 수정

**원인**: `track:registered` key가 `[room_id, user_id]`만으로 구성 → audio와 video가 같은 key → `inc_with`에서 마지막 메시지(audio)가 video를 덮어쓰기.

**수정**: track_ops.rs ×2 + ingress.rs ×1 — key에 kind 추가: `["track:registered", room_id, user_id, kind]`. audio/video 별도 행.

### 5. 클라이언트 preset 방어 코딩

**원인**: `resolvePreset("voice_radio")`에서 video=null → `videoDuplex: "full"`로 폴백. 현재는 `addVideoTrack({duplex:"half"})`에서 덮어쓰므로 동작하지만 잠재적 위험.

**수정**:
- `presets.js`: `videoDuplex: preset.video?.duplex || null` (null 반환)
- `voice_radio/app.js`: `if (preset.hasVideo)` 가드 추가 (video 없는 프리셋에서 `_videoDuplex`/`_simulcastEnabled` 미설정)

### 6. METRICS_GUIDE_FOR_AI.md 현행화

- AGG LOG 레이블 사전: 5종 추가/갱신 (publish_intent, registered, publish_remove, removed, cleanup)
- 분석 체크리스트 항목 6: "트랙 이벤트" → "트랙 lifecycle" 강화, 정상 체인 명시
- 최종 갱신일 2026-04-05

---

## 스냅샷 검증 결과

3차에 걸쳐 빌드+시험:
1. **1차**: agg-log 추가 → track:registered(HalfNonSim) 동작 확인
2. **2차**: ssrc serde default + ingress audio 수정 → track:publish_remove + track:removed 정상 기록, codec=opus 확인
3. **3차**: agg-log key kind 분리 → audio/video 별도 행 표시 확인

**서버 로그 대조**: video(half) 사전등록은 서버 내부에서 정상 동작 확인 ([TRACK:REG] + [TRACK:VIRTUAL] 출력). agg-log에서 안 보이던 건 key 충돌이 원인.

---

## 주의: audio pt=0, codec=VP8은 의도적

ingress.rs에 명시적 주석:
```
// actual_pt: video만 PT 정규화 대상. audio는 0 (Opus PT=111 전 브라우저 고정)
// audio에 actual_pt=111을 넣으면 PT 정규화 코드가 Opus를 VP8(96)으로 변조함!
```

participant.tracks의 audio `actual_pt=0`, `video_codec=VP8`은 데이터 모델의 한계 (VideoCodec enum에 Opus 없음). 스냅샷 표시는 개선 여지 있지만 기능적 문제 아님.

---

## 잔여 이슈

1. **TRACK IDENTITY에서 video 미표시**: 서버 로그에서는 등록 확인, agg-log에서도 확인, 하지만 admin snapshot의 TRACK IDENTITY 섹션에서 video가 안 보임. admin WS snapshot 갱신 타이밍 or 스냅샷 생성 시점 불일치 가능성. 기능에는 영향 없음 (PTT relay 정상).
2. **U156 INTENT received=false 패턴**: 3번째 참가자(마지막 입장)에서 반복. intent merge가 되어야 하는데 스냅샷에서 false. 서버 로그에서는 PUBLISH_TRACKS 처리 확인. 1번과 같은 snapshot 타이밍 이슈일 수 있음.
3. **ack_mismatch 지속**: half-duplex virtual SSRC vs 원본 SSRC 불일치. 기능적으로는 tolerate 처리됨.

---

## 오늘의 기각 후보

없음 — 이번 세션은 기존 코드의 진단 정확성 개선에 집중.

---

## 오늘의 지침 후보 (SKILL 반영 검토)

1. **agg-log key 설계 원칙**: 같은 이벤트를 종류별로 구분해야 하면 key에 종류(kind 등) 포함. `inc_with`는 마지막 메시지만 남기므로 구분 안 하면 덮어쓰기됨.
2. **serde 필수/선택 필드 규칙**: action별로 필요한 필드가 다르면 `#[serde(default)]` 적용. add에서는 필수지만 remove에서는 불필요한 필드 → default로 통일.
3. **스냅샷 분석 원칙 추가**: AGG LOG에서 `publish_intent`에 video 있는데 `registered(video)` 없으면 등록 실패 → 서버 로그 확인 필수.

---

## 수정 파일 목록

### 서버 (oxlens-sfu-server)
- `src/signaling/message.rs` — PublishTrackItem.ssrc serde default
- `src/signaling/handler/track_ops.rs` — track:registered agg-log ×2 + track:removed agg-log + key kind 분리
- `src/signaling/handler/room_ops.rs` — track:cleanup agg-log ×2 (leave + disconnect)
- `src/transport/udp/ingress.rs` — audio codec=opus/source=- + key kind 분리

### 클라이언트 (oxlens-home)
- `demo/presets.js` — videoDuplex null 반환
- `demo/scenarios/voice_radio/app.js` — hasVideo 가드

### 컨텍스트
- `context/METRICS_GUIDE_FOR_AI.md` — 트랙 lifecycle agg-log 반영

---

*author: kodeholic (powered by Claude)*
