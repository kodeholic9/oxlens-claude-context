// author: kodeholic (powered by Claude)
# 2026-06-12b 클라 미디어 평면 감사 + 오디오 패스 업계 조사

## 세션 성격
분석/조사 세션 (코딩 없음 — 맥북 부재 대부분, 부장 소스 첨부로 진행).
대상: `media-acquire.js` / `local-endpoint.js` / `local-pipe.js`(+`pipe.js`) 결함 발굴
     + 오디오 디바이스 권한·라우팅 업계 조사(권한 거부 / 블루투스 / setSinkId / iOS26).
직전 `20260610_client_send_room_review`(engine/talkgroups/transport/sdp-builder)의 미디어 평면 후속.

---

## 다룬 것 (순서)
1. 권한(permission) 거부 처리 — denied 복구 / 설정 이동 / 브라우저별 안내
2. `_gumWithTimeout` 필요성·결함
3. 카메라 전·후면 전환(facingMode) — replaceTrack 만으로 되나
4. MediaStream / `syncStream` 정체 (브라우저 셀프뷰 어댑터)
5. 블루투스/이어셋 입력 — 입력 전환 대응 유무
6. 오디오 라우팅 업계 조사 (LiveKit / Daily / mic-check / iOS26)
7. `local-pipe` 게이트 본체 분석 (미뤄둔 4개 확인 닫기)

---

## 확정 결함 (전부 local-endpoint 조립층 — local-pipe 본체는 건전)

### ① `_publishCamera` SUSPENDED 미처리 — 진짜 결함 (우선순위 높음)
- `getPipeBySource`는 `p.active` 필터, `_publishCamera`는 `trackState===ACTIVE` 로만 early return.
- `active=true && trackState=SUSPENDED` 인 pipe 가 **두 판단 사이로 샘** → early return 못 타고 새 `acquire.video()`+`_publishOne`.
- local-pipe 에 `resume()` 이 멀쩡히 있는데 **우회**하고 새로 만듦 → 옛 pipe 는 release/deactivate 안 거쳐 `_serial.terminate()` 도 안 됨 → `_heldTrack`+SerialLock+transceiver/sender 통째 좀비.
- 실제 경로: device-mute suspend(블루투스/OS 회수, `_attachTrackLifecycle`) 후 카메라 재시도.
- 올바른 분기: ACTIVE→return / SUSPENDED→`resume()`(재acquire 금지) / INACTIVE·dead→정리 후 재발행.

### ② 블루투스 영구 분리 fallback 부재 — 진짜 결함 (full-duplex)
- 분리 → `_heldTrack` ended → `resume()` 이 `need_track` 반환 → RELEASED.
- **새 device acquire 트리거가 full-duplex 엔 없음.** PTT 는 floor grant(`setPendingInputDevice`→power) 가 트리거지만 일반 통화는 트리거 부재 → RELEASED 로 멈춤 → 통화 침묵.
- `_attachTrackLifecycle` 의 `onmute→suspend` 가 "일시 상실"과 "영구 분리"를 미구분.

### 새 발견 — SUSPENDED 누락의 근원 = 선택 축 혼용
- `getPipeBySource`(active 축) vs `_publishCamera`(trackState 축) **두 축 혼용**이 ① 의 근원.
- 서버 "분류 권위 단일" 원칙의 클라 위반. pipe 선택을 한 축으로 통일 필요(getPipeBySource 를 trackState 기반으로 가든가, _publishCamera 가 둘 다 보든가).

---

## 부차 / 미완성 (오작동 아님 or 완성도)
- `unpublishVideo` Map 미삭제 → deactivate 가 `active=false` 라 getPipeBySource 안 걸림. **오작동 아님, Map 좀비 누수만.** (어제 "좀비 출처 둘" 정밀화: 진짜는 ① suspend 케이스, unpublish 는 부차.)
- `_gumWithTimeout` — liveness guard 정당하나 (a)`Promise.race` 진 쪽(getUserMedia) 취소 안 함 → timeout 직후 늦게 resolve 된 track orphan 누수(카메라 LED 잔존), 특히 "hang 아닌 느린 디바이스" (b)5초가 "드라이버 hang"과 "사용자 팝업 고민" 미구분, Safari 특히. "짜다 만" 코드.
- 전면 디폴트 미보장 — `media-acquire.video()` base 에 `facingMode` 없음 → 브라우저 기본(전면 보장 X). `{ideal:"user"}` 추가 필요.
- `_stream` 에 audio track 섞임 — 셀프뷰 어댑터(video)와 생명주기 일괄정리(all)를 한 객체가 겸해 정의 흐림. 우선순위 낮음.

---

## 긍정 — local-pipe 정교 (개판 아님)
미뤄둔 4개 확인 전부 **건전**으로 닫힘:
- `swapTrack`→`_mountTrack`→`sender.replaceTrack(track)` + `track`=`sender.track??_heldTrack` 파생 getter 자동 반영 (헌법 제1·2조). SerialLock 직렬.
- `suspend`/`resume` — SerialLock+epoch 종단으로 "큐 잔여 resume 이 죽은 pipe 되살리는 interleaving 구멍"까지 막음.
- `setTrack`/`holdRtp` — `replaceTrack(null)` 차단 → ok 후 `setTrack` 시작. 건전.
- **입력 전환 pipe 게이트 이미 완성**: `setInputDevice`(ACTIVE, 기존 constraints 재적용·deviceId 제외) + `setPendingInputDevice`(SUSPENDED/RELEASED, PTT 꺼진 장치 안 깨우고 다음 grant 때 acquire). 어제 "입력전환 미구현"은 정밀히는 **pipe 게이트 완성 + DeviceManager 상위 정책만 빔** = 절반 구현.

→ 결함은 전부 조립층(local-endpoint)이 부품 미사용. 처방 = 재설계 아닌 **"있는 게이트로 재배선" 3~4곳.** local-pipe 는 손대지 말 것.

---

## 오디오 패스 결론 — 업계 따라가기로 충분 (부장 결정)

### 업계 실측 (LiveKit / Daily / mic-check / iOS26)
- **입력 우선순위 자동(BT>유선>내장)**: LiveKit 도 안 함 — `switchActiveDevice(kind,deviceId)`로 OS default 추종 + 사용자 선택. AudioSwitch 식 우선순위 매니저는 웹 SDK 누구도 SDK 레벨 미구현(네이티브 전용).
- **출력 라우팅**: 데스크톱 setSinkId 만. **Android 모바일 불가**(client-sdk-js #1507 — 블루투스 출력 안 됨, audiooutput 목록 빈 채). 블루투스 분리 시 오디오 멈춤은 **LiveKit 도 버그**(#1220 — 우리 `_attachTrackLifecycle` 결함과 동일).
- **iOS 26 변화**: Safari 26 Speaker Selection API 로 이어피스/스피커/BT 전환 웹 지원 시작(#1568), 단 SDK 적용 과도기(meet.livekit 목록은 뜨나 실제 전환 미적용).
- **권한 거부**: denied 는 코드로 팝업 재호출/설정 이동 불가(브라우저 보안). chrome://·about: 네비 차단. 텍스트 안내가 최선(업계 공통). Daily 는 ua-parser-js 로 브라우저/OS 감지 + `blockedBy`(user vs OS 차단) 구분. mic-check 매트릭스 = OS-level("by system")/browser-level 별 에러 문자열 상이(같은 NotAllowedError 도 "by system" 유무로 갈림, Windows 는 NotReadableError). Safari 는 Permissions API 미지원 → 우리 `_refreshPermission`/`_watchPermission` 무력.

### 정책 매핑 (부장 우선순위: 입력 BT>이어셋>내장 / 출력 무전=스피커·통화=이어피스)
| | 데스크톱 웹 | Android 웹 | iOS 웹 |
|---|---|---|---|
| 입력 우선순위 | 수동(OS default+deviceId) | 동일 | 동일 |
| 출력 무전=스피커/통화=이어피스 | setSinkId(이어피스 개념 없음) | **불가** | **iOS26+만** |

### 함의 (전략)
- 웹 = 데스크톱 관제/디스패치(setSinkId 가능), 모바일 현장 = 네이티브(oxlens-sdk-core + AudioSwitch). 웹으로 모바일 출력 욕심 → 막힘.
- 이 영역은 LiveKit 과 동일 벽 — 우리 뒤처짐 아님.

---

## 오늘의 기각 후보
- **오디오 입력 우선순위 자동 매니저(AudioSwitch 식) 자체 구현** — 업계 누구도 웹 SDK 레벨 안 함. OS default + 사용자 선택이 표준. 네이티브 전용. 깊은 토끼굴, 파봐야 OS 미개방이면 헛수고.
- **모바일 출력 라우팅(무전=스피커/통화=이어피스) 웹 강제** — setSinkId 모바일 불가(Android), iOS26+ 만 차차. 플랫폼 천장. 모바일 현장 = 네이티브 확정.
- **권한 거부 시 설정 화면 자동 이동** — chrome://·about: 네비 차단으로 웹 불가. 텍스트 안내가 최선(Meet/Zoom/Daily 공통). (Tauri/Electron 데스크톱 래핑 시엔 OS 설정 deep link 가능 — 미래 옵션.)

## 오늘의 지침 후보
- **오디오 패스 = "업계 따라가기"로 충분** — 입력 deviceId 전환(switchActiveDevice 동급) + 분리 fallback 시도만 채우고, 우선순위 자동/모바일 출력은 보류(플랫폼 개방 대기). 깊은 토끼굴 금지.
- **결함은 조립층이 부품 미사용** — 재설계 아닌 "있는 게이트로 재배선". local-pipe 정교하니 손대지 말 것.
- **엣지 = PTT 제품 본체** — 권한/디바이스/블루투스는 화상회의보다 PTT 에서 우선순위 높음(현장 이어셋 필수). "happy path 통과 = 완료" 금지.
- **pipe 선택 축 단일화** — getPipeBySource(active) vs trackState 혼용 차단. 서버 "분류 권위 단일"의 클라판.

---

## 이월 (다음 세션 진입 거리)
- `_publishCamera` SUSPENDED→resume 재배선 (+ 선택 축 단일화)
- 블루투스 분리 fallback (full-duplex: resume need_track → 내장 마이크 자동 acquire 트리거)
- `_gumWithTimeout` orphan cleanup + timeout 값/구분
- `media-acquire.video()` base 에 `facingMode:{ideal:"user"}` (전면 디폴트)
- 입력 전환 상위 정책 — DeviceManager 가 setInputDevice/setPendingInputDevice 호출하는 트리거(devicechange 정책: 자동/사용자선택/하이브리드 — 부장 [택1] 미결)
- 카메라 전환 외부 API — `switchCamera()`(모바일)+`setVideoInput(deviceId)`(데스크톱), 둘 다 restartTrack 수렴
- (확인) `unpublishVideo` Map 미삭제 좀비 정리 여부 (부차)

※ 갭 진열 단일 출처 = `context/202605/20260523_session_gap_inventory.md` — 위 이월 항목 반영은 부장 지시 후.

---

*author: kodeholic (powered by Claude)*
