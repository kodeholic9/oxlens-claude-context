// author: kodeholic (powered by Claude)
# OxLens Web SDK — 외부 평면 재설계 작업 지침 ① 저위험 청소

> 작성: 2026-06-09. 부장님(kodeholic) ↔ 김대리(Claude).
> 설계 근거: `20260609_client_outer_plane_ownership_design.md` §11 (갭 목록 / 구현 순서).
> **본 지침 범위 = §11.2 의 1~3 (저위험 청소): G1 → G6 → G7.**
> G2(A안)·G3~G5(다방 본체)는 후속 지침(사유 §0.1). 불변 원칙·계약 = PROJECT_MASTER.md. 대상 = `oxlens-home/sdk/` (활성).

---

## 0. 범위와 전제

### 0.1 왜 이 범위만

§11.2 순서는 `1~3 저위험 청소 → 4 A안 → 5 다방 본체`다. 5 진입 전제 = §10.1 미해결(청취 floor 처리 / engine.ptt 단수 vs 통합)을 먼저 닫는 것. **그 전에 청소(G1/G6/G7)부터 떼어, 회귀 위험 0에 가깝게 굳혀 둔다.** G2는 PTT attach/detach(floor·power 접촉)라 "중간" 위험 + A안 설계 결정(§6.6 플래그)이 걸려 별 지침으로 분리한다.

### 0.2 공통 불변

- **실측 기반.** 추측 금지 — 손대기 전 대상 함수 직독.
- **死코드 금지.** op/이벤트/변수 폐기 시 송신처·구독처 0 확인 후 제거.
- **server-authoritative 유지.** 낙관적 업데이트 0.
- **floor.js FSM 무변경.** PTT 코어 로직 비대상.
- **서버 코드 비대상**(별 repo). 서버 의존은 `⚠`로 표기 — 클라 단독으로 못 닫는 항목은 선결 확인.
- 산출물 author = `kodeholic (powered by Claude)`.

### 0.3 진행 방식

`G1 → 검증 → G6 → 검증 → G7 → 검증`. 단계마다 **단일방 full-duplex E2E**(connect → createRoom → joinRoom → enableMic/Camera → mute/unmute → setDuplex → unpublish) PASS 유지가 공통 AC. 한 단계 깨지면 다음 진입 금지.

---

## 1. G1 — MUTE_UPDATE 폐기 → TRACK_STATE_REQ 단일

**목표.** 요청 op 2갈래(`MUTE_UPDATE` 0x1103 = mute / `TRACK_STATE_REQ` 0x1106 = duplex)를 **0x1106 단일**로. body 분기 `{muted?}` / `{duplex?}`로 빈도·명확성 유지. 통지(`TRACK_STATE` 0x2102)는 이미 muted+active 통합이라 수신측 무변경.

**⚠ 선결(서버 의존) — 착수 전 1건 확인.**
현 `TRACK_STATE_REQ`(0x1106)이 **`{muted}` body 를 수용하는지** 확인해야 한다(현 정의는 duplex 전용). 서버 0x1106 이 muted 를 안 받으면 클라만 바꿔도 mute 가 서버에 안 먹는다.
- 수용 O → 그대로 진행.
- 수용 X → **G1 보류** 또는 서버 0x1106 muted 수용을 선작업으로. (이 한 줄이 "G1 = 작음"의 진짜 게이트. 클라 측만 보면 트리비얼하나 서버 계약이 전제.)

**손댈 파일.**

| 파일 | 작업 |
|---|---|
| `local-endpoint.js` `setTrackState` | `if(apply.muted) sig.send(OP.MUTE_UPDATE,{track_id,ssrc,muted})` → `sig.send(OP.TRACK_STATE_REQ,{track_id,muted})`. duplex 분기는 이미 0x1106 — 유지. |
| `ptt/power.js` `_notifyMuteServer(kind,muted)` | **2번째 송신처.** 현 `sig.send(OP.MUTE_UPDATE,{ssrc,muted})`(ssrc-only) → `TRACK_STATE_REQ` 로. 단 track_id 없음·ssrc 는 camera/screen 미구분 → 아래 매핑 처리. |
| `shared/constants.js` `OP.MUTE_UPDATE` | **마지막 단계.** 송신처 0 확인 + 서버 폐기 동기화 후 0x1103 상수 제거. 그 전엔 둔다(死op 방지 순서). |

**power 송신처 track_id 확보(순서 약결합).**
`_notifyMuteServer` 는 kind 만 알고 track_id 가 없다. `getPublishSsrc(kind)` 도 camera/screen 미구분(둘 다 m=video). 해결 = `localEndpoint.getPipeBySource(kind→source)` 로 `pipe.trackId` 조회 후 track_id 기반 전송. **G7 전이라 source→pipe 1:1 가정이 아직 유효** → 지금 동작하고, G7 에서 `getPipe(trackKey)` 로 치환. (G1 이 G7 에 막히지 않게 이 경로로 푼다.)

**AC.**
- mute/unmute(mic·camera) + setDuplex 시 wire 캡처에 **0x1103 = 0건, 0x1106 만**.
- 통지 수신(room.js `_onTrackState`) 정상 — 무변경 확인.
- 단일방 E2E PASS.

**no-touch.** 통지 처리 경로(room.js), floor gating(half mute skip 규칙) 유지.

---

## 2. G6 — LocalPipeState 개명 + media track SSOT

**목표.** (a) enum `TrackState` → `LocalPipeState` 개명(값 4종 유지). (b) track 3출처(`this.track` / `_savedTrack` / `_sender.track`) → **권위 = `sender.track`, 백업 = `_savedTrack` 1개**로 축약.

**손댈 파일.**

| 파일 | 작업 |
|---|---|
| `domain/local-pipe.js` | `export const TrackState` → `LocalPipeState`. 내부 전 참조 치환. SSOT: 권위 track 조회 단일화(`_sender?.track ?? _savedTrack`), `suspend`/`release` 의 `_sender?.track \|\| this.track` OR 제거 → "권위=sender, 없으면 백업" 규칙으로. |
| `domain/local-endpoint.js` | `import { TrackState }` → `LocalPipeState`. 비교문 치환. |
| `ptt/power.js` | `import { TrackState }` → `LocalPipeState`. `TrackState.SUSPENDED/ACTIVE/RELEASED` 비교 **다수** — 누락 시 런타임 깨짐, 전수 치환. |

**⚠ mute 재타게팅(§2.3).** 현 `local-pipe.setTrackState` 는 mute 를 `this.track.enabled` 로 토글한다. 권위를 sender.track 으로 옮기면서 ACTIVE 중 this.track 을 비우면 토글 대상이 사라진다. → **둘 중 하나 명시**: ① mute 를 `_sender?.track.enabled` 기준으로 재타게팅, 또는 ② ACTIVE 동안 this.track 을 권위 미러로 유지. 동작 불변이 목표라 ②가 안전(현 동작과 동일), 단 "거짓말 제거" 취지는 ①. **②로 가되 주석에 "ACTIVE 미러"임을 명시** 권장.

**AC.** 순수 기계적 — **동작 불변**. 단일방 E2E + PTT 전력 FSM(suspend→resume→release via floor 시뮬) 회귀 0. mute 가 enabled 토글로 동작(SSRC 보존) 유지.

**회귀 위험.** power.js 의 enum 비교 누락. → 치환 후 `TrackState` 잔존 0 grep 확인.

---

## 3. G7 — trackKey (복수 cam/screen)

**목표.** source 라벨 의존 식별 → 클라 발급 유니크 `trackKey`. `getPipe(trackKey)`(유니크) + `getPipesBySource(source)`(라벨 필터, 복수 반환).

**⚠ 광범위(작음 아님).** source 키 조회처가 한 곳이 아니다:
`local-endpoint`(hasPipe/getPipeBySource/getPipeByKind/collectPreset/restartTrack/setProcessor/stopProcessor/setTrackState/unpublishAudio/unpublishVideo) + `power`(_micPipe/_cameraPipe) + `local-stream`(_pipe) + 공개 API('mic'/'camera'/'screen').

**단계.**
1. **trackKey 발급 규칙** — 예 `${source}#${seq}`(cam#1, scr#1). intent 구획 보관. 발급 주체 = LocalEndpoint(publish 시점).
2. **인덱스** — `pipes` Map 에 trackKey 보조 인덱스(`trackKey → pipe`). track_id/mid 는 그 위 속성(trackKey 가 1차 키).
3. **공개 API 호환** — 외부는 'mic'/'camera'/'screen' 문자열 유지. 단일 인스턴스 = `getPipesBySource(source)[0]` 로 해소. 복수 = trackKey 기반 신 경로(외부 노출 형태는 §8 LocalStream 과 함께).
4. **LocalStream 안정키** — `_source` → `_trackKey` 전환(재발행 stale 회피 + 복수 트랙).

**⚠ trackKey ↔ track_id 매핑 보관자(§11.2).** 현 `_learnTrackId` 가 `m:{mid}` 임시키 → 서버 track_id 재키잉. trackKey 끼면 사슬 `trackKey → ssrc → enrich → track_id`. **매핑 유지 주체 = LocalEndpoint** 로 못 박는다(보조 인덱스 trackKey→pipe). 복수 카메라 키 충돌 방지 = trackKey 유일 1차 키.

**AC.**
- 단일 cam/mic/screen 기존 동작 **불변**(공개 API 그대로).
- 카메라 2개 publish → `getPipesBySource('camera')` 2개 반환, 각각 독립 mute/duplex.

**no-touch.** 서버 프로토콜 무관(trackKey = 클라 내부 키, wire 미노출).

---

## 4. 후속 (본 지침 범위 밖 — 별 지침)

- **G2 (A안, 중간).** LocalEndpoint = duplex 권위(half→PTT attach / full→detach). `setTrackState` 에 PTT attach/detach(②) 채움(§10.2). `_upstreamPaused` → ACTIVE 하위 플래그 정합 + 공개 `LocalStream.pause/resumeUpstream` + `UPSTREAM_PAUSED/RESUMED` 제거(§6.6). floor·power 접촉 → 별 지침.
- **G3+G4+G5 (다방 본체, 최대).** **선결 = §10.1**(청취 floor 처리 / engine.ptt 단수 vs 통합 노출). 닫은 뒤 착수. PTT 방별 슬롯은 Phase ①.5 스캐폴드 활용(constants `ptt-{room}-(audio/video)` + room `_pttVirtual.ensureVirtual`) — 식별은 있고 인스턴스(engine.ptt 단일)·`Map<roomId>` 관리만 신설.

---

*author: kodeholic (powered by Claude)*
