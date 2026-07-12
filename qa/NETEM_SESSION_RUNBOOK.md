# 실망(實網) 시험 묶음 런북 — auto layer 최종 물증 (부장님 세션용)

> author: kodeholic (powered by Claude)
> created: 2026-07-12 (김대리 — 20260711 백로그 "실망시험 묶음" + SRV-0712 수리 효과 정량)
> 소요 추정: 40~60분 1회. **필요한 것: 부장님 sudo(전 구간) + 귀(§4 청감 게이트만)**.
> 도구: `testlogs/202607/bwe_shaper.sh`(dummynet, 휘발성 — 재부팅 시 자동 소멸) ·
> 3층 qa/live · oxadmin. 측정 로그는 `testlogs/202607/` 박제(김대리가 세션 중 캡처).

## 사전 상태 (김대리가 세션 시작 시 확인)

- 서버 HEAD(SRV-0712 수리 포함) 가동 + `policy.toml auto_layer="v2"` / `bwe_mode="twcc"`
- `sudo ./bwe_shaper.sh spike` — dummynet 자가검증(ping 127.0.0.1 ≈ 200ms 확인)
- 3층 참가자: qa/live 수동 페이지(pub simulcast + sub) 또는 SIM-AUTO 하니스 활용

## §1 SRV-0712 수리 효과 정량 — 프로브 수렴 횟수 (신규, 최우선)

- **왜**: 구 측정(희석)에서 Chrome 실브라우저가 3회 수렴(312k→1.25M→1.63M→2.03M,
  20260711). 수리 후 1~2회 기대 — 2층 봇은 1회 실증됐으나 Chrome FB 타이밍은 실측 필요.
- **방법**: 실브라우저 pub(sim)+sub, shaper 없이(깨끗한 링크) sub 재접속 → 초기 demote →
  promote 까지 `[SIM:AUTO] probe 완주` 로그의 acked/estimate 나열.
- **판정**: 수렴 ≤2회 = 수리 실전 확인. 3회 이상 재현 = Chrome FB 특성의 별도 희석원
  존재 — 티켓.

## §2 bufferbloat 진동 소멸 (백로그 — 실 인코더 수요-반응이 본체)

- **방법**: `sudo ./bwe_shaper.sh on 1Mbit/s 50` (대역 1M + 깊은 큐 = bufferbloat 유발형).
  h(수요 1.65M) 불가 링크 — demote 후 재-promote 시도가 진동하는지 20분 방치 관찰.
- **관측**: oxadmin `user <sub>` 표 2회 Δ + `[SIM:AUTO]` demote/promote/backoff 라인 수집.
- **판정**: backoff 배증(15→30→60s cap)으로 진동 주기가 벌어지며 사실상 l 안착 = PASS.
  일정 주기 무한 플랩 = FAIL(백오프 설계 재검토).
- 변형: `on 3Mbit/s 20 40ms` (h 가능 경계) — promote 성공/생존 확인.

## §3 v1(REMB) 후퇴처 실망 검증 (백로그)

- **방법**: `policy.toml auto_layer="v1"` 재기동(oxadmin stop/load) → §2 동일 협착.
- **판정**: 실브라우저 REMB 로 demote 가 제때(협착 후 수 초) 걸리는가 + 해제 후 promote
  시도-후퇴 사이클 정상. v2 대비 반응 지연은 기대치(수신량 추정 특성) — 기능 성립만 확인.
- 종료 후 `auto_layer="v2"` 원복 재기동 필수.

## §4 PTT 청감 게이트 (사람 귀 — 자동화 불가분)

- **방법**: 음성무전(돌림노래 2인) 흐르는 중 video sub 가 프로브를 유발(§1 형).
  프로브(RTX 패딩, 수요×1.35 ≈ 2.2M, 2.5s)가 오디오와 동시 통과할 때 청감 열화 여부.
- **판정**: 끊김/로봇음/지연감 감지 시 → 티켓(프로브 rate-limit 은 20ms chunk 로 이미
  평활 — 그래도 들리면 audio 우선순위/프로브 상한 재설계).
- 참고: 0710 티켓 "NACK Δ 오디오 혼입"도 이 세션에서 재현 관찰 가능(demote 사유 로그에
  nack 가 뜨는데 원인이 audio NACK 인 경우).

## §5 GRACE 10s 튜닝 (백로그 — grace 로그 실측)

- **방법**: §2 경계 대역(3Mbit/s)에서 promote 직후 `[SIM:AUTO] grace remb 억제` 라인의
  REMB 램프 곡선(3s 간격) 수집 — 램프가 10s 안에 수요를 넘는가.
- **판정**: 항상 7s 이내 도달이면 GRACE 축소 후보 / 10s 초과 빈발이면 증가 후보.
  상수 변경은 별건 결재(수치만 박제).

## §6 P4b(video pacing) 착수 조건 판정

- §2~4 중 0624형 burst 증상(발신 발화중 wall-clock 뭉침 → 수신 지터 증폭) 재관찰 시에만
  P4b 착수 — 미관찰이면 계속 보류(20260711 결정 유지).

## 뒷정리

```bash
sudo ./bwe_shaper.sh off     # dummynet 원복 (status 로 pipe 없음 확인)
```
- policy.toml 원복(v2) + 재기동 확인, 측정 로그 `testlogs/202607/netem_<날짜>.md` 박제.
