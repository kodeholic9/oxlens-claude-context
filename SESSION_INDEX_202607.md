# 세션 인덱스 — 2026-07

> 포맷: `날짜 | 파일명 | 요약 | 백로그`
> 규칙: 요약 100자 이내, 백로그 100자 이내. 백로그 = 미해결/미뤄둔 것 정리 — 없으면 `없음`.
> 파일 위치: `context/202607/<파일명>`

| 날짜 | 파일명 | 요약 | 백로그 |
| --- | --- | --- | --- |
| 07-01 | 20260701_sdk0.2_ts_rewrite_and_xsfu_slot_fix.md | sdk0.2 배포용 TS SDK 백지 재작성(2-path·어휘계승·internal 봉인·IoC 제거·tsup) + cross-sfu PTT slot 수신 GAP 해소(_byMid 폐기→slotByMid+sfuId 라우팅) + 3층 라이브 5/5 통과 + main 통합·브랜치 정리 | 관측 계층(telemetry/event-reporter/user-probe) v0.3 / origin main push 미실행 / CJS export 경고 / 청취 N방 영상 마스킹 미확인 |
| 07-02 | 20260702_sdk0.2_processor_media_filter.md | sdk0.2 Processor(인코더앞 미디어 filter) — 3사 조사(filter=인코더앞, encoded transform=E2EE전용) → LocalPipe.setProcessor(swapTrack 게이트)+WebAudio/Canvas 파이프라인(v2 이식)+내장3종(RadioVoice/Noise/Blur). 3층 라이브 2/2(radioVoice FFT 43dB·blur Canvas)·회귀 6/6 | video insertable 최적화(현 Canvas) / NS·Blur placeholder→ML승격 / extension 등록제·annotation 통합 / 수신측 가공 미지원 |
