// author: kodeholic (powered by Claude)
# 완료보고 20260607f — C4(장치) Phase C (입력 전환 §5.4 — PTT 결함 해소) + Phase B 정리

> 작업지침: `design/20260607_client_api_c4_phaseC_work_order.md`(변경 결재 C4-4 deviceId+acquire 타이밍 / C4-2 단일 trackLock). 직전: 0607e(A+B, `cfdb159`).
> C-1(§5.4 본체: local-pipe+power+DeviceManager) + C-2(§0.5 정리 6건). device-manager 가 양쪽 걸쳐 **Phase C 단일 커밋**.

---

## 결론

C4 **입력 전환 §5.4 충돌 ①②③ 해소 — PTT 마이크 전환이 조용히 깨지고 옛 device 로 발화하던 실결함 종결.** + Phase B 정리 6건. mock 9종 ALL PASS(기존 8 + 신규 _c4c_check, 회귀 0). **커밋 안 함**(검토 후 GO).

변경: home 7파일 수정 +182/−66, 신규 1(_c4c_check.mjs).

---

## C-1 본체 (§5.4)

| 항목 | 파일 | 한 일 |
|---|---|---|
| **setInputDevice(track)** | `local-pipe.js` | ACTIVE 전용 — swapTrack(replaceTrack, encoding 보존) + **① 기존 constraints 재적용**(deviceId 제외 — 새 device 유지) |
| **setPendingInputDevice(deviceId)** | `local-pipe.js` | **SUSPENDED/RELEASED 전용 — acquire 0**(PTT 꺼진 장치 안 깨움). _savedTrack stop+RELEASED 전이 + savedConstraints.deviceId 예약(C4-4) |
| **③ _trackLock** | `local-pipe.js` | 단일 직렬화 큐(C4-2). 교체류(setTrack/suspend/resume/swapTrack/setInputDevice/setPendingInputDevice/pauseUpstream/resumeUpstream) 직렬. power `_resumePipe`의 resume() 도 관통(power 무수정) |
| **audio 비대칭 해소** | `power.js` | `_buildAudioOverrides`(_buildVideoOverrides 대칭) + `_doEnsureHot` audio acquire 에 override 1줄 → 예약 deviceId 가 다음 grant 에 반영 |
| **DeviceManager switch 입력분** | `device-manager.js` | `_switchInput` — ACTIVE→acquire({deviceId:exact})→setInputDevice / SUSPENDED·RELEASED→setPendingInputDevice. acquire=MediaAcquire 단일 게이트(LocalPipe 는 track/deviceId만) |

### ★ 검토 보정 (선조치 후 보고)
**`release()`/`deactivate()`는 _trackLock 에서 제외**(작업지침 lock 목록엔 포함). 근거: 둘은 **동기 종단 메서드**(현 시그너처 sync, 호출처 `unpublishAudio/Video`가 `pipe.deactivate()` 직후 동기로 `_stream.removeTrack` + 상태 의존). lock 으로 비동기화하면 상태 변이(active=false/trackState)가 microtask 로 밀려 **동기 호출처가 stale 상태를 읽는 회귀** 위험. 교체류(replaceTrack glare)는 전부 잠갰고, release/deactivate 는 terminal 이라 device전환↔grant 경합과 무관. → 측정 시 추가 가능. **부장 veto 가능**(원하면 sync 보존하며 잠그는 변형 검토).

---

## C-2 정리 (§0.5, 6건)

| # | 항목 | 처리 |
|---|---|---|
| 1 | C4-3 Safari skip + gUM dedup | `list()` — Safari(iOS)서 활성 track 있으면 label gUM skip(재획득 버그) + `_gumInflight` 로 진행 중 gUM await(중복 프롬프트 차단) |
| 2 | setSinkId probe | `_switchOutput` — 실제 setSinkId 시도 후 **전부 reject 면 `_sinkUnsupported` 세션 비활성화** |
| 3 | `_outputElements` 캡슐화 | `pipe._element` 직접 → `pipe.getMediaElement()`(base Pipe 신설) |
| 4 | **EnvAdapter window 미가드** | `start()` online/offline 만 `if (typeof window !== "undefined")` 분기(visibility 는 살림). _c3_check window mock 제거 |
| 5 | constants DeviceKind 위치 | `export { DEVICE_KIND as DeviceKind }` 를 const 정의 아래로(가독성) |

> #1 userMediaPromiseMap 은 **DeviceManager.list 범위 dedup(`_gumInflight`)** 로 구현(MediaAcquire 게이트 무수정 — 단일 게이트 보존). 전역 concurrent-gUM dedup 이 필요해지면 MediaAcquire 로 승격(별 토픽).

---

## 불변 (실증)

- swapTrack/setInputDevice getParameters/setParameters 무접근 — encodings 보존, constraints 만 applyConstraints.
- pauseUpstream(C2 B) ↔ suspend(PTT 전력) 의미 분리 — 같은 _trackLock 이되 동작 불변.
- power FSM 로직 보존 — `_buildAudioOverrides` + `_doEnsureHot` override 1줄만. _set/_scheduleDown/floor handler 무변경.
- acquire = MediaAcquire 단일 게이트(DeviceManager). LocalPipe 는 acquire 안 함.
- SUSPENDED/RELEASED(PTT 꺼짐) device 전환 = acquire 0. 입력 분리 자동폴백 안 함(통지만).

---

## 검증

- `node --check` 7파일 PASS.
- **mock 9종 ALL PASS**: 기존 8(회귀 0 — PTT/T2~3/C2/C3/C4-B) + **신규 `_c4c_check`**.
- `_c4c_check`(★ PTT device 전환 실결함 회귀): ACTIVE switch→acquire(exact)+setInputDevice swapTrack+constraints 재적용 / **SUSPENDED switch→acquire 0 + RELEASED 전이 + savedConstraints 예약** / **power._buildAudioOverrides→예약 deviceId** / RELEASED resume→need_track / RELEASED switch→예약 갱신(acquire 0) / _trackLock 동시호출 직렬.

---

## 미착수 (후순위)

- D — #15 모바일 백그라운드 재획득(C2 §6-F 공유) / OS 기본장치 label 변경 감지(★4).
- 선택 출력장치 신규 mount element 에 자동 setSinkId 상속(레거시 addOutputElement 패턴) — 현 _switchOutput 은 현존 element 만. 실수요 시.

---

## ★ 종결

- **[결재]** home 7파일+신규1 diff 검토 후 GO → **Phase C 단일 커밋**(device-manager 양쪽 걸쳐 묶음 — 작업지침 허용)(+ context done).
- **[택1]** release/deactivate _trackLock 제외(보정) — 현행(제외, 권장) vs 작업지침대로 포함(sync 보존 변형 필요).
- **[보고]** C4 종결(A+B+C). EnvAdapter window 가드(앞 발견_사항)도 본 커밋에 포함 해소. 다음 후보 = C5(데이터/제어) / C1 §7 서버작업.

---

*author: kodeholic (powered by Claude)*
