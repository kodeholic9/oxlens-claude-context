# _done 보고 — Publisher 2계층 Stage 4 (recv_stats Track 귀속 + simulcast_group 폐기)

문서 ID: `20260530_publisher_2layer_stage4_done.md`
작성: 김과장 (Claude Code)
대상: 부장님 (kodeholic)
원지침: `claudecode/202605/20260530c_publisher_2layer_roadmap.md` §2 단계 4
상태: **Stage 4 GREEN 정지점 통과 (코드+unit). oxe2e 회귀는 부장님 환경 필요. 커밋 전.**
선행: Stage 1(rename 커밋 `dadc342`) + Stage 2(논리 PublisherStream/PLI, 미커밋) + Stage 3(명명 청산, 미커밋) 위 적층.

> ⚠️ Stage 4 = **동작 변경 포함** (recv_stats RR 생성 경로). unit test 211 통과로 1차 검증. 로드맵 §2 단계4가 요구한 `camera+screen 동시 keyframe` oxe2e 회귀는 봇 환경이라 김과장이 못 돌림 — 부장님 환경 확인 필요.

---

## GREEN 점진 — 3 substep

### 4a — PublisherTrack 에 recv_stats 필드 (additive)
- `pub recv_stats: Mutex<RecvStats>` 필드 + `new()` 에서 `RecvStats::new(ssrc, clock_rate)` 초기화 (clock_rate 이미 인자에 존재).
- import `crate::transport::udp::rtcp_terminator::RecvStats`. → build GREEN (미사용 warning 1, 4b 에서 해소).

### 4b — 호출처 3곳 전환 + DashMap 폐기 (동작 변경: RR 경로)
| 파일 | 변경 |
|---|---|
| `ingress_publish.rs:184` | `recv_stats.entry(ssrc).or_insert(RecvStats::new)` → `find_publisher_track(ssrc).recv_stats.lock().update()`. lazy entry 불필요(Track new 가 초기화). clock_rate 지역변수 제거 |
| `ingress_rtcp.rs:75` | SR 수신 `recv_stats.get(ssrc)` → `find_publisher_track(ssrc).recv_stats.on_sr_received()` |
| `egress.rs:311` | RR 생성 `recv_stats.iter()` → `tracks.load().iter().filter(!is_rtx).map(recv_stats.build_rr_block())` |
| `peer.rs` | `PublishContext.recv_stats: DashMap` 필드+init 제거 + `use dashmap::DashMap` / `RecvStats` import 제거 |
- **RTX 중복 없음 근거**: RTX SSRC 는 별도 PublisherTrack 미등록(원본 `rtx_ssrc` 필드로 표현). tracks 순회 = 전부 media Track → media SSRC 당 1 RR (기존 DashMap 도 `stream_kind != Rtx` 가드로 media 만 보유 — 동치). → build GREEN, 경고 0.

### 4c — simulcast_group 폐기 (순수 dead 제거)
- 사전 확인: `.simulcast_group` 을 **읽어서 분기하는 곳 0** (생성→저장→snapshot 자기복사뿐). placeholder 판별은 `is_placeholder()`(ssrc sentinel) 담당 — simulcast_group 무관.
- 제거 지점: `PublisherTrack` struct 필드 / `new()` 인자+init / `PublisherTrackSnapshot` 필드+생성 / `create_or_update_at_rtp` 인자+Self::new 전달 / `peer.add_publisher_track` 인자+전달 / `track_ops.rs` `register_simulcast_group` 생성+전달 / 테스트 헬퍼 2곳(hooks·publisher_track) new 호출 인자.
- → build GREEN + test GREEN.

## 정지점 검증 (실측 — 최종 재확인)
- `cargo build` (워크스페이스) → **GREEN** (WS_BUILD=0).
- `cargo build -p oxsfud` → 에러 0 / **경고 0**.
- `cargo test -p oxsfud` → **211 passed; 0 failed**.
- 잔존(전수 grep): `publish.recv_stats` **0** / `simulcast_group`(전 crate) **0** / `DashMap`(peer.rs) **0**.
- 신규: `track.recv_stats.lock` 3곳(ingress_publish/ingress_rtcp/egress) / `PublisherTrack.recv_stats` 필드 1.
- 변경 파일 19 (Stage 2~4 누적, 미커밋).

> ⚠️ 진행 중 도구 배치 호출로 일부 Edit 가 stale-string 실패 반복 → 매번 빌드가 잡아 순차 복구. 최종 GREEN 은 위 실측이 단일 기준.

## 2계층 마무리 상태
- ✅ Stage 1: PublisherStream→PublisherTrack rename (물리 명명 교정)
- ✅ Stage 2: 논리 PublisherStream 신설 + PLI 자료 source 이주 (**명제 B + catch 4 해결**)
- ✅ Stage 3: 명명 청산 (PublishContext `tracks`(물리)/`streams`(논리), Peer 메서드 정합)
- ✅ Stage 4: recv_stats Track 귀속 + simulcast_group 약한 끈 폐기
- → `PublishContext ⊃ PublisherStream(논리) ⊃ PublisherTrack(물리)` 2계층 자료구조 완성.

## 잔여 (부장님 판단)
- **oxe2e 회귀 미수행** — `camera+screen 동시 + screen keyframe`(명제 B 검증) 시나리오 추가 + conf/ptt/gating 회귀. 봇 환경 = 부장님.
- 커밋: Stage 1만 커밋됨(`dadc342`). Stage 2/3/4는 부장님 지시로 미커밋 — diff 검토 후 일괄 또는 단계별 커밋.
- 로드맵 `20260530c` §2 단계 3 = "명명 청산"으로 정정됨(Stage 3 _done 기록). 로드맵 파일 갱신은 부장님 지시 시.

> **커밋 안 함.** diff 검토 → GO 후 커밋 + 회귀.

---

*author: kodeholic (powered by Claude)*
