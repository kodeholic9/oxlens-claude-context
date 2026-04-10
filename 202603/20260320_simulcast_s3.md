# SESSION_CONTEXT — Simulcast 세션 3 완료

> date: 2026-03-20
> author: kodeholic (powered by Claude)

## 완료 내용: Phase 3 — 가상 SSRC + SimulcastRewriter + 레이어 전환

### 핵심 구현

**가상 Video SSRC 도입**: publisher별 고정 가상 video SSRC 할당. subscriber는 항상 이 SSRC만 보므로 Chrome SDP 매칭 보장.

```
Publisher[h] real_ssrc=0xAAA  ─┐
Publisher[l] real_ssrc=0xBBB  ─┤  서버: ensure_simulcast_video_ssrc() → virtual=0xCCC
                               │
TRACKS_UPDATE(add) ────────────┤→ subscriber에게 ssrc=0xCCC (rid 제거)
ingress fan-out ───────────────┤→ SimulcastRewriter.rewrite(real→virtual)
subscriber Chrome ─────────────┘  SDP에 0xCCC → 매칭 ✓
```

### 변경 파일 (서버 6개 + 클라이언트 3개)

| # | 파일 | 변경 |
|---|------|------|
| 1 | `participant.rs` | `SimulcastRewriter`, `SubscribeLayerEntry`, `simulcast_video_ssrc` (AtomicU32 CAS), `subscribe_layers`, `ensure_simulcast_video_ssrc()` |
| 2 | `room.rs` | `find_publisher_by_vssrc()` |
| 3 | `message.rs` | `SubscribeLayerRequest`, `SubscribeLayerTarget` |
| 4 | `handler.rs` | `handle_subscribe_layer(op=51)`, `simulcast_replace_video_ssrc()`, `simulcast_replace_video_ssrc_direct()`, TRACKS_UPDATE/ROOM_JOIN/ROOM_SYNC/ROOM_LEAVE/TRACKS_ACK/TRACKS_RESYNC 6곳 가상 SSRC 교체 |
| 5 | `ingress.rs` | simulcast fan-out (SubscribeLayer + SimulcastRewriter), PLI/NACK 역매핑 (find_publisher_by_vssrc), SR translation 가상 SSRC, TWCC extmap ID 동적 참조 |
| 6 | `egress.rs` | (변경 없음 — SendStats가 가상 SSRC 키로 자동 기록) |
| 7 | `constants.js` | `ROOM_SYNC: 50`, `SUBSCRIBE_LAYER: 51` |
| 8 | `signaling.js` | `subscribeLayer(targets)` + 응답 핸들러 |
| 9 | `app.js` | `redistributeTiles()`, `showLayerPopup()`, long-press 이벤트, `_manualLayerOverride` |

### SSRC 참조 경로 체크리스트 10항목 전체 완료

| # | 경로 | ✅ |
|---|------|---|
| 1 | PUBLISH_TRACKS → TRACKS_UPDATE(add) | ✅ |
| 2 | ROOM_JOIN → existing_tracks | ✅ |
| 3 | ROOM_SYNC → subscribe_tracks | ✅ |
| 4 | ROOM_LEAVE/cleanup → TRACKS_UPDATE(remove) | ✅ |
| 5 | SUBSCRIBE_LAYER (op=51) | ✅ |
| 6 | ingress fan-out (SimulcastRewriter) | ✅ |
| 7 | ingress PLI relay (가상→실제 역매핑) | ✅ |
| 8 | ingress NACK (가상→실제 SSRC/seq 역매핑) | ✅ |
| 9 | TRACKS_ACK expected set (가상 SSRC 기준) | ✅ |
| 10 | SR relay (가상 SSRC로 send_stats 조회) | ✅ |

### PLI 교착 2중 대책 구현

- **대책 #1** (ingress.rs): SubscribeLayer 즉석 생성 시 즉시 PLI burst [0,200,500,1500]ms
- **대책 #2** (handler.rs): SUBSCRIBE_LAYER에서 old==new && `!rewriter.initialized` → PLI burst

### 추가 수정: TWCC extmap ID 동적 참조

Phase 1에서 client-offer 전환 후 Chrome이 TWCC extmap ID=3 할당, 서버 하드코딩 ID=6과 불일치 → TWCC 추출 실패 → BWE 30kbps 추락.

**수정**: `ingress.rs`에서 `sender.twcc_extmap_id` 동적 참조 (0이면 서버 기본값 fallback)

### 테스트 결과

| 단계 | 항목 | 결과 |
|------|------|------|
| 2 | simulcast OFF 2인 양방향 | ✅ 12/12 Contract, loss 0% |
| 2 | PTT regression | ✅ granted/released/revoked 전체 cycle |
| 3 | simulcast ON 2인 양방향 | ✅ 12/12 Contract, SimulcastEncoderAdapter 확인, h 1.6Mbps |
| 4 | H → L 전환 | ✅ 해상도 감소 확인 |
| 4 | L → PAUSE | ✅ 영상 완전 멈춤 |
| 4 | PAUSE → H 복구 | ✅ <1초 복구 |

### 서버 버전

- v0.5.5 → Phase 3 적용 후 실질적으로 v0.6.0 수준

---

## 다음 작업 후보

1. **Phase 2**: IntersectionObserver 기반 visibility → 자동 레이어 선택 (Phase 3 위에 구현)
2. **Phase 4**: Active Speaker 자동 전환 (RFC 6464 audio level → ACTIVE_SPEAKERS op=144)
3. **프로세스 분리**: oxpmd / oxhubd / oxsfud / oxcccd (5월 예정)
4. **oxrecd**: 녹음 데몬 (파견센터 필수)
5. **demo.oxlens.com 배포**

### 주의사항

- `simulcast_enabled==false` 방은 기존 코드 100% 동작 (regression 없음 확인)
- PTT 방은 simulcast 강제 OFF (room.rs에서 처리)
- 초반 ~5초 영상 끊김은 설계대로 (SimulcastRewriter initialized=false → P-frame 드롭 → PLI burst → 키프레임 도착 후 정상화)
- 노트북 1대 테스트 한계: encoder_healthy=bandwidth limited는 CPU 병목 (별도 기기 테스트 필요)
