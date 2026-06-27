<!-- author: kodeholic (powered by Claude) -->

# 20260624d — 마스터/문서 현행화 + webrtc 빌드환경 격리 이동 (세션 기록)

> 한 줄: 마스터 3종을 소스/디렉토리 실측으로 현행화(오판 유발 줄 삭제 + 소스 트리 + 사실 정합) → priming/stat 미커밋 표기를 커밋 해시로 갱신 → webrtc 빌드 체크아웃을 `~/repository/webrtc-checkout/` 하위로 격리 이동하고 video_replay 로컬 패치를 `oxlens-tools` 브랜치로 보존.
> 선행: [[20260624_ptt_priming_live_neteq_rootcause]], [[20260624b_ptt_vs_videocall_test]], [[20260622_republish_rewrite_fix_libwebrtc_videoreplay]].

---

## 1. NetEQ deception 줄 삭제 (오판 차단)

- PROJECT_MASTER.md SDK 코어 — `미해결: NetEQ deception (PTT 전환 시 RTX storm → NetEQ collapse)` 줄 삭제.
  - 사유: 06-24 결론(돌림노래 근본 = 수신 NetEQ arrival 지터 증폭, RTX/marker 무관)과 어긋나 이 줄을 읽고 오판함. 다른 이슈인데 혼선.
  - 하위 `libwebrtc custom build: oxlens-custom branch` 줄은 중립 사실이라 top-level 로 승격 보존.

## 2. 소스 트리 현행화 (실측 대조)

서버/웹 디렉토리를 실제로 떠서 문서와 대조. 잡힌 delta:

### 서버 (PROJECT_SERVER.md)
| 변경 | 근거 |
|---|---|
| `+ oxsfud/trace.rs` | 랩 전용 SRTP 평문 패킷 탭, `#[cfg(feature="trace")]`, 보안 1급 |
| `oxsfud handler/ 9→8파일` | `telemetry.rs` 폐기 (telemetry hub→oxcccd 직행, sfud 왕복 제거) |
| `+ oxhubd/ccc/mod.rs` | CccForwarder (텔레메트리 tap→oxcccd push, try_send fire-and-forget) |
| `+ oxhubd/probe/mod.rs` | User Probe (user 1명 unicast 진단 브리지) |
| `− oxhubd/track_dump/` | 2026-06-20 폐기 |
| `+ common/process.rs` | 데몬 프로세스 계약 상수 (supervisor↔자식) |
| Track Dump 섹션 → User Probe 섹션 | 모듈 삭제 정합 |

### 웹 (PROJECT_WEB.md)
| 변경 | 근거 |
|---|---|
| `core/ → __core_deprecated__/` | 0620 개명, demo 일부 `core/` import 가 개명으로 깨짐(강제 flush), sdk 배선은 app.sdk.js |
| `+ observability/{logger, user-probe-collector}.js` | 후자는 track-dump-collector 후신 |
| `− ptt/freeze.js` | virtual.js 흡수 (마스킹 개념 이전) |
| `− plugins/track-dump.js` | 폐기 (User Probe 대체) |
| admin 탭 / sdk/tests 19→20종 | 실측 정합 |

### opcode (PROJECT_MASTER.md) — 재활용 = 오판 위험 최고
- `0x2701`/`0x1702` 는 삭제가 아니라 **재활용**: `TRACK_DUMP_REQ/REPLY` → `USER_PROBE_REQ/REPLY` (같은 번호, 의미 교체, 0620). 두 표 줄 + 총 op 주석 + 키워드 + ADMIN_SNAPSHOT 설명 정정. 총 44 op 유지(42→44).
- 마일스톤 history(0520b/0520c~d) 는 날짜 박힌 기록이라 보존.

## 3. 마스터 사실 현행화 (소스/디렉토리 직접 확인)

| 위치 | 틀린 사실 → 정정 |
|---|---|
| 빌드 환경 | `.cargo/config.toml: +crt-static 필수` → 실제는 `rustflags=["--cfg","tokio_unstable"]`(Tokio RuntimeMetrics). crt-static 없음 |
| 디렉토리 구조 | `design/` 부재 → `architecture/`(설계 산출물 15파일). 202606/qa/PROJECT_*.md 누락 보강. `SESSION_INDEX.md` → 월별 `SESSION_INDEX_202606.md` |
| 구성 표 | `core/ 레거시` → `__core_deprecated__/ 개명(0620)` |
| 규칙 | `설계 문서: design/...` → `architecture/...` |

- **맞음 확인(정정 불요)**: crates 8종, opcode 상수/ALL_OPS 각 44개, 레포 4종 경로, 가이드 7종(guide/ 실측 일치), 시나리오 conf_basic/ptt_rapid 실재, oxlab-* 5크레이트.
- **보고만(부장님 판단 대기)**: `claudecode/` 디렉토리 부재 — context/ 전체에 없음. §분업 체계(김대리/김과장) + 글로벌 지침이 이 경로를 작업 지침 자리로 명시 → 워크플로 현행성 확인 필요. 디렉토리 구조 블록에서만 빼고 주석 남김.

## 4. priming/stat 미커밋 → 커밋 갱신

git log 로 실제 커밋 확인 후 표기 정정:
- oxsfud 예열(priming) 4파일 → **`6584bc3`** feat(oxsfud): PTT 예열(priming)
- oxadmin stat 다중 user + --out → **`f4209a9`** feat(oxadmin): stat 연속 모니터
- 반영처: 20260624_(§0·§2·§9·§10), 20260624b_(§5·§6), SESSION_INDEX 백로그 2행.
- 참고: 06-24 에 trace(`6f0232c`/`f4f7f33`/`23d4866`), user probe(`db325af`/`cc001dc`/`fcc54c9`), PTT half slot SR relay(`7386651`) 등도 커밋돼 있음 — 세션 기록 반영은 별도.

## 5. webrtc 빌드환경 격리 이동

`~/repository/` 루트가 webrtc 트리·부산물 로그와 뒤섞여 있어 한 부모로 격리.

- 이동: `~/repository/src` + `~/repository/.gclient` → `~/repository/webrtc-checkout/{ .gclient, src/ }` (+ gclient/ninja 로그 4개 동반). 같은 파일시스템이라 12G 즉시 이동.
- 제약: gclient 는 `.gclient` 부모 바로 아래 `src/`(솔루션명) 기대 → `.gclient` 도 같이 이동해야 함.
- 검증 4종 PASS: `gclient root`=webrtc-checkout 인식 / 도구 실행 exit=0(정적, 경로 무관) / `gn gen out/Default` 4034 targets 회복(toolchain.ninja 절대경로 regen) / 옛 경로 grep 0건.
- 경로 참조 8곳 갱신(현행 명령은 새 경로, 개명 이력 0621 src 서술은 보존+`→0624 이동` 한 단계 추가):
  - RUN_GUIDE_FOR_AI.md, 20260624_, 20260624b_, 20260622_
  - 메모리: project_libwebrtc_buildable_videoreplay, reference_neteq_rtpplay_harness, MEMORY.md

## 6. webrtc video_replay 패치 브랜치 보존

- webrtc src `main` 에 uncommitted 패치 1건: `rtc_tools/video_replay.cc` +11줄 (`--verbose` 플래그 — 수신 파이프라인 인과 로그 stderr 토출).
- `gclient sync` 에 날아갈 위험 → 브랜치 `oxlens-tools`(main `ce262a9607` 기반)에 커밋 **`9f19baf82c`**. `main` 무수정, upstream push 안 함(로컬 보존).
- 빌드/디버깅은 `oxlens-tools` 브랜치에서. main 으로 돌아가면 패치 빠짐.

---

## 변경 파일

### context 레포 (M — 부장님 commit)
- PROJECT_MASTER.md / PROJECT_SERVER.md / PROJECT_WEB.md
- SESSION_INDEX_202606.md
- guide/RUN_GUIDE_FOR_AI.md
- 202606/20260622_…md / 20260624_…md / 20260624b_…md
- 202606/20260624c_…md (본 기록, 신규)

### Claude 메모리 (갱신 완료)
- project_libwebrtc_buildable_videoreplay.md / reference_neteq_rtpplay_harness.md / MEMORY.md

### 파일시스템 / git
- `~/repository/webrtc-checkout/` 신설, src+.gclient 이동
- webrtc src 브랜치 `oxlens-tools` `9f19baf82c` (video_replay --verbose)

---

## 백로그 / 다음

1. **06-24 돌림노래 결론(수신 NetEQ 증폭·SFU 무죄·getStats 권위)의 마스터 반영** — 직전 [결재] 대기분. 미착수.
2. **claudecode/ 부재 + §분업 체계 섹션 현행성** — 부장님 확인 후 마스터 정합.
3. ~~webrtc 빌드환경 경로 가이드 명시~~ — **완료**: RUN_GUIDE §4-S 에 "webrtc 오프라인 도구 빌드환경" 박스 추가(체크아웃/빌드/gn gen 회복/`oxlens-tools` 브랜치 주의)..
4. PROJECT_WEB.md 의 `design/...` 설계 문서 경로 참조는 실제 `context/202606/` 또는 `architecture/` 와 어긋남 — 별도 정합 필요.

_기록 끝._
