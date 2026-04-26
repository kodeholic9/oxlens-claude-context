# 20260425 — 블로그 전략 재검토 (Velog 조회수 0 실측)

## 발단

잡담 중 "WebRTC 관심 갖는 사람들 주로 쓰는 블로그는 어디, 어떤 주제로 쓰면 좋을까" 질문. 김대리가 "SFU 내부, simulcast SSRC 동적 매핑, RTCP Terminator, TWCC 튜닝 같은 심도 있는 한국어 글 거의 없음 — 국내 독보적 틈새" 답변. 부장님 회신:

> "이거 velog에 내가 올렸자나, 조회수 0 이야. 아무도 관심없어."

**실측 반례**. 김대리 "독보적 틈새" 가정 무너짐. 재검토 필요.

---

## 실제 작성된 블로그 (context/blog/ 확인)

부장님은 이미 다음 시리즈를 작성하셨음:

- **S1 (SFU 기초 5편)**: MCU/SFU/Mesh, ICE-Lite, DTLS/SRTP, SDP-Free, Single Port Demux
- **S2 (RTCP 5편)**: RTCP basics, Terminator, SR Translation, PLI Governor, TWCC BWE
- **S3 (Simulcast 4편)**: Simulcast intro, PT hardcoding, Virtual SSRC Rewriter, Keyframe war
- **S8 (AI 활용 5편)**: Stop guessing, Giving memory, GIGO, AI debugging, Bonus
- **SFU Forensics 7편**: Pipeline stats, NACK storm, Mode-aware, Track identity, PT norm, jb_delay, System complete

즉 **공급 없음 가설은 틀림** — 부장님이 이미 공급 중. 조회수 0 의 원인은 다른 데 있음.

---

## 원인 재분석 (김대리 가설)

### 1. Velog 알고리즘 구조적 불리
- Velog 트렌딩 = 초반 24시간 burst 기반 좋아요/조회
- WebRTC 는 burst 독자층 없음 (전공자 희소)
- "리액트/스프링/면접 후기" 는 burst 잘 나옴
- 구조적으로 WebRTC 심도 글은 트렌딩 진입 불가

### 2. 한국 개발자 WebRTC 수요 얇음
- 입문 수준만 읽히는 구조 가능성
- "SFU 내부", "RTCP Terminator" 검색량 월 몇 건 수준
- 있을 수가 없는 검색량 → 존재만으로 조회수 안 나옴

### 3. 검색 유입 부재
- Velog Google SEO 평범
- 국내 관련 쿼리 검색량 자체가 바닥

### 4. 도메인 권위 부재
- 낯선 저자 + 낯선 주제 + 낯선 플랫폼
- Chad Hart (webrtchacks) 는 10년 누적 권위로 읽힘 — 글 좋아서만이 아님

---

## 재배치 전략 (Velog 우선순위 하향)

### A. Velog
- **국내 유입 도구 아님** (실측 확인)
- 크로스 포스팅 목적지 1개로 유지 — "여기 글 있다" 존재 증명
- 에너지 분배 감소

### B. 해외 플랫폼 (우선순위 상향)
- **webrtcHacks 기고** — 기술 심도 높은 1~2편 영문 번역 후 submission. Chad Hart 에게 직접 컨택 가능. 실리면 1~10만 조회. 권위 포인트 크게 상승
- **dev.to** — 쉬운 톤, 태그 기반 노출, 영문 부담 적음
- **Hacker News submit** — virtual SSRC / Rust SFU / NetEQ deception 류는 대박 터질 수 있음. 적중 시 수만 조회
- **Reddit r/WebRTC** — 좁지만 정확한 독자층

### C. 회사 블로그 (oxlens.com/blog, 우선순위 상향)
- B2B 리드 전환이 실제 목표라면 Velog 조회수 무의미
- 방문자 100명 중 10명이 문의 양식 작성 > Velog 조회 10000
- 회사 블로그 글은 SEO 자산 영구 축적 + 회사 브랜드 권위 형성
- Hugo 정적 사이트 기반 (부장님 skill 에 있음)

### D. B2B 세일즈 문서 (한국어)
- 기술 독자 포기, **의사결정자** 타겟
- 주제 예시:
  - 파견센터에 WebRTC PTT 도입기
  - MCPTT vs WebRTC PTT 비용 비교
  - 관제 시스템에 무전 위젯 붙이기
- 조회수가 아니라 **세일즈 도구** 로서의 가치
- 영업 팀장이 실제 미팅에서 배포 가능한 자료

### E. 기술 심도 글 = 영문 only
- 한국어 "RTCP Terminator" 독자 10명 / 영문 1만명
- 시간 ROI 1000배
- 한국어 초안 → LLM 번역 루프로 결과물 수준 유지 가능

---

## 실행 후보 (우선순위)

1. **기존 S2 / S3 시리즈 중 1~2편 영문 번역 후 webrtcHacks 기고 시도**
   - 후보: Virtual SSRC Rewriter (S3-03), RTCP Terminator (S2-02), SR Translation (S2-03)
   - 업계에서 실제로 자주 틀리는 지점 + OxLens 고유 기법

2. **oxlens.com/blog (Hugo) 구축** — Velog 글 migration + SEO 튜닝 (제목/meta/내부 링크)

3. **B2B 세일즈 문서 1~2편 작성** — 영업 팀장과 협의

4. **HN submission** — Virtual SSRC 또는 Rust WebRTC SFU 주제로

---

## 관찰

- 김대리의 "틈새" 판단이 공급만 보고 수요 놓친 사례
- 실측 데이터 (부장님 조회수 0) 가 가설을 즉시 무너뜨림 — 스냅샷 우선 원칙 ≒ 블로그 전략에도 적용
- 글 자체 퀄리티 ≠ 플랫폼 도달 — 분리 판단 필요
- Velog 에 쏟은 에너지는 손해 아니고 **배포되지 않은 자산**. 채널만 바꾸면 활용 가능

---

## 미결

- 영문 번역 루프 표준화 (LLM 초안 → 김대리 교정)
- Hugo 도메인 + 호스팅 선택
- oxlens.com 존재 여부 (도메인 확보 상태 확인 필요)
- 영업 팀장과 B2B 문서 협의 타이밍

---

*author: kodeholic (powered by Claude)*
