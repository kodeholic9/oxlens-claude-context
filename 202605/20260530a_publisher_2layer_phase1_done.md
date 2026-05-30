# _done 보고 — Publisher 2계층 (Stream 논리 / Track 물리) Phase 1

문서 ID: `20260530a_publisher_2layer_phase1_done.md`
작성: 김과장 (Claude Code)
대상: 부장님 (kodeholic)
원지침: `20260530a_publisher_2layer_phase1.md`
상태: **⛔ 전량 롤백됨 (2026-05-30). Phase 1 + Phase 2 작업분 `git checkout` 으로 폐기, `publisher_track.rs` 삭제. oxsfud 워킹트리 = `35f80bc` 상태, 빌드 GREEN.**

---

## ⛔ 롤백 기록 (2026-05-30)

- **무엇**: 본 문서가 기술한 Phase 1(자료 이동) + 이어 착수한 Phase 2(호출처 배선) 변경을 **전부 되돌림**.
  - `git checkout -- crates/oxsfud/src/` (수정 12파일 복원) + `rm publisher_track.rs` (신규 삭제).
  - 복원 후 `git status` 변경 0, `cargo build -p oxsfud` GREEN 확인.
- **왜**: 부장님 지시. Phase 2 호출처 배선(113→약 50개까지 진행)이 길어지고, 세션 중 도구 호출 운영 미숙(병렬 과다 투입 → stale 결과 오독, string 불일치 재시도 반복)으로 진행이 비효율적. 깨끗한 상태에서 재출발 판단.
- **남긴 것**: 본 _done 문서(설계 결정 + 에러 패턴 레시피)만 기록으로 보존. 코드 산출물 0.
- **재개 시 참고**: 아래 §Phase 2 진행 절의 "배선 결정 3건"과 "호출처 수정 레시피" 표가 그대로 유효 — 다음 세션에서 기계적으로 재적용 가능. 단, hot-path(ingress/egress/PLI) 정확성 검증을 위해 안정 세션 권장.

---

### (이하 롤백 전 작업 기록 — 참고용 보존)
원상태: **Phase B 에러목록 산출 완료. 커밋 전 — diff 검토 대기.**

> ⚠️ 환경/자기정정: 작업 중 도구 출력이 배치로 뒤섞여 stale 결과를 두 번 잘못 읽었음.
> ① "Phase A GREEN/211 PASS" 오보고 → 실제로는 mod.rs 미등록 상태였음.
> ② mod.rs 등록 후에도 `publisher_track.rs` 에 **타입명 오타**(`RecvReceiverState`, 실제는 `RecvStats`) 1건이 남아 있었음 (E0432).
> → 오타 수정 완료. 아래는 **순차 호출 + exit code 로 재검증한 확정값**.

---

## §0 의무 점검 결과

| grep | 결과 |
|---|---|
| `rg "PublisherStream" crates/oxsfud/src` | **145** |
| `rg "publish\.recv_stats"` | **3** (egress / ingress_rtcp / ingress_publish) |
| `rg "publish\.pli_state\|pli_burst_handle"` | **~12** |

- PROJECT_MASTER "Peer 재설계 원칙" + "자료구조 단일 출처" 재독 완료. §2/§3 무단 변경 없음.

---

## Phase A — PublisherTrack(물리) 신설

### 산출
- **신규** `room/publisher_track.rs` (419줄): `PublisherTrack` (`ssrc / rid(ArcSwap) / clock_rate / actual_pt / actual_rtx_pt / rtx_ssrc / repair_for / recv_stats: Mutex<RecvStats> / rtp_cache / nack_generator / first_seen`) + `new()` + `rid_load/store` + `is_rtx()` + `is_placeholder()`. `#![allow(dead_code)]`.
- **수정** `room/mod.rs`: `pub mod publisher_track;` 등록.
- **수정** `publisher_stream.rs`: `RtpCache`/`NackGenerator` 정의+테스트 제거 → publisher_track import.

### §6.3 시그니처 선조치 — RtpCache/NackGenerator: **이동(move)**
- 사유: SSRC 단위 자산 = 물리(Track) home (§2). 외부 참조 0 확인 후 이동. `nack_generator_tests` 10건 동반 이동.
- `recv_stats` 는 `RecvStats::new(ssrc, clock_rate)` 로 초기화(Default 없음 — ssrc/clock_rate 보유).
- `kind: TrackKind` 는 `new()` 에서 nack_generator(video only) 결정에만 사용, 미보관.

### Phase A 건전성 (직접 관측)
- mod.rs 등록 후 단독 빌드 에러 = **RecvStats 오타 1건이 유일** → 그 외 Phase A 변경(타입 이동·테스트 이동·import)은 전부 클린.
- 오타 수정 후 전체 빌드에서 **`publisher_track.rs` 에러 0** 확인 (아래 폭발 목록에서 빠짐) → 물리 타입 정의 건전.
- ※ 211 테스트 단독 재실행은 **안 함** — 현재 Phase B 가 얹혀 크레이트가 의도적으로 안 깨짐(=컴파일 불가). 단독 GREEN 재검증 원하시면 Phase B revert→test→reapply 수행하겠음.

---

## Phase B — 논리 전환 + PublishContext 정리

### 변경 (구조체 정의 + new() 만; 호출처·메서드 본문 의도적 미수정)

**`PublisherStream` — 논리 계층 재정의**
- 물리 필드 제거: `ssrc / clock_rate / actual_pt / actual_rtx_pt / rtx_ssrc / repair_for / rid / rtp_cache / nack_generator / first_seen`. `simulcast_group` 폐기.
- 논리 필드 추가: `tracks: ArcSwap<Vec<Arc<PublisherTrack>>>`, `simulcast_pli_pending: AtomicBool`.
- PublishContext 에서 이동: `pli_state`, `pli_burst_handle`, **`last_pli_relay_ms`**(§3). `new()` 논리 전용 축소.

**`PublishContext` (peer.rs)**
- 제거: `recv_stats`, `pli_state`, `pli_burst_handle`, `last_pli_relay_ms`.
- 추가: `tracks_by_ssrc: DashMap<u32, Arc<PublisherTrack>>`. `new()` 정합 + `PublisherTrack` import.

### §3 추천 적용 (부장님 GO: "추천대로")
| 자료 | 추천 | 결과 |
|---|---|---|
| `last_pli_relay_ms` | Stream | ✅ PublishContext→PublisherStream 실이동 |
| `muted` | Stream | ✅ 이미 PublisherStream 잔류 |
| `phase` | Stream | ✅ 이미 PublisherStream 잔류 |
| `rtp_gap_suppress_until_ms` | Track | ⏸ **Phase 1 보류** — §2 확정/§4 제거목록 외. PublishContext 잔류, Track 이동은 Phase 2+ (추천 미결재) |

### 빌드 폭발 (의도된 산출 — 고치지 않음)
- `cargo build -p oxsfud` → **EXIT=101, 에러 93 / 경고 5**.
- **`publisher_track.rs` 에러 0** — 폭발은 전부 호출처/메서드 = Phase 2 todo.

**에러코드 (전부 "struct 모양 변경" 부류):**
| 코드 | 수 | 의미 |
|---|---|---|
| E0609 | 73 | 없는 필드 접근 (`.ssrc`/`.rid`/`.recv_stats`/`.pli_state`/`.simulcast_group` 등) |
| E0282 | 19 | 필드 소실로 인한 타입추론 실패 (E0609 연쇄) |
| E0061 | 1 | `PublisherStream::new` 인자 수 불일치 |

**파일별 (`-->` 위치, Phase 2 todo 규모):**
| 파일 | 에러 |
|---|---|
| `transport/udp/ingress_publish.rs` | 29 |
| `room/publisher_stream.rs` | 15 (자체 메서드 fanout/broadcast_full/snapshot/create_or_update_at_rtp) |
| `transport/udp/egress.rs` | 13 |
| `transport/udp/ingress_subscribe.rs` | 9 |
| `signaling/handler/admin.rs` | 7 |
| `signaling/handler/track_ops.rs` | 6 |
| `room/peer.rs` | 6 |
| `room/publisher_stream_index.rs` | 5 |
| `transport/udp/pli.rs` | 3 |
| `transport/udp/ingress_rtcp.rs` | 2 |
| `tasks.rs` / `room/room.rs` / `room/floor_broadcast.rs` | 각 1 |
| `hooks/stream.rs` | 1 |

(합 99 > 93 — 일부 에러가 복수 `-->` note 위치 보유. **publisher_track.rs 0**.)

---

## 변경 파일 (diff 검토 대상)
- 신규: `crates/oxsfud/src/room/publisher_track.rs`
- 수정: `crates/oxsfud/src/room/publisher_stream.rs`, `room/peer.rs`, `room/mod.rs`

> **커밋 안 함.** 부장님 diff 검토 → GO 후 커밋. Phase B 빌드는 깨진 상태(의도). 회귀시험은 Phase 2 완료 후 GREEN 복귀 시점 수행.

---

---

# Phase 2 진행 (2026-05-30, 부장님 "phase 2로 넘어가" + 서브-결정 3건 GO)

## 결정된 배선 (부장님 GO)
- **ssrc→Stream 해소 = Track 에 `stream: Weak<PublisherStream>` 역참조** (Option A).
- 서브-결정 3건 (기본안 GO): ① simulcast 레이어→Stream 매칭 = (kind, source) ② snapshot = Track당 1행(`snapshots()`) ③ PublisherStreamIndex `by_ssrc` 폐기, ssrc 조회는 `tracks_by_ssrc` 단일 경로.

## 완료: 프레임워크 4파일 전부 컴파일 통과 (에러 0)
- **publisher_track.rs**: `stream: Weak<PublisherStream>` + `stream()` accessor. `new()` 에 stream 파라미터.
- **publisher_stream.rs**: Track 컨테이너 API(`tracks_load/add_track/track_by_ssrc/track_by_rid/primary_track/primary_ssrc`). `is_rtx/is_placeholder/rid_load/rid_store` 제거(→Track). `snapshot()`(primary track)+`snapshots()`(per-track). `create_or_update_at_rtp` → 2계층 `(Stream, Track, is_new)` 반환 + `tracks_by_ssrc` 인덱싱(media+rtx 키). `fanout`: pli_state→`self.pli_state`, rid→`track_by_ssrc(rtp_hdr.ssrc).rid_load()`. `broadcast_full` PLI ssrc→track.
- **publisher_stream_index.rs**: 논리 컨테이너(`ordered`)로 단순화. `get`=`stream_by_ssrc` 별칭(선형검색). `with_removed(ssrc)`=Track 보유 Stream 제거. `find_ssrc_by_rid/has_video/has_audio/pending_notifications` Track 기반.
- **peer.rs**: PublishContext `recv_stats→tracks_by_ssrc`, `pli_state/pli_burst_handle/last_pli_relay_ms→Stream`. `add_publisher_stream`(simulcast_group 폐기), `remove_publisher_stream`(tracks_by_ssrc 정리), `switch_stream_duplex`(primary_ssrc).

## 빌드 추이: 93 → 113 errors (프레임워크 거의 0, 남은 ~113 = 순수 호출처)

> ⚠️ 수치 정정: 프레임워크가 일관돼지면서 그동안 다른 에러에 가려졌던 호출처 에러가 **전부 노출**됨 (회귀 아님 — todo 전모). publisher_stream/index/peer/track 프레임워크 4파일은 잔여 소수(내 `rid` move 버그 1건 수정 + 호출처-시그니처 불일치).

| 파일 | 남은 에러 | 수정 레시피 |
|---|---|---|
| `transport/udp/ingress_publish.rs` | 40 | `create_or_update_at_rtp` 새 반환 `(stream,track,is_new)` + sim_group 인자 제거; recv_stats → `tracks_by_ssrc.get(&ssrc).map(\|t\| t.recv_stats.lock())`; rtp_cache/nack_generator/rid/actual_pt/rtx → track; `is_rtx`/`is_placeholder` → track; `find_by_rtx_ssrc` → `tracks_by_ssrc.get(rtx)` |
| `transport/udp/egress.rs` | 16 | recv_stats iter → `streams→tracks` 순회(rtx 별칭 중복 회피); pli_state → 해당 video Stream; stream.ssrc/rid/nack_generator/is_rtx → track |
| `signaling/handler/admin.rs` | 16 | 스트림 순회 출력 → `snapshots()` (per-track); pli_state → Stream; is_rtx/rid_load/ssrc/actual_pt/first_seen/is_placeholder → track |
| `transport/udp/ingress_subscribe.rs` | 15 | pli_state → publisher video Stream; rid_load/ssrc → track |
| `signaling/handler/track_ops.rs` | 9 | pli_state → Stream; stream.rid/ssrc → track |
| `room/peer.rs` | 5 | pli_burst_handle(750) → Stream; 잔여 시그니처 정합 |
| `transport/udp/ingress_rtcp.rs` | 4 | recv_stats.get → `tracks_by_ssrc.get→track.recv_stats`; rid_load → track |
| `room/publisher_stream.rs` | 4 | `rid` move(646, **수정 완료**) + 호출처 시그니처 잔여 |
| `transport/udp/pli.rs` | 3 | pli_state/pli_burst_handle → per-Stream 해소 |
| `tasks.rs` | 3 | is_rtx/rid_load/ssrc → track/primary_* |
| `room/subscriber_stream.rs`/`room/room.rs`/`floor_broadcast.rs`/`hooks/stream.rs` | 각 1 | rid_load/ssrc → track/primary_* |

## ⚠️ 정확성 핵심
- **pli_state 가 publisher-단위 단일 → 논리 Stream 단위로 내려간 것이 명제 B 버그 수정 본체**. 호출처는 "publisher-wide lock"이 아니라 **PLI 대상 video Stream**을 정확히 해소해 lock 해야 함 (camera/screen 오염 차단).
- RTX RTP(ssrc=rtx)는 `tracks_by_ssrc` 에서 media Track 으로 해소됨 — egress RR 생성 시 media+rtx 두 키가 같은 Track 가리켜 **중복 집계 주의** → `streams→tracks` 순회로 RR 생성 권장.

## 환경 이슈 (정직 보고)
- 세션 후반 도구 출력(Bash/Read **display**)이 환각·중복·요약을 섞어 반환(예: 존재하지 않는 "스텁 fanout/생략" 표시). **실제 파일 작업(Edit/build/grep -c)은 정상**임을 `grep -c`(fanout=1, 생략=0)로 교차확인. 그럼에도 full-file read 검증 신뢰도가 낮아, 정확성이 중요한 hot-path 호출처 73곳을 무검증 강행하지 않고 본 체크포인트에서 멈춤.
- 변경은 전부 **워킹트리 미커밋** — 프레임워크 diff 검토 가능. 호출처 완료는 안정 세션 권장(위 레시피로 기계적 진행 가능).

---

*author: kodeholic (powered by Claude)*
