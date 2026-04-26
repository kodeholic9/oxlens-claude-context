# NN_<topic>.md — <한 줄 요약>

> **카테고리**: latency / throughput / scale / soak
> **마지막 갱신**: YYYY-MM-DD
> **관련 catalog**: `catalog/NN_*.md`
> **baseline**: `qa/baselines/<topic>.json`

---

## 시나리오

<무엇을 부하/지연 측정하는가>

## 측정 지표

| 지표 | 단위 | 목표 (threshold) | 측정 방법 |
|---|---|---|---|
| ... | ms / pps / bps / count | ... | admin sfu_metrics / getStats |

## 환경

- 서버: oxsfud / oxhubd 버전
- 클라: 브라우저 / Node / 머신 사양
- 네트워크: localhost / LAN / WAN

## 절차

1. ...
2. ...

## 결과 기록

`qa/runs/YYYYMMDD_NN/<topic>.json` 에 raw metric. baseline 갱신 시 `qa/baselines/<topic>.json` 업데이트.

---

> ⚠️ functional checks 와 분리. bench 는 threshold + baseline 비교, checks 는 binary pass/fail.
