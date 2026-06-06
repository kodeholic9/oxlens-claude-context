// author: kodeholic (powered by Claude)
# 완료보고 20260606c — repo 서버 문서 현행화 + 소스 잔재 청산

> 지침: `claudecode/202606/20260606c_repo_doc_resync.md`. 갱신 대상 = `oxlens-sfu-server/CLAUDE.md`/`README.md`/`.env(.example)` 뿐. 코드 동작 변경 0.
> 모든 재작성 사실 = 이번 세션 직접 정독 실증(opcode.rs / domain 실트리 / PROJECT_SERVER 라이브 / 0606b done). 창작 0.

---

## 결론

- **Phase A CLAUDE.md 전면 재작성 완료** — v2 화석(op 숫자/`room/`/`stream_map`/SWITCH_DUPLEX/252 tests/ParticipantPhase 5단계 단일출처) 전부 교정. v3 16진 + domain/ 2계층 + 3-Layer State + cross-sfu/supervisor 반영.
- **Phase C `.env`/`.env.example` 삭제 완료** — grep 결과 死파일 확정(아래 §Phase C). 마스터 ".env/dotenvy 완전 삭제" 가 사실로 회복.
- **Phase B README.md 초안 작성 완료** — v3 정합 + 포지셔닝 위반 2건 제거. **정지점 1 — commit 보류, 부장님 리뷰 대기.**
- **Phase D system.toml 잔재** — 발견_사항 보고만(아래 §Phase D). **수정 안 함.**
- 커밋: **아직 안 함**(작업절차 1단계 — diff 검토 후 GO 시 커밋).

---

## Phase A — CLAUDE.md 전면 재작성

실소스 대조로 발견 체크리스트 전 항목 교정:

| 화석(구) | 교정(현행) | 근거 |
|---|---|---|
| op 1~60 숫자, TRACKS_ACK, SWITCH_DUPLEX op=52, FLOOR_PING, SCOPE_UPDATE/SET | v3 16진 (TRACKS_READY 0x1102 / TRACK_STATE_REQ 0x1106 / SCOPE 0x1200 mode 분기 / FLOOR_MBCP 0x2400 / FLOOR_PING 폐기) | `oxsig/src/opcode.rs`(43 op) |
| `room/` 디렉토리, `media/`(router/track) | `domain/` (room→domain rename, media 흡수) | 실트리 |
| `stream_map.rs` "단일 출처" + "stream_map 외 SSRC 참조 금지" | 폐기 — enum 은 `domain/types.rs` 통합. 금지사항 삭제 | types.rs 헤더(이동 출처 2026-06-02) |
| `SubscribeMode enum 단일 출처 / match self.mode` | 분류 권위 = publisher `TrackType`(types.rs). SubscribeMode 자료로 응축 | types.rs `TrackType` |
| `participant.rs = RoomMember+ParticipantPhase+MidPool` | RoomMember(멤버십 메타)만. phase 는 `state.rs` 3-Layer | participant.rs 헤더(F29) |
| `PublisherStream(SSRC)` 단일 | 2계층: 논리 `PublisherStream`(source) ⊃ 물리 `PublisherTrack`(SSRC) + index 3종 | PROJECT_SERVER §2계층 |
| handler "7파일" | 9파일 (+scope_ops/client_event, +telemetry/mod) | 실트리 |
| Phase 표 ①.5 에서 끝남 | 묶음1~8 / F29 / ingress SRP / 통계정렬 / 2계층 / Duplex Activeness / 식별계층 / **cross-sfu Phase0~2b / supervisor** / CLIENT_EVENT+uniform-ack | PROJECT_MASTER 마일스톤 |
| "252 tests" | "현행 ~204~205 (0602e 기준)" | PROJECT_MASTER 0602b~e |
| MBCP "RTCP APP PT=204" | TS 24.380 native TLV (DC-only, WS Floor path 삭제) | PROJECT_SERVER §MBCP |
| ParticipantPhase 단일 `AtomicU8` | 3-Layer state enum(PeerState/PublishState/SubscribeState). lifecycle 설명은 유지, 자료위치=state.rs | state.rs 헤더 |
| oxhubd 맵에 supervisor/cross-sfu 누락 | `supervisor/`(8파일), state.rs(sfu_registry/room_sfu), rest/supervisor.rs·health.rs, track_dump/ 추가 | PROJECT_SERVER §oxhubd |

추가: Cross-SFU/Supervisor 섹션 신설, 빌드에 oxe2e 회귀시험 한 줄.

## Phase B — README.md 재작성 초안 (★ 정지점 1)

**B-1 v3/구조 정합**: op 표 전면 v3 16진(43 op, 카테고리 nibble 표) / `room/`·`media/`→`domain/` / MBCP→TS 24.380 native TLV(DC-only) / oxsig crate 명시 / 구조 트리 supervisor·cross-sfu 반영 / Tech Stack edition 2024·sctp-proto·nix 추가 / 버전 v0.6.16-dev → **v0.6.24-dev**(`crates/oxsfud/Cargo.toml` 실측).

**B-2 포지셔닝 위반 제거** (PROJECT_MASTER 정합):
- intro 수직시장 나열 *"(파견센터, 보안, 물류, 발전소)"* → **삭제**. "웹 브라우저 기반 상용 PTT + PTT 위젯 SaaS 지향 (B2B)" 로 교체.
- Design Targets *"최대 30명(RPi 기준), 1000명 검증"* → **삭제**. "상용 상한 1만 user (cross-room × SFU 3~5대)" 로 교체.
- "단일 인스턴스" 뉘앙스 → cross-sfu multi-node(hub supervisor, room→sfu 1:1) 반영.

**B-3**: "No fork. No framework. Just Rust." 톤 유지(사실).

> **정지점 1 — README 는 GitHub 공개물 가능성 + 포지셔닝 문구라 commit 전 부장님 최종 확인 요청.**

## Phase C — .env / .env.example 처리 (grep 판정 → 死파일 삭제)

grep 결과:
- **`dotenvy` 의존 = 0** (`crates/` 전체 + 모든 `Cargo.toml`).
- **`.env` 를 읽는 코드 = 0** — `std::env::var` 는 `oxsfud/src/metrics/env.rs` 의 `RUST_LOG`/`LOG_LEVEL` 표준 환경변수 2건뿐. dotenvy 없으니 `.env` 파일은 프로세스 env 에 로드조차 안 됨. `.env` 직접 파서/`from_path`/`from_filename` 호출 0건. (udp/mod.rs:141 `// REMB ... .env REMB_BITRATE_BPS` 는 stale **주석**일 뿐 리더 아님.)

→ 지침 §4-C 2번 조건(dotenvy 0 + 리더 0) 충족 → **死파일 확정, 삭제**:
- `.env` — **untracked**(`.gitignore` line 2 `.env`) → `rm` 으로 제거(git 추적 안 됨).
- `.env.example` — **tracked** → `git rm --cached` + `rm` (git status `D .env.example` staged).

마스터(PROJECT_MASTER L419 / PROJECT_SERVER L326) ".env/dotenvy 완전 삭제" 기술이 **사실로 회복**.

## Phase D — system.toml 잔재 (발견_사항, 수정 안 함)

**D-1 `[recording]`(oxtapd) 섹션 잔재** — `system.toml` L52~57:
```
[recording]
base_path = "./recordings"  / retention_days=30 / segment_continuous_secs=300 / segment_utterance_secs=3600 / segment_moderate_secs=3600
```
oxtapd 는 워크스페이스에 미존재(`crates/` 멤버 = oxsig/common/oxrtc/oxsfud/oxhubd 5개뿐, oxtapd 크레이트 없음). 읽는 코드 확인 필요하나 **현재 oxtapd 데몬 자체가 없어 死섹션 후보**. **삭제 안 함 — 부장님 별 토픽.**

**D-2 sfud2 supervisor unit 포트 불일치 + 충돌 후보** — `system.toml`:
- L75 주석: `sfud2 는 grpc(50052)+udp(19742)만 override`
- L79 실제 인자: `args = ["--grpc-listen", "127.0.0.1:50052", "--udp-port", "19741"]`
- → **주석(19742) ↔ 실제 인자(19741) 불일치.**
- 게다가 L45 `[sfu] ws_port = 19741`. sfud2 의 `--udp-port 19741` 이 sfu self-config 의 ws_port(19741)와 **같은 값** → 포트 충돌 후보(단, ws_port 는 "sfud 가 bind 안 함 — WS=hub 담당"이라 L75 주석. 실제 bind 여부는 코드 확인 필요).
- **포트 버그 후보. 수정 안 함 — 동작 영향 + 별 토픽.** 의도가 19742 라면 인자를 19742 로, 의도가 19741 이라면 주석을 19741 로 정정 필요(어느 쪽이 맞는지는 부장님 판단).

---

## 변경 파일

| 파일 | 변경 | 상태 |
|---|---|---|
| `oxlens-sfu-server/CLAUDE.md` | 전면 재작성 | 작성 완료(정지점 0, 통합 리뷰) |
| `oxlens-sfu-server/README.md` | 전면 재작성 | 초안 완료(**정지점 1, commit 보류**) |
| `oxlens-sfu-server/.env` | 삭제 | 완료(untracked rm) |
| `oxlens-sfu-server/.env.example` | 삭제 | 완료(git rm staged) |
| `oxlens-sfu-server/system.toml` | **무수정** | 발견_사항 보고만(D-1/D-2) |
| `context/PROJECT_*.md` | **무수정** | 0606b 영역 |

---

## 커밋 구조 (GO 후)

지침 §8: **server 레포 A(CLAUDE.md)+C(.env 삭제) 한 커밋**, **B(README) 는 정지점 1 통과 후 별 커밋**. context 레포는 본 done 보고만(코드 0).

---

## ★ 보고 종결

- **[결재]** CLAUDE.md + .env 삭제(A+C) — diff 검토 후 GO 주시면 A+C 한 커밋.
- **[택1]** README(B) 포지셔닝 문구(수직시장 삭제 / "1만 user" 상한 / cross-sfu multi-node) 최종 확인 — 공개물이라 정지점 1. 문구 OK 면 별 커밋.
- **[질문]** Phase D-2 sfud2 포트 — 의도값이 **19742**(주석 정합, udp 분리) 인지 **19741**(인자 현행) 인지? 별 토픽으로 정정 지침 주시면 처리. (D-1 oxtapd 섹션 존치/제거도 별 토픽.)

---

*author: kodeholic (powered by Claude)*
