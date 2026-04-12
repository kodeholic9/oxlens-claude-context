# 20260412e — FloorFsm 항상 생성 + Moderate 슬라이드 네비게이션 규칙화

## 요약
FloorFsm을 Room 생성 시 항상 생성하도록 변경하여 모든 참가자가 floor 상태를 관찰할 수 있게 함. Moderate 데모의 슬라이드 네비게이션을 2규칙 체계로 정리. PTT 버튼 상태 동기화 버그 수정. 청중 발화 시 로컬 카메라 표시 추가.

## 완료된 수정

### 1. FloorFsm 항상 생성 (SDK 3파일)

**문제**: FloorFsm이 half-duplex pipe가 있을 때만 생성 → 진행자/다른 청중이 floor:state를 수신 못함 → showVideo/hideVideo 트리거 불가

**해법**: FloorFsm과 PowerManager 생명주기 분리
- FloorFsm: Room 생성 시 항상 생성 → Room.teardown() 시 파괴
- PowerManager: half-duplex pipe 조건부 attach/detach (기존대로)

**수정 파일:**
| 파일 | 변경 |
|------|------|
| `core/room.js` | FloorFsm import 추가, 생성자에서 항상 생성/attach, hydrate needsFloor 제거, applyDuplexSwitch → powerAction 반환 |
| `core/engine.js` | FloorFsm import 삭제, joinRoom/SWITCH_DUPLEX에서 floor 생성 제거 → power만 관리 |
| `core/moderate.js` | FloorFsm import 삭제, authorized/unauthorized에서 floor 생성/파괴 제거 → power만 관리 |

### 2. Moderate 데모 raw 이벤트 → 공개 이벤트 전환

`_floor:taken_raw`/`_floor:idle_raw`/`_floor:revoke_raw` → `floor:taken`/`floor:idle`/`floor:revoke`
- SDK 경계 위반 해소 (TODO 항목 완료)

### 3. PTT 버튼 상태 동기화 버그 수정

**문제**: PTT 버튼 `pttActive` 상태가 클릭과 moderate:unauthorized에서만 리셋 → floor:idle/revoke 시 버튼이 발언중 상태로 고정

**수정**: `floor:state` 핸들러 추가 → talking/requesting이 아닌 상태로 전이 시 버튼 리셋

### 4. 청중 발화 시 로컬 카메라 표시

**문제**: floor:taken에서 내가 발화자일 때 pttVideoPipe(서버 relay)를 마운트 → SFU는 내 영상을 나에게 relay 안 함 → 검은 화면

**수정**: 
- half duplex: floor:taken에서 `d.speaker === s.userId`이면 로컬 카메라 stream으로 video element 생성
- full duplex: moderate:authorized에서 로컬 카메라를 내 슬라이드에 즉시 mount

### 5. 슬라이드 네비게이션 2규칙 체계

**기존**: 7곳의 goSlide가 `aud-slide-mod`/`mod-slide-local` 하드코딩

**규칙 1 (우선, authorization 기반)**:
- 슬라이드 생성 → `goSlide(tgt, 생성된 id)` — 즉각
- 슬라이드 삭제 → `goToNearestAuthorized(tgt)` — authorized 슬라이드 있으면 거기로, 없으면 진행자/로컬
- floor:idle/revoke → `goToNearestAuthorized(tgt)` — 규칙 1 폴백

**규칙 2 (부차, 화자 기반)**:
- `active:speakers` (op=144, RFC 6464 오디오 레벨) → 최상위 화자 슬라이드로 이동
- **2초 debounce** — 화자가 안정될 때만 이동, 빠른 교대 시 캐러셀 고정
- floor:taken에서 goSlide 제거 (active:speakers가 통합 담당)

**유틸 함수:**
```javascript
function goToNearestAuthorized(tgt) {
  const slide = document.querySelector(`#${tgt} [data-authorized]`);
  if (slide) { goSlide(tgt, slide.id); return; }
  goSlide(tgt, tgt === "aud-slides" ? "aud-slide-mod" : "mod-slide-local");
}
```

**active:speakers 설계 배경:**
- 서버 500ms 주기, 변경 시에만 전송 (delta)
- half-duplex: gated audio라 floor holder만 감지 → floor:taken과 동일 효과
- full-duplex: 오디오 레벨로 감지 → floor:taken으로 커버 안 되는 영역
- 통합: active:speakers 하나로 half/full 모두 커버

## 수정 파일 목록

| 파일 | 변경 |
|------|------|
| `core/room.js` | FloorFsm import+항상 생성, hydrate needsFloor 제거, applyDuplexSwitch powerAction |
| `core/engine.js` | FloorFsm import 삭제, power만 조건부 attach |
| `core/moderate.js` | FloorFsm import/생성/파괴 삭제, power만 관리 |
| `demo/scenarios/moderate/app.js` | raw→공개 이벤트, floor:state PTT 버튼, 로컬 카메라, goToNearestAuthorized, active:speakers |

## 기각된 접근법
- **FloorFsm 없이 floor:taken/idle을 Engine에서 직접 emit** — FloorFsm 항상 생성이 더 단순. 상태머신이 이미 있으니 활용
- **floor:taken으로 슬라이드 네비게이션** — full-duplex 화자 커버 불가. active:speakers가 통합 커버

## 교훈
- FloorFsm = "내 발화권 관리" + "방의 발화 상태 관찰" 두 역할. 후자는 모든 참가자에게 필요
- PowerManager와 FloorFsm 생명주기는 분리가 정답 (결합도 낮추기)
- 서버 opcode 전체를 파악해야 설계가 나옴 (active:speakers 존재를 늦게 발견)
- 슬라이드 네비게이션은 규칙 기반으로 정리해야 조건 폭발 방지

## 미해결
- **2차 authorize 검은 화면**: Chrome transceiver inactive→active 재활용 시 렌더 파이프라인 미연결 (이전 세션에서 이관)
- **E2E 테스트**: 금번 변경사항 전체 시나리오 검증 (다음 세션)

---
*author: kodeholic (powered by Claude)*
