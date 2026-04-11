# 세션 컨텍스트: Track Mount/Unmount 설계 방향 확정

> 2026-04-11 | Phase 47 (continued) | author: kodeholic (powered by Claude)

---

## 작업 요약

1. **PTT 슬라이드 버그 분석** — moderate 캐러셀에서 PTT 슬라이드가 2번째 speaker부터 노출 안 되는 문제
2. **근본 원인 발견** — PTT virtual SSRC가 동일하므로 ontrack 재발생 불가. rmSlide로 DOM 제거하면 복구 불가
3. **hidden 토글 시도** — display:none이 snap scroll + indicator 깨뜨림
4. **SDK/app 경계 재정립 논의** — app이 너무 많은 raw 이벤트를 종합하고 있음
5. **LiveKit 패턴 조사** — track.attach()/detach() 패턴 확인
6. **Track Mount/Unmount 설계 방향 확정** — SDK가 video element 소유, 전 시나리오 동일 패턴

## 확정된 설계 방향

### track.mount() / track.unmount() 패턴

| 영역 | 책임 |
|---|---|
| **SDK** | 트랙별 video element 생성/소유, srcObject 연결, ontrack 처리, freeze masking |
| **SDK** | `track.mount()` → element 반환, `track.unmount()` → 정리 |
| **SDK** | Conference든 PTT든 동일 패턴 |
| **SDK** | local track mount 시 muted=true 자동 (하울링 방지) |
| **app** | element 받아서 어디에 넣을지 (캐러셀, 그리드, PttPanel 등) |
| **app** | `floor:taken/idle` 받아서 PTT element를 DOM에 넣고 빼기 |
| **app** | 슬라이드 모양, indicator, 스와이프, 레이아웃 |

### PTT element 2개
- **내꺼**: 내 카메라 영상 (talking 시 노출)
- **남의꺼**: virtual track 영상 (listening 시 노출)

### 전 시나리오 동일 패턴

| 시나리오 | 내꺼 | 남의꺼 | 트랙 수 |
|---|---|---|---|
| Conference | 내 카메라 element | 참가자별 element | N개 |
| 영상무전 | 내 카메라 element | PTT virtual element | 1개 |
| Moderate | 내 카메라 element | PTT virtual + 진행자 element | 2개 |
| Dispatch | 내 카메라 element | 현장요원별 element | N개 |

### app에서 사라지는 것
- `isPtt` 분기
- `_floor:taken_raw` / `_floor:idle_raw` / `_floor:revoke_raw` 내부 이벤트 소비
- `moderate:speakers` 슬라이드 생명주기 해석
- ontrack 타이밍 큐잉 (`_pendingTracks`)
- PTT slide DOM 생명주기 관리 (hidden/display 토글)

## 버그 분석 기록

### PTT 슬라이드 NOT FOUND 버그
- **증상**: 청중A 발언→해제→청중B 발언 시 진행자 캐러셀에 B 슬라이드 안 보임
- **원인**: `moderate:speakers` 빈 목록 시 `rmSlide("mod-slide-ptt")` → DOM 제거. PTT virtual SSRC 동일하므로 ontrack 재발생 불가 → 슬라이드 재생성 불가
- **시도 1**: rmSlide 제거 → 결과: 발언 해제 후 frozen frame 잔류
- **시도 2**: hidden class 토글 → 결과: snap scroll indicator 불일치, grant/revoke 반복 시 꼬임
- **근본 해법**: SDK가 video element 소유 + app이 appendChild/removeChild (track.mount/unmount 패턴)

### visibility:hidden 학습
- ptt-panel.js의 freeze masking 패턴에서 사용
- `display:none` — 공간 자체 사라짐 (레이아웃에서 빠짐)
- `visibility:hidden` — 공간 유지하되 안 보임 (디코더 동작 유지)
- Vue로 치면 `v-if` vs `v-show`

## LiveKit 이벤트 조사 결과

LiveKit RoomEvent 32개, ParticipantEvent 20+개. 전부 raw 이벤트 기반.
- TrackSubscribed/Unsubscribed — 우리 media:track / tracks:update와 유사
- ActiveSpeakersChanged — 정렬된 speaker 배열 제공
- track.attach() → SDK가 video element 생성/반환, app이 DOM에 삽입
- track.detach() → SDK가 srcObject 정리, app이 DOM에서 제거
- mediasoup-client는 더 로우레벨 — Transport/Producer/Consumer 단위 이벤트만

## 오늘의 기각 후보

| 기각 | 이유 |
|---|---|
| PTT 슬라이드 rmSlide | virtual SSRC 동일 → ontrack 재발생 불가 |
| PTT 슬라이드 hidden 토글 | snap scroll + indicator 불일치 |
| app에서 floor raw 이벤트 직접 소비 | SDK 내부 이벤트가 app에 새는 구조 |
| app에서 moderate:speakers 슬라이드 생명주기 해석 | DOM-as-state 구조 → 이벤트 순서에 취약 |
| SDK 컨테이너 팩토리 콜백 | 업계 표준 아님. LiveKit도 track 단위 |

## 오늘의 지침 후보

- **track.mount()/unmount() 패턴** — SDK가 video element 소유, app은 DOM 위치만 결정
- **Conference/PTT/Moderate 동일 패턴** — app 입장에서 local이든 remote든 PTT든 구분 없음
- **PTT virtual track의 DOM은 절대 제거하지 않는다** — 이동만 (appendChild/removeChild)
- **`_` prefix 이벤트는 app이 소비하지 않는다** — SDK 내부에서 종합 후 의미 있는 이벤트로 변환

## 다음 세션 우선순위

1. **track.mount()/unmount() SDK 구현** — client.js에 Track 클래스 추가, video element 소유
2. **moderate app.js 단순화** — mount/unmount 패턴 적용, isPtt/floor raw/speakers 로직 제거
3. **E2E 테스트** — grant/revoke 반복, half/full 혼합, 3명 이상
4. **다른 시나리오 확산** — conference, radio, dispatch에 동일 패턴 적용

## 변경 파일 목록

### 수정된 파일
- `demo/scenarios/moderate/app.js` — moderate:speakers rmSlide 제거 + hidden 토글 시도 (미완성, 롤백 필요)

### 코드 변경 없음 (설계 논의 세션)
- track.mount()/unmount() 패턴은 다음 세션에서 구현

---

*v1.0 — 2026-04-11*
