# 20260426 P-07 Fix + §A Catalog 보정 (Phase 62)

> Phase 61 후속. P-07 클라이언트 결함 fix + 부수발견 fix (camera unpublish 비대칭) + §A 5건 catalog 보정.

---

## 처리 결과 요약

### 1. §A catalog 사실 mismatch — 5건 처리

`qa/catalog/10_sdk_api.md` (4건) + `qa/catalog/11_events.md` (1건):

| # | 항목 | 변경 |
|---|---|---|
| 1 | `Pipe.mount()/unmount()` 시그니처 | 인자 없음 + LiveKit owner 패턴 + `_attachTrack` 비고 추가 |
| 2 | `MediaAcquire (engine.acquire)` 신규 섹션 | `audio()/video()/screen()` 반환 = `{track, stream}` wrapper, throw `DeviceAcquireError`, emit 3종 |
| 3 | `subscribeLayer` rid 표기 | `h/m/l/pause` → `h/l/pause` (m 제거, 2계층 + pause) |
| 4 | `addVideoTrack(source, opts)` | `enableScreen/disableScreen` 같은 별도 메서드 없음 명시. screen 워크플로 = `addVideoTrack('screen')` 단일 호출 |
| 5 | `engine.scope.on('changed')` cause | "현재 cause = `'user'` 단일" 명시. SDK 는 서버 `d.cause` pass-through |

`qa/README.md` 라이브 큐 §A 에서 5건 제거. scope.panRequest 함정은 잔존 (지금 미진행).

### 2. P-07 클라이언트 결함 fix — `pipe.deactivate()` 에 `pipe.active = false`

**원인**: `getPublishedTracks()` 필터 = `direction==='send' && p.active`. `pipe.deactivate()` 가 `trackState=INACTIVE` 만 설정하고 `pipe.active` 는 그대로 true 유지 → `state().published` 가 stale.

**Fix** (`oxlens-home/core/pipe.js`):
```js
deactivate() {
    ...
    this.trackState = TrackState.INACTIVE;
    this.active = false;   // ★ 추가 — getPublishedTracks/hasPipe/getSendPipes 등 필터 정합
    ...
}
```

**Cleanup** (`oxlens-home/core/endpoint.js`): `_unpublishScreen` 의 redundant `pipe.active = false` 제거 (이제 deactivate 가 자동 처리).

### 3. ★ P-07 부수발견 fix — `_unpublishCamera` 가 `unpublishTracks` 미호출

**진짜 원인**: SDK `_unpublishCamera` 가 `_notifyMuteServer('video', true)` (MUTE_UPDATE) 만 보내고 `engine.nego.unpublishTracks()` 를 호출하지 않음. 주석에 `BWE preserved` 명시.

| | mic | **camera** | screen |
|---|:---:|:---:|:---:|
| 서버 통보 (PUBLISH_TRACKS remove) | ✅ | **❌ MUTE_UPDATE 만** | ✅ |

**결과**: 클라는 disable 했는데 서버 admin tracks 에 video 트랙 stale (5초 후도 동일). 서버는 정상 — SDK 가 안 보낸 것. mic/screen 과 비대칭.

**Fix** (`oxlens-home/core/endpoint.js` `_unpublishCamera`):
- `_notifyMuteServer('video', true)` 제거
- `engine.nego.unpublishTracks([{ kind: 'video', source: 'camera' }])` 추가

**BWE 보존 의도는 보존됨** — `pipe.deactivate()` 가 `sender.replaceTrack(null)` 만 하고 transceiver/m-line 은 살림. 다음 `_publishCamera` 의 Resume 분기 (`existing.sender` 분기) 에서 setTrack 만으로 재사용. 즉 transceiver 수준의 BWE estimator 는 유지, 트랙 메타데이터만 서버에 정확히 통보.

### 4. Playwright 검증 — 모든 단계 client = server 일치

```
joined-only         server[]                            client[]                          ✅
enable mic          server[audio]                       client[audio/mic]                 ✅
enable camera       server[audio, video/camera]         client[audio/mic, video/camera]   ✅
disable mic         server[video/camera]                client[video/camera]              ✅
disable camera      server[]                            client[]                          ✅ ★
re-enable both      server[audio, video(새 SSRC)]       client[audio/mic, video/camera]   ✅
re-disable both     server[]                            client[]                          ✅
```

### 5. 부수효과 — §F 의심 2건 자동 해소

| ID | 의심 내용 | 해소 |
|---|---|---|
| §F #B | disable mic 가 새 video SSRC 등록 만드는 부작용 | ✅ 사라짐. disable-camera 가 unpublish 안 보내서 생기는 SDP mid/SSRC 동기화 mismatch 였음 |
| §F #C | spawn-only 에 video/camera 트랙 자동 등록 | ✅ 사라짐. 이전 세션 zombie 잔재로 추정. fresh navigate 후 안 발생 |

### 6. PowerManager 분석 — 삭제 (4/26 부장님 지시)

> "파워매니저 정합은 당장 볼일 없어". 이 서브섹션에 있던 분석 결과(HOT/HOT_STANDBY/COLD 3상태 + `mute/unmute` 의미 + `toggleVideo` 이전 의문점)는 기록에서 제거. 해당 작업 자체가 차우선순위 하락.

---

## 변경된 파일 목록

```
oxlens-home/core/pipe.js                               (P-07: deactivate에 active=false)
oxlens-home/core/endpoint.js                           (_unpublishScreen redundant 제거 + _unpublishCamera unpublishTracks 호출)
context/qa/catalog/10_sdk_api.md                       (§A 4건)
context/qa/catalog/11_events.md                        (§A scope cause)
context/qa/README.md                                   (라이브 큐 §A 5건 제거)
```

---

## 라이브 큐 변동 (`qa/README.md`)

- §A: 14건 → 9건 (5건 처리, scope.panRequest + Admin/Lifecycle/Power/Video 식별 등 잔존)
- §E: 3건 → 2건 (P-07 제거. S-08, PW-08 잔존)
- §F: 4건 → 2건 (#B, #C 자동 해소. F-12 preemption, RV-09 zombie timing 잔존)

---

## 핵심 학습 / 지침 후보

### 1. "비대칭은 결함 신호" — 같은 도메인의 메서드가 다른 패턴이면 90% 결함

P-07 의 진짜 결함은 클라 stale (`pipe.active`) 이 아니라 **`_unpublishCamera` 가 mic/screen 과 비대칭** 인 것이었다. `BWE preserved` 주석이 의도를 명시했지만, transceiver 보존은 `pipe.deactivate()` 의 `replaceTrack(null)` 으로 이미 달성됨 → MUTE_UPDATE 만 보내고 PUBLISH_TRACKS(remove) 를 빼는 건 의도와 무관한 손실. 같은 도메인 (audio/video/screen unpublish) 의 비대칭은 즉시 의심해야 함.

**지침 후보 → 같은 카테고리의 메서드들이 서로 다른 서버 통보 패턴을 보이면 일단 결함으로 가정. "의도된 비대칭" 주장은 두 메서드가 의도 측면에서도 명확히 다른 도메인일 때만 인정.**

### 2. "표면 결함과 진짜 결함의 거리" — 클라이언트 stale 뒤에 서버 비동기

P-07 처음 정의는 클라 `state().published` stale. fix 후 검증 중 "admin tracks 에 video 트랙 잔존" 발견 → 서버측 결함 가설 → 서버 코드 분석 → SDK 가 unpublishTracks 안 보낸다는 진짜 원인. **클라 fix 만으로는 불완전, 서버까지 통합 검증해야 진짜 fix**.

### 3. "재현 환경의 cleanliness" — 이전 세션 잔재가 의심을 만든다

§F #C (spawn-only video 트랙 자동 등록) 는 이전 세션의 zombie 잔재였음. 시험 시작 시 `q.reset()` + `await q.sleep(2500)` + fresh `q.spawn` 패턴으로 깨끗한 시작 보장. 의심 항목 분석 시 "환경 변수" 먼저 제거.

### 4. "BWE 보존" 의 진짜 메커니즘은 transceiver 수준

audio 의 BWE 가치 미미 (32~64kbps), video 의 BWE 가치 큼 (수 Mbps). 하지만 **BWE estimator 는 transceiver 의 sender 단위에서 유지** — track 을 null 로 바꿔도 살아있음. 즉 `replaceTrack(null)` + `unpublishTracks` 조합으로도 BWE 보존 + 서버 메타 정합 둘 다 가능. "트랙 메타까지 서버에 보존해야 BWE 산다" 는 잘못된 가정이었음.

### 5. "의미와 동작이 안 맞으면 이름이 잘못됐거나 동작이 잘못됐다"

PowerManager 의 `toggleVideo` 가 그 사례. 이름은 "video 토글" 인데 위치는 PowerManager (전력 관리). 책임 분리 원칙 위배. 부장님 지적: "PowerManager 에서 관리될 사항은 아닌거 같은데". 현재는 땜빵, 정합 후보.

---

## 기각된 접근법 (반복 유혹 높은 것)

- **`disableCamera` 의 `BWE preserved` 패턴 유지** — 부장님 정합 의지 명확. mic/screen 과 동일 패턴이 정답. transceiver 수준 BWE 는 별도로 유지됨
- **`_unpublishCamera` 에 MUTE_UPDATE + unpublishTracks 둘 다 보내기** — 중복. 트랙이 서버에서 사라지는 마당에 MUTE_UPDATE 의미 없음. 순서 race 위험
- **클라 fix (`pipe.active=false`) 만으로 P-07 종결 처리** — 부장님 지적: 서버 propagate 가 진짜 fix 의 핵심. 클라 fix 는 표면 증상 제거에 불과
- **iframe ws.send hook 으로 wire 검증 시도** — controller realm 에서 cross-realm 접근 제약. 코드 증거가 명확하면 wire 검증 안 가도 결론 충분
- **PowerManager `toggleVideo` 즉시 이전** — 부장님 명시 동의 없이 진행 금지. 분석 보고 후 결정 받기 (이번 교훈: 멋대로 수정 시도하다 두 번 까임)

---

## 다음 세션 후보

| 후보 | 공수 | 우선순위 |
|---|---|---|
| **PowerManager `toggleVideo` 이전** | 1~2시간 | 부장님 결정 후 |
| **`power.mute/unmute` 공통함수 위임 정합** | 1~2시간 | mute 의미 결정 후 |
| **§E PW-08** (handle.mute 동작 catalog 불일치) | mute/unmute 정합과 묶음 | |
| **§E S-08** (multi-publisher m-line race) | 1일 | 별도 세션 |
| **§I 품질 카테고리 (Tier 1~3)** | 반나절~1일 | 영업 자산, 별도 세션 |
| **§A 잔여 9건 + scope.panRequest 메서드 분리** | 반나절 | 가벼운 묶음 |
| **§D fault hook 인프라 5건** | 1일 | 다음 cycle 효율 |

권장: 다음 세션 = **PowerManager `toggleVideo` 이전 + `mute/unmute` 정합** 묶음. 부장님이 의문 제기한 핵심 항목.

---

## CHANGELOG 블록 (부장님 카피용)

SDK 변경 기록:

```markdown
## [Unreleased] - Phase 62

### Fixed
- **P-07: `disable('mic'/'camera')` 후 `state().published` stale**.
  `pipe.deactivate()` 가 `trackState=INACTIVE` 만 설정하고 `pipe.active` 는 true 유지하여
  `getPublishedTracks()` / `hasPipe()` / `getSendPipes()` 의 필터링이 stale 항목을 노출하던 버그.
  `pipe.deactivate()` 끝에 `this.active = false` 추가. `_unpublishScreen` 의 redundant 라인 제거.
- **P-07 부수발견: `_unpublishCamera` 가 서버에 `PUBLISH_TRACKS(remove)` 미송신**.
  mic/screen 과 비대칭 (`MUTE_UPDATE` 만 송신). 서버 admin snapshot 에 video 트랙 stale 잔존하던 원인.
  `_notifyMuteServer('video', true)` 제거 후 `engine.nego.unpublishTracks([{kind:'video', source:'camera'}])` 추가.
  BWE 보존 의도는 transceiver/m-line 보존으로 유지 (`replaceTrack(null)` 만 호출, transceiver.stop 안 함).
  다음 `_publishCamera` 의 Resume 분기 (`existing.sender`) 에서 setTrack 만으로 재사용.

### Notes
- 검증: Playwright MCP 로 enable/disable/re-enable 사이클 모두 client = server 일치 확인.
- 부수효과: §F #B (disable mic 가 새 video SSRC 등록) / §F #C (spawn-only 에 video 트랙 자동 등록) 자동 해소.
```

QA catalog 변경 기록:

```markdown
## [Unreleased] - Phase 62 (qa)

### Changed
- §A 5건 catalog 보정: `Pipe.mount/unmount` owner 패턴, `MediaAcquire` 신규 섹션 (`{track, stream}` wrapper),
  `subscribeLayer` rid `h/l/pause`, `addVideoTrack('screen')` 워크플로, `scope.changed.cause = 'user'`.
```

---

*author: kodeholic (powered by Claude)*
