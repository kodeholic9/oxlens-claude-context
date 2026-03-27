# 세션 3 지시사항 — Phase 3: 가상 SSRC + SimulcastRewriter + 레이어 전환

## 컨텍스트 로딩 (반드시 먼저 읽을 것)

다음 파일들을 순서대로 읽어:
1. `/Users/tgkang/repository/oxlens-sfu-server/doc/SIMULCAST_REBUILD_GUIDE_20260320.md` — 전체 설계 + 실수 목록 + 체크리스트
2. `/Users/tgkang/repository/oxlens-sfu-server/claude/SESSION_CONTEXT_20260320_simulcast_s2.md` — 세션 2 완료 상태
3. `/Users/tgkang/repository/oxlens-sfu-server/src/room/participant.rs`
4. `/Users/tgkang/repository/oxlens-sfu-server/src/room/room.rs`
5. `/Users/tgkang/repository/oxlens-sfu-server/src/signaling/handler.rs`
6. `/Users/tgkang/repository/oxlens-sfu-server/src/signaling/message.rs`
7. `/Users/tgkang/repository/oxlens-sfu-server/src/signaling/opcode.rs`
8. `/Users/tgkang/repository/oxlens-sfu-server/src/transport/udp/ingress.rs`
9. `/Users/tgkang/repository/oxlens-sfu-server/src/transport/udp/egress.rs`

클라이언트 (이미 Phase 1 완료, 참고용):
10. `/Users/tgkang/repository/oxlens-home/core/client.js`
11. `/Users/tgkang/repository/oxlens-home/core/signaling.js`
12. `/Users/tgkang/repository/oxlens-home/demo/client/app.js`

---

## 현재 상태

- **Phase 0** ✅ — 서버 구조 준비 (simulcast_enabled, Track.rid, add_track_ext 등)
- **Phase 1** ✅ — 서버: rid 필터링, twcc_extmap_id 저장, simulcast extmap 추가
- **Phase 1** ✅ — 클라이언트: client-offer 전환, getStats SSRC 폴링, PUBLISH_TRACKS에 rid+twcc_extmap_id
- **Phase 3** ⬜ — **이번 세션에서 할 것**

서버 v0.5.5, 모든 테스트 통과 상태.

---

## Phase 3 작업 범위

### 핵심: 가상 Video SSRC 도입

Subscriber는 video m-line 1개만 가짐. SDP에 선언된 단일 SSRC로 패킷이 와야 함.
서버가 h↔l 전환 시 다른 real SSRC 패킷을 보내면 Chrome이 무시.
→ publisher별 고정 가상 video SSRC 할당 → 모든 레이어 패킷을 이 SSRC로 rewrite.

### SSRC 참조 경로 체크리스트 (10항목 — 한번에 전부 수정)

| # | 경로 | 설명 |
|---|------|------|
| 1 | PUBLISH_TRACKS → TRACKS_UPDATE | h video SSRC → 가상 SSRC 교체, rid 제거 |
| 2 | ROOM_JOIN → existing_tracks | 이미 있는 publisher의 h video → 가상 SSRC |
| 3 | ROOM_SYNC → subscribe_tracks | 동기화 응답의 h video → 가상 SSRC |
| 4 | ROOM_LEAVE / cleanup → TRACKS_UPDATE(remove) | 퇴장 broadcast의 h video → 가상 SSRC |
| 5 | SUBSCRIBE_LAYER | SubscribeLayer의 output_ssrc = 가상 SSRC |
| 6 | ingress.rs fan-out | SimulcastRewriter로 가상 SSRC rewrite |
| 7 | ingress.rs PLI relay | subscriber PLI(가상 SSRC) → real SSRC 역매핑 |
| 8 | ingress.rs NACK | subscriber NACK(가상 SSRC, 가상 seq) → real SSRC/seq 역매핑 |
| 9 | TRACKS_ACK expected set | 가상 SSRC 기준 비교 확인 |
| 10 | SR relay | send_stats에서 가상 SSRC 기준 조회 확인 |

### 서버측 구현

**participant.rs:**
- `simulcast_video_ssrc: AtomicU32` (0=미할당)
- `ensure_simulcast_video_ssrc()` — CAS lazy 할당
- `SimulcastRewriter` 구조체: virtual_ssrc, last_out_seq/ts, pending_keyframe, seq_offset/ts_offset, initialized(pub)
- `SubscribeLayer` 구조체: subscriber별 {publisher_pid → (current_rid, SimulcastRewriter)}

**room.rs:**
- `find_publisher_by_vssrc(vssrc: u32) -> Option<Arc<Participant>>` — PLI/NACK 역매핑용

**handler.rs:**
- SUBSCRIBE_LAYER (op=51) 핸들러
- TRACKS_UPDATE/ROOM_JOIN/ROOM_SYNC/ROOM_LEAVE에서 가상 SSRC 교체 로직
- PLI 교착 방지: SUBSCRIBE_LAYER에서 old==new여도 rewriter.initialized==false면 PLI 발사

**ingress.rs:**
- simulcast fan-out: SubscribeLayer 확인 → SimulcastRewriter.rewrite() 적용
- SubscribeLayer 즉석 생성 시 즉시 PLI burst [0,200,500,1500]ms
- PLI 역매핑: 가상 SSRC → find_publisher_by_vssrc → real SSRC
- NACK 역매핑: 가상 SSRC/seq → real SSRC/seq

### 클라이언트측 구현

**signaling.js:**
- `subscribeLayer(targets)` → `OP.SUBSCRIBE_LAYER` (op=51) 전송

**app.js:**
- `redistributeTiles()`: simulcast ON이면 main 타일 → h, thumbs → l
- `_setupThumbObserver()`: IntersectionObserver — visibility 변경 시 l/pause
- long-press popup: 수동 h/l/pause 선택 (디버그용)
- `_manualLayerOverride` Set: 수동 설정 보호 (redistributeTiles가 덮어쓰기 방지)

---

## 절대 지켜야 할 룰

1. **코딩 전에 반드시 설계 + 변경 범위 + 체크리스트를 먼저 보여줘**
2. **한 Phase의 모든 변경을 한 턴에 완료해. "다음 턴에서" 금지**
3. **문제 발생 시 로그를 먼저 요청해. 추측 코딩 절대 금지**
4. **컴파일 에러 가능성 (Arc move, pub 접근성 등) 코딩 시점에 미리 처리해**
5. **simulcast_enabled==false이면 기존 코드 100% 그대로 동작해야 함**

### PLI 교착 문제 (반드시 대책 구현)

```
1. 첫 RTP → subscribe_state 비어있음 → SubscribeLayer 즉석 생성 (initialized=false)
2. 첫 패킷이 P-frame → rewriter 드롭 → Chrome 0바이트
3. Chrome: "패킷 없으니 PLI 안 보냄" (경로 A 실패)
4. SUBSCRIBE_LAYER(h) → old==new(h==h) → PLI skip (경로 B 실패)
5. 영구 stuck
```

**대책 2중:**
- ingress: SubscribeLayer 즉석 생성 시 즉시 PLI burst [0,200,500,1500]ms
- handler: SUBSCRIBE_LAYER old==new여도 rewriter.initialized==false면 PLI 발사

### Rust 컴파일 주의

- `room.simulcast_enabled` 클로저 캡처: `let sim_enabled = room.simulcast_enabled;`로 Copy 타입 사전 캡처
- `Arc<Room>`을 move 클로저에 넣지 않음
- `SimulcastRewriter.initialized` 필드 반드시 `pub`
- ingress.rs에서 `SubscribeLayer` import 확인

---

## 테스트 순서

1. simulcast OFF 2인 양방향 — 기존 regression 없는지 (12/12 Contract PASS)
2. PTT regression — simulcast OFF 방에서 정상
3. simulcast ON 2인 양방향 — high 레이어 전달, 양쪽 영상 정상
4. simulcast ON 3인 — 노트북 1대 한계 인지 (enc_time 40ms+ 정상)
5. 레이어 전환 — long-press h→l→pause→h, 각 전환 시 영상 복구

**문제 발생 시 코드 안 고치고:**
- 서버 로그: `[SIM:PLI]`, `[DBG:SIM]`, `SUBSCRIBE_LAYER`
- 클라이언트 콘솔: `[MEDIA]`, `[DBG:TRACK]`
- 텔레메트리 스냅샷
- 원인 확정 후에만 코딩

---

*Phase 3가 simulcast의 핵심이자 가장 위험한 단계. 체크리스트 10항목 빠짐없이, PLI 교착 2중 대책 필수.*
