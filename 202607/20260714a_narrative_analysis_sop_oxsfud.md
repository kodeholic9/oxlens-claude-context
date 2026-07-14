// author: kodeholic (powered by Claude)
# oxsfud 서사 기반 정적 분석 — 작업 지침 (SOP)

**문서 2/2 — 실행 지침**
version 0.1 (2026-07-14) · 대상: `oxsfud` (Rust WebRTC SFU)

> 방법론의 근거·한계는 **문서 1 `20260714_narrative_analysis_method.md`** 참조.
> **코딩 세칙·컨벤션의 단일 출처는 `PROJECT_MASTER.md`.** 본 문서와 충돌하면 `PROJECT_MASTER` 가 우선한다.
> 서버 구조는 `PROJECT_SERVER.md` 참조.

---

## 0. 절대 제약 (위반 시 세션 중단)

| # | 제약 | 근거 |
|---|---|---|
| **C1** | **2PC 경로는 어떤 이유로도 수정하지 않는다.** 분석·서술은 하되 변경 제안은 "관찰" 로만 기록 | 프로젝트 불변 |
| **C2** | **커밋은 부장님 결재 전까지 금지.** 분석 세션은 read-only | 프로젝트 규약 |
| **C3** | **근거 없는 문장 금지.** 모든 서술에 소스 앵커(파일 :: 함수 / 주석 인용) | 방법론 §5.1 |
| **C4** | **추측과 실측을 명시적으로 구분.** 확인 못 한 것은 "결함" 이 아니라 "❔ 의문" | 일반 원칙 |
| **C5** | **하이브리드(1PC) 작업 중인 파일은 분석만.** 변경 제안은 보류 목록으로 | 충돌 방지 |
| **C6** | **"코딩해" 명시 전까지 코드 작성 금지.** 분석 세션은 설계/발견만 | PROJECT_MASTER |

---

## 1. 세션 단위

### 1.1 1세션 = 1 인물군

**파일 1개가 아니라 "함께 사는 인물들" 이 단위다.**
`peer.rs` 만 읽으면 `PublisherTrack` 과의 관계가 안 보인다.

- 1세션 입력: **2~4개 파일**, 총 2000~3000줄 내외
- 테스트 코드 **반드시 포함** (`#[cfg(test)] mod tests` 는 증언이다)
- 3000줄을 넘으면 인물이 15명을 넘고 서사가 무너진다 → 분할

### 1.2 세션 산출물 (고정)

```
context/202607/YYYYMMDD<suffix>_narrative_<군이름>.md
```

**5개 섹션 고정. 하나라도 비면 세션 미완.**

1. **인물 대장** (Dramatis Personae) — 인물/소품/배역 분류
2. **인물 카드** — 인물당 1장, 1인칭
3. **대칭 표** — 형제 비교. **빈칸이 핵심** (F3)
4. **관계 비교 표** — 같은 자료를 만지는 함수 나란히 놓기 (F2) ★★
5. **발견 목록** — 등급별, 소스 앵커 + 2PC 영향 필수

**서사 본문(소설)은 선택이다.** 위 5개가 본체다.
서사는 5개를 채우게 만드는 **강제 장치**이지 산출물이 아니다.

---

## 2. 입력 규약 — 김대리에게 무엇을 주는가

### 2.1 필수
- 대상 파일 **전문** (테스트 포함, 잘라내지 말 것)
- 직접 의존하는 타입 정의 (`domain/types.rs`, `domain/state.rs` 등)

### 2.2 선택 (있으면 정확도가 오른다)
- 해당 파일의 `git log --oneline -30`
- `PROJECT_SERVER.md` 의 관련 레이어 정의 (→ Reflexion diff 가능)

### 2.3 주지 말 것
- **"이 부분이 이상한 것 같다" 는 힌트** — 후보 생성을 오염시킨다.
  방법론의 요점은 **어디를 볼지 모르는 상태에서 후보가 튀어나오게** 하는 것이다.
- **요약본** — 전수 열거(F1)가 무너진다

---

## 3. 실행 절차

### Act 0 — 배역 선정

```bash
rg '^pub (struct|enum|trait)' --no-heading -n <파일>
```

**분류 기준 (기계적):**

| 판정 | 기준 |
|---|---|
| **인물** | 필드에 `Arc` / `Mutex` / `Atomic*` / `Sender` / `ArcSwap` 보유 |
| **소품** | 순수 데이터. 위 없음 |
| **배역** | `trait` |

> **소품을 인물로 착각하면 서사가 산으로 간다.** `RtpPacket` 은 인물이 아니라 **편지**다.
> **trait 은 인물이 아니라 배역이다.** `BandwidthSignal` 은 인물이 아니라 *"대역폭을 보고하는 직책"* 이고,
> v1 계측자와 v2 GCC/TWCC 는 **같은 배역을 다르게 연기하는 두 배우**다.

**인물이 15명을 넘으면 → 세션 분할.**

### Act 1 — 인물 카드 (1인칭 고정)

```
■ <인물명>
  배역:              <Controller | Coordinator | Structurer | Service Provider
                      | Information Holder | Interfacer>
  나는 무엇인가:     (한 문장)
  내가 아는 것:      (보유 상태 필드)
  내가 못 하는 것:   ★ (다른 인물의 책임인 것)
  나를 움직이는 것:  (누가 나를 호출하는가 — tick? 이벤트? 직접 호출?)
  나의 갈등:         (trade-off / 경쟁 / 불확실성)
  내가 못 믿는 자:   ★ (지연·거짓·부재 가능성이 있는 협력자)
  나의 죽음:         ★ (Drop 있는가? 없으면 누가 정리하는가?)
  ▸ 근거: <소스 앵커>
```

**★ 3칸이 가장 중요하다.** 인물의 정체는 능력이 아니라 **경계**에서 드러난다.
"나의 죽음" 칸이 비면 그 자체가 발견이다 (→ `Peer` 에 `Drop` 부재).

**배역 유형 (Wirfs-Brock role stereotype):**

| 배역 | 성격 | oxsfud 예 |
|---|---|---|
| Information Holder | 알고만 있음. 물어야 답함 | SDP 파싱 결과, `PeerSnapshot` |
| Structurer | 관계·명부를 관리 | `Room`, `RoomHub`, `PeerMap` |
| Service Provider | 시키면 계산함 | `MidPool`, `RtpRewriter` |
| Controller | 결정하고 지시함 | `DownlinkController`, `FloorController`, `PliGovernor` |
| Coordinator | 직접 결정 안 함, 중개만 | hub WS dispatch (투명 프록시) |
| Interfacer | 바깥 세계와의 통역·외교 | `MediaSession` (ICE/DTLS/SRTP) |

> **한 인물이 두 배역을 겸하면 SRP 위반이고, 대개 거기에 버그가 산다.**

### Act 2 — 대칭 표 (F3) ★

**같은 층위의 형제를 표로 그린다. 빈칸이 곧 결함 후보다.**

실측 예 (세션 01):
```
publish.tracks    → PublisherTrackIndex          ✅
subscribe.streams → SubscriberStreamIndex        ✅
publish.streams   → Vec<Arc<PublisherStream>>    ❌ 빈칸 → 조회 7개가 Peer 로 누출
```

**대칭 축 (oxsfud):**
- publish 축 ↔ subscribe 축
- 물리(`PublisherTrack`) ↔ 논리(`PublisherStream`)
- 1PC ↔ 2PC
- audio ↔ video
- 인덱스 타입 유무 / `Drop` 구현 유무 / `snapshot()` 유무

### Act 3 — 관계 비교 표 (F2) ★★ 가장 중요

**같은 자료를 만지는 함수를 전부 한 표에 놓는다.**

실측 예 (세션 01) — 🔴 가 이 표에서 나왔다:

| 함수 | 사는 곳 | 만지는 자료 | 순서 | 락 |
|---|---|---|---|---|
| `release_subscribe_track` | `impl Peer` | mid_map, streams, mid_pool | **①②③** | map→drop→RCU→pool |
| `release_stale_mids` | `impl SubscribeContext` | mid_map, streams, mid_pool | **①③②** ← 불일치 | map+pool 동시→drop→RCU |

**표를 그리는 순간 불일치가 보인다.**

**비교 축:**
- 같은 필드를 쓰는 함수 그룹
- 같은 락을 잡는 함수 그룹
- 같은 RCU 컨테이너를 swap 하는 함수 그룹
- **호출 순서 / 락 순서 / 정리 순서** ★

### Act 4 — 주석 승격 (F4)

**주석에서 "왜" 를 추출해 불변식 목록으로 만든다.** 산출물은 `INVARIANTS.md` 에 누적 (§9).

```
INV-01: mid_pool.release 는 "다음 add 의 시작 신호". 그 전에 streams 가 깨끗해야 한다.
        ▸ domain/peer.rs :: release_subscribe_track 주석 (0524a 정합)
        → 위반: release_stale_mids  🔴

INV-02: SRTP 키 write 이후에만 set_media_state(Ready). (Release 게시)
        ▸ domain/peer.rs :: MediaSession::install_srtp_keys 주석
        → 검사: 다른 곳에서 set_media_state(Ready) 를 호출하는가?

TABOO-01: placeholder sentinel 금지 (0xF000_0000 — 실 ssrc 1/16 충돌 → 자기제거 → 검은 화면)
        ▸ domain/peer.rs :: alloc_sim_group 폐기 주석 (S4 20260628c)

TABOO-02: universal PTT vssrc 상수 금지 (cross-room 동시 발언이 같은 NetEQ 로 합류 → Axiom 2)
        ▸ domain/room.rs :: alloc_ptt_vssrc 주석 (Phase ①.5)

TABOO-03: auto-select 금지. scope 변경은 명시가 원칙.
        (sfud 마다 독립 발사 → user-global "발언축 1" 불변 파괴)
        ▸ domain/peer.rs :: sync_scope_on_join 주석 (S-e, 20260610)
```

**"★", "함정", "주의", "폐기 사유" 표기가 있는 주석은 최우선 검사 대상.**

### Act 5 — 발견 목록

| 등급 | 정의 | 처리 |
|---|---|---|
| 🔴 | **불변식 위반 / 잠복 결함.** 소스 근거 확실 | 즉시 별도 세션. P0 |
| 🟡 | **설계 공백.** 미완 설계, 누수 후보, 정리 책임 불명 | 백로그 |
| 🟢 | **정합성 흠.** 이름-동작 불일치, dead code, 관측 구멍 | 묶어서 일괄 |
| ❔ | **의문.** 확인 필요, 단정 불가 | 실측 대상 |

**모든 항목 필수 기재:**
```
[등급] 제목
  현상:   (무엇이)
  근거:   (소스 앵커 — 파일 :: 함수 / 주석 인용)
  원칙:   (어떤 INV/TABOO/아키텍처 원칙 위반인가)
  미확인: (내가 확인 못 한 것 — 반드시 명시)
  영향:   (2PC 영향 여부 ★ 필수)
```

**❔ 등급을 두려워하지 말 것.** 단정보다 정직이 낫다.

### Act 6 — 낭독 검증 (필수)

**소리 내어 이야기한다. 막히는 지점 = 이해 못 한 지점.**

그리고 **김대리에게 반증을 시킨다:**
> *"이 인물이 이렇게 행동한다고 썼는데, 소스 어디에 근거가 있나?"*

**서사는 반증되지 않는다. 이 단계가 유일한 안전장치다.**

---

## 4. 인물군 진행 현황

| 산출물 | 인물군 | 상태 |
|---|---|---|
| (세션 01) | 세션과 방 — `domain/peer.rs`, `domain/room.rs` | ✅ 🔴1 🟡3 🟢4 |
| `20260714b_narrative_floor_trilogy.md` | Floor 3부작 | ✅ |
| `20260714c_narrative_domain_saga.md` | domain 사가 | ✅ |
| `20260714d_narrative_udp_epic.md` | UDP 서사시 | ✅ |
| `20260714e_narrative_handler_bureaucracy.md` | 핸들러 관료제 | ✅ |
| `20260714f_narrative_datachannel_postoffice.md` | DataChannel 우체국 | ✅ |
| `20260714g_narrative_backstage_watchmen.md` | 무대 뒤 감시자들 | ✅ |
| `20260714h_narrative_gateway_gatekeeper.md` | 게이트웨이 문지기 | ✅ |
| `20260714i_narrative_frontdesk_ledger.md` | 프런트데스크 장부 | ✅ |

> **⚠ 위 8편은 산출물 파일명만 확인한 것이고, 본 SOP 작성 시점에 내용은 미독해다.**
> 다음 작업은 **8편의 발견 목록을 통합·중복제거·등급 재조정** 하는 것이다 (§5.1).

### 4.1 통합 후 최우선 판정 — 🔴 동시성

**🔴 (`release_stale_mids` 순서 위반) 의 실제 위험도는 `collect_subscribe_tracks` 호출부가 결정한다.**

> **같은 peer 에 대해 `release_stale_mids` 와 `release_subscribe_track` 이 동시 실행 가능한가?**
> - 직렬화되어 있다 → 무해. 순서 통일은 **위생 작업**으로 강등
> - 동시 가능 → **잠복 결함 확정. P0**

**이 판정 전에는 P0 착수 금지.**
`20260714e_narrative_handler_bureaucracy.md` (핸들러 관료제) 에 답이 있을 가능성이 높다 —
`helpers.rs` / `room_ops.rs` / `tasks.rs` 가 "옛 3중복 패턴" 이 살던 자리다.

---

## 5. 발견 → 조치 파이프라인

```
발견 (🔴/🟡/🟢/❔)
   ↓
❔ → 실측 (소스 / 테스트 / git log -S) → 등급 확정
   ↓
🔴 → 2PC 영향 검사 (C1)
        ├─ 영향 있음 → 기록만. 변경 금지
        └─ 영향 없음 → 재현 테스트 작성 → 결재 요청 → 수정
   ↓
🟡/🟢 → 백로그 → 하이브리드 종료 후 일괄
```

### 5.1 통합 단계 (다중 세션 후 필수)

**세션 N개를 돌리면 발견이 N배 나오는 게 아니라 중복이 N배 나온다.**
따라서 통합 단계가 반드시 필요하다:

1. **중복 제거** — 같은 결함이 여러 인물군에서 다른 이름으로 보고됐을 수 있다
2. **등급 재조정** — 세션 A의 🟡 이 세션 B의 발견과 합쳐지면 🔴 이 될 수 있다.
   **인물군 경계를 넘는 결함은 개별 세션에서 과소평가된다.**
3. **모순 검출** — 두 세션이 같은 인물을 다르게 서술했다면, 둘 중 하나가 틀렸다
4. **오탐 제거** — 근거 앵커가 없는 항목은 즉시 폐기

**산출물**: `INVARIANTS.md` + 통합 발견 목록 (등급순)

### 5.2 재현 테스트 우선

**수정보다 재현이 먼저다.** `oxsfud` 는 이미 그 문화가 있다:

```rust
#[test]
fn partial_release_without_stream_cleanup_reproduces_stale() {
    assert_eq!(s2.egress_ssrc.load(...), 0xAAAA,
        "②streams 미정리 시 옛 잔재가 반환됨 — release_subscribe_track 이 막아야 하는 버그");
}
```

**버그를 죽이지 않고 유리관에 넣어 전시한 테스트다.**
새 🔴 도 같은 형식으로 박제한 뒤 고친다.

---

## 6. 세션 01 미결 항목

| # | 등급 | 항목 | 다음 행동 |
|---|---|---|---|
| 1 | 🔴 | `release_stale_mids` 순서 ①③② vs `release_subscribe_track` ①②③ (INV-01 위반) | **동시성 판정** |
| 2 | 🟡 | `PublisherStreamIndex` 부재 → 조회 7개 Peer 누출 (`find_stream_by_track_id`/`by_vssrc`/`first_stream_of_kind`/`find_stream_for_attach`/`register_stream`/`detach_track_from_streams`/`stream_for_pli_target`) | `c`(domain saga) 확인 |
| 3 | 🟡 | `Peer` 에 `Drop` 부재. `cancel_pli_burst()` 를 누가 부르나? egress task 정리는? | `g`(감시자들) 확인 |
| 4 | 🟡 | `RoomHub` 방 GC 없음 (`remove_room` = "현재 사용처 없음") → 단조 증가 | `g` 확인 |
| 5 | 🟡 | `MediaState::Failed` 편도. 재협상 시 복구 경로? (주석: "재시도 자리는 별도 토픽") | `d`(UDP) 확인 |
| 6 | 🟢 | `mid_map` + `mid_pool` 락 2개 → `Mutex<MidTable>` 통합 시 락 순서 주석 소멸 | 백로그 |
| 7 | 🟢 | `session(PcType)` vs `egress_session()` 층위 혼재 (구조 기준 vs 목적 기준). 주석이 경고 중이나 **주석은 컴파일 안 됨** | **1PC 확산 전** |
| 8 | 🟢 | `find_publisher_by_simulcast_vssrc` — 이름-동작 불일치 (주석이 자인) | 개명 |
| 9 | 🟢 | `learn_rtx_ssrc` agg-log 가 `pub_room=Some` 일 때만 → join≠select 이므로 관측 구멍 | 백로그 |

---

## 7. 커밋 규율 (P0 착수 시)

**이동과 수정을 절대 한 커밋에 섞지 않는다.**

```bash
# 커밋 1 — 순수 이동, 로직 0 변경
git commit -m "refactor: release_subscribe_track → impl SubscribeContext (pure move, no logic change)"

# .git-blame-ignore-revs 등록 (없으면 이번에 신설)
echo "<hash>  # pure move: release_subscribe_track → SubscribeContext" >> .git-blame-ignore-revs
git config blame.ignoreRevsFile .git-blame-ignore-revs

# 커밋 2 — 로직 수정 (blame 에 남아야 함)
git commit -m "fix: release_stale_mids 정리 순서 ②streams → ③pool 정정 (INV-01)"
```

**이유:**
- 섞으면 diff 가 "함수 통째 삭제 + 통째 추가" → **한 줄 바뀐 걸 리뷰어가 못 찾는다**
- 섞으면 `.git-blame-ignore-revs` 로 무시할 수도 없다 (로직이 섞여 있으므로)
- 3년 뒤 `git blame` 이 "Phase 111 재입장 미노출 버그 수정" 대신 "refactor" 만 보여준다

**blame 복원 도구:**
```bash
git blame -M -C <file>          # 이동/복사 추적
git log -S '<문자열>'            # pickaxe — blame 이 놓쳐도 이건 안 놓친다
git log -L <시작>,<끝>:<file>    # 특정 라인 범위 전체 이력
```

---

## 8. 세션 시작 프롬프트 (복사용)

```
oxsfud 서사 기반 정적 분석 세션 — <인물군 이름>

지침: context/202607/20260714a_narrative_analysis_sop_oxsfud.md 를 따른다.

[첨부: 대상 파일 전문, 테스트 포함]

산출물 5개 고정:
  1. 인물 대장 (인물/소품/배역)
  2. 인물 카드 (1인칭, ★3칸 필수: 못 하는 것 / 못 믿는 자 / 나의 죽음)
  3. 대칭 표 (빈칸 = 결함 후보)
  4. 관계 비교 표 (같은 자료를 만지는 함수 나란히) ★★
  5. 발견 목록 (🔴/🟡/🟢/❔ + 소스 앵커 + 2PC 영향)

규칙:
- 근거 없는 문장 금지. 모든 서술에 소스 앵커.
- 확인 못 한 것은 "결함" 이 아니라 "❔ 의문" 으로.
- 2PC 경로 변경 제안 금지 (관찰만).
- 힌트 주지 않았다. 스스로 찾아라.
- "코딩해" 전까지 코드 작성 금지.
```

---

## 9. 산출물 배치

```
context/202607/
├── 20260714_narrative_analysis_method.md        ← 문서 1 (방법론)
├── 20260714a_narrative_analysis_sop_oxsfud.md   ← 문서 2 (본 지침)
├── 20260714b_narrative_floor_trilogy.md         ← 세션 산출물
├── 20260714c_narrative_domain_saga.md
├── 20260714d_narrative_udp_epic.md
├── 20260714e_narrative_handler_bureaucracy.md
├── 20260714f_narrative_datachannel_postoffice.md
├── 20260714g_narrative_backstage_watchmen.md
├── 20260714h_narrative_gateway_gatekeeper.md
├── 20260714i_narrative_frontdesk_ledger.md
└── INVARIANTS.md                                ← ★ 신규 (미작성). INV-xx / TABOO-xx 누적
```

`SESSION_INDEX_202607.md` 에 한 줄 요약(20~40자)만 등록.

### 9.1 `INVARIANTS.md` 가 최대 부산물일 수 있다

Act 4 의 산출물이 세션마다 누적되면, **그것이 곧 `oxsfud` 의 명세서다.**
지금은 주석에 흩어져 있어서, **그 파일을 읽은 사람만 안다.**

- 신규 인원이 파일 하나로 시스템의 계율을 배운다
- 새 코드가 계율을 어기는지 **기계적으로 검사할 목록**이 생긴다
- 장기적으로 `arch_check.mjs` 의 **서버판 정적 가드** 입력이 될 수 있다

---

## 10. 중단 조건

다음 중 하나라도 해당하면 **세션을 중단하고 방법론을 재검토한다:**

- 3세션 연속으로 🔴/🟡 이 0건
- 오탐(false positive)이 진성 발견보다 많다
- 인물 카드가 형식적으로 채워지기 시작한다 (= 강제력 상실)
- 문서 1 §6 대조 실험에서 **B 가 C 와 동일한 성과**를 낸다 (= 서사는 장식, 단순화)

**방법론은 도구다. 도구가 값을 못 하면 버린다.**

---

## 변경 이력

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. 세션 01(`domain/peer.rs`·`domain/room.rs`) 결과 반영. 산출물 b~i 존재 확인 |
