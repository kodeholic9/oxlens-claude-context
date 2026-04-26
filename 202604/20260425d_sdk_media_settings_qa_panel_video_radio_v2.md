# 2026-04-25 (d) — 시험 체계 정착 + SDK Media Settings G1~G4 + QA 패널 + 영상무전 회귀

## 한 줄 요약

시험 체계 단일 출처 정립 + SDK 미디어 설정 API 4그룹 1차 사이클(설계→코딩→시험) + QA UI 패널/토글 인프라 + 영상무전 smoke v1→v2 회귀(8/0/0) + participant.js 의 pipe.mount 통일 수정 + 실측으로 수정 전/후 동작 확인.

## 흐름

1. **시험 체계 명칭 정착** — "OxQA" 같은 별도 명칭 기각, "시험 체계 (E2E / Smoke)" 일반 용어 사용. 단일 출처 = `context/guide/QA_GUIDE_FOR_AI.md`. 시험 시작 전 의무 로드. PROJECT_MASTER 에 섹션 신설(부장님 명시 요청 시에만 직접 수정 정책 #23 적용).
2. **QA_GUIDE §0.5 시험 매트릭스 신설** — 1행=1 SDK 외부 공개 API. `✅`/`⚠️`/`[개발필요]`/`[감시]` 라벨. QA 전용 방(`qa_test_01/02/03`) 강제. nested pipeline 스키마 갱신.
3. **SDK Media Settings 설계** — G1(송신 파라미터) / G2(출력 제어) / G3(캡처 처리) / G4(트랙 필터 통합) / G5(코덱 런타임 — 별도 사이클 보류). 베낀 티 회피: LiveKit `setMaxBitrate`/`setProcessor`/`restartTrack` 이름 차용 안 함, 우리 어휘(`setBitrate`/`addFilter`/`swapTrack`/`MediaAcquire`)로 흡수.
4. **G1~G4 한방 코딩** — `pipe.js` (G1/G2/G4 메서드 + setter property), `device-manager.js` (G2 글로벌), `engine.js` (4그룹 facade + 재획득 fallback), `core/filters/background-blur-filter.js` + `noise-cancel-filter.js` (placeholder 2개).
5. **G1~G4 1차 시험** — 16/0/5 (성공/실패/알수없음). `setMicCapture` 의 1→2차 fallback 경로 (재획득 + `pipe.swapTrack`) 발동 확인. element 측 G2 검증은 다중 참가자 환경 부재로 알수없음.
6. **QA UI 패널 인프라 도입** — A(시험 진행) + B(단계 상세) + D(참가자 상태) 3 패널. C(컨트롤 버튼)는 부장님 명시 거부로 제외. `__qa__.test.start/step/result/end/dismiss` API. 참가자 폴링 500ms.
7. **부장님 화면 인지 보강** — 패널 높이 드래그(`resize: vertical`) + 헤더 토글 버튼 3개(시험/참가자/Grid, `user-hidden` 클래스). 시험 패널 비활성 시 placeholder 텍스트.
8. **영상무전 smoke v1** — 8단계 시나리오. 6/1/1. S4(1.5s 측정창 admin 카운터) 실패, S5(`remoteEndpoints.get('alice_vr')`) 알수없음.
9. **S4/S5 사실 추적** — sfu_metrics 송신 주기 = **3000 ms 정확** (5회 측정 ts 차이 [3000,3000,3000,3001,3000]). PTT virtual track = `trackId='ptt-audio'/'ptt-video'` 고정 + `userId=null` (서버가 의도적으로 비귀속, `room.js resolveOnTrack` 의 isPtt 분기와 일치). 1차 시험의 expected 자체가 시나리오 부적합.
10. **영상무전 smoke v2 (수정 expected)** — 측정창 1.5s→3.5s, S5 검증 `getAllSubscribePipes().filter(kind=video, duplex=half)` 로 변경. **8/0/0**. S4 pub.rtp_in delta=293, S5 pttVideoPipes.count=1.
11. **부장님 지적: 그리드 영역 remote 미표시 + pipe.mount 통일** — participant.js 의 로컬은 stream 직접 srcObject (✗), 리모트 video 는 pipe.mount() 호출하지만 cssText 로 덼어쓰며 freeze masking 우회 (✗), 리모트 audio 는 srcObject 만 변도 element 에 복사 (✗). 근본원인: `el.muted=false` + `el.play()` 미호출 → autoplay 정책 위반 → element 영구적 paused.
12. **수정 + 실측** — participant.html 의 고정 video/audio 제거, slot 컨테이너 + audio-wrap 추가. participant.js 는 `attachMounted(pipe, container)` 헬퍼 (muted=true + play() 명시) + 로컬/리모트 모두 이 경로. PTT freeze masking 은 `engine.on('floor:state')` 핵들러에서 showVideo/hideVideo 자동 호출. 실측 결과: 로컬 정상 재생 (paused=false, videoWidth=640, readyState=4), 리모트도 floor:state 관련 마다 srcObject 재할당 + play() 호출 확인 (`pipe._showing: true`, `paused: false`). styleLeft 는 fake media 환경의 디코드 한계(`videoWidth=0` 유지)로 rVFC 미 fire → `left:0` 도달 안 함. 실제 카메라 환경에서는 정상 작동 예상.

## 변경 파일

### SDK 코드
- `oxlens-home/core/pipe.js` — G1 메서드 5개(setBitrate/setFps/setSize/degradation/getBitrate), G2 muted/volume setter, G4 `_filterPipeline` lazy + addFilter/removeFilter/clearFilters/filters
- `oxlens-home/core/device-manager.js` — G2 `_outputMuted`/`_outputVolume` + setOutputMuted/setOutputVolume + addOutputElement 자동 상속
- `oxlens-home/core/engine.js` — 4그룹 facade (setVideoBitrate/Fps/Size, outputMuted/outputVolume property, setMicGain/setMicCapture, setBackgroundBlur/setNoiseCancel) + `_reacquireVideo` 헬퍼 + filters 모듈 import
- `oxlens-home/core/filters/background-blur-filter.js` — 신규 placeholder VideoFilter
- `oxlens-home/core/filters/noise-cancel-filter.js` — 신규 placeholder AudioFilter (Web Audio HP+LP+Compressor)

### QA 인프라
- `oxlens-home/qa/index.html` — 시험 패널 + 참가자 패널 div, CSS, 헤더 토글 버튼 3개
- `oxlens-home/qa/controller.js` — `__qa__.test.*` API + `renderParticipantsPanel` (500ms 폴링) + visibility 토글 핸들러
- `oxlens-home/qa/participant.html` — 고정 video/audio 제거, slot 컨테이너 + off-screen audio-wrap 추가 + .slot CSS 조정
- `oxlens-home/qa/participant.js` — `attachMounted` 헬퍼 도입, 로컬/리모트 video + 리모트 audio 모두 pipe.mount 통일, autoplay 정책 회피 (`muted=true; play()`), `floor:state` 기반 PTT freeze masking 자동 호출

### 문서
- `context/design/20260425_sdk_media_settings.md` — 신규 (G1~G5 설계)
- `context/guide/QA_GUIDE_FOR_AI.md` — §0.5 매트릭스 신설 + nested pipeline 스키마 + dot-path pluck 갱신
- `context/qa/20260425_g1_g4_facade.md` — G1~G4 1차 시험 (16/0/5)
- `context/qa/20260425_video_radio_smoke.md` — 영상무전 v1 (6/1/1)
- `context/qa/20260425_s4_s5_trace.md` — S4/S5 사실 추적
- `context/qa/20260425_video_radio_smoke_v2.md` — 영상무전 v2 (8/0/0)
- `context/qa/20260425_pipe_mount_unification.md` — participant.js pipe.mount 통일 + 수정 전/후 실측
- `PROJECT_MASTER.md` — 시험 체계 섹션 신설 (부장님 명시 요청 반영)

## 도출 사실 / 원칙

- **시험 체계 = E2E = Smoke 동일 행위**. 단일 출처 QA_GUIDE_FOR_AI.md. 별도 명칭 만들지 않음
- **시험 결과 기록은 호출/반환값/측정값 + 판정(성공/실패/알수없음)** — 추론(어느 분기 탔다, 왜 그런지) 분리. 평가어(통과/검증성공) 사용 금지
- **측정창 ≥ 송신 주기** — admin sfu_metrics 송신 주기 3000 ms 정확. 측정창이 짧으면 before/after 가 같은 메시지에서 추출되어 모든 카운터 delta=0
- **PTT virtual track 의 user_id=null 은 의도된 설계** — `trackId='ptt-audio'/'ptt-video'` 고정, `userId=null`, `duplex='half'`. 시나리오 검증 메서드는 `getAllSubscribePipes().filter(kind=video, duplex=half)` 사용 (`remoteEndpoints.get(userId)` 부적합)
- **sfu_metrics `pipeline` 키는 publishing 트랙 있을 때만 포함** — 참가자 0명이면 키 자체 누락
- **베낀 티 회피 원칙** — 업계 SDK 메서드명 그대로 차용 금지. 우리 SDK 어휘로 흡수. G4(트랙 필터)는 신규 도입 아니라 기존 `VideoFilterPipeline`/`AudioFilterPipeline` Pipe 차원 통합으로 표현
- **`pipe.mount()` 호출 자체로는 동작 보장 안 됨** — element.muted 설정 + element.play() 명시 호출 필요 (autoplay 정책). cssText 로 인라인 style 덼어쓰면 pipe 가 설정한 freeze masking style 이 말소됨 — 외부에서 style 직접 덼어쓰기 금지
- **size 책임은 wrap 컨테이너** — pipe.mount() 가 만든 video element 는 width/height 100%. 컨테이너의 .slot 이 size 결정. 호출자가 cssText 로 세먜한 값 덼어쓰는 우회 금지

## 오늘의 기각 후보

- **시험 명칭 "OxQA" 별도 정의** — `ox-` 접두어는 데몬/컴포넌트용. 추상 개념엔 일반 용어로 충분
- **시험 결과에서 추론 기재** — "1차 경로 적용", "재획득 fallback 발동" 같은 분기 식별은 actual 측정값에 직접 안 보이면 추론. 빼고 사실만
- **시험 결과 평가어 사용** — "통과", "검증 성공" 등. 판정은 성공/실패/알수없음 라벨로만
- **C 그룹 (컨트롤 버튼)** — 시험 일시정지/재실행/단계 진입 등. 부장님 명시 거부 ("내가 컨트롤할 필요가 있을까")
- **LiveKit 메서드명 그대로 차용** (`setMaxBitrate`/`setProcessor`/`restartTrack`) — 우리 SDK 어휘로 흡수
- **G4 BackgroundBlur/NoiseCancel 라이브러리 사이클 내 결정** — placeholder 슬롯만, 라이브러리(MediaPipe/RNNoise) 선택은 별도 사이클
- **시험 도구 환경에서 결과 라이브 관찰 가정** — Playwright 브라우저는 부장님 화면 외부. 시험 패널 만들어도 부장님이 자기 환경에서 시험 돌리지 않으면 인지 안 됨

## 오늘의 지침 후보

- **시험 시작 전 QA_GUIDE_FOR_AI.md 의무 로드** (METRICS_GUIDE 와 같은 의무 규칙)
- **시험 매트릭스 단일 출처는 QA_GUIDE §0.5** — 시나리오 정의서는 `context/qa/scenarios/*.md` 로 누적
- **시험 기록은 일자별 별도 파일** (`context/qa/YYYYMMDD_*.md`) — 세션 파일 (`context/YYYYMM/`) 과 분리
- **시험 기록의 expected 컬럼은 본 시험에서 명시 정의** — 사양 인용이 아닌 측정 기준
- **PTT-aware 검증 메서드 사용** — PTT 시나리오에서 `remoteEndpoints.get(userId)` 대신 `getAllSubscribePipes().filter(...)` 경로
- **admin 카운터 측정창 ≥ 3000 ms** (sfu_metrics 송신 주기)
- **부장님이 패널 직접 보면서 진행하시면 좋음** — Claude in Chrome 으로 부장님 브라우저 직접 진행 가능 환경 확인됨

## 미시험 / 후속 후보

### G1~G4 보강
- G2-2/G2-5 다중 참가자 환경에서 등록된 output element 의 `el.muted`/`el.volume` 직접 측정
- 실제 카메라 환경에서 G1 1차 `applyConstraints` 미반영 분기 (Firefox 등)
- `BackgroundBlur`/`NoiseCancel` 출력 track 픽셀/신호 비교 (라이브러리 통합 후)

### 코드 위치 미식별 (서버)
- `SfuMetrics::flush()` 호출처 (lib.rs spawn 본문에 미식별)
- sfu_metrics 메시지에 `pipeline` 키 추가하는 코드 위치
- 서버 측 PTT virtual track 의 `t.user_id` 비우는 정확한 위치 (`helpers.rs` / `track_ops.rs`)

### 시험 인프라 보강
- console errors 메시지 자동 캡처 (현재 건수만 측정, 메시지 미캡처)
- 시험 결과 자동 export (현재 AI MD 작성)
- 시나리오 spec 의 파일화 (현재 inline)
- 회귀 시험 누적 db (회차간 diff 비교)

### 시험 시나리오 누적
- 음성무전 (voice_radio) smoke
- dispatch / support / moderate 시나리오
- conference simulcast 회귀
- 1대N (3명 이상) PTT
- PTT freeze masking 의 element 가시성 직접 측정 (`left:-9999px` ↔ rVFC fire)
- TS 24.380 MBCP DC 패킷 capture
- 양방향 사이클 반복 안정성 (회차 5+)

## 다음 작업 예약 (부장님 결정 영역)

| 후보 | 우선순위 |
|---|---|
| Step 4c 후속 작업 (메모리상 활성) | 부장님 결정 |
| G2 다중 참가자 보강 시험 | 우선 1 (인프라 동일) |
| 음성무전/conference 시나리오 누적 | 우선 2 |
| 서버 sfu_metrics flush 호출처 추적 | 우선 3 |
| G4 라이브러리 통합 (MediaPipe/RNNoise) | 부장님 결정 |
| Hub Registry / Cross-SFU Phase 2 | 부장님 명시 시 |

---

*author: kodeholic (powered by Claude)*
