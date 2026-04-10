# 세션 컨텍스트: OxLabs 현장 재현 테스트 체계 설계

> 2026-03-29 | author: kodeholic (powered by Claude)

---

## 세션 요약

OxLens 안정화 단계에서 **현장 재현 테스트 체계(OxLabs)** 의 필요성 도출 → 업계 조사 → 설계 완료.

### 진행 순서

1. **업계 인력 현황 조사** — SFU Top 5 + Zoom/Sendbird/Google Meet 개발 인력 비교
   - Janus 2~3명, mediasoup 2명, LiveKit 83명 → SFU 코어는 소수 정예로 만들 수 있음 확인
   - 첫 릴리즈까지 공통 1.5~2년, 상용 안정화 2~3년

2. **OxLabs 설계** — 현장→측정→재현→수정→평가 품질 루프
   - 5개 crate (oxlab-net, oxlab-bot, oxlab-scenario, oxlab-judge, oxlab-cli)
   - 핵심 차별화: 스냅샷→재현 파이프라인 (어드민 텔레메트리 기반)
   - 설계 문서: `/Users/tgkang/repository/context/OXLABS_DESIGN.md`

3. **업계 테스트 도구 조사** — Jattack, jitsi-hammer, lk load-test, Zakuro, KITE, testRTC
   - 전 업체가 자체 도구를 직접 제작 (범용 도구로는 자사 프로토콜 테스트 불가)
   - 전부 "부하 생성" 수준에서 멈춤 → 품질 루프(네트워크 프로파일 × 시나리오 × 판정 × 회귀)는 없음
   - 스냅샷→재현 파이프라인은 업계에 전무

4. **설계 확장 논의**
   - SFU는 패킷 헤더만 보므로 봇 테스트가 SFU 검증의 100% (실기기 불필요)
   - SDK 검증은 별도 영역 — pre-encoded 미디어(IVF/OGG)로 봇이 SDK 상대방 역할 가능
   - participant별 type(bot/sdk), publish/subscribe 조합으로 다양한 시나리오 커버
   - **tc/netem 의존 제거**: 유저스페이스 네트워크 필터로 봇 내부에 녹임
     - 크로스 플랫폼 (Linux/macOS/Windows)
     - 참가자별 개별 프로파일 가능 (tc netem은 인터페이스 단위라 불가)
     - sudo 권한 불필요
   - 시그널링 어댑터 분리 → 향후 타 SFU 검증 확장 가능 (제품화 가능성)

---

## 핵심 결정사항

| 결정 | 내용 | 근거 |
|:-----|:-----|:-----|
| 직접 제작 | 외부 도구 안 씀 | OxLens 독자 프로토콜, PTT 시퀀스, 텔레메트리 통합 필요 |
| TOML 시나리오 | 사람이 읽지 않음, AI-Native | 스냅샷→시나리오 자동 생성, 사람 개입 시 의도 틀어짐 |
| 유저스페이스 필터 | tc/netem 미사용 | 크로스 플랫폼 + 참가자별 개별 프로파일 |
| Rust | SFU 코드 직접 import | opcode, RTP 구조체 공유, 타이밍 정밀도 |
| 시그널링 어댑터 | trait 분리 | 현재 OxLens 전용, 향후 타 SFU 확장 대비 |

---

## 기각된 접근법

- **Selenium/Playwright 기반**: 브라우저 의존, 무거움, RTP 정밀 제어 불가
- **testRTC 등 SaaS**: 독자 프로토콜 미지원, 오프라인 불가, 비용
- **tc/netem 직접 래핑**: 리눅스 전용, 인터페이스 단위(참가자별 불가), sudo 필요

---

## 부장님 MVS 경험

- 이전 프로젝트에서 MVS(자동검증 시스템) 구축 경험 있음
- MVML로 시나리오/패킷 생성 정의, SMS 서비스 데몬(10여개)과 통신하는 자동검증 체계
- OxLabs와 구조적으로 동일 (시나리오 정의 → 패킷 생성 → 다수 데몬 오케스트레이션 → 판정)
- 소스 추후 공유 예정 → OxLabs 설계에 반영

---

## 다음 세션 작업

- OxLabs Phase 0 구현 시작 시 이 컨텍스트 + OXLABS_DESIGN.md 참조
- 부장님 MVS 소스 공유 시 설계 반영
- SKILL_OXLENS.md에 OxLabs 섹션 추가 필요

---

*author: kodeholic (powered by Claude)*
