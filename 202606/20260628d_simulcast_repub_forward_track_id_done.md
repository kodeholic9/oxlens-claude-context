# simulcast repub 검은화면·subscriber 누적 해소 — 완료 보고

- author: 김과장 (Claude Code)
- 작성: 2026-06-28 (세션 0628d)
- 근거 설계: `20260628c_publisher_meta_ownership_design.md` (publisher 메타 단일소유)
- 3층 브라우저 최종 검증: ✅ 정상 확인(부장님)

---

## 3증상 해소 (커밋 5개)

| 증상 | 근인 | 해결 | 커밋 |
|---|---|---|---|
| **SRV-0625** resp track_id ≠ add track_id | PublisherStream::new random vssrc + remove→new | 메타/MID/track_id/vssrc 를 논리 `PublisherStream` 단일소유, placeholder sentinel(0xF000_0000) 폐기 | f000c88 |
| **repub 검은화면** (l만 오고 h 지각=BWE drop) | notify 가 rid=h 도착 의존(`skipping notify for rid=l`) → h 안 오면 add 영영 누락 | **작전1** forward layer fallback (아래) | ecd768f·b29f2d4 |
| **subscriber 누적** (sim h-only repub) | remove 의 track_id 가 vssrc→실ssrc 둔갑 → 클라 getPipe(track_id) None → 안 지움 | **정석** track_id Track 불변 보유 (아래) | 4a871ee |

게이트(전부): 빌드 0경고 / 1층 217 / 2층 전체 회귀 0 / pytest 78 / 3층 정상.

## 작전1 — forward layer fallback (검은화면)

서버 simulcast forward 가 "수동 SUBSCRIBE_LAYER(current)만" 이라 h 미도착 시 l 도 못 보냄.
사용자 선호(desired)와 가용성(available)을 분리·합성:

- **S2** rid=l 도 통지(skip 블록 제거) + `current = resolve(desired=High, available)` → l 만 오면 Low(l forward)
- **S3** rid=h NEW → 구독자 promote(target=High) + h ssrc PLI → keyframe 도착 시 기존 502-504 가 current=High 전환
- **S4a** SUBSCRIBE_LAYER 를 `desired` 기반(사용자 l/h 선택 존중) + resolve
- **F4** h 소실(BWE drop) → `PublisherTrack.last_rtp_ms` stale 감지 → demote(High→Low) l fallback

핵심 자료: `Forwarder.desired`(신설) + `PublisherStream.available_layers()` + `Layer::resolve()`.
2층 실증: hdelay(h 60프레임 지각)에서 9.38s→7.47s 단축 + `[SIM:SWITCH] l→h` promote 확인.

## 정석 — track_id 정체성 불변 (누적)

근인: snapshot/notify 의 track_id 를 `stream().map(track_id).unwrap_or(ssrc)` 로 — Stream 폐기(detach) 후
`stream()` None 이면 **ssrc 로 위조**. add 는 stream Some(vssrc), remove 는 detach 후 ssrc → 불일치(I3 위반).

정석: `PublisherTrack.track_id: OnceLock<Arc<str>>` — register_track_to_stream 시 `stream.track_id()`(vssrc)
1회 복사 보유(불변). 발급 권위는 Stream(register_stream, 단일출처) 유지 / Track 은 정체성 보유만.
→ snapshot/notify = `self.track_id()` (위조 제거). 폐기 후에도 add==remove track_id.

**전수 확인(부장님 "일부만 판단 말라")**: sim 만 결함(Stream.track_id=vssrc≠fallback ssrc).
non-sim 은 Stream.track_id=first_track_ssrc=fallback ssrc **동일→무영향**, half 는 remove 가
`ptt-room-*` 경로(snapshot 무관)→무영향. 2층 honly(h-only Stream 폐기)로 remove track_id=add(vssrc) 실증.

## 2층(e2e) 검증 자산 — "모든 재현이 됨"

- 봇: `unpublish_video` + `SimulcastSender(order, h_delay_frames)` + orchestrator `republish_timeline`
- 시나리오: `conf_simulcast_repub{,_lfirst,_hdelay,_multi,_honly}` (repub 변형 5종) + `conf_sentinel_band`(0xF8 가드)
- 검증기: `simulcast_track_id_match` 집합대조(republish 거짓양성 수정) + SRV-0625 격리해제
- **2층으로 서버/클라 가름**: 봇 `REMOVE:MATCH mid_hit=Some(3)`(재활용) vs 3층 `None`(둔갑) → 서버 정상·클라 누적 입증 후, track_id 둔갑이 진짜 근인임을 dump(add==remove)로 확정.

## 교훈 / 사고

- **손실 사고**: git checkout 흐름(브랜치 생성·전환)에서 `oxe2epy` 미커밋 작업(+`.venv`)이 사라짐 →
  대화 기록으로 전량 재작성. 이후 **단계마다 커밋**(ecd768f WIP)으로 재발 차단. venv 는 python3.12 재생성.
- placeholder/forward/track_id 모두 "Stream 단일위임 + 폐기 시 ssrc fallback" 구조가 정체성을 도중에
  바꾼 게 공통 결함. **track_id 는 불변(I3)** — 어떤 상황에서도 둔갑 금지.

## 잔여

- 클라(oxlens-home SDK) `_recycleByMid`/`matchPipeByMid === 타입` 은 서버 수정으로 증상 해소됐으나
  코드 자체는 track_id 매칭이라 서버측 정합이 우선이었음(추가 정리 여부는 별도).
