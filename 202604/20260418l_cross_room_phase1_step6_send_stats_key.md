# Cross-Room Federation Phase 1 Step 6 — send_stats/stalled_tracker 키 확장

- 날짜: 2026-04-18
- 범위: Phase 1 Step 6 (설계서 §10.2)
- 결과: ✅ 완료 (빌드/테스트/E2E 통과)

## 목표

`send_stats` / `stalled_tracker` 맵의 key를 `u32 (ssrc)` → `(u32, String) (ssrc, room_id)` 로 확장.

**왜 필요**: Conference 원본 SSRC 유지 relay 원칙에서 같은 subscriber가 여러 방에서 같은 원본 SSRC를 받을 때 방별 독립된 `packet_count/octet_count` 및 SR 생성 보장. Phase 1 단일방 환경에서는 실질 동작 변화 없음 — 자료구조 확장이 목적.

## 호출처 전수 조사 (7곳)

| # | 파일:함수 | 접근 패턴 | room_id 획득 경로 |
|---|----------|---------|------------------|
| 1 | `participant.rs` 필드 정의 + 초기화 | 타입 선언 | — |
| 2 | `egress.rs::run_egress_task` | write (매 RTP) | `participant.room_id` (subscriber 본인 방) |
| 3 | `ingress.rs::build_sr_translation` Simulcast | read | `sender.room_id` (Step 5 원칙) |
| 4 | `ingress.rs::build_sr_translation` Non-sim | read | `sender.room_id` |
| 5 | `tasks.rs::run_stalled_checker` | read (tracker iter_mut + send_stats get) | `room.id` (상위 루프) |
| 6 | `track_ops.rs::record_stalled_snapshot` | read+write | `room.id` (파라미터) |
| 7 | `admin.rs`, `rtcp_terminator.rs`, `room.rs`, `grpc/sfu_service.rs` | 직접 접근 없음 | ✅ |

**Step 5 반성 체크리스트 엄격 적용**: 핫패스 파일(egress.rs 포함) 수동 포함, RTCP 경로/admin 경로까지 교차 확인. 결과: 한 번에 빌드 통과, 누락 없음.

## 설계 결정

### egress.rs `run_egress_task`의 room_id 선택

**채택**: `participant.room_id` (subscriber 본인 방)

근거:
- `run_egress_task`는 subscriber 전용 task — subscriber의 방 정보 자연 확보
- Phase 1 단일방: `subscriber.room_id == publisher.room_id` 동치
- Step 6 범위를 "key 확장만"에 좁게 유지

**기각 (Step 9~10으로 연기)**:
- `EgressPacket` enum에 `room_id` 필드 추가 (fan-out source room)
- Phase 2에서 정확한 의미(fan-out 경로의 source room)를 반영하려면 필요하지만 Step 6 범위 초과
- 4개 fan-out 사이트 변경 + consume 사이트 연쇄 → Step 9~10 "SR Translation multi-room 재설계"와 일괄

### `StalledSnapshot` 구조체 불변

- `publisher_id`, `kind` 필드 이미 존재 (agg-log용)
- `room_id`는 **key에만** 포함, value 구조체 변경 불필요

### `ingress.rs::build_sr_translation`은 `sender.room_id` 사용

Step 5에서 확립된 원칙 유지. 함수가 "publisher 기준 송신 변환"이므로 publisher의 방이 논리적.

## 코드 변경 (5파일 ~15줄)

1. `participant.rs` — 두 필드 타입 변경 + Phase 1 Step 6 주석
2. `egress.rs::run_egress_task` — `let key = (ssrc, participant.room_id.clone())` + `entry(key)`
3. `ingress.rs::build_sr_translation` Simulcast — `get(&(vssrc, sender.room_id.clone()))`
4. `ingress.rs::build_sr_translation` Non-sim — `get(&(pub_ssrc, sender.room_id.clone()))`
5. `tasks.rs::run_stalled_checker` — `for (&(ssrc, ref rid), snap) in tracker.iter_mut()` + `send_stats.get(&(ssrc, rid.clone()))`
6. `track_ops.rs::record_stalled_snapshot` — `room_id = room.id.clone()` 캐시 + `send_stats.get(&key)` + `tracker.insert(key, ...)` + `prev_notified` 맵 키 확장

## 검증

- `cargo check --release`: 에러 0, 빌드 통과
- `cargo test -p oxsfud --release room::endpoint`: **9/9 통과**
- `cargo build --release`: 성공
- **E2E 3명 시나리오 스냅샷 확인** (demo_vid, U695/U388/U842):
  - AGG LOG에 STALLED 엔트리 없음 (오탐 0건)
  - Pipeline Stats 정상 (relayed delta 288, gated delta 정상)
  - `[server:ptt] rewritten=288 video_rw=288` — video rewrite 정상
  - Contract check에서 Step 6 관련 regression 없음

## 기각 사항 (세션 내 결정)

- ❌ `EgressPacket::Rtp(Vec<u8>, String)` 즉시 확장 — Step 9~10 범위, 4개 fan-out 사이트 연쇄 변경 필요
- ❌ `StalledSnapshot`에 `room_id` 필드 추가 — key에 있으면 충분, 중복 정보
- ❌ `RoomId` newtype 도입 — Phase 1 끝(Step 10)에 일괄 (Step 5와 동일 원칙)
- ❌ Step 6 범위에서 `send_stats`를 Endpoint로 이동 — Step 7 범위

## 오늘의 지침 (반성/환류)

### Step 5 반성 체크리스트가 작동했다
Step 5에서 `cd` 실패 후 업로드 폴더만 grep해서 ingress.rs를 놓쳤던 실수가 있었다. Step 6에서는:
- ✅ 핫패스 파일을 **이름으로 명시** 수동 포함: ingress.rs, egress.rs, ingress_subscribe.rs, ingress_mbcp.rs, rtcp_terminator.rs
- ✅ Filesystem:read_text_file로 의심 파일 직접 읽어 내부 grep
- ✅ 정의 파일(participant.rs) + 실제 사용 파일(egress/ingress/tasks/track_ops) + 추가 의심(admin/room/sfu_service) 3단계 확인

**결과: 한 번에 빌드 통과, 누락 호출처 0.** 체크리스트가 설계 단계에서 작동.

### HashMap 키 타입 확장은 컴파일러가 강하게 체크
`HashMap<u32, V>` → `HashMap<(u32, String), V>` 같은 변경은 모든 호출처를 컴파일러가 잡아준다. **빌드 통과 = 전수 발견 완료**의 강한 보증. Step 9~10의 enum 필드 추가, 구조체 리네임 등도 같은 성질. 타입 변경 기반 리팩터링은 안전.

### tuple 패턴 destructuring 유의
`for (&(ssrc, ref rid), snap) in tracker.iter_mut()` — `u32`는 Copy라 `&(ssrc, ...)` 가능, `String`은 `ref rid`로 참조. 한 번에 맞았음. 두 자료형 섞인 tuple key에서 반복 유용.

## 발견된 별건 이슈 (기록 — 다음 세션에서 해결)

### PTT talking 전환 시 audio not_enabled 버그

**증상**: video_radio 시나리오에서 PTT 눌러도 U842(talking) 오디오가 안 들림.

**진단 근거**:
- 서버: `[U842:audio] pkts_delta=0` + `[server:ptt] audio_rw=0` → RTP 자체 미도착
- 클라 콘솔: `[POWER:METRICS] restore audio=not_enabled(0ms)` 3회 반복 + `[PIPE:camera] setTrack kind=video` 만 있고 audio setTrack 없음
- `[U842:sender:unknown] hasTrack=false` — audio sender에 track 미부착

**근본 원인**: `pipe.js resume()`가 `TrackState.INACTIVE` 상태에서 `'not_enabled'` 반환. `power-manager.js _doEnsureHot`는 `'need_track'` 분기에서만 `acquire.audio()` 호출 → audio는 영영 활성화 안 됨.

**회귀 시점 추정**: 0418a Pipe Track Gateway 전환 시 `sender.replaceTrack` 17→0 중앙화 과정에서 기존 `_publishMic` 경로의 "audio RELEASED 초기화"가 이관 안 됨. video는 다른 경로로 RELEASED 되는 듯하나 audio는 INACTIVE 그대로.

**수정 방향 (다음 세션 검토용)**:
- **안 A (추천)**: `pipe.js resume()`의 `INACTIVE → 'not_enabled'`를 `INACTIVE → 'need_track'`으로 변경. "최초 활성화도 새 track 필요"라는 의미. 1줄 변경, `'not_enabled'` 반환값이 dead code 되므로 정리 가능.
- **안 B**: PowerManager `_doEnsureHot`에서 `'not_enabled'` 분기도 acquire 호출. 버그 마스킹 느낌.

**설계 의도 확인 필요**: `context/design/20260417_pipe_track_gateway_design.md` Phase 2 섹션에서 `TrackState.INACTIVE → 'not_enabled'`를 의도적으로 둔 이유 확인 후 안 A로 진행 권장.

**Step 6 커밋과 분리** — 서버 변경 + 클라 버그픽스 혼재 방지. 별도 커밋 + 별도 세션.

## 남은 Phase 1 로드맵

| Step | 내용 | 상태 |
|------|------|------|
| 4 | STUN 인덱스 EndpointMap 이동 | ✅ |
| 5 | subscribe_layers 키 확장 | ✅ |
| 6 | send_stats/stalled_tracker 키 확장 | ✅ |
| 7 | Track 소유권 Endpoint 단일 소유 (§10.4 옵션 A) | 미착수 |
| 8 | Participant → RoomMember 리네임 + 역할 축소 | 미착수 |
| 9 | collect_subscribe_tracks multi-room + ingress fan-out multi-room (§4) | 미착수 |
| 10 | 어드민 Endpoint 뷰 + agg-log 정비 + build_sr_translation multi-room 재설계 + PROJECT_MASTER.md 일괄 갱신 | 미착수 |

Phase 1 완료 시 PROJECT_MASTER.md 일괄 갱신 (중간 상태 박제 금지 원칙 유지).

---

*author: kodeholic (powered by Claude)*
