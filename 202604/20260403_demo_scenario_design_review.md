# 세션: 데모 시나리오 설계 검토 + Simulcast 트랙 속성 + PROMOTED 2중 notify 수정

- **날짜**: 2026-04-03
- **버전**: v0.6.12-dev → v0.6.13-dev
- **영역**: 설계 검토 + 서버 (ingress.rs)
- **이전 세션**: `20260403_pli_governor_rid_fix.md`

---

## 1. 버그 수정: PROMOTED simulcast 2중 notify

### 증상
- U736 퇴장→재입장 시 subscriber의 subscribe SDP에 같은 user video m-line 2개 (같은 vssrc)
- Chrome: `Failed to process the bundled m= section with mid='6'` → subscribe PC 사망
- 재입장한 사용자 자신도 남의 영상도 안 보임

### 근본 원인
어제 rid 파싱 intent 가드(RID_EXTMAP_ID fallback 제거) 수정의 **부작용**.
- RTP가 intent보다 먼저 도착 → 3개 SSRC가 `unknown`으로 등록
- intent 도착 후 PROMOTED 경로에서 MID 매칭으로 video 승격
- **simulcast h/l이 같은 MID를 공유** → 둘 다 별도 video 트랙으로 promote → 2번 TRACKS_UPDATE(add)
- 같은 vssrc에 대해 subscribe SDP에 video m-line 2개 → BUNDLE 충돌

### 수정 (ingress.rs register_and_notify_stream)
- PROMOTED 경로에서 video로 승격 시 rid=None인 경우, sender.tracks에 이미 같은 source의 video 트랙이 있으면 → rid="l"로 보정
- stream_map에도 rid 반영 (후속 HIT path 일관성)
- 기존 `rid.as_deref() == Some("l")` skip notify 로직이 그대로 동작
- 로그: `[STREAM:REG] PROMOTED secondary → rid=l`

### 검증 결과
- Conference simulcast 4탭 + 퇴장→재입장 시나리오: **전원 PASS**
- contract check 전원 PASS, decoded_delta 71~72, fps 23~25, loss 0%

---

## 2. 설계 검토: Simulcast를 트랙 속성으로

### 왜 방 단위가 아니라 트랙 단위인가
- **이미 그렇게 동작**: screen=non-sim, camera=sim (하드코딩을 속성으로 올리는 것)
- **duplex와 같은 레이어**: 둘 다 "이 트랙을 어떻게 송출할 것인가"의 속성
- **방 단위의 모순**: video_radio(half) + presenter(full) 공존 시, 방 단위 sim on/off가 답 없음

### 파생 규칙 (독립 속성이 아님)
```
half-duplex  →  항상 sim=off  (강제, PttRewriter+SimulcastRewriter 충돌)
full-duplex  →  sim=on 또는 off  (프리셋에서 선택)
```
- 정적 속성 (입장 시 결정, 런타임 전환 안 함)
- 클라이언트가 half+sim=on 보내도 서버에서 강제 off

### 트랙 속성 최종 형태
```
track = duplex(full/half) + simulcast(on/off) + priority(0~N)
```

### TRACKS_UPDATE 프로토콜 확장
```json
{
  "op": 101,
  "d": {
    "action": "add",
    "userId": "U438",
    "tracks": [
      { "kind": "audio", "duplex": "full", "simulcast": false },
      { "kind": "video", "source": "camera", "duplex": "full", "simulcast": true },
      { "kind": "video", "source": "screen", "duplex": "full", "simulcast": false }
    ]
  }
}
```
- duplex: 구독자가 PTT UI vs 일반 타일 분기
- simulcast: 구독자가 레이어 선택 UI 활성/비활성 분기
- 혼합 시나리오에서 방 모드 기반 UI 전체 갈아끼우기 불가 → 트랙 단위 필수

### 구현 시 서버 점검 포인트 4개
1. **fan-out 분기** — `room.simulcast_enabled` → source별 simulcast 참조. hot path O(1)
2. **SimulcastRewriter 생성 조건** — sim=off 트랙에는 rewriter 미생성
3. **SR Translation 경로** — sim=off 트랙은 원본 SR 그대로 릴레이
4. **SUBSCRIBE_LAYER (op=51) 검증** — sim=off 트랙에 op=51 오면 서버에서 무시

---

## 3. 시나리오 + 역할 프리셋 체계

### 역할 프리셋 (빌딩 블록 8개)

| 프리셋 | audio | video | screen |
|--------|-------|-------|--------|
| talker | full | full, sim=on | - |
| viewer | off | off | - |
| voice_radio | half | off | - |
| video_radio | half | half, sim=off | - |
| presenter | full | full, sim=on | full, sim=off |
| caster | full | off | full, sim=off |
| monitor | off | full, sim=off | - |
| dispatch | full | full, sim=on | full, sim=off |

### 시나리오 분류 (3계열 10종)

| 계열 | 시나리오 | 역할 구성 | 차별화 |
|------|---------|----------|--------|
| Conference | 화상회의 | talker × N | 업계 동등 |
| Conference | 발표+토론 | presenter × 1 + talker × N | 업계 동등 |
| Conference | 웨비나 | presenter × 1~2 + viewer × N | 업계 동등 |
| PTT | 음성무전 | voice_radio × N | MCPTT 동등 |
| PTT | 영상무전 | video_radio × N | MCPTT 동등 |
| **혼합** | **디스패치** | dispatch × 1~2 + video_radio × N | **업계 전례 없음** |
| **혼합** | **CCTV+지휘** | dispatch × 1 + monitor × N + voice_radio × M | **업계 전례 없음** |
| **혼합** | **교육/훈련** | presenter × 1 + talker × 1~2 + voice_radio × N | **업계 전례 없음** |
| **혼합** | **원격지원** | caster × 1 + video_radio × 1 | **업계 전례 없음** |
| **혼합** | **사회자+패널** | talker × 1 + voice_radio × N | **업계 전례 없음** |

혼합 6개가 "방 분리 없이 트랙 속성만으로" 가능하다는 것이 6월 데모 핵심 메시지.

### 데모앱 구조 (5~6종)

| 데모앱 | 커버 시나리오 | 레이아웃 |
|--------|-------------|---------|
| conference | 화상회의, 발표+토론 | Main+Thumb (기존) |
| webinar | 웨비나 | Main + 청중 목록 |
| voice_radio | 음성무전 | 참가자 리스트 + PTT |
| dispatch | 디스패치, CCTV+지휘, 영상무전 | 그리드 + PTT |
| classroom | 교육, 사회자+패널 | Main(강사) + 학생 목록 |
| remote-support | 원격지원 | 1:1 split |

---

## 4. SDK API 설계

### Low-level (SDK primitive)
```javascript
client.publishTrack({
  kind: 'video',
  source: 'camera',
  duplex: 'half',
  simulcast: false,
  priority: 0
});
```

### High-level (프리셋 — 앱 레이어, SDK 밖)
```javascript
// 프리셋 JSON 정의 (앱 레이어)
const PRESETS = {
  video_radio: {
    audio: { duplex: 'half', priority: 0 },
    video: { duplex: 'half', simulcast: false, priority: 0 },
    screen: null
  },
  presenter: {
    audio: { duplex: 'full' },
    video: { duplex: 'full', simulcast: true },
    screen: { duplex: 'full', simulcast: false }
  }
};
```

### 경계 원칙
- SDK: publishTrack API만 (프리셋 개념 모름)
- SFU: 트랙 속성만 보고 라우팅 (역할 개념 모름)
- 프리셋/역할: 앱 레이어 JSON (고객이 자유 커스터마이즈)
- "SDK + SFU = dumb and generic" 원칙 유지

---

## 5. 데모앱 아키텍처 결정

### 디렉토리
```
oxlens-home/
├── core/              ← SDK (변경 없음)
├── demo/
│   ├── components/    ← 데모앱 공용 UI 조각
│   │   ├── video-tile.js
│   │   ├── ptt-button.js
│   │   ├── device-settings.js
│   │   └── join-flow.js
│   ├── conference/    ← Main+Thumb
│   ├── radio/         ← 리스트+PTT
│   ├── dispatch/      ← 그리드+PTT
│   ├── classroom/
│   ├── webinar/
│   ├── remote-support/
│   └── admin/         ← 운영자 전용 (고객 비공개)
```

### 핵심 결정
- **바닐라 JS + Tailwind 유지** — 빌드 없이 브라우저 바로 열림, fork 용이
- **components는 demo 안** — core(SDK)와 성격 다름
- **admin ≠ dispatch** — admin은 SFU 운영자용(비공개), dispatch는 최종 사용자용(영업용)
- **레이아웃은 시나리오별 새로 만들되, 타일·PTT·설정 컴포넌트는 공유**

### 사용자 ID/닉네임
- 랜덤 UUID → localStorage (같은 브라우저 = 같은 ID, 비가입/비로그인)
- 닉네임: UUID 해시 → 색상(6)+동물(6) 조합 = 36가지, 방당 30명 커버
- 닉네임 별도 저장 불필요 — UUID만 있으면 어디서든 동일 닉네임

### TS / npm / Android
- SDK API 확정 전 TS 전환 안 함 → 확정 후 .d.ts 별도 배포
- Android SDK: libwebrtc 순정(Google Maven) 유지 — 개조는 근거 확인 후

---

## 6. 서버 내부 상태 텔레메트리 보강 필요

오늘 3개 버그 모두 서버 로그 grep으로 진단. 어드민 스냅샷에 아래 추가 필요:
- Governor 상태 (pub별 pending + since 경과 시간)
- stream_map (SSRC ↔ rid 매핑 테이블)
- gate 상태 (subscriber별 pause/resume + 대기 시간)
- intent 도착 여부 (수신 시각 + extmap IDs)

상용 배치 시 서버 로그 접근 불가 환경 대비.
"스냅샷 주세요" 한 마디로 디버깅 시작 가능해야 함.

---

## 7. 수정된 파일

| 파일 | 수정 내용 |
|------|----------|
| `src/transport/udp/ingress.rs` | PROMOTED simulcast secondary → rid=l 보정 (register_and_notify_stream) |

(어제 세션 수정 3파일: pli_governor.rs, ingress.rs PLI h SSRC+rid가드, room.rs 주석 — 오늘 검증 완료)

---

## 8. 다음 작업 (우선순위)

- [x] 빌드 검증 (PLI Governor + rid 오독 + PROMOTED 2중 notify)  ← 완료
- [ ] SKILL_OXLENS.md 블록 적용 (어제 세션 제공분 + 오늘 추가)
- [ ] simulcast 트랙 속성 구현 (intent 필드 + fan-out 분기 + TRACKS_UPDATE)
- [ ] TRACKS_UPDATE duplex + simulcast 필드 추가
- [ ] 프리셋 체계 구현 (JSON + demo/components/ 추출)
- [ ] 데모앱 시나리오별 구현 (conference → dispatch → radio → ...)
- [ ] Moderated Floor Control (진행자 전용 op 추가)
- [ ] 서버 내부 상태 텔레메트리 보강 (Governor, stream_map, gate, intent)
- [ ] 학습 로드맵 상세화 (context/lesson/EXTERNAL_STUDY_ROADMAP.md)

---

## 9. PENDING (이전 세션에서 이월)

- [ ] ts_gap drift B안 RPi 실기기 검증
- [ ] OxLabs Phase 3 FAILs 해결 (L1-04, L1-13, L1-08)

---

## 10. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| simulcast를 독립 속성으로 | duplex에서 파생 제약 있음 (half→강제off). 독립이면 half+sim=on 허용 실수 |
| 런타임 sim on↔off 전환 | SimulcastRewriter 초기화, stream_map 재구축, SDP 재협상 연쇄 → ABR 영역이지 프리셋이 아님 |
| PROMOTED 경로에서 rid 파싱 시도 | 이미 stream_map에 Unknown으로 등록된 SSRC. rid extension은 최초 패킷에서만 의미. register_and_notify_stream에서 보정이 정석 |
| 프리셋을 SDK 안에 포함 | 시나리오/UI 종속 → 요구사항 대응 범위 폭발. SDK는 primitive만, 프리셋은 앱 레이어 |
| admin에 관제 기능 포함 | admin은 SFU 내부 구조 노출(개발용), dispatch는 최종 사용자용(영업용). 합치면 양쪽 다 망가짐 |

---

## 11. 오늘의 지침 후보 (SKILL 반영 검토)

- **half-duplex → simulcast 강제 off** — PttRewriter + SimulcastRewriter 충돌 방지. 서버 intent 검증 시 강제 덮어쓰기.
- **프리셋은 SDK 밖** — SDK는 publishTrack primitive만. 프리셋은 앱 레이어 JSON.
- **admin ≠ dispatch** — admin은 운영자/개발자용, dispatch는 최종 사용자용. 절대 합치지 않는다.
- **PROMOTED 경로 simulcast 안전장치** — unknown→video 승격 시 이미 같은 source video 존재하면 rid=l 보정 필수 (2중 notify → BUNDLE 충돌)

---

*author: kodeholic (powered by Claude)*
