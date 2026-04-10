# 20260329 — 잔여 업무 현행화 + 화면공유 클라이언트 source 파이프라인

## 작업 요약

### 잔여 업무 현행화
이전 세션들의 완료 여부를 부장님과 확인하여 정리:
- 블로그 Velog 게시: ✅ 완료 (피드백 아직 없음)
- Active Speaker 화자인식: ✅ 완료
- PLI Governor Phase 2: ✅ 완료 (재확인 필요)
- SKILL_OXLENS.md 반영: ✅ 완료
- Git commit: ✅ 완료
- 멀티 채널 / 프로세스 분리 / oxrecd: 📋 추후

### 서버 화면공유 로그 확인
3/29 서버 로그에서 화면공유 E2E 정상 동작 확인:
```
PUBLISH_TRACKS user=U996 tracks=3 video_sources=[camera(mid=1,pt=109,rtx=114), screen(mid=2,pt=109,rtx=114)]
[STREAM] NEW video (mid=2) ssrc=0xA00B1EBF user=U996 pt=102
[STREAM:REG] track registered source=Some("screen") codec=H264
TRACKS_UPDATE(add) kind=video ssrc=0xA00B1EBF gate_paused=true
```
U512도 동일 패턴 정상.

### 화면공유 클라이언트 source 파이프라인 (코딩 완료)

**문제**: ontrack → media:track 이벤트에 source 정보 누락. screen 트랙이 camera 스트림을 덮어쓰는 문제.

**수정 3개 파일:**

| 파일 | 변경 |
|------|------|
| `core/media-session.js` | ontrack에서 `e.transceiver.mid` → `_subscribeTracks` 매칭으로 source 추출. `media:track` 이벤트에 source 필드 추가 |
| `demo/client/app.js` | source="screen" 분기 + 별도 키(`userId_screen`) 저장 + `tiles.addScreenTile()`. `tracks:update` 리스너로 screen 제거 감지 |
| `demo/client/tile-manager.js` | `_screenShareUid` 상태, `addScreenTile`/`removeScreenTile` export, `_resolveMainUid`에 screen 우선순위, simulcast 대상 제외, 퇴장 시 자동 정리, `reset` 추가 |

### 화면공유 레이아웃 설계 (미확정)
- 화면공유 시 어디에 노출할지
- 기존 카메라는 어디에 노출할지
- 해제 시 카메라 레이아웃 복원 방식
→ 부장님 레이아웃 확정 후 E2E 시험 예정

## 다음 세션 TODO
1. **화면공유 레이아웃 설계 확정** → 코드 반영 → E2E 시험
2. **PLI Governor Phase 2 재확인**
3. **SKILL_OXLENS.md 반영** (이번 세션 변경사항 — 아래 블록 참조)

## 기각된 접근법
- 없음 (이번 세션은 현행화 + 기존 설계 기반 코딩)

---
*author: kodeholic (powered by Claude)*
