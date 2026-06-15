// author: kodeholic (powered by Claude)
# 스마트 글래스 시장 조사 + BYOD 전략 정리 (2026-06-14)

> **세션 성격**: 코딩/서버 작업 아님. 시장 조사(web search) + 부장님과 전략 토론.
> 출처는 전부 웹 검색(2026-06-14 시점). 본 문서는 *조사로 확보한 사실* + *도출된 전략 결론* 단일 기록.
> 트리거: 부장님 "스마트 글래스 자료 조사. 기능 위주로" → 영상 송출 사례/원조 → 입력 방식(제스처) → 개방성 → 전략 수렴.

---

## §1. 조사 지식 (사실 위주)

### 1.1 시장 3+1 분할 (기능 축이 다름)

| 축 | 핵심 기능 | 대표 | 가격대 |
|---|---|---|---|
| AI 오디오 글래스 | 카메라·음성비서·실시간 통역, **디스플레이 없음** | Ray-Ban Meta Gen2 | ~$379 |
| 디스플레이/HUD | 인-렌즈 화면(내비·자막·메시지) | Meta Ray-Ban Display, Even Realities G2 | $599~$799 |
| XR 디스플레이 | 대화면 가상 모니터(미디어/게임) | XREAL One Pro, Viture Beast | $449~$599 |
| **산업용 assisted-reality** | **핸즈프리 음성제어 + 원격지원 영상스트리밍** | **RealWear Navigator 520, Vuzix M400/LX1** | €2,400+ |

- 소비자 축 수렴 방향 = **AI 비서 + 실시간 통역 + 알림 표시**. Google(2026 가을, Gemini), Apple(2026, AR 없이 카메라+AI)도 같은 방향.
- 빅테크(Apple/Meta/Microsoft)는 **엔터프라이즈 XR 하드웨어에서 손 뗌** → 그 자리를 Vuzix/RealWear 같은 "이 일을 위해 만들어진" 벤더가 채움.

### 1.2 산업용 라인 사양 (우리 타겟과 직결)

- **RealWear Navigator 520**: Android(Snapdragon 660). HyperDisplay 1280×720, 48MP 카메라(OIS, 1080p 60fps 송출), 음성제어(100dBA 소음에서도 인식, 12+ 언어), IP66 + MIL-STD-810H + **ATEX Zone 1(방폭)**, 핫스왑 배터리, FLIR 열화상 모듈 교체.
- **Vuzix(2026-02)**: `Remote Assist by Vuzix Solutions` 출시 — **MS Teams·Zoom을 글래스 폼팩터에 맞춰 네이티브 재구성**. "기존 화상협업 플랫폼은 폰/PC용 설계라 헤드마운트에선 성능·사용성 저하" → 그 갭을 핸즈프리 제어로 메움. **(시사점: 범용 화상스택을 글래스에 그대로 못 얹는다는 걸 시장이 인정)**
- 기능 철학 = **양손 자유 + 시선 유지**: 라이브 영상 가이드 + 디지털 작업지시를 시선 안에서, 양손은 작업에.

### 1.3 영상 송출 — 역사/원조 계보 (중요)

**영상 송출 원격지원의 "원조"는 글래스 벤더가 아니라 SW 벤더다.**

| 시점 | 주체 | 의미 |
|---|---|---|
| ~2007 | **Librestream (Onsight)** | 산업용 원격 전문가 비디오의 **진짜 원조**(120개국 배포). 처음엔 핸드헬드/헤드마운트 카메라 |
| 2013 | Google Glass | 글래스 폼팩터 등장(소비자 실패→엔터프라이즈 피벗) |
| 2014 | **Ericsson WebRTC PoC** | 글래스 + **WebRTC** 원격지원 최초 사례(WebRTC+WebGL+NodeJS) |
| 2014 | ClickSoftware+FieldBit, Looxcie Vidcie | 필드서비스 라이브 송출 상용 데모 |
| 2016 | Vuzix M300 + XOEye | 산업용 글래스 전용 비디오 협업 SW |
| 2017 | RealWear HMT-1 | 하드햇 폼팩터 assisted-reality 시작 |
| 2020~21 | Vuzix+Librestream, Google Glass EE2 | COVID 의료 원격지원(수술/간호 트레이닝 라이브) 확산 |

- **Ericsson 2014 교훈(우리와 직결)**: Glass 프로세서가 약해 영상 어노테이션을 인근 기기로 오프로드, 정지 이미지 위주로. → **무거운 처리는 서버(SFU)로 밀어야 한다**는 게 10년 전 증명. 우리 dumb-SFU 철학과 정합.
- **Librestream Onsight 전송 특성**: 최소 **30kbps 초저대역폭**에서 동작 + 오프라인 모드 + 위성/셀룰러 강조. → **WebRTC가 아닌 자체 코덱/대역폭 튜닝 공산이 큼**(미검증). 양날: 초저대역폭은 우리(브라우저 WebRTC)가 불리한 영역.

### 1.4 PTT 인접 지형 (경쟁/레퍼런스)

- **Zello**: iOS/Android/React Native **Mobile SDK로 PTT 임베드** + 라디오 게이트웨이로 LMR 브릿지. → SDK 임베드 모델이 우리와 가장 유사한 경쟁.
- **MS Teams Walkie Talkie**: 전용 PTT 버튼 헤드셋 연동, Wi-Fi/셀룰러.
- **weavix Walt / RingCentral / Zoom Phone PTT**: 멀티미디어 PTT + AI 통역/전사로 확장.
- **공통 관찰**: 전부 "전용 앱 + 셀룰러/Wi-Fi" 모델. **브라우저 기반 WebRTC PTT는 안 보임.** PTT 본질 = half-duplex(한 번에 한 명 송신).

### 1.5 입력 방식 — 제스처(밴드/링) 동향

- **Meta Neural Band**: sEMG(표면근전도)로 팔뚝 근육 미세 전기신호 감지 → 핀치/스와이프/손목회전. 광학 핸드트래킹이 못하는 것 + 햅틱. IPX7, 18h.
- **Mudra Link**: 손목 EMG 신경밴드, cross-platform 제스처 매핑(AR/VR·생산성).
- **Oura**: 제스처 스타트업 **Doublepoint 인수**(2026)로 스마트링에 제스처 통합.
- **산업용 EMG 암밴드**: IP67, **<20ms 레이턴시**, 1000Hz 샘플링 스펙화. Apple Ring 루머(2026). J-Style JCRing X5 "산업용 핸즈프리 제어" 명시.
- **확인된 한계**: 이들 전부 **범용 UI/헬스/생산성** 타겟. **"PTT floor invoke 전용으로 글래스+제스처 통합"한 사례는 아직 없음.** = 빈 자리.

### 1.6 ★ 디바이스 서드파티 개방 — Meta가 열었다 (2026-05-14, 핵심)

**가장 닫혀 있던 Meta Ray-Ban Display가 서드파티 개발자에게 개방됨.** "Meta 전용 경험 → 플랫폼" 전환.

- **두 경로** (Meta Wearables Device Access Toolkit):
  1. **네이티브 SDK** — iOS(Swift)/Android(Kotlin). 기존 모바일 앱을 글래스 디스플레이로 확장. camera/audio/display 하드웨어 접근("no other AI glasses SDK can match" 수준).
  2. **Web Apps** — **HTML/CSS/JS로 독립 경험, 앱스토어 없이 표준 URL 배포.** ★★★ 우리 브라우저 WebRTC 베팅과 정확히 맞물리는 경로.
- **Neural Band 제스처도 개방** — 서드파티가 sEMG 제스처 입력 수신 가능.
- **Meta가 직접 든 use case에 "field-service 앱(작업지시·체크리스트·확인 프롬프트)" 포함** — 우리 타겟 도메인.
- **단계**: 현재 developer preview, select 파트너만 일반 배포, **broader 개방은 2026 중 예정** (= "조금씩 열린다"가 정확).
- **Android XR SDK 1.0 GA** — Google도 개방 플랫폼. 개방 경쟁 시작.

- **디바이스 개방성 지형** (BYOD 가능 여부):
  - 열림(우리 진입 가능): **Android 기반 글래스(브라우저/APK), 표준 BT/HID PTT 액세서리, cross-platform 밴드(Mudra)**
  - 닫힘→**열리는 중**: Meta(2026-05 개방), Apple(미확인)

---

## §2. 전략 결론 (부장님과 도출)

1. **민주화 패턴 (특수→일반)**: 험한 직업이라 전용 장비로 쓰던 패러다임(핸즈프리·1인칭 영상·즉시 음성연결)이 자연스러운 폼팩터(글래스)를 만나 일반인 손으로 흘러내림. GPS·GoPro·PTT의 반복 패턴.
2. **B2C 직접 진입은 함정**: 일반인 글래스 위 범용 영상/PTT는 Meta(WhatsApp)·Google(Meet)이 공짜 기본탑재. 인프라 회사가 B2C에서 빅테크와 정면승부 = 자살.
3. **곡괭이 포지션 = 정답**: 패러다임 일반화 → 글래스 위에 자기 PTT/영상 서비스 얹으려는 *사업자* 폭증 → **그들에게 SFU+SDK 판매**. 금 캐지 말고 곡괭이/청바지 팔기.
4. **BYOD + 하드웨어 불가지**: "안경/링/밴드 안 만들지만, 네가 이미 가진 디바이스에 산업 특화 기능 얹어준다." 디바이스 레벨에선 **특수업=일반인 경계 소멸**(같은 글래스, 위에 까는 SW만 다름). 빅테크가 하드웨어 보급할수록 우리 단말이 공짜로 깔림.
5. **"제조사 아님 = 약점→자산" 재구성** ★: 제조사였어도 하드웨어 시장(빅테크 보조금 레드오션)은 못 뚫음. SW 인프라 = CAPEX≈0, 마진高, N단말 복제. **개방이 일어난 지금 "제조 안 함"은 유일하게 올바른 포지션.**
6. **개방은 대칭적 = 경쟁 격화** ★: 장벽이 나한테 열린 만큼 모두에게 열림. 하드웨어 장벽 사라진 자리 = **"구현 품질"이라는 새 장벽**. 우리 해자 = **기술 깊이**(floor FSM, RTCP Terminator, 크로스-SFU, dumb-SFU 위 PTT gating). "PTT 됩니다"는 Zello도 줌. 아무나 못 주는 건 *제대로 동작하는 깊은 미디어 엔진*. 1년의 깊이가 그래서 무기.
7. **track-level duplex 차별점** ★: 한 사용자 안 audio=half(무전)+video=full(상시)을 **엔진이 트랙 단위 네이티브 처리**. 업계는 full-duplex 전제(화상회의) 또는 half 음성 전제(PTT 전용) — 둘 다 트랙별 혼합을 엔진 1등시민으로 안 다룸. app 레이어 mute 흉내 = "유저공간 폴링으로 인터럽트 흉내". 빠른 floor 전환·다자·크로스룸에서 폴링은 무너지고 우리 커널 네이티브는 안 무너짐. **표면 복제는 누구나(데모 레벨), 상용 품질·규모에선 우리 해자.**
8. **글래스 폼팩터가 혼합 듀플렉스 수요를 구조적으로 키움** ★: 글래스=1인칭 카메라+핸즈프리 음성 → 자연 모드 = "카메라 상시 송출(full) + 음성 무전 규율(half)" = 우리 `field` 프리셋. 폰/PC 시대엔 어색했던 조합이 글래스에선 **기본값**. → 수요 풀 확대 근거는 희망이 아니라 폼팩터 구조.
9. **브라우저 WebRTC 선택과 Meta Web Apps 개방의 합류** (조건부): 네이티브 SDK로 갔으면 글래스마다 재작성. 브라우저로 갔으니 Meta든 Android XR이든 *같은 URL 하나*가 돎. **단 Web Apps가 WebRTC 풀스택 도는지 미검증** → 합류 완성은 그 검증에 달림.

---

## §3. 미검증 / 다음 액션 (우선순위)

1. ★ **글래스 Web Apps가 WebRTC 풀스택 지원하나** — `getUserMedia`/`RTCPeerConnection` + **카메라 송출 권한**. Meta Web Apps 경로 + Android XR 글래스 WebView 양쪽. **이 한 가지가 "스마트 글래스=OxLens 단말" 검토의 결론을 가름.** yes면 부장님 비전 전체(BYOD+브라우저+제스처+민주화)가 기술적으로 배선 가능.
2. Librestream Onsight 실제 전송 프로토콜(WebRTC 여부 / 자체 초저대역폭). 우리가 *못 가는* 영역 경계 확정.
3. RealWear/Vuzix Android에서 **BT/HID PTT 버튼·제스처 밴드 이벤트를 앱이 받는지**(floor invoke 인터페이스 개방성). 막히면 IRQ 라인 끊김.
4. Meta broader 개방 시점 + Apple 개방 정책(BYOD TAM 좌우).

---

## §4. 오늘의 기각 후보

- **B2C 일반인용 글래스 앱 직접 개발** — 빅테크 영토. 인프라 회사가 들어가면 죽음. (곡괭이 포지션으로 우회)
- **제스처 PTT 선제 베팅(과투자)** — BT 버튼/RSM 액세서리가 이미 floor invoke를 즉각·핸즈프리·소음무관·음성미오염으로 해결. 제스처가 *추가로* 이기는 시나리오를 못 대면 over-engineering. 입력 불가지 설계로 흡수만 하고, 제스처 자체 개발/베팅은 보류.
- **"어떤 글래스든 연동" 단정** — *열린* 단말만(Android/개방 BT/Mudra). 닫힌 단말(개방 전 Meta/Apple)은 보급돼도 못 들어감. "열린 글래스/밴드면 연동"으로 보정.
- **Librestream식 초저대역폭(30kbps/위성) 영역 진입** — 우리 WebRTC 불리. 그들의 영역은 피하고 Wi-Fi/5G 보장 환경의 다자 PTT+영상(우리 강점)에 집중.
- **하드웨어(글래스/링/밴드) 자체 제조** — 빅테크 보조금 레드오션. "제조 안 함"이 자산.

## §5. 오늘의 지침 후보

- **포지셔닝 문장 확정**: "화상회의+PTT 합칩니다"(누구나 흉내) ✗ → **"트랙 단위 듀플렉스 엔진 네이티브 — 영상 상시 송출 중 음성 무전이 빠른 전환·다자에서 음질 안 깨진다"** ○. *글래스 원격지원의 디폴트 모드가 정확히 이것*이라는 점이 힘을 실음.
- **타겟 세그먼트 정조준**: 차별점이 값받는 곳 = **품질·규모 critical(공공안전·디스패치·산업 원격지원)**. 가벼운 일반 유즈는 app 레이어로 만족할 수 있어 우리 깊이 불필요.
- **곡괭이 포지션 유지**: B2B SFU+SDK(PROJECT_MASTER "시장 축소 금지, 광범위 상용 인프라"와 정합). 민주화는 이 전략을 부정이 아니라 *강화*.
- **선점 시간 싸움**: 빅테크가 PTT 규율을 1등시민으로 넣을 동기는 약하나(니치) 영원하지 않음. 깊이+선점으로 그 공백 굳히기.

---

## §6. 출처 (web search, 2026-06-14)

- 시장 개관: treeview.studio/blog/best-smart-glasses, glassalmanac.com, visionxo.com
- 산업용: vuzix.com/pages/remote-assist, realwear.com/devices/navigator-520, vr.org(big-tech-quit-enterprise-xr), vsight.io
- 영상송출 역사: ericsson.com(field-service-google-glass-webrtc 2014), librestream.com, prnewswire(vuzix-librestream telehealth), forrester(google-glass-enterprise)
- PTT 인접: zello.com, weavix.com, learn.microsoft.com(walkie-talkie), ringcentral.com
- 제스처: roadtovr.com(neural-band), mudra-band.com, pymnts.com(oura-doublepoint), accio.com(emg-armband)
- ★ Meta 개방: developers.meta.com/blog(build-for-display-glasses, 2026-05-14), developers.meta.com/wearables/faq, vr.org(meta-ray-ban-display-developer-sdk-2026), ghacks.net, roadtovr.com(device-access-toolkit)

---

**[보고]** 시리즈 결론: 부장님 전략 직관(민주화·BYOD·브라우저·제스처·track-duplex) 전부 시장 데이터와 동기화 확인. 최대 리스크(폐쇄성)는 Meta 개방(2026-05-14)으로 해소 중. 우리 승부처는 하드웨어 해자 → **기술 깊이 해자**로 이동(이미 보유). 전 전략이 단 하나의 미검증 기술 사실(글래스 Web Apps WebRTC 풀스택) 위에 섬 — 다음 세션 1순위.

*author: kodeholic (powered by Claude)*
