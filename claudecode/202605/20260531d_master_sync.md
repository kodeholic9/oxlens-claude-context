# 작업 지침 — PROJECT_MASTER.md 현행화 (duplex activeness 반영)

문서 ID: `20260531d_master_sync.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: PROJECT_MASTER.md 의 stale 부분 7곳 현행화 (duplex activeness Phase 1~3 커밋 반영 + SubscribeMode 잔재 정정). **기계적 치환** — edit_file 의 정확 old/new 7건.
대상 파일: `/Users/tgkang/repository/context/PROJECT_MASTER.md`

> 부장님 명시 지시로 PROJECT_MASTER 수정 (평소 금지 원칙의 예외). 아래 7건 *외 다른 곳 손대지 말 것*. SESSION_INDEX 는 별도(김과장 일감).

---

## §0 의무 점검
1. 대상 파일 1줄씩 읽어 아래 7건 old 텍스트가 **정확히 1회** 매칭되는지 확인 (edit_file dryRun=true 선행 필수 — Korean 포함이라 ASCII 앵커 안 되면 해당 블록만 read 후 정확 복제).
2. 7건 모두 dryRun GREEN 확인 후 일괄 apply.

---

## §1 치환 7건

### 치환 1 — 서버 트리 track_ops.rs 설명
**old**:
```
│       │       │       ├── track_ops.rs— PUBLISH, TRACKS_READY, MUTE, CAMERA, SUBSCRIBE_LAYER (SWITCH_DUPLEX 폐기 — PUBLISH_TRACKS 재전송으로 duplex 전환)
```
**new**:
```
│       │       │       ├── track_ops.rs— PUBLISH, TRACKS_READY, MUTE, CAMERA, SUBSCRIBE_LAYER, TRACK_STATE_REQ (duplex 전환 단일 경로, 2026-05-31)
```

### 치환 2 — opcode 총 op 수
**old**:
```
카테고리 nibble 하나로 dispatch / 방향 / pid 부여 / ACK / priority / intent 전부 lookup. flag 비트 신설 금지가 v3 도그마. 총 **41 op**. 새 op 추가 시 `oxsig::opcode::ALL_OPS` + `context/design/wire_v3_catalog.md` 동시 갱신.
```
**new**:
```
카테고리 nibble 하나로 dispatch / 방향 / pid 부여 / ACK / priority / intent 전부 lookup. flag 비트 신설 금지가 v3 도그마. 총 **42 op**. 새 op 추가 시 `oxsig::opcode::ALL_OPS` + `context/design/wire_v3_catalog.md` 동시 갱신.
```

### 치환 3 — Request 표에 TRACK_STATE_REQ 행 추가
**old**:
```
| 0x1105 | SUBSCRIBE_LAYER | Simulcast 레이어 선택 (h/l/pause, targets 배치 지원) |
```
**new**:
```
| 0x1105 | SUBSCRIBE_LAYER | Simulcast 레이어 선택 (h/l/pause, targets 배치 지원) |
| 0x1106 | TRACK_STATE_REQ | duplex 전환 단일 경로 (half↔full). full→half 캐싱 보존 + active:false 통지, half→full 보존 stream 자동 재송출 + active:true / 신규 sub add. PUBLISH_TRACKS hot-swap 에서 분리 (이중화 금지, 2026-05-31) |
```

### 치환 4 — Event 표 TRACK_STATE 설명
**old**:
```
| 0x2102 | TRACK_STATE | mute 상태 브로드캐스트 |
```
**new**:
```
| 0x2102 | TRACK_STATE | 트랙 상태 통지 — mute(`muted` 필드) + duplex active/inactive(`active`+`source`+`duplex` 필드, 2026-05-31) |
```

### 치환 5 — "### Duplex hot-swap" 섹션 전체 교체
**old** (섹션 머리부터 "새 fan-out 로직 0줄" 줄까지 전부):
```
### Duplex hot-swap (클라 책임 + 서버 부수 처리)
- 클라가 PUBLISH_TRACKS 재전송으로 duplex 전환 (op=52 SWITCH_DUPLEX 폐기, 2026-04-30)
- 서버 hot-swap: `add_publisher_stream` 의 `streams.load().get(ssrc)` 매칭 시 `Arc::clone(&existing)` 반환 + ArcSwap 만 갱신 (atomic, Phase 2.7)
- half→full 부수 처리: prev_duplex 검사 → floor.release + apply_floor_actions → 후속 FullNonSim 자연 진입
- full→half 부수 처리: emit_per_user_tracks_update("remove") + mid 회수 + remove_subscriber_stream_by_vssrc + HalfNonSim skip
- 새 fan-out 로직 0줄 — TrackType 추상화가 라우팅 결정
```
**new**:
```
### Duplex 전환 (TRACK_STATE_REQ 단일 경로 + full→half 캐싱, 2026-05-31)
- **전환 신호 = `TRACK_STATE_REQ`(0x1106) 단일 경로** — PUBLISH_TRACKS hot-swap 에서 분리 (이중화 금지, 결정 D). PUBLISH_TRACKS 는 최초 등록 전용
- **분류 권위 = publisher `TrackType`** — fanout/forward 분기를 `publisher.track_type()` match 단일로 (Phase 1). `duplex_store(target)` 갱신만으로 fanout 경로 자동 선택, 새 fan-out 로직 0줄
- **full→half (캐싱 보존)** — 개인 SubscriberStream/mid/mid_pool 제거 안 함 (구 republish 폐기). publisher.duplex=Half → fanout HalfNonSim arm 이 broadcast_full 을 안 타 자동 미송출. 개인 mid 보유 sub 에 `TRACK_STATE{active:false}`. slot 은 collect 가 늘 상존
- **half→full (복귀)** — floor.release + publisher.duplex=Full → fanout broadcast_full 이 **보존 Weak 자동 재송출** (Phase 1+2 토대, 재활성 코드 최소). per-sub: 보존 sub(mid 보유) → `TRACK_STATE{active:true}` + video PLI burst(디코더 재개), 신규 sub(mid 미보유) → SubscriberStream 생성 + `TRACKS_UPDATE{add}`
- **생명주기 기준** — `collect_subscribe_tracks` 가 half 전환 개인 트랙(subscriber mid_map 보유 = full 이력)을 `active:false` 로 current_ids 에 포함 → `release_stale_mids` 회수 제외 (ROOM_SYNC 캐싱 생존). mid_map 미보유(half 로 시작)는 slot 만
- **클라(웹/Android) TRACK_STATE_REQ 발신 · 통지 수신 · 개인grid↔PTT slot UI 패러다임 전환 = 별도 작업** (미착수). 신규 sub add 경로 실행 검증도 멀티봇/클라 단계
```

### 치환 6 — 마일스톤에 duplex activeness 추가
**old** (Publisher 2계층 항목 끝 줄 + Phase ② Hall 줄):
```
- ⏸ **Phase ② Hall** — 부장님 명시(2026-05-02): 먼 미래로 보류.
```
**new**:
```
- ✅ **Duplex Activeness (half↔full 전환) 서버 3단계** (2026-05-31) — Phase 1 분류 권위 `TrackType` 단일화 (fanout/forward 분기를 `track_type()` match 로, is_half/is_simulcast_video 재조합 폐기) → Phase 2 full→half 캐싱 (republish 폐기 → 개인 SubscriberStream/mid 보존 + collect `active:false` 생명주기 기준 C) → Phase 3 `TRACK_STATE_REQ`(0x1106) 신설 + half→full 복귀(보존 Weak 자동 재송출) + 통지(결정 D: full→half active:false / half→full active:true·신규 sub add) + PUBLISH_TRACKS hot-swap 분리(이중화 금지). oxsig 54 + oxsfud 211 PASS + 회귀(conf_basic/ptt_rapid) 무변경 + duplex_cache 신규 e2e(음성 대조 FAIL 로 판별성). 클라(TRACK_STATE_REQ 발신·통지·UI 전환) + 신규 sub add 실행 검증 = 별도.
- ⏸ **Phase ② Hall** — 부장님 명시(2026-05-02): 먼 미래로 보류.
```

### 치환 7 — 아키텍처 원칙 "자료구조 단일 출처" (SubscribeMode 잔재 정정)
**old**:
```
- **자료구조 단일 출처** — 같은 정보(simulcast 여부, duplex 등)가 N 곳에 표현되면 시점 race 발생. enum + match exhaustiveness 로 호출처 갱신 강제. `SubscribeMode` (Audio/VideoNonSim/VideoSim/ViaSlot) 가 표준 패턴 — 등록 시점 1회 결정 후 불변, forward 본문은 `match self.mode` 단일 분기
```
**new**:
```
- **자료구조 단일 출처 + 분류 권위 단일** — 같은 정보(simulcast 여부, duplex 등)가 N 곳에 표현되면 시점 race. **분기 판단은 단일 주체로** — fanout/forward 의 모드 분기 = publisher `TrackType`(FullNonSim/FullSim/HalfNonSim) 단일 권위, `publisher.track_type()` 파생 (Phase 1, 2026-05-31). subscriber 의 `via_slot:bool` + `forwarder:Option` 은 *자료* 로 등록 시점 1회 결정 후 불변 (구 `SubscribeMode` enum 은 catch 6 에서 자료로 응축, 분류 *판단* 은 TrackType 으로 복원 — "자료 단순화가 분류 권위를 흩는" 안티패턴 회피)
```

---

## §2 운영 룰
- 7건 *외 수정 금지*. 오타/줄바꿈 보존.
- 각 건 dryRun GREEN 확인 후 일괄 apply. old 가 0회/2회 매칭되면 중단 + 보고 (내가 텍스트 다시 특정).
- 빌드/테스트 불필요 (문서만). 커밋은 부장님 판단.

## §3 산출물
- PROJECT_MASTER.md 7건 치환.
- 보고: 7건 각 apply 결과 (매칭 1회 확인).

---

*author: kodeholic (powered by Claude)*
