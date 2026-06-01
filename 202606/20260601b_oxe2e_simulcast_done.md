# _done — oxe2e simulcast publish 시나리오 추가

문서 ID: `20260601b_oxe2e_simulcast_done.md`
지침: `claudecode/202606/20260601b_oxe2e_simulcast.md`
수행: 김과장 (Claude Code)
범위: oxe2e 봇 송출만 (config/media/mod 3파일 + simulcast TOML). **서버·judge 0 변경.**

---

## §0 의무 점검
- REGRESSION_GUIDE 로드. config.rs 자기선언 철학(봇이 PUBLISH_TRACKS 로 선언하는 값) 숙지.
- baseline conf_basic / ptt_rapid PASS 확보(착수 전 + 사후 재확인).

## §1 변경 (oxe2e 봇 3파일 + TOML)

### config.rs
- `RID_EXTMAP_ID: u8 = 4` (mid=1 과 충돌 안 함, 봇 자기선언 — 서버가 이 id 로 RTP rid ext 파싱) / `RID_HIGH="h"` / `RID_LOW="l"`.

### media.rs
- `RtpSender.rid: Option<&'static str>` 필드. `audio()`/`video()` = `None`(현행). `video_sim(ssrc, rid)` 신설 = `Some(rid)`.
- `next_packet()` ext 블록: rid `Some` 이면 MID(2B)+RID(2B) = 정확히 4B = 1 word(`ext_len_words=1` 유지, 패딩 0). RID element = `(RID_EXTMAP_ID<<4)|0` + rid 첫 글자. `None` 은 현행(MID + 0 패딩).

### mod.rs
- `build_tracks` `"video" if track.simulcast` arm: h/l 2 SSRC(`ssrc_for(BASE, "{id}-{rid}")` salt 로 충돌 회피) + `video_sim(ssrc_h,"h")`/`video_sim(ssrc_l,"l")` 2 sender. PUBLISH_TRACKS entry 는 **1개**(simulcast=true). non-sim video 는 현행 1 SSRC + `video()`.
- PUBLISH_TRACKS body 에 `rid_extmap_id: RID_EXTMAP_ID` 추가(conf/floor 두 body).

### scenarios/simulcast_basic.toml
- sim1/sim2 각 audio full + video simulcast=true. run_secs 10(promote + gate.pause(5000) + TRACKS_READY resume + keyframe 2초 주기 마진). 레이어 전환 없음.

## §2 SSRC 처리 (§7-1 역산 아님)
- §C "SSRC 미선언" 은 서버 `track_ops` 의 `if t.ssrc==0 { continue }`(모든 트랙 공통 가드)에 걸려 트랙 skip → placeholder 미등록. 그래서 entry 에 **non-zero ssrc_h** 삽입. FullSim 이라 서버가 `alloc_sim_group()` sentinel 로 **대체**(register_ssrc) → entry ssrc 는 의미 없음. 보편 PUBLISH_TRACKS 계약(ssrc≠0) 충족용이지 simulcast 핸들러 역산 아님(conf 비디오도 동일 계약).

## §3 검증 (★ 정지점 1)
| 항목 | 결과 |
|---|---|
| `cargo build -p oxe2e` | clean (경고 0) |
| **`simulcast_basic`** | **✓ PASS** — sim1/sim2 각 약속 2건, 수신 ssrc 2종/743패킷 |
| baseline `conf_basic` / `ptt_rapid` | ✓ PASS (봇 공통코드 무손상) |
| 서버/judge 변경 | **0** (oxe2e 봇만) |

- **catch 2 verify 닫힘**: sim2 가 sim1 video **virtual ssrc** 743패킷 수신 = `simulcast=true` → sentinel placeholder → RTP `rid=h` 파싱 → **promote** → `TRACKS_UPDATE(add, virtual)` → SimulcastRewriter(h→virtual) fan-out 전체 체인 성공. promote 실패 시 video ssrc 0 → evaluate FAIL(판별성).
- judge `evaluate` 무변경(§2-3) — 약속(virtual)↔이행(virtual rewrite) 단순 비교가 그대로 성립. PASS 메시지의 "conf_basic" 문구는 비-floor judge 경로 재사용(정상).
- 서버 로그(nohup)는 config 2줄만 캡처 → functional PASS 가 promote 증거.
- broadcast 통합(20260601 Phase C, slot.subscribers) 위에서 simulcast FullSim arm(`self.subscribers`) 정상.

## §4 범위 제외 (이번 작업 아님)
- SUBSCRIBE_LAYER 레이어 전환(h↔l) 검증 제외(부장님). RTX(rrid) 송출 제외. 서버 0 변경.

## §5 커밋
- 소스 3파일 + simulcast_basic.toml. 정지점 GO 후 커밋. judge/서버 0 변경.

---

*author: kodeholic (powered by Claude)*
