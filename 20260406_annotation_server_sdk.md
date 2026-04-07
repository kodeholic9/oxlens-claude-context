# 2026-04-06: PTT jb_delay 수정 + 스냅샷 버그 + Annotation 서버/SDK 배관

## 요약

1. **PTT jb_delay 1634ms → 정상**: clear_speaker() 이중 호출로 인한 silence flush 이중 생성이 근본 원인. 멱등 가드 1줄 추가.
2. **audio pt=0/codec=VP8 스냅샷 버그 수정**: audio 트랙에 pt=111, codec=opus 정상 표시.
3. **Canvas Annotation 설계 업데이트**: 제스처 자동 분기(PointerEvent), panzoom+perfect-freehand 라이브러리, ANNOTATE/ANNOTATE_EVENT opcode 1쌍.
4. **Annotation 서버+SDK 배관 완료**: 서버 빌드 성공, 클라이언트 constants/signaling/client.js 수정 완료.
5. **SR Translation 미완 아님 확인**: 코드 확인 결과 이미 구현 완료. 메모리 잔재 정리.

## 수정 파일

### 서버 (oxlens-sfu-server)
| 파일 | 변경 |
|------|------|
| `room/ptt_rewriter.rs` | `clear_speaker()` 상단 speaker.is_none() 가드 — 이중 silence flush 방지 |
| `signaling/handler/track_ops.rs` | audio `actual_pt = 111` (기존 0) |
| `signaling/handler/admin.rs` | audio 트랙 `"codec":"opus"`, video만 `video_codec` 출력 |
| `signaling/opcode.rs` | `ANNOTATE=60`, `ANNOTATE_EVENT=160` 추가 |
| `signaling/handler/mod.rs` | dispatch에 `ANNOTATE → helpers::handle_annotate` 추가 |
| `signaling/handler/helpers.rs` | `handle_annotate()` — payload 통째로 relay, action 파싱 없음 |

### 클라이언트 (oxlens-home)
| 파일 | 변경 |
|------|------|
| `demo/admin/snapshot.js` | `t.video_codec \|\| t.codec \|\| "?"` fallback |
| `core/constants.js` | `ANNOTATE: 60`, `ANNOTATE_EVENT: 160` 추가 |
| `core/signaling.js` | ANNOTATE_EVENT → action별 `annotate:stroke/clear/zoom` emit |
| `core/client.js` | `annotate(payload)` 메서드 추가 |
| `core/annotation/` | 디렉토리 생성 (annotation-layer.js는 다음 세션) |

## PTT jb_delay 근본 원인 (상세)

### 이중 silence flush 메커니즘

```
21:53:28  FLOOR released → silence flush #1 (last_ts=191040, last_relay_at=28.959)
21:53:30  SWITCH_DUPLEX half→full → flush_ptt_silence() → clear_speaker() 재호출
          → speaker 이미 None인데 silence flush #2 생성 (last_ts=193920)
```

subscriber 입장: flush #1 ts=191040 (arrival=28.959s) → flush #2 ts=192000 (arrival=30.719s)
**ts_gap=20ms, arrival_gap=1760ms** → NetEQ: "1740ms 늦게 도착" → jitter buffer 확장 → jb_delay=1634ms

### 수정: clear_speaker() 멱등 가드
```rust
if s.speaker.is_none() { return None; }
```

## Annotation 설계 (업데이트 완료)

설계 문서: `context/20260406_canvas_annotation_design.md`

### 주요 변경사항
- **opcode 6개 → 2개**: `ANNOTATE(60)` + `ANNOTATE_EVENT(160)`, action 필드로 분기
- **제스처 자동 분기**: 모드 토글 없이 1 finger=draw, 2 finger=zoom/pan (PointerEvent 기반)
- **라이브러리**: `@panzoom/panzoom`(~3.7KB) + `perfect-freehand`(~2KB), 총 ~6KB
- **기각**: 펜 모드 토글, Hammer.js, tldraw/Konva/Fabric

### 서버 구현 (완료, 빌드 성공)
- `handle_annotate()`: payload 통째로 relay, action 파싱 없음, user_id 주입
- 나중에 action 추가(undo, pointer 등)해도 서버 변경 0

## 다음 세션

1. **`core/annotation/annotation-layer.js`** 작성 — 이 대화에 코드 준비 완료:
   - 제스처 자동 분기 (_activePointers, _gestureState)
   - perfect-freehand 동적 로딩 (esm.sh CDN)
   - 페이드아웃 렌더 루프 (rAF + opacity)
   - onRemoteStroke/Clear/Zoom 수신 API
2. **support 시나리오 연동**: AnnotationLayer 생성 + annotate:* 이벤트 바인딩 + 컨트롤 UI
3. **브라우저 테스트**: 전문가↔현장기사 양방향 annotation 동작 확인

## 지침 후보

- **clear_speaker()는 멱등**: speaker=None이면 silence flush 생성 금지 (SKILL 반영 대상)
- **ANNOTATE opcode는 순수 relay**: 서버가 action 파싱하지 않음. 확장성 보장

## 기각 후보

- **reset_relay_timing()으로 jb_delay 해결**: 근본 원인은 이중 silence flush. 인위 조작 불필요
- **opcode 3쌍 분리 (60-62/160-162)**: action 필드 1쌍이 확장성 우수
- **펜 모드 토글 버튼**: PointerEvent touch count 자동 분기가 업계 표준
- **Hammer.js 제스처 라이브러리**: 유지보수 중단(2017). PointerEvent 네이티브로 충분

## 커밋 메시지

### oxlens-sfu-server
```
fix(ptt): prevent double silence flush — root cause of jb_delay spike

clear_speaker() now returns None if speaker is already None.
Double flush caused ts_gap(20ms) << arrival_gap(seconds) →
NetEQ expanded jitter buffer to 1634ms.

Also: audio track snapshot pt=111/codec=opus (was 0/VP8).
New: ANNOTATE(op=60) + ANNOTATE_EVENT(op=160) — pure relay handler.
```

### oxlens-home
```
feat(sdk): ANNOTATE opcode + annotation module scaffold

- constants.js: ANNOTATE=60, ANNOTATE_EVENT=160
- signaling.js: ANNOTATE_EVENT → annotate:stroke/clear/zoom emit
- client.js: annotate(payload) method
- core/annotation/ directory created
- admin snapshot: audio codec=opus (was VP8)
```

---

*author: kodeholic (powered by Claude)*
