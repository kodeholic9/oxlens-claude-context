# 세션 컨텍스트: Moderate 시나리오 UX 개선 + Grant Duplex + Subscribe-only 버그 수정

> 2026-04-11 | Phase 47 (continued) | author: kodeholic (powered by Claude)

---

## 작업 요약

1. **캐러셀 UX 개선** — IntersectionObserver 활성 슬라이드 추적, 수동 스와이프 3초 억제, 슬라이드 간 시각적 분리(w-11/12, rounded-lg, scroll-padding)
2. **Grant duplex 전달** — Hub session.rs + handler.rs + moderate.js + app.js 전 경로 duplex 필드 추가
3. **Subscribe-only SDP 버그 수정** — 트랙 없이 publish PC 생성 시 BUNDLE 에러 → lazy pubPc 생성
4. **PTT userId `__ptt__` 제거** — `isPtt` 플래그 기반 판별로 전환, PTT virtual track 슬라이드 처리
5. **media:track 타이밍 버그** — ontrack이 room:joined보다 먼저 발생 → _pendingTracks 큐 + 재처리
6. **슬라이드 정리** — 회수 시 PTT/사용자 슬라이드 제거 (moderate:speakers + tracks:update)
7. **진행자 캐러셀 floor 이벤트** — idle/revoke 시 내 카메라 복귀 (mod-slide-local id 추가)

## 완료된 변경 (확정)

### 서버 (oxhubd, 2파일)

#### session.rs
- `authorized_speakers: HashMap<String, (Vec<String>, String)>` — kinds + duplex 튜플
- `grant()` → duplex 파라미터 추가, 반환값 3-tuple
- `speakers_list()` → duplex 필드 포함

#### handler.rs
- `parse_duplex()` 헬퍼 추가 (기본값 "half")
- grant 액션: duplex 파싱 + authorized 이벤트에 duplex 포함

### SDK 코어 (3파일)

#### media-session.js
- `setup()`: subscribe-only(stream 없음) 시 `_setupPublishPc()` 생략
- `publishAudioTrack()`: `throw "not ready"` 제거, `!_pubPc`이면 lazy 생성
- ontrack: `userId = "__ptt__"` → `userId = null` (isPtt 플래그로 판별)

#### client.js
- PTT 오디오 엘리먼트 키: `"__ptt__"` → `"ptt"`

#### moderate.js
- `grant()`: duplex 파라미터 추가
- `_onAuthorized()`: `d.duplex || "half"` 사용 (하드코딩 제거)
- PTT attach: half-duplex일 때만 (full이면 자유발언)

### 데모 (2파일)

#### moderate/index.html
- 진행자 첫 슬라이드: `id="mod-slide-local"` 추가
- 캐러셀 컨테이너: `scroll-padding-inline:4%; padding-inline:4%` (좌우 여백)
- 슬라이드: `w-11/12 rounded-lg overflow-hidden mx-1` (시각적 분리)
- 청중 캐러셀: `flex-1 + aspect-ratio:16/9 wrapper` (길쭉함 방지)

#### moderate/app.js (major)
- `_carouselState` + `IntersectionObserver` 활성 슬라이드 추적
- `_bindSwipePause()` 수동 스와이프 3초 auto-swipe 억제
- `_pendingTracks[]` 큐 + room:joined 후 재처리 (ontrack 타이밍 버그)
- `isPtt` 기반 PTT 슬라이드 생성 (`__ptt__` 제거)
- `grantUser()` → duplex 전달
- `moderate:authorized` → `d.duplex || "half"` 사용
- `moderate:speakers` → 빈 목록 시 PTT/사용자 슬라이드 제거
- `tracks:update(remove)` → 사용자 슬라이드 제거
- `_floor:idle_raw/_floor:revoke_raw` → 진행자 `mod-slide-local` 복귀
- `video:enabled` → 내 슬라이드로 auto-swipe
- 디버그 로그: `[DBG:CAROUSEL]`, `[DBG:FLOOR]`, `[DBG] participant raw`, `[DBG] media:track`

## 발견된 문제 + 해결

| 문제 | 원인 | 해결 |
|---|---|---|
| Subscribe-only SDP BUNDLE 에러 | 빈 offer에 m-line 없음 | setup()에서 pubPc 생략, publishAudioTrack에서 lazy 생성 |
| 진행자 영상 청중에서 안 보임 | ontrack이 room:joined보다 먼저 발생 → role 판별 실패 | _pendingTracks 큐 + 재처리 |
| PTT userId `__ptt__` | 가상 트랙에 실제 user_id 부여 | `isPtt` 플래그 기반으로 전환 |
| 청중B에 발언자 패널 안 보임 | PTT virtual track `userId=null` → participants 미존재 → 큐 갇힘 | `isPtt` 체크를 participants 체크 앞에 배치 |
| 회수 후 슬라이드 잔류 | PTT/사용자 슬라이드 제거 로직 부재 | moderate:speakers 빈 목록 + tracks:update(remove) 처리 |
| 진행자 idle 시 복귀 실패 | 첫 슬라이드에 id 없음 → goSlide id="" | `id="mod-slide-local"` 추가 |
| 진행자 캐러셀 시각적 안 움직임 | goSlide OK 로그 나오지만 scrollIntoView 미동작 의심 | **미해결** — 다음 세션 검토 |

## 오늘의 기각 후보

| 기각 | 이유 |
|---|---|
| `__ptt__`를 userId로 사용 | 가상 트랙에 실제 user_id 부여는 설계 오류. `isPtt` 플래그가 정답 |
| participants 맵 기반 role 판별만 의존 | ontrack 타이밍 문제. 큐잉 필수 |
| removeVideoTrack("camera") = mute 패턴으로 회수 | tracks:update(remove) 안 옴 → speakers 목록 기반 정리가 필수 |

## 오늘의 지침 후보

- **PTT virtual track은 `isPtt` 플래그로 판별** — userId를 부여하지 않는다
- **ontrack은 room:joined보다 먼저 발생할 수 있다** — participants 의존 로직은 큐잉 필수
- **moderate 회수 = camera mute 패턴** — tracks:update(remove)가 아닌 speakers 목록으로 슬라이드 정리
- **캐러셀 슬라이드에는 반드시 id 부여** — goSlide 타겟으로 사용

## 다음 세션 우선순위

1. **캐러셀 실제 스크롤 동작 검증** — goSlide OK 로그지만 진행자 캐러셀이 시각적으로 안 움직인다는 보고 → scrollIntoView + snap 컨테이너 구조 검토
2. **E2E 테스트** — 리팩터링된 코드 전체 시나리오 검증
3. **디버그 로그 정리** — 안정화 후 [DBG] 로그 제거
4. **SKILL_OXLENS.md 업데이트** — `isPtt` 패턴, subscribe-only lazy pubPc, _pendingTracks 큐

## 변경 파일 목록

### 서버
- `crates/oxhubd/src/moderate/session.rs`
- `crates/oxhubd/src/moderate/handler.rs`

### SDK 코어
- `core/media-session.js`
- `core/client.js`
- `core/moderate.js`

### 데모
- `demo/scenarios/moderate/index.html`
- `demo/scenarios/moderate/app.js`

---

*v1.0 — 2026-04-11*
