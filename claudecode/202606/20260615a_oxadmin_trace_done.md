# 완료 보고 — oxadmin trace (랩 전용 패킷 in/out 진단)

> author: kodeholic (powered by Claude) / 구현: 김대리(Claude Code)
> 2026-06-15a. 설계: `context/design/20260615_oxadmin_trace_design.md`.
> 커밋: `oxlens-sfu-server` main `68785bc` (feat(trace) …). 회귀 oxe2e 5/5 PASS.

---

## §0 한 줄

특정 `user+ssrc` 의 RTP/RTCP 가 SFU 안에서 ingress→(변환/gate)→egress 까지 어떻게 흐르고 어디서
죽는지를 평문 전수로 떠내는 디버깅 탭. sfud `#[cfg(feature="trace")]` 격리, hub 우회 gRPC 직접 dial,
서버는 원시만 토출(분석은 AI). 설계 결정은 전부 코드와 정합 — 빌드/회귀 통과.

## §1 한 일 (변경 파일)

- **proto** `oxlens_sfu_v1.proto`: `rpc TracePackets(TraceFilter) returns (stream TraceEvent)` +
  `TraceDir` enum. common 이 server+client 생성(oxadmin 재사용).
- **oxsfud**
  - `Cargo.toml`: `[features]` 신설 (레포 최초). **현 `default = ["trace"]`** — §3 주의.
  - `trace.rs`(신규, 전체 `#[cfg(feature="trace")]`): 전역 단일세션 broadcast, `MatchKey`(user/ssrc/dir,
    user=None=와일드카드), dir OR 병합, 마지막 구독자 종료 시 세션 자동해제, hot-path `emit`(무매칭 alloc 0).
  - `grpc/sfu_service.rs`: `trace_packets` 핸들러 — off=`Status` 거부, on=구독→per-stream dir 필터→proto.
  - 6 trace point(전부 cfg): `ingress.rs`(ingress_rtp / decrypt_fail), `ingress_rtcp.rs`(ingress_rtcp /
    rtcp decrypt_fail), `subscriber_stream.rs`(egress_rtp / egress_gate_drop), `egress.rs`(egress_rtcp).
  - `lib.rs`: `#[cfg(feature="trace")] pub mod trace;`
- **oxadmin**
  - `Cargo.toml`: `common` + `tonic` 추가(gRPC 클라 첫 진입).
  - `trace.rs`(신규): `sfus` REST→addr→sfud 직접 dial→`TracePackets` 스트림 tail. simple/detail hexdump 렌더.
  - `main.rs`: `cmd=="trace"` 특수분기(shutdown 패턴) + **`room <id>` 스냅샷에 trace 인자 카탈로그**
    (USER/DIR/KIND/SSRC — publish ssrc·egress vssrc) 추가. 데이터는 기존 snapshot REST 에 이미 존재.

## §2 설계 대비 보정/결정 (검토 결과 반영)

- **egress RTP point = `subscriber_stream.rs::forward`**(설계 §5 추정 `egress.rs` 아님). rewrite 끝난 평문
  `buf` 자리. `origin_seq = ctx.rtp_hdr.seq`(rewrite 전 원본) 동봉 → §6 짝 정확.
- **gate_drop = video full-track 한정**(`tt != HalfNonSim && kind==Video && !is_allowed()`). PTT/audio 는
  이 gate 안 탐 — 코드·가이드 명시. `PauseReason` 실제 enum명(track_discovery 등) 사용.
- **PTT slot 역해석(§11 1순위) 결론**: explicit 매칭 + `user='*'` 와일드카드로 **PTT slot egress 전 listener
  완전 커버**. (oxe2e 실측: ptt1·ptt2 의 out audio 가 동일 `0xA5D8C694` = slot.virtual_ssrc 확인.)
- **빌드 편의 결정(부장님)**: "상용 아직 멀었다, 불편하게 쓰기 싫다" → `default=["trace"]`. `cargo build
  --release` 한 줄로 trace 빌드. Cargo.toml + 가이드 §4-T + 메모리에 **상용 전 `default=[]` 되돌림** 가드.

## §3 미결 / 후속

- **역해석 자동 fan-out 미구현(의도)**: "한 끝만 줄 때 반대 평면 자동 확장"(publisher 실 ssrc→slot
  vssrc / N listener 자동)은 보류. 설계 §4 가 "양 끝 명시=더 정확, 역해석은 보조"라 했고 cross-user 자동
  확장은 §10 "필터에 의미 강제" 기각선에 근접. 필요 시 부장님 결정 후 추가.
- **상용 전 빌드 위생**: `crates/oxsfud/Cargo.toml default = []` 복귀 필수 (deploy 가 `cargo build
  --release` 사용 → 안 빼면 도청 탭 묻어 들어감). 메모리 `project_trace_feature_default` 등록.
- oxe2e trace 빌드 연동 자동 단언(설계 §9-3)은 별 토픽.

## §4 검증

- 빌드: default(trace on) / `--no-default-features`(clean) / 전체 워크스페이스 release 양쪽 OK. clippy 순증 0.
- 단위: `cargo test` 전부 green(oxsfud 207 등 0 실패).
- 회귀 oxe2e **5/5 PASS**: conf_basic · ptt_rapid(A+B) · simulcast_basic · duplex_cache · telemetry_collect.
  내가 얹은 hot-path(ingress RTP/RTCP, egress RTP 전 subscriber, video gate, egress RR) 전부 실타격, 0 회귀.
- 라이브: PTT 진행 중 `oxadmin room qa_test_02` → trace 인자 카탈로그 정상 채워짐(§2 slot vssrc 실측).

## §5 가이드 현행화

- `context/guide/RUN_GUIDE_FOR_AI.md`: §4-T(oxadmin trace) 신설 + 명령표 Trace 행 + `room` 카탈로그 설명 +
  §6 빌드 함정(default trace) + §7 설계 링크. (context 레포 — 커밋은 부장님 몫.)
