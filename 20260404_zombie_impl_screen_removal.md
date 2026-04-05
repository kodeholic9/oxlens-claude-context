# 세션: 좀비 2단계 구현 + screen 하드코딩 제거 + 프리셋 체계 v1

- **날짜**: 2026-04-04
- **버전**: v0.6.15-dev → v0.6.16-dev
- **영역**: 서버 5파일 + 클라이언트 5파일
- **이전 세션**: `20260403_roommode_removal_zombie_design.md`

---

## 1. 완료: 좀비 2단계 구현 (Suspect → Zombie)

### 설계
```
ALIVE ──(20초 무응답)──> SUSPECT ──(+15초)──> ZOMBIE(삭제)
  ^                         │
  └──(packet received)──────┘
```

| 상수 | 이전 | 변경 |
|------|------|------|
| `REAPER_INTERVAL_MS` | 30,000 | 5,000 |
| `SUSPECT_TIMEOUT_MS` | (없음) | 20,000 |
| `ZOMBIE_TIMEOUT_MS` | 120,000 | 35,000 |

### 성능 설계 포인트
`suspect_since: AtomicU64` — 상태+시각 단일 atomic (0=ALIVE, non-zero=Suspect 진입 시각).
CAS 한 방으로 원자적 상태 전환. 별도 enum + 시각 분리 시 두 변수 간 찢어진 읽기 → lock 필요.

### agg-log 3종 + 스냅샷 state
- `session:suspect`, `session:zombie`, `session:recovered`
- 어드민 스냅샷 `"state": "alive" | "suspect"`

### touch() 확인
- `ingress.rs:49` (RTP) + `udp/mod.rs:343` (STUN) — subscribe-only 참가자도 STUN으로 touch

### 수정 파일: config.rs, participant.rs, room.rs, tasks.rs, admin.rs

---

## 2. 완료: screen 하드코딩 제거 + TRACKS_UPDATE duplex/simulcast

### 핵심
- `src == "screen"` → `t.simulcast.unwrap_or(duplex != Half)` — 클라이언트 명시 우선
- `PublishTrackItem.simulcast: Option<bool>` 추가
- TRACKS_UPDATE(add) 전 경로에 `duplex`/`simulcast` 필드 포함

### 수정 파일: message.rs, track_ops.rs, helpers.rs, ingress.rs, media-session.js

---

## 3. 완료: 프리셋 체계 v1

### 구조
- `demo/presets.js`: 8개 역할 프리셋 JSON + `resolvePreset()` + 10개 시나리오
- SDK는 프리셋 개념 모름 — `_audioDuplex`, `_videoDuplex`, `_simulcastEnabled` primitive만
- 프리셋은 앱 레이어 JSON (고객 커스터마이즈 가능)

### 프리셋 목록
| 프리셋 | audio | video | 계열 |
|--------|-------|-------|------|
| talker | full | full, sim=on | Conference |
| viewer | off | off | Conference |
| presenter | full | full, sim=on + screen | Conference |
| voice_radio | half | off | PTT |
| video_radio | half | half, sim=off | PTT |
| dispatch | full | full, sim=on + screen | 혼합 |
| monitor | off | full, sim=off | 혼합 |
| caster | full | off + screen | 혼합 |

### UI
- `index.html`: preset-select 드롭다운 (연결 패널 내, room-select 아래)
- badge: CONF(파란색) / PTT(주황색) 자동 전환
- 입장 중 preset-select 비활성화

### 연동 흐름
1. 프리셋 선택 → badge 업데이트
2. 입장 클릭 → `resolvePreset()` → `media._audioDuplex/videoDuplex/simulcastEnabled` 설정
3. `client.js _onJoinOk`: `media._simulcastEnabled` 우선, 서버 응답 fallback
4. PUBLISH_TRACKS에 duplex/simulcast 명시 전송
5. PTT 모드: `preset.audioDuplex === "half"` → ptt.switchControlMode("ptt")

### 수정 파일
| 파일 | 변경 |
|------|------|
| `demo/presets.js` | 신규 — 8 프리셋 + resolvePreset + 10 시나리오 |
| `demo/client/index.html` | preset-select UI |
| `demo/client/app.js` | import + 초기화 + joinRoom 연동 + badge + PTT 모드 파생 |
| `core/client.js` | `_simulcastEnabled` — 프리셋 우선 로직 |
| `core/media-session.js` | `_videoDuplex` 추가 + teardown 리셋 |

---

## 4. 다음 세션 작업

- [ ] 브라우저 테스트: talker + radio 혼합 입장 시나리오
- [ ] 데모앱 시나리오별 분리 (components 추출)
- [ ] Moderated Floor Control (진행자 전용 op)
- [ ] SKILL_OXLENS.md 업데이트
- [ ] 세션 컨텍스트 / SESSION_INDEX 갱신

---

## 5. 기각된 접근법

| 접근법 | 기각 이유 |
|--------|----------|
| suspect_since를 AtomicU8(상태) + AtomicU64(시각) 분리 | 두 atomic 간 찢어진 읽기 → lock 필요. 핫패스 lock 회피 |
| simulcast를 서버가 source 이름으로 판단 유지 | 새 source마다 서버 수정 필요. 클라이언트 명시가 확장성 우월 |
| 프리셋을 SDK 안에 포함 | 시나리오/UI 종속 → SDK는 primitive만 (dumb and generic) |
| `_simulcastEnabled`를 서버 응답으로만 결정 | 서버에서 simulcast.enabled 제거됨 → 프리셋이 authority |

---

## 6. 커밋

```
git commit -am "feat: 좀비 2단계 + screen 하드코딩 제거 + 프리셋 체계 v1

Zombie 2-stage: ALIVE→Suspect(20s)→Zombie(35s), suspect_since AtomicU64
Screen removal: t.simulcast.unwrap_or() — 클라이언트 명시 우선
TRACKS_UPDATE: duplex/simulcast 필드 전 경로 추가
Preset system v1: 8 roles + resolvePreset + UI + badge
client.js: simulcast 프리셋 우선 로직
media-session.js: _videoDuplex + PUBLISH_TRACKS 연동"
```

---

*author: kodeholic (powered by Claude)*
