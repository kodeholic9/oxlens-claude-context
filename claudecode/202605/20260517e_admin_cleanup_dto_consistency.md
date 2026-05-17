# 작업 지침: Admin DTO 일관성 + 대시보드 시각화 + Hook Ctx 안전망 (Hook Phase 3 후속 cleanup)

> Claude Code 작업 지침. 본 파일이 단일 출처. 별도 설계서 없음.
> 작성: 2026-05-17 (claude.ai 김대리, Hook Phase 3 (`20260517d`) 종결 후 즉시 진입)
> 검토자: 부장님 (kodeholic)
> 클라이언트 wire 변경: **0** (admin JSON 필드 *추가만*, 기존 필드 무변경)

> **본 작업은 *Hook Phase 3 후속 cleanup 묶음*** — 위험도 낮음. 정지점 없음. 통합 리뷰. 두 레포 (sfu-server + oxlens-home) 각 1 commit.

---

## 0. 작업 시작 전 의무 점검

```bash
cd ~/repository/oxlens-sfu-server
git status
git diff --stat HEAD
git log --oneline -5  # 직전 commit = Hook Phase 3 (20260517d) 일 것

# Phase 3 회귀 확인
cargo test --release -p oxsfud  # 252+ tests, FAIL 시 작업 진입 금지

cd ~/repository/oxlens-home
git status  # dd23894 (Hook Phase 3 정합) 이후 작업 여부 확인
```

### 추가 사전 점검

```bash
# 1. snapshot DTO 정의 자리
grep -rn "pub struct PublisherStreamSnapshot\|pub struct SubscriberStreamSnapshot\|impl.*snapshot()" crates/oxsfud/src/room/

# 2. admin.rs 의 직접 접근 자리 — 작업 대상 (3~4 자리)
grep -n "stream.phase.load\|s.phase.load" crates/oxsfud/src/signaling/handler/admin.rs

# 3. hooks::ctx() 사용 자리 — warn 로그 추가 자리
grep -rn "hooks::ctx\|HookCtx::ctx" crates/oxsfud/src/

# 4. snapshot.js 의 필드 매핑 — publish_state / subscribe_state 이미 매핑 있는지
grep -n "publish_state\|subscribe_state\|peer_state\|p\\.phase" ~/repository/oxlens-home/demo/admin/snapshot.js
```

---

## 1. 컨텍스트

### 1.1 직전 작업 (`20260517d`, Hook Phase 3) 산물

- 3 enum 분해 완료 (PeerState / PublishState / SubscribeState)
- admin JSON 키 분리 완료 (`peer_state` / `publish_state` / `subscribe_state`)
- oxlens-home `dd23894` 별 commit — render-overview.js / snapshot.js 의 `peer_state` 만 반영

### 1.2 본 작업이 푸는 4개

1. **DTO 일관성** — admin.rs 가 *PublisherStream / SubscriberStream 의 phase 직접 접근* 으로 우회 (snapshot DTO 에 phase 필드 없음). *추상화 침범*. 4 자리.
2. **대시보드 시각화** — render-overview.js 가 *peer_state dot 만 표시*. publish_state / subscribe_state 는 *서버가 보내지만 클라가 미사용*. 신규 시각화.
3. **F16 표현 정정** — 직전 *"admin 중복 표시 cleanup"* 표현이 부정확. *축 분리는 PROJECT_MASTER §어드민 (Cross-Room rev.2 §9.5) 정합* — 서버 출력 중복 유지. F16 의 진짜 의미 = *대시보드 표시 디자인*.
4. **hooks::ctx() warn 로그** — production startup 에서 init 미호출 시 *silent fail* 위험. Hook Phase 1 의 백로그 자리.

### 1.3 부장님 결정 (2026-05-17 세션)

| 항목 | 결정 |
|------|------|
| F16 처리 | 옵션 A — 서버 출력 유지 (축 분리 정합). 대시보드 표시 디자인으로 정정 |
| DTO phase 필드 type | 옵션 A — `phase: PublishState` / `phase: SubscribeState` (enum 직접) |
| 대시보드 시각화 디자인 | 옵션 A — tracks 행 안에 publish_state dot 추가 (기존 peer_state dot 패턴 확장) |
| hooks::ctx() warn | warn 로그 1자리 추가 (운영 안전망) |

---

## 2. 결정된 사항 (확정, 변경 금지)

1. **snapshot DTO 에 phase 필드 추가** — PublisherStreamSnapshot / SubscriberStreamSnapshot 각각
2. **admin.rs 의 직접 접근 제거** — `snap.phase` 사용으로 통일
3. **render-overview.js 의 tracks/sub_streams 행에 state dot 추가** — created=회색 / intended=노랑 / active=초록
4. **hooks::ctx() None 분기 warn 로그** — init 누락 silent fail 안전망
5. **클라 wire 영향 0** — admin JSON 필드 *추가만*, 기존 키/값 무변경

---

## 3. 결정 추천 (Claude Code 선조치 자리)

### 3.1 ★ snapshot DTO 의 phase 필드 시점

`stream.snapshot()` 메서드 본문에서 *어느 시점 phase* 캡처할지:

- **옵션 A** (추천): `phase: PublishState::from_u8(self.phase.load(Ordering::Relaxed))` — snapshot 호출 시점의 phase 값 캡처
- **옵션 B**: `phase: AtomicU8` (직접 노출) — DTO 자체가 atomic 보유. 의미 부적합 (DTO 는 시점 캡처)

→ 옵션 A 채택. **Claude Code 가 다른 필드의 캡처 패턴 (`muted: self.muted.load(Ordering::Relaxed)`) 과 일관** 으로 박음.

### 3.2 ★ hooks::ctx() warn 위치 + 빈도

`ctx()` 가 None 반환 시 매 호출 warn 로그 → 로그 폭주 위험. 빈도 제한 필요:

- **옵션 A** (추천): `OnceLock<()>` 으로 *최초 1회만 warn* — 운영 환경 init 누락 1자리 감지 충분
- **옵션 B**: `tracing::warn_once!` 매크로 — 외부 의존 추가
- **옵션 C**: 매 호출 warn — 부적합 (폭주)

→ 옵션 A 채택. **Claude Code 가 `hooks::ctx()` 함수 시그니처/본문 보고 자연스럽게 박음**.

### 3.3 ★ 대시보드 dot 색상 매핑

`stateColors` 객체에 *publish_state / subscribe_state 별 매핑* 추가:

```js
const publishStateColors = {
  created:  "bg-gray-500/20 text-gray-400",   // RTP 대기
  intended: "bg-yellow-500/20 text-yellow-400", // 사전등록 완료
  active:   "bg-green-500/20 text-green-400",  // RTP 흐름 중
};
const subscribeStateColors = {
  created: "bg-gray-500/20 text-gray-400",
  active:  "bg-green-500/20 text-green-400",
};
```

dot 문자 — 기존 `●` 재사용. tracks 행 안의 *kind / ssrc / publish_state* 한 줄 표현.

---

## 4. 단계별 작업

### Phase A: snapshot DTO 에 phase 필드 추가

**대상 파일**:
- `crates/oxsfud/src/room/publisher_stream.rs`
- `crates/oxsfud/src/room/subscriber_stream.rs`

**작업**:
1. `PublisherStreamSnapshot` struct 에 `phase: PublishState` 필드 추가
2. `impl PublisherStream::snapshot()` 본문에 `phase: PublishState::from_u8(self.phase.load(Ordering::Relaxed))` 라인 추가
3. `SubscriberStreamSnapshot` struct 에 `phase: SubscribeState` 필드 추가
4. `impl SubscriberStream::snapshot()` 본문에 동일 패턴

**검증**: `cargo build --release` 통과. 단위 테스트 영향 없음.

### Phase B: admin.rs 의 직접 접근 제거

**대상 파일**: `crates/oxsfud/src/signaling/handler/admin.rs`

**자리** (사전 점검 §0 #2 grep 결과):
- Room scope tracks 빌더 (`admin.rs:31` 추정)
- User scope tracks 빌더 (`admin.rs:317` 추정)
- User scope sub_streams 빌더 (`admin.rs:357` 추정)
- 기타 직접 접근 자리

**작업**:
1. 각 자리에서 `stream.phase.load(Ordering::Relaxed)` → `snap.phase` 로 변경
2. `PublishState::from_u8(...)` 분리 호출 제거 — DTO 가 이미 enum 보유
3. JSON 직렬화: `"publish_state": snap.phase.as_str()` 로 통일

**검증**: `cargo build --release`. admin snapshot JSON 출력 형식 *기존 그대로* (필드 값/타입 무변경).

### Phase C: hooks::ctx() warn 로그

**대상 파일**: `crates/oxsfud/src/hooks/mod.rs`

**작업**:
1. `ctx()` 함수 본문에서 `None` 반환 분기 직전 `OnceLock<()>` 기반 *최초 1회만* warn 로그
2. 로그 메시지 예: `"hooks::ctx() called before hooks::init(); hook handlers will no-op until init is called"`
3. 테스트 환경 (init 미호출) 에서도 *최초 1회만* 발동 → 테스트 출력 폭주 없음

**검증**: `cargo test --release -p oxsfud` 통과. 테스트 출력에 warn 1자리 등장 OK.

### Phase D: 대시보드 시각화 (oxlens-home)

**대상 파일**:
- `oxlens-home/demo/admin/render-overview.js`
- `oxlens-home/demo/admin/snapshot.js` (필드 매핑 확인, 필요 시 추가)

**작업**:
1. `render-overview.js` 상단에 `publishStateColors` / `subscribeStateColors` 객체 추가 (§3.3 매핑)
2. tracks 행 렌더 자리에서 *kind / ssrc / publish_state* 한 줄 표현 — dot 색상 매핑
   ```js
   const ps = t.publish_state || "created";
   const pscls = publishStateColors[ps] || publishStateColors.created;
   return `<span class="... ${pscls}" title="publish_state: ${ps}">● ${t.kind}</span>`;
   ```
3. sub_streams 행 렌더 자리에서 *subscribe_state* 동일 패턴
4. `snapshot.js` 의 필드 매핑 확인 — `publish_state` / `subscribe_state` 가 *통과* 되는지 (직접 접근이면 OK, 매핑 누락이면 추가)

**검증**: 부장님 환경에서 admin 대시보드 새로고침 → tracks / sub_streams 각 dot 색상 표시 확인.

### Phase E: 검증

```bash
# sfu-server
cargo build --release
cargo test --release -p oxsfud  # 252+ tests PASS

# 잔존 직접 접근 grep
grep -rn "stream.phase.load\|s.phase.load" crates/oxsfud/src/signaling/handler/admin.rs  # 0건

# admin JSON 출력 형식 — 부장님 환경 수동 확인
# 1. 서버 기동 후 admin WS 접속 → snapshot 메시지의 publish_state / subscribe_state 필드 존재 확인
# 2. 대시보드 새로고침 → tracks/sub_streams dot 색상 표시 확인
```

---

## 5. 변경 영향 범위

### oxlens-sfu-server

| 파일 | 변경 종류 | 예상 줄수 |
|------|---------|------|
| `crates/oxsfud/src/room/publisher_stream.rs` | Snapshot DTO 에 phase 필드 + snapshot() 본문 | +3 / -0 |
| `crates/oxsfud/src/room/subscriber_stream.rs` | Snapshot DTO 에 phase 필드 + snapshot() 본문 | +3 / -0 |
| `crates/oxsfud/src/signaling/handler/admin.rs` | 직접 접근 제거 (4 자리) — snap.phase 사용 | +5 / -15 |
| `crates/oxsfud/src/hooks/mod.rs` | ctx() None 분기 warn 로그 (OnceLock 1회) | +6 / -1 |

### oxlens-home

| 파일 | 변경 종류 | 예상 줄수 |
|------|---------|------|
| `demo/admin/render-overview.js` | tracks/sub_streams 행에 state dot 추가 | +25 / -5 |
| `demo/admin/snapshot.js` | publish_state / subscribe_state 매핑 (필요 시) | +0~5 / -0 |

**총 +47/-21** (sfu-server) + **+25/-5** (oxlens-home). 신규 파일 없음. 클라 wire 영향 0.

---

## 6. 운영 룰 — 경량화

본 작업은 *위험도 낮은 cleanup* 묶음. 정지점 없음. 단:

### 6.1 정지점 없음 — 통합 리뷰

각 Phase 끝나면 commit 후 다음 Phase 자유 진행. *전체 끝나면 통합 리뷰*. 단:
- *위험 phase 발견 시* (DTO 시그니처 변경이 예상보다 큰 영향 발견 등) **즉시 중단 + 보고**

### 6.2 추가 변경 금지 — 부장님 컨펌 후 진행

§5 영향 범위 외 파일 손대지 말 것. 발견_사항으로 보고만.

### 6.3 "2회 실패 시 중단"

같은 컴파일 에러 / 같은 테스트 실패 2회 시도 후 미해결 → 즉시 중단 + 보고.

### 6.4 부장님 작업 중 파일 회피

oxlens-home 의 *부장님이 다른 작업 중인 파일* (Hook Phase 3 의 F15 참조: `core/constants.js`, `core/engine.js`, `core/room.js`, `qa/participant.js`, `qa/test_phase15_smoke.html`) **손대지 말 것**. 본 작업은 `demo/admin/` 자리만.

---

## 7. 기각된 접근법 (반복 제안 금지)

1. **F16 = 서버 출력 중복 cleanup** — 직전 *F16 표현 부정확*. 축 분리 정합 (PROJECT_MASTER §어드민 Cross-Room rev.2 §9.5). 서버 출력 유지 정합
2. **DTO 에 AtomicU8 직접 노출** — DTO 는 시점 캡처. atomic 보유 의미 부적합
3. **hooks::ctx() 매 호출 warn** — 로그 폭주 위험. OnceLock 1회만 발동이 정합
4. **publish_state / subscribe_state 별 컬럼 추가** — UI 변경 면적 큼. tracks/sub_streams 행 안 dot 이 자연 (기존 peer_state dot 패턴 확장)
5. **tracks 카드 형태 신설** — 정보 밀도 낮음. 한 줄 dot 표현이 깔끔

---

## 8. 작업 후 산출물

1. **변경된 파일** — 위 §5 표대로
2. **세션 파일** — `~/repository/context/202605/20260517e_admin_cleanup_done.md`
   - 본 지침 기준 실제 변경 내역
   - 발견_사항: 별 문제 발견했지만 본 작업에 박지 않은 항목들
   - 오늘의 기각 후보 / 지침 후보
   - 다음 토픽 후보 (handle_scope_announce_for_room 본문 / F8 GATE:PLI / on_publisher_phase / PTT 비시뮬 RTP 흐름 분석 / set_phase → set_state rename)
3. **SESSION_INDEX.md 갱신** — 한 줄 요약

---

## 9. 시작 전 부장님 확인 사항

- [x] §3.1 snapshot 캡처 시점 (옵션 A)
- [x] §3.2 hooks::ctx() warn 빈도 (OnceLock 1회)
- [x] §3.3 대시보드 dot 색상 매핑
- [x] §6 운영 룰 (정지점 없음, 통합 리뷰)
- [x] §6.4 부장님 작업 중 파일 회피

부장님 *"중요한거 같지 않다, 네가 제안한 방향으로"* 확정. Claude Code 진입.

---

*author: kodeholic (powered by Claude) — 김대리, claude.ai 분석 세션 2026-05-17*
