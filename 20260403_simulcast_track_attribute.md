# 세션: Simulcast 트랙 속성 전환 — room.simulcast_enabled → Track.simulcast

- **날짜**: 2026-04-03
- **버전**: v0.6.13-dev → v0.6.14-dev
- **영역**: 서버 (participant.rs, stream_map.rs, ingress.rs, track_ops.rs, helpers.rs, room_ops.rs, tasks.rs)
- **이전 세션**: `20260403_telemetry_track_identity.md`

---

## 1. 배경

데모 시나리오 설계 (20260403_demo_scenario_design_review.md)에서 확정된 트랙 단위 duplex + simulcast 속성.
`room.simulcast_enabled`는 방 전체에 일괄 적용되어 혼합 시나리오(full-duplex camera sim=on + half-duplex bodycam sim=off)를 지원 불가.

## 2. 핵심 변경

### 데이터 모델
- `Track.simulcast: bool` 필드 추가 (participant.rs)
- `RtpStream.simulcast: bool` 필드 추가 (stream_map.rs)
- `add_track_ext()` / `add_track_full()` simulcast 파라미터 추가

### 파생 규칙 (서버 강제)
```
half-duplex  →  항상 sim=false  (PttRewriter + SimulcastRewriter 충돌)
full-duplex  →  room.simulcast_enabled 기본값 (프리셋에서 오버라이드 가능)
screen       →  항상 sim=false
```

### `room.simulcast_enabled` 역할 변경
- **이전**: 방 전체 simulcast on/off 스위치 (라우팅 판단 기준)
- **이후**: 방 기본값 (intent 계산 + 클라이언트 config + non-sim 등록 게이트용)
- 핫패스 라우팅 판단은 모두 `track.simulcast` / `stream.simulcast` 기반으로 전환

## 3. 수정 파일 (7개)

| 파일 | 수정 내용 |
|------|----------|
| `participant.rs` | `Track.simulcast: bool`, `add_track_ext/add_track_full` 파라미터 추가 |
| `stream_map.rs` | `RtpStream.simulcast: bool`, 테스트 `duplex` 필드 누락 수정 |
| `ingress.rs` | `resolve_stream_kind` 파라미터 제거 + intent 기반 sim 파생, 핫패스 `is_sim_track`, PLI/NACK vssrc 역매핑 guard 제거, SR translation `track.simulcast` 전환 (10곳) |
| `track_ops.rs` | `VideoSource.simulcast` 파생, expected SSRC `t.simulcast`, PLI target 2곳, SUBSCRIBE_LAYER per-publisher 가드, `add_track_ext` simulcast=false |
| `helpers.rs` | `collect_subscribe_tracks` vssrc 인라인 교체, `build_remove_tracks` sim_enabled 파라미터 제거 |
| `room_ops.rs` | `build_remove_tracks` 호출부 2곳 시그니처 맞춤 |
| `tasks.rs` | `build_remove_tracks` 호출부 시그니처 맞춤 (zombie reaper) |

## 4. ingress.rs 핫패스 변경 상세

| 위치 | 이전 | 이후 |
|------|------|------|
| resolve_stream_kind 파라미터 | `room.simulcast_enabled` 전달 | 파라미터 제거, intent에서 `intent_has_sim` 파생 |
| rid 파싱 gate | `simulcast_enabled && has_rid_hint` | `intent_has_sim && has_rid_hint` |
| RtpStream 생성 (rid 경로) | simulcast 미설정 | `stream.simulcast = true` |
| RtpStream 생성 (PROMOTED 경로) | simulcast 미설정 | `stream.simulcast = intent.find_video_by_mid().simulcast` |
| 핫패스 fan-out 분기 | `room.simulcast_enabled && !is_screen_video` | `is_sim_track` (stream_map 1회 조회) |
| PLI Governor non-sim 감지 | `!room.simulcast_enabled \|\| is_screen_video` | `!is_sim_track` |
| PLI relay vssrc 역매핑 | `if room.simulcast_enabled { if let Some(pub_p)...` | `if let Some(pub_p)...` (guard 제거, None fallthrough) |
| NACK vssrc 역매핑 | 동일 패턴 | 동일 변경 + 고아 중괄호 정리 |
| SR translation | `if room.simulcast_enabled` | `if track_sim` (tracks에서 per-SSRC 조회) |
| notify_new_stream subscriber_ssrc | `room.simulcast_enabled && !is_screen` | `stream.simulcast` |

## 5. helpers.rs 주요 변경

### collect_subscribe_tracks
- **이전**: 후처리 블록에서 JSON value의 `kind=="video" && source!="screen"` 체크 → vssrc 교체
- **이후**: `.map()` 클로저 안에서 `t.simulcast` 체크 → 인라인 vssrc 교체. 후처리 블록 삭제.

### build_remove_tracks
- **이전**: `sim_enabled: bool` 파라미터 + `simulcast_replace_video_ssrc_direct()` 호출
- **이후**: 파라미터 제거, `t.simulcast` 기반 인라인 처리. `simulcast_replace_video_ssrc_direct` dead code 처리.

## 6. 빌드 에러 수정

| 에러 | 원인 | 수정 |
|------|------|------|
| E0382 `src` borrow after move | `src`가 struct field로 이동 후 `simulcast:` 표현식에서 참조 | `sim` 변수를 struct 리터럴 전에 계산 |
| E0061 `build_remove_tracks` 4 args | tasks.rs 호출부 누락 | `room.simulcast_enabled` 파라미터 제거 |
| W unused `is_screen_video` | `is_sim_track`에 흡수됨 | `_is_screen_video`로 rename |
| W unused `room` param | `build_sr_translation`에서 room 불필요해짐 | `_room`으로 rename |

## 7. 검증

- `cargo build --release` — 빌드 성공, 경고 0
- Conference/Simulcast/PTT 실기기 테스트: **부장님 확인 필요**

## 8. 다음 작업

- [ ] Conference Simulcast 4탭 테스트 (기존 동작 보존 확인)
- [ ] PTT 2인 테스트 (half-duplex → sim=false 확인)
- [ ] 혼합 시나리오 테스트 (같은 방에 full+half duplex 공존)
- [ ] TRACKS_UPDATE에 `simulcast` 필드 추가 (클라이언트 UI 분기용)
- [ ] Moderated Floor Control (FLOOR_GRANT/DENY/SKIP/REORDER)
- [ ] 데모앱 components 추출 + conference/dispatch 데모앱 분리

## 9. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| `room.simulcast_enabled` 완전 제거 | 클라이언트 config, non-sim 등록 게이트, DIAG 로그에 여전히 필요. 역할만 "기본값"으로 격하 |
| `resolve_stream_kind`에 intent를 외부에서 전달 | stream_map 이중 lock 문제. 함수 내부에서 intent 추출이 더 깔끔 |
| PLI/NACK vssrc 역매핑 guard 유지 | 혼합 방에서 sim+non-sim 공존 시 room-level guard가 답 없음. `find_publisher_by_vssrc` None fallthrough로 충분 |
| `simulcast_replace_video_ssrc_direct` 유지 | `build_remove_tracks`에서 Track 구조체 직접 참조 가능 → JSON 후처리 불필요 |

---

*author: kodeholic (powered by Claude)*
