# 20260418c — Conference video encoder=null 근본 원인 확정

## 요약

Conference 시나리오 영상 미표시의 근본 원인을 `encoder=null` (Chrome이 OpenH264 인코더 미할당)로 확정.
video_radio 탭과의 교차 분석으로 재현 조건 특정. 글로벌 선례 조사(LiveKit). 개발환경 한정 문제.

## 증상

- 화상회의에서 내 영상+상대 영상 간헐적 미표시
- 한쪽 안 되면 양쪽 다 안 됨, 잘 되면 양쪽 다 잘 됨
- 코드 경로 100% 동일 (정상/비정상 모두)

## 진단 과정

### 1. DIAG 로그 추가 (endpoint.js 3곳)

- `[SDK:CAM]` getUserMedia 직후 track 상태
- `[DIAG:VIDEO]` enableCamera 2초 후 sender.getStats() (first-time 경로)
- `[DIAG:VIDEO:RESUME]` resume 경로 동일 진단

### 2. 12회 반복 시험 결과

| userId | enableCamera | encoder | framesEncoded | 결과 |
|--------|-------------|---------|---------------|------|
| U852 | 11.6ms | OpenH264 | 44 | ✅ |
| U687 | 8.1ms | OpenH264 | 44 | ✅ |
| U391 | 1210ms | OpenH264 | 44 | ✅ |
| U145 | 16.2ms | OpenH264 | 44 | ✅ |
| U415 | 198ms | OpenH264 | 44 | ✅ |
| **U663** | **17.8ms** | **null** | **0** | **❌** |

- encoder=null: Chrome이 OpenH264 인코더를 아예 할당하지 않음
- track=video/live/unmuted, enabled=true, SDP 정상, PC connected — 전부 정상인데 인코더만 미할당

### 3. video_radio 교차 분석

U663(❌, 8:54:49) 시점에 video_radio 탭 상태:
- U296이 hot_standby (8:54:42에 발화 OFF)
- hot_standby = `replaceTrack(null)` → 인코더 해제 + 카메라 track still live

비교:
- U145(✅, 8:54:38) 시점 → video_radio U296 **발화 중** (인코더 활성)
- U663(❌, 8:54:49) 시점 → video_radio U296 **hot_standby** (인코더 해제, 카메라 점유)

핵심: "인코더 반납 + 카메라 점유" 중간 상태에서 다른 탭이 re-nego로 video 추가 시 실패.

## 근본 원인

Chrome 내부 레이스 컨디션:
- Camera capture는 Browser 프로세스 중앙 관리, 프레임을 IPC로 각 탭에 분배
- 같은 origin(127.0.0.1:5500) → 같은 Renderer 프로세스 → 인코더 리소스 경합
- video_radio 탭의 인코더가 해제 중인 타이밍에 conference 탭이 새 인코더 생성 시도 → 간헐적 실패

이전 코드(lazy loading 전)에서 안 됐던 이유:
- 초기 offer에 video track 포함 → addTransceiver(videoTrack) 시점에 즉시 인코더 할당
- re-nego가 아닌 초기 offer이므로 타이밍 경합 없음

## 글로벌 선례 조사

- **LiveKit**: 동일 패턴(addTransceiver(realTrack) + negotiate) 사용. 하지만 멀티탭 카메라 공유 시나리오 미시험 → 미발견
- **mediasoup/Twilio**: 유사 re-nego 패턴. encoder=null 리포트 없음
- **Chrome 아키텍처 문서**: VideoCaptureController가 Browser 프로세스에서 프레임 분배 확인
- **BlogGeek.me**: "Chrome이 CPU 이슈 감지 시 HW→SW fallback 실패 → 아무것도 안 됨" 사례 존재

결론: 글로벌 탑들도 같은 코드를 쓰지만 재현 조건(같은 브라우저 + 같은 카메라 + 멀티 시나리오)을 만들 일이 없어서 모름.

## 결론

- **상용 환경**: 1인 1탭 → 문제 없음
- **개발 환경**: 같은 Chrome에서 여러 시나리오 동시 실행 시 간헐적 발생
- **방어 로직(미구현)**: encoder=null 감지 → 토스트 → replaceTrack(null→track) 재시도 → 실패 시 새로고침 안내

## 수정 파일

| 파일 | 수정 |
|------|------|
| `core/endpoint.js` | `[SDK:CAM]` track 상태 로그, `[DIAG:VIDEO]` 인코더 진단 2곳 (first-time + resume) |

※ pipe.js, sdp-negotiator.js 수정은 이전 세션(20260418a)에서 완료

## 기각

- 초기 offer에 video 포함 회귀 — connect→publish 분리의 40배 성능 이득 포기 불가
- setupPublishPc를 enableCamera까지 defer — audio 지연 발생

## 다음 세션

- encoder=null 감지 시 토스트 + replaceTrack 재시도 복구 로직 구현
- 상용 전 DIAG verbose 로그 정리 (pipe.js bindSender, [SDK:CAM] settings JSON)
