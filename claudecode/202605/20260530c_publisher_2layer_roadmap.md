# 작업 지침 — Publisher 2계층 전환 (Stream 논리 / Track 물리), GREEN 점진

문서 ID: `20260530c_publisher_2layer_roadmap.md`
작성: 김대리 (claude.ai)
대상: 김과장 (Claude Code)
성격: 대공사. **매 단계 GREEN 유지** (빌드 폭발 금지). 본 문서는 전체 로드맵 + **단계 1 지침**.
폐기: `20260530a`(빌드 폭발 방식) / `20260530b`(국소 수술) — 둘 다 폐기. 본 문서가 유일 유효.

---

## §0 의무 점검

1. 현재 빌드 GREEN + `cargo test` PASS 기준선 확인 (211 예상).
2. PROJECT_MASTER "Peer 재설계 원칙" + "자료구조 단일 출처" + "mechanical refactor 함정" 절 재독.
3. 명명 규칙 확정 (OxLens): **`Stream` = 논리 계층(camera/screen), `Track` = 물리 최소(SSRC)**. 클라이언트 `MediaStream ⊃ MediaStreamTrack` 정합. 포함: `PublishContext ⊃ PublisherStream(논리) ⊃ PublisherTrack(물리)`.

---

## §1 컨텍스트 — 왜 2계층

### 결함 (명제 B — 확정)
`PublishContext.pli_state: Mutex<PliPublisherState>` 가 publisher 당 **단일**. `publisher_stream.rs::fanout` keyframe 블록에서 camera-h(simulcast High)와 screen(non-sim → `Layer::High`)이 같은 `layers[High]` 슬롯 공유 → screen keyframe 이 camera-h pending 거짓 해제. camera+screen 동시 발행 시 PLI 오염. catch 4(`simulcast_pli_pending`)도 동일 자리 동일 병.

### 근본 원인
"video source(camera/screen) = 논리 단위" 계층이 부재. 현 `PublisherStream`은 SSRC(물리) 단위라 camera-h/camera-l/screen 이 각각 별 인스턴스 — source 단위로 묶을 자리가 없음. `simulcast_group: Option<u32>` 약한 끈으로만 흉내. → 논리 계층 신설로 근본 해소.

### 방식 — GREEN 점진 (빌드 폭발 폐기)
직전 시도(`20260530a`)는 타입 바꿔 빌드 폭발시키고 에러 목록을 todo 로 삼으려 했으나 **실패** — Claude Code 가 GREEN 본능이라 안 멈추고 끝없이 고침. 본 작업은 **매 단계가 작고 컴파일 GREEN + 테스트 PASS** 를 정지점으로. 호출처는 빌드 폭발에 안 맡기고 김대리가 단계별로 조사해 명시.

---

## §2 전체 로드맵 (누락 방지 — 4단계 전부 명시)

> 각 단계 끝 = `cargo build` GREEN + `cargo test` PASS 필수. 한 단계 = 하나의 정지점.

### 단계 1 — 순수 rename: `PublisherStream` → `PublisherTrack` [본 지침 §4]
- 현 SSRC 단위 자료구조 = 물리 = `PublisherTrack` 확정. **의미·동작 0 변경.** 컴파일러 일괄 치환.
- 목적: 논리 계층에 `PublisherStream` 이름을 비워줌 (같은 이름 두 의미 동시 존재 방지 = mechanical 함정 회피).
- 위험: **0** (rename). 빌드 폭발 아님.

### 단계 2 — 논리 `PublisherStream` 신설 + PLI 자료 이주 (명제 B + catch 4 해결)
- `PublisherStream`(논리) struct 신설: source/kind/mid/duplex/simulcast/virtual_ssrc/subscribers/phase + `pli_state`/`simulcast_pli_pending`/`pli_burst_handle`/`tracks: Vec<Arc<PublisherTrack>>`.
- `PublishContext.streams`(논리) 추가, source 별로 `PublisherTrack` 묶기.
- `pli_state`/`simulcast_pli_pending` 을 PublishContext → 논리 `PublisherStream` 으로 이주. fanout/pli.rs/governor/admin 호출처를 source 단위 조회로 전환.
- **명제 B + catch 4 여기서 해결.**
- 호출처 조사: 단계 1 GREEN 후 ingress_rtcp/tasks/track_ops/admin/helpers 정밀 조사 → 단계 2 지침 별도 작성.

### 단계 3 — fan-out 을 Stream(논리) 기준으로 전환
- `subscribers`/`broadcast_full`/`fanout` 를 PublisherTrack(SSRC) → PublisherStream(논리) 진입으로. `tracks_by_ssrc` hot path 인덱스 정비.

### 단계 4 — recv_stats Track 귀속 + 정리 + 회귀
- `PublishContext.recv_stats: DashMap` 통째 → 각 `PublisherTrack.recv_stats` 분산. `simulcast_group` 약한 끈 폐기.
- 회귀 시나리오 `camera+screen 동시 + screen keyframe`(명제 B 검증) oxe2e 추가.

> 단계 2~4 의 정밀 지침은 **각 단계 GREEN 확인 후** 호출처 재조사하여 작성. 본 문서는 로드맵 + 단계 1 확정.

---

## §3 결정 추천 (★ 정지점 — 부장님 확인)

| 항목 | 추천 | 근거 |
|---|---|---|
| 단계 1 = rename 먼저 | **채택** | 논리에 `PublisherStream` 이름 비우기. 위험 0. 명명 혼동 시간차 분리 |
| `PublishContext.streams` 필드명 (단계 1 후 임시) | `tracks`로 rename | 단계 1 시점 = PublisherTrack 직접 보유. 단계 2 에서 `streams`(논리) 재도입 |
| 단계 2 묶음 키 | source | screen non-sim 커버 (simulcast_group None 회피) |

→ 부장님: **로드맵 단계 순서**(특히 rename 먼저)에 이견 있으면 지금 조정. 단계 1 자체는 위험 0.

---

## §4 단계 1 작업 — 순수 rename [정지점: GREEN + test]

**원칙: 이름만 치환. 로직/시그니처 구조/동작 일절 변경 금지.** 아래 목록 외 변경 = 범위 위반.

### 치환 목록
**타입**
- `PublisherStream` → `PublisherTrack`
- `PublisherStreamIndex` → `PublisherTrackIndex`
- `PublisherStreamSnapshot` → `PublisherTrackSnapshot`

**파일** (`git mv` 후 내부 치환)
- `room/publisher_stream.rs` → `room/publisher_track.rs`
- `room/publisher_stream_index.rs` → `room/publisher_track_index.rs`
- `room/mod.rs`: `pub mod publisher_stream;` → `pub mod publisher_track;` (+ index 동일)

**Peer 메서드 (peer.rs)**
- `add_publisher_stream` → `add_publisher_track`
- `register_publisher_stream` → `register_publisher_track`
- `remove_publisher_stream` → `remove_publisher_track`
- `find_publisher_stream` → `find_publisher_track`
- `first_stream_of_kind` → `first_track_of_kind`
- `switch_stream_duplex` → `switch_track_duplex`
- `set_stream_muted` → `set_track_muted`
- `publisher_streams_snapshot` → `publisher_tracks_snapshot`

**PublishContext 필드 (peer.rs)**
- `streams: ArcSwap<PublisherStreamIndex>` → `tracks: ArcSwap<PublisherTrackIndex>`
- 접근부 `peer.publish.streams` → `peer.publish.tracks` 전량 (호출처 다수 — 컴파일러가 전부 지목)

### 유지 (이름 안 바꿈)
- `create_or_update_at_rtp` / `fanout` / `broadcast_full` / `attach_subscriber` 등 **메서드 이름은 그대로** (PublisherTrack 의 메서드가 됨).
- `subscriber_stream.rs` 의 `PacketContext.publisher: &PublisherStream` → 타입명만 `&PublisherTrack` (필드명 publisher 유지).
- 변수명 `stream`/`streams` 지역변수는 바꿔도/둬도 무방 — 단 통일 위해 `track`/`tracks` 권장 (선택, 동작 무관).

### 절차 (Claude Code)
1. IDE rename 또는 `rg -l` 기반 sed 일괄 치환 — 위 목록 순서대로.
2. `cargo build` — 에러는 **누락된 치환 자리**만 (의미 에러 아님). 컴파일러 지목 따라 치환 완결.
3. `cargo test` PASS — 동작 0 변경이므로 기존 테스트 그대로 통과해야 함. **테스트가 깨지면 rename 외 변경이 섞인 것** → 되돌려 점검.
4. **정지점**: GREEN + test PASS → 부장님 보고. 단계 2 진입 대기.

---

## §5 변경 영향 범위 (단계 1)

- rename 대상이라 **전 파일에 걸침** (PublisherStream 참조처 전부). 단 전부 이름 치환 — 로직 변경 0.
- 컴파일러가 누락 자리 100% 지목 (rename 은 의미 변경 0 이라 컴파일러 신뢰 가능 — 빌드 폭발과 다른 점).

---

## §6 운영 룰

1. **정지점**: 단계 1 끝 (GREEN + test). 보고 + GO 후 단계 2.
2. **로직 변경 절대 금지** (단계 1). 이름 치환만. 발견한 개선/결함은 _done 에 메모만.
3. **2회 실패 시 중단**: rename 후 test 가 깨지고 2회 시도로 원인(섞인 변경) 못 찾으면 중단 + 보고.

---

## §7 기각 접근법

- **빌드 폭발 → 에러 목록 todo** (`20260530a`) — 기각. Claude Code GREEN 본능과 충돌, 안 멈춤.
- **국소 수술 (PLI 자료만 source 키 DashMap)** (`20260530b`) — 기각. 약한 끈 잔존, 2계층 포기. 부장님 결정 = 근본(2계층).
- **rename 없이 논리 신설** — 기각. 현 `PublisherStream`(SSRC) 이름 점유 상태에서 논리 `PublisherStream` 신설 = 같은 이름 두 의미 동시 → mechanical 함정.
- **rename + 논리 신설 한 단계에** — 기각. 한 단계가 커지면 GREEN 정지점 흐려짐. rename(위험0) 과 논리신설(자료 이주) 분리.

---

## §8 산출물

- 단계 1: rename 완료된 트리 + GREEN + test PASS.
- `_done` 보고: 치환 목록 1:1 완료 확인 + 빌드/테스트 결과 + (발견 시) 로직 메모.

---

## §9 시작 전 확인

- [ ] 빌드 GREEN + test PASS (기준선)
- [ ] §3 — 부장님 로드맵 단계 순서 GO (rename 먼저)
- [ ] 단계 1 = 이름 치환만, 로직 0 변경 숙지

---

## §10 직전 작업 처리

- `20260530a`(2계층 빌드폭발) → 롤백. `20260530b`(국소) → 폐기 (작성만 됨, 미실행).
- 본 문서가 2계층 유일 유효 지침. 단계 2~4 정밀 지침은 단계 1 GREEN 후 순차 작성.
- 후속 작업(부장님 별건)은 본 로드맵과 독립 — 단계 사이 정지점에서 끼워넣기 가능.

---

*author: kodeholic (powered by Claude)*
