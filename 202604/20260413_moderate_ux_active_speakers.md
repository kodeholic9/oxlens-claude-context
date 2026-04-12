# 20260413_moderate_ux_active_speakers — Moderate UX 개선 + active:speakers 연동

## 요약
Moderate 시나리오의 화자 정보(active:speakers) 연동, 슬라이드 라벨 체계, 청중 화면 2단 구조, 진행자 다중 지원 등 전반적 UX 개선. 2차 authorize 검은 화면 버그는 half/full 모두 동일 증상 확인 — 미해결 이월.

## 완료된 수정

### 1. active:speakers 연동 (signaling + app.js)
- `signaling.js` op=144에 console.log 추가 (디버깅용, 추후 제거)
- **서버 ingress.rs 확인**: `!track_type.is_half()` 필터로 half-duplex audio는 speaker_tracker 미포함 — 의도된 동작
- **speakerSlideId() 헬퍼**: userId→slideId 매핑, role과 특수 슬라이드(mod-slide-local, aud-slide-me) 고려
- **setSlideGlow/clearAllGlow**: CSS `speaking-glow` 클래스 (::after 가상 요소, z-index:20, border 3px solid green)
- **_currentFloorSpeaker**: PTT floor holder 추적 → active:speakers 빈 배열이 floor:taken glow를 삭제하는 문제 방지
- **debounce 버그 수정**: 같은 화자면 타이머 리셋 안 함 (`_speakerNavTarget` 비교)

### 2. 슬라이드 라벨 체계
- `slideLabel(userId)` 헬퍼: "내 카메라" / "진행자(U111)" / "청중(U222)"
- 모든 addSlide/addAuthorizedSlide 호출에 적용

### 3. 고정 aud-slide-mod 제거 → 동적 슬라이드
- HTML에서 `aud-slide-mod` 제거, `_modSlideUserId` 상태 삭제
- 모든 참가자(진행자 포함) `aud-slide-{userId}` 동적 생성
- 진행자 다중 입장 지원 — 각각 별도 슬라이드

### 4. 청중 화면 2단 구조 (5:5)
- 상단 `aud-slides-mod`: 진행자 슬라이드 + `aud-empty-mod` 빈 상태 안내
- 하단 `aud-slides-aud`: 청중/내카메라 슬라이드 + `aud-empty-aud` 빈 상태 안내
- `audTarget(userId)` 헬퍼: role에 따라 상/하단 라우팅
- 슬라이드 추가/제거 시 `updateAudEmptyMsg()` 호출로 빈 상태 토글

### 5. 슬라이드 크기/비율
- `w-[55%] h-[85%]`: 한 화면에 1.5~2개 슬라이드 보임
- `items-center`: 캐러셀 내 수직 중앙 정렬
- video `object-fit:cover`로 비율 자연 처리

### 6. 진행자 빈 상태/퇴장 처리
- 진행자 없을 때: 배경에 "진행자 입장 대기 중" 안내 (슬라이드 아닌 배경)
- 진행자 퇴장: `hasModeratorInRoom()` 체크 → 0명이면 플레이스홀더 복원
- 참가자 영역 Half/Full/회수 버튼 제거 (손든사람/발언자격자 영역에서만 조작)

## 수정 파일 목록

| 파일 | 변경 |
|------|------|
| `core/signaling.js` | op=144 console.log 추가 |
| `demo/scenarios/moderate/index.html` | speaking-glow CSS, aud-slide-mod 제거, 2단 구조(aud-slides-mod/aud-slides-aud), 빈 상태 안내, 슬라이드 크기 |
| `demo/scenarios/moderate/app.js` | speakerSlideId, slideLabel, audTarget, updateAudEmptyMsg, setSlideGlow(CSS class), _currentFloorSpeaker, debounce 수정, 동적 진행자 슬라이드, 참가자 버튼 제거, cleanup 정리 |

## 기각된 접근법
- **Tailwind ring-2/ring-inset로 화자 glow** — box-shadow는 video(position:absolute) 아래에 그려짐. outline도 동일 문제. ::after 가상 요소가 정답
- **aspect-video로 슬라이드 비율 강제** — 세로 빈 공간 과다. h-[85%] + object-fit:cover가 실용적

## 교훈
- active:speakers(500ms 주기)와 floor:taken은 독립 소스 → 충돌 방지 상태 필요 (_currentFloorSpeaker)
- debounce에서 "같은 값 반복 수신 시 타이머 리셋" = 영원히 만료 안 됨. 동일 대상이면 기존 타이머 유지
- CSS ::after + z-index가 position:absolute 자식 위에 그리는 가장 확실한 방법
- 고정 슬롯(aud-slide-mod)보다 동적 생성이 다중 진행자/유연한 UI에 유리

## 미해결
- **★ 2차 authorize 검은 화면**: revoke 후 재 grant 시 video 미표시. half(PTT)뿐 아니라 full에서도 동일 증상. Chrome transceiver inactive→active 재활용 시 렌더 파이프라인 미연결. 이전 세션(20260412d)에서 이관. Twilio#931 동일 증상.
- `signaling.js` console.log 제거 (디버깅 완료 후)

---
*author: kodeholic (powered by Claude)*
