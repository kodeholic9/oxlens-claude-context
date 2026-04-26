# 20260426f — §F 결함 의심 4건 일괄 해소 (Phase 67)

> **세션 영역**: QA / 진단 / catalog 정리
> **시작 상태**: §F 결함 의심 4건 (F-12, server-side stale, RV-09, G3-02·03)
> **종료 상태**: §F 4건 모두 결함 아님 판정 → 큐 0건. catalog/doc 5건 보정 + §H 환경 불변 3건 추가
> **시험 도구**: Playwright MCP (Claude in Chrome 부장님 환경에서 미작동 → Playwright 채택)

---

## 핵심 결정 (이 세션의 산물)

### 1. §F 4건 모두 결함 아님 — 큐 0 으로 비움

| ID | 판정 | 핵심 근거 |
|---|---|---|
| **RV-09** | catalog stale | `oxsfud/src/config.rs` ground truth: `SUSPECT_TIMEOUT_MS=15_000`, `ZOMBIE_TIMEOUT_MS=20_000` (주석: "= SUSPECT + 5s, take-over 로 충분"). PROJECT_MASTER 본문의 `Active ──(15s)──> Suspect ──(+5s)──> Zombie` 와 일치. 4/25e 단축 후 catalog 만 35s 옛 값에 멈춤. 실측 18s/24s = 5s polling 변동 안 정확 일치. zombie phase 미관측은 reaper 한 cycle 안 전이+삭제로 admin snapshot 노출시간 0인 관측성 구조 |
| **server-side stale** | 운영 한계 | reconnect 정책 의도. `endpoints.get_or_create_with_creds` 가 zombie 정리 20s 안 새 IDENTIFY 시 기존 Peer 재사용. take-over 는 `2003 AlreadyInRoom` (같은 방 재진입) 에만 발동 → 다른 방 ROOM_JOIN 시 그냥 `peer.join_room` + `scope_insert` 누적. shadow는 방 참가자 목록만 누적, scope 무관 → stale 가산자 아님. cleanup 패턴 (`engine.scope.set({sub:[], pub:[]})` + `room.leave()` + disconnect) 이 정답 |
| **F-12** | 시험 환경 setup 결함 (Phase 61 catalog 시험 logic) | 서버 `floor.rs::request` Taken 분기에 preempt 로직 완전 구현 (`preemption_enabled=true` default → Revoked + Granted 두 action, 큐 삽입 안 함). 클라 path `engine.floorRequest({priority})` → `floor-fsm.js::request` → `buildRequest(priority)` → MBCP TLV `FIELD.PRIORITY` (id=0) 로 인코딩. **Phase 67 시험 결과**: alice press(0) → `floor:granted priority=0`, 1.5s 후 bob press(3) → alice `floor:revoke cause='preempted'` + `floor:idle prev_speaker=alice` + bob `floor:granted priority=3`. 완벽 동작 확정. Phase 61 false negative 는 spec 형식 잘못 (`audio:{duplex:'half'}` → `tracks.mic.{enabled,duplex}` 가 정답) 으로 mic publish 안 되어 발생 |
| **G3-02/03** | 결함 아님 | macOS Chrome 기준 정상 동작. raw `getUserMedia({audio:{autoGainControl:false, noiseSuppression:false, echoCancellation:false}})` 도 SDK `setMicCapture({동일})` 도 `applyConstraints` 직접 호출도 모두 `track.getSettings` 에 `{AGC:false, NS:false, EC:false}` 정확히 반영. Phase 61 결과는 당시 시험 코드/환경 결함으로 보이며 현 빌드에서 재현 안 됨 |

### 2. §H QA 시험 환경 불변 — 3건 추가

- **QA spawn spec 형식 = `tracks.mic.{enabled,duplex}` / `tracks.camera.{enabled,duplex,simulcast}`**: Phase 61 F-12 false negative 의 원인이 spec 형식이었음. `audio:{duplex:'half'}` 같은 spec 은 `participant.js parseSpec()` 이 무시하고 `tracks.mic.enabled=false` 로 스포닝 → mic pipe 자체 없이 모든 floor 시험이 false negative.
- **PTT 시험 경로**: spawn (`tracks.mic.{enabled:true, duplex:'half'}`) 만으로 phase=ready 직후 floor 사용 가능. 추가 `__qa__.user(u).enable('mic')` 호출 금지 — duplex='full' 고정으로 재생성되어 floor 무효화 함정.
- **reset 후 zombie 잔재 = 운영 한계**: WS disconnect → sfud 는 SESSION_DISCONNECT 통보만, Peer/sub_rooms/pub_rooms 그대로 유지. zombie reaper 20s 자연 정리. 그 timing 안 새 IDENTIFY 면 `endpoints.get_or_create_with_creds` 가 기존 Peer 재사용. cleanup 패턴: `engine.scope.set({sub:[], pub:[]})` + `room.leave()` + disconnect 또는 zombie 정리 20s 대기. 자세한 메커니즘은 `doc/server_side_stale_membership.md`.

### 3. zombie reaper timing — 단일 출처 명시

`config.rs` 가 ground truth: `REAPER_INTERVAL_MS=5_000`, `SUSPECT_TIMEOUT_MS=15_000`, `ZOMBIE_TIMEOUT_MS=20_000` (4/25e 에 35→20 단축).

**오해 회피 포인트**:
- catalog 의 35s/30s 표기는 4/25e 이전 옛 값 잔재 — 보정 완료 (`checks/90_recovery.md`)
- `oxsfud/src/tasks.rs::run_zombie_reaper` 함수 doc-comment 도 옛 값 (`Suspect(20s) → Zombie(35s)`) 으로 표기되어 있음 — **코드 동작에는 영향 없음** (실제 호출은 `config::SUSPECT_TIMEOUT_MS`/`ZOMBIE_TIMEOUT_MS`). 부장님 명시 요청 시에만 보정 (상수 사용으로 동작 정합성은 이미 보장).
- zombie phase 가 admin snapshot 에 노출되지 않는 것은 reaper 가 phase=Zombie 전이 직후 `endpoints.remove()` 로 삭제하는 구조 — 노출 시간 0 = 관측성 한계 (결함 아님).

---

## 처리 결과 — 시정사항 큐

### catalog/checks/doc 보정 5건 (Phase 67)

| 파일 | 변경 |
|---|---|
| `qa/README.md` | §F 4건 모두 처리 완료 표시. §H 3건 추가 (spec 형식 / PTT 시험 경로 / reset zombie 패턴 + zombie reaper timing). 마지막 갱신 timestamp 갱신 |
| `qa/checks/90_recovery.md` | RV-08 `Suspect (15s 무응답)`, RV-09 `Zombie (20s, 자동 삭제)` ✅ + zombie phase 노출 기대 제거. RV-10/RV-05 timing 보정 (35s→20s). 실측 fact 표기 갱신 |
| `qa/checks/60_floor_single.md` | F-12 ✅ 갱신 + 시험 스펙 표준화 (4단계 정확 명세 + spec 형식 함정 + DC bearer 효과 검증 원리) |
| `qa/checks/92_media_settings.md` | G3-02/03 ⚠️→✅ + 재검증 fact (raw getUserMedia / SDK / applyConstraints 모두 정확 반영) |
| `qa/doc/server_side_stale_membership.md` | "판정 대기" → "운영 한계 확정" (Phase 67 §F). 메커니즘 재분석 (Peer 재사용 + take-over 미발동 단일 원인). cleanup 패턴 + zombie 자연 정리 20s 대기 옵션 추가. 중복된 cascade 섹션 제거 |

### 라이브 큐 상태 (Phase 67 종료)

- §A 0건
- §B 0건
- §C 0건
- §D 0건
- §E **2건 잔존** (PW-08 → 4/26 §E-2 처리됨, 잔존: P-07 catalog 시험 logic 차원, S-08 → 4/26b 처리됨, 잔존: §E 0건? — 다음 세션 확인)
- §F **0건** ← 본 세션 산물
- §G 0건
- §H 5건 → **8건** (3건 추가)
- §I 품질 카테고리 (작업 분할 4단계, 진행 중)

> 정확한 §E 잔존 건수는 다음 세션에서 README 직접 확인. Phase 64+65+66 후속이라 변동 가능.

---

## Playwright 시험 실측 결과 (재현 가능 형태)

### F-12 priority preemption — 정상 동작 확정

**스펙**:
```js
const spec = (user) => ({
  user, room: 'qa_test_01',
  tracks: { mic: { enabled: true, duplex: 'half' }, camera: { enabled: false, duplex: 'full' } },
  autojoin: true,
});
await __qa__.spawn(spec('alice'));
await __qa__.spawn(spec('bob'));
// phase==='ready' 대기 (~200ms)

// 시나리오
await __qa__.user('alice').ptt.press(0);  // priority 0
await __qa__.sleep(1500);
await __qa__.user('bob').ptt.press(3);    // priority 3 → preempt
```

**실측 이벤트 시퀀스**:
- t0: alice `floor:state requesting` → t0+3ms: `floor:state talking` + `floor:granted speaker=alice duration=30` + `floor:taken priority=0`
- t0+1502ms: alice `floor:state idle (prev=talking)` + `floor:revoke cause=preempted` + `floor:idle prev_speaker=alice` + `floor:state listening speaker=bob` + `floor:taken speaker=bob priority=3`
- bob 측: 같은 timestamp 에 `floor:granted speaker=bob duration=30` + `floor:taken priority=3`

DC bearer 라 WS hook 으로는 wire byte 캡처 불가 — 효과 (revoke + granted 두 action 모두 발생) 로 priority TLV 정상 인코딩 + 서버 preempt 분기 진입 확정.

### G3-02/03 capture constraint — 정상 동작 확정

| 시험 | AGC | NS | EC |
|---|---|---|---|
| spawn 후 mic (Chrome default) | true | true | true |
| raw `getUserMedia({audio:true})` | true | true | true |
| raw `getUserMedia({audio:{all:false}})` | **false** | **false** | **false** |
| raw `getUserMedia({audio:{AGC:{ideal:false}}})` | **false** | **false** | **false** |
| **SDK `setMicCapture({all:false})`** ret='reacquired' | **false** | **false** | **false** |
| `applyConstraints({all:false})` 직접 (SDK 우회) | **false** | **false** | **false** |

모든 path 가 의도한 constraint 즉시 반영. macOS Chrome 빌드 정상.

---

## 핵심 학습 / 지침 후보

### 1. 시험 환경 setup 결함 = 결함 의심 큐의 큰 카테고리

Phase 61 의심 4건 중 3건이 **시험 환경 setup 결함** (catalog 또는 시험 코드의 spec 형식 잘못 / 시험 logic 누락) 이었다:

- F-12: spec `audio:{duplex:'half'}` 가 `participant.js parseSpec()` 이 무시 → mic pipe 미생성 → false negative
- F-14/PAN-06: catalog 가 외부 facade 가 받지 않는 키 (`destinations`, `pubSetId`) 를 객체에 담아 호출 → 무의미 시험 (Phase 61 후속에서 이미 처리)
- G3-02/03: 당시 시험 코드/환경 결함 (정확한 원인 불명) 으로 false negative — 현 빌드에 재현 안 됨

**지침 후보**: catalog 시험 시 spec/시그너처 검증 단계 명시. 외부 facade 만 호출 (§H 4/26 추가) + 시험 시나리오 시작 시 환경 sanity check (e.g., mic pipe 존재 + duplex 일치) 사전 확인.

### 2. zombie reaper 관측성 = phase 노출보다 사라짐 확인

zombie reaper 가 phase=Zombie 전이 후 `endpoints.remove()` 로 즉시 삭제하는 구조 → admin snapshot 에서 `phase: "zombie"` 를 관측하기는 거의 불가능 (5s polling cycle 안 전이+삭제 동시 발생). 시험은 **phase 노출 확인이 아니라 user 가 사라졌는지 확인** 하는 것이 정답.

이는 reaper 의도 (한 cycle 안 cleanup 완결) 와 일치. 별도 staging 단계를 두면 race window 가 커짐 — 현 구조가 옳다.

### 3. reconnect 정책의 자연 귀결 = WS disconnect ≠ LeaveRoom

PROJECT_MASTER §sfud/hub lifecycle 의 "독립 전이" 원칙: WS 끊김 → SESSION_DISCONNECT 통보만, Peer/sub_rooms/pub_rooms 보존. 이는 reconnect 복구 정책의 핵심. **disconnect 를 LeaveRoom 으로 재해석하면 hub 종속 발생** — 이미 명시된 기각 접근법.

따라서 server-side stale 은 결함이 아니라 **reconnect 정책의 자연 귀결**. 시험 클라이언트가 cleanup 책임을 진다 — `engine.scope.set({sub:[], pub:[]})` 명시 호출 + `room.leave()` + disconnect 순서.

### 4. catalog vs 코드 ground truth — 코드 우선

`config.rs` 의 `SUSPECT_TIMEOUT_MS=15_000` / `ZOMBIE_TIMEOUT_MS=20_000` 와 catalog 의 35s/30s 가 충돌할 때 **코드가 ground truth**. 4/25e 단축 시 catalog 갱신 누락이 Phase 61 RV-09 의심의 원인.

**지침 후보**: 서버 상수 변경 시 catalog `00_index` 또는 영향 받는 checks 항목 동시 갱신을 코딩 워크플로에 박기 (commit checklist).

---

## 오늘의 기각 후보

- **서버 zombie reaper 가 SUSPECT 진입 시 sub/pub cleanup**: reconnect 복구 정책과 충돌. 의도적 leave vs 비정상 끊김 구분 없이 정리하면 reconnect 시 멤버십 잃음 — 영업 시나리오 침해.
- **zombie phase 를 admin snapshot 에 staging 노출**: race window 커지고 본질적 가치 없음. 사라짐 확인이 정답.
- **`endpoints.get_or_create_with_creds` 의 Peer 재사용 정책 변경 (user-scope take-over 확장)**: LiveKit/mediasoup 표준 동작과 어긋나며 reconnect 복구 정책 무력화.

## 오늘의 지침 후보

- **시험 환경 setup 결함이 결함 의심의 큰 카테고리** — Phase 61 4건 중 3건이 이 패턴. 결함 의심 보고 시 시험 코드/spec 직접 재현 검증을 1차로.
- **DC bearer 시험은 효과로 검증** — WS hook 으로는 wire byte 캡처 불가. floor:revoke + granted 두 action 시퀀스로 priority TLV 인코딩 정상 추론.
- **시험 도구 우선순위**: Playwright MCP 가 cross-realm eval + ws.send hook + 자동 이벤트 캡처 검증된 패턴. Claude in Chrome 은 부장님 환경에서 미작동 — 다음 시험도 Playwright 우선.

---

## 후속 작업

1. **서버 코드 주석 보정 (선택)**: `oxsfud/src/tasks.rs::run_zombie_reaper` 함수 doc-comment 의 "Suspect(20s) → Zombie(35s)" 옛 값 표기. 동작에는 영향 없음 (config 상수 사용). 부장님 명시 요청 시에만.
2. **§E 잔존 건수 확인**: PW-08 / S-08 등이 4/26 후속에서 처리됐는지 README §E 직접 확인. 다음 세션 첫 점검.
3. **§I 품질 카테고리 진행**: synth 인프라 + baseline 수집 + 94_quality.md 본격화 — 별도 세션.

---

*author: kodeholic (powered by Claude)*
