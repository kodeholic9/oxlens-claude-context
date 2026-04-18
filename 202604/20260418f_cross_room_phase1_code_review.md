// author: kodeholic (powered by Claude)

# 2026-04-18 (f) — Cross-Room Federation Phase 1 코드 리뷰

**저장 위치**: `context/202604/20260418f_cross_room_phase1_code_review.md`
**연관 설계 문서**: `context/design/20260416_cross_room_federation_design.md` (§10 addendum 추가)
**선행 논의**: `context/202604/20260416a_cross_room_federation.md`

> **2026-04-18 용어 교체**: 초기 설계의 `Connection` → `Endpoint`로 일괄 전환.
> 근거: WebRTC `PeerConnection` 혼동 + 일반성 과도. 서버 코드에 이미 `peer_addr`/`PeerAddrHandle`/`PeerConnection` 3가지 맥락으로 `peer`가 존재하므로 `Peer`도 기각. RTCP Terminator 원칙("SFU는 RTP 세션의 endpoint")과 일치하는 `Endpoint` 채택.

---

## 세션 목적

- Cross-Room Federation Phase 1 착수 전 **실제 코드 구조 vs 설계서 매핑**
- 설계서만으로는 드러나지 않는 리팩터링 리스크 사전 식별
- 공수 실측 재평가
- 신규 구조체 네이밍 확정

---

## 읽은 파일

| 파일 | 크기 | 용도 |
|------|------|------|
| `crates/oxsfud/src/room/participant.rs` | 42.5 KB | 분리 대상 본체 (필드 50+) |
| `crates/oxsfud/src/room/room.rs` (head 120) | 19.3 KB | RoomHub / STUN 인덱스 |
| `crates/oxsfud/src/signaling/handler/helpers.rs` (head 250) | — | `collect_subscribe_tracks` 구조 |

---

## Participant 필드 분류 (이동처 매핑)

### Endpoint 이동 (~35 필드)
- **Identity/생명주기**: `user_id`, `participant_type`, `joined_at`, `last_seen`, `suspect_since`, `phase`
- **Transport (ICE/DTLS/SRTP)**: `publish: MediaSession`, `subscribe: MediaSession`
- **Egress (mpsc)**: `egress_tx`, `egress_rx`
- **Publisher 상태**: `rtp_cache`, `rtx_ssrc_counter`, `rtx_seq`, `twcc_recorder`, `recv_stats`, `last_audio_arrival_us`, `last_video_rtp_ms`, `rtp_gap_suppress_until_ms`, `last_pli_relay_ms`, `pli_pub_state`, `twcc_extmap_id`, `simulcast_video_ssrc`, `stream_map`
- **Subscriber 상태**: `send_stats`, `rtx_budget_used`, `nack_suppress_until_ms`, `expected_video_pt`, `expected_rtx_pt`, `subscriber_gate`, `subscribe_layers`, `stalled_tracker`, `sub_mid_pool`, `sub_mid_map`
- **DataChannel**: `dc_unreliable_tx`, `dc_unreliable_ready`, `dc_pending_buf`
- **진단/기타**: `pipeline`, `pli_burst_handle`

### RoomMember 이동 (~3 필드)
- `role: u8` (moderate role, 방별)
- `tracks: Mutex<Vec<Track>>` — **단, 설계서 §10.4에서 Endpoint 단일 소유로 확정**
- `room_id` (암시적, RoomMember 생성 시 주입)

### Endpoint 신규 필드
- `active_floor_room: AtomicU8 또는 Mutex<Option<RoomId>>`
- `rooms: DashSet<RoomId>` (또는 `HashSet` + Mutex)

---

## 드러난 리스크 4개 (설계서 §10으로 확정)

### 10.1 `subscribe_layers` 키 확장
- 현재: `HashMap<publisher_id, SubscribeLayerEntry>`
- `SubscribeLayerEntry`가 `SimulcastRewriter { virtual_ssrc }` 소유 → publisher:virtual_ssrc = 1:1 전제
- cross-room에선 같은 publisher를 Room 1/2로 두 번 구독 → mid 2개 → virtual_ssrc 2개 필요
- **확정**: key `(publisher_id, room_id)` 확장

### 10.2 `send_stats` / `stalled_tracker` 방별 독립 키
- 현재: `HashMap<ssrc, SendStats>`
- Conference 모드는 원본 SSRC 유지 relay → Room 1/2 송신이 같은 SSRC → 한 SendStats에 두 방 통계 섞임
- SR `packet_count/octet_count` 오염 → jb_delay 누적
- **확정**: key `(ssrc, room_id)` 확장 — 상위 리뷰에서 짚은 "SR Translation 방별 독립"의 실체

### 10.3 STUN 인덱스 Room → EndpointMap 이동
- 현재: `Room.by_ufrag`, `Room.by_addr` — 방별 STUN 인덱스
- Endpoint가 다중 방 소속이면 "ufrag는 어느 방 인덱스?" 질문이 무의미
- **확정**: 전역 `EndpointMap { by_user, by_ufrag, by_addr }` 신설. Room은 `members: DashMap<user_id, RoomMember>` 만

### 10.4 Track 소유권 — Endpoint 단일 소유
- 옵션 A: Endpoint.tracks + RoomMember.publish_intent
- 옵션 B: RoomMember가 Track 소유, 방별 중복 등록 **← 기각**
  - 핫패스 비용, mute/duplex 전파 부담, "sfud=빈깡통" 위배
- **확정**: 옵션 A

---

## 네이밍 논의 (Connection → Peer → Endpoint)

### 1차 제안: `Connection`
- 부장님 이견: WebRTC `RTCPeerConnection`과 혼동. 너무 일반적

### 2차 제안: `Peer`
- 부장님 질의: 서버 소스 내에서 peer 용법은?
- 실측: `grep -rn` 결과
  - `peer_addr`: 14건 (transport 계층 UDP 주소)
  - `PeerAddrHandle`: 6건 (DTLS/SCTP 공유 핸들 타입)
  - `peer` 주석: 7건 (RTCP "서버가 peer로서 RR/SR 생성" 원칙)
  - `PeerConnection`: 3건 (주석만, 클라 RTCPeerConnection 지칭)
- 판단: **타입명 `Peer` 도입 시 `peer_addr` 변수와 같은 함수에 공존 위험 확정** → 기각

### 3차 확정: `Endpoint`
- 부장님 우려: SDK Endpoint와 PeerConnection 동등 개념 아님
- 답: sfud 레벨 `Endpoint`는 "RTP 세션 종단점" (RFC/RTP 표준 용어, RTCP Terminator 원칙 일치)
- SDK Endpoint는 앱 레벨 원격 참가자 — 레이어 완전 분리, 실무 혼동 없음
- **부장님 확정 지시**: "Endpoint로 일괄 치환"

---

## 공수 재평가

| 작업 | 주차 |
|------|------|
| Endpoint / RoomMember 분리 기본 | 1주 |
| 10.1~10.2 키 확장 — SR/Simulcast/STALLED 회귀 포함 | +1주 |
| 10.3 STUN 인덱스 재배치 | +3~4일 |
| 어드민 Endpoint 뷰 + agg-log | +2~3일 |
| Participant 참조 경로 전체 수정 (100곳+) | 상시 |

**총 2~3주**. 초기 제안한 "1주+"는 낙관 추정이었음.

---

## 오늘의 기각 후보

- **옵션 B (RoomMember Track 소유)**: 핫패스 반복, 동기화 부담, "sfud=빈깡통" 위배
- **구조체명 `Connection`**: WebRTC PeerConnection 혼동 + 일반성 과도
- **구조체명 `Peer`**: `peer_addr`/`PeerAddrHandle` 공존 혼동 확정
- **서버 측 subscribe dedup**: §7 기존 기각 재확인 (디버깅 지옥)
- **연합 중첩 (방의 방)**: §7 기존 기각 재확인 (flat only)
- **설계서 없이 코드부터 작성**: 리팩터링 범위가 SR/Simulcast/STALLED 도메인 전체 건드림 → 사전 설계 필수

---

## 오늘의 지침 후보 (PROJECT_MASTER.md 반영 검토)

1. **"설계서에 없는 순서를 있는 것처럼 말하지 말 것"** — 김대리 행동 원칙 추가 후보
   - 2026-04-18 세션에서 설계서에 없는 Step 1~5 순서를 설계서 기반인 것처럼 제시 → 부장님 지적
   - 대응: "설계서 그대로 / 제 제안" 구분 표기 의무화

2. **"리팩터링 규모 추정은 실측 후에만"** — 공수 추정 원칙 후보
   - 파일 안 보고 "1주+" 추정 → 실측 후 "2~3주"로 상향
   - 대응: 대규모 리팩터링은 **핵심 파일 3~5개 실측 전 공수 추정 금지**

3. **"cross-room 설계는 방별 독립성 검증이 설계 완료 조건"** — 설계 체크리스트 후보
   - subscribe_layers / send_stats / stalled_tracker / STUN 인덱스 모두 "방별 독립" 관점으로 봐야 빈틈 드러남
   - 대응: cross-room 관련 구조체 추가 시 "방별 독립 키인가?" 체크 필수

4. **"공식 문서 업데이트는 반드시 파일 형식 확인 후"** — SESSION_INDEX/CHANGELOG 등
   - 부장님 지적: SESSION_INDEX.md 형식 안 보고 임의 불릿으로 블록 제시
   - 대응: 공식 문서 업데이트 블록 제시 전 반드시 실제 파일 형식 read로 확인

5. **"네이밍 충돌은 실측 grep으로 확정"** — 네이밍 원칙 후보
   - Peer 네이밍 판단 시 `grep -rn`으로 `peer_addr`/`PeerAddrHandle`/`PeerConnection` 3가지 맥락 동시 존재 확인
   - 대응: 새 타입명 도입 시 코드베이스 grep 선행

---

## 다음 액션

1. ✅ 설계서 §10 addendum 추가 + `Connection` → `Endpoint` 일괄 치환 완료
2. ✅ 세션 파일 작성 완료
3. Phase 1 착수 — **Step 1: `Endpoint` 구조체 신설부터**
   - 파일: `crates/oxsfud/src/room/endpoint.rs` 신규
   - 초기에는 `Arc<Endpoint>`를 `Participant`가 참조하는 하이브리드 단계 (점진적 이행)
4. Step별 착수 설계는 별도 세션에서 확정 후 코딩

---

## SESSION_INDEX.md 업데이트 블록 (부장님 복사-붙여넣기용, 실제 형식 반영)

0418 테이블 마지막 행 뒤에 추가:

```
| 0418 | `20260418f_cross_room_phase1_code_review` | 설계+분석 | **★ Cross-Room Federation Phase 1 착수 전 코드 실측 리뷰**: `participant.rs`(42KB 필드 50+)/`room.rs`/`helpers.rs` 매핑. Endpoint 이동 35필드 vs RoomMember 3필드 분류. **★★ 설계서 §10 addendum 추가**(4항 확정): 10.1 `subscribe_layers` 키 `(publisher_id,room_id)` 확장 / 10.2 `send_stats`·`stalled_tracker` `(ssrc,room_id)` 확장 — SR Translation 방별 독립의 실체 / 10.3 STUN 인덱스 Room→EndpointMap 전역 이동 / 10.4 Track 소유권 Endpoint 단일(옵션 B RoomMember 분산 기각). **★ 네이밍 확정**: Connection→Peer(grep 3맥락 공존 기각)→**Endpoint** (RTCP Terminator 원칙 일치). 공수 재평가 1주+→**2~3주**. 오늘의 지침 후보: 설계서에 없는 순서 단정 금지 / 리팩터링 공수는 실측 후 / 네이밍은 grep 선행. 설계서: `design/20260416_cross_room_federation_design.md` (§10 추가 + Connection→Endpoint 치환) |
```

통계 블록 갱신:
```
- **총 세션 파일**: 188개
- **기간**: 2026-03-09 ~ 2026-04-18 (40일)
```

헤더 최종 업데이트 일자:
```
> 최종 업데이트: 2026-04-18
```

---

*author: kodeholic (powered by Claude), 2026-04-18*
