# 작업 지침 — Publisher 2계층 배선 완료 반영 (소스 주석 + 마스터 현행화)
> 완료 보고 → [20260531e_publisher_2layer_doc_sync_done](../../202605/20260531e_publisher_2layer_doc_sync_done.md)

문서 ID: `20260531e_publisher_2layer_doc_sync.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: **동작 변경 0.** 2계층(`PublisherStream` ⊃ `PublisherTrack`) 배선이 코드엔 이미 완료인데, 소스 모듈 주석/attribute 와 PROJECT_MASTER 마일스톤이 "아직 미배선/미커밋"인 척하는 stale 잔재를 현물에 정합. 주석·doc·attribute 만 손댄다.
대상 파일:
- `crates/oxsfud/src/room/publisher_stream.rs` (모듈 doc + `#![allow(dead_code)]`)
- `crates/oxsfud/src/room/publisher_track.rs` (모듈 doc)
- `/Users/tgkang/repository/context/PROJECT_MASTER.md` (마일스톤 1항목 — **부장님 승인 후**)

> 이 stale 은 아키텍처 문서 2장 §D.3(2계층) 작성 중 발견. 코드 사실: `Peer::register_publisher_track` → `attach_track_to_stream`(`set_stream` 역참조)로 논리 Stream 배선이 살아 있음.

---

## §0 의무 점검
1. **git 상태부터 확인** — `git log --oneline -- crates/oxsfud/src/room/publisher_stream.rs` 로 Stage 1 커밋(`dadc342`) *이후* 2계층 배선(streams 등록 / register_publisher_track→attach_track_to_stream) 커밋이 있는지 확인.
   - 배선 코드는 **이미 존재**(peer.rs). 관건은 그게 *커밋됐는지*. 코드 배선 완료 ≠ git 커밋 완료 — 이 둘을 구분해 §1-D 마스터 문구를 고른다.
2. `publisher_stream.rs` 의 `#![allow(dead_code)]` 와 "## Stage 2 상태" 주석 블록이 현재도 그대로인지 확인(아래 §1-B old 텍스트 매칭).
3. **edit_file dryRun=true 선행 필수** — Korean 포함 주석이라 ASCII 앵커 안 되면 해당 줄만 read 후 정확 복제.

---

## §1 작업

### A. (선) git 확인 결과 분기
- **커밋 있음** → §D 마스터 문구 = "배선 완료 (커밋 `<hash>`)".
- **커밋 없음(코드만 배선, working tree)** → §D 마스터 문구 = "배선 완료 (코드), 커밋 대기". 커밋 자체는 부장님 판단 — 지침은 문구만.
- 어느 쪽이든 §B·§C(소스 주석)는 동일하게 진행.

### B. publisher_stream.rs — dead_code 해제 + Stage 주석 갱신

**B-1. `#![allow(dead_code)]` 제거 시도**
**old**:
```
#![allow(dead_code)] // Stage 2a: 신설만. 배선은 Stage 2b/2c.
```
→ **삭제**(이 줄 통째). 단 삭제 후 `cargo check -p oxsfud` 로 dead_code warn 확인.

> ★ **정지점 1** — attribute 는 파일 전체 스코프라, 제거하면 *아직 안 쓰이는* accessor/필드가 warn 으로 드러날 수 있다(`last_pli_relay_ms` 등 PLI 자료 일부가 호출처 미연결일 가능성). cargo check 결과를 다음 기준으로 처리하고 **보고**:
> - warn 0건 → 그대로 제거 확정.
> - warn 있음 → **진짜 미사용**(어디서도 안 부름)은 그대로 두지 말고 *해당 항목만* `#[allow(dead_code)]` 좁혀 부착 + "곧 쓰일 자리면 그 이유 1줄 주석". 파일 전체 `#![allow]` 로 되돌리지 말 것(전체 은폐 = stale 재발).
> - 판단 애매한 항목은 제거하지 말고 목록만 보고 → 김대리가 호출처 추적.

**B-2. "## Stage 2 상태" 주석 블록 갱신**
**old**:
```
//! ## Stage 2 상태 (2026-05-30 로드맵 §2 단계 2)
//! - struct + accessor 신설. 배선(`PublishContext.streams` 등록 / 호출처 전환)은 Stage 2b/2c.
//! - 설계서: `context/claudecode/202605/20260530c_publisher_2layer_roadmap.md`
```
**new**:
```
//! ## 배선 상태 (2026-05-31 — 배선 완료)
//! - `PublishContext.streams` 등록 + 호출처 전환 완료: `Peer::register_publisher_track`
//!   → `attach_track_to_stream`(`PublisherTrack::set_stream` 으로 Weak 역참조). 논리 Stream 은
//!   `(source, kind)` 묶음으로 신설·합류, 빈 Stream 은 `detach_track_from_streams` 가 폐기.
//! - 로드맵: `context/claudecode/202605/20260530c_publisher_2layer_roadmap.md`
```

### C. publisher_track.rs — 모듈 doc 정합 (방향 역전 + Index)

**C-1. "## 책임" 의 fan-out 표현 — 방향 역전 반영**
**old**:
```
//! - fan-out hot path 진입 (pub_room 단일 자리 fan-out)
```
**new**:
```
//! - fan-out hot path 진입 (`fanout()` → track_type() 분기: Full=broadcast_full 로
//!   `subscribers`(Weak Vec) 직접 순회 / Half=방 Slot 1회 rewrite). 방향 역전 — vssrc 역탐색 폐기.
```

**C-2. "## 핵심 자료구조" 에 누락 필드 보강** (2계층 후 Track 귀속분)
**old**:
```
//! - `virtual_ssrc: AtomicU32` (simulcast lazy CAS)
//! - `phase: AtomicU8` (PublishState)
```
**new**:
```
//! - `virtual_ssrc: AtomicU32` (simulcast lazy CAS)
//! - `recv_stats: Mutex<RecvStats>` (RR 생성, 물리 Track 1:1 — RTX 제외)
//! - `subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` (fan-out 방향 역전, Full 만 채움)
//! - `stream: Weak<PublisherStream>` (논리 Stream 역참조 — 순환 회피)
//! - `phase: AtomicU8` (PublishState)
```

**C-3. "ArcSwap<Vec<…>>" 표현 정정** — 모듈 doc/필드 주석 중 *컨테이너(tracks)* 를 `ArcSwap<Vec<…>>` 로 적은 자리가 있으면(grep `ArcSwap<Vec` 로 특정) → 실제 타입 확인 후:
- `PublishContext.tracks` 를 가리키는 자리 → `ArcSwap<PublisherTrackIndex>` 로 정정.
- `PublisherStream.tracks` / `PublisherTrack.subscribers` 는 *진짜* `ArcSwap<Vec<…>>` 이니 **그대로 둔다**(오정정 금지). 어느 컨테이너를 가리키는지 문맥 보고 판단, 애매하면 보고.

### D. PROJECT_MASTER.md 마일스톤 — **부장님 승인 후 apply**
마일스톤 "Publisher 2계층 전환 (2026-05-30)" 항목 끝의 stale 문구를 §A git 결과에 맞춰 정정. **마스터는 명시 승인 예외 원칙** — 아래 제안 블록을 부장님께 보이고 GO 받은 뒤에만 치환. GO 전엔 손대지 말 것.

**old** (해당 항목 꼬리):
```
... 211 PASS, Stage 1 commit `dadc342` / Stage 2~4 미커밋. **회귀/커밋 대기** — camera+screen oxe2e 시나리오 + 브라우저 명제 B 실증(admin `pli_state` dump) 미완.
```
**new (커밋 있음 case)**:
```
... 211 PASS, Stage 1~4 배선 완료 (커밋 `<hash>`). **회귀 대기** — camera+screen oxe2e 시나리오 + 브라우저 명제 B 실증(admin `pli_state` dump) 미완.
```
**new (커밋 없음 case)**:
```
... 211 PASS, Stage 1~4 코드 배선 완료 (`register_publisher_track`→`attach_track_to_stream`), 커밋 대기. **회귀/커밋 대기** — camera+screen oxe2e 시나리오 + 브라우저 명제 B 실증(admin `pli_state` dump) 미완.
```

---

## §5 변경 영향 범위
- `publisher_stream.rs` — attribute 1줄(제거 또는 좁힘) + 모듈 doc 3줄. **동작 0**(단 dead_code warn 표면화 가능 → 정지점 1).
- `publisher_track.rs` — 모듈 doc 만. 동작 0.
- `PROJECT_MASTER.md` — 마일스톤 1항목 꼬리(부장님 GO 후).
- 이 셋 외 손대지 말 것. cargo test 영향 없음(주석), cargo check 만 dead_code 표면화 확인용.

## §6 운영 룰
1. **주석/doc/attribute 외 코드 손대지 말 것.** 배선 로직은 이미 정상 — 건드리면 회귀.
2. **정지점 1**(§B-1 dead_code warn) — cargo check 결과 보고 후 진행. warn 항목을 파일 전체 allow 로 되돌려 은폐 금지.
3. 마스터(§D)는 제안 블록만, 부장님 GO 후 apply.
4. 같은 cargo check 에러 2회 미해결 → 중단 + 보고.

## §7 기각 접근법
- **파일 전체 `#![allow(dead_code)]` 유지** — stale 의 원인. "곧 쓸 거니까" 핑계로 전체 은폐하면 진짜 미사용이 영영 안 드러난다. 항목별 좁힘이 정답.
- **배선 로직까지 "정리"** — 지침 범위 밖. 주석만.

## §8 산출물
- 소스 2파일 주석/attribute 정정 + `cargo check -p oxsfud` 결과(warn 목록 포함).
- 마스터 제안 블록 처리 결과(GO 후 치환 / 또는 GO 대기 보고).
- 보고 파일: `context/202605/20260531e_publisher_2layer_doc_sync_done.md`.

## §9 시작 전 확인
- 아키텍처 문서 `context/design/architecture/20260531_state_ownership.md` §D.3(2계층 소유 그림) — 이 작업이 정합시키려는 "진실".

## §10 직전 작업 처리
- `20260531d_master_sync.md`(duplex activeness 마스터 7건)와 **별개 토픽**. 그 7건은 duplex, 이 건은 2계층 배선. 마스터에서 건드리는 자리도 겹치지 않음(d=track_ops/opcode/TRACK_STATE/SubscribeMode, e=마일스톤 2계층 항목 1줄).

---

*author: kodeholic (powered by Claude)*
