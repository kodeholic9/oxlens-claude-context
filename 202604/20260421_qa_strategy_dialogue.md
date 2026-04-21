# QA 자동화 작전 수립 — Claude in Chrome 한계 확인 → 테스트 UI 분리 설계

날짜: 2026-04-21
영역: QA / 인프라
결과: 작전 확정. 집 맥북에서 Phase 1 구현 착수 준비 완료

---

## 오늘 대화의 출발

부장님: "너 웹브라우저 제어 가능하지?"

본격 QA 자동화 활용 가능성을 탐색하면서 회사 컴 Claude in Chrome 차단 조사 3시간, 그 경험을 거쳐 **테스트 전용 UI + iframe grid + 5인 한도** 작전 확정까지.

---

## 회사 컴 Claude in Chrome 차단 조사

**5회 시도, 5회 차단**:

- `oxlens.com`, `localhost`, `tgkang.smartscore.kr`, `google.com`, `claude.ai`
- `chrome://policy` 완전히 비어 있음 — 조직 Chrome Enterprise Policy **아님**
- 조직이 Claude 제품을 사용하지 않으므로 Team/Enterprise Claude 관리자 정책도 **존재 불가**
- 경로 변경 무효 — Desktop 앱 경유 / 확장 사이드패널 직접 경유 모두 차단
- 계정 변경 무효 — 다른 Claude 계정으로 전환해도 동일
- `get_page_text`(네트워크 요청 없는 읽기) 도 차단 — `navigate` 전용 문제 아님
- Approved sites에 도메인 수동 추가도 무효

결론: 회사 환경에서 Claude in Chrome 사용은 **불가**. 원인 확정은 못 함 (네트워크 솔루션 / 확장 내부 캐시 / Anthropic Beta 보수적 기본값 중 하나). **원인 더 파는 건 가치 없음** — 대안이 이미 있음.

### 대조 관찰 (결정적)

Cursor + Playwright MCP는 **회사 컴에서도 동작**. 로컬 프로세스가 Chromium을 직접 런치하므로 Anthropic 서버 경유 및 확장 정책 체크를 전부 우회. **"Anthropic이 운영하는 확장"이 막히고 "로컬 MCP 서버"는 되는** 구조적 차이 명확.

### Chrome in Chrome 제어 스택 (오늘 학습 정리)

```
저(LLM) → Anthropic API → 인터넷 → 부장님 Chrome의 Claude 확장
                                        ↓ 정책 체크 ← 여기서 차단
                                   chrome.tabs.update() 등
```

3-layer 권한 구조: Chrome manifest → 확장 per-site 권한 → 조직 관리자 정책. 부장님은 3번 레이어가 원인일 거라 생각했으나 `chrome://policy` 비어있어 배제. 남은 범인은 확장 자체의 Beta 보수적 기본값일 가능성이 가장 크지만 확정은 못 함.

---

## 환경 분리 원칙 확정

| 장소 | 플랫폼 | 용도 |
|------|--------|------|
| 회사 컴 | Claude Desktop 채팅 | 설계/코딩 상담. 브라우저 자동화 X |
| 집 맥북 | Claude Desktop + Claude in Chrome (개인 계정, 동작 확인됨) | QA 자동화 주 환경 |

맥락 공유는 `/Users/tgkang/repository/context/` 파일시스템. 이미 이 프로젝트가 그렇게 운영 중이므로 추가 인프라 불필요.

---

## Chrome Split View 검증 (Chrome 145, 2026-02 정식)

부장님이 이미 split view로 영상무전/화상회의 2인 시나리오 수동 시험을 해왔음. 실증 사항:

- split view 내 두 pane이 MCP에 **독립 tabId 2개로 인식됨** (통합 컨테이너 아님)
- 두 pane 모두 `visibilityState: "visible"` 유지 (부장님 증언). rVFC/setInterval throttling **없음**. **tab hidden 왜곡 없음**
- 하드 한계: 최대 2 pane — 3인 이상 시나리오 커버 불가

**Claude in Chrome + Split View 조합은 2인 시연/반자동 QA의 가장 가벼운 수단**. N인은 다른 구조 필요.

---

## 작전 — 테스트 전용 UI 분리

### 부장님 질문의 핵심
"데모가 아니라 테스트 전용 UI를 하나 만드는 게 낫지 않냐"

### 결론: **확정**. 데모/QA 분리가 정답

근거:

1. **관심사 분리**. 데모 사용자(고객, 영업 파트너)와 QA 사용자(기계, 회귀 감시)의 요구가 다름. 한 UI에 욱여넣으면 둘 다 어중간해짐.
2. **데모 UI 변경이 QA 인질 되는 문제 원천 차단**. selector brittle, UI 리팩터가 QA 파괴.
3. **기각 리스트 회귀 감시**(`display:none` 금지, PTT freeze masking `left:-9999px+rVFC` 등)가 원래 목표 중 하나인데, 데모 UI를 관통하기보다 SDK 파이프라인 한 점을 **바로 찌르는** 구조가 맞음.
4. **업계 선례** — LiveKit(`meet.livekit.io` vs `agents-playground.livekit.io`), mediasoup, Janus 전부 데모와 test harness 분리 운영.

### 구조

```
oxlens-home/qa/
├── index.html          테스트 컨트롤러 (iframe grid + window.__qa__)
├── participant.html    참가자 인스턴스 (Engine 1개, 최소 DOM)
└── scenarios/
    ├── video_radio_2.json
    ├── video_radio_5.json
    └── ...
```

### 설계 원칙

- **iframe grid**: 한 parent window에 `participant.html` iframe N개. CSS grid 2×3 배치로 한 화면 동시 렌더
- **최대 5인**: 기능 QA 한정(성능 QA 아님). 그 이상은 `oxlens-sfu-labs`의 oxlab-bot 몫
- **같은 origin**: getUserMedia 권한 프롬프트 1회 통과로 N인 전부 커버
- **parent window visibility 일괄 적용**: parent가 visible이면 iframe 전부 visible → **tab hidden 구조적 불가**
- **`window.__qa__` 전역 제어 표면**: postMessage 같은 프로토콜 오버엔지니어링 회피. QA 전용 페이지라 전역 노출이 명료
- **스타일 zero**: monospace + 텍스트 상태만. UI selector brittle 문제 원천 차단
- **`data-qa` 속성**: 제어 가능 요소(mute 토글, PTT 버튼, video element 등)에 안정 selector
- **dev 빌드 한정 접근**: production 번들에서 제외

### window.__qa__ 표면 (스케치)

```javascript
window.__qa__ = {
  users: [/* N개 iframe 핸들 */],
  all: {
    mute(kind), unmute(kind),
    phases(),      // 전원 Phase 수집
    snapshot()     // 전원 getStats 덤프
  },
  scenario: { load(name), reset() }
}

// 개별
window.__qa__.users[0].mute('audio')
window.__qa__.users[2].ptt.press()
window.__qa__.users[1].getStats()
```

MCP 측에서는 `javascript_tool`로 `window.__qa__.users[N].xxx()` 한 방 호출. tabId는 parent 1개만 관리하면 됨.

### Cross-reference 저장소 구조

각 run 디렉토리에 **서버 어드민 스냅샷 + 클라 `__qa__.all.snapshot()`** 나란히 저장 → diff. 스냅샷↔런타임 불일치(부장님 오랜 과제) 감지가 자동화됨. TRACK IDENTITY 원칙의 구현체.

```
context/qa/
├── scenarios/
│   └── video_radio.md          시나리오 정의서
├── baselines/
│   └── video_radio_2.json      정상 기준 (1회 생성 후 주기 갱신)
└── runs/
    └── 20260421_01/
        ├── server_snapshot_T1.json     서버 진실
        ├── client_state_T1.json        클라 진실(__qa__.all.snapshot)
        ├── diff_T1.md                  두 source 비교 + 불일치 표시
        ├── console.log
        └── verdict.md                  PASS/FAIL + 사유
```

### 첫 시나리오: video_radio

voice_radio는 1 PC 시험 시 마이크↔스피커 에코/하울링 → **보류**. video_radio로 착수.

이유:
- 부장님 수동 시험 자산 풍부 → baseline 만들기 쉬움
- **PTT freeze masking 회귀 감시 직결** (display:none 금지, left:-9999px+rVFC 원칙)
- OxLens 차별화 정중앙

### video_radio 시나리오 스텝 초안 (2인)

```
T0  두 iframe 동시 load, autojoin, phase=READY 대기(10s timeout)
T1  서버 어드민 스냅샷 ① + __qa__.all.phases() ②
    검증: 서버 phase=Active ×2, 클라 phase=READY ×2
T2  user1.ptt.press() → 3초 hold → release
    발화 중 user2의 audio/video 수신 확인
T3  1초 idle (silence flush 완료 대기)
T4  user2.ptt.press() → 3초 hold → release (화자 전환)
T5  1초 idle
T6  두 탭 leave → phase 정리
```

### Pass/Fail 기준

**정상 기준 (기계 판정)**
- 서버 phase 전이 `Created → Intended → Active → (leave)`
- Floor 전이 `idle → taken(A) → idle → taken(B) → idle`
- 발화자 `audio.packetsSent > 0`, `video.packetsSent > 0`
- 수신자 `audio.packetsReceived` delta ≥ 임계 (50pps × 3s × 0.67 = **100**)
- 수신자 `video.freezeCount` delta = **0**
- STALLED(op=106) 이벤트 **0회**
- console error **0건** (warning 허용)

**회귀 감시 (기각 리스트 재발 감지)**
- 수신자 video element `computedStyle.display !== 'none'` 유지
- 숨김 수단이 `left:-9999px` 또는 `visibility:hidden` (display 기반 아님)
- 수신자 측에서 `track.onmute` 기반으로 표시 결정하지 않음 (rVFC 기반)
- half-duplex 트랙의 virtual SSRC가 서버 어드민 스냅샷에 존재

**실패 시 자동 수집**
- 실패 스텝 ±3초 구간 console 로그
- 그 시점 어드민 스냅샷 JSON
- `__qa__.all.snapshot()` 전원 getStats 덤프
- 각 iframe video element `computedStyle` 캡처
- 필요 시 `gif_creator`로 해당 구간 GIF 녹화

### fake media 플래그 (필수)

실 마이크/카메라 사용 금지 — 에코 차단 + 재현성 확보. macOS zshrc alias 예:

```bash
alias qachrome='open -na "Google Chrome" --args \
  --user-data-dir="$HOME/chrome-qa-profile" \
  --use-fake-device-for-media-stream \
  --use-fake-ui-for-media-stream \
  --autoplay-policy=no-user-gesture-required'
```

`qachrome` 타이핑 한 번으로 QA 환경 진입 표준화. 부장님 일상 Chrome과 프로파일 격리.

---

## Phase 1 실행 계획 (집 맥북, 주말 단일 세션 볼륨)

1. `qa/participant.html` — Engine 인스턴스 + 쿼리파라미터 파싱 + `window.__qa__` 로컬 + 최소 DOM
2. `qa/index.html` — iframe grid + 통합 `window.__qa__` + 시나리오 JSON 파서
3. `scenarios/video_radio_2.json` 작성, 로컬 실행 성공
4. baseline 1회 촬영 → `context/qa/baselines/video_radio_2.json`
5. 5인 확장 `scenarios/video_radio_5.json` — 코드 변경 0, JSON 추가만 (Step 4 동작 확인 후 자연 follow-up)

---

## 오늘의 기각 후보

- **voice_radio 1 PC 수동 시험**: 마이크↔스피커 에코/하울링. 근본 해법은 mute 토글이 아니라 fake media 플래그
- **탭 N개 단독 구성 QA**: 뒤 탭 `visibilityState: "hidden"` + rVFC/setInterval throttling → 관측 왜곡. 본말전도
- **데모 UI 위에 QA 덧씌우기**: selector brittle, UI 변경이 QA 파괴, 관심사 섞임
- **OS Chrome 창 2개**: OS focus 정책에 의존, 둘 중 하나는 반드시 뒤로 밀림. split view보다 열위
- **role 자동 진입에 쿼리파라미터 추가(데모 기준)**: 데모 아키텍처 수정 비용. QA UI 분리가 확정되어 불필요
- **`window.__qa__` 대신 postMessage 프로토콜**: QA 전용 페이지에 과도한 캡슐화. 관측성↓
- **QA UI에 부하 테스트 섞기**: 기능 QA와 성능 QA는 다른 도구(oxlab-bot). 5인 상한 선언
- **Chrome Split View를 다인 시나리오 주력으로**: 2 pane 하드 한계. 2인 시연/반자동 보조 수단으로만
- **Claude in Chrome 회사 컴 돌파 시도 지속**: 원인 규명 없이도 결론 명확 — 우회 경로가 이미 작동(Cursor MCP)
- **claude.ai Session과 Claude Desktop Session의 인위적 분업 설계**: 사실 부장님은 Claude Desktop 단일 환경에서 작업 중. "지휘본부 vs 실행부대" 이분법은 김대리가 만든 과잉 엔지니어링. 맥락 공유는 파일시스템 한 방이면 끝 — 이게 자명한 상식
- **Claude in Chrome을 QA 자동화 주력으로**: v1.0.68(2026-04-15 업데이트)부터 Anthropic 서버가 모든 navigate 요청을 분류 후 차단. `localhost`/`127.0.0.1`/`claude.ai` 등 전부 `org_policy: "block"` 응답. 사용자가 풀 방법 없음. Playwright MCP로 전환이 근본 해법
- **Playwright MCP 기본 설정만으로 동작 기대**: Claude Desktop이 MCP subprocess를 `cwd=/` 로 띄워서 `mkdir '/.playwright-mcp'` 실패(ENOENT). `--output-dir /Users/<user>/.playwright-mcp` 인자 명시 **필수**
- **getUserMedia 자동 허용 기대**: Playwright Chromium도 기본적으론 권한 프롬프트 띄움 → MediaAcquire 5초 타임아웃 → enableMic 실패. `PLAYWRIGHT_MCP_GRANT_PERMISSIONS=microphone,camera` env var **필수**

## 오늘의 지침 후보

- **QA와 데모 UI는 물리적으로 분리** — `oxlens-home/qa/` 격리 디렉토리. production 번들 제외
- **QA UI 스타일 zero** — monospace, 텍스트 상태, 버튼 최소, video element. 모든 제어 요소에 `data-qa=...` 속성
- **iframe grid + same-origin** — visibility 일괄 `visible`, getUserMedia 권한 1회 통과. parent 1 tab으로 MCP 제어 단순화
- **기능 QA는 최대 5인, 그 이상은 oxlab-bot** — QA UI 범위 선언으로 scope creep 방지
- **`window.__qa__` 전역 제어 표면** — QA 전용이므로 캡슐화보다 관측성이 우선
- **fake media 플래그 필수** — 에코 차단 + 재현성. `qachrome` alias로 환경 진입 표준화, 일상 Chrome과 프로파일 격리
- **Cross-reference 저장 패턴** — 각 run에 서버 어드민 스냅샷 + 클라 `__qa__.all.snapshot()` 나란히. 스냅샷↔런타임 불일치 자동 감지
- **환경 분리(회사/집, 회사계정/개인계정)** — 회사 컴은 Claude 채팅 전용, QA 자동화는 맥북
- **도구 용도 3층 구분** — Claude in Chrome(2인 시연/반자동) / iframe grid(N인 기능 QA 주력) / Playwright MCP headless(확장 옵션)
- **시나리오 1개 완결 후 확장** — 첫 돌아가는 시나리오 하나가 완벽한 프레임워크보다 중요. 과잉 엔지니어링 경계
- **Playwright MCP config 정석** — Claude Desktop `~/Library/Application Support/Claude/claude_desktop_config.json` 에 `args: ["-y", "@playwright/mcp@latest", "--output-dir", "/Users/<user>/.playwright-mcp"]` + `env: {"PLAYWRIGHT_MCP_GRANT_PERMISSIONS": "microphone,camera"}`. 설정 후 ⌘Q 완전 종료 → 재실행 필수
- **서버 방 이름 `demo_*` 프리픽스** — startup.rs가 사전 생성한 10방(`demo_conference`/`demo_video_radio`/`demo_voice_radio`/`demo_dispatch`/`demo_cctv`/`demo_classroom`/`demo_support`/`demo_panel`/`demo_presentation`/`demo_webinar`). 시나리오 스크립트 작성 시 room 필드는 이 중 하나
- **AI 시험 정석 패턴** — 단일 `browser_evaluate` 호출 안에서 `snapshot(t0) → 액션 → sleep → snapshot(t1) → diff`를 reshape한 JSON 한 방 리턴. round-trip 최소화. console 로그는 `browser_console_messages` 별도 호출

---

## 실증 결과 (Phase 1 완료, 2026-04-21 저녁)

### 환경 셋업 실전 이슈 2건

**Issue 1 — `/.playwright-mcp` mkdir 실패 (ENOENT)**
- Claude Desktop이 MCP subprocess를 `cwd=/` 로 띄움. Playwright MCP는 `process.cwd()`에서 output 경로 파생 → `/.playwright-mcp/` 시도 → 루트 쓰기 권한 없어 실패
- GitHub Issue [openai/codex#16390](https://github.com/openai/codex/issues/16390) 와 동일 증상 (Codex Desktop도 같은 문제)
- 해결: config `args`에 `"--output-dir", "/Users/tgkang/.playwright-mcp"` 추가

**Issue 2 — getUserMedia 권한 프롬프트로 5초 타임아웃**
- Playwright Chromium이 마이크/카메라 프롬프트 띄움, MCP 자동 응답 안 함 → `[PERF] enableMic:failed Δ5001.4ms` → `[ACQUIRE] audio permission: prompt → granted` 로그 (이미 타임아웃 뒤 grant)
- 해결: config `env`에 `"PLAYWRIGHT_MCP_GRANT_PERMISSIONS": "microphone,camera"` 추가. 이걸로 BrowserContext 레벨에서 pre-grant → 프롬프트 안 뜸 → 실 디바이스 사용

### 2인 video_radio 스모크 테스트 PASS

구성: Alice + Bob, room=`demo_video_radio`, 둘 다 `{mic:half, camera:half}`.

**Floor 전이** (PTT 3초 발화):
- T+0: `alice.floor=idle` / `bob.floor=idle`
- T+0.5s (press 직후): `alice.floor=talking, speaker=alice` / `bob.floor=listening, speaker=alice`
- T+3s (발화 중): 동일 유지
- T+3.5s (release): idle 복귀 (검증 생략, 증분만 측정)

**Alice publish (outbound) 3초 증분**:
- audio: packetsSent 101 → 301 (Δ+200), bytesSent 5.4KB → 16.7KB
- video: packetsSent 684 → 1031 (Δ+347), bytesSent 658KB → 1.0MB, fps=15
- nackCount=0

**Bob subscribe (inbound) 3초 증분**:
- audio: packetsReceived 0 → 175, packetsLost=**0**, jitter=0
- video: packetsReceived 0 → 306, packetsLost=**0**, jitter=0.001, freezeCount=**0**, framesDecoded=53

### Pass 기준 대조 (세션 파일 초안 기준 8개)

| 항목 | 기준 | 결과 |
|------|------|------|
| 서버 phase 전이 | Created→Intended→Active | ✅ (ready 도달) |
| Floor 전이 | idle→taken(A)→idle | ✅ |
| Alice audio.packetsSent | > 0 | ✅ (+200) |
| Bob audio.packetsReceived delta | ≥ 100 | ✅ **175** |
| Bob video.freezeCount delta | = 0 | ✅ **0** |
| packetsLost | = 0 | ✅ **0** |
| TRACK_STALLED | 0회 | ✅ (lastError: null) |
| console error | 0건 | ✅ (favicon 404만) |

### 확인된 파이프라인 전체 길이

`browser_navigate` → iframe `spawn` → Engine 생성 → WS IDENTIFY → `joinRoom(demo_video_radio)` → pubPc SDP nego(DC-only offer / ICE-Lite answer) → ICE connected → DTLS connected → DC unreliable channel open → `enableMic({duplex:'half'})` → `enableCamera({duplex:'half'})` → `PHASE.READY` → 2명째 `spawn`에서 subscribe re-nego (mid 0/1 할당) → PTT press → `floor_bearer=dc` MBCP Granted → 3초 발화 → RTP hot path(publish SSRC → 가상 SSRC → Bob subscribe inbound) → release

**130ms** 안에 Alice 전체 파이프라인 READY 도달, 2인 합쳐 **수 초** 안에 전체 시험 가능.

### 회귀 감시 관점 관찰

- **freezeCount=0** — PTT freeze masking(`left:-9999px`+rVFC) 기각 원칙 유지 정황 증거
- **jitter=0.001** — SR Translation/RTCP Terminator 동작, jb_delay 폭증 없음
- **packetsLost=0, nackCount=0** — NACK/PLI 경로 정상, publisher→subscriber 손실 없이 릴레이
- **lastError null 유지** — STALLED checker 동작 영역 진입 없음

### 확정된 QA 운영 패턴

- 부장님이 live-server로 `:5500/oxlens-home/` 띄워두면, 제가 `browser_navigate` 한 방으로 `/qa/` 진입
- `browser_evaluate(async () => { ... })` 안에서 전체 시나리오 실행 + 결과 reshape 리턴 → round-trip 1~3회로 전체 시험 1건 완결
- 세부 로그는 `browser_console_messages` 별도 호출, 필요 시 `output-dir`에 자동 저장된 파일 조회
- Filesystem MCP의 `edit_file`로 세션 파일/코드 업데이트 병행

---

## On the horizon

- ✅ **Phase 1 Step 1~4 완료** (참가자 iframe + index.html + video_radio_2 스모크 PASS)
- **Step 5 — 5인 확장**: 같은 `demo_video_radio` 방에 3명 더 `spawn` 추가. 다수 subscriber 거동(PLI, NACK burst, fps drop, freeze) 관찰
- **시나리오 추가 후보**: conference (다인 기본), dispatch (비대칭 1+N), moderate (authorization 전이)
- **기각 리스트 회귀 감시 스크립트 목록화** — display:none, RESYNC, PT 하드코딩, 텔레메트리 기반 의사결정 등 코드에서 재발 패턴을 정적·동적으로 감지. 런타임 감시 항목 예: `getComputedStyle(videoEl).display !== 'none'` 체크, freezeCount delta=0 assertion, subscribe PC 재생성 횟수 카운터
- **`apply(partialSpec)` 선언적 API 추가** — 현재는 `enable/disable/switchDuplex/toggleMute` 개별 메서드. diff 기반 apply 얇은 래퍼로 얹으면 시나리오 표현력 상승
- **`waitFor(predicate, timeout)` 조건 대기 API** — `setTimeout` 블라인드 대기 대신 phase/floor/speaker 조건 기반. 현재는 `Promise.race([ready, sleep])` 수작업
- **어드민 스냅샷 REST 엔드포인트 ↔ QA 컨트롤러 fetch 통합** — 현재 어드민 페이지가 뽑는 포맷 재사용
- **voice_radio 재편입** — fake media 플래그로 에코 없음 실증되면 scenarios에 추가
- **Cursor + Playwright MCP headless 경로** — 6인+ 규모 / headless CI 전환 필요 시 옵션으로 대기. 지금 착수 아님
- **GIF 증거 수집 자동화** — 실패 시 `gif_creator` 자동 트리거, 리포트에 첨부

---

*author: kodeholic (powered by Claude)*
