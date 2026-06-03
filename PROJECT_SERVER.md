// author: kodeholic (powered by Claude)
# OxLens — 서버 구조/아키텍처 (oxlens-sfu-server + oxhubd)

> PROJECT_MASTER.md 에서 분리(2026-06-03). 서버 코드 종속 — 소스 구조·미디어 아키텍처·oxhubd·Peer 재설계·scope 자료구조.
> 현행화 기준: 0602e(Phase B 진행). 코드 비종속 원칙·계약은 [PROJECT_MASTER.md](PROJECT_MASTER.md).

---


## 서버 소스 구조 (oxlens-sfu-server, Cargo workspace)

```
oxlens-sfu-server/
├── Cargo.toml              ← workspace root (resolver = "3")
├── system.toml             ← static config (포트, 경로, TLS, JWT, gRPC)
├── policy.toml             ← dynamic config (타이머, 대역폭, 방 정책, 로그)
├── proto/
│   └── oxlens_sfu_v1.proto ← gRPC v2: SfuService 단일, WsMessage {oneof json/binary} passthrough
└── crates/
    ├── common/             ← 공유 인프라 모듈
    │   └── src/
    │       ├── config/     — system.rs (SystemConfig), policy.rs (PolicyConfig + ArcSwap)
    │       ├── signaling/  — mod.rs, opcode.rs (4단계 priority, error_code, role)
    │       ├── auth/       — JWT create_token / verify_token (jsonwebtoken)
    │       ├── ws/         — OutboundQueue (4단계 우선순위 + 슬라이딩윈도우 + 대칭 ACK)
    │       ├── telemetry/  — agg.rs, bus.rs, primitives.rs, registry.rs (Counter/Gauge/TimingStat + metrics_group! 매크로)
    │       └── proto       — tonic::include_proto! codegen (build.rs)
    │
    ├── oxsig/              ← 프로토콜/타입 공유 (lib.rs, opcode.rs)
    │
    ├── oxrtc/              ← WebRTC transport 라이브러리 (ICE/DTLS/SRTP/NACK/PLI/RR/WS)
    │
    ├── oxsfud/             ← SFU 미디어 엔진 (상태 마스터)
    │   └── src/
    │       ├── main.rs / lib.rs / config.rs / error.rs / state.rs
    │       ├── startup.rs      — 환경 초기화, 시나리오 10방 사전 생성
    │       ├── tasks.rs        — floor timer, zombie reaper, active speaker, PLI governor, stalled checker (user 단위)
    │       ├── agg_logger.rs   — agg-log 발행 (track:publish_intent, session:suspect/zombie/recovered, scope:changed 등)
    │       ├── event_bus.rs    — WsBroadcast(per_user_payloads + binary_payload) + broadcast 채널 (hub 전달용)
    │       ├── telemetry_bus.rs— telemetry 수집/전달 버스
    │       ├── signaling/
    │       │   ├── opcode.rs   — common re-export
    │       │   ├── message.rs  — 패킷 타입 (common::Packet re-export) + ScopeUpdate/Set/EventPayload
    │       │   └── handler/    — gRPC dispatch (8파일)
    │       │       ├── mod.rs      — DispatchContext, dispatch, dispatch_binary
    │       │       ├── room_ops.rs — JOIN, LEAVE, SYNC (per-user TRACKS_UPDATE), SESSION_DISCONNECT
    │       │       ├── track_ops.rs— PUBLISH, TRACKS_READY, MUTE, CAMERA, SUBSCRIBE_LAYER, TRACK_STATE_REQ (duplex 전환 단일 경로, 2026-05-31)
    │       │       ├── floor_ops.rs— handle_floor_binary (DC bearer=WS 경로, WS JSON floor 삭제됨)
    │       │       ├── scope_ops.rs — SCOPE 단일 op 핸들러 (body 안 `mode=update/set` 분기) + sub primitive (묶음 1 Phase A, Cross-Room rev.2)
    │       │       ├── helpers.rs  — emit_to_hub, emit_per_user_tracks_update, collect_subscribe_tracks(mid 할당), flush_ptt_silence
    │       │       ├── admin.rs    — build_rooms_snapshot + build_users_snapshot (축 분리: 방 뷰 + User 뷰)
    │       │       └── telemetry.rs— telemetry passthrough
    │       ├── grpc/
    │       │   ├── mod.rs          — tonic Server (SfuService 1개만 등록)
    │       │   └── sfu_service.rs  — Handle(JSON/binary passthrough → dispatch 재사용), Subscribe, SubscribeAdmin
    │       ├── domain/        ← 도메인 엔티티 (구 room/ + media/ 흡수 — room→domain rename 2026-06-02)
    │       │   ├── mod.rs / room.rs — Room 상태 (RoomHub: DashMap 3-index O(1))
    │       │   ├── room_id.rs      — RoomId 타입 (Borrow<str> — HashSet/HashMap &str 조회)
    │       │   ├── types.rs        — 도메인 어휘 enum 단일출처: StreamKind/TrackKind/VideoCodec/DuplexMode/TrackType (구 stream_map/participant/publisher_track 분산 → 통합, 2026-06-02)
    │       │   ├── state.rs        — 3-Layer State enum (PeerState / PublishState / SubscribeState)
    │       │   ├── participant.rs  — RoomMember (방 멤버십 메타만: room_id/role/joined_at/Arc<Peer>. 통계는 트랙/스트림 직속 이주)
    │       │   ├── peer.rs         — Peer / PublishContext (pub_room + extmap atomic 5종 + audio_mid ArcSwap + audio_duplex/twcc home) / SubscribeContext / DcState + `sub_rooms: ArcSwap<HashSet<RoomId>>`. publish_room() 단일 진입 헬퍼
    │       │   ├── peer_map.rs     — PeerMap + SubscriberIndex(by_room_subscriber DashMap) + zombie reaper
    │       │   ├── publisher_stream.rs — 논리 Stream(camera/screen 단위 = 클라 MediaStream 정합). track_id+vssrc 식별 소유(불투명) + pli_state/pli_burst home(2계층). PublisherTrack 컨테이너
    │       │   ├── publisher_track.rs  — 물리 Track(SSRC 1등시민 = 클라 MediaStreamTrack 정합). rr_stats + pub_pipeline_stats + rtp_cache + NackGenerator + `subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>`(fan-out 방향역전) + stream Weak 역참조
    │       │   ├── publisher_track_index.rs — by_ssrc / by_rtx_ssrc O(1) RCU
    │       │   ├── subscriber_stream.rs — SubscriberStream(m-line=mid=vssrc, forward 단일 진입). sr_stats / stalled / sub_pipeline_stats / room_id 직속
    │       │   ├── subscriber_stream_index.rs — by_vssrc / by_mid O(1) RCU
    │       │   ├── slot.rs         — PTT/Hall Slot (per-room virtual_ssrc + Slot.subscribers Weak Vec)
    │       │   ├── floor.rs        — FloorController (PTT 발화권, QueueUpdated 액션)
    │       │   ├── floor_broadcast.rs — Floor 액션 → DC/WS 브로드캐스트 (SubscriberIndex user 단위, speaker_rooms/via_room TLV)
    │       │   ├── floor_routing.rs — FloorRouteDeny 등 floor 라우팅 (peer.rs 에서 분리, pub use re-export)
    │       │   ├── ptt_rewriter.rs — PTT SSRC/seq/ts 오프셋 리라이팅 (RtpRewriter wrapper) + translate_rtp_ts
    │       │   ├── rtp_rewriter.rs — 공통 토대 RtpRewriter (uint64 seq/ts + SnRangeMap + PLI 자가치유)
    │       │   ├── speaker_tracker.rs — Active speaker 추적 (RFC 6464)
    │       │   ├── subscriber_gate.rs — SubscriberGate (lock-free atomic, PauseReason)
    │       │   └── pli_governor.rs — PLI Governor (Layer + Pli{Publisher,Subscriber}State)
    │       ├── hooks/         ← phase 천이 hook → agg-log (묶음 6, 2026-05-17)
    │       │   ├── stream.rs       — on_publisher_phase / on_subscriber_phase (track:publish_active / subscribe:active)
    │       │   ├── floor.rs / media.rs — 미래 횡단 관심사 빈 틀
    │       ├── transport/
    │       │   ├── mod.rs / ice.rs / stun.rs / dtls.rs / srtp.rs
    │       │   ├── demux.rs / demux_conn.rs (peer_addr: Arc<RwLock> — ICE migration 지원)
    │       │   └── udp/
    │       │       ├── mod.rs / ingress.rs — UDP 수신 hot path 진입 (211줄, 분기만)
    │       │       ├── ingress_publish.rs — publish SRTP 처리 (475줄, RTP/RTCP 분기, decide_rid_promotion / evaluate_publisher_floor 헬퍼)
    │       │       ├── ingress_rtcp.rs    — RTCP 처리 (236줄, RR/SR/NACK/PLI 디스패치)
    │       │       ├── ingress_subscribe.rs — subscribe SRTP 처리
    │       │       ├── egress.rs       — UDP 송신 (sr_stats 직접 갱신)
    │       │       └── rtcp.rs / rtcp_terminator.rs(RrStats/SrStats) / twcc.rs / pli.rs / rtp_extension.rs
    │       │       (NackGenerator 는 domain/publisher_track.rs 흡수 — 구 nack_generator.rs 폐기)
    │       ├── datachannel/
    │       │   ├── mod.rs          — SCTP event loop + DCEP + MBCP Floor dispatch + T132 재전송 + DC broadcast
    │       │   ├── dcep.rs         — RFC 8832 DataChannel Establishment Protocol 파서/빌더
    │       │   └── mbcp_native.rs  — 3GPP TS 24.380 native TLV 포맷 빌더/파서 + 단위 테스트
    │       └── metrics/
    │           ├── mod.rs          — 모듈 선언만 (GlobalMetrics 삭제됨)
    │           ├── sfu_metrics.rs  — metrics_group! 기반 SfuMetrics (static Registry, dc 카테고리 포함)
    │           ├── env.rs          — EnvironmentMeta
    │           └── tokio_snapshot.rs
    │
    └── oxhubd/             ← WS 게이트웨이 + REST + JWT + Extension
        └── src/
            ├── main.rs / lib.rs / state.rs (HubState, WsSession + SessionPhase, room_clients 2차 인덱스)
            ├── metrics.rs      — HubMetrics (metrics_group! 6카테고리)
            ├── convert.rs      — proto→JSON 변환 (비움 — passthrough 전환)
            ├── grpc/mod.rs     — SfuClient (SfuServiceClient 1개, ArcSwap lazy reconnect)
            ├── rest/           — auth.rs (JWT), rooms.rs, admin.rs, helpers.rs
            ├── ws/
            │   ├── mod.rs      — WS 게이트웨이 (select! 4-way + OutboundQueue + 대칭 ACK + Binary 수신)
            │   └── dispatch/mod.rs — user_id 주입 + JSON/binary 그대로 gRPC Handle (투명 프록시)
            ├── moderate/       — Moderated Floor Control (authorization 상태머신, grant/revoke)
            ├── events/mod.rs   — sfud→hub 이벤트 소비 + WS broadcast(per_user/binary 분기) + reconnect loop
            └── shadow/mod.rs   — 이벤트 기반 상태 누적 (복구용)
```

---

## 미디어 아키텍처

### 2PC (Two PeerConnection) 구조
- Publish PC: 클라이언트 → 서버 (RTP 송신), track-less 생성 지원 (DC를 위해)
- Subscribe PC: 서버 → 클라이언트 (RTP 수신)
- SDP-Free 시그널링: server_config 기반 로컬 SDP 조립

### RTP-First Stream Discovery (Phase D 완료 + catch 2 3-D~3-F, 0529)
  (물리 트랙 = `PublisherTrack`, 2계층 rename 후 명명. 논리 묶음 = `PublisherStream`(source 단위))
- PUBLISH_TRACKS 처리 = PublishContext atomic store (extmap 5 + audio_mid/audio_duplex) + PublisherTrack 등록(→ attach_track_to_stream 로 논리 Stream 합류)
- Non-sim: PUBLISH_TRACKS 시점 실 SSRC PublisherTrack 등록 (track_ops 전담)
- Simulcast: **PUBLISH_TRACKS 시점 placeholder PublisherTrack 사전등록** (sentinel ssrc `0xF000_0000|counter`, simulcast=true, rid=None, mid/source/pt 박힘). RTP 도착 시 `rid` 파싱 → 같은 source 의 placeholder remove + 실 ssrc PublisherTrack rid 별 분화 등록 (`[STREAM:PROMOTE]` 로그 1회). 논리 Stream 은 생존(track_id/vssrc 보존). mediasoup `NewRtpStream` rid 별 발급 / LiveKit TrackInfo 사전등록 정합
- resolve_stream_kind 판별: Opus PT=111 → rid → repaired-rid → PublisherTrack.actual_rtx_pt → MID. **extmap ID 는 PublishContext atomic load**(rid/repair_rid/mid/audio_level/twcc). **MID↔kind 매핑 = PublisherTrack.mid + PublishContext.audio_mid** (race 안전망). **핫패스 stream_map lock = 0건** (stream_map.rs 폐기, enum 은 types.rs)
- RTX 는 PublisherTrack.actual_rtx_pt 매칭 또는 `repaired-rtp-stream-id` extension

### DataChannel (SCTP over DTLS)
- **sctp-proto 0.9.0** (Sans-I/O, str0m 3년+ 검증). Pub PC 단독 (양방향), Subscribe PC에 DC 없음
- DCEP(RFC 8832) DATA_CHANNEL_OPEN/ACK. `unreliable` 채널(maxRetransmits=0) — MBCP Floor 전용. reliable 채널은 Phase 2
- 프레임 포맷: `[svc(1) + len(2) + payload]` — svc=0x01(MBCP). svc=0x03(Pan-Floor) 폐기 (묶음 1, 2026-05-18)
- readiness 버퍼링: `dc_unreliable_ready: AtomicBool` + `dc_pending_buf: Mutex<VecDeque>` (MAX=64), DCEP Open 시 drain
- DcMetrics 19 카운터 (sfu_metrics.rs dc 카테고리)
- 설계: `context/design/20260414_datachannel_design.md`

### MBCP Floor Control (DC-only, 3GPP TS 24.380)
- **TS 24.380 native TLV 포맷** (RTCP APP PT=204 폐기). 헤더 ACK_REQ(1b)+type(4b)+field_count(1B)=2B, 필드 TLV id(1)+len(1)+value
- **FIELD_DESTINATIONS(0x18, 24)** (4/22 추가): FLOOR_REQUEST 시 발화 대상 방 목록을 동반. `u8 count + [u8 len + utf8 room_id] × count`. 서버가 `destinations[0]` 로 방 선택(기존 `participant.room_id` 고정 참조 폐기). Phase 1 서버는 `count==1` 만 허용, `count≥2` 는 Denied (Phase 2에서 enable)
- **WS Floor path 완전 삭제** — bearer=ws fallback은 동일 바이너리를 WS binary frame으로 전달 (envelope `[env_len|env_json|payload]`)
- **viaRoom TLV 5개 빌더 의무화** (4/25i): `mbcp_native::build_{granted/idle/deny/revoke/queue_info}` 가 `via_room: Option<String>` 동봉. floor_broadcast.rs / datachannel/mod.rs / floor_ops.rs 호출처 17곳 주입. 클라 라우팅 fallback chain: `viaRoom → destinations[0] → speakerRooms[0] → _currentRoom`
- **T101/T104** (클라): 500ms × 3회, Floor Ack 수신 시 취소
- **T132** (서버): ACK_REQ=1 메시지(Granted/Revoke), 500ms × 3회
- **FLOOR_PING 제거** → RTP liveness: tasks.rs에서 speaker의 `last_video_rtp_ms`/`last_audio_arrival_us` 활용 (hot path 변경 0줄)
- DC 양방향 응답: Granted/Denied/Queued를 같은 SCTP stream에 즉시 write
- bearer 왕복: 클라→hub(WS binary)→sfud(gRPC binary)→floor→event_tx→hub(bin_event_tx)→클라
- 큐 위치 갱신 (TS 24.380 §6.3.4.4) 6곳, Granted duration (§8.2.2) FIELD_DURATION(9) u16 BE
- 설계: `context/design/20260415_mbcp_datachannel_v2_design.md`

### SubscriberGate (mediasoup pause/resume 패턴)
- 새 publisher video 발견 → subscriber에 gate pause
- subscriber SDP re-nego 완료(TRACKS_READY, 구 TRACKS_ACK) → gate resume + GATE:PLI
- video fan-out hot path에서 `gate.is_allowed()` O(1) 체크, 5초 타임아웃 안전장치

### Fan-out 방향 역전 (0528~0601)
- **물리 Track 이 다운스트림을 직접 보유**: `PublisherTrack.subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` (Full), Half(PTT)는 방 `Slot.subscribers`.
- **fan-out 단일 본문**: `fanout() → track_type() 분기 → broadcast(subs, prefan)` — Full=`self.subscribers` / Half=방 `Slot.subscribers` 를 **직접 순회**. 두 경로가 broadcast 한 본문에 합류.
- **vssrc 역탐색 폐기**: 구 `find_subscriber_stream_by_vssrc` 매칭 fan-out 폐기. **vssrc 는 라우팅 키가 아니라 값** — subscribe 등록(cold-path)에서 `SubscriberStream.vssrc` 로 복사돼 egress rewrite hot-path 가 그 복사본 사용.
- dead Weak 는 attach_subscriber 의 retain 으로 자연 청소 (명시 detach 없음).
- 설계서: `context/design/20260528_fanout_direction_redesign.md`.

### PLI Governor (인과관계 기반 PLI 평탄화)
- PLI를 "요청"이 아닌 "이벤트"로 취급. "PLI 보냈다 → I-Frame 왔는가 → subscriber에게 릴레이됐는가" 관측 사실로 판단
- 시간 임계치는 유실 대비 안전망 (주 판단은 상태). 레이어별 차등 (h 무겁고, l 가벼움)
- **인프라 PLI는 Governor bypass** (GATE:PLI, NACK_ESC, RTP_GAP)

### RTCP Terminator (v1 완료)
- SFU는 두 독립 RTP 세션의 종단점(peer) — relay가 아님
- Ingress(Publisher→SFU): 서버가 수신자 → RR 자체 생성
- Egress(SFU→Subscriber): 서버가 송신자 → SR 필요
- **subscriber RR은 publisher에게 릴레이 금지**, SR 자체 생성 금지(서버 NTP → jb_delay 폭등, Janus PR #2007)
- RTX는 RrStats/SrStats 에서 반드시 제외 (개명: 구 RecvStats→**RrStats**, SendStats→**SrStats**, 0602b)

### SR Translation
- Conference/Simulcast: SSRC/RTP ts 원본 유지, packet_count/octet_count만 egress SrStats 기준
- PTT: SSRC→virtual, RTP ts→오프셋 변환 (`PttRewriter.translate_rtp_ts`). **PTT 모드에서는 SR 릴레이 중단** (NTP↔RTP drift 방지)
- NTP timestamp은 항상 원본 유지 (lip sync 기준점, 변조 금지)

### Stats 트랙 차원 정렬 (0602b~c)
- **RTCP 생성 통계 = 트랙/스트림 직속**: `RrStats`(RR 생성) = `PublisherTrack` 직속 (구 PublishContext.recv_stats DashMap). `SrStats`(SR 번역 count) = `SubscriberStream` 직속 (구 room_stats[].send_stats).
- **텔레메트리 = 트랙/스트림 직속** (차원 비대칭 해소): `PublishPipelineStats`(rtp_in/gated/rewritten/video_pending/pli_received) = `PublisherTrack.pub_pipeline_stats` (구 PublishContext.pub_stats user-scope). `SubscribePipelineStats`(rtp_relayed/dropped/sr_relayed/nack_sent) = `SubscriberStream.sub_pipeline_stats` (구 RoomMember.sub_stats). `rtx_received` 는 producer 0 dead → 삭제(4필드).
- **room_stats DashMap 폐기**: `SubscriberStream.room_stats: DashMap<RoomId>` (항상 1엔트리 잉여) 제거 → `sr_stats`/`stalled`/`stats_primed` 직속 + **`room_id: RoomId` 정체 필드 승격** (STALLED 체커 floor/publisher 조회용).
- **admin 집계**: 트랙 합산(`Peer::pub_pipeline_snapshot`) / room_id 필터 합산(`sub_pipeline_snapshot_for_room`) — 출력 형태(user-scope pub / room-scope sub) 보존.

### PTT 미디어 파이프라인
- Floor Gating: `track.duplex == Half`인 트랙만 (room.mode 판단 아님)
- SSRC Rewriting: 오프셋 기반 audio/video 리라이팅 (ptt_rewriter.rs)
- Dynamic ts_gap: idle 경과 시간을 ts에 반영 (arrival_time vs RTP ts 일치 원칙)
- Video pending compensation: switch_speaker→first_pkt 경과 시간(카메라 구동 지연) 보상
- Silence flush: clear_speaker 시 Opus silence 3프레임 주입 (NetEQ 연속성)
- VP8 키프레임 대기: 화자 전환 후 P-frame 드롭, I-frame 도착 시 릴레이 시작
- PLI burst: Floor Granted 시 3연발 (Governor 경유, I-Frame 도착 시 자동 취소)
- NACK 역매핑: 가상SSRC → 원본seq 역산 + last_speaker fallback
- **PTT virtual track remove 보호**: 참가자 퇴장 시 같은 kind의 half-duplex 보유자 잔존하면 virtual track remove 생략 (leave + zombie 경로 모두)

### STALLED 감지
- `StalledSnapshot.packets_sent_at_ack` 스냅샷: TRACKS_READY 시점 `SubscriberStream.sr_stats.packets_sent` 기록 (구 room_stats[].send_stats — stalled/stats_primed 와 함께 stream 직속)
- 5초 주기 체크: delta==0이면 STALLED (정당사유 제외)
- 정당사유: PTT floor 없음, 트랙 muted, SubscriberGate paused, Simulcast pause, Publisher 퇴장, PTT kf_pending
- TRACK_STALLED(0x2105) → 클라이언트 ROOM_SYNC 1회 + 토스트. 30초 쿨다운
- ParticipantPhase < Active(2) 가드 (Created/Intended는 미디어 미전송이므로 skip)

### Duplex 전환 (TRACK_STATE_REQ 단일 경로 + full→half 캐싱, 2026-05-31)
- **전환 신호 = `TRACK_STATE_REQ`(0x1106) 단일 경로** — PUBLISH_TRACKS hot-swap 에서 분리 (이중화 금지, 결정 D). PUBLISH_TRACKS 는 최초 등록 전용
- **분류 권위 = publisher `TrackType`** — fanout/forward 분기를 `publisher.track_type()` match 단일로 (Phase 1). `duplex_store(target)` 갱신만으로 fanout 경로 자동 선택, 새 fan-out 로직 0줄
- **full→half (캐싱 보존)** — 개인 SubscriberStream/mid/mid_pool 제거 안 함 (구 republish 폐기). publisher.duplex=Half → fanout HalfNonSim arm 이 broadcast_full 을 안 타 자동 미송출. 개인 mid 보유 sub 에 `TRACK_STATE{active:false}`. slot 은 collect 가 늘 상존
- **half→full (복귀)** — floor.release + publisher.duplex=Full → fanout broadcast_full 이 **보존 Weak 자동 재송출** (Phase 1+2 토대, 재활성 코드 최소). per-sub: 보존 sub(mid 보유) → `TRACK_STATE{active:true}` + video PLI burst(디코더 재개), 신규 sub(mid 미보유) → SubscriberStream 생성 + `TRACKS_UPDATE{add}`
- **생명주기 기준** — `collect_subscribe_tracks` 가 half 전환 개인 트랙(subscriber mid_map 보유 = full 이력)을 `active:false` 로 current_ids 에 포함 → `release_stale_mids` 회수 제외 (ROOM_SYNC 캐싱 생존). mid_map 미보유(half 로 시작)는 slot 만
- **클라(웹/Android) TRACK_STATE_REQ 발신 · 통지 수신 · 개인grid↔PTT slot UI 패러다임 전환 = 별도 작업** (미착수). 신규 sub add 경로 실행 검증도 멀티봇/클라 단계

### 식별 계층 (track_id / vssrc / 실 ssrc, 0603 — 서버 A·B 완료)
설계서 `context/design/20260531_track_state_unification.md`(rev.3). 식별 3평면 분리 — 평면을 가르고 캡슐화.

| 평면 | 식별자 | 소유 | 쓰임 |
|---|---|---|---|
| 시그널링(지목) | **track_id**(불투명) | 논리 `PublisherStream` | MUTE_UPDATE·TRACK_STATE_REQ(발신)·TRACK_STATE·TRACKS_UPDATE(통지). **키 조회, 파싱 금지** |
| egress SSRC(값) | **vssrc** | 논리 `PublisherStream` | subscriber 단일 SSRC 의 publisher측 원천. subscribe 등록(cold-path)에서 `SubscriberStream.vssrc` 로 복사 — **라우팅 키 아님** |
| ingress(식별) | 실 `ssrc` | 물리 `PublisherTrack` | publisher RTP 수신 매칭·NACK/RTX (`PublisherTrackIndex.by_ssrc`) |

- **track_id 생성 = `{user}_{대표 ssrc}`** — non-sim/PTT=원본ssrc, simulcast=vssrc. **`attach_track_to_stream` 의 `PublisherStream::new` 1회 발급**(eager vssrc). 물리 Track 교체(분화)돼도 논리 Stream 생존 → track_id/vssrc 보존.
- **조회 = 키**: `Peer::find_stream_by_track_id(&str)` / `find_stream_by_vssrc(u32)`(vssrc=0 가드). 역추출 금지.
- **mute = Stream 단위**: `mute_stream(track_id?, ssrc, muted)` 가 Stream 의 모든 물리 Track set_muted (simulcast h/l 비대칭 해소). **simulcast duplex 전환 reject**(§11). `switch_track_duplex` dead 청산.
- **학습 = PUBLISH_TRACKS `ok` 응답 `d.tracks=[{mid, track_id}]`** + TRACK_STATE/TRACKS_UPDATE 통지 track_id 동봉(active:false/true 포함). self-unicast 폐기.
- **기각**: track_id 역추출(`rsplit_once` — 캡슐화 위반) / vssrc 를 라우팅 키로(방향역전 — Track.subscribers 직접 순회) / track_id·vssrc 를 물리 Track 유지(클라 1 Pipe ↔ 서버 다수 계층 불일치 #5b).
- 서버 A(식별 이주, `8b0627a`) + B(발신/통지/응답, `208a498`) 완료. 클라(transceiver.mid 학습·setTrackState 게이트·TRACK_STATE 수신) = 별 세션.

### 트랙 속성 체계 (RoomMode 제거 완료)
```
track = duplex(full/half) + simulcast(on/off) + priority(0~N)
```
- **방은 빈 그릇** — room.mode / room.simulcast_enabled 완전 제거
- `has_half_duplex_tracks()` / `has_simulcast_tracks()` 헬퍼로 대체
- full+half 트랙 공존 가능 (같은 방에 conference + PTT 참가자 혼합)
- 파생 규칙: half-duplex → simulcast 강제 off (PttRewriter + SimulcastRewriter 충돌 방지)
- 클라이언트가 PUBLISH_TRACKS에 duplex/simulcast 명시 전송
- TRACKS_UPDATE(add)에 duplex/simulcast/mid 필드 포함 (per-user 전달)

### Subscribe MID 서버 주도 할당
- 서버가 mid 할당 (per-subscriber `MidPool`, kind별 분리: recycled_audio/recycled_video) — 클라 자체 할당 시 m-line 무한 누적 → video freeze
- WsBroadcast에 `per_user_payloads` — TRACKS_UPDATE add/remove 전부 per-user 전달
- 클라이언트 passthrough: `assignMids`는 서버 mid 그대로 사용, mid 기반 inactive pipe 재활용
- 설계: `context/design/20260412_subscribe_mid_design.md`

### ParticipantPhase 5단계 (좀비 2단계 확장)
```
Created(0) ──(PUBLISH_TRACKS)──> Intended(1) ──(첫 RTP)──> Active(2)
                                                              │
                                    ┌──(packet received)─────┘
                                    v
                       Active ──(15초 무응답)──> Suspect(3) ──(+5초)──> Zombie(4, 삭제)
```
- CAS로 원자적 상태 전환, lock-free (`phase: AtomicU8`)
- 어드민 스냅샷: `"phase": "created"|"intended"|"active"|"suspect"|"zombie"`
- REAPER_INTERVAL: 5초, SUSPECT_TIMEOUT: 15초, ZOMBIE_TIMEOUT: 20초 (4/25e 단축 — take-over 분기 도입으로 reconnect race 별도 처리)
- agg-log 3종: `session:suspect`, `session:zombie`, `session:recovered`
- **Take-over (LiveKit/mediasoup 표준, 4/25e)** — ROOM_JOIN AlreadyInRoom(2003) 시 `helpers.rs::evict_user_from_room()` (handle_room_leave cleanup 7단계 재현: cancel_pli_burst → floor cleanup → rooms.remove_participant → SubscriberIndex detach → peer.leave_room → simulcast purge_subscribe_layers + speaker_tracker.remove → emit_per_user_tracks_update + participant_left broadcast) → 새 peer 재생성 (새 ICE creds) → join_room 재시도. 5초 안에 phase=ready 회복. 단순 zombie 단축으로는 reconnect race 못 막음
- 설계: `context/design/20260417_server_lifecycle_phase.md`, `20260417_server_participant_phase.md`

### ICE Address Migration
- ICE restart 불필요 — STUN consent check 자동 갱신(Pion/mediasoup/Janus 공통)
- SRTP 경로: 기존 `latch_by_ufrag`→`latch_address`→`get_address` 자동 갱신
- **DTLS/SCTP 갭 수정**: DemuxConn `peer_addr: Arc<RwLock>` + DtlsSessionMap `migrate()`

---

## oxhubd — WS 게이트웨이 + Extension

### 아키텍처
- **hub WS dispatch = 투명 프록시** — JSON/binary 모두 user_id 주입만
- **Extension 모듈은 hub에서 정책 수행** — moderate(자격 관리), 향후 cross-room 등
- **sfud가 상태 마스터** — Room/Participant/Floor + 미디어 엔진 전체
- gRPC v2 passthrough: SfuService 단일, WsMessage {oneof json/binary}, proto 36줄
- 포트: hub:1974, sfud gRPC:50051

### SessionPhase 4단계
```
Connected(0) → Identified(1) ⇄ Joined(2) → Disconnected(3)
                    ▲            │
                    └─ROOM_LEAVE─┘  (방 퇴장 시 Identified 복귀, WS 유지)
```
- **WS disconnect → SESSION_DISCONNECT(0xE001) 통보만** — sfud에 LeaveRoom 안 보냄 (종속 해소)
- 설계: `context/design/20260417_server_lifecycle_phase.md`

### WS 흐름제어
- OutboundQueue: 4단계 우선순위(P0 floor/gate ~ P3 telemetry) + 슬라이딩윈도우(8)
- 대칭 ACK: 모든 메시지에 `ok` 필드 기반 (양방향 동일)
- 채널 분리: event_tx(bounded) + reply_tx(unbounded) + **bin_event_tx(bounded, binary)**
- **binary 메시지는 OutboundQueue 우회** (T132 이중화 방지)
- pid는 per-connection seq

### Track Dump (Hub Extension, 2026-05-20)
- 방 단위 4-Point 진단 풀 덤프 인프라 — `admin HTTP → hub → TRACK_DUMP_REQ(0x2701) broadcast → 클라 풀 덤프 수집 → TRACK_DUMP_REPLY(0x1702) → hub fan-in 5s timeout → join → HTTP response`
- row 단위 4-Point JSON (cli_pub / srv_pub / srv_sub / cli_sub) + verdict 자동 산출
- dump_id 는 hub AtomicU32 자체 발급 (wire pid 와 분리 — broadcast OutboundQueue 재발급으로 매칭 부적합)
- hot-path 카운팅 추가 금지 — packets/bytes/jitter/loss 는 클라 [1]/[4] `getStats()` 양단 비교만 (canonical source: outbound-rtp / inbound-rtp)

### Moderated Floor Control (Hub Extension)
- PTT와 별개 도메인 — 진행자 기반 발언 자격 관리
- hub moderate/ 3파일: authorization 상태머신, grant(kinds)/revoke
- `role: u8` 참가자 역할 (sfud 저장/릴레이, 의미 해석은 hub/app)
- `isPtt` 플래그 (`__ptt__` virtual userId 패턴 제거)
- grant → SDK 자동 audio/video publish (기존 PTT 파이프라인 재사용, sfud 변경 제로)
- 설계: `context/design/20260409_moderated_floor_design.md`, `20260410_moderated_floor_design_v2.md`

### 이벤트 인프라
- sfud→hub: `emit_to_hub()` 단일화 (per_user_payloads + binary_payload 분기)
- hub: event consumer reconnect loop (backoff 2→15초)
- gRPC keepalive 15s/5s, ArcSwap lazy reconnect

### HubMetrics
- metrics_group! 매크로 6카테고리 (ws/flow/grpc/auth/msg/stream)
- 어드민 대시보드 Hub Gateway 섹션

### Config 체계
- system.toml: static (포트, 경로, TLS, JWT secret, gRPC 주소)
- policy.toml: dynamic (타이머, 대역폭, 로그레벨, 방 정책) + ArcSwap 런타임 교체
- `.env` / dotenvy 완전 삭제

---

## Peer 재설계 원칙 (장기 출처)

- **Scope는 타입으로 표현** — user-scope=`Peer`, PC pair-scope=`PublishContext`/`SubscribeContext`, room-scope=`RoomMember`. 필드 위치가 의미를 말하게 하고, 주석/네이밍에 의존하지 않는다
- **user × sfud = PC pair 1쌍** — 방 수와 무관. PC pair에 귀속되는 모든 자원(SRTP/SDP/RTP cache/stats/DC)은 `Peer` 소유. `RoomMember`는 방 멤버십 메타데이터만 보유
- **publish 자료 home = `PublishContext`** — `pub_room` (선택된 발언 방, 묶음 3 단수화) + **PC pair 협상 메타** (`rid/repair_rid/mid/audio_level/twcc` extmap ID `AtomicU8` + `audio_mid: ArcSwap<Option<Arc<str>>>` + `audio_duplex: AtomicU8`, catch 2 3-B/3-C 0529) 가 `PublishContext` 소유. SDP 협상 결과는 PC pair 단위. **publisher 통계는 물리 Track 직속 이주(0602b~c)**: `pub_stats`(텔레메트리)→`PublisherTrack.pub_pipeline_stats`, `recv_stats`(RR)→`PublisherTrack.rr_stats`. 트랙 메타도 `PublisherTrack`(물리, SSRC) 흡수. PLI 자료(`pli_state`/`simulcast_pli_pending` 등) + **식별(track_id/vssrc)** 은 논리 `PublisherStream`(source 단위) home — 2계층 전환(2026-05-30, 명제 B 해결) + 식별 계층 재설계(0603). `Peer::publish_room()` 단일 진입 헬퍼만 노출. publisher 측 = `peer.publish_room()` / subscriber 측 = `peer.sub_rooms` 임의 1방 의미 분리 (`first_room_hint` 헬퍼 폐기, 0521c)
- **PC 종류 축(publish/subscribe) ≠ packet 방향 축(ingress/egress)** — 상위 컨테이너는 `Publish/SubscribeContext` (PC 단위), 하위 hot path 레이어는 `transport/udp/ingress.rs`/`egress.rs` (packet 방향). 섞으면 레이어 충돌
- **편의 프록시 신설 금지** — 경로가 길어지는 것은 구조 신호. 단, 기존 공개 API는 외부 인터페이스 보존 원칙으로 유지하고 내부만 위임

---

## Scope 모델 (Cross-Room rev.2, 2026-04-23 + 묶음 1 Phase A, 2026-05-18)

### 데이터 구조 — N방 청취 + 1방 발언

```rust
Peer {
    rooms:     Mutex<HashSet<RoomId>>,               // 입장한 방들 (joined)
    sub_rooms: ArcSwap<HashSet<RoomId>>,             // "받을 방들" = MCPTT Affiliated (N방 청취). RoomSet/RoomSetId 래퍼 폐기(0602e) → bare HashSet
    publish: PublishContext {
        pub_room: ArcSwap<Option<RoomId>>,           // "보낼 방" = MCPTT Selected (1방 발언, 묶음 3 단수화)
        // srtp, sdp, extmap atomic 등 PC pair publisher 자원 home
        // (pub_stats → PublisherTrack.pub_pipeline_stats / recv_stats → PublisherTrack.rr_stats 이주, 0602b~c)
    },
    // ...
}
// RoomSet/RoomSetId 폐기(0602e) — sub_rooms 는 bare HashSet<RoomId>. SCOPE op·다방 청취 유지.
```

- **외부 접근은 `peer.publish_room() -> Option<RoomId>` 단일 진입 헬퍼만** — `publish.pub_room` 직접 접근 금지 (Peer 재설계 원칙 — publish 자료 home 일원화)
- **set_id(RoomSetId) 폐기 (0602e)** — `sub_set_id`/`pub_set_id` wire 필드(SCOPE_EVENT)·admin 키 제거. 구 `"sub-{user_id}"` 식별자 모델 접음. SCOPE op(sub_add/remove)·다방 청취 기능은 유지.
- **묶음 1 Phase A (2026-05-18)**: Cross-Room publish 폐기 → SCOPE handler 는 *sub_rooms 전용*. pub_room 은 `join(R)` 시 auto-select 1방, `leave(R)` 시 auto-deselect 자동 — SCOPE 가 건드리지 않음
- **방/트랙은 scope 모름** — 기존 경로로 동작. Scope 는 라우팅 대상 판정 / 전달 대상 수집 / 관측 축 통일에만 등장
- **SubscriberIndex** (`PeerMap.by_room_subscriber: DashMap<RoomId, DashMap<user_id, Arc<Peer>>>`) — fan-out 핫패스에서 방 순회 없애고 user 단위 O(1) 조회

### Primitive

| 레이어 | 추가 | 제거 | 진입점 |
|---|---|---|---|
| joined_rooms | `join(R)` | `leave(R)` | ROOM_JOIN(0x1003) / ROOM_LEAVE(0x1004) |
| sub_rooms | `affiliate(R)` | `deaffiliate(R)` | SCOPE(0x1200) `mode=update` body 안 `sub_add` / `sub_remove` |
| pub_room | (`join(R)` 시 auto-select) | (`leave(R)` 시 auto-deselect) | SCOPE 가 건드리지 않음 |

**SCOPE handler batch 순서**: `sub_add → sub_remove`. (Phase A 이전 `pub_add` / `pub_remove` 자리는 폐기 — wire 호환 위해 클라가 보내도 서버 무시)

**Cascade**:
- `leave(R)` → pub_room 자동 `None` (이 방이었으면) → 해당 방 floor release → 방 퇴장
- `deaffiliate(R)` (sub_remove) — sub_rooms 에서만 제거. pub_room 영향 없음
- JOIN 기본 옵션 A (implicit): `join(R) → sub += {R}, pub_room = R (없으면)` — 단일 방 기존 동작 100% 호환

### SDK 공개 API (`engine.scope.*`)

→ **[PROJECT_WEB.md](PROJECT_WEB.md)** 로 이동 (2026-06-03, 발견_사항 3). 서버 SCOPE_EVENT wire payload = `{sub, pub, cause, change_id}` (set_id 폐기 0602e). 서버 자료구조는 위 "데이터 구조"·아래 "불변 원칙" 참조.

### Floor 관련

- **FLOOR_TAKEN 전달 = user 단위** (SubscriberIndex 기반). 발화자 pub_room 을 TLV `FIELD_SPEAKER_ROOMS(0x16)` 로, 수신자 경유 방을 `FIELD_VIA_ROOM(0x17)` 로 전달 (단수지만 wire 호환을 위해 array 표현 잔존).
- **Floor 판정은 방별 독립** — 집계 레이어 없음. MCPTT per-group floor independence + LMR Patch Voice Grant 정합.
- **FLOOR_REQUEST 방 지정**: TLV `FIELD_DESTINATIONS(0x18)` `count==1` 만 (Pan-Floor 폐기로 N방 동시 발화 불가). 묶음 1 이전 `FIELD_PUB_SET_ID(0x19)` TLV + struct field 잔존 흔적 있음 — **dead code 가능성, 별 토픽 검토**.

### STALLED / Admin (user 단위로 전환)

- **STALLED checker**: `peers_snapshot()` 1중 루프. tracker key `(ssrc, room_id)` 에서 room_id 로 `rooms.get()` 호출.
- **Admin**: `build_rooms_snapshot` 응답에 `users` 배열 병행 추가. 축 분리 — 방 뷰는 방 정보만, User 뷰는 user 정보만.

### Scope 모델 불변 원칙

- **방/트랙은 scope 모른다** — Room.members / FloorFsm / 트랙 속성은 기존 경로로 동작. Scope 는 Peer / SubscriberIndex / FLOOR 전달 / admin User 뷰에만 존재
- **Server-authoritative** — SDK 낙관적 업데이트 금지. partial success 경로에서 어긋남
- **(폐기) set_id 모델** — RoomSetId(`sub-{user_id}`) 폐기(0602e). hub shadow(oxhubd ShadowState)는 ROOM_EVENT join/left 만 누적·SCOPE/set_id 미참조 → 폐기 영향 클라 한정(서버 hub 무영향, 검증 완료)
- **`pub_room ⊆ sub_rooms` 자명** — Phase A 이후 1방 발언이라 pub_room 은 항상 sub_rooms 의 한 원소 (join auto-select 가 sub_rooms 에도 R 추가). CCTV/드론 송출 전용 시나리오는 향후 별 토픽
- **SDK = `engine.scope.*` 네임스페이스 그룹** — flat 접미사 API(`engine.affiliateScope` 등) 기각. Engine 비대 + `select` 단어 자동완성 혼동 방지

---
