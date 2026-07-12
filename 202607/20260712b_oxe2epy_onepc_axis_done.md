# 20260712b — B8 2층 1PC 축 집행 완료 (봇 pc_mode + onepc 매트릭스 8종)

> author: kodeholic (powered by Claude)
> 집행: 김대리 (본 세션 — B7 `20260712_oxe2epy_twcc_synth_design.md` 직후 연속 집행, 부장님 "다음 진행" 사인).
> 배경: 20260712 시험 공백 진단의 A축 — Hyb 1PC 신설 기계(RTCP 라우터·egress_session·mid base)가
> 단위+3층 스모크만 있고 2층 27등식 대장이 1PC 에서 죽은 자산이던 구멍.

## 핵심 — 봇 천장이 없었다

클라 SDK 의 1PC 난제(mirror-offer·단일 협상 큐·PT 파서)는 전부 **SDP 협상** 때문이다.
oxe2epy 봇은 ORTC 직결(ufrag/pwd/fingerprint)이라 그 난제가 아예 없다 — 변경은:

1. `Bot(pc_mode="1pc")` — publish ufrag 로 **단일 transport** 연결, `self.sub = self.pub`
   alias. 기존 sub 참조 경로(수신 sink·RR/NACK 송신·twcc_synth FB) 전부 무수정 동작.
2. ROOM_JOIN body 에 `pc_mode:"1pc"` 동봉(2pc=미지정 — 클라 SDK wire 규약 동일).
3. orchestrator: 시나리오 전역 `pc_mode` 키 + 봇별 오버라이드(혼합 모드 방 가능).
4. 1pc 봇 다방 청취(multi-SFU listen)는 명시 raise(스코프 밖).

검증기·등식 **무수정** — dump 판정은 모드 무관(설계 원리 그대로): 27+B7 등식 대장이
그대로 1PC 판정기가 됐다.

## 매트릭스 8종 (scenarios/onepc_*.yaml — run-all 자동 편입)

| 시나리오 | 1PC 에서 처음 실전 판정되는 것 |
|---|---|
| `onepc_conf_audio_n3` | 단일 PC fan-out 완전성(under/over/self-echo) |
| `onepc_conf_video` | video gate + 수신 흐름 |
| `onepc_conf_simulcast` | vssrc 변환·rid-only (ONEPC-SIM 2층판) |
| `onepc_adv_rtcp` | ★route_onepc_rtcp **SR(by_ssrc)/RR(by_vssrc) 분류** + S3 종단 유지 |
| `onepc_adv_loss` | ★라우터 **NACK(fmt1) 분류** → RTX 복구(L4) 단일 PC 회신 |
| `onepc_ptt_voice` | floor DC + gating (ONEPC-PTT 2층판) |
| `onepc_ptt_stale_nack` | RTX gate 전환경계(S1)가 라우터 뒤에서도 유지 |
| `onepc_sim_bwe_updown` | ★★**1PC × v2 교차축** — FMT15 FB 가 라우터 분류를 타고 왕복 완주 |

## 검증

- 8종 전부 **첫 발 PASS**. 물증: 서버 로그 `ROOM_JOIN ... mode=1pc`(전 봇) + dump
  ROOM_JOIN send body pc_mode. 교차축 왕복 h(1.2~3.4)→l(~21.6)→h(~39.0)→l(~55.1) —
  2PC 원본과 동일 시각대(라우터가 투명).
- run-all full 36종 + pytest — 본 문서 커밋 시점 수치는 커밋 메시지가 진실.
- 서버 코드 diff 0. 부수 관찰: 1pc gate(TRACKS_READY→첫 수신) 1~2ms (2pc ~1080ms —
  sub DTLS 왕복이 없다. 수치 비교는 참고용).

## 잔여 (이월)

- 1pc 봇 다방 청취 / scope·sequential 경로 1pc 변형 — 필요 시 확장.
- 혼합 모드 방(1pc pub × 2pc sub) 전용 시나리오 — 메커니즘은 이미 있음(봇별 키), 대표
  시나리오는 미작성.
- 모드 take-over(재JOIN 1pc↔2pc) 라이브 변형 — 단위 통합시험만 존재.
- 클라 SDK 고유 축(mirror-offer·폴백 트리거 확장)은 봇이 못 만든다 — 3층 몫(진단 D).
