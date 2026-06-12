// author: kodeholic (powered by Claude)
# 2026-06-12c 클라 미디어 평면 결함 수정 + 장치 정책 하이브리드 + blockedBy 분류

## 세션 성격
구현 세션 — 직전 감사(`20260612b_client_media_plane_audit_audiopath`)의 이월 전량 소화.
대상 레포: oxlens-home (커밋 3: `6d6ba08` 결함수정+정책 / `02d5cbb` tests 일원화 / blockedBy 1건).

---

## 한 것 (순서)

### 1. 감사 이월 ①~⑤ + 추가 발견 2건 — `6d6ba08`
- **① pipe 소생(`_revivePipe`)**: publishAudio/_publishCamera 가 신규 발행 전 trackState **전체 분기**.
  ACTIVE→skip / SUSPENDED→resume(재acquire 0) / RELEASED→재장착(같은 sender=같은 SSRC, 협상 0,
  PUBLISH_TRACKS 불요 — release 가 sender 를 unbind 안 하고 setTrack 이 RELEASED→ACTIVE 허용이라
  경로가 이미 열려 있었음) / INACTIVE→신규 발행. **publishAudio 에도 동일 구멍 있었음(감사 누락) — 같이 닫음.**
  camera 소생 시 CAMERA_READY 재송신(PLI 보험).
- **② 영구 분리 fallback(`_recoverPipe`)**: full-duplex 한정. onended + resume()=="need_track" 트리거 →
  savedConstraints 재acquire, 실패 시 deviceId 제거 **1회만** 재시도(OS default=내장 마이크).
  half(PTT)는 비개입 — 다음 floor grant 의 power 경로 유지. acquire 중 deactivate 경합 부활 금지 가드.
- **③ `_gumWithTimeout`**: timeout 이원화 — granted(팝업 없음, hang 감지)=5s / prompt(팝업 고민,
  Safari 포함)=60s, 모듈 상수. race 패배 후 늦은 resolve stream 의 track 전부 stop(LED 잔존 해소).
  gum 승리 시 timer 해제(살아있는 stream 오살 방지).
- **④ 전면 디폴트**: video base 에 `facingMode:{ideal:"user"}` (overrides 가 이김, ideal=soft).
- **⑤ unpublish Map 정리**: `_deletePipe`(trackId/`m:{mid}` 키 모두) + lifecycle 잔여 timer 해제.
- **추가 1 — restartTrack/applyInputTrack 옛 track 정지**: 미정지 시 카메라 LED/마이크 hot 잔존.
- **추가 2 — lifecycle 교체 정리(`_lifecycles` Map)**: track 교체 시 이전 track 의 잔여 debounce
  timer 가 새 track 실은 pipe 를 suspend 하는 오발동 차단. teardown 일괄 해제.

### 2. 장치 정책 결정 + 구현 ⑥⑦ — 같은 커밋
- **부장 결정: devicechange = 하이브리드** (감사 이월 [택1] 해소).
  - 명시 선택 無 → **OS default 추종**(`_followDefault`): default 실 id 변경 감지(normalize 전후 비교)
    → ACTIVE 입력 pipe 만 전환. 같은 장치/실패 시 현 장치 유지(멱등·통화 보호). PTT suspended 안 깨움.
  - 명시 선택 有 → 고정. 그 장치 분리 시에만 해제(disconnected 통지) → 추종 모드 복귀.
    track 사망 복구는 ②(_recoverPipe)가 담당 — DeviceManager 는 선택 상태만 관리.
- **⑦ 카메라 전환 API**: `LocalStream.switchCamera()`(facingMode user↔environment 토글) +
  `setVideoInput(deviceId)` — 둘 다 restartTrack 수렴(같은 SSRC, 협상 0).
- **`applyInputTrack`(LocalEndpoint) 신설**: 장치 전환 적용 단일 경로 — setInputDevice +
  lifecycle 재부착 + _stream 동기화 + 옛 track 정지. DeviceManager._switchInput 의 빠진 고리
  (옛 track 미정지 + lifecycle 미부착) 동시 해소.

### 3. 검증 스크립트 일원화 — `02d5cbb`
- sdk/·domain/·transport/ 에 흩어진 `_*_check.mjs` 19개 → **`sdk/tests/`** (git mv, `_` 접두사 제거,
  import 경로 출신별 수정).
- **브라우저 probe 폐기 3건**(부장 지시): `_t2a_check.html`(event-bus 폐기로 이미 파손),
  `t3b2_pubseq.html`+`t3b2_cdp.mjs`(결론은 _publishMany mid 가드에 반영 완료) —
  **브라우저 시험은 e2e/ 하위 일원화 방침.**
- 교훈: 첫 커밋에 git mv 스테이징분만 들어가고 sed 수정이 빠짐 → amend 보정. mv 후 수정 시 add 재확인.

### 4. mic-check 차용 — blockedBy 안내처 분류 (이 세션 마지막 커밋)
- **출처 정정(부장)**: mic-check 는 Daily 아닌 Glimpse 팀(helenamerk). Daily 는 별도 blockedBy+ua-parser.
- **통째 흡수 기각** — 결정적 사유: mic-check 의 `requestMediaPermissions()`가 **자체 getUserMedia 호출**
  → "gUM 직접 호출 금지, MediaAcquire 단일 게이트" 불변원칙 정면 충돌. bowser 의존도 불요(자체 UA 2줄).
- **매트릭스만 차용, 단 축 분리**(mic-check 와의 차이): code(복구 카테고리) 보존 + `BlockedBy` 별도 축.
  mic-check 는 FF NotFound 를 SystemPermissionDenied 로 code 자체를 덮음 — 진짜 장치없음과 뭉개짐.
  우리는 code=NOT_FOUND 유지 + blockedBy=system **힌트**.
  | blockedBy | 의미 | 안내처 |
  |---|---|---|
  | system | 영구 — OS 가 브라우저 차단(macOS) | 시스템 설정 |
  | user | 영구 — 팝업/사이트 차단 | 브라우저 자물쇠 |
  | dismissed | 일시 — 팝업 닫음(Chromium, mic-check 에 없는 추가) | 재시도 |
  | null | 판별 불가(추측 금지 — OS 차단자에게 자물쇠 안내가 최악) | 복합 안내 |
- 부수 수정: AbortError→IN_USE 매핑 추가 / **dismissed 는 denied 캐시 금지**(기존엔 팝업만 닫아도
  영구 거부로 캐시돼 다음 acquire 사전 차단되는 결함).
- Safari 커버: Permissions API 부재로 _refreshPermission 무력 → gUM catch 의 이 분류가 유일 신호.

---

## 결정 사항 (부장)
- devicechange 정책 = **하이브리드** (자동/수동 기각).
- **축 완전 단일화(active 파생 getter) 기각** — publish 진행 구간(active=true+INACTIVE)은 의도된
  어긋남(등록 축 vs 미디어 축). 합치면 screen 이중 발행 가드 파손 + base Pipe까지 침습(재설계 급).
  방어는 getPipesBySource 경고 주석("active 선택 + trackState 전체 분기")으로 종결.
- mic-check 통째 흡수 기각(위 사유).

## 검증
- 글루 검증 19/19 PASS (mp_check 신설 — 50 체크: 소생/복구/half 비개입/fallback/Map 정리/
  gum orphan/facingMode/하이브리드 추종·고정/switchCamera/blockedBy 매트릭스).
- wire 계약 무변경(서버 op 0 변경). 로컬 이벤트 추가 필드만: device `changed{reason:"os_default"}`,
  acquire `error/permission_required{blockedBy}`.

## 이월 / 기록
- **UA 스니핑 3곳 중복** (pipe.js/device-manager.js/media-acquire.js 각자 _isSafari 류) — shared/ua.js 통합 후보.
- blockedBy 의 UI 소비(안내문 분기)는 앱 영역 — SDK 는 분류·통지까지.
- 실기기 확인 필요(글루 검증 밖): 실제 블루투스 연결/분리, iOS Safari, Chrome 메시지 휴리스틱 버전 의존.
- core/ 의 `.test.mjs` 4개는 co-located 유지(부장 별도 지시 시 이동).

---

*author: kodeholic (powered by Claude)*
