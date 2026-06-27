// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 묶음 A~E 완료 종합 보고 (20260626e)

> **커밋 전.** 커밋은 부장님 지침대로 **전 작업 완료 후 한 방**. E(json! 추출 리팩터) "지침에 있는거 전부 진행" GO 로 착수·완료.
> 근거: 설계서 `20260626b` / 작업지침 `20260626c`. 정정 사항은 `20260626d`(묶음 A) 참조.
> 0625 simulcast track_id 작업(stash@{0})은 **버리기로 결정** — sentinel placeholder 폐기·논리 stream 직생성(199줄, 영상 forward 회귀) 미채택. 묶음 A는 stash 무관 최소 변경(가드 1줄 + 봇 정직)으로 수행.

---

## 1. 한 줄 결과

봇 정직화 + 서버 가드 1줄로 simulcast track_id 회신을 살리고(A), 부장님이 적재한 원료(B) 위에 judge 를 `count==0` → **등식 4종**(C1 seq·C3 ts·C4 track_id·C6 codec)으로 격상했으며, 1층 release 3중 정합 등식(D)을 유닛으로 박았다. **단위 oxe2e 15 / oxsfud 217, 회귀 5종 전부 PASS, 등식 위반 0.**

---

## 2. 변경 파일 (6 / +584 −37)

| 파일 | 묶음 | 내용 | 서버 동작 |
|---|---|---|---|
| `oxsfud/.../track_ops.rs` | A·E | A: `t.ssrc==0` 가드 `&& != FullSim` / E: add 2곳 `build_fullnonsim_add_core` 사용 | **변경**(A 가드 1줄 / E 리팩터=불변) |
| `oxsfud/.../helpers.rs` | E | `apply_video_codec_fields`·`build_fullnonsim_add_core` 신설 + collect 경로 사용 + 조립등식 유닛 4 | **변경**(리팩터=불변) |
| `oxe2e/src/bot/mod.rs` | A·B·C4 | simulcast entry ssrc→0(정직) / `packets`(부장님) / `Promise.pt`·`published_tracks`·`publish_ack_tracks`·`recv_pt` 캡처 | 무관(봇) |
| `oxe2e/src/bot/media.rs` | B·C6 | `RecvLog.packets`(부장님) / `recv_pt` 적재 | 무관(봇) |
| `oxe2e/src/judge/mod.rs` | C·테스트 | 등식 C1/C3/C4/C6 + 음성 픽스처 13종 | 무관(판정) |
| `oxsfud/.../peer.rs` | D | release_subscribe_track 3중 정합 유닛 2(양성+음성) | **무변경**(테스트만) |

> 서버 런타임 변경: **A 가드 1줄 + E 리팩터(동작 불변).** D는 `#[cfg(test)]`.

---

## 3. 묶음별 상세

### A. 봇 정직화 + 가드 (서버 가드 1줄)
- 봇 simulcast intent `ssrc: 0`(실 클라 SDP 계약 = SDP에 simulcast ssrc 없음). 가짜 non-zero 우회값 제거.
- 서버 가드 `if t.ssrc==0 { continue }` → `track_type` 확정 뒤로 내려 `if t.ssrc==0 && track_type != FullSim { continue }`. non-sim ssrc=0(파싱 실패)은 기존대로 skip 보존, simulcast(ssrc=0)는 placeholder 경로로 통과 → 응답 track_id 회신(vssrc 기반, track_ops:228).
- 게이트: simulcast_basic **forward PASS**(743패킷) = 봇 정직(ssrc=0) + 새 가드(`!FullSim`) 짝으로 forward·track_id 회신이 살아있음. (정정 20260626f #3: track_id **failability** 실증은 라이브 옛/신 대조가 아니라 **음성 픽스처 13종**이 담당 — 깨진 입력에서 빨간불.)

### B. 봇 수신 원료 (부장님 직접 구현)
- `RecvLog.packets: HashMap<u32, Vec<(u16,u32)>>` + 수신 루프 무가공 push + `BotResult.packets`. C1/C3 원료.

### C. judge count→등식 (C1/C3/C4/C6)
- **C1 seq 완전성**: 수신 ssrc별 seq 집합 min~max 결손 0(재정렬≠손실 → 집합). count==0 단독 PASS 소멸.
- **C3 ts 단조**: seq 오름차순(송신 순서) 정렬 후 ts 비감소. 역행=relay/rewrite 버그.
- **C4 track_id 회신 ★**: published mid ↔ ack track_id 대조. simulcast skip/빈값 검출 = **0625 §1.4 직격**. (봇 PUBLISH_TRACKS ack 캡처: conf=수신 루프, floor=sig_task Arc<Mutex>.)
- **C6 codec 정합**: 약속 video_pt ↔ 수신 RTP pt. 불일치=디코더 오선택(검은 화면 ④). audio(pt None)는 skip.
- **음성 픽스처 13종**: seq 갭/단일패킷, ts 역행/도착재정렬, track_id 미회신/빈값, codec 불일치/audio-skip 등 — 각 등식이 깨진 입력에서 빨간불(P-7).
- **C5 TRACKS_READY = 보류**: 봇 능동 송신이라 미처리 시 (a)이행이 0패킷으로 이미 FAIL + `evaluate_gate_resume`(ccc) 중복.
- **C2 개수 = 후순위**: `|수신|==송신N−gated` 에서 gated 가 화자전환에서 비결정적(작업지침 단서). 정적 conf 한정 약한 단언은 그물 효과 작아 보류.

### D. 1층 release 3중 정합 (oxsfud 유닛, 서버 무변경)
- `release_subscribe_track` 후 mid_map/SubscriberStreamIndex/mid_pool 3자 정합 → 재입장 시 새 stream(옛 egress 잔재 아님).
- 양성: release → 재입장 fresh(0xBBBB). 음성: ②streams 누락 시 옛 잔재(0xAAAA) 출현 = 재입장 미노출 버그 고정.

### E. json! 추출 리팩터 (프로덕션 코드 — "전부 진행" GO)
- **전제 정정**: 작업지침의 "5중복 단일 함수"는 실제 코드와 어긋남. 5곳은 **변형**(rtx_ssrc 유무 / simulcast 하드 vs 동적 / active / add vs remove / source null vs 키없음). 단일 통일은 거대 추상(설계서 §8 기각) 또는 동작 변경(리팩터 불변 게이트 위반).
- **동작 불변 범위만 추출**:
  - `apply_video_codec_fields(j, pt, rtx_pt, codec, simulcast)` — video codec 4필드 블록(track_ops:275·494, helpers:307) **3중복** 단일화. simulcast 파라미터화로 하드/동적 모두 수용.
  - `build_fullnonsim_add_core(user_id, kind, ssrc, track_id, video)` — FullNonSim add 코어(275·494 쌍둥이). source/mid 는 호출 맥락 차이(Option 조건부 vs String 직접, 콜백 vs 인라인)라 호출처 유지.
- **완전 단일통일·remove 통합은 안 함** — 동작 변경/거대 추상이라 게이트 위반. `build_remove_tracks`는 기존대로.
- 조립 등식 유닛 4(audio/video 코어, pt=0 생략, 양수 set)로 "상태→페이로드" 고정.

---

## 4. 게이트 결과

| | 결과 |
|---|---|
| `cargo build` (전체) | ✅ |
| `cargo test -p oxe2e` | ✅ 15 passed |
| `cargo test -p oxsfud` | ✅ 217 passed (기존 211 + D 2 + E 4) |
| 회귀 5종 (A~D 단계, A 가드 반영 sfud) | ✅ 5/5 exit=0, 등식 위반 0 |
| **E 동작 불변 회귀** (E 반영 sfud 재기동 후) | ✅ **5/5 exit=0, 등식 위반 0** — 리팩터 동작 불변 증명 완료 |

> ptt_rapid는 재기동 직후 첫 cold 1회 flaky(워밍업) — warm-up 1회 후 안정 PASS. 묶음 무관(별건).

---

## 5. 남은 것

- ~~E 동작 불변 최종 확인~~ — ✅ 완료(새 sfud 재기동 후 회귀 5종 동일 PASS).
- C5(TRACKS_READY)/C2(개수) — (a)이행·gate_resume 중복 / gated 비결정성으로 보류·후순위(설계 판단상 미채택).
- **남은 작업 없음.** diff 검토 → GO 시 A~E 한 방 커밋만 대기.

---

## 6. 커밋

전 작업(A~D, 그리고 GO 시 E)을 **한 방 커밋** 예정. 현재 커밋 안 함. 5파일 diff 검토 후 GO 주시면 커밋 메시지 잡습니다.

---

*author: kodeholic (powered by Claude)*
*묶음 A~D 완료. 커밋 전. E는 별도 GO. context 레포는 파일 작성만(커밋은 부장님).*
