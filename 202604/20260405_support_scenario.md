# 세션 컨텍스트: support 시나리오 + Moderated Floor 설계 검토

> 날짜: 2026-04-05
> 영역: 클라이언트 (oxlens-home) + 서버 설계 검토
> 서버 변경: 없음 (Moderated Floor 시도 → 원복)
> 이전 세션: 20260405_dispatch_scenario.md

---

## 완료 사항

### 1. support_field 프리셋 추가 (presets.js)

```js
support_field: {
  label: "현장기사",
  icon: "ph-wrench",
  audio: { duplex: "full" },
  video: { duplex: "full", simulcast: false },
  screen: null,
}
```

SCENARIOS.support.presets를 `["caster", "video_radio"]` → `["caster", "support_field"]`로 변경.

### 2. support 시나리오 페이지 생성

`demo/scenarios/support/` 디렉토리에 index.html + app.js 신규 작성.

**전문가 (caster 프리셋)**:
- audio=full, video=null, screen=full
- 1:1 Focus 레이아웃: 현장기사 카메라 전체화면
- 컨트롤: 마이크 · 화면공유 토글 · 스피커
- 화면공유 시 헤더에 "화면 공유 중" 인디케이터

**현장기사 (support_field 프리셋)**:
- audio=full, video=full, screen=null
- Screen-First 레이아웃: 전문가 화면공유 전체화면 + 로컬 카메라 PIP
- 컨트롤: 마이크 · 카메라 토글 · 스피커

### 3. 시각적 차별화 (dispatch vs support)

- dispatch: 블루/오렌지 — N명 VideoGrid — PTT(half-duplex)
- support: 에메랄드/시안 — 1:1 Focus — 양방향 음성(full-duplex)

### 4. demo/index.html 업데이트

- 역할 레전드에 `support_field` 뱃지 추가
- support 카드: video_radio → support_field 뱃지, 설명 문구 수정

---

## 설계 판단 기록

### 1:1 full-duplex 선택 이유
- 원격지원은 1:1 — "여기 볼트 보여주세요" "네 이거요?"가 동시 대화
- PTT는 그룹 통신용 — 1:1에서 교대 통화는 부자연스러움

### support_field 프리셋 분리 이유
- field(dispatch용): audio=half → PTT
- support_field: audio=full → 1:1 양방향
- video는 동일(full, sim=off)하지만 audio duplex가 다름

---

## Moderated Floor Control 설계 검토 (미구현 → 원복)

### 시도한 것
panel(사회자+패널) 시나리오를 위해 Moderated Floor Control 서버 구현 시도.
- GrantMode enum (Auto/Moderated)
- FloorConfig.grant_mode 추가
- request() Moderated 분기, _try_grant_next() auto-pop 차단
- moderate_grant(), moderate_deny() 메서드
- FLOOR_GRANT(op=44), FLOOR_DENY(op=45), FLOOR_QUEUE_UPDATE(op=146)
- startup.rs에서 demo_panel만 Moderated로 생성

### 원복 이유
`floor_grant_mode`를 방 레벨에 넣으면 "방은 빈 그릇" 원칙 위반.
진행자를 participant 레벨로 옮기면 인가(authorization) 로직이 필요 → hub 관할.
**hub 없이 sfud에 넣으면 나중에 프로세스 분리 시 뜯어내야 함.**

### 기각된 접근법

| 접근 | 기각 이유 |
|------|----------|
| floor_grant_mode를 Room에 추가 | "방은 빈 그릇" 원칙 위반 — room.mode 제거한 것과 같은 실수 |
| participant.moderator 플래그 | 인가 로직 = hub 관할. sfud에 넣으면 분리 시 재작업 |
| 데모니까 방 레벨로 그냥 넣기 | 시도 후 원복 — 파급 범위가 예상보다 큼 (8파일 변경) |

### Moderated Floor의 올바른 위치
- **oxhubd**에서 인가 → FLOOR_GRANT/DENY를 hub가 검증 후 sfud에 전달
- sfud는 "grant하라는 명령"만 받아서 실행 (지금의 Auto 로직과 동일 구조)
- 프로세스 분리 후 구현이 정답

---

## 수정 파일 목록 (최종)

### 클라이언트 (oxlens-home) — 유지
- `demo/presets.js` — support_field 프리셋 추가, SCENARIOS.support 업데이트
- `demo/scenarios/support/index.html` — 신규
- `demo/scenarios/support/app.js` — 신규
- `demo/index.html` — support_field 뱃지 + support 카드 설명 수정

### 서버 (oxlens-sfu-server) — 전체 원복
- 변경 없음 (git checkout으로 원복 완료)

---

## 다음 세션 TODO

1. **support 시나리오 브라우저 시험** — 전문가+현장기사 동작, 화면공유, 카메라 토글, PIP
2. **panel 시나리오** — Moderated Floor 없이 Auto Grant + 사회자 음성 권위로 먼저 만들기 (서버 변경 제로)
   - 또는 프로세스 분리 후 hub에서 Moderated Floor 구현
3. **SKILL_OXLENS.md 프리셋 테이블** — support_field 행 추가

---

*author: kodeholic (powered by Claude)*
