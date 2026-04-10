# 세션 컨텍스트: Simulcast 삽질기 블로그 시리즈 작성

- **날짜**: 2026-03-29
- **작업**: OxLens 기술 블로그 시리즈 3 "Simulcast 삽질기" 전 4편 초안 + 썸네일 작성

---

## 완료된 작업

### 시리즈 3: Simulcast 삽질기 (4편 완결) — ✅ 전편 Velog 게시 완료

| # | 제목 | 상태 | 썸네일 |
|---|------|------|--------|
| 1 | Simulcast란 — 왜 필요하고 뭐가 어려운가 | ✅ Velog 게시 완료 | ✓ |
| 2 | SSRC가 SDP에 없다고? — PT 하드코딩에서 RTP-First까지 | ✅ Velog 게시 완료 | ✓ |
| 3 | 가상 SSRC와 레이어 전환 — SimulcastRewriter의 세계 | ✅ Velog 게시 완료 | ✓ |
| 4 | 키프레임 전쟁 — SDP 타이밍, PLI 제어, inactive m-line | ✅ Velog 게시 완료 | ✓ |

### Velog 게시 정보
- **시리즈명**: Simulcast 삽질기
- **포인트 컬러**: indigo (#6366f1)
- **1편 태그**: Simulcast, WebRTC, SFU, 화상회의, 미디어 서버, Rust, 대역폭 최적화, 삽질기
- **2편 태그**: Simulcast, WebRTC, SFU, RTP, Payload Type, SSRC, rtp-stream-id, Rust, 삽질기
- **3편 태그**: Simulcast, WebRTC, SFU, SSRC, SimulcastRewriter, PLI, 키프레임, Chrome 버그, Rust, 삽질기
- **4편 태그**: Simulcast, WebRTC, SFU, 키프레임, PLI, SubscriberGate, SDP, mediasoup, Rust, 삽질기

### 초안 파일 위치
- `/Users/tgkang/repository/context/blog_s3_01_simulcast_intro.md`
- `/Users/tgkang/repository/context/blog_s3_02_pt_hardcoding_rtp_first.md`
- `/Users/tgkang/repository/context/blog_s3_03_virtual_ssrc_rewriter.md`
- `/Users/tgkang/repository/context/blog_s3_04_keyframe_war.md`

---

## 주요 결정 사항 및 학습

### 편수 결정
- 스킬 파일의 5편 구성 → 4편으로 축소
- 5편(Active Speaker 자동 전환)은 미구현 기능이라 삽질기 톤에 안 맞음
- "내용이 알차면 편수는 상관없다" 원칙 (S8에서 확립)

### 문체 통일
- 1편 초안이 "~입니다" 체(경어체)로 작성됨 → S2 톤("~다" 체, 평서형 단정)과 불일치
- 부장님 피드백으로 전편 "~다" 체로 통일
- **교훈**: 시리즈 간 톤 일관성이 중요. 이전 시리즈 문체를 반드시 확인 후 작성

### 2편 마무리 변경 — 열린 결말
- 원래: "배운 건 하나다" 단정 종결
- 변경: "아직 끝나지 않은 이야기" — 검증 진행 중임을 솔직히 밝히는 톤
- 부장님 표현: "온실속 화초를 바깥으로 꺼낸 단계"
- "따라했다가 안 된다고 비난받을 수 있다" → 방향은 맞지만 자기 환경 검증은 필수라고 명시

### 4편 전면 재작성 — 보편성 확보
- 초안: "우리 버그 → 우리 해결" 구조 → 부장님 피드백 "너무 우리 이야기만"
- 재작성: "보편적 문제 → 업계 접근 → 우리 선택" 구조로 전환
- 구체 변경:
  - SubscriberGate → "키프레임이 SDP보다 먼저 도착하는 문제" (보편 주제)
  - PLI Governor → "SFU에서 PLI를 어떻게 제어할 것인가" (설계 질문) + LiveKit/mediasoup/Janus 비교표
  - SDP 3연패 → 3번 실패 디테일 압축, mediasoup active/disabled/closed 표 중심
  - 마무리 원칙 → OxLens 구현 디테일 대신 SFU 구현자 보편 원칙 5개

---

## 기각된 접근법

- **5편 Active Speaker 포함**: 미구현 기능 예고편은 삽질기 톤에 맞지 않음
- **"~입니다" 체 혼용**: 시리즈 간 톤 불일치. "~다" 체 통일이 정답
- **4편 우리 삽질 디테일 중심**: 독자는 교훈을 원함. 삽질 과정보다 "무엇을 배울 수 있는가"

---

## 블로그 전체 현황 (2026-03-29 기준)

| 시리즈 | 편수 | 상태 | 포인트 컬러 |
|--------|------|------|------------|
| S1: SFU 해부학 | 5편 | ✅ 전편 게시 완료 | teal |
| S2: RTCP 완전정복 | 5편 | ✅ 전편 게시 완료 | amber (#f59e0b) |
| S3: Simulcast 삽질기 | 4편 | ✅ 전편 게시 완료 | indigo (#6366f1) |
| S8: AI와 함께 코딩하기 | 3편+부록 | ✅ 전편 게시 완료 | emerald (#10b981) |

**총 게시: 18편** (S1:5 + S2:5 + S3:4 + S8:4)

---

## 상태: ✅ 시리즈 완결 (게시 완료)

---

*author: kodeholic (powered by Claude)*
