# 묶음 8 — 운영성 마무리 (axis4 + 백로그 청산) 완료 보고

- 작업자: 김과장 (Claude Code)
- 일자: 2026-05-17
- 지침: `context/claudecode/202605/20260520a_operability_wrapup.md`
- 빌드: `cargo build --release -p oxsfud` PASS
- 테스트: `cargo test --release -p oxsfud` **194 passed / 0 failed** (묶음 6 유지)

---

## §0 의무 점검

- 194 PASS 확인 후 진입
- 사전 grep:
  - `ingress_mbcp` mod 등록 0 / 파일 존재 (Phase A 삭제 대상)
  - `_peer_map`/`_socket:` underscored 인자: **0** (묶음 5 원복 후 자리 0 — F25 작업 자체 부적용)
  - `PROJECT_MASTER.md` 자리: `/Users/tgkang/repository/PROJECT_MASTER.md` (git 외 자료)

## Phase 진행

| Phase | commit | 내용 | 결과 |
|-------|--------|------|------|
| A | `f98f426` | F26 — `ingress_mbcp.rs` 파일 삭제 + transport/udp/mod.rs:20 모듈 구조 주석 정리 | 완료 |
| B | — (스킵) | F25 — 면적 점검 결과 *작업 자체 부적용* (underscored 인자 0) | 스킵 |
| C | `2162f9a` | 주요 모듈 5개 `//!` 시작 주석 표준화 (책임/핵심 자료구조/호출처 3섹션) | 완료 |
| D | (context repo) | `context/design/wire_v3_catalog.md` 신설 (275줄) | 완료 |
| E | (PROJECT_MASTER) | E-1 명세 7자리 모두 적용 | 완료 |
| F | (본 commit) | 최종 검증 + 보고서 | 완료 |

## Phase B 면적 점검 결과 (부장님 보고)

**F25 작업 자체 부적용** — `process_association_events` chain (`handle_stream_event`, `handle_dc_binary`, `handle_mbcp_from_datachannel`) 의 `peer_map` / `socket` 인자가 *모두 사용 중*. 묶음 5 원복 후 *underscored 자리 0*. 시그너처 정리 작업 없음.

지침 §6 명시: "면적 점검 의무 — ~3 파일 + 100줄 초과 시 별 토픽 분리". 본 자리는 *부적용 → 별 토픽도 불필요*. Phase B 스킵 정합.

## Phase 세부

### Phase A — F26 ingress_mbcp.rs dead 파일 청소
- `crates/oxsfud/src/transport/udp/ingress_mbcp.rs` 파일 삭제 (mod 미등록 dead 파일, 본문 `apply_floor_actions` 5-인자 구 시그너처 — mod 등록 시 컴파일 실패)
- `transport/udp/mod.rs:20` 모듈 구조 doc 줄 1자리 제거
- `ingress_mbcp` 잔존 grep: **0** ✓

### Phase C — 주요 모듈 5개 //! 표준화
- `room/peer.rs`: 책임 (PC pair 소유 / Stream 컨테이너 / 1방 발언+N방 청취) / 핵심 자료구조 (PublishContext / SubscribeContext / pub_room / sub_rooms / PeerState) / 호출처 (PeerMap::get_or_create / set_phase_state / register_publisher_stream 등)
- `room/publisher_stream.rs`: 책임 (publisher RTP 1등 시민 / fan-out / hot-swap) / 핵심 자료구조 (ssrc / duplex / virtual_ssrc / phase / peer_ref Weak) / 호출처 (create_or_update_at_rtp / ingress::handle_srtp / set_phase_state)
- `room/subscriber_stream.rs`: 책임 (forward 진입점 / SubscriberGate / pli_state mode 무관) / 핵심 자료구조 (mid / virtual_ssrc / publisher_ref / room_stats / gate / pli_state / mode) / 호출처 (add_subscriber_stream / forward / track_ops::do_tracks_ack)
- `room/floor.rs`: 책임 (PTT 상태 머신 / 큐잉 / Vec<FloorAction> 반환) / 핵심 자료구조 (FloorState / FloorAction / FloorConfig / FloorInner) / 호출처 (request / release / check_timers / on_participant_leave + apply_floor_actions)
- `signaling/handler/mod.rs`: 책임 (gRPC dispatch / opcode 분기 / Packet 응답) / 핵심 자료구조 (DispatchContext / 모듈 분리 7개) / 호출처 (sfu_service::handle / event_tx broadcast)
- `transport/udp/mod.rs`: 기존 모듈 구조 doc 양호 — Phase A 정리만

### Phase D — context/design/wire_v3_catalog.md 신설
- 275줄 (지침 200~400줄 범위 정합)
- 18 섹션: 공통 wire frame / opcode 카테고리 nibble / Handshake/Session/Request(Room/Media/Scope/Data)/Event(Room/Media/Scope/Data/Floor MBCP/Speakers/Extension)/Admin/Internal/Error / State 천이 추적 (axis4 §3.2)
- 데이터 출처: `crates/oxsig/src/opcode.rs` + `signaling/message.rs` + `signaling/handler/` + MBCP `mbcp_native.rs`

### Phase E — PROJECT_MASTER.md 갱신 (E-1 명세 그대로)
- §시그널링 프로토콜 op=53 SCOPE_UPDATE: *"pub_add/pub_remove 폐기 (묶음 1)"* 명시
- §Scope 모델 데이터 구조: `pub_rooms: ArcSwap<RoomSet>` → `pub_room: ArcSwap<Option<RoomId>>` (1방 발언 묶음 3 단수화) 정합 + `RoomSet` 주석 *"sub_rooms 전용 (묶음 1 의미 축소)"*
- §마일스톤: 묶음 1~6 5건 추가 (지침 명시: 묶음 1/2/3/4/6)
- §아키텍처 원칙: 신규 2건 (*hook 분류 = 횡단 관심사 fire-and-forget 만* / *표현 정확도 — 폐기/이주/마이그/통합 동사 검증*)
- §기각된 접근법: 신규 3건 (MBCP 주 흐름 hook 이주 분류 오류 / 빈 placeholder YAGNI 위반 / on_peer_phase agg-log trade-off)
- §분업 체계 적용 사례: 묶음 1~7 사례 추가 (분류 오류 → 원복 → 정정 사이클 검증 자리)
- 총 +11줄 net (864 → 875)

자의적 추가 0 — 모두 김대리 명세 자리.

## §F 잔존 grep

```
ingress_mbcp                                : 0 ✓
PROJECT_MASTER E-1 명세 미적용 자리            : 0 (모두 적용 완료)
wire_v3_catalog.md 존재                      : 275줄 ✓
```

## 주요 변경 파일 5개 선별

```
context/design/wire_v3_catalog.md            | 275 +++++++ (신규)
PROJECT_MASTER.md                            |  11 ++ (E-1 명세 적용, git 외)
crates/oxsfud/src/transport/udp/ingress_mbcp.rs | 107 --- (삭제, Phase A)
crates/oxsfud/src/room/peer.rs               |  + (Phase C 표준화)
crates/oxsfud/src/room/publisher_stream.rs   |  + (Phase C 표준화)
```

## 산출물

- 2 commits (oxlens-sfu-server: Phase A + Phase C)
- 신규 문서 1건 (`wire_v3_catalog.md`, 275줄)
- 갱신 문서 1건 (`PROJECT_MASTER.md`, +11줄)
- 194 tests PASS 유지
- 완료 보고서 (본 문서)

## 발견 사항 (별 토픽 후보)

1. **agg-log 테스트 멀티 스레드 race** — `cargo test --release` 의 *기본 멀티 스레드* 실행 자리에서 `publisher_active_phase_emits_agg_log` / `subscriber_active_phase_emits_agg_log` 가 *공유 AGG Registry* 사용. test parallel 자리에서 *간헐 1건 실패* (재실행 시 PASS). 단위 테스트 격리 방안: `serial_test` crate 또는 `agg_flush` race 회피. **본 묶음 범위 외 — 측정 후 별 토픽 분리 권고**.

## 호환성 / 위험

- 클라 wire 영향 0
- 코드 동작 변경 0 — dead 파일 삭제 + 주석 + 문서 위주
- F25 작업 부적용 — 묶음 5 원복 결과 자료가 자연 정리됨
- 분업 체계 정합 — E-1 명세 그대로 적용, 자의적 추가 0
