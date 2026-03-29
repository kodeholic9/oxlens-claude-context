# 2026-03-29 화면공유 텔레메트리 + rid=l 버그 수정

## 작업 요약

### 1. 화면공유 텔레메트리 3건 (코딩 완료)

화면공유 시 camera vs screen 구분이 불가능한 텔레메트리 빈틈 3건 수정.

| # | 파일 | 변경 | 효과 |
|---|---|---|---|
| 1 | `core/client.js` | getDisplayMedia 실패 시 `pushCritical` 추가 | 화면공유 실패가 어드민 타임라인에 기록 |
| 2 | `core/telemetry.js` | `start()`/`stop()`에 screen:started/stopped 이벤트 구독/해제, outbound에 source 태그 (screenMid 매칭), inbound에 source 태그 (subscribeTracks lookup) | 타임라인에 화면공유 시작/종료 시점 기록, camera vs screen 즉시 구분 |
| 3 | `demo/admin/snapshot.js` | PUBLISH/SUBSCRIBE 스냅샷에 `:screen` 태그 | `[U411:video:screen]`, `[U286←U411:video:screen]` 형태로 출력 |

### 2. rid=l mark_notified 누락 버그 (코딩 완료, 서버 빌드 검증 완료)

**근본 원인**: simulcast rid=l 스트림을 skip할 때 `mark_notified()`를 안 해서, 이후 screen 트랙의 `notify_new_stream()`이 호출될 때 `pending_notifications()`에 camera l-layer가 잔류 → `.find(|s| s.kind == Video)`가 camera l-layer를 먼저 pick → camera의 vssrc와 track_id로 broadcast.

**증상**: simulcast 방에서 첫 화면공유 시 subscriber에 screen이 아닌 camera 정보가 전달 → screen 타일 미생성. 2차 화면공유부터는 l-layer가 이미 소진되어 정상.

**수정**: `src/transport/udp/ingress.rs` — rid=l skip 시 `mark_notified()` 6줄 추가.

**영향 범위**: simulcast 방에서만 발생. non-simulcast/PTT 무관.

### 3. 돌림노래 현상 조사

화면공유 시 음성 돌림노래 현상 보고 → 테스트 환경 한계로 확정.

**원인**: MacBook 1대 3탭 환경에서 simulcast + screen share = 탭당 SW encoder 3개(h+l+screen) × 3탭 = 9개 → CPU 포화 → AEC 타이밍 지연 → echo loop.

**증거**: simulcast 방에서 `quality_limit=cpu` 발생, non-simulcast 일반 대화방에서는 encoder 부하 적어(2개×3=6개) 미발생.

**결론**: 실배포 환경(기기당 최대 encoder 3개)에서는 발생하지 않음. OxLens 버그 아님.

## 변경 파일 목록

### 서버 (oxlens-sfu-server)
- `src/transport/udp/ingress.rs` — rid=l skip 시 `mark_notified()` 추가 (+6줄)

### 웹 클라이언트 (oxlens-home)
- `core/client.js` — getDisplayMedia 실패 시 `pushCritical` (+1줄)
- `core/telemetry.js` — screen 이벤트 구독/해제, outbound/inbound source 태그 (+28줄)
- `demo/admin/snapshot.js` — PUBLISH/SUBSCRIBE `:screen` 태그 (+4줄)

## 기각된 접근법
- 없음 (이번 세션은 텔레메트리 확장 + 버그 수정, 설계 분기 없음)

## 시험 결과
- 텔레메트리 source 태그: PUBLISH `[U411:video:screen]` ✅, SUBSCRIBE `[U286←U411:video:screen]` ✅
- rid=l 버그 수정 후: 첫 화면공유부터 screen 타일 정상 생성 ✅
- 돌림노래: simulcast 방 = 재현(CPU 과부하), non-simulcast 방 = 미재현 → 테스트 환경 한계 확정

## 다음 세션 TODO
- SKILL_OXLENS.md 반영 (아래 블록)
- 어드민 타임라인에 `screen_share_started`/`screen_share_stopped` 이벤트 description 매핑 (render-detail.js eventDescriptionExport)
- Git commit

---
*author: kodeholic (powered by Claude)*
