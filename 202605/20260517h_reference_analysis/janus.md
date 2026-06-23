# Janus Gateway — videoroom plugin 심층 분석

> 작성: 2026-05-17 (김과장)
> 대상: `~/repository/reference/janus-gateway/`
> 핵심 파일: `src/plugins/janus_videoroom.c` (**14,266줄 단일 파일**)
> 목적: 내일부터 소스 참조 못한다 가정 — 상세 자료구조 + 흐름 + OxLens 매핑

---

## 0. 한 줄 요약

C 기반 *plugin 아키텍처* WebRTC 게이트웨이. **Janus core** 가 ICE/DTLS/SCTP/RTP-relay 인프라, **plugin** 이 SDP + RTP forwarding 정책. videoroom plugin 이 SFU 역할. **14,266줄 단일 파일**에 자료구조/핸들러/RTCP/forwarding/recording/remote publisher 모두 거주.

---

## 1. 전체 구조

### 1.1 Janus 프로젝트 디렉토리

```
janus-gateway/
├── src/
│   ├── janus.c                # 메인 엔트리 (수천 줄)
│   ├── ice.c, dtls.c          # ICE/DTLS 코어 (libnice + OpenSSL)
│   ├── sdp.c                  # SDP negotiator
│   ├── rtp.c, rtcp.c          # RTP/RTCP 헬퍼
│   ├── sctp.c                 # DataChannel
│   ├── rtpfwd.c               # RTP forwarder (외부 UDP 송출)
│   ├── record.c               # MJR 녹화
│   ├── auth.c                 # API 토큰 인증
│   ├── events/, loggers/      # 이벤트 핸들러 / 로거 plugin
│   └── plugins/               # 각 plugin (videoroom, audiobridge, sip, ...)
│       └── janus_videoroom.c  ← SFU 핵심 (14266 줄)
├── conf/                      # Janus + plugin 설정 (텍스트 INI)
└── html/                      # 데모 클라
```

### 1.2 plugin 인터페이스 (Janus core ↔ plugin)

```c
static janus_plugin janus_videoroom_plugin = JANUS_PLUGIN_INIT (
    .init = janus_videoroom_init,
    .destroy = janus_videoroom_destroy,
    .create_session = janus_videoroom_create_session,
    .handle_message = janus_videoroom_handle_message,
    .setup_media = janus_videoroom_setup_media,
    .incoming_rtp = janus_videoroom_incoming_rtp,       // RTP 진입점
    .incoming_rtcp = janus_videoroom_incoming_rtcp,     // RTCP 진입점
    .incoming_data = janus_videoroom_incoming_data,     // DataChannel
    .slow_link = janus_videoroom_slow_link,             // BWE feedback
    .hangup_media = janus_videoroom_hangup_media,
    .destroy_session = janus_videoroom_destroy_session,
);
```

plugin 은 *RTP 패킷 수신/송신*을 *Janus core 위임* (`gateway->relay_rtp(handle, &rtp)`). plugin 자체는 *어디로 보낼지 결정* 만.

---

## 2. 핵심 자료구조 (line 2271~2660)

### 2.1 `janus_videoroom` (방, line 2327)

```c
typedef struct janus_videoroom {
    guint64 room_id;             // 방 ID
    gchar *room_id_str;
    gchar *room_name;
    GHashTable *participants;    // user_id → publisher
    janus_mutex mutex;
    int max_publishers;
    uint32_t bitrate;            // 기본 bitrate
    int fir_freq;                // FIR/PLI 주기 (초)
    janus_audiocodec acodec[5];  // 허용 오디오 코덱 (최대 5종)
    janus_videocodec vcodec[5];  // 허용 비디오 코덱
    gboolean require_pvtid;
    gboolean record;             // 녹화 활성
    gchar *rec_dir;
    GList *threads;              // helper thread 목록
    int helper_threads;
    volatile gint destroyed;
    janus_refcount ref;
    ...
} janus_videoroom;
```

**OxLens 매핑**: `crate::room::Room` (`crates/oxsfud/src/room/room.rs`). 단 OxLens 의 Room 은 *PTT slot 보유* (audio_slot/video_slot per-room virtual_ssrc 의 자리) + FloorController. Janus 는 *audiobridge plugin 별 분리*.

### 2.2 `janus_videoroom_publisher` (line 2419) — user-scope

```c
typedef struct janus_videoroom_publisher {
    janus_videoroom_session *session;
    janus_videoroom *room;
    guint64 user_id;
    guint32 pvt_id;              // 비공개 ID (subscriber 매칭용)
    gchar *display;              // 표시 이름
    gboolean dummy;              // dummy publisher (placeholder)
    janus_audiocodec acodec;
    janus_videocodec vcodec;
    gboolean talking;            // 발화 중 (audio level 기반)
    gboolean firefox;            // FF 는 FIR 다르게
    GList *streams;              // 이 publisher 의 stream 들 (audio/video/data)
    GHashTable *streams_byid;    // mindex → stream
    GHashTable *streams_bymid;   // mid → stream
    int data_mindex;
    janus_mutex streams_mutex;
    uint32_t bitrate;
    gint64 remb_startup;         // REMB ramp-up
    gint64 remb_latest;
    gboolean recording_active;
    janus_recorder *rc;          // 녹화기
    GSList *subscriptions;       // 이 publisher 가 구독 중인 publisher 목록
    janus_mutex subscribers_mutex;
    janus_mutex own_subscriptions_mutex;
    GHashTable *remote_recipients; // 외부 SFU 로 forward 시
    gboolean remote;             // 외부 publisher 인지
    uint32_t remote_ssrc_offset;
    int remote_fd, remote_rtcp_fd, pipefd[2];
    struct sockaddr_storage rtcp_addr;
    GThread *remote_thread;      // 외부 publisher 처리 스레드
    GHashTable *rtp_forwarders;  // 외부 RTP forward 목록
    janus_mutex rtp_forwarders_mutex;
    int udp_sock;
    gboolean kicked;
    gboolean e2ee;               // E2EE flag
    janus_mutex mutex;
    json_t *metadata;
    volatile gint destroyed;
    janus_refcount ref;
} janus_videoroom_publisher;
```

**OxLens 매핑**: `crate::room::peer::Peer` + `crate::room::participant::RoomMember` 결합 자리. Janus 는 *publisher = 방 단위* (한 user 가 N 방 publish 시 *각자 다른 publisher*). OxLens 는 *Peer 단일 + RoomMember 방별*.

**핵심 차이**:
- Janus: `publisher.subscriptions` (이 user 가 *구독* 중인 다른 publisher 목록) — *subscribe 도 publisher 가 추적*. OxLens 에서 *Peer.subscribe.streams* 와 다른 관점.
- Janus: `GHashTable *rtp_forwarders` — 외부 UDP 로 RTP 송출 (recording/cascade). **OxLens 없음**.
- Janus: `remote_publisher` — 외부 SFU 의 RTP 수신 (cascade). **OxLens 폐기 정합 (축 1)**.
- Janus: `talking` (audio level 기반 발화 감지). OxLens 도 `speaker_tracker` 존재.

### 2.3 `janus_videoroom_publisher_stream` (line 2470) — stream-scope, **OxLens 가 차용**

```c
typedef struct janus_videoroom_publisher_stream {
    janus_videoroom_publisher *publisher;
    janus_videoroom_media type;          // audio/video/data
    int mindex;                          // SDP m-line index
    char *mid;                           // SDP mid
    char *description;
    gboolean disabled;
    gboolean active;
    gboolean muted;
    janus_audiocodec acodec;
    janus_videocodec vcodec;
    int pt;                              // PT
    char *fmtp;                          // negotiated fmtp
    char *h264_profile, *vp9_profile;
    gint64 fir_latest;                   // 최근 PLI 시각 (throttle)
    gint fir_seq;                        // FIR seq number
    gboolean opusfec, opusdtx, opusstereo;
    gboolean simulcast, svc;
    uint32_t vssrc[3];                   // simulcast SSRC 3 layer
    char *rid[3];                        // rid 3 layer
    int rid_extmap_id;
    janus_mutex rid_mutex;
    // RTP extensions
    guint8 audio_level_extmap_id;
    guint8 video_orient_extmap_id;
    guint8 playout_delay_extmap_id;
    janus_sdp_mdirection audio_level_mdir, video_orient_mdir, playout_delay_mdir;
    int16_t min_delay, max_delay;        // playout delay 범위
    // Audio level (RFC 6464 extension)
    int audio_dBov_level;
    int audio_active_packets;
    int audio_dBov_sum;
    gboolean talking;
    // Recording
    janus_recorder *rc;
    janus_rtp_switching_context rec_ctx;
    janus_rtp_simulcasting_context rec_simctx;
    // RTP forwarders (외부)
    GHashTable *rtp_forwarders;
    janus_mutex rtp_forwarders_mutex;
    // Remote publisher 전용
    volatile gint need_pli;              // 지연 PLI 플래그
    volatile gint sending_pli;           // PLI 발사 중 가드
    gint64 pli_latest;                   // 최근 PLI 시각
    gboolean is_srtp;
    int srtp_suite;
    char *srtp_crypto;
    srtp_t srtp_ctx;
    srtp_policy_t srtp_policy;
    // 이 stream 을 구독 중인 subscriber stream 목록
    GSList *subscribers;
    janus_mutex subscribers_mutex;
    volatile gint destroyed;
    janus_refcount ref;
} janus_videoroom_publisher_stream;
```

**OxLens 매핑**: `crate::room::publisher_stream::PublisherStream` (`crates/oxsfud/src/room/publisher_stream.rs`).
- **직접 차용**: subscriber_stream.rs:2 *"Janus videoroom 의 publisher_stream + LiveKit DownTrack 차용"* 명시.
- 동일: `publisher` 역참조 (OxLens 는 `peer_ref: Weak<Peer>`), `vssrc[3]`, `rid[3]`, simulcast/svc, recording, RTP forwarders.
- **OxLens 차이**:
  - `subscribers: GSList` (Janus 는 stream 별 subscriber list 보유) ↔ OxLens 는 *방 순회* (publisher_stream.fanout 이 `transport.endpoint_map.subscribers_snapshot(fan_room.id)` 으로 *방 단위 lookup*)
  - `pli_pending/sending_pli/pli_latest/need_pli` (단순 3 atomic) ↔ OxLens 는 *PLI Governor* (관측 사실 기반, layer 별 PliLayerState)
  - `is_srtp`/`srtp_ctx`/`srtp_policy` 가 *stream 별* (Janus 는 *remote publisher 전용*) ↔ OxLens 는 *Peer.publish.media* 단일 SRTP context
  - `audio_dBov_level/audio_active_packets/audio_dBov_sum` 같은 audio level 분석 ↔ OxLens 는 *speaker_tracker* 별도

### 2.4 `janus_videoroom_subscriber` (line 2557) + `_stream` (line 2578) — **OxLens 가 차용**

```c
typedef struct janus_videoroom_subscriber {
    janus_videoroom_session *session;
    janus_videoroom *room;
    GList *streams;                      // sub stream 목록
    GHashTable *streams_byid;
    GHashTable *streams_bymid;
    janus_mutex streams_mutex;
    gboolean use_msid;
    gboolean autoupdate;                 // publisher 사라지면 자동 renego
    guint32 pvt_id;                      // 매칭 ID
    gboolean paused;                     // 전체 일시정지
    gboolean kicked;
    gboolean e2ee;
    volatile gint answered, pending_offer, pending_restart, skipped_autoupdate;
    volatile gint destroyed;
    janus_refcount ref;
} janus_videoroom_subscriber;

typedef struct janus_videoroom_subscriber_stream {
    janus_videoroom_subscriber *subscriber;
    GSList *publisher_streams;           // ← 한 sub stream 이 N publisher_stream 가리킴
    int mindex;
    char *mid;
    char *msid, *mstid;
    char *crossrefid;
    gboolean send;
    janus_videoroom_media type;
    janus_audiocodec acodec;
    janus_videocodec vcodec;
    char *h264_profile, *vp9_profile;
    int pt;
    gboolean opusfec;
    janus_rtp_switching_context context;    // RTP munging (timestamp/seq)
    janus_rtp_simulcasting_context sim_context;  // 현재 simulcast layer 상태
    janus_vp8_simulcast_context vp8_context;
    janus_rtp_svc_context svc_context;       // SVC layer 상태
    int16_t min_delay, max_delay;
    volatile gint ready, destroyed;
    janus_refcount ref;
} janus_videoroom_subscriber_stream;
```

**OxLens 매핑**: `crate::room::subscriber_stream::SubscriberStream` (subscriber_stream.rs:2 *"Janus subscriber_stream 정합"*).
- 동일: `mindex`/`mid`/`type`, RTP context (munging), simulcast context, SVC context, paused flag.
- **OxLens 차이**:
  - `publisher_streams: GSList` (한 sub stream 이 *N publisher* 가리킴, 주로 data 채널) ↔ OxLens 는 `publisher_ref: ArcSwap<PublisherRef>` 단일 (`Direct(Weak<PublisherStream>)` 또는 `ViaSlot(Weak<Slot>)`)
  - `paused: gboolean` (subscriber 전체) ↔ OxLens 는 `SubscriberGate` per-publisher (mediasoup 패턴)
  - `sim_context`/`vp8_context`/`svc_context` ↔ OxLens 는 `SubscribeMode::VideoSim { layer: Mutex<SubscribeLayerEntry { rid, target_rid, rewriter: SimulcastRewriter, pli_state: PliSubscriberState } }` (단일 mode enum 안)

### 2.5 `janus_videoroom_rtp_relay_packet` (line 2613)

```c
typedef struct janus_videoroom_rtp_relay_packet {
    janus_videoroom_publisher_stream *source;  // 어떤 publisher stream 에서 왔는지
    janus_rtp_header *data;
    gint length;
    gboolean is_rtp;
    gboolean is_video;
    uint32_t ssrc[3];                          // simulcast 3 SSRC
    uint32_t timestamp;
    uint16_t seq_number;
    janus_plugin_rtp_extensions extensions;
    gboolean simulcast;
    gboolean svc;
    janus_vp9_svc_info svc_info;
    gboolean textdata;
} janus_videoroom_rtp_relay_packet;
```

→ *publisher → subscribers fan-out 시 packet 메타 캡슐화*. OxLens 는 `EgressPacket::Rtp { room_id, data }` 단순 (전송 큐 entry).

### 2.6 그 외 자료구조

- `janus_videoroom_session` (line 2374) — Janus core 가 관리하는 session 의 *plugin 측 캐스트*. user 가 publisher/subscriber 어느 쪽인지 (`participant_type`).
- `janus_videoroom_helper` (line 2393) — helper thread 풀 (fan-out 부담 분산)
- `janus_videoroom_remote_recipient` (line 2642) — RTP forwarder 의 *outbound 송출 대상*

---

## 3. 핵심 흐름

### 3.1 RTP 진입 → fan-out (line 8715~8930)

```c
void janus_videoroom_incoming_rtp(janus_plugin_session *handle, janus_plugin_rtp *pkt) {
    // 1. session/participant 검증
    janus_videoroom_session *session = ...;
    janus_videoroom_publisher *participant = janus_videoroom_session_get_publisher(session);
    janus_videoroom_incoming_rtp_internal(session, participant, pkt);
}

// internal:
static void janus_videoroom_incoming_rtp_internal(...) {
    char *buf = pkt->buffer;
    uint16_t len = pkt->length;
    int sc = -1;  // simulcast index
    // ... mindex/mid 로 ps (publisher_stream) 찾음
    janus_videoroom_publisher_stream *ps = ...;
    
    // 2. simulcast 면 SSRC 등록 (vssrc[0/1/2])
    if(ps->simulcast) {
        uint32_t ssrc = ntohl(rtp->ssrc);
        if(ps->vssrc[0] == 0 || ps->vssrc[0] == ssrc) {
            ps->vssrc[0] = ssrc; sc = 0;
        } else if(ps->vssrc[1] == 0 || ps->vssrc[1] == ssrc) {
            ps->vssrc[1] = ssrc; sc = 1;
        } else if(...) { sc = 2; }
    }
    
    // 3. recording (있으면)
    if(ps->rc) {
        janus_rtp_header_update(rtp, &ps->rec_ctx, TRUE, 0);
        rtp->ssrc = ps->vssrc[0];  // 녹화는 고정 SSRC
        janus_recorder_save_frame(ps->rc, buf, len);
        rtp->ssrc = htonl(ssrc);  // 복원
    }
    
    // 4. fan-out packet 구성
    janus_videoroom_rtp_relay_packet packet = { 0 };
    packet.source = ps;
    packet.data = rtp;
    packet.length = len;
    packet.ssrc[0] = ps->vssrc[0];  // 3 layer SSRC 캐싱
    packet.ssrc[1] = ps->vssrc[1];
    packet.ssrc[2] = ps->vssrc[2];
    packet.simulcast = ps->simulcast;
    packet.svc = ...;  // SVC info 파싱 (VP9/AV1)
    
    // 5. fan-out — subscribers 순회
    janus_mutex_lock(&ps->subscribers_mutex);
    if(videoroom->helper_threads > 0) {
        // helper thread pool 로 분산
        g_list_foreach(videoroom->threads, janus_videoroom_helper_rtpdata_packet, &packet);
    } else {
        g_slist_foreach(ps->subscribers, janus_videoroom_relay_rtp_packet, &packet);
    }
    janus_mutex_unlock(&ps->subscribers_mutex);
    
    // 6. REMB 송신 (필요 시) + FIR/PLI 자체 발사 (fir_freq 주기)
    if(video && ps->active && !ps->muted) {
        // REMB ramp-up 또는 5초 주기
        ...
        // 키프레임 도착 시 fir_latest 갱신, 안 도착하면 reqpli 호출
        if(janus_vp8_is_keyframe(payload, plen)) ps->fir_latest = now;
        ...
        if((now - ps->fir_latest) >= fir_freq * G_USEC_PER_SEC) {
            janus_videoroom_reqpli(ps, "Regular keyframe request");
        }
    }
}
```

**OxLens 대응**:
- 진입점: `crates/oxsfud/src/transport/udp/ingress.rs::handle_srtp` (RTP 패킷 처리)
- fan-out: `PublisherStream::fanout(transport, plaintext, rtp_hdr, sender, ...)` (publisher_stream.rs:407+)
- 차이:
  - Janus: *publisher_stream 별 subscribers GSList* — direct 순회. **OxLens: 방 순회 + sub_peer 순회 + find_subscriber_stream_by_vssrc lookup**
  - Janus: *각 sub-stream 별 munging context* — subscriber_stream.context (janus_rtp_switching_context)
  - OxLens: *SubscribeMode 단일 출처 + SimulcastRewriter / PttRewriter*
  - 키프레임 감지 자리는 양쪽 동일 (VP8/VP9/H264/AV1/H265). OxLens 는 `is_vp8_keyframe / is_h264_keyframe` (ptt_rewriter.rs)

### 3.2 PLI 발사 (line 2973~3050) — `janus_videoroom_reqpli`

```c
static void janus_videoroom_reqpli(janus_videoroom_publisher_stream *ps, const char *reason) {
    if(ps == NULL || g_atomic_int_get(&ps->destroyed))
        return;
    if(ps->publisher == NULL || g_atomic_int_get(&ps->publisher->destroyed))
        return;
    janus_videoroom_publisher *remote_publisher = NULL;
    if(ps->publisher->remote) {
        remote_publisher = ps->publisher;
        if(remote_publisher->remote_rtcp_fd < 0)
            return;
    }
    // ★ CAS 진입 가드
    if(!g_atomic_int_compare_and_exchange(&ps->sending_pli, 0, 1))
        return;
    
    gint64 now = janus_get_monotonic_time();
    // ★ 1초 throttle
    if(now - ps->pli_latest < G_USEC_PER_SEC) {
        // 1초 내 재요청 → 후속 발사 flag 만 set
        g_atomic_int_set(&ps->need_pli, 1);
        g_atomic_int_set(&ps->sending_pli, 0);
        return;
    }
    
    JANUS_LOG(LOG_VERB, "%s, sending PLI ...\n", reason);
    g_atomic_int_set(&ps->need_pli, 0);
    ps->pli_latest = janus_get_monotonic_time();
    ps->fir_latest = ps->pli_latest;
    
    if(remote_publisher == NULL) {
        // 로컬 publisher — Janus core 에 위임
        gateway->send_pli_stream(ps->publisher->session->handle, ps->mindex);
    } else {
        // 원격 publisher — RTCP build + UDP send
        char rtcp_buf[12]; int rtcp_len = 12;
        janus_rtcp_pli((char *)rtcp_buf, rtcp_len);
        ... // sendto(remote_rtcp_fd, ...)
    }
    g_atomic_int_set(&ps->sending_pli, 0);
}
```

**핵심 패턴**:
1. CAS 진입 가드 (`sending_pli` 0→1) — 동시 호출 1개만 통과
2. 1초 throttle — *시간 기반*. 너무 잦은 PLI 회피
3. throttle 적중 시 `need_pli=1` 마킹 — 후속 발사 자리 (시간 경과 후)

**OxLens 대응**: `crate::room::pli_governor::judge_subscriber_pli / judge_server_pli` (pli_governor.rs)
- **OxLens 가 더 발전**:
  - 시간 throttle (Janus 1초) → **관측 사실 기반** (pli_pending + last_keyframe_received_at 비교)
  - Janus 의 `sending_pli` CAS 가드 → OxLens 의 *PliPublisherState.layer.pli_pending* 비슷 의미
  - Janus 의 `need_pli` 후속 발사 → OxLens 의 *consecutive_pli_count* 추적
- **OxLens 도입 자리**:
  - Janus 의 simulcast context `last_relayed` 추적 (line 13425) — *"1초 동안 relay 안 됐으면 need_pli=1"* — OxLens 의 stalled_tracker 패턴 정합

### 3.3 Subscriber fan-out (line 13334~13513) — `janus_videoroom_relay_rtp_packet`

```c
static void janus_videoroom_relay_rtp_packet(gpointer data, gpointer user_data) {
    janus_videoroom_rtp_relay_packet *packet = (janus_videoroom_rtp_relay_packet *)user_data;
    janus_videoroom_subscriber_stream *stream = (janus_videoroom_subscriber_stream *)data;
    
    // 1. 검증: ready/destroyed/send/paused/kicked
    if(!stream || !g_atomic_int_get(&stream->ready) || ...)
        return;
    
    // 2. publisher_stream 매칭 (한 sub stream 이 N publisher 가리킬 수 있어서 검사)
    janus_videoroom_publisher_stream *ps = stream->publisher_streams ?
        stream->publisher_streams->data : NULL;
    if(ps != packet->source || ps == NULL) return;
    
    janus_videoroom_subscriber *subscriber = stream->subscriber;
    janus_videoroom_session *session = subscriber->session;
    
    if(packet->is_video) {
        if(packet->svc) {
            // === SVC 처리 ===
            char *payload = janus_rtp_payload((char *)packet->data, packet->length, &plen);
            char rtph[12];
            memcpy(&rtph, packet->data, sizeof(rtph));
            
            gboolean relay = janus_rtp_svc_context_process_rtp(
                &stream->svc_context, ..., ps->vcodec, &packet->svc_info, &stream->context);
            
            // SVC 가 PLI 요청 시
            if(stream->svc_context.need_pli) {
                janus_videoroom_reqpli(ps, "SVC change");
            }
            if(!relay) return;
            
            // spatial/temporal layer 변경 시 이벤트
            if(stream->svc_context.changed_spatial) {
                json_t *event = json_object();
                json_object_set_new(event, "spatial_layer", ...);
                gateway->push_event(...);
            }
            
            janus_rtp_header_update(packet->data, &stream->context, TRUE, 0);
            // 송신
            janus_plugin_rtp rtp = { .mindex = stream->mindex, .video = TRUE, ... };
            gateway->relay_rtp(session->handle, &rtp);
            memcpy(packet->data, &rtph, sizeof(rtph));  // 헤더 복원
        } else if(packet->simulcast) {
            // === Simulcast 처리 ===
            gboolean relay = janus_rtp_simulcasting_context_process_rtp(
                &stream->sim_context, ...,
                packet->ssrc, NULL, ps->vcodec, &stream->context, &ps->rid_mutex);
            
            if(!relay) {
                // 1초 동안 relay 안 됐으면 PLI 요청 마킹
                gint64 now = janus_get_monotonic_time();
                if((now - stream->sim_context.last_relayed) >= G_USEC_PER_SEC) {
                    g_atomic_int_set(&stream->sim_context.need_pli, 1);
                }
            }
            if(stream->sim_context.need_pli) {
                janus_videoroom_reqpli(ps, "Simulcast change");
            }
            if(!relay) return;
            
            // substream/temporal 변경 시 이벤트
            if(stream->sim_context.changed_substream) {
                json_t *event = json_object();
                json_object_set_new(event, "substream", ...);
                gateway->push_event(...);
            }
            
            janus_rtp_header_update(packet->data, &stream->context, TRUE, 0);
            // VP8 simulcast descriptor 갱신
            char vp8pd[6];
            if(ps->vcodec == JANUS_VIDEOCODEC_VP8 && plen >= sizeof(vp8pd)) {
                memcpy(vp8pd, payload, sizeof(vp8pd));
                janus_vp8_simulcast_descriptor_update(payload, plen, &stream->vp8_context, ...);
            }
            
            janus_plugin_rtp rtp = { .mindex = stream->mindex, .video = TRUE, ... };
            gateway->relay_rtp(session->handle, &rtp);
            // 송신 후 publisher 원본 timestamp/seq 복원 (다음 sub 위해)
            packet->data->timestamp = htonl(packet->timestamp);
            packet->data->seq_number = htons(packet->seq_number);
            if(ps->vcodec == JANUS_VIDEOCODEC_VP8) memcpy(payload, vp8pd, sizeof(vp8pd));
        } else {
            // === Non-simulcast (단순 1:1) ===
            janus_rtp_header_update(packet->data, &stream->context, TRUE, 0);
            gateway->relay_rtp(session->handle, &rtp);
            packet->data->timestamp = htonl(packet->timestamp);
            packet->data->seq_number = htons(packet->seq_number);
        }
    } else {
        // Audio
        janus_rtp_header_update(packet->data, &stream->context, FALSE, 0);
        gateway->relay_rtp(session->handle, &rtp);
        packet->data->timestamp = htonl(packet->timestamp);
        packet->data->seq_number = htons(packet->seq_number);
    }
}
```

**핵심 패턴**:
- *RTP header munging* (`janus_rtp_header_update`) — publisher 가 sub 별로 timestamp/seq 다르게. OxLens 의 `RtpRewriter` / `SimulcastRewriter` / `PttRewriter` 대응
- *Publisher 원본 헤더 복원* — 다음 sub 가 같은 패킷 재사용. **OxLens 도 동일 패턴** (publisher_stream::fanout 의 `payload_for_kf` 캐싱)
- *Simulcast/SVC 컨텍스트 별 처리* — 한 sub 가 *현재 어느 layer 듣는지* `sim_context.substream` 추적. **OxLens 의 `SubscribeMode::VideoSim::layer.rid` 대응**
- *Layer 변경 이벤트* — 클라에게 `push_event` 송신. **OxLens 의 wire op `LAYER_CHANGED` (0x2106) 대응**

### 3.4 SubscriberGate / pause 의미

Janus 는 `subscriber.paused: gboolean` 단일 — *전체 일시정지*. publisher 별 분리 없음.

```c
if(stream->subscriber->paused || stream->subscriber->kicked || ...)
    return;
```

**OxLens 차이**: SubscriberGate 는 *publisher_id 별* (mediasoup 패턴). 새 publisher 발견 시 *그 publisher 만* pause + TRACKS_ACK 후 resume + PLI.

### 3.5 Helper Thread Pool (성능 최적화)

```c
if(videoroom->helper_threads > 0) {
    g_list_foreach(videoroom->threads, janus_videoroom_helper_rtpdata_packet, &packet);
}
```

각 helper thread 가 *subscriber 부분집합* 담당 — fan-out CPU 부담 분산. **OxLens 의 worker_id (SO_REUSEPORT) 와 다른 차원** — OxLens 는 *workers per UDP socket*. Janus 는 *workers per fan-out*.

---

## 4. RTCP 처리 (line 8999~)

```c
void janus_videoroom_incoming_rtcp(janus_plugin_session *handle, janus_plugin_rtcp *packet) {
    janus_videoroom_session *session = ...;
    
    if(session->participant_type == janus_videoroom_p_type_subscriber) {
        // 구독자가 보낸 RTCP — PLI/NACK/RR
        janus_videoroom_subscriber *s = ...;
        // 각 sub stream 의 publisher 측에 relay 또는 dedup
        ...
    } else if(session->participant_type == janus_videoroom_p_type_publisher) {
        // publisher 가 보낸 RTCP — SR
        // 외부로 forward 가능
    }
}
```

**OxLens 대응**: `transport/udp/ingress_subscribe.rs::handle_rtcp_from_subscriber` (line 330+) — RTCP feedback 의 PLI 자리.
- Janus: 단순 *publisher 측 relay 또는 dedup*
- OxLens: `PLI Governor::judge_subscriber_pli` 통과 + 다운그레이드 트리거

---

## 5. RTP Forwarder (외부 송출, line 2531+, rtpfwd.c)

```c
static janus_rtp_forwarder *janus_videoroom_rtp_forwarder_add_helper(
    janus_videoroom_publisher *p,
    janus_videoroom_publisher_stream *ps,
    const gchar *host, int port, int rtcp_port,
    int pt, uint32_t ssrc,
    gboolean simulcast, int srtp_suite, const char *srtp_crypto,
    int substream, gboolean is_video, gboolean is_data);
```

- 외부 UDP 송출 — recording 서버 / 다른 SFU / streaming endpoint
- SRTP 지원 (옵션)
- Simulcast substream 선택 가능

**OxLens 없음**. *cross-room federation* 자체가 cross-sfud 분산 없이 단일 sfud 가정. 축 1 정합.

---

## 6. Recording (MJR 포맷)

`janus_recorder *rc` per publisher_stream:
- *MJR* (Janus 전용 포맷) 으로 디스크 저장
- `janus_videoroom_recorder_create / close` (line 2662)
- post-processing 으로 *Matroska/MP4* 변환

**OxLens 없음**. 미구현 자리.

---

## 7. Audio Level (RFC 6464 — active speaker)

```c
ps->audio_dBov_level    // 최근 audio level (dBov)
ps->audio_active_packets // 누적
ps->audio_dBov_sum
ps->talking              // 발화 중 flag
```

publisher_stream 별 추적. `audio_level_extmap_id` (RTP extension) 기반.

**OxLens 대응**: `crate::room::speaker_tracker` 별도 모듈. Janus 와 다른 자리에 거주.

---

## 8. Remote Publisher (cross-SFU)

```c
gboolean remote;                  // 외부 SFU 의 publisher 인가
uint32_t remote_ssrc_offset;       // SSRC 충돌 회피 offset
int remote_fd, remote_rtcp_fd;     // UDP 소켓
struct sockaddr_storage rtcp_addr;
GThread *remote_thread;            // 외부 RTP 수신 스레드
volatile gint remote_leaving;
```

cross-SFU cascade 시나리오. 외부 SFU 의 publisher 를 *현 SFU 의 가짜 publisher* 로 등록.

**OxLens 없음**. cross-room publish 폐기 (축 1) 정합.

---

## 9. 동시성 — Mutex 패턴

Janus 의 mutex 자리 (한 publisher_stream 안에):
- `publisher.streams_mutex` — publisher 의 streams 목록 보호
- `publisher.subscribers_mutex` — subscriptions
- `publisher.own_subscriptions_mutex` — 이 publisher 가 구독 중인 목록
- `publisher.rtp_forwarders_mutex` — RTP forwarders
- `publisher.mutex` — 일반 보호
- `publisher.rec_mutex` — 녹화기
- `publisher_stream.subscribers_mutex` — 이 stream 의 subscribers
- `publisher_stream.rid_mutex` — simulcast rid 배열
- `publisher_stream.rtp_forwarders_mutex` — stream 별 forwarders
- `subscriber.streams_mutex` — sub stream 목록

→ **mutex 다수**. fan-out hot-path 안 *2~3개 lock*. 단 *짧음* (배열 순회 / 포인터 복사).

**OxLens 차이**: ArcSwap RCU (publish.streams, sub_rooms 등) — read lock-free. Mutex 는 *SRTP context / send_stats / gate / layer / stream_map* 등 *짧은 영역*.

---

## 10. Reference Counting

```c
janus_refcount ref;
janus_refcount_increase(&ps->ref);
janus_refcount_decrease(&ps->ref);
```

C 의 *수동 refcount* — Janus 직접 구현 (`utils.c::janus_refcount_init/increase/decrease`). 회수 시 `_free` 콜백 호출.

**OxLens 대응**: Rust 의 `Arc<T>` — *컴파일러 보장*. *use-after-free* 가능성 0.

---

## 11. Janus 의 *참조할 만한 강점* (OxLens 가 도입 가능한 자리)

### 11.1 SVC (Scalable Video Coding) 지원

- VP9 SVC (spatial × temporal)
- AV1 SVC (Dependency Descriptor extension)
- `janus_rtp_svc_context_process_rtp` — 패킷 별 layer 판단 + drop/relay

**OxLens 없음**. 도입 후보 — 단 *현재 사용 안 함* (simulcast 만). YAGNI 정합.

### 11.2 Dummy Publisher (placeholder)

```c
gboolean dummy;  // dummy publisher used just for placeholder subscriptions
```

→ subscriber 가 *publisher 가 없어도* 구독 가능 (대기 상태). publisher join 시 자연 binding.

**OxLens 없음**. *PTT slot* 자리가 비슷 (per-room virtual_ssrc 가 publisher 없어도 존재) — 의미 부분 흡수.

### 11.3 Audio Level Extension (RFC 6464)

```c
guint8 audio_level_extmap_id;
janus_sdp_mdirection audio_level_mdir;  // 양방향/단방향
```

publisher 가 *audio level* 을 RTP extension 으로 전송. SFU 가 *발화 감지* 가능.

**OxLens 부분 도입**: `speaker_tracker` 모듈. Janus 만큼 정밀하지 않을 수 있음 — 비교 필요.

### 11.4 Playout Delay Extension (RFC 8843)

```c
int16_t min_delay, max_delay;  // playout delay 범위
```

publisher 가 *최소/최대 playout delay* 요청. SFU 가 *그대로 전달*.

**OxLens 없음**. 도입 후보 — *현재 사용 안 함*. YAGNI.

### 11.5 *Crossrefid* — 구독 id 매핑

```c
char *crossrefid;  // 구독 시 클라가 지정. UI 매핑용
```

구독 요청 시 *클라이언트가 id 지정* — *어느 sub stream 이 어느 UI 카드 인지* 매핑.

**OxLens 차이**: server-assigned MID 기반. crossrefid 같은 *클라 hint* 없음 — *간결성 vs 유연성* trade-off.

### 11.6 *Talking* (audio level 기반 발화 감지)

```c
gboolean talking;
int user_audio_active_packets;  // 임계치
int user_audio_level_average;
```

publisher 가 *발화 중인지* 자동 감지 + 이벤트 송신.

**OxLens 부분 도입**: `speaker_tracker`. Conference 시나리오 의 *active speaker* 추적 자리.

### 11.7 *Helper threads* — fan-out CPU 분산

```c
int helper_threads;
GList *threads;
```

방 별 *helper thread pool* — N sub fan-out 부담 분산. **OxLens 의 worker_id 와 다른 차원**.

### 11.8 *Remote Publisher* (cross-SFU cascade)

별도 thread 로 외부 SFU 의 RTP 수신.

**OxLens 폐기 (축 1 정합)**.

### 11.9 *RTP Forwarder* — 외부 송출

녹화 / 다른 SFU / streaming endpoint 로 RTP 송출.

**OxLens 없음**. 추후 *녹화 서비스* 추가 시 도입 후보.

### 11.10 *Single file* 운영성

14,266 줄 단일 파일 — *컨텍스트 검색 비용 0* (한 파일 안에 모든 흐름). **단점**: 가독성 ↓, 신규 진입 큼.

**OxLens 는 모듈 분리** (room/transport/signaling/hooks/) — 가독성 ↑. Janus 단일 파일 패턴은 *흉내 비추천*.

---

## 12. Janus 의 *기각할 패턴*

### 12.1 *Single file 단일* — 가독성 ↓
14,266 줄 1 파일은 *유지보수 비용* 큼. 신규 개발자 *컨텍스트 학습 어려움*.

### 12.2 *수동 refcount*
C 에서 *수동 increase/decrease* — *누수 위험 + use-after-free 위험*. Rust `Arc` 가 안전.

### 12.3 *Mutex 다수*
한 자료구조 별 *5~10 mutex*. dead-lock 가능성. **OxLens 의 ArcSwap RCU 가 우월**.

### 12.4 *시간 기반 PLI throttle (1초)*
*관측 사실 기반* (OxLens) 가 우월.

### 12.5 *GLib 의존*
`GList`/`GHashTable`/`GSList`/`janus_mutex` — GLib 의존. Rust 의 `Vec/HashMap/DashMap` 표준 라이브러리 우월.

### 12.6 *publisher 가 자기 subscription 추적*
`publisher.subscriptions: GSList` — *user 가 구독 중인 다른 publisher 목록* 까지 추적. **자료구조 중복**. OxLens 는 *Peer.subscribe.streams 단일* — 정합.

---

## 13. OxLens ↔ Janus 매핑 요약 표

| 영역 | Janus | OxLens |
|------|-------|--------|
| 언어 | C + GLib | Rust + Tokio |
| 아키텍처 | plugin (Janus core ↔ plugin) | 모놀리스 (oxsfud) |
| 코어 인프라 | Janus core (ICE/DTLS/SCTP) | oxrtc 직접 구현 |
| 자료구조 (방) | `janus_videoroom` | `crate::room::Room` |
| 자료구조 (publisher) | `janus_videoroom_publisher` | `Peer` + `RoomMember` |
| 자료구조 (publisher stream) | `janus_videoroom_publisher_stream` | `PublisherStream` |
| 자료구조 (subscriber) | `janus_videoroom_subscriber` | (Peer 안에 흡수) |
| 자료구조 (subscriber stream) | `janus_videoroom_subscriber_stream` | `SubscriberStream` |
| Simulcast | `vssrc[3]`, `sim_context` | `SubscribeMode::VideoSim { layer }` |
| SVC | spatial/temporal context | **없음** (도입 후보) |
| PLI throttle | 시간 기반 1초 throttle | **PLI Governor** (관측 사실 기반) |
| Subscriber pause | `subscriber.paused: gboolean` 단일 | **SubscriberGate** per-publisher (mediasoup 패턴) |
| Audio level | `audio_dBov_level` per stream | `speaker_tracker` 별도 |
| 녹화 | `janus_recorder` MJR | **없음** |
| Cross-SFU | `remote_publisher` + remote_thread | **폐기 (축 1)** |
| RTP forwarder | `rtp_forwarders` 외부 송출 | **없음** |
| Refcounting | `janus_refcount` 수동 | `Arc<T>` 자동 |
| 동시성 | mutex 다수 + helper threads | ArcSwap RCU + tokio + worker_id (SO_REUSEPORT) |
| BWE | REMB (기본) | TWCC / REMB 둘 다 |
| RTCP | core 가 relay/dedup | RTCP Terminator (서버 자체 RR/SR) |
| 파일 구조 | 단일 14266줄 | 모듈 분리 (~30 파일) |

---

## 14. 결론 — Janus 에서 *배울 자리*

1. **SVC 지원** — 향후 회의 품질 강화 시 도입 후보 (단 YAGNI)
2. **Audio Level extension** — `speaker_tracker` 와 결합. publisher 측 발화 감지 강화
3. **Playout Delay extension** — 회의 시나리오의 *지연 제어* 자리
4. **Helper threads** — 방 별 *fan-out 분산*. 대규모 회의 (N sub 큼) 시 검토. OxLens 의 worker_id 와 다른 차원
5. **RTP forwarder** — 녹화 / 외부 cascade. 추후 *녹화 서비스* 추가 시
6. **Dummy publisher** — *publisher 가 없어도 구독 가능* — UX 의 *대기 상태* 자리

## 15. 결론 — Janus 에서 *기각할 자리*

1. **단일 파일** — 14266 줄 — 절대 따라하지 말 것
2. **수동 refcount** — 누수 위험. Rust Arc 우월
3. **Mutex 다수** — ArcSwap RCU 가 우월
4. **시간 기반 PLI throttle** — *관측 사실 기반* 이 우월 (OxLens 는 이미 적용)
5. **publisher 가 subscription 추적** — 자료구조 중복
6. **GLib 의존** — Rust 표준 우월

---

*author: 김과장 — 2026-05-17 Phase 0 레퍼런스 심층 분석*
