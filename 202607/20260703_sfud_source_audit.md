// author: kodeholic (powered by Claude)
# oxsfud 전수 소스 감사 — 리팩토링 상처·미구현·주석-코드 불일치 (20260703)

> 조사: 김과장 (조사반 4개 병렬 정독 + 최상위 11건 본인 직접 재검증). 수리 0 — 발굴·보고만.
> 범위: `crates/oxsfud/src` 75파일 24,514줄 전수 (oxrtc/oxhubd 는 범위 외, 단 rec 플래그는 워크스페이스 전체 grep).
> 판정 기준선: PROJECT_SERVER.md + 리팩토링 이력(room→domain, 2계층 전환, fan-out 방향역전, stats 이주 0602, set_id 폐기 0602e, SnRangeMap 폐기 0622, FLOOR_PING 폐기, track_dump 폐기 0620).
> 원 발굴 ~97건 → 아래는 심각도 순 정리. ★ = 본인 직접 소스 재검증 완료.

---

## §1 상 — 실동작/상용 위험 (5건, 전부 ★검증 확정)

### S1. RTX gate 미구현 — SnRangeMap 폐기의 안전 근거가 소비 지점에 없음
- `rtp_rewriter.rs:378` `is_in_rtx_gate_region()` — **crate 전체 호출처 0** (쓰기 5곳만).
- NACK 역매핑 `ingress_subscribe.rs:437,459` 가 gate 검사 없이 `reverse_seq` 직행.
- 주석 3곳(`rtp_rewriter.rs:22`/`ptt_rewriter.rs:28,30`)이 "전환경계 옛 NACK 은 RTX gate 가 차단"이라 주장 — **미구현 주장**.
- 위험: 화자/레이어 전환 직후 stale NACK 이 현 스칼라 offset 으로 역산 → 엉뚱한 원본 seq RTX 재전송 가능. `reverse_seq`의 "옛 시점" 분기도 no-op(`saturating_sub(0)`, rtp_rewriter.rs:322).

### S2. `FLOOR_MAX_BURST_MS = 86_400_000` (24h) — 자기 자백형 디버그 잔재
- `config.rs:210-211` "(디버깅: 발화 무한 유지 — 24h. **상용 복귀 시 30_000 으로 되돌릴 것**)".
- T2 revoke 안전망 사실상 비활성. `Cargo.toml default=["trace"]` 와 같은 "상용 전 제거" 부류 — **상용 전 체크리스트 등재 필요**.

### S3. rtcp_terminator.rs 모듈 헤더가 현행 SR 동작을 정반대 서술
- 헤더(`:2,6,9`) "서버 자체 RR/**SR 생성**" + "publisher SR 릴레이하지 않고 소비".
- 실코드: SR 자가생성은 test-only(`:318-320` "프로덕션 미사용" 자기 명시), publisher SR 은 `translate_sr` **번역 릴레이**(`ingress_rtcp.rs:146`) 가 현행 — 마스터 문서 "SR Translation" 절과도 헤더만 충돌.
- 동반 화석: `udp/mod.rs:219`·`egress.rs:257` "자체 RR/SR 생성 타이머"(RR만 생성), `egress.rs:344` TODO "publisher SR 기반 translation 설계 후 재활성화" — **요구 기능은 이미 구현 완료**(build_sr_translation, 0621), TODO 자체가 폐기 대상.

### S4. FLOOR destinations count≥2 — 계약은 Denied, 구현은 조용히 첫 방 채택
- 계약: `mbcp_native.rs:109` "Phase 1: len ≤ 1 허용, ≥ 2 는 Denied" + PROJECT_SERVER.md 동일.
- 실코드: `peer.rs:656-668 resolve_floor_target` — count 검사 없음, `destinations[0]` 채택. `FloorRouteDeny` 에 해당 변형 자체가 없음(floor_routing.rs:21-26).
- 현 클라는 항상 count==1 이라 잠복 — Phase 2(다방 발화) 착수 시 밟는 지뢰.

### S5. 에러코드 의미 충돌 — 같은 번호가 op 마다 다른 뜻
- `error.rs`: 2003=AlreadyInRoom · 2005=RoomNameRequired · 3003=MissingPid.
- 리터럴 사용: `scope_ops.rs:79,111,116,170` 2003="not identified"/"peer not found" · `track_ops.rs:383,392,903` 2005="track not found" · `track_ops.rs:387` 3003="simulcast duplex switch not supported".
- 실위험: take-over 분기(room_ops)가 2003==AlreadyInRoom 전제. **클라 sdk0.2 `_syncRoom` 은 2001/2003/2004 를 "서버 세션 소실→forget" 으로 처리** — scope 계열 2003(단순 미식별)과 의미 충돌 시 클라가 방을 잘못 잊을 수 있는 부류.

## §2 중 — 오도성 화석 주석 (핵심만; 유지보수자를 없는 곳으로 보냄)

| 위치 | 화석 내용 | 실체 |
|---|---|---|
| ★`tasks.rs:234` | TRACK_STALLED 가 `"{user}_{kind}"`(예: alice_video)를 track_id 로 송출 | 실 track_id 는 `{user}_{ssrc:x}`(track_ops.rs:154) — **wire 로 가짜 식별자**, 클라 매칭 항상 miss |
| ★`floor_ops.rs:127`+`datachannel/mod.rs:548` | FIELD_DURATION 파싱(`msg.duration_s`) 후 | 양 bearer 모두 `floor.request(..., None)` 하드코딩 — **수신-후-무시**, 안내 주석 없음 |
| ★`ingress_subscribe.rs:215-218` | "RR relay count" 분기 | relay_blocks 엔 PT=206 만 수집(rtcp.rs) — **도달 불능**, `rr_relayed` 메트릭 영구 0 |
| `scope_ops.rs:150-153` | "pub_room 은 auto-select, SCOPE 가 안 건드림" | 같은 함수가 pub_select/deselect 처리 — 자기 본문과 모순 (auto-select 는 0610 폐기) |
| `room.rs:139,171` | `rec` "oxtapd 가 감시, REST 로 변경 가능" | ★`set_rec` 워크스페이스 전체 호출처 0, oxtapd 데몬 자체 부재 — 영구 false 죽은 플래그 |
| `helpers.rs:200` | collect_subscribe_tracks "full-duplex 만 수집" | 본문은 half 전환 트랙 active:false push (full→half 캐싱 0531 후 미갱신) |
| `datachannel/mod.rs:475-478` | FloorRoute/Pan-Floor/svc=0x03 현재형 서술 | 셋 다 폐기 (같은 파일 10·36행이 폐기 명시) |
| `slot.rs:192` | release 진입점 = "`helpers::flush_ptt_silence` 단일" | 그 함수 부재. 실 진입점 floor_broadcast.rs 2곳 |
| `room.rs:348-354` | `PublisherTrack.virtual_ssrc` 매칭 서술 | 필드 폐기(0603) — 실코드는 `find_stream_by_vssrc` |
| `peer.rs:22`, `publisher_stream.rs:17`, `publisher_track.rs:614` | 진입점 안내가 폐기 API(`register_publisher_track`/`add_track_ext`) 지목 | 현행 `register_stream`/`register_track_to_stream`/`add_publisher_track` |
| floor.rs PING 군집(`:59,102,483`)+`config.rs:212-215` | 클라 FLOOR_PING 프로토콜 현재형 | RTP liveness 로 대체 — `PingOk/PingDenied` 반환값도 버려짐(tasks.rs:67) |
| `publisher_track.rs:347 vs 404` | "Audio 트랙은 None(메모리 절약)" | 생성자는 kind 무관 항상 `Some(RtpCache)` — audio cache 신설(Phase C.2) 후 doc 미갱신 |
| `publisher_track.rs:374,839` | fan-out doc 이 Step1 "채워두기만"·"vssrc 매칭 lookup" 서술 | 방향역전 후 subscribers Vec 직접 순회가 유일 경로 |
| `handler/mod.rs:18,113`, `admin.rs:241,495`, `mbcp_native.rs:5` | telemetry.rs/track_dump/set_id/core-datachannel.js 잔재 참조 | 전부 폐기·삭제됨 |
| `rtcp_terminator.rs:22,283`, `pli.rs:3-8,35`, `udp/mod.rs:10,16-22,130,269`, `subscriber_stream_index.rs:6-8,23`, `ingress_publish.rs:12` | 존재하지 않는 함수/필드/모듈 지도(on_rtp_received, fanout_simulcast_video, GlobalMetrics, admin_tx 등) | 이름 grep 추적 단절 유발 |
| `room_id.rs:12 vs 30` | "no serde" 설계 판단 vs 실제 serde derive | 파일 내 자기모순 |
| `subscriber_stream.rs:6,409 vs 420` | forward "via_slot/forwarder 분기" vs 본문 track_type() 분기 | 구/신 서술 공존 |
| `floor_ops.rs vs datachannel/mod.rs` | WS RELEASE=envelope room, DC RELEASE=pub_room | 두 bearer 대상 방 결정 비대칭 (실해 검토 필요) |

## §3 중 — 사(死)코드 군집 (참조 0 실측)

- ★**`pub_set_id` TLV 일습** (`mbcp_native.rs` 0x19 상수+필드+파서+빌더+시험 6종) — 파싱 후 read 0, mutex_violation Deny 도 부재. set_id 폐기(0602e)의 wire 화석. *PROJECT_SERVER.md 가 이미 "별 토픽 검토" 표기.*
- ★**PLI 잔재 필드**: `PublisherStream.simulcast_pli_pending`·`last_pli_relay_ms`(+접근자 2) — Governor 재설계(0621)가 대체, 참조 0.
- **Phase 계획 박제**: room.rs:29-105 enum 4종+`lookup_publisher_for_ssrc`(~75줄, Phase D.3 미착수 4.5개월) · `switch_source`(rtp_rewriter, prepare_source_switch 와 바이트 동일) · secondLast rollback 자료(핫패스에서 매 패킷 쓰고 아무도 안 읽음) · `HallSlotRewriter`(2회 언급, 실체 0) · `MidPool::with_reserved_start`(폐기 모델).
- **죽은 API/헬퍼**: ice.rs `handle_stun_packet`(STUN 로직 2벌 중 unreachable 쪽) · `detach_subscriber` · `cancel_queue`(release 분기와 중복+부수효과 비대칭) · `current_state` · `participant_count`/`member_ids`/`has_simulcast_tracks` · PublisherTrackIndex 3건 · PttRewriter 2건 · `RtpCache::slot_seq` · `first_of_kind`.
  - ~~`SubscriberStreamSnapshot`(소비자 0)~~ — **오판 정정(0703 집행 중 발견)**: admin.rs sub_streams 빌더가 `s.snapshot()` 실소비. 산 코드.
- **죽은 상수/구조체**: message.rs 구조체 6종(FloorPingMsg 등 WS-floor 화석) · config.rs 상수군(HEARTBEAT_*/ACK_*/SCTP_PORT/OPUS_PAYLOAD_TYPE/PTT_*_MID/FLOOR_MAX_PRIORITY) · dcep.rs PPID 5종 · stun.rs 상수+priority() · `PauseReason` 5변형 중 상용 1(`TrackDiscovery`) · `Layer::min` · twcc.rs 동일 결과 중복 분기 · pli.rs "RESYNC:PLI" 생산자 0.
- **written-never-read**: `speaker_tracker.last_update` · SimulcastRewriter mirror 절반(pending_keyframe/pli_sent_at/virtual_ssrc) · `egress_ssrc: AtomicU32`(주석 스스로 잔재 자백).

## §4 문서(마스터) 수정 대상

- ★PROJECT_SERVER.md:77 — rtp_rewriter 구성요소로 **SnRangeMap** 서술(0622 폐기·재도입 금지 구조를 현재형으로).
- PROJECT_SERVER.md "10방 사전 생성"(startup.rs) — 0603l 폐기, 코드 주석 3곳은 정합(문서만 낡음).
- 기준선 "PTT 모드 SR 릴레이 중단" — 코드가 앞섬: 현행은 slot rewriter offset 번역 릴레이(0621), 문서 갱신 필요.

## §5 기지·해소 확인 (좋은 소식 포함)

- **묵시 VP8 함정(0613 이월) — 해소 확인**: `from_str_or_default` 레포 소멸, `from_str_strict` 전량 거절(track_ops.rs:85-96)로 대체.
- 10방 사전생성 폐기 정합 / USER_PROBE opcode 재사용(0x2701/0x1702) 명명·카탈로그 정합 / track_id 파싱 금지 준수(rsplit_once 0건) / telemetry_bus 적재물 주석 정합 / admin.rs "stream_map" JSON 키는 의도적 wire 호환 잔존(스카 아님).
- `Cargo.toml default=["trace"]` 잔존 — 기지(상용 전 제거, S2 와 동일 체크리스트).

## §6 하 등급 요약

주석-함수 결합 밀림(floor.rs:551), 모듈 지도 낡음(tasks.rs:2 "2개"→실제 4개, handler/mod.rs 목록), opcode 카탈로그 수 "41"↔실 44, 단계번호 결번(helpers.rs 1→2→4), 전신 프로젝트명 잔재(error.rs "light-livechat"/`LightError`), 파라미터명 `vssrc`↔메서드명 egress_ssrc, 헤더 2줄 중복 등 — 원 보고 참조(하 ~30건).

## §7 총평·다음 수순 제안 (결재용)

**총평**: 구조 골격(2계층·방향역전·terminator·gate)은 코드가 건강. 병은 ① 대형 리팩토링 5~6회의 **주석이 코드를 못 따라온 것**(화석 ~40건, 특히 모듈 헤더/진입점 안내가 위험), ② **Phase ②/D.3 계획 박제**(사코드 ~30건), ③ **안전장치 2건의 공백**(S1 RTX gate 미구현, S2 T2 24h) — 마지막 부류만 실동작 위험.

수순 제안(지침화는 부장님 결정):
1. **즉결 수리 후보**: S2(상수 복원) · S5(에러코드 표 정리) · tasks.rs 가짜 track_id — 전부 저면적.
2. **설계 판단 필요**: S1(RTX gate 구현 vs 주석 철회+stale NACK 위험 수용 실측) · S4(count≥2 Deny 구현 시점) · WS/DC RELEASE 대상 방 비대칭.
3. **일괄 청소**: 화석 주석·사코드 군집(§2·§3) — 기계적, 회귀 무풍.
4. **문서**: §4 3건 (context 레포 — 부장님 직접).
