// author: kodeholic (powered by Claude)
# 작업지침 20260606c — repo 서버 문서 현행화 + 소스 잔재 청산 (CLAUDE.md / README.md / .env)
> 완료 보고 → [20260606c_repo_doc_resync_done](../../202606/20260606c_repo_doc_resync_done.md)

> 본 건은 0606b(마스터 PROJECT_* 3종 현행화)에서 **누락된 영역** — repo 안 서버 문서 + 소스 잔재.
> 라이브 master = `context/PROJECT_{MASTER,SERVER,WEB}.md` (0606b 가 갱신 중). **본 지침은 PROJECT_* 를 손대지 않는다** (범위 충돌 금지).
> 본 지침 사실 = 김대리 직접 정독 실증(추측 0): repo 루트 directory_tree + oxsfud/src + domain/ directory_tree + CLAUDE.md/README.md/system.toml/.env.example 정독.

---

## §0 의무 점검
- 갱신 대상 = `oxlens-sfu-server/CLAUDE.md` + `README.md` + (조건부) `.env`/`.env.example` **뿐**. 코드 동작 변경 0.
- **stale 문서를 사실 출처로 믿지 말 것** — CLAUDE.md/README 자체가 v2 화석이다. 재작성 근거는 *실제 소스 직접 정독*.
- 권위 출처(재작성 시 이걸 읽어라):
  - opcode → `crates/common/src/signaling/opcode.rs` + `context/design/wire_v3_catalog.md` (43 op, v3 16진).
  - 소스 트리 → 실제 `crates/oxsfud/src/` + `crates/oxsfud/src/domain/` + `crates/oxhubd/src/` directory_tree.
  - Phase/원칙/포지셔닝 → `context/PROJECT_MASTER.md` + `PROJECT_SERVER.md` (라이브, context/) + `context/SESSION_INDEX.md` + `context/202606/` done 보고.
- 모르면 멈추고 [질문]. 새 사실 창작 금지.

---

## §1 컨텍스트 (무엇이 stale, 왜 위험)
0606b 는 PROJECT_* 마스터 3종(claude.ai 지식본 + context/ 라이브본)만 현행화한다. 그런데 **김과장이 매 세션 먼저 읽는 `oxlens-sfu-server/CLAUDE.md` 는 손대지 않았다.** CLAUDE.md/README.md 는 v2 시대(~2026-04, op 숫자 / `room/` / `stream_map` / `SWITCH_DUPLEX` / 252 tests)에 멈춘 화석 → **김과장이 이걸 사실로 믿고 옛 구조로 작업할 위험의 원흉.** 마스터가 아무리 정합해도 김과장 작업 컨텍스트(CLAUDE.md)가 거짓이면 무의미.

추가로 마스터가 "삭제됨"이라 단언한 소스 잔재가 실물로 남아 있다 (`.env`/`.env.example` — dotenvy 완전 삭제 주장과 충돌).

---

## §2 결정된 사항
1. `CLAUDE.md` 전면 재작성 (실제 소스 대조). 내부 문서 → 정지점 0.
2. `README.md` 재작성 — v3 정합 + **마스터 포지셔닝 원칙 위반 표현 제거**. 공개물 가능 → 정지점 1 (§3).
3. `.env`/`.env.example` 는 grep 판정 후 처리 (§4-C).
4. `system.toml` 의 `[recording]`/sfud2 포트 잔재는 **손대지 말 것** — 발견_사항 보고만 (§4-D).
5. 코드 동작 변경 0.

---

## §3 결정 추천 (★ 정지점)
- **정지점 1** — README.md 재작성 초안 작성 후 commit 전 부장님 리뷰. 이유: README 는 GitHub 공개물 가능성 + 타겟/규모 문구는 사업 포지셔닝. 마스터 원칙(아래 B-2)대로 초안 잡되, 최종 문구는 부장님 확인.
- CLAUDE.md(A) 는 내부 작업 문서 → 정지점 0, A+C+D 통합 리뷰.

---

## §4 단계별 작업

### Phase A — CLAUDE.md 전면 재작성
실제 소스 대조로 아래 stale 전부 교정 (김대리 발견 체크리스트 — 누락 금지):
- **opcode**: v2 잔재(`TRACKS_ACK`/`op=52 SWITCH_DUPLEX`/`FLOOR_PING`/`SCOPE_UPDATE/SET`/op 1~60 숫자) → v3 16진. `opcode.rs` + `wire_v3_catalog.md` 읽고 정합. (TRACKS_ACK→0x1102 TRACKS_READY / SWITCH_DUPLEX 폐기→0x1106 TRACK_STATE_REQ / FLOOR_PING 폐기 / SCOPE 단일 0x1200 mode 분기.)
- **디렉토리**: `room/` → `domain/` (rename 완료). `media/`(router/track) → **없음**(domain 흡수).
- **`stream_map.rs` "단일 출처"** → **폐기**(enum 은 `domain/types.rs` 통합). "stream_map 외 SSRC 참조 금지" 금지사항도 삭제.
- **`SubscribeMode enum 단일 출처 / match self.mode`** → 분류 권위는 publisher `TrackType`(types.rs). SubscribeMode 는 자료로 응축(catch 6).
- **`participant.rs = RoomMember+ParticipantPhase+MidPool`** → F29 해체. RoomMember(멤버십 메타)만. phase 는 `state.rs` 3-Layer(PeerState/PublishState/SubscribeState).
- **`PublisherStream(SSRC)` 단일** → 2계층: 논리 `PublisherStream`(source 단위) ⊃ 물리 `PublisherTrack`(SSRC). + `publisher_track_index.rs`/`subscriber_stream_index.rs`/`floor_routing.rs` 신규.
- **handler "7파일"** → 9파일(`scope_ops.rs`/`client_event.rs` 추가).
- **Phase 상태표**: ①.5 에서 끝남 → 묶음1~8 / F29 / ingress SRP(0521b) / 통계 트랙정렬(0602b~c) / Publisher 2계층(0530) / Duplex Activeness(0531) / 식별계층(0603) / **cross-sfu Phase0~2b(0603j~n) / supervisor(0603e~i)** 반영. (substance 는 done 보고 단일출처 — CLAUDE.md 는 한 줄 요약만.)
- **"252 tests"** → 현행 수치로(라이브 SERVER/done 확인; 0602e 기준 ~204~205).
- **MBCP**: "RTCP APP PT=204" 류 잔재 있으면 → TS 24.380 native TLV(DC-only, WS Floor path 삭제).
- **ParticipantPhase 단일 `phase: AtomicU8`** 설명 → 3-Layer state enum 으로 정합(과거 5단계 표는 lifecycle 설명으로 유지 가능, 단 자료구조 위치는 state.rs).
- supervisor/cross-sfu 가 oxhubd 핵심 파일 맵에 빠짐 → `supervisor/`, `state.rs`(sfu_registry/room_sfu), `rest/supervisor.rs`,`health.rs`, `track_dump/` 추가.

### Phase B — README.md 재작성
**B-1 v3/구조 정합** (A 와 동일 축): opcode v2 표(op 1~160) → v3 / `room/`·`media/` → `domain/` / MBCP "RTCP APP PT=204" → TS 24.380 native TLV / "Simulcast Phase 3"·"Floor Control v2" 등 옛 라벨 정리 / Tech Stack edition·버전 현행 확인.
**B-2 ★ 마스터 포지셔닝 원칙 위반 제거** (PROJECT_MASTER 정합 — 이게 핵심):
- *"B2B 타겟 (파견센터, 보안, 물류, 발전소)"* → **수직시장 나열 삭제.** 포지셔닝 = "웹 브라우저 상용 PTT + PTT 위젯 SaaS" (특정 수직시장으로 좁히지 말 것).
- Design Targets *"Room capacity: 최대 30명(RPi 기준), 아키텍처는 1000명 검증"* → **하드웨어로 규모 한정 표현 삭제.** 상용 상한 = 1만 user (cross-room × SFU 3~5대). "RPi 기준 30명" 같은 특정 HW 한정 금지.
- "단일 인스턴스" 뉘앙스 잔재 → cross-sfu(multi-node, supervisor) 반영.
**B-3** "No fork. No framework. Just Rust." 류 톤/마케팅 문구는 유지 가능(사실). 최종 문구 정지점 1 에서 부장님 확인.

### Phase C — .env / .env.example 처리
1. `dotenvy` 및 `std::env::var` 호출을 `crates/` 전체 grep.
2. **dotenvy 의존 0 + .env 를 읽는 코드 0** 이면 → `.env`/`.env.example` 죽은 파일 → 삭제 + done 에 보고. (마스터 ".env/dotenvy 완전 삭제" 가 사실로 회복.)
3. **.env 를 읽는 코드가 살아있으면** → 삭제 금지 + **[질문] 보고** (마스터 기술이 거짓 → 부장님 판단). `Cargo.toml` dotenvy 잔존 여부도 같이 보고.

### Phase D — system.toml 잔재 (보고만, 손대지 말 것)
- `[recording]`(oxtapd) 섹션: oxtapd 미구현 자리 — 잔재 여부 판단해 발견_사항 보고. **삭제 금지** (부장님 별 토픽).
- sfud2 unit: 주석 `udp(19742)` ↔ 실제 인자 `--udp-port 19741` 불일치 + 19741 이 `[sfu].ws_port` 와 충돌 가능 → **포트 버그 후보**. 발견_사항 보고만. **수정 금지** (별 토픽).

---

## §5 변경 영향 범위
- `oxlens-sfu-server/CLAUDE.md` / `README.md` — 재작성.
- (조건부) `oxlens-sfu-server/.env` / `.env.example` — Phase C 판정 시 삭제.
- `system.toml` — **읽기만, 수정 금지.** `context/PROJECT_*.md` — **손대지 말 것**(0606b 영역).
- 그 외 일절 손대지 말 것.

---

## §6 운영 룰
- 정지점 1(README 초안 리뷰). CLAUDE.md/.env/system.toml 보고는 통합.
- 추가 변경 금지 — §5 밖 발견은 *발견_사항* 보고만, 부장님 컨펌 후 별 토픽.
- 2회 실패 시 중단 + 보고.
- 내용 창작 금지 — 재작성 사실은 실 소스 + 권위 출처(§0) 대조로만.

---

## §7 기각 접근법
- **CLAUDE.md/README 경로만 치환(부분 패치)** — 기각. opcode/디렉토리/Phase 가 통째로 어긋나 전면 재작성.
- **stale 문서 기술을 근거로 재작성** — 기각. 그게 거짓 본체. 실 소스가 유일 근거.
- **.env "무조건 삭제"** — 기각. 살아있는 호출 가능성 → grep 선행.
- **system.toml 포트 버그 즉시 수정** — 기각. 동작 영향 + 별 토픽 → 보고만.
- **PROJECT_* 마스터 동시 수정** — 기각. 0606b 영역, 충돌.

---

## §8 산출물
- 재작성된 `CLAUDE.md`/`README.md` (+ 조건부 .env 삭제).
- done 보고 `context/202606/20260606c_repo_doc_resync_done.md` — Phase C grep 결과 + Phase D 발견_사항(oxtapd/포트) 포함.
- 커밋: server 레포 — A+C 한 커밋, B(README) 는 정지점 1 통과 후.

---

## §9 시작 전 확인
- `CLAUDE.md`/`README.md`/`system.toml`/`.env.example` 존재 확인.
- `opcode.rs` + `wire_v3_catalog.md` 존재 확인 (opcode 권위 출처).
- 실제 `domain/` 트리 재확인(§4-A 체크리스트와 대조 — drift 시 실트리 우선).
- 0606b done(`20260606b_master_doc_refresh_done.md`) 존재 여부 확인 — 있으면 라이브 PROJECT_* 가 이미 현행이라 Phase 수치/원칙 대조에 활용.

---

## §10 직전 작업 처리
- 0606b(마스터 PROJECT_* 현행화)와 **범위 완전 분리** — 0606b=PROJECT_*, 본 건=repo 서버 문서+소스 잔재. 동시 진행해도 파일 충돌 0.
- 0606a(uniform-ack) 커밋 완료, 본 건과 무관.

---

*author: kodeholic (powered by Claude)*
