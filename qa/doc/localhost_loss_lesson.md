# localhost_loss_lesson.md — "22.5% packetsLost" 오진 사례

> **카테고리**: 교훈
> **마지막 갱신**: 2026-04-26
> **출처**: 2026-03-31 추정 시점 (현 PROJECT_MASTER 의 "텔레메트리는 사후 보고서이지 제어 신호가 아니다" 원칙의 계기)
> **관련 doc**: `pitfalls.md §1`

---

## 사건

PTT 영상무전 시나리오에서 subscriber 측 inbound-rtp.packetsLost 가 22.5% 측정. 시험 환경 = 단일 맥북 localhost (loopback only). 패킷 손실이 물리적으로 발생할 수 없는 환경.

## 오진의 흐름

1. "loss 22.5%" 라는 숫자만 보고 "네트워크 문제" 로 결론
2. 같은 숫자가 conference 모드에서는 0% → "PTT 모드의 네트워크 부하" 가설
3. RTX 추가 / NACK 강화 시도 → 효과 없음 → 시간 낭비

## 진실

`packetsLost` 는 **seq 갭 해석**. 즉 "수신한 마지막 seq" 과 "현재 seq" 사이 빈 갭의 갯수. localhost loopback 에선 물리 유실 0.

PTT 모드의 `packetsLost > 0` 의 진짜 원인:
- **SimulcastRewriter / PttRewriter 가 가상 SSRC 로 seq 재작성** → publisher 측 seq 증가, subscriber 측은 화자 변경 시점 reset → seq 갭 발생 → packetsLost 카운트 증가
- 즉 **rewrite 가 정상 동작했다는 증거**일 뿐, 실제 패킷 유실 0

## 교훈

> **localhost 에서 물리 유실은 불가능. `packetsLost > 0` 은 seq 갭 해석이다. 원인은 논리(rewrite / self-skip / transition) 에서 찾는다.**

이 사건이 PROJECT_MASTER 의 다음 원칙들로 정리됨:
- "텔레메트리는 사후 보고서이지 제어 신호가 아니다"
- "AI에게 오염된 정보를 주면 AI도 쓸모없어진다 — AI-Native 설계"

## 보호 장치

- **admin 서버 카운터로 교차** — `relay.egress_drop`, `srtp.decrypt_fail` 둘 다 0 이면 SDK 내 갭 해석 문제 (네트워크 아님)
- **메트릭별 정상 패턴 화이트리스트** — `audio_concealment`, `video_freeze during transitions`, PTT 의 `packetsLost` (seq 갭), `fps=0` idle 시
- **수치만 보지 말고 시나리오 컨텍스트 함께** — PTT 화자 전환 직후인지, conference 정상 운영 중인지

---

> ⚠️ "현장에서 통하는 답" 은 숫자 그대로 믿지 않는 것. 동일한 숫자도 시나리오에 따라 정상/이상.
