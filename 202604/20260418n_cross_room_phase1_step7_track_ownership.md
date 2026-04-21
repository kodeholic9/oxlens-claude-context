# 2026-04-18 Cross-Room Federation Phase 1 Step 7: Track 소유권 Endpoint 이동

## 목표
Track 소유권(`tracks` + `rtx_ssrc_counter` 필드, 관련 메서드 9개)을
Participant → Endpoint로 이동. 설계서 §10.4 옵션 A 확정.

## 사전 확정사항 (세션 시작 시 부장님 지시)
- **이동 대상**: `tracks`, `rtx_ssrc_counter` + 메서드 8개 + `alloc_rtx_ssrc` 내부 함수
- **Step 7 범위 외 (Participant 유지)**: `rtx_seq`, `rtp_cache`, `recv_stats`,
  `send_stats`, `simulcast_video_ssrc`, `expected_*_pt`, `stalled_tracker`,
  `twcc_recorder`, `stream_map`, `subscribe_layers`, `subscriber_gate`, `pli_pub_state`
  (Phase 2 RoomMember 분리 때 재배치)
- **별건 (섞지 말 것)**: PTT audio `not_enabled` 버그(0418l 기록) — 별도 세션/커밋
- **RoomId newtype / Participant→RoomMember 리네임**: Step 8~10 일괄
- **EgressPacket room_id 추가**: Step 9~10 일괄

## 호출처 전수조사

부장님 조사: 13파일 52건 (당초 12파일 리스트, **floor_ops.rs 1파일 1건 누락** — cargo check 수정 단계에서 발견)

| 파일 | 부장님 카운트 | 실제 치환 | 비고 |
|---|---|---|---|
| track_ops.rs | 15 | 0 | **이미 선제 치환 완료** (Step 7 설계 확정 전) |
| ingress.rs | 7 | 7 | |
| helpers.rs | 6 | 4 | (중첩 카운팅 차이) |
| ingress_subscribe.rs | 5 | 7 | |
| room_ops.rs | 4 | 1 | **3건 이미 선제 치환 완료** |
| tasks.rs | 4 | 4 | |
| egress.rs | 3 | 3 | |
| room.rs | 3 | 3 | |
| admin.rs | 2 | 2 | |
| ingress_mbcp.rs | 1 | 1 | |
| floor_broadcast.rs | 1 | 1 | |
| datachannel/mod.rs | 1 | 1 | |
| **floor_ops.rs** | **0 (누락)** | **1** | **cargo check에서 발견** |
| **합계** | **52** | **35** | ~18건 선제 처리분 + 1건 누락 보정 |

## 작업 분할 (additive → 치환 → removal)

### Phase 1: endpoint.rs 확장 (이전 세션)
- `pub tracks: Mutex<Vec<Track>>` + `rtx_ssrc_counter: AtomicU32` 필드 신규
- 메서드 9개 이관: `add_track`/`add_track_ext`/`add_track_full`(private)/
  `get_video_codec`/`alloc_rtx_ssrc`(private)/`remove_track`/
  `switch_track_duplex`/`set_track_muted`/`get_tracks`
- 단위 테스트 3개 신규

### Phase 2: 호출처 치환 (이번 세션)
13파일 35건. `participant.tracks.lock()` → `participant.endpoint.tracks.lock()` 등.

### Phase 3: participant.rs 제거 (이전 세션)
- 필드 2개 제거 + `Participant::new` 초기화 제거
- 메서드 9개 제거 (`next_rtx_seq`는 `rtx_seq` 필드와 세트로 유지)

## 검증 결과
cargo check --release:   0 errors (3.10s)
cargo test -p oxsfud --release room::endpoint:
12 passed; 0 failed (기존 9 + Step 7 신규 3)
cargo build --release:   0 errors (4.69s)

신규 테스트 3건:
- `endpoint_add_remove_roundtrip`
- `endpoint_rtx_unique_per_media`
- `endpoint_switch_duplex_excludes_simulcast_layers`

**E2E (voice_radio + video_radio)**: 부장님 확인 대기.

## 반성

### 오늘의 기각 후보
1. **부장님 전수조사를 100% 신뢰하고 바로 편집 시작** — floor_ops.rs 누락을 놓치고
   cargo check 왕복 1회 소비. 컴파일러가 잡긴 하지만 예방 가능했음.
2. **str_replace로 Korean context 포함 편집** — 과거 encoding 실패 경험. 이번 세션은
   `Filesystem:edit_file` 전환으로 100% 성공. 향후 str_replace 재진입 금지.

### 오늘의 지침 후보 (코드에 남지 않는, 반복 위험 높은 원칙)

1. **타입 기반 리팩터링: 편집 완료 직후 전체 crate 독립 grep 1회 필수 (cargo check 전에)**
```bash
   grep -rn -E '<직접접근 패턴들>' <crate_root> | grep -v '<새 경로 패턴>' | grep -v '//'
```
   결과 0건 확인 후에야 cargo check 실행. cargo 왕복 횟수 최소화.

2. **부장님 제공 전수조사는 수령자 측도 독립 grep으로 교차검증**
   - "N파일 M건" 숫자 합계가 맞아도 파일 리스트 자체 누락 가능 (이번 floor_ops.rs 사례)
   - 세션 시작 체크리스트: ① 설계 문서 읽기 → ② 호출처 독립 grep → ③ 부장님 리스트와 교차 → ④ 편집 계획

3. **additive → 치환 → removal 3-Phase 분할의 가치 재확인**
   - 중간 상태에서도 빌드 가능 → 편집 흐름 끊기지 않음
   - 이번처럼 Phase 3가 선행 완료된 상태여도 Phase 1 덕분에 endpoint.rs 정의가
     이미 존재 → 치환만 수행하면 최종 일치 상태로 수렴

### 플러스 포인트
- `Filesystem:edit_file` dryRun/실제 적용 과정에서 Korean context가 한 번도
  encoding 실패 없이 매칭됨. str_replace 비교 우위 재확인.
- 타입 기반 리팩터링(필드 이동)은 매크로/동적 호출이 없는 한 컴파일러가 완벽히
  전수검증. Step 7 전체를 안전하게 끌고 온 근본 이유.

## Phase 1 로드맵

| Step | 범위 | 상태 |
|---|---|---|
| Step 1 | Endpoint/EndpointMap 뼈대 | ✅ |
| Step 2 | MidPool 이동 | ✅ |
| Step 3 | cross-room floor 제약 (active_floor_room) | ✅ |
| Step 4 | STUN 인덱스 EndpointMap 이동 | ✅ |
| Step 5 | subscribe_layers 키 확장 ((pub_id, room_id)) | ✅ |
| Step 6 | send_stats/stalled_tracker 키 확장 ((ssrc, room_id)) | ✅ |
| **Step 7** | **Track 소유권 Endpoint 이동** | **✅ (이번 세션)** |
| Step 8 | Participant → RoomMember 리네임 + RoomId newtype | 다음 세션 |
| Step 9 | EgressPacket room_id 추가 + cross-room fan-out 경로 | 다음 세션 |
| Step 10 | build_sr_translation multi-room 재설계 + 최종 통합 테스트 | 다음 세션 |

## 별건 (다음 세션이 아닌 별도 세션에서)
- PTT audio `not_enabled` 버그 (0418l): `pipe.js` resume INACTIVE→`'need_track'` 경로.
  Phase 1 완료 후 별도 세션/별도 커밋.

---

*author: kodeholic (powered by Claude)*