# bench/ — 성능 시험

> **목적**: 부하 / 지연 / 규모 / soak 시험. functional checks 와 분리하여 어펜드 가능 구조.
> **functional 과의 차이**:
>   - functional: binary pass/fail
>   - bench: threshold + baseline 비교 + soak duration

## 파일 구성 (점진 추가)

| 파일 | 카테고리 | 상태 |
|---|---|:---:|
| (예시) 10_floor_latency.md | latency | ⬜ TBD |
| (예시) 20_simulcast_throughput.md | throughput | ⬜ TBD |
| (예시) 30_scale_50participants.md | scale | ⬜ TBD |
| (예시) 40_24h_soak.md | soak | ⬜ TBD |

> ⚠️ 부장님 정의 시 점진 추가. 현재 자리만 잡음.

## 공통 측정 도구

- `__qa__.admin.sfu()` / `hub()` — 서버 카운터 (T0/T1 delta)
- `__qa__.user(u).getStats()` — 클라 RTCStats
- 별도 부하 도구: `oxlens-sfu-labs` (5 crate, Rust)

## baseline 위치

- `qa/baselines/<topic>.json` — 기준값
- `qa/runs/YYYYMMDD_NN/<topic>.json` — 실행 결과

## bench 시나리오 vs functional 시나리오

| 항목 | functional | bench |
|---|---|---|
| 위치 | `qa/scenarios/` | `qa/bench/` (사양) + `qa/runs/` (결과) |
| 검증 | catalog/checks 1:1 | threshold + baseline 비교 |
| 결과 | pass/fail | metrics + delta |
| 기간 | 보통 < 1분 | 1분 ~ 24시간 |
