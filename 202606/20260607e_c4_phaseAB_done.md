// author: kodeholic (powered by Claude)
# 완료보고 20260607e — C4(장치) Phase A+B (DeviceManager 본체 — 안전부)

> 작업지침: `design/20260607_client_api_c4_work_order.md` Phase A·B(결재 C4-1 단일 / C4-3 requestPermissions). 설계: `20260606_client_api_c4_device.md`.
> 작업지침 분할대로 **이번 세션 = A+B(§5.4 무관 안전부)**. **Phase C(입력전환 §5.4 — local-pipe+power, 위험 집중)는 별 세션·별 커밋**.

---

## 결론

C4 **Phase A(상수) + B(DeviceManager 본체 — 열거/출력/핫플러그) 완결.** 레거시 core/device-manager.js 이식 + 신규 보강(#10 normalize / #11 label gUM 제어 / #7 핫플러그 보호). **입력전환(§5.4)은 자리만(Phase C).** mock 8종 ALL PASS(기존 7 + 신규 _c4_check). **커밋 안 함**(검토 후 GO).

변경: home 5파일 수정 +197/−6, 신규 1(_c4_check.mjs).

---

## 구현

| Phase | 항목 | 파일 | 한 일 |
|---|---|---|---|
| A | 상수 | `constants.js`+`index.js` | `DeviceEvent`(CHANGED/LIST/DISCONNECTED/PERMISSION) 신설 + `DeviceKind`=DEVICE_KIND 별칭. `DeviceError`(media-acquire) index 재노출 |
| B | DeviceManager 본체 | `media/device-manager.js`(stub→본체) | **deps 주입**({bus,acquire,localEndpoint,env,rooms} — engine 통째 금지). 열거 refreshDevices/list/active. 출력 switch(AUDIO_OUTPUT)→setSinkId 순회+setOutputMuted/Volume. 핫플러그 `env:devicechange` 구독. 권한 재노출(device:permission_changed→PERMISSION). on/off facade |
| B | #10 normalizeDeviceId | `device-manager.js` | `active(kind)` = 'default'→groupId 역해석 실 deviceId |
| B | #11 label gUM 제어 | `device-manager.js` | `list(kind,{requestPermissions})` — label 비고 requestPermissions 면 gUM 1회→재열거. 무조건 gUM 금지(C4-3) |
| B | #7 핫플러그 보호 | `device-manager.js` | 입력장치 분리 시 **자동 재획득 안 함(통지만)** — BYO/screen track 보호. 출력만 default 폴백 |
| B | engine 배선 | `engine.js` | `engine.device`=DeviceManager 인스턴스. connect 에 `env.start()`+`device.start()`, disconnect 에 `device.stop()`+`env.stop()` |

---

## ★ 부수 배선/발견

- **env.start() 미호출 발견 → engine.connect 에 추가.** 실측: `EnvAdapter.start()` 가 어디서도 안 불려 **env:\* 전부 휴면**이었음(C4 핫플러그 + PTT Power 의 env:visibility/netchange 반응까지). C4 핫플러그(env:devicechange) 위해 connect 에 `env.start()` 추가 → **부수효과로 PTT env 반응도 활성**(긍정). disconnect 에 env.stop().
- **발견_사항(미수정, production 무해): `EnvAdapter.start()` 가 `window`(online/offline) 를 typeof 가드 없이 참조.** 브라우저엔 window 항상 존재라 무해하나, document 만 있고 window 없는 환경(일부 node 테스트 목)에선 ReferenceError. 모듈 주석 원칙("typeof 가드 후에만")과 어긋나는 잠복 — **별 토픽 후보**(본 작업서는 _c3_check mock 에 window 추가로 우회, EnvAdapter 무수정).

---

## 경계/불변 (작업지침 §0.5 준수)

- 출력 element 소유 = RemotePipe(C3 0 변경). device 는 rooms 순회만(`*_outputElements()` 읽기).
- devicechange = `env:devicechange`(EnvAdapter 경유) — 직접 navigator 이벤트 구독 0. enumerate 는 query 라 직접(가드 + `_enumerate` seam).
- 권한 = MediaAcquire 단독. device 는 PERMISSION 재노출만.
- cross-sfu 무관(장치=로컬 입력단). 입력전환 §5.4·swapTrack·power = Phase C(미착수).

---

## 검증

- `node --check` 4파일 PASS.
- **mock 8종 ALL PASS**: 기존 7(회귀 0) + **신규 `_c4_check`**.
- `_c4_check`: #11 list(권한없이 gUM 0 / requestPermissions gUM 1회+label) / #10 active('default')→실 deviceId / switch(AUDIO_OUTPUT)→setSinkId+CHANGED / setOutputMuted·Volume / switch(AUDIO_INPUT)=Phase C false / **#7 입력 분리=통지만(자동 재획득 0)**+LIST{removed} / 권한 재노출.

---

## 미착수 (Phase C — 별 세션·별 커밋, 위험 집중)

- **§5.4 입력 전환** — `LocalPipe.setInputDevice(track)` 신설(trackState별 분기 ①ACTIVE swapTrack+constraints / ②SUSPENDED _savedTrack 교체 / ③RELEASED savedConstraints) + **power.js audio 비대칭(_buildAudioOverrides)** + 트랙조작 직렬화락(C2 §6-D 공유). **PTT 마이크가 SUSPENDED/RELEASED서 조용히 안 바뀌고 옛 device 발화하던 실결함.** local-pipe+power 동시 변경이라 격리.
- D 후순위(#15 모바일 재획득 / OS 기본장치 label 변경).

---

## ★ 종결

- **[결재]** home 5파일+신규1 diff 검토 후 GO → 한 커밋(+ context done).
- **[보고]** 다음 = **Phase C(입력전환 §5.4 — local-pipe+power, PTT device 전환 결함 해소)**. 작업지침대로 별 세션.
- **[질문]** EnvAdapter window 미가드(발견_사항) — 별 토픽으로 1줄 가드 고칠지(권장) 판단 주시면 처리.

---

*author: kodeholic (powered by Claude)*
