# 20260426e QA §G UI 시각 검증 3건 (Phase 66)

> Phase 65 후속. 라이브 큐 §G 3/3 — UI 시각 검증 항목 (G-1 위치 룰 / G-2 audio-only video panel / G-3 오버레이 방 정보) 모두 처리. SDK Pipe API 1건 확장 (`Pipe.roomId`) + QA UI cell 구조 변경 + INV 5건 신설로 **다음 시험부터 자동 적용**.

---

## 처리 결과 요약

### §G 3건 처리 완료

| ID | 항목 | 변경 범위 | 검증 |
|---|---|---|---|
| G-1 | 위치 룰 (half=1행, full=2행) | 변경 없음 (이미 정합) | INV-14/15/16 신설 |
| G-2 | audio-only video panel 자동 생성 | `participant.js` (placeholder 헬퍼) | INV-18 |
| G-3 | 오버레이 방 정보 (cross-room 식별) | SDK `Pipe.roomId` 노출 + UI hdr 갱신 | INV-17 |

**부장님 결정 (옵션 A)**: G-3 은 SDK 에 `Pipe.roomId` 노출하는 방식. 옵션 B (QA UI 자체 추적) 기각 — 깔끔성 우선, 다른 앱에서도 활용 가능.

---

### G-3 SDK 변경 (Pipe.roomId 노출)

**핵심 의미 결정**: `pipe.roomId` = recv pipe 가 어느 Room 의 `hydrate` / `applyTracksUpdate` 시점에 도착했는지. cross-room 시 같은 user 의 다른 SSRC track 이 다른 Room 에 hydrate 되면 각각 그 Room 의 roomId 가짐. send pipe / PTT virtual 은 null (의미 모호).

**3개 파일 변경**:

```
oxlens-home/core/pipe.js     — 생성자 opts.roomId 추가, JSDoc 갱신
oxlens-home/core/room.js     — hydrate / applyTracksUpdate 의 ep.addPipe 3개 호출처에 roomId: this.roomId 주입
                                (1) hydrate 첫 분기
                                (2) applyTracksUpdate add 의 recycled (recyclePayload)
                                (3) applyTracksUpdate add 의 new
```

기각된 path:
- send pipe 에 owner Room.roomId 박는 path → cross-room scope 모델에서 send pipe 가 여러 방에 select 되면 한 roomId 로 표현 못 함. 의미 모호.
- 모든 등장 방의 set 으로 박는 path → 시험 단순화 위해 첫 등장 방만 박음.

### G-3 UI 변경

```
oxlens-home/qa/participant.js
  - attachMounted: cell.dataset.roomId = pipe.roomId || '' (G-3 cross-room 식별)
  - _rxHdr: 시그니처 변경 (userKey → cell). 헤더 라인 = `RX <userKey> / <roomId>`
  - refreshStats 호출처: _rxHdr(userKey) → _rxHdr(cell)
```

### G-2 audio-only video panel 자동 생성

**핵심 의미**: audio-only user (mic half 단독 spawn, camera 없음) 도 video panel 자동 생성 + 오버레이에 user/방 정보 표시. 부장님 요구 = "audio-only 도 video panel 무조건 생성".

**1파일 변경**:

```
oxlens-home/qa/participant.js
  - _placeholderId(userId) 헬퍼
  - _createAudioOnlyPlaceholder(pipe, container) — audio recv pipe 도착 시 마이크 아이콘 placeholder cell 생성
  - _removeAudioOnlyPlaceholder(userId) — video pipe 도착 시 같은 user 의 placeholder 제거 (자동 통합)
  - attachMounted 의 video 분기 진입 시: pipe.userId 의 placeholder 제거
  - attachMounted 의 audio 분기 진입 시: pipe.userId 의 placeholder 자동 생성
```

기각된 path:
- user 단위 cell 통합 관리 (userCells: Map<userId, cell>) → 구조 재설계 정도 큰 변경. 단순 placeholder 자동 생성/제거로 의미 충족 → 채택.
- placeholder cell 의 video element 자리에 audio meter UI → 단순 마이크 아이콘만 박음 (1단계). 추후 G-2 보강 (audio level 시각화) 별도 round.

### G-1 위치 룰 (검증 logic 만)

**SDK/UI 이미 정합** — participant.html CSS grid (1행: local + half / 2행: full grid-column 1/-1), participant.js attachMounted 의 분기 (half→halfWrap, full→fullWrap).

**신규 검증 logic 만 추가**: `99_invariants.md` 의 INV-14~18 + measurement helper.

```
INV-14: half-wrap cell 의 dataset.duplex === 'half'
INV-15: full-wrap cell 의 dataset.duplex === 'full'
INV-16: full-wrap top ≥ half-wrap bottom (CSS grid layout 무결성, getBoundingClientRect)
INV-17: recv cell 의 dataset.roomId 비어있지 않음 (G-3, PTT virtual 제외)
INV-18: audio-only placeholder dataset 무결성 (G-2)
```

5건 모두 `checkInvariants()` 헬퍼에 추가 → 다음 시험 cycle 자동 적용.

---

## 변경된 파일 목록

```
oxlens-home/core/pipe.js                  (Pipe 생성자 opts.roomId, JSDoc)
oxlens-home/core/room.js                  (3개 ep.addPipe 호출처에 roomId 주입)
oxlens-home/qa/participant.js             (cell.dataset.roomId, _rxHdr, _createAudioOnlyPlaceholder/_removeAudioOnlyPlaceholder)

qa/catalog/10_sdk_api.md                  (Pipe 속성 표 userId/roomId 분리, 항목 갯수 17→18, 헤더 갱신)
qa/catalog/40_qa_ui.md                    (QA UI cell.dataset 섹션 신설, RX overlay hdr 명세, 헤더 갱신)
qa/checks/99_invariants.md                (UI 시각 구조 섹션 신설 INV-14~18, checkInvariants 헬퍼 갱신, 항목 갯수 13→18)

qa/README.md                              (§G 3/3 처리 완료, 다음 시험 default sentinel INV 갯수 13→18, 마지막 갱신 Phase 66)
context/202604/20260426e_qa_section_g_visual.md   (이 파일, 신규)
context/SESSION_INDEX.md                  (Phase 66 추가, 통계 229→230)
```

---

## 라이브 큐 변동 (5건 영역 진행 중 + 16건 잔여 → 13건)

| 영역 | Phase 65 후 | Phase 66 후 |
|---|---|---|
| §A/§B/§C/§D/§E | 0/0/0/0/0 | 0/0/0/0/0 |
| §F | 4 | 4 |
| **§G** | **3** | **0** ✅ |
| §H | 4 | 4 |
| §I | 5 | 5 |

---

## 오늘의 지침 후보 (3건)

### 1. SDK API 확장 결정 시 cross-room 모델 정합성 우선 검증

옵션 A (`Pipe.roomId` 노출) 진행 시 다음 의문이 떠올랐다 — "cross-room 시 같은 user 의 미디어가 두 방에 동시 도착하면 어떻게 분류?"

→ scope 모델 fact 확인 (`PROJECT_MASTER.md`): 같은 sfud 내 cross-room 도 SSRC 재사용 금지. 즉 다른 SSRC = 다른 transceiver = 다른 hydrate path. 따라서 `roomId = hydrate 시점의 Room.roomId` 정의가 정확.

지침: SDK API 추가 시 cross-room / multi-room 행동 fact 를 먼저 확인 — 의미 모호한 API 는 추가하지 않음. (이번엔 정합성 확인 후 채택. 만약 같은 SSRC 가 다른 방에 라우팅되는 모델이었다면 단일 roomId 표현 자체가 오해 유발 → API 형태 재설계 필요.)

### 2. UI 시각 검증은 INV 형태로 박혀야 default 적용

§G 같은 "다음 시험 default" 항목은 시험 logic 측 ad-hoc 검증보다 INV 로 박는 게 정합. 시험 logic 측 검증은 매 시나리오마다 작성자가 명시 호출해야 — 누락 위험. INV 로 박으면 `checkInvariants()` 가 매 시나리오 종료 시 자동 호출 → 누락 0.

INV 박기 적정 후보: 무결성 sentinel (값이 비어있지 않음), 구조적 불변식 (DOM layout, 자료구조 일관성). 동적 행동 검증 (이벤트 순서, timing) 은 INV 가 아닌 시험 logic.

### 3. 큰 구조 재설계 안건은 "단순 path" 와 "이상적 path" 분리

§G G-2 의 경우 두 가지 구현 path:
- **단순**: audio pipe 마다 placeholder cell 자동 생성 + video pipe 도착 시 자동 통합 (이번 채택)
- **이상**: user 단위 cell 통합 관리 (userCells Map) + audio/video pipe 가 같은 cell 안에 합쳐지는 구조

이상 path 는 코드 변경 폭 큼 (~100줄). 의미 충족 측면에서는 단순 path 면 충분 (audio-only 시 video panel 자동 생성 OK). 이상 path 는 audio level 시각화 등 보강 시 별도 round.

지침: 단순 path 먼저 박고 의미 충족 확인. 이상 path 는 별도 round 로 미루는 게 부장님 답답함 + 검증 부담 감소.

---

## 다음 세션 후보 (잔여 라이브 큐 = 13건)

| 후보 | 분량 | 비고 |
|---|---|---|
| **§D + §G 시험 cycle** | 1일 | Playwright MCP 시험 — 인프라 sanity check + 결과 ✅/⚠️ 기록. INV-14~18 자동 검증 포함. fault hook 5종 + UI invariant 5종 |
| **§F 결함 의심 4건** | 1일+ | F-12 priority preemption / server-side stale / RV-09 zombie timing / G3-02·03 capture constraint |
| **§H 환경 불변 4건** | 반나절 | 정합 확인만 |
| **§I 품질 카테고리 (Tier 1~3)** | 반나절~1일+ | 영업 자산. 별도 세션 |

권장: **§D + §G 시험 cycle** — 인프라 박힌 직후 검증해야 hook + INV 동작 확인 + 결과 기록.

---

## 한국어 escape 정리 (재학습)

이번 round 에서 README 의 한 글자가 깨진 byte 로 보임 (`영���` ← read_text_file 출력). 우회 위해 §G 헤더 + 3개 [ ]→[x] 항목만 anchor 잡아 정정 (깨진 라인은 그대로 유지). edit 결과 diff 보니 깨진 글자가 정상 한글로 복원됨 — read 출력의 ��� 표시가 반드시 invalid byte 가 아님.

지침: read_text_file 의 ��� 출력 → 반드시 invalid byte 라고 단정하지 말 것. 우회 anchor 사용 후 결과 diff 로 raw 확인.

---

*author: kodeholic (powered by Claude)*
