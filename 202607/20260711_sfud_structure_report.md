// author: kodeholic (powered by Claude)
# oxsfud 구조 진단서 — SFU 미디어 엔진 전수 분석 (20260711)

> 목적: 부장님 리뷰용 진단서. 소스 없이도 구조 파악이 되도록 "쉬운 개념 → 실제 구조 → 소스 좌표" 순으로 서술.
> 범위: `oxlens-sfu-server/crates/oxsfud` 단독 (81파일 27,567줄, HEAD `2e477dd` 기준). oxrtc/common/oxhubd 는 경계 계약만 언급.
> 방법: 6개 병렬 전수 정독(시그널링/도메인/핫패스/혼잡제어/PTT/골격·관측성) + 마스터 문서·감사 이력 교차.
> 비중: 구조 7 : 비평 3. 각 장 끝에 [진단] 절, 제9장에 종합.
> 자매 문서: PROJECT_SERVER.md(구조 단일출처), 20260703_sfud_source_audit.md(전수 감사), 20260711_auto_layer_final_report.md(자동 레이어 완결).

---

## 읽기 전 5분 — 이 문서에 반복 등장하는 용어

| 용어 | 뜻 |
|---|---|
| **SFU** | Selective Forwarding Unit. 미디어를 디코딩하지 않고 "받은 RTP 패킷을 골라서 전달"만 하는 중계 서버. MCU(믹싱)와 달리 CPU가 싸고 지연이 짧다. |
| **RTP / RTCP** | RTP = 실제 오디오/비디오 패킷. RTCP = 그 품질 리포트·제어 패킷(수신 리포트 RR, 송신 리포트 SR, 재전송 요청 NACK, 키프레임 요청 PLI 등). |
| **SSRC** | RTP 스트림의 32bit 식별번호. "이 패킷이 어느 스트림 것인가"를 말해 준다. |
| **seq / ts** | RTP 시퀀스 번호(패킷 순번)와 타임스탬프(재생 시각). 수신기는 이 둘의 연속성으로 스트림을 재조립한다. |
| **ICE / DTLS / SRTP** | 순서대로: 주소 뚫기(어느 IP:port로 통신할지 합의) / 암호 키 합의(TLS의 UDP판) / 그 키로 RTP를 암호화한 것. UDP 한 소켓 위에 셋이 겹쳐 흐른다. |
| **simulcast** | 송신자가 같은 화면을 고화질(h)/저화질(l) 두 벌로 동시에 올리고, 서버가 수신자별로 골라 주는 방식. |
| **PTT / Floor** | Push-To-Talk 무전. Floor = "지금 누가 말할 권리를 갖는가"의 중재(3GPP MCPTT 용어). |
| **DataChannel(DC) / SCTP** | WebRTC의 데이터 통로. 본 시스템에선 Floor 제어 메시지(MBCP)가 이 통로로 오간다. |
| **핫패스(hot path)** | 초당 수천 번 도는 패킷 처리 경로. 여기서 락을 잡거나 메모리를 할당하면 전체 성능이 무너지므로 별도 규율이 적용된다. |
| **ArcSwap / DashMap / Atomic** | 락 없이 공유 상태를 다루는 Rust 도구들. ArcSwap = 포인터 통째 교체(RCU), DashMap = 샤딩된 동시 해시맵, Atomic = 정수 단위 원자 연산. |
| **RCU** | Read-Copy-Update. 읽기는 무제한 동시, 쓰기는 "복사본 만들어 통째 교체". 읽기가 압도적으로 많은 자료에 쓴다. |

---

## 제1장. 개관 — oxsfud는 무엇이고 어디에 서 있는가

### 1.1 한 문장 정의

oxsfud는 **"방(Room)·참가자(Peer)·발화권(Floor)의 상태 마스터이자, RTP 패킷을 선별 전달하는 미디어 엔진"**이다. Cargo.toml의 자기소개도 동일하다: `description = "OxLens SFU Daemon — media engine + state master"` (crates/oxsfud/Cargo.toml).

"상태 마스터"라는 말이 중요하다. 이 시스템에서 누가 어느 방에 있는지, 누가 발화권을 쥐고 있는지, 어떤 트랙이 발행 중인지의 **유일한 진실은 oxsfud 메모리 안에 있다**. 앞단의 oxhubd(WS 게이트웨이)는 투명 프록시로 user_id만 주입해 넘기고, 정책 해석·상태 변경은 전부 oxsfud가 한다. 별도 DB 없음 — 상태는 전부 인메모리이고, 프로세스가 죽으면 상태도 사라지며 복구는 클라이언트 재합류(R1/R2)가 담당한다.

### 1.2 시스템 안에서의 위치

```
[웹/Android 클라] ──WS(JSON/binary)── [oxhubd] ──gRPC passthrough── [oxsfud]  ← 이 문서의 대상
        │                            (게이트웨이,                 (상태 마스터 +
        └────────UDP(STUN/DTLS/SRTP)────supervisor)───────────────  미디어 엔진)
                     ↑ 미디어는 hub를 거치지 않고 클라 ↔ sfud 직결
[oxcccd] ← 텔레메트리 수집   [oxadmin] → hub REST 경유 운영 CLI
```

- **시그널링 경로**: 클라 → hub(WS) → sfud(gRPC `Handle`, JSON/binary passthrough). hub는 내용을 해석하지 않는다(proto 36줄짜리 `WsMessage {oneof json/binary}`).
- **미디어 경로**: 클라 ↔ sfud 직접 UDP. 한 소켓 위에 STUN/DTLS/SRTP가 다중화되어 흐르고, sfud가 첫 바이트로 갈라 처리한다(제4장).
- **프로세스 관계**: oxhubd가 supervisor로서 oxsfud N개를 자식 프로세스로 기동/감시/재기동한다. 계약 상수는 `common/process.rs` 공유(고아 프로세스 포트 점유 사고의 재발 방지 장치).
- **cross-sfu**: 배치 단위는 "방 → sfu 1:1"(user가 아님). 여러 sfud가 있어도 한 방의 미디어는 한 sfud에만 있다. SFU 간 미디어 릴레이는 기각된 설계다.

### 1.3 규모와 모듈 지도

81개 .rs 파일, 27,567줄 (2026-07-11 HEAD `2e477dd`). 디렉터리별 배치와 규모:

| 모듈 | 파일 수 | 대략 줄 수 | 책임 |
|---|---|---|---|
| `domain/` | 21 | ~9,600 | 도메인 모델 — Room/Peer/Stream/Track/Slot/Floor/혼잡제어 판단 |
| `transport/` | 17 | ~6,600 | UDP 핫패스 — demux/ICE/DTLS/SRTP/ingress/egress/RTCP/TWCC |
| `signaling/` | 11 | ~4,300 | 시그널링 — opcode/dispatch/핸들러 8파일 |
| `datachannel/` | 3 | ~1,800 | SCTP/DCEP/MBCP(Floor 제어 wire) |
| 루트(main/lib/config/tasks/trace 등) | 13 | ~1,900 | 골격 — 기동/백그라운드 태스크/설정/트레이스 |
| `metrics/` + `hooks/` | 8 | ~850 | 관측 — 메트릭/phase 훅 |
| `grpc/` | 2 | ~410 | tonic 서버(SfuService) |

큰 파일 상위 5개가 어디인지가 이 코드베이스의 무게중심을 말해 준다: `domain/peer.rs`(1,619줄 — 참가자 상태의 뿌리), `domain/publisher_track.rs`(1,270줄 — 물리 트랙+fan-out+NACK), `transport/udp/twcc.rs`(1,142줄 — v2 BWE 배관, 최신), `signaling/handler/track_ops.rs`(1,119줄 — 트랙 발행/구독), `signaling/handler/helpers.rs`(852줄 — 구독 수집/mid 할당).

### 1.4 외부 크레이트 경계 — 무엇을 직접 만들고 무엇을 빌렸나

의존성 목록(Cargo.toml)이 설계 철학을 드러낸다:

- **빌린 것**: DTLS 핸드셰이크(`dtls` 0.17), SRTP 암복호(`webrtc-srtp` 0.17), SCTP 상태기계(`sctp-proto` 0.9, Sans-I/O), 런타임(tokio), gRPC(tonic).
- **직접 만든 것**: ICE-lite/STUN 처리, RTP/RTCP 파싱과 재작성, NACK/PLI/RTX 회복 기계, TWCC/GCC 혼잡제어, MBCP TLV, 시그널링 전부.

즉 "**암호와 전송 프리미티브는 검증된 것을 쓰고, 미디어 의미론은 전부 자작**"이다. webrtc-rs 풀스택이나 mediasoup 같은 기성 SFU를 쓰지 않고 RTP 계층을 직접 쥔 것이 이 프로젝트의 정체성이며, PTT 같은 비표준 요구(가상 SSRC 슬롯, 발화자 전환 리라이팅)를 소화할 수 있는 근거다.

### 1.5 설계 철학의 코드 반영 — 다섯 가지 기둥

마스터 문서의 원칙들이 실제 코드 구조로 어떻게 나타나는지. (각 항목의 상세는 해당 장에서.)

1. **핫패스에 락 없음** — 패킷 경로에서 Mutex/RwLock 접촉 0을 목표로, 공유 상태는 ArcSwap/DashMap/Atomic으로만. "핫패스 stream_map lock = 0건" 같은 이력이 그 산물(제7장에서 전수 검증).
2. **Scope는 타입으로 표현** — user 것은 `Peer`, PC쌍 것은 `PublishContext`/`SubscribeContext`, 방 멤버십 것은 `RoomMember`. 필드의 "사는 곳"이 의미를 말하게 하고 주석에 의존하지 않는다(제3장).
3. **논리/물리 2계층** — 클라의 MediaStream(논리)과 MediaStreamTrack(물리) 구분을 서버가 그대로 거울: `PublisherStream`(track_id/vssrc 소유) vs `PublisherTrack`(실 SSRC 소유). simulcast에서 물리 트랙이 갈라져도 논리 식별자는 생존한다(제3장).
4. **fan-out 방향 역전** — "구독자가 발행자를 찾는" 역탐색 대신 "발행자가 구독자 목록(Weak)을 직접 들고 순회". 라우팅 키 조회가 핫패스에서 사라졌다(제3·4장).
5. **IoC 금지, 직접 호출** — 콜백 주입/훅 릴레이 없이 모듈이 모듈을 직접 부른다. 흐름이 소스에서 정적으로 추적된다(전 장 공통).

### 1.6 [진단] 개관 수준에서 보이는 것

**강점**: ① 책임 경계가 데몬 단위로 선명하다 — hub는 통과, sfud는 결정. 상태 이원화가 없어 "어느 쪽이 진실인가" 논쟁이 원천 차단된다. ② 모듈 배치가 개념 축과 일치한다 — PC 종류 축(publish/subscribe)은 domain의 Context로, 패킷 방향 축(ingress/egress)은 transport/udp로, 두 축이 섞이지 않는다. ③ 의존성 선택이 보수적이다 — 암호는 빌리고 의미론은 소유.

**주의점**: ① `default = ["trace"]` — 평문 미디어 탭이 기본 빌드에 포함된 상태. Cargo.toml 주석 자체가 "상용 전 반드시 제거"를 자백하는 기지 항목이며, 상용 체크리스트의 1번이어야 한다. ② 인메모리 단일 진실은 장점이자 제약 — sfud 프로세스 사망 = 그 sfud 담당 방들의 상태 전멸이며, 복구 부담이 전적으로 클라이언트 재합류에 있다. 현 규모(랩·소규모 운용)에선 올바른 트레이드오프이나, 방 수 × 참가자 수가 커지면 재합류 폭풍(thundering herd)이 설계 토픽으로 돌아온다. ③ 큰 파일 상위권(peer.rs 1.6k, track_ops.rs 1.1k)은 책임이 많아서 큰 것 — 분할 자체가 목적이 되어선 안 되지만, peer.rs는 제3장에서 내부 응집도를 따로 본다.

---

## 제2장. 시그널링 평면 — 명령은 어떻게 들어와서 어떻게 퍼지는가

> 대상: `signaling/` 11파일 + `grpc/` 2파일 + `event_bus.rs` (~4,700줄). opcode 원본은 `crates/oxsig`.

### 2.1 쉬운 그림 먼저 — 두 개의 물길

sfud의 시그널링은 방향이 다른 두 물길로 이뤄진다.

- **요청 물길(클라→서버)**: 클라가 WS로 hub에 보낸 메시지를 hub가 gRPC `Handle`로 그대로 넘긴다(내용 해석 없음, user_id만 주입). sfud가 해석·처리하고 응답 1개를 되돌린다. **1요청 1응답**.
- **이벤트 물길(서버→클라)**: sfud 안에서 일어난 일(누가 들어옴, 트랙 생김, 발화권 변동)을 hub가 미리 열어 둔 gRPC `Subscribe` 스트림으로 흘리고, hub가 대상 클라에게 WS로 배달한다. **불특정 다수 대상**.

이 두 물길이 만나는 지점은 없다 — 응답은 요청자에게만, 이벤트는 브로드캐스트 채널로만. 헷갈리기 쉬운 두 개념이 코드에서 물리적으로 분리돼 있다.

### 2.2 opcode 체계 — 번호가 곧 문서다

모든 메시지는 8바이트 wire 헤더 + 본문이고, 헤더의 op 번호 **상위 4비트(nibble)가 카테고리를, 다음 4비트가 도메인을** 말한다(oxsig/src/opcode.rs:9-21). 총 44개 op:

```
0x0xxx Handshake (hub 로컬)     0x1xxx Request  (클라→서버, 응답 필수)
0x2xxx Event    (서버→클라)     0x3xxx Admin    (운영 평면)
0xExxx Internal (hub↔sfud)      0xFxxx Error
   두 번째 자리: 0=Room, 1=Media, 2=Scope, 3=Data, 4=Floor, 5=Speakers, 7=Extension
```

예: `0x1003`=ROOM_JOIN(Request/Room), `0x2101`=TRACKS_UPDATE(Event/Media), `0x2400`=FLOOR_MBCP(Event/Floor, 유일한 binary body), `0x3005`=ADMIN_DOWNLINK_INJECT.

이 규약의 힘은 **파생 속성이 전부 번호에서 자동 계산**된다는 것: 우선순위(FLOOR/MODERATE 계열=CRITICAL, 요청·제어=CONTROL, 채팅·스피커=INFO, admin=TELEMETRY), pid 부여 여부, body가 JSON인지 binary인지(`body_is_binary` — FLOOR_MBCP만 true), 이벤트 intent 비트까지(common/src/signaling/mod.rs:40-91). 새 op를 추가하면 번호만 규약대로 고르면 배관이 따라온다. 카탈로그 불변식(중복 없음, 카테고리 상호 배타)은 단위 테스트가 강제한다(oxsig/src/opcode.rs:272-411).

### 2.3 요청 물길 해부 — Handle → dispatch → 핸들러

한 요청의 일생 (grpc/sfu_service.rs:69-151 → signaling/handler/mod.rs:74-146):

1. **gRPC 진입**: `WsMessage{user_id, room_id, wire}` 수신. wire가 8바이트 미만이면 즉시 거부.
2. **FLOOR_MBCP 지름길**: 헤더 op가 0x2400이면 JSON 파싱 없이 body를 `floor_ops::handle_floor_binary`로 직행하고 빈 응답 반환(fire-and-forget). 발화권은 지연에 민감해서 일반 경로를 안 탄다.
3. **envelope 주입**: body JSON에 hub가 검증한 `user_id`를 **무조건 덮어쓰고**, `room_id`는 body에 없을 때만 채운다(sfu_service.rs:109-116). 클라가 남의 user_id를 사칭할 수 없게 하는 보안 장치 — 대신 kick/reap처럼 "남"을 지목하는 op는 `target_user`라는 별도 필드를 쓴다(§2.7 진단 참조).
4. **dispatch**(handler/mod.rs): ACK면 무시, 미인증이면 1001, 나머지는 op별 match로 8개 핸들러 파일에 위임.
5. **응답 조립**: 핸들러가 돌려준 `Packet`을 wire로 프레이밍해 반환. 라우팅 필드는 전부 비운다(단일 응답이라 불필요).

**핸들러 8파일의 분업**:

| 파일 | 담당 op | 요지 |
|---|---|---|
| `room_ops.rs`(701줄) | LIST/CREATE/JOIN/LEAVE/SYNC/MESSAGE | 방 생명주기. JOIN이 최복잡(아래) |
| `track_ops.rs`(1,119줄) | PUBLISH/TRACKS_READY/MUTE/CAMERA/SUBSCRIBE_LAYER/TRACK_STATE_REQ | 미디어 발행·구독·duplex 전환 |
| `scope_ops.rs`(250줄) | SCOPE(0x1200) | N방 청취/1방 발언 스코프 |
| `floor_ops.rs`(231줄) | (dispatch 우회) WS bearer MBCP | DC와 동일 상태기계의 WS 판 |
| `helpers.rs`(852줄) | — | 공용: emit, 구독 수집, mid 할당, evict |
| `admin.rs`(652줄) | SNAPSHOT/REAP/DOWNLINK_INJECT | 운영 평면 |
| `client_event.rs`(41줄) | CLIENT_EVENT | 클라 사건 보고 → agg 카운팅 |
| `mod.rs`(146줄) | — | dispatch 라우터 |

### 2.4 대표 흐름 셋 — JOIN, PUBLISH, SYNC

**ROOM_JOIN**(room_ops.rs:141-355)은 이 평면에서 가장 긴 절차다. 순서대로: 방 확인 → pc_mode 판정(미상 값은 reject — 묵시 기본값 함정 차단) → Peer 확보(user당 1개, ICE 자격은 생성 시 1회) → **모드 불일치·AlreadyInRoom이면 take-over**(기존 세션 evict 후 새 Peer로 재시도 — 재접속 race의 정답) → 명시 select(발언방 지정) → STUN/구독자 인덱스 등록 → `collect_subscribe_tracks`로 기존 트랙 수집 → participant_joined 브로드캐스트 → 응답에 **서버가 아는 모든 것을 동봉**: 참가자 목록, scope 스냅샷, server_config(ICE/DTLS/코덱/extmap — 클라가 SDP를 로컬 조립하는 SDP-Free 시그널링의 재료), 구독할 트랙 목록.

**PUBLISH_TRACKS**(track_ops.rs:23-324)의 요체는 "**시그널이 먼저, RTP가 나중**": extmap ID 5종을 atomic에 저장하고, 논리 Stream을 RTP 도착 전에 확정 등록한다(`register_stream`). video인데 codec 미지정이면 **전체 거절** — 과거 "묵시 VP8" 검은 화면 사고의 재발 방지가 코드로 박힌 자리(track_ops.rs:85-96). 이후 트랙 성격(TrackType)별로 갈라진다: PTT(HalfNonSim)는 slot이 방에 상존하므로 브로드캐스트조차 안 하고, 일반(FullNonSim)은 구독자마다 mid를 할당해 TRACKS_UPDATE를 per-user로 보낸다.

**ROOM_SYNC**(room_ops.rs:361-407)는 폴링용 전체 재동기화. 특기할 것은 에러코드 선택 — 세션이 없으면 2003이 아니라 **1001**을 준다. 클라 SDK가 2001/2003/2004를 "서버가 나를 잊었다 → 방을 forget하라"로 해석하기 때문에, 재연결 race에서 멀쩡한 방을 잊는 사고를 코드 번호 선택으로 차단한 것(room_ops.rs:362-367). wire 계약의 소비자를 아는 서버 코드다.

### 2.5 구독 수집과 mid 할당 — collect_subscribe_tracks

`helpers.rs:260-491`은 "이 구독자가 지금 받아야 할 트랙 전부"를 계산하는 이 평면의 심장이다. 브라우저는 m-line(=mid)의 순서와 재활용에 극도로 민감하므로 서버가 mid를 주도한다.

1. **sub_rooms 전 방 순회** — N방 청취면 모든 방의 트랙+PTT slot을 한 번에.
2. **attach 대상 분류** — full 트랙은 Track/Stream(AttachTarget), PTT slot은 Slot으로.
3. **mid 할당** — track_id당 고정 mid를 `MidPool`에서 부여. 사라진 트랙의 mid는 먼저 회수(`release_stale_mids`)하고, kind별 재활용 풀에서 꺼낸다.
4. **m-line 정렬** — mid 오름차순 정렬로 재협상 시 "m-lines order doesn't match" 브라우저 오류를 원천 차단(helpers.rs:423-428).
5. **배관 연결** — SubscriberStream을 만들고 발행자 쪽 subscribers 목록에 Weak 등록. **이미 구독 중인 트랙에는 gate.pause를 다시 걸지 않는다**(멱등 체크, helpers.rs:473-478) — SYNC 폴링이 기존 영상을 끊던 회귀의 봉합 자국.

한 가지 실무 팁: half로 전환됐지만 full 이력이 있는 트랙(개인 mid 보유)은 `active:false`로 목록에 남긴다 — mid 캐싱을 살려서 half→full 복귀 때 재협상 없이 재활성하기 위해서다.

### 2.6 이벤트 물길 — WsBroadcast와 hub 스트림

이벤트의 그릇은 `WsBroadcast{room_id, exclude_user_ids, target_user_id, wire}` 하나다(event_bus.rs:13-21). target이 비면 방 브로드캐스트, 채워지면 unicast. **v3에서 wire 단일화**됐다 — 과거의 per_user_payloads/binary_payload 3원 구조는 폐기됐고, per-user 차별화(구독자마다 mid가 다른 TRACKS_UPDATE 등)는 `emit_per_user_tracks_update`(helpers.rs:549-575)가 **user마다 별도 unicast를 발행**하는 방식으로 대체됐다. ⚠️ 마스터 문서(PROJECT_SERVER.md)의 "per_user_payloads + binary_payload" 서술은 이 v3 전환을 반영하지 못한 낡은 서술이다 — 문서 정합 대상(제9장).

전달 배관: 핸들러 → `emit_to_hub` → `broadcast::channel(4096)` → gRPC `Subscribe` 스트림 → hub OutboundQueue(pid 재할당·우선순위 큐) → 클라. 채널이 넘치면 **가장 오래된 이벤트부터 조용히 버린다**(lag skip, sfu_service.rs:182-185) — §2.7 진단 참조.

admin 물길은 별도다: `SubscribeAdmin` 스트림이 telemetry_bus 이벤트와 3초 주기 방 스냅샷을 select!로 병합해 흘린다(sfu_service.rs:197-277). admin.rs의 스냅샷 빌더는 방 축과 user 축을 분리해 조립하고(rooms + users 배열), 자료구조를 건드리지 않고 응답에서만 파생값을 계산하는 derive 헬퍼(파생 활성 여부, 가상 트랙 여부 등)를 쓴다.

### 2.7 [진단] 시그널링 평면

**강점**
1. **자기서술 opcode** — 번호가 카테고리·우선순위·바디 포맷·pid 규칙을 결정하고 테스트가 불변식을 지킨다. wire 계약 확장이 규약을 따라가는 한 안전.
2. **묵시 기본값 함정의 조직적 차단** — pc_mode 미상 reject, video codec 미지정 전체 거절, auto_layer off 시 inject 거부(조용한 no-op 금지). "모르면 기본값" 대신 "모르면 거절"이 일관 적용된 흔적은 사고 이력에서 배운 조직 학습이다.
3. **scope 변경 op는 결과 스냅샷 동봉** — JOIN/LEAVE/SCOPE 응답에 서버 권위 스냅샷이 실려 클라 낙관 갱신을 없앤다(server-authoritative 원칙의 wire 구현).
4. **회귀 봉합 자국의 밀도** — mid 재활용 kind 분리, SYNC 멱등 gate, 1001 에러코드 우회 등 실사고 봉합이 해당 자리마다 주석·코드로 남아 있다.

**리스크·냄새**
1. **target_user 우회 규약의 산재** — envelope가 body.user_id를 무조건 덮어쓰므로 "남을 지목하는" admin성 op는 전부 `target_user` 별도 필드를 써야 한다(room_ops.rs:421-424, admin.rs:583,613). 이 규약이 코드 3곳에 흩어져 있고 강제 장치가 없다 — 새 admin op를 만드는 사람이 body.user_id를 쓰면 자기 자신을 kick하는 부류의 버그가 재발한다. dispatch 층에서 규약을 한 번에 강제할 자리.
2. **이벤트 채널 오버플로 = 조용한 상태 불일치** — broadcast 4096 초과 시 TRACKS_UPDATE 같은 상태 이벤트도 lag로 버려진다. 클라에 ROOM_SYNC 복구 경로가 있어 치명은 아니나, 드롭 카운터/경보가 없어 폭주 상황에서 "왜 클라 상태가 어긋났나"의 단서가 로그 한 줄뿐이다.
3. **admin 스냅샷 O(전체)** — 단일 방 조회(`build_room_snapshot`)도 전체 방·전체 user 스냅샷을 만들고 필터링한다(admin.rs:526-533). 3초 주기 tick과 겹치면 방·유저 수에 선형으로 비용이 늘고, 스냅샷 조립이 forwarder/mid_map 등 다수 Mutex를 잠깐씩 잡는다. 현 규모 무해, 확장 시 상위 재방문 목록.
4. **에러코드 이중 체계** — `LightError` 카탈로그(error.rs)가 권위인데 핸들러 곳곳은 numeric 리터럴 `Packet::err(op,pid,1002,...)`를 직접 쓴다. 0703 감사에서 충돌(S5)은 정리됐지만, 리터럴 직접 사용이 남아 있는 한 같은 부류의 드리프트가 재발 가능한 구조다.
5. **SCOPE_EVENT(0x2200) 미완** — op 정의·우선순위·intent 배선은 있으나 emit하는 곳이 없다(scope_ops.rs:17). cross-room 상황에서 타 참가자에게 scope 변화가 통지되지 않는 상태(S-d 미결). 의도된 보류지만, 카탈로그만 보면 구현된 것처럼 읽힌다.
6. **`unwrap()` 산재** — `ctx.user_id.clone().unwrap()`류는 dispatch 인증 가드가 보호하지만, `mid_map.lock().unwrap()`은 Mutex poisoning 시 해당 gRPC 태스크 패닉으로 이어진다. tonic이 태스크 단위로 격리해 프로세스는 살지만, 원인 없는 요청 실패로 관측된다.

---

## 제3장. 도메인 모델 — 방·참가자·트랙은 메모리에 어떻게 사는가

> 대상: `domain/` 17파일 6,727줄 (혼잡제어·Floor·rewriter 계열은 각각 제5·6장에서). 이 장이 이 문서의 척추다 — 제4장(핫패스)의 모든 조회가 여기서 정의된 자료구조 위에서 일어난다.

### 3.1 쉬운 그림 먼저 — 세 가지 세계

이 서버의 도메인 모델은 세 세계로 나뉜다.

1. **방의 세계** — `RoomHub` → `Room` → `RoomMember`. "어느 방에 누가 있는가."
2. **사람의 세계** — `PeerMap` → `Peer`. "이 유저의 연결(ICE/DTLS/SRTP)과 발행/구독 자산 전부."
3. **미디어의 세계** — `PublisherStream`(논리) / `PublisherTrack`(물리) / `SubscriberStream`(수신측). "패킷이 실제로 타고 흐르는 배관."

핵심 규칙 하나만 기억하면 길을 잃지 않는다: **한 유저의 진짜 몸은 `Peer` 하나이고, 방은 그 몸을 빌려 볼 뿐이다.** 유저가 방 3개에 들어가도 PC(PeerConnection) 쌍은 1쌍, SRTP 키도 1벌, 트랙 목록도 1벌 — 전부 Peer 소유다. 방에는 `RoomMember`라는 얇은 명찰(room_id + role + joined_at + `Arc<Peer>`)만 놓인다 (participant.rs:38-47). "user × sfud = PC pair 1쌍, 방 수와 무관"이라는 마스터 원칙이 자료구조로 그대로 구현된 것이다.

### 3.2 소유 관계 전체 지도 — 누가 누구를 들고 있는가

Rust에서 "누가 소유하는가"는 곧 "누가 언제 죽는가"다. 전체 트리:

```
RoomHub.rooms: DashMap<RoomId, Arc<Room>>                      ← 방의 뿌리
 └─ Room
     ├─ participants: DashMap<user_id, Arc<RoomMember>>         (명찰들)
     │   └─ RoomMember.peer: Arc<Peer>                          (몸을 빌려 봄 — 소유자 아님)
     ├─ slots: Vec<Arc<Slot>>                                   (PTT 가상 채널, 방마다 audio/video 2개 고정)
     │   ├─ current_publisher: ArcSwap<Option<Weak<PublisherTrack>>>   [Weak]
     │   └─ subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>          [Weak]
     ├─ floor: FloorController                                  (발화권 — 제6장)
     └─ speaker_tracker: Mutex<SpeakerTracker>                  (active speaker)

PeerMap ← Peer의 "진짜 소유자"
 ├─ by_user: DashMap<user_id, Arc<Peer>>                        ← 여기가 Peer의 홈
 ├─ by_ufrag / by_addr: DashMap<..., (Arc<Peer>, PcType)>       (STUN·SRTP 조회용 별칭 인덱스)
 └─ by_room_subscriber: DashMap<RoomId, DashMap<user_id, Arc<Peer>>>  (방별 구독자 색인)

Peer
 ├─ publish: PublishContext
 │   ├─ streams: ArcSwap<Vec<Arc<PublisherStream>>>             ← 논리 Stream의 홈
 │   │   └─ PublisherStream
 │   │       ├─ tracks: ArcSwap<Vec<Arc<PublisherTrack>>>       (물리 Track — 2중 소유 지점 ①)
 │   │       └─ subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>      [Weak]
 │   └─ tracks: ArcSwap<PublisherTrackIndex>                    (물리 Track — 2중 소유 지점 ②)
 │       └─ PublisherTrack
 │           ├─ subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>      [Weak]
 │           └─ stream: ArcSwap<Option<Weak<PublisherStream>>>         [Weak — 순환 회피]
 └─ subscribe: SubscribeContext
     └─ streams: ArcSwap<SubscriberStreamIndex>                 ← SubscriberStream의 "진짜 홈"
```

읽는 법:
- **Arc = 소유**(내가 살아 있는 한 상대도 산다), **Weak = 캐시**(상대가 죽었으면 upgrade가 실패할 뿐, 잡아두지 않음).
- **역참조는 예외 없이 전부 Weak다** — Track→Stream(publisher_track.rs:367-370), Slot→발화자 Track(slot.rs:81-83), 모든 fan-out subscribers 목록(publisher_track.rs:360-365, publisher_stream.rs:73-81, slot.rs:84-88). 덕분에 참조 순환(메모리 누수의 고전 원인)이 구조적으로 불가능하다.
- SubscriberStream의 진짜 소유자는 구독자 자신의 `SubscribeContext.streams`다. 발행자 쪽 subscribers 목록들은 전부 Weak 캐시라서, 구독자가 나가며 Arc가 drop되면 발행자 쪽 항목은 "저절로 죽은 포인터"가 되고, 다음 attach 때 청소된다(명시적 detach 없음 — §3.6).

### 3.3 Peer 해부 — 1,619줄의 무게중심

`Peer`(peer.rs:500-532)는 "한 유저가 이 sfud에 대해 갖는 모든 것"이다. 필드를 성격별로 묶으면:

**신원(불변)**: `user_id`, `participant_type`(user/recorder), `created_at`, `conn_mode`(TwoPc/OnePc — 모드 전환은 필드 변경이 아니라 Peer 재생성. "불변이어야 할 것은 애초에 불변으로"의 전형, peer.rs:506-509).

**방 스코프(2벌)**: `rooms: Mutex<HashSet<RoomId>>` = "입장한 방"(presence), `sub_rooms: ArcSwap<HashSet<RoomId>>` = "받을 방"(MCPTT Affiliated, N방 청취). 발언 방은 따로 `publish.pub_room: ArcSwap<Option<RoomId>>` 1개(1방 발언). 왜 rooms는 Mutex이고 sub_rooms는 ArcSwap인가 — **sub_rooms는 fan-out 핫패스가 읽는다**(수신 대상 판정). 핫패스가 읽는 것은 lock-free, 시그널링만 만지는 것은 Mutex로 충분하다는 규율이 필드 단위로 적용된 것.

**생존(atomic)**: `last_seen`(heartbeat), `phase: AtomicU8`(PeerState), `suspect_since`. reaper가 CAS로만 천이시킨다(§3.8).

**PC쌍 자산**: `publish: PublishContext` / `subscribe: SubscribeContext`. 각각 `MediaSession`(ufrag/ice_pwd/latch 주소/SRTP 컨텍스트 in·out/`media_state: AtomicU8`)을 품는다. SRTP 키 설치가 끝나면 `media_state`를 Release 순서로 Ready 게시(peer.rs:213-224) — 핫패스는 이 atomic 하나만 Acquire로 읽고 "이 PC로 보내도 되는가"를 판단한다.

`PublishContext`(peer.rs:303-336)에서 눈여겨볼 것:
- **extmap ID 5종이 전부 `AtomicU8`** (twcc/rid/repair_rid/mid/audio_level): SDP 협상 결과(콜드패스 쓰기)를 패킷 파싱(핫패스 읽기)이 참조하는 전형적 자리라 atomic.
- `audio_mid: ArcSwap<Option<Arc<str>>>`: RTP-first 발견에서 "이 MID는 audio다"를 race 없이 알기 위한 안전망.
- `pub_room`: 발언 방. 외부에서 직접 만지지 못하고 `peer.publish_room()` 단일 헬퍼로만 읽는다(캡슐화 규율).
- `tracks: ArcSwap<PublisherTrackIndex>` / `streams: ArcSwap<Vec<Arc<PublisherStream>>>`: 발행 자산 2계층의 홈.

`SubscribeContext`(peer.rs:395-417)에서 눈여겨볼 것:
- `egress_tx/egress_rx`: 송신 전용 tokio task로 패킷을 넘기는 mpsc 채널. `egress_spawn_guard: AtomicBool` CAS로 egress task가 정확히 1번만 뜬다(peer.rs:399).
- `mid_pool: Mutex<MidPool>`: 서버 주도 mid 할당(다음 번호 + kind별 재활용 풀 — audio가 쓰던 m-line을 video에 재활용하면 브라우저가 깨지므로 풀을 분리). 1PC 모드는 `with_base(32)`로 클라 pub mid(0..P)와 번호대를 분리.
- `downlink: DownlinkController` / `bwe: DownlinkBwe`: 자동 레이어 전환의 판단 기관이 **구독자 transport 단위**로 여기 사는 이유 — 병목은 "그 구독자의 다운링크"이지 방이나 트랙이 아니기 때문(제5장).
- `streams: ArcSwap<SubscriberStreamIndex>`: 수신 배관의 홈.

**[진단 — peer.rs 응집도]** 1,619줄은 크지만 내부는 "Peer + 그 부속 타입 6종(MediaSession/MidPool/DcState/두 Context/MediaState)"으로, 전부 Peer의 신체 기관이라 응집도는 정상이다. 다만 `rooms`(Mutex)와 `sub_rooms`(ArcSwap)가 개념상 겹치는 집합을 두 벌 들고 있는 것(peer.rs:512-516), 그리고 `PeerMap.by_room_subscriber`가 sub_rooms와 사실상 같은 정보의 역인덱스라는 것(peer_map.rs:19-21, 주석이 스스로 "이중 관리" 인정)은 상태 정합을 join/leave/SCOPE 핸들러의 규율에 맡기고 있는 지점이다. 현재는 갱신 진입점이 `sync_scope_on_join/leave`(peer.rs:636-651)와 `attach_to/detach_from_room`(peer_map.rs:207-220)으로 집중돼 있어 통제되지만, 새 스코프 op를 추가하는 사람이 세 자리 중 한 곳을 빠뜨리는 실수가 이 구조의 대표 함정이다.

### 3.4 2계층 미디어 모델 — 논리 Stream과 물리 Track

**왜 두 층인가.** 브라우저의 세계에는 `MediaStream`(카메라 하나, 화면공유 하나 같은 "소스")과 `MediaStreamTrack`(그 소스의 실제 트랙)이 있다. simulcast를 켜면 한 카메라가 고화질(h)/저화질(l) **두 개의 RTP 스트림(SSRC 2개)**으로 갈라진다. 이때 "카메라"라는 논리 정체성과 "SSRC 하나짜리 RTP 흐름"이라는 물리 실체가 1:2가 된다. 서버가 이 구분을 안 하면 — 실제로 과거에 겪었듯 — mute가 h에만 걸리고 l은 새거나, 화면공유 키프레임 요청이 카메라를 오염시키는 류의 버그가 나온다.

그래서:

| | `PublisherStream` (논리) | `PublisherTrack` (물리) |
|---|---|---|
| 클라 대응물 | MediaStream (camera/screen 단위) | MediaStreamTrack (RTP 흐름 1개) |
| 개수 | source당 1 | non-sim=1, simulcast=h/l 2 |
| 소유 식별자 | **track_id**(시그널링 키, 불투명 `{user}_{ssrc:x}`), **vssrc**(simulcast 가상 SSRC), **mid**, codec/PT 메타 (publisher_stream.rs:40-61) | **실 ssrc**, rtx_ssrc/repair_for, **rid**("h"/"l") (publisher_track.rs:295-328) |
| 소유 상태 | PLI 상태(pli_state — source 단위로 내려 camera↔screen 키프레임 오염 차단), FullSim fan-out 구독자 목록 | RtpCache(NACK 재전송 캐시), NackGenerator, RR 통계, 파이프라인 카운터, duplex(AtomicU8 — hot-swap 가능) |

**식별자 배치가 곧 설계다.** track_id와 vssrc를 논리 Stream이 소유하기 때문에, simulcast에서 물리 Track이 placeholder→실 SSRC로 분화·교체돼도(RTP-first discovery) 클라가 아는 track_id와 구독자가 받는 egress SSRC(vssrc)는 흔들리지 않는다. 이것이 "publisher 메타 Stream 단일소유(I1~I5)"의 실체이고, placeholder sentinel 시절 검은 화면 사고의 재발 방지 구조다. Track은 track_id를 `OnceLock`으로 1회 복사만 보유한다(publisher_track.rs:301-305) — 발급 권위는 Stream, Track이 들고 있는 건 Stream이 먼저 죽어도 로그·통계가 이름을 잃지 않게 하는 사본이다.

Track에서 codec/PT 같은 intent 메타를 물으면 내부적으로 `self.stream()` Weak를 upgrade해 Stream에 위임한다(publisher_track.rs:449-462) — 메타의 단일출처를 지키면서 호출부 편의만 제공하는 위임이지, 상태 복제가 아니다.

### 3.5 인덱스 — 패킷이 주인을 O(1)에 찾는 법

패킷은 초당 수천 개 오는데 매번 "전 참가자의 전 트랙을 뒤지기"는 불가능하다. 세 종류의 O(1) 인덱스가 있고, 갱신 방식이 두 부류로 나뉜다.

**RCU 부류 (ArcSwap — 읽기 무제한, 쓰기는 통째 교체)**:
- `PublisherTrackIndex`(publisher_track_index.rs:33-43): `by_ssrc`(수신 RTP 매칭) + `by_rtx_ssrc`(재전송 스트림 → 원본 역인덱스) + `ordered`. 쓰기는 `with_added/with_removed/with_rtx_learned`가 **새 인덱스를 만들어 반환**하고 호출자가 `store()`로 통째 교체(76-109행). 읽기(`tracks.load()`)는 락 없이 ~4ns.
- `SubscriberStreamIndex`(subscriber_stream_index.rs:32-41): `by_egress_ssrc`(수신 RTCP·NACK 매칭) + `by_mid`(SUBSCRIBE_LAYER op) + `ordered`. 동일 패턴.

트랙 추가/제거는 분당 몇 번, 패킷 조회는 초당 수천 번 — 읽기:쓰기 비율이 극단적으로 읽기 쪽이라 RCU가 정확히 맞는 자리다.

**DashMap 부류 (내부 샤드 락 — 읽기도 쓰기도 잦은 곳)**:
- `PeerMap`의 4인덱스: `by_user`(시그널링), `by_ufrag`(STUN 콜드패스), `by_addr`(SRTP 핫패스 — 패킷의 소스 주소로 Peer를 찾는 첫 관문), `by_room_subscriber`(방별 구독자 — fan-out 대상 수집이 방 순회 없이 user 단위 O(1)).

by_user의 키가 user_id인 것은 재접속(take-over) 시 새 Peer로 자연 교체되게 하기 위함이고(peer_map.rs:23-24), ufrag/addr 인덱스의 값이 `(Arc<Peer>, PcType)` 쌍인 것은 publish PC와 subscribe PC를 같은 유저의 다른 문으로 구별하기 위함이다.

### 3.6 fan-out 방향 역전 — 이 코드베이스에서 가장 중요한 한 수

**옛 방식(폐기)**: RTP가 도착하면 "이 트랙을 구독 중인 SubscriberStream을 vssrc로 역탐색"했다. 참가자×스트림에 비례하는 조회가 패킷마다 발생.

**현 방식**: 구독이 성립하는 순간(콜드패스) 구독자가 발행자의 `subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` 목록에 자기를 등록해 둔다. 패킷이 오면 발행자는 **자기 목록을 그냥 순회**한다. 조회가 사라지고, vssrc는 "라우팅 키"에서 "등록 때 복사해 두는 값"으로 강등됐다.

등록(`attach_subscriber`)은 Track/Stream/Slot 세 곳이 동형 로직이다(publisher_track.rs:683-711, publisher_stream.rs:126-152, slot.rs:200-223): 현재 Vec을 훑으며 ① 같은 구독자가 이미 살아 있으면 중복 등록 안 함(멱등 — JOIN/SYNC가 몇 번 반복돼도 목록이 불지 않음, 회귀 테스트 publisher_track.rs:1253-1269), ② 죽은 Weak는 버림(**등록이 곧 청소** — 별도 detach 경로가 없다), ③ 새 Vec을 store.

순회(`broadcast`, publisher_track.rs:730-792)는 패킷마다: Weak upgrade 실패 skip → 자기 자신 skip → 대상 방의 RoomMember 조회 → `is_subscribe_ready()` 게이트 → `forward()`.

그리고 **분기 3로**(fanout, publisher_track.rs:900-953) — 트랙의 성격(`track_type()`)이 어느 구독자 목록을 순회할지 정한다:
- **FullNonSim**(일반 회의) → 물리 `Track.subscribers`
- **FullSim**(simulcast) → 논리 `Stream.subscribers` (물리가 아닌 논리 소유인 이유: 구독 성립 시점에 l 트랙이 아직 분화 전이면 물리 목록엔 등록할 곳이 없어 배관이 끊긴다 — 0709 런타임 레이어 전환 GAP의 처방으로 논리 소유로 올렸다, publisher_track.rs:920-923)
- **HalfNonSim**(PTT) → 방 `Slot.subscribers` (개인 배관이 아니라 방의 가상 채널 — 제6장)

`AttachTarget` enum(Track/Stream/Slot/None, slot.rs:240-246)이 "트랙이면서 슬롯" 같은 불가능 조합을 타입으로 차단한다.

### 3.7 상태 기계 3벌 — 무엇이 "살아 있음"인가

상태가 하나의 거대 enum이 아니라 **관심사별로 3벌**로 쪼개져 있다(state.rs).

- **PeerState**(연결 생존): Alive(0) → Suspect(1, 15s 무응답) → Zombie(2, 20s → 삭제). 천이는 reaper만, CAS로(peer_map.rs:261-311).
- **PublishState**(발행 트랙): Created(0) → Intended(1, PUBLISH_TRACKS 수신) → Active(2, 첫 RTP). "클라가 보내겠다고 했는가"와 "실제로 오는가"의 구분.
- **SubscribeState**(수신 배관): Created(0) → Active(1, TRACKS_READY). Intended가 없는 이유: 구독은 등록 자체가 의도 표명이라 중간 단계가 무의미(state.rs:112).

세 벌 모두 `AtomicU8` + `#[repr(u8)]`로 저장하고, 천이 진입점이 각 1곳(`set_phase_state`)이라 상태 변경의 감사 추적이 쉽다. 천이 시 hooks(제8장)로 agg-log가 남는다.

### 3.8 생명주기 — 태어나서 죽기까지

**입장**: `PeerMap::get_or_create_with_creds`(Peer 생성+ICE 자격 발급, peer_map.rs:64-90) → `Peer::join_room`(rooms 추가 + sub_rooms 동기, peer.rs:613-619) → `Room::add_participant`(RoomMember 명찰, 정원 검사, room.rs:136-154) → ufrag 등록 → (미디어가 실제 붙으면) STUN latch로 by_addr 등록 + SRTP 키 설치 → Ready.

**발행(2단)**: ① PUBLISH_TRACKS 시그널 → `register_stream`(논리 Stream 생성, track_id/vssrc 발급, peer.rs:767-800). ② 첫 RTP 도착 → `add_publisher_track` → 기존 SSRC면 hot-swap(Arc 보존), 신규면 소속 Stream을 찾아 물리 Track 생성·결합(peer.rs:854-881, publisher_track.rs:611-668). **소속 Stream이 없으면 RTP를 버린다** — "고아 물리 트랙 금지" 불변식. 시그널링이 먼저, 미디어가 나중이라는 순서 계약이 코드로 강제된 것.

**구독**: `collect_subscribe_tracks`(제2장)가 mid 할당 → `add_subscriber_stream`(멱등, peer.rs:1090-1123) → 발행자 쪽 목록에 `attach_subscriber`.

**퇴장**: `leave_room`(pub_room이 그 방이었으면 자동 해제 + floor release cascade) → 구독 배관 회수 `release_subscribe_track`(peer.rs:1069-1082)은 **mid_map 제거 → 인덱스 제거 → mid_pool 반납** 순서가 고정 — 순서를 바꾸면 재입장 시 회수 안 된 mid가 재발급되는 버그가 있었다(peer.rs:1059-1066, 회귀 테스트 동반).

**좀비 수확**(reap_zombies, peer_map.rs:241-315): 5초마다 by_user 스냅샷을 뜨고(장기 락 회피) user 단위로 last_seen 검사. 20s 초과면: 전 방 remove_participant → PLI burst abort → ufrag/addr 등록 해제 → by_user 제거. 이후는 Rust 소유권이 일한다 — Peer Arc가 떨어지면 Context→Stream→Track이 연쇄 drop되고, 발행자들 목록에 남은 Weak는 저절로 죽은 포인터가 된다. **파괴에 "전 자료구조 순회 청소"가 없다.** 소유 트리가 올바르기 때문에 가능한 절약이다.

### 3.9 보조 기관들

- **SubscriberGate**(subscriber_gate.rs): 새 video 트랙이 광고됐지만 구독자의 SDP 재협상이 아직일 때, 키프레임이 허공에 버려지는 걸 막는 일시정지 밸브. 핫패스는 `paused: AtomicBool` 하나만 Acquire로 읽는다(70-86행). 사유(`PauseReason::TrackDiscovery/LayerSwitch`)는 Mutex지만 진단용 콜드패스에서만 접촉. 5s 타임아웃 자동 해제 내장, resume은 `swap`으로 "정말 멈춰 있었는가"를 회수해 PLI 필요 여부를 알린다. 게이트는 Full video에만 적용 — PTT는 floor가 그 역할을 대신한다(subscriber_stream.rs:433-448).
- **PliGovernor**(pli_governor.rs): 한때 "PLI 보냈으니 키프레임이 왔는지"까지 추적하는 인과 기계였으나, 오탐으로 화면을 얼리는 부작용 끝에 **시간 throttle 하나로 감량**됐다(5-18행). 레이어별 `last_pli_sent_at`만 판단에 쓰고, 나머지는 진단 기록. "안전장치가 사고를 내면 안전장치를 단순하게" — 이 코드베이스의 성숙한 결정 중 하나.
- **SpeakerTracker**(speaker_tracker.rs): RFC 6464 audio-level 확장을 EWMA로 평활해 active speaker를 뽑는다. 방 단위 `Mutex<SpeakerTracker>` — full-duplex 회의 전용이고 주기 태스크(제8장)만 만지므로 Mutex로 충분한 자리.

### 3.10 [진단] 도메인 모델

**강점 (구조가 버그를 막는 지점들)**
1. **소유 트리의 정직함** — Arc는 아래로만, 역참조는 전부 Weak. 파괴가 소유권 연쇄로 끝나고 수동 청소 코드가 없다. 누수·이중해제 부류의 버그가 설계로 봉쇄됨.
2. **핫패스 접촉 상태의 프리미티브 규율** — 핫패스가 읽는 것(sub_rooms, media_state, extmap ID, gate.paused, 인덱스)은 예외 없이 ArcSwap/Atomic, 시그널링 전용은 Mutex. 어떤 필드가 어느 온도인지 타입만 봐도 안다.
3. **식별 계층 분리의 완성도** — track_id/vssrc(논리) vs ssrc/rid(물리) 소유 분리가 simulcast 분화·화자 전환에서 클라 관측 정체성을 보존한다. 최근 자동 레이어 전환(제5장)이 큰 개조 없이 얹힌 것이 이 토대의 방증.
4. **멱등성의 일관 적용** — attach_subscriber, add_subscriber_stream, ROOM_CREATE 등 재시도·재동기화가 잦은 진입점이 전부 멱등. 분산 시그널링의 현실(중복 전달)에 맞는 방어.

**리스크·냄새 (우선순위순)**
1. **PublisherTrack 2중 Arc 소유** — `PublishContext.tracks`(색인)와 `PublisherStream.tracks`(묶음) 양쪽이 소유(peer.rs:331, publisher_stream.rs:65). 제거 시 두 곳을 다 정리해야 하며, 한쪽 누락 시 트랙이 유령 생존한다. 현재는 `remove_publisher_track`(peer.rs:899-910) 단일 진입으로 통제되지만, 구조적으론 "색인이 Arc 대신 Weak를 들거나, 소유를 Stream 한쪽으로" 정리할 여지가 있다.
2. **sub_rooms ↔ by_room_subscriber 이중 장부** — 같은 사실("누가 어느 방을 구독하나")의 정방향/역방향 두 벌. 주석이 스스로 인정(peer_map.rs:19-21). 갱신 진입점 집중으로 완화 중이나, 정합 검증(디버그 assert나 admin 대사)이 없다.
3. **defensive fallback의 침묵** — FullSim인데 forwarder가 None이면 조용히 passthrough(subscriber_stream.rs:574-583). "설계상 불가"를 런타임 방어로 때우면 계약 위반이 증상 없이 흐른다. 카운터 하나라도 달아 관측 가능하게 할 자리.
4. **잔재·미배선 필드** — `egress_ssrc: AtomicU32`(주석 스스로 "u32 환원 후보" 자백, subscriber_stream.rs:288), `rec`/`speaker_enabled`(항상 false/미배선, room.rs:60-66). 0703 감사에서 "보존 판단"된 항목들이나, 분기마다 재확인 비용을 낸다.
5. **콜드패스 선형 탐색** — `find_publisher_track_by_vssrc`(room.rs:212-229, 참가자×스트림), `find_stream_by_track_id`(peer.rs:753-761, 선형). 핫패스 금지 주석은 있으나 admin/PLI 경로가 대형 방에서 반복 호출하면 비용이 드러난다. 규모 확장 시 재방문 목록.
6. **SubscribeState 천이 가드 부재** — 같은 상태로의 재천이도 hook을 태운다(subscriber_stream.rs:375-388). N방 청취에서 의도된 면이 있으나 hook 소비자(agg-log) 입장에선 중복 이벤트다.

---

## 제4장. 미디어 핫패스 — UDP 패킷 하나의 일생

> 대상: `transport/` 17파일 ~6,600줄 + rewriter 계열. 초당 수천 번 도는 경로이므로, 이 장은 "패킷 하나를 손에 쥐고 끝까지 따라가는" 방식으로 쓴다.

### 4.1 쉬운 그림 먼저 — 한 소켓 위의 세 가지 언어

WebRTC 미디어는 UDP 포트 하나 위에 세 종류의 패킷이 섞여 온다: **STUN**(주소 확인 — "너 거기 있니?"), **DTLS**(암호 키 합의), **SRTP/SRTCP**(암호화된 미디어와 리포트). 다행히 첫 바이트 범위가 서로 겹치지 않아, 서버는 첫 바이트만 보고 갈라낸다(demux.rs:20-31):

```
0x00~0x03 → STUN    0x14~0x3F → DTLS    0x80~0xBF → SRTP/SRTCP    그 외 → 버림
```

STUN·DTLS는 연결 수립 때만 오는 **콜드패스**, SRTP가 **핫패스**다. 이 장의 주인공은 SRTP 미디어 패킷이다.

### 4.2 연결 수립 콜드패스 — STUN latch와 DTLS

미디어가 흐르기 전에 두 절차가 선행된다.

**STUN(udp/mod.rs:354-429)**: 클라의 BINDING_REQUEST에서 ufrag를 뽑아 `peer_map.find_by_ufrag`로 주인을 찾고, **그 순간의 소스 주소를 by_addr 인덱스에 "래치(latch)"**한다. 이후 그 주소에서 오는 모든 패킷은 이 Peer 것이다 — SDP 후보 교환 없이 주소를 배우는 ICE-lite 서버의 핵심 동작. HMAC(ice_pwd) 검증 후 응답. USE-CANDIDATE가 붙어 있고 DTLS 세션이 없으면 DTLS 핸드셰이크를 시작한다.

**ICE 주소 이동(migration)**: 클라의 네트워크가 바뀌면(Wi-Fi→LTE) 같은 ufrag로 새 주소에서 STUN이 온다. 서버는 latch를 갱신하고, DTLS/SCTP가 쓰는 `DemuxConn.peer_addr: Arc<RwLock<SocketAddr>>`를 write 한 번으로 바꿔치운다(udp/mod.rs:106-114, demux_conn.rs:28). ICE restart 없이 주소만 미끄러지는 표준(Pion/mediasoup 동형) 방식.

**DTLS(udp/mod.rs:456-536)**: 서버는 passive. 핸드셰이크(10s 타임아웃) 후 `export_keying_material`로 60바이트를 뽑아 client/server 키·salt 4벌로 쪼개 SRTP 컨텍스트에 설치하고(dtls.rs:104-121), `media_state=Ready`를 Release 게시. Subscribe PC(1PC면 Publish PC)가 Ready가 되는 순간 **그 구독자 전용 egress task**가 뜨고(hooks/media.rs), Publish PC라면 SCTP(DataChannel) 루프도 뜬다.

### 4.3 핫패스 정방향 — 발행자의 RTP 패킷이 구독자에게 가기까지

이제 발행자의 오디오/비디오 패킷 하나를 따라간다. 단계마다 (함수, 파일:줄)을 붙인다.

**① 수신·분류** — `UdpTransport::run`(udp/mod.rs:202)이 `recv_from` → `Bytes::copy_from_slice`(첫 복사, mod.rs:238) → demux → SRTP면 `handle_srtp`(ingress.rs:42).

**② 주인 찾기** — `peer_map.find_by_addr(remote)` DashMap O(1)로 (Peer, PC종류)를 얻는다(ingress.rs:43). `last_seen` 갱신(좀비 reaper의 생존 신호가 바로 이것). PC가 Subscribe면 구독자발 RTCP 처리(§4.5)로, Publish면 계속.

**③ RTP/RTCP 구분·복호** — byte[1] 하위 7비트가 72~79면 RTCP. RTP면 `inbound_srtp.lock()` 후 복호(ingress.rs:87-114 → srtp.rs:48). 이 Mutex가 핫패스의 첫 락인데, 같은 5-tuple은 커널이 같은 worker로 보내므로 실경합은 낮다. 락 대기 시간을 `lock_wait` TimingStat으로 계측한다 — "락을 못 없애면 관측한다"는 태도.

**④ 스트림 판별** — `resolve_stream_kind`(ingress_publish.rs:223): 이 SSRC가 누구의 무슨 트랙인가. 4단 사다리 — ⑴ `by_ssrc` HashMap 히트(기존 트랙, 대부분 여기서 끝) ⑵ `by_rtx_ssrc`(재전송 스트림) ⑶ RTP 확장의 rid/repair-rid(simulcast 신규 분화) ⑷ rtx_pt/MID 매칭. 전부 실패하면 Unknown으로 버린다. **서버는 SDP를 안 읽는다** — extmap ID(atomic)와 RTP 헤더 확장만으로 런타임에 배운다(SDP-free의 실체).

**⑤ 트랙별 장부 기입** — 신규면 등록·통지, 기존이면: RR 통계 갱신(`rr_stats.lock().update` — 손실·지터 계산, RFC 3550), video면 `rtp_cache.store`(NACK 재전송용 사본, seq%1024 링버퍼) + `nack_generator.record`(손실 감지), audio면 speaker tracker, TWCC seq가 있으면 recorder 기록. phase를 Active로 swap(첫 패킷이 "정말 온다"의 증거).

**⑥ fan-out** — `track.fanout`(publisher_track.rs:812). 제3장의 3분기: PTT면 slot rewriter로 **1회 사전 재작성(prefan)** 후 slot 구독자 순회, simulcast면 논리 Stream 구독자 순회, 일반이면 물리 Track 구독자 순회. video 키프레임이 감지되면 PLI 상태에 "왔다"를 기록(재요청 중단 근거).

**⑦ 구독자별 재작성** — `SubscriberStream::forward`(subscriber_stream.rs:413). 구독자마다 `payload_base.to_vec()`으로 **자기 사본**을 뜨고(재작성이 in-place라 원본 보호 — N구독자면 N복사, §4.8), 성격별로: PTT는 prefan 결과에 PT만 정정, simulcast는 forwarder 락 안에서 레이어 매칭 후 `SimulcastRewriter.rewrite`, 일반은 무변조 통과. video면 gate 검사(atomic 1회)가 앞선다.

**⑧ egress 큐잉·송신** — `egress_tx.try_send(EgressPacket)`으로 구독자 전용 task에 넘긴다(용량 256, 넘치면 드롭 카운트). egress task(egress.rs:195)는 이 transport의 **유일한 송신자**라서: TWCC 스탬핑(v2, 제5장) → SR 통계 기입 → `outbound_srtp.lock()` 암호화(경합 없음 — 유일 소유자) → `send_to`. 발신 SRTP 락을 task 소유로 만든 것이 LiveKit식 경합 제거 설계다.

요약하면 락은 ③⑤⑦⑧의 국소 Mutex뿐이고, 조회는 전부 ArcSwap/DashMap O(1)이다. 패킷당 복사는 수신 1 + 복호 1 + (video면 캐시 1) + 구독자 N + 암호화 N.

### 4.4 되감기 기계 — rewriter의 단일 스칼라 offset

PTT와 simulcast의 공통 문제: **수신자는 SSRC 하나짜리 연속 스트림을 기대하는데, 실제 원천은 계속 바뀐다**(화자 교대, 레이어 전환). 그 간극을 메우는 것이 `RtpRewriter`(rtp_rewriter.rs)다.

원리는 세 줄로 요약된다:
1. 16bit seq/32bit ts를 **u64로 확장**해 wrap(65535→0 되돌이) 문제를 자료구조 차원에서 제거.
2. 출력 = 입력 + **offset 하나**(seq용, ts용 각 1개 스칼라). 원천이 바뀌면 "다음 키프레임에서 offset을 다시 계산"(`prepare_source_switch` → pending_keyframe).
3. 초기화 전 non-keyframe은 버린다(수신 디코더가 어차피 못 그림).

**왜 "하나"인가가 이 코드의 흉터다.** 과거엔 시점별 offset 지도(SnRangeMap)를 유지해 "옛 시점 seq도 정확히 역산"하려 했다. 그러나 발행자마다 독립인 16bit seq 공간이 수치상 충돌해 stale offset을 반환했고, egress seq가 역행(실측 15614→209)해 수신 지터버퍼가 스트림을 폐기 — PTT 오디오 절단 사고가 났다. 20260622에 단일 스칼라로 회귀했고, 폐기 근거가 실측치와 함께 주석에 박제됐다(rtp_rewriter.rs:87-93). **재도입 금지 구조.**

단일 스칼라의 대가는 "전환 경계의 옛 NACK을 정확히 역산 못 함"인데, 이는 **RTX gate**가 막는다: 전환~키프레임 사이엔 gate가 닫혀 NACK 응답 자체를 거부한다(`is_in_rtx_gate_region`, NACK 경로 배선 완료 — 0703 S1 후속 b25e9b9). ⚠️ 단 rtp_rewriter.rs:22-24 주석은 아직 "미배선, 결재 대기"로 낡아 있다 — 코드가 주석보다 앞선 상태(제9장 문서 정합 목록).

PLI 자가치유도 여기 있다: rewrite가 키프레임을 기다리며 버리는 동안 2초 간격으로 "PLI 다시 보내라" 신호를 올린다(needs_pli_retry) — 첫 PLI가 유실돼도 화면이 영구히 안 뜨는 일이 없게.

### 4.5 역방향 — RTCP 리포트의 종단과 번역

RTCP에서 이 서버의 정체성이 가장 뚜렷하다: **SFU는 릴레이가 아니라 두 독립 RTP 세션의 종단점**이다(rtcp_terminator.rs:5-11).

- **RR(수신 리포트)**: 발행자→서버 구간의 수신자는 서버다. 서버가 매 RTP마다 통계를 쌓고(RrStats — 손실·지터·확장 seq, RFC 3550 A.1/A.8, probation 포함) 1초마다 **자기 RR을 만들어** 발행자에게 보낸다(egress.rs:290-363). 구독자가 보낸 RR은 서버가 **먹고 끝낸다**(발행자 릴레이 금지) — 안 그러면 발행자가 "저 먼 구독자의 사정"으로 자기 인코딩을 조절하는 오작동이 난다.
- **SR(송신 리포트)**: 서버가 자기 시계로 SR을 만들면 안 된다 — 서버 NTP가 원본 미디어 소스와 안 맞아 수신 지터버퍼 지연 폭등(Janus PR #2007의 그 사고). 대신 발행자의 SR을 **번역 릴레이**한다(`translate_sr`): NTP는 원본 유지(립싱크 기준점), packet/octet count만 서버 egress 통계로 교체, PTT는 RTP ts를 slot rewriter의 동일 offset으로 변환(RTP와 SR이 자동 정합). SR 자가생성 코드는 test-only로 격리돼 있다.
- **NACK**: 두 방향이 완전히 다르다. ⑴ 서버→발행자: 서버의 NackGenerator가 수신 구멍을 감지해 100ms 주기로 NACK을 보낸다(손실 회복 요청자로서). ⑵ 구독자→서버: 구독자의 NACK을 받으면 서버가 rtp_cache에서 사본을 꺼내 **RTX 패킷**(RFC 4588 — RTX SSRC/PT, payload 앞 2바이트에 원본 seq)으로 직접 재전송한다(ingress_subscribe.rs:430-628). 발행자까지 안 간다. 안전판 3중: RTX gate(전환 경계 차단) + 캐시 미스 과반이면 NACK 억제 5초 + PLI 승격(NACK_ESC — "재전송으론 못 살린다, 새 키프레임으로") + 3초당 200패킷 RTX 예산.
- **PLI(키프레임 요청)**: 구독자 PLI는 발행자로 가야 하는 유일한 피드백인데, 무제한 통과시키면 발행자 인코더가 키프레임만 찍는다. **PLI Governor**가 논리 Stream 단위·레이어별 시간 throttle(h 300ms/l 100ms)로 죽인다. simulcast에서는 구독자가 아는 vssrc를 **h 레이어 실 SSRC로 치환**해 보낸다(Chrome은 h PLI만 전 레이어 키프레임을 만든다 — 실측 기반). throttle 시 PSFB 블록만 걸러내는 필터는 정상 동작 확인(ingress_subscribe.rs:388 — PT 비교에 마스크 없음; 384-386 주석은 "마스크를 쓰면 안 되는 이유"의 방어 설명이다). 서버가 스스로 쏘는 PLI(`spawn_pli_burst` — [0,200,500,1500]ms 버스트)는 GATE/NACK_ESC/RTP_GAP 등 인프라 사유면 Governor를 우회한다.
- **1PC 라우터**: 1PC 모드는 한 5-tuple로 SR(그 클라=발행자)과 RR/NACK/PLI(그 클라=구독자)가 섞여 온다. `route_onepc_rtcp`(ingress_rtcp.rs)가 패킷 단위로 분해해 각 평문 처리부로 보내고, 못 가른 것은 **카운터를 올리며 버린다**(`rtcp.onepc_unrouted` — 조용한 드롭 금지).

### 4.6 RTP 헤더 확장 — 서버가 읽고 쓰는 것

읽기 4종(one-byte form만, rtp_extension.rs): audio-level(RFC 6464 — active speaker), rid/repair-rid(simulcast 레이어 판별), mid(SSRC↔m-line 매핑). 쓰기는 단 1종 — egress의 TWCC seq 스탬핑(제5장). "읽기는 배우기 위해, 쓰기는 측정하기 위해"로 요약된다.

### 4.7 핫패스 규율 실사 — 원칙은 지켜지고 있는가

"핫패스 diff 0" 원칙(변경이 핫패스 비용을 늘리면 안 됨)의 관점에서 현 상태:

**지켜진 것**: 조회 전부 O(1)(주소→Peer, SSRC→Track, egress SSRC→SubscriberStream), 순회 목록 전부 ArcSwap load, 킬스위치 off 경로는 바이트 동일(auto_layer/trace 등), 관측은 atomic 카운터와 try_send(가득 차면 버림 — 관측이 미디어를 못 막음).

**남은 비용(정량)**: 패킷당 락 3~5회(복호 1, 통계 1~3, 암호화 1 — 전부 소유자가 사실상 단일이라 경합 낮음), 복사 2+N회(§4.3⑦), `SystemTime::now` 다중 호출(audio 경로 2회 — Instant 대비 비쌈), video 캐시 to_vec 1회.

### 4.8 [진단] 미디어 핫패스

**강점**
1. **SDP-free의 일관 관철** — 서버가 SDP 파서를 갖지 않고 RTP에서 전부 배운다. SDP 방언(브라우저별 차이) 이슈가 서버에서 구조적으로 사라졌고, 시그널링·미디어의 결합도가 낮다.
2. **종단자(terminator) 원칙의 정확한 구현** — RR 종단, SR 번역(NTP 불변), NACK 서버 흡수. 각 결정에 업계 사고 사례(Janus jb_delay)가 근거로 붙어 있다.
3. **회복 기계의 다층 방어** — NACK(정밀)→RTX gate(경계)→예산(폭주)→PLI 승격(포기 선언)의 사다리가 명시적. "재전송이 항상 정답은 아니다"를 아는 코드.
4. **경합 제거의 구조적 해법** — 구독자당 egress task가 발신 SRTP를 독점. 락을 "잘 잡는" 게 아니라 "잡을 일을 없앤" 설계.

**리스크·냄새 (우선순위순)**
1. **FullNonSim passthrough의 불필요 복사** — 재작성이 없는 일반 회의 경로도 구독자마다 `to_vec()`한다(subscriber_stream.rs:587). N명 방에서 패킷당 N할당. `Bytes`/`Arc<[u8]>` 공유로 없앨 수 있는 가장 굵은 최적화 후보이나, 핫패스 개조이므로 부하 실측과 함께 별 토픽으로.
2. **audio에도 상주하는 rtp_cache** — 트랙당 1024슬롯 캐시가 audio에도 항상 생성된다(publisher_track.rs:335-337). audio NACK/RTX는 실질 미사용 — 메모리와 store 비용이 공짜가 아니다. 0703 감사에서 주석만 정정된 항목의 실체 정리 후보.
3. **ROC 추정 1차 구현** — rewriter의 u64 확장이 "보수적 추정"(rtp_rewriter.rs:135-137)이라 극단적 재정렬·장기 wrap에서 오추정 여지. 현 트래픽 패턴에선 발현 안 했지만 Phase ② 보강이 명시된 미완.
4. **stale NACK 방어의 gate 단일 의존** — 단일 스칼라 선택의 구조적 귀결로, 전환 경계 정확성은 전적으로 RTX gate에 걸려 있다. gate 극성 시험은 있으나(0703), 화자 고속 교대 + NACK 폭주의 조합 시험은 실망 시험 백로그에 있어야 한다.
5. **`SystemTime::now` 중복 취득** — 패킷당 2~3회(ingress_publish.rs:154,174). 미세하지만 초당 수천 배수로 곱해지는 자리. 시각을 ①단계에서 1회 취득해 관통시키는 정리 여지.

---

## 제5장. 혼잡제어·적응 계층 — 구독자의 회선에 맞춰 화질을 승강하다

> 대상: `domain/downlink.rs`(772) · `bwe.rs`(291) · `gcc.rs`(532) · `transport/udp/auto_layer.rs`(293) · `twcc.rs`(1,142) + 배선 접점. 2026-07-09~11에 완결된 최신 계층으로, 기존 문서 공백이 가장 큰 영역이라 이 장을 가장 상세히 쓴다.

### 5.1 쉬운 그림 먼저 — 문제와 답의 뼈대

simulcast 발행자는 고화질 h(1.65Mbps)와 저화질 l(250kbps)을 동시에 올린다. 어느 구독자에게 어느 쪽을 줄지는 지금까지 클라 수동(SUBSCRIBE_LAYER)이었다. 이 계층은 그 판단을 서버가 자동으로 한다:

```
[신호 수집]  구독자 회선이 얼마나 버티는가?          ← v1: REMB / v2: TWCC+GCC
[판단]      내릴까(demote) 올릴까(promote)?          ← DownlinkController (v1/v2 공용)
[집행]      Forwarder에 목표 레이어 설정 + 키프레임 요청  ← 제4장 전환 기계 재사용
```

세 칸 중 **가운데와 오른쪽은 v1/v2가 완전히 같고, 왼쪽 신호원만 갈아 끼운다.** 이 "신호원 교체 아키텍처"가 이 계층의 최대 설계 결정이다.

운영 모드는 policy.toml 한 줄:

```toml
[media] auto_layer = "v2"   # off(수동만·비상 킬) | v1(REMB 후퇴처) | v2(TWCC 정식)
```

키 부재·오값이면 **off로 폴백**(기능은 명시 opt-in), 재기동으로만 전환. off일 때 핫패스는 현행과 바이트 동일이다.

### 5.2 판단 기관 — DownlinkController

**어디 사는가**: 구독자의 `SubscribeContext` 직속(peer.rs:405-412). 병목은 "그 구독자의 다운링크(transport)"이지 방·트랙이 아니므로, 판단 소유권을 transport 단위에 뒀다(D1). 수집(RTCP 경로가 atomic으로 기록)과 판단(1초 tick이 Mutex 안 순수함수 실행)이 분리돼 있고, 판단 결과는 `auto_cap: AtomicU8` 캐시로 게시돼 SUBSCRIBE_LAYER 핸들러·admin이 락 없이 읽는다. tick 마지막에 캐시 동기화를 `Controller::tick` 안에 봉인해(0710 결함 2 수리) 진실↔캐시 불일치를 호출 계약이 아닌 코드로 막았다.

**demote(내리기) — 빠르고 민감하게.** 매초 4개 사유를 검사해 **2연속 성립(~2초)**이면 내린다:

| 사유 | 조건 | 뜻 |
|---|---|---|
| remb | 추정 대역 < 1.2 × 현재 수요 | 회선이 수요+20% 여유를 못 준다 |
| loss | RR 손실률 8% 초과가 2연속 | 실제로 패킷이 깨지고 있다 |
| nack | 재전송 요청 20개/s 초과 | 수신자가 구멍을 호소한다 |
| drop | egress 큐 드롭 발생 | 서버 송신단부터 밀린다 |

**promote(올리기) — 느리고 의심 많게.** Low에서 손실<2%·NACK<1/s·드롭 0의 "깨끗한 상태"가 **backoff 창(초기 15s)** 동안 지속돼야 시도한다. 올렸다가 5초 안에 다시 무너지면(재-demote) backoff가 2배(15→30→60s cap)로 늘어 다음 시도가 신중해지고, 5초를 버티면 초기값으로 복귀한다. 이 **비대칭 히스테리시스**(내림 2s vs 올림 15s+)가 h↔l 진동(flapping)을 막는 뼈대다.

**grace — promote 직후의 오판 방지(0710 결함 1).** 올리는 순간 REMB는 아직 낮은 값에서 램프 중이라, 그대로 두면 "remb 부족" 사유로 즉시 재강등된다(실측: 60초 중 2초만 High). 그래서 promote 후 10초는 **remb 사유만** 억제한다 — loss/nack/drop은 진짜 붕괴 신호라 grace 없이 유지. grace(10s) > 재-demote 창(5s)이므로 remb 사유는 배증 창에 원리적으로 못 들어온다(downlink.rs:178-184) — 단 이 부등식이 두 상수의 암묵 계약이라는 점은 §5.7에서.

신호 신선도도 사유별 시계가 다르다: REMB 5s, loss 6s(RR 실측 주기 p99 2.1s의 2배+, 0710 결함 3 — stale loss streak이 박제돼 진동하던 것의 수리). 만료된 신호는 "없음"으로 취급한다.

### 5.3 v1 신호원 — REMB (수신자의 감)

REMB는 수신 브라우저가 "나 이 정도 받을 수 있어요"라고 보내는 추정치다. 경로: 구독자 RTCP(PSFB fmt15) 도착 → `collect_downlink_signals`(ingress_subscribe.rs:649-678)가 REMB bps와 RR worst 손실률을 파싱 → Controller의 atomic에 기록 → tick이 읽는다. 1PC 모드는 SR에 내장된 수신 블록에서도 loss를 줍는다(ingress_rtcp.rs:202-220).

v1의 한계는 둘: ① REMB는 수신자 종단 시계 기반 추정이라 잡음이 크고, ② **Low를 받는 동안 REMB는 항상 낮아서** "올려도 되는지"를 알 방법이 없다. 그래서 v1의 promote는 "깨끗하면 일단 올려 보고, 무너지면 backoff"라는 시도-후퇴다 — 사용자 화면에 순간 열화가 노출될 수 있는 구조적 타협.

### 5.4 v2 신호원 — TWCC send-side BWE (서버의 실측)

v2는 그 한계를 뒤집는다: **서버가 자기 hop(서버→구독자)의 송신↔도착을 직접 실측**한다.

**① 스탬핑(송신 기록)** — egress task가 나가는 모든 RTP(RTX 포함)에 transport-wide seq를 찍는다. `ensure_twcc_seq`(twcc.rs:558-613)는 3분기: 발행자가 이미 넣은 twcc 확장이 있으면 **값을 교체**(원본 seq를 통과시키면 발행자 시계로 서버 hop을 재는 시계 오염 — 실측으로 확인된 함정), BEDE 확장은 있는데 원소가 없으면 1워드 삽입, 확장 자체가 없으면(서버 자작 프로브) 헤더째 신설. 동시에 `SendRecord` 링버퍼(8192)에 (seq, 송신 시각, 크기)를 남긴다.

**② 피드백** — 구독자 Chrome이 "seq n번은 t에 도착, n+1은 유실…"을 TWCC FB(RTPFB fmt15)로 회신한다. 서버가 유일하게 클라 SDP를 모르므로 "협상됐는가"는 **FB가 실제로 왔는가로 자기실증**(latch)한다. 재미있는 실측: 스탬핑만 켜도 Chrome이 REMB 송신을 끊는다 — 그래서 스탬핑·FB소비·신호교체·프로브가 **한 게이트(bwe_v2_enabled)로 원자 개폐**돼야 했다(부분 개방이 v1을 굶기는 사고 방지, config.rs:152-154). 클라 쪽도 sub m-line에만 `transport-cc`를 협상한다(codecs_sub — pub 방향 무접촉).

**③ 추정(GccEstimator, gcc.rs)** — libwebrtc GCC의 이식: FB의 (송신시각, 도착시각) 쌍을 burst 그룹으로 묶고 → 그룹 간 **지연 변화 기울기**를 최소자승 trendline으로 추정 → 적응 임계와 비교해 Overusing/Normal/Underusing 판정 → AIMD(혼잡이면 ×0.85 감산, 평시면 가산/승산 증가). 손실 기반 추정과 min 합성하고, 송신량이 추정치의 50% 미만이면(ALR — 애초에 안 보내는 중) 추정을 동결해 "적게 보내니 추정이 무너지는" 자기붕괴를 막는다. 전부 순수함수(시계 주입)라 합성 시나리오 단위시험 9종이 붙어 있다. 상수는 전량 libwebrtc 이식값(BWE_AIMD_BETA=0.85=kDefaultBackoffFactor 등, config.rs:158-204에 출처 주석).

**④ 프로브 — promote를 "화면 무접촉으로" 검증.** v2의 백미. Low에서 clean 창을 통과하면 바로 올리지 않고, **RTX 패딩 패킷**(ts=0, 미디어 타임라인 무접촉, 마지막 바이트=패딩 길이)을 h 수요의 1.35배 속도로 2.5초간 20ms 간격 페이싱 송출한다(burst 금지 — 0624 audio 밀림 교훈). 이 가짜 트래픽도 스탬핑을 통과하므로 estimator가 실측 상향하고, 판정창(4s) 안에 추정치가 1.2×h수요에 도달하면 그때 promote한다. Overusing 감지·egress 큐 포화 시 즉시 중단. 라이브 실측: 프로브 3회 수렴(312k→1.25M→1.63M→2.03M≥1.98M) 후 promote, 수신 무단절.

**폴백 경계**: v2 신호가 신선하지 않으면(FB 1초 이상 부재) tick이 자동으로 v1 REMB로 하강한다(auto_layer.rs:76-84). v2 죽음이 기능 죽음이 아니라 신호 품질 하락으로만 나타나는 설계.

### 5.5 집행 — 판단이 화면 전환이 되기까지

`run_downlink_tick`(auto_layer.rs, worker-0의 1초 RTCP 타이머에 편승)이 구독자·simulcast 스트림별로:

1. `effective = apply_cap(사용자 desired, auto cap)` — **min 합류**. 서버는 사용자의 수동 선택을 넘어서 올리지 않는다(cap=Low면 강등만, cap=High면 desired 그대로).
2. 전환 필요하고 **전환 중이 아니면**(target=None) `fwd.target = effective` 설정 + **target 레이어 rid의 실 SSRC로 PLI**. "h에 PLI하면 전 레이어 키프레임"이라는 통념은 실브라우저에서 깨졌다(l 키프레임이 안 옴 → 전환 영구 pending) — target-rid PLI가 실측 수리다(auto_layer.rs:255-256, mediasoup 동형).
3. 실제 스위치는 제4장 Forwarder의 키프레임 분기가 수행 — target 레이어의 키프레임이 도착하는 순간 current를 교체(무단절). target이 10초 넘게 안 풀리면 클리어(pending 상한).

같은 Forwarder Mutex를 쓰는 F4 in-band demote(발행자 h 업링크가 끊겼을 때 forward 경로가 직접 l로 강등 + PLI)와의 경합은 "**target이 서 있는 동안 tick 무개입**" 규칙 하나로 해소된다 — 락 순서 규약 없이 상태 기계 규칙으로 race를 없앤 사례.

관측·시험 배선: admin users 스냅샷에 downlink/bwe 필드(킬스위치 off면 필드 자체 부재), 0x3005 주입 훅은 REMB/loss를 **기록만** 하고 판단·집행은 정규 tick이 하게 해 시험조차 실경로를 태운다(off면 조용한 no-op가 아니라 거부).

### 5.6 v1/v2 공존의 코드 배치

| | v1 | v2 |
|---|---|---|
| 신호원 | DownlinkController의 remb/loss atomic | DownlinkBwe.signal_bps(estimator) |
| 판단 | `policy_tick` **공용** (v2는 remb 자리에 추정치 주입) | 동일 |
| promote 방식 | clean 창 후 직행(시도-후퇴) | 프로브 검증 후(probe_capable) |
| 집행·관측 | 공용 | 공용 |

`SubscribeContext`에 downlink(v1)와 bwe(v2)가 **항상 나란히 생성**돼 있고, tick이 매초 "v2 신호가 신선한가"로 provider를 고른다. v2가 v1을 대체하는 게 아니라 **끼워 넣는** 구조라, v2 신규 코드에 이상이 생겨도 v1 후퇴가 배포 설정 한 줄이다.

### 5.7 [진단] 혼잡제어·적응 계층

**강점**
1. **신호원 교체 아키텍처** — 판단·집행 불변에 신호만 갈아 끼우는 구조 덕에 v2가 서버 4파일 신설로 끝났고, 3단 후퇴 사다리(v2→v1→off)가 공짜로 생겼다. 이 계층의 가장 잘한 결정.
2. **순수함수 정책** — policy_tick과 GccEstimator가 시계·신호를 인자로 받아 합성 시나리오 시험이 가능하다(각 13종/9종). 혼잡제어는 재현이 지옥인 분야인데 판단부만은 결정론적으로 시험된다.
3. **실측 주도 개발의 흔적** — target-rid PLI, 스탬핑↔REMB 중단 인과, grace 필요성, 프로브 페이싱 전부 라이브/dummynet 실측에서 역산됐고 근거가 주석에 좌표로 박제돼 있다.
4. **opt-in과 원자 게이트** — 부분 개방이 기존 기능을 굶기는 함정을 게이트 원자화로 봉쇄했고, off 경로 바이트 동일이 반복 검증됐다.

**리스크·냄새 (우선순위순)**
1. **GCC 이식 상수 미실측** — 전 상수가 "이식값으로 시작, netem 튜닝 별도"로 명시돼 있고(gcc.rs:5-6), AIMD 가산율·수렴 판정은 자칭 "간이"다. dummynet 1회 물증은 있으나 실망(진짜 무선망) 수렴 특성은 미확인 — 백로그의 실망 시험 묶음이 이 계층의 실질 완결 조건이다.
2. **GRACE>REDEMOTE_WINDOW 암묵 불변식** — 10s>5s 부등식이 "remb demote는 배증 없음" 논리의 전제인데, 두 상수는 독립 선언돼 있다. 한쪽만 튜닝하면 조용히 깨진다. `const_assert` 한 줄이면 봉인되는 자리.
3. **프로브 실패의 침묵** — RTX 미협상·publisher 부재면 프로브가 조용히 안 나가고, 정책은 판정창 만료→clean 창 재시작을 무한 반복한다(진전 없는 재시도). 로그는 있으나 카운터가 없어 admin에서 "v2인데 왜 안 올라가나"를 못 본다. 관측 카운터 1개 추가 후보.
4. **프로브가 발행자 RTX seq 공간 소비** — 패딩 seq를 `pub.publish.rtx_seq`에서 뽑는다(auto_layer.rs:229). RTX는 OSN이 별도라 이론상 무해하지만, 정상 RTX 재전송과 seq 공간을 공유하는 것의 수신측 영향(지터버퍼 통계 등)은 미검증.
5. **worker-0 직렬 tick 확장성** — 전 구독자 판단이 1초 tick 한 태스크에서 직렬 순회 + 스트림별 Forwarder lock. 구독자 수백까지는 무해하나 수천이면 tick 완주 압박. 제8장 worker-0 단일점과 같은 뿌리.
6. **drop 사유의 민감도** — egress 큐 드롭 1건×2연속이면 demote. NACK/RTX가 흡수 가능한 순간 backpressure에도 반응할 수 있다. 실망 시험에서 demote 사유 분포를 보고 임계 재조정할 자리.
7. **주석 표기 부채** — 옛 킬스위치 이름(`SIMULCAST_AUTO_LAYER`/`BWE_V2`)이 주석 다수에 잔존(실 게이트는 `auto_layer_enabled()`/`bwe_v2_enabled()`). 기능 무관하나 신규 독자를 헤매게 한다.

---

## 제6장. PTT/Floor 특화 계층 — 무전기를 WebRTC 위에 올리다

> 대상: `domain/floor*.rs` + `ptt_rewriter.rs` + `slot.rs` + `speaker_tracker.rs` + `datachannel/` 3파일 + `floor_ops.rs`/`scope_ops.rs` (~3,900줄). 이 시스템이 일반 SFU와 갈라지는 지점 — PTT가 부속이 아니라 1급 시민이다.

### 6.1 쉬운 그림 먼저 — 회의와 무전의 근본 차이

화상회의: 참가자 N명이 각자 트랙을 올리고, 수신자는 **사람 수만큼의 스트림**을 받는다.
무전(PTT): 한 순간 **한 명만** 말한다(발화권 중재). 수신자 입장에서 채널은 "지금 말하는 누군가"라는 **단일 스트림**이다.

이 차이를 서버는 두 기계로 구현한다:
- **FloorController** — "누가 말할 권리를 갖는가"의 중재자(방마다 1개).
- **Slot** — "말하는 사람이 누구든 수신자에겐 하나의 스트림으로 보이게" 하는 가상 채널(방마다 audio/video 각 1개, 고정 virtual SSRC).

그리고 제어 메시지(MBCP)는 시그널링 WS가 아니라 **DataChannel**로 오간다 — 발화권 응답은 밀리초가 체감 품질(PTT 반응성)이기 때문이다.

### 6.2 FloorController — 발화권 상태기계

상태는 단 둘: `Idle` | `Taken{speaker, priority, burst_start, last_ping, max_burst_ms}` (floor.rs:47-66). 복잡성은 상태 수가 아니라 천이 규칙에 있다:

- **요청(request)**: Idle이면 즉시 Granted. 이미 화자가 있으면 — ⑴ 요청자 우선순위가 **높으면 선점**(현 화자에게 Revoked{preempted}, 새 화자 Granted — 선점당한 화자는 3GPP 규격대로 큐에 안 넣음) ⑵ 아니면 **큐잉**(priority 내림차순→도착순 정렬, 최대 10명, 꽉 차면 Denied). 같은 화자의 재요청은 멱등.
- **해제(release)**: 화자 본인이면 Released 후 큐 선두에 자동 grant(`_try_grant_next`). 비화자면 큐 취소로 해석. Idle에 release가 오면 멱등 no-op.
- **타임아웃(check_timers, 2초 주기 태스크)**: **T2**(최대 발화 30초 초과 → Revoked) + **RTP liveness**(5초 무패킷 → "participant lost" Revoked). 클라 FLOOR_PING 프로토콜은 폐기됐고, 서버가 화자의 실제 RTP 도착 시각으로 **self-ping**한다(tasks.rs:60-72) — "살아 있다는 신호는 미디어 그 자체"라는 발상으로 wire 왕복을 없앤 것.
- **퇴장 cascade**: 방을 떠나면 화자든 대기자든 자동 정리.

모든 천이는 `Vec<FloorAction>`(Granted/Denied/Queued/Released/Revoked/QueueUpdated)을 반환하고, **부수효과는 하나도 안 일으킨다**. 상태기계는 순수하게, 방송·미디어 연동은 단일 진입점 `apply_floor_actions`(floor_broadcast.rs:75-214)가 전담 — DC 핸들러·WS 핸들러·타이머·퇴장 4경로가 같은 기계와 같은 방송 코드를 재사용한다. 액션 순서 계약(Released가 Granted보다 먼저)까지 단위시험 13종이 못 박는다.

큐 위치 변동은 TS 24.380 §6.3.4.4대로 **전 대기자에게 재통지**(QueueUpdated), 발화 지속시간은 Granted에 duration(30s)으로 실린다.

### 6.3 MBCP over DataChannel — 제어 wire

MBCP는 3GPP TS 24.380의 native TLV를 자체 경량화한 포맷이다(mbcp_native.rs): 헤더 2바이트(`[ACK_REQ 1bit|type 4bit][field_count]`) + TLV 나열. 메시지 타입은 표준 정합(REQUEST/GRANTED/DENY/RELEASE/IDLE/TAKEN/REVOKE/QUEUE_*/ACK), 필드도 표준 ID(priority/duration/cause/queue_pos...)에 자체 확장 5종(0x14~0x18: prev_speaker, cause_text, **speaker_rooms, via_room, destinations** — 다방 환경에서 "누가 어느 방에 송출 중이고 이 이벤트는 어느 방 것인가"의 라우팅 정보)을 얹었다.

전달 계층:
- **SCTP/DCEP**(datachannel/): Publish PC의 DTLS 위에 sctp-proto(Sans-I/O) 루프. 클라가 DCEP OPEN("unreliable", maxRetransmits=0)을 보내면 서버가 ACK하고 stream을 기억한다. DC 수립 전에 도착한 floor 이벤트는 pending 버퍼(64개)에 쌓였다가 open 순간 drain — join 직후 grant race의 방어.
- **신뢰성은 앱 계층에서**: 채널이 unreliable이므로 중요한 메시지(Granted/Revoke, ACK_REQ=1)는 서버가 **T132 재전송**(500ms×3회, ACK 오면 취소)으로 보강한다. 50ms 타이머가 pending 재전송을 관리.
- **WS 폴백**: bearer는 세션 고정("dc"|"ws")이지만, DC 송신 실패 시 같은 바이너리를 WS unicast로 폴백한다(floor_broadcast.rs:305-312) — DC를 안 여는 청취 전용/cross-sfu 참가자가 발화권 이벤트를 못 받던 구멍의 봉합(S-h). floor 메시지가 멱등이라 이중 전달이 무해하다는 성질을 이용했다.

### 6.4 Slot과 PttRewriter — 화자가 바뀌어도 스트림은 하나

**Slot**(slot.rs)은 방의 가상 채널이다. 방 생성 시 audio/video 슬롯이 랜덤 virtual SSRC로 만들어지고(per-room 발급 — 전역 상수였다면 두 방을 동시 청취할 때 두 방 발화가 수신기의 같은 지터버퍼로 합쳐지는 결함이 있었다), 구독자는 `ptt-{room}-audio/video`라는 고정 track_id로 이 슬롯을 구독한다. 발화권이 회전하면 `set_publisher`가 현 화자의 물리 트랙을 Weak로 걸고 rewriter에 화자 교대를 알린다. **구독자 목록과 화자는 서로 무관**하다 — 입력(화자)이 바뀌어도 출력(구독) 배관은 그대로.

**PttRewriter**(ptt_rewriter.rs)는 제4장 RtpRewriter 위에 무전 시나리오를 얹은 래퍼다. 핵심 문제: **화자 A의 seq/ts와 화자 B의 seq/ts는 아무 관계가 없는데, 수신기는 하나의 연속 스트림을 기대한다.**

- **연속성**: virtual SSRC와 출력 누적치(ext_last_seq/ts)는 슬롯 수명 동안 이어진다. 화자가 바뀌면 offset만 다시 계산(다음 키프레임/첫 패킷에서).
- **침묵 구간의 시간 처리(arrival-gap)**: B가 말 시작할 때 ts를 얼마나 건너뛸까? 정답은 "수신자가 실제로 겪은 침묵 길이"다. 새 화자의 **첫 패킷이 도착한 시각**과 직전 릴레이 시각의 차를 ts로 환산해 건너뛴다 — 서버가 만드는 ts 간격과 수신측 도착 간격이 정확히 일치해 NetEQ(수신 지터버퍼)가 왜곡을 안 겪는다. 구 방식(전환 시각 기준 추정)은 전환마다 +43ms 드리프트가 누적되는 실측 결함이 있었고, 근본 수리 근거가 주석에 남아 있다(ptt_rewriter.rs:36-42).
- **silence flush**: 화자가 끝나면 Opus 무음 3프레임을 만들어 흘린다 — 수신 디코더가 "스트림이 끊겼나?"를 고민하지 않고 자연스럽게 무음 전환. 멱등(이중 호출 방어 — 이중이면 ts 간격 계산이 깨져 지터버퍼가 오판하던 사고의 봉합).
- **priming CN**: 발화권을 받고 첫 음성이 나오기까지(마이크 재획득 등, 실측 ~700ms) 수신 NetEQ가 식은 상태로 첫 burst를 맞으면 지연이 폭주한다(돌림노래 사고, 20260623). grant 즉시 20ms 페이싱의 comfort-noise를 흘려 버퍼를 데워 두고, 진짜 음성이 오면 멈춘다. **발화자 본인은 제외**(exclude_user — self-echo 방지, SRV-0629 수리). 세대 카운터(priming_gen)로 화자 추월 시 옛 예열 태스크가 자가 종료.
- **video PTT**: 키프레임 없이는 전환이 완결되지 않으므로 pending_keyframe 대기 + Granted 시 PLI 버스트. priming/silence는 audio 전용이라 video는 키프레임 도착까지 검은 화면이 구조적으로 가능(코드가 인정하는 한계).
- **NACK 역매핑**: 구독자가 virtual SSRC 기준으로 재전송을 요청하면 현재 offset으로 역산해 원본 캐시에서 꺼낸다. 전환 경계의 낡은 요청은 RTX gate가 차단(제4장).

### 6.5 다방 청취와 발언 전환 — Scope 모델

무전 UX의 요구: **여러 채널을 동시에 듣고, 말하는 채널은 하나.** 자료구조가 그대로 대응한다 — `sub_rooms: HashSet`(N방 청취, MCPTT Affiliated) + `pub_room: Option`(1방 발언, Selected), 불변식 `pub_room ⊆ sub_rooms`.

- **SCOPE op(0x1200)** 하나가 전부 처리: `mode=update`(sub_add/sub_remove/pub_select/pub_deselect 증분) 또는 `mode=set`(sub 전체 집합 — 서버가 diff 계산). 적용 순서 고정(sub_add→sub_remove→pub_deselect→pub_select — 해제가 선택보다 먼저라 같은 sfud 내 발언방 swap이 안전). 응답에 항상 최종 스냅샷 동봉(서버 권위).
- **발언 대상 결정**: FLOOR_REQUEST의 destinations TLV로 방을 지목한다. 검증 3종이 타입화돼 있다(`FloorRouteDeny`: 목적지 없음/2개 이상(Phase 1은 단일방만 — 0703 S4로 Deny 배선 완료)/미참가 방). RELEASE는 envelope의 방이 아니라 **pub_room 기준** — cross-sfu 발언방 전환 직후 옛 방으로 release가 가는 유령을 막는 결정이며, WS/DC 두 bearer가 동형이다(0703 ③ 통일).
- **cross-sfu**: 방→sfu가 1:1이므로 sfu 간 미디어 릴레이는 없다. 클라가 sfu별 transport를 풀링하고, 발언 전환은 이전 sfud pub_deselect + 새 sfud pub_select 두 요청으로 클라가 쪼개 보낸다.

### 6.6 Active Speaker — Floor와는 다른 기계

혼동 주의: **Floor는 중재된 발화권**(무전), **Active Speaker는 음량 관측**(회의 UI 표시등)으로 완전 별개다. 후자는 RTP의 audio-level 확장(RFC 6464)을 EWMA(α=0.3)로 평활해 500ms마다 상위 3명을 뽑고, 직전 방송과 달라졌을 때만 DC(SVC_SPEAKERS)로 쏜다(delta 방송 — 트래픽 절약). 방별 opt-in(기본 꺼짐).

### 6.7 [진단] PTT/Floor 계층

**강점**
1. **순수 상태기계 + 단일 방송 진입점** — 4개 유입 경로가 한 기계·한 방송 코드로 수렴하고 액션 순서까지 시험으로 고정. 발화권처럼 race가 체감 사고로 직결되는 도메인에서 올바른 구조.
2. **수신기 물리학에 대한 이해** — arrival-gap ts, silence flush 멱등, priming CN, marker bit 규칙(Opus만 강제 — VP8에 강제하면 Chrome freeze)까지, NetEQ/디코더의 실제 동작에서 역산된 처리가 층층이 쌓여 있고 각각 실측 사고가 근거로 붙어 있다. 이 코드베이스에서 도메인 지식 밀도가 가장 높은 곳.
3. **liveness의 무비용화** — FLOOR_PING wire 폐기, RTP 도착 시각 재활용(핫패스 변경 0줄). "이미 있는 사실을 재활용"하는 원자 사실 원칙의 모범.
4. **회귀 가드의 정밀함** — seq 충돌 교차, priming 후 단조성, 엇갈린 clear 재연 등 사고 재연 시험이 rewriter에 박혀 있다.

**리스크·냄새 (우선순위순)**
1. **Idle release의 prev_speaker 오염** — Idle 상태에서 비화자가 release를 보내면 `Released{prev_speaker: 요청자}`가 반환되고, 방송 경로가 이 값을 IDLE 메시지에 그대로 싣는다(floor.rs:408-413). 실제 직전 화자가 아닌 사람이 "방금 말 끝낸 사람"으로 전파될 수 있다. 클라 UI가 이 필드를 어떻게 쓰는지에 따라 실해가 갈리므로 확인 후 수리 후보.
2. **엇갈린 clear의 화자 드롭(클로버 경로)** — floor 락 밖에서 apply가 돌고 clear_speaker가 대상 지정이 없어서, 큐 상황에서 switch(B)→늦게 도착한 clear(A분)가 B를 지워 B 음성이 통째 Skip될 수 있다. 테스트가 이 경로를 **재연만** 하고 있다(ptt_rewriter.rs:736-752) — 알려진 미봉합. clear에 "누구의 clear인가"를 태우면 닫힌다.
3. **liveness 임계 공유의 경계 취약** — self-ping 조건과 revoke 조건이 같은 5000ms를 쓴다(tasks.rs:62-69). 2초 타이머 위상에 따라 화자의 짧은 패킷 공백(4~5초)이 ping 기회 없이 곧장 revoke로 갈 수 있다. ping 판정 창을 timeout보다 짧게(예: 4s) 분리하면 닫히는 자리.
4. **duration 파싱 후 무시** — 클라가 보낸 발화 시간 요청이 양 bearer에서 파싱되지만 `None`으로 버려져 항상 30초 고정이다(datachannel/mod.rs:547, floor_ops.rs:127 — 의도적 미결). 겹쳐서 큐 경유 grant는 per-request 시간이 소실되는 잠복 버그도 있다(floor.rs:566). wire와 동작의 괴리 — 활성화하든 필드를 거절하든 결정이 필요.
5. **DC 방송의 O(N) 락 순회** — floor 이벤트마다 참가자별 pending_buf/unreliable_tx Mutex를 순회(floor_broadcast.rs:378-408). 발화권 이벤트 빈도가 낮아 현재 무해하나 대형 talkgroup에선 grant 지연에 기여할 수 있다.
6. **주석의 낡은 심볼** — `room.audio_rewriter`(슬롯 이주 전 이름, ingress_subscribe.rs:59), "flush_ptt_silence"(존재하지 않는 함수명 — 실체는 clear_speaker+broadcast_silence_frames 조합)가 주석·구전에 남아 있다. 이번 정독에서도 두 정독 반이 이 유령 심볼을 추적하느라 품을 썼다 — 문서 정합의 실비용 사례(제9장).

---

## 제7장. 런타임 골격과 동시성 전략 — 프로세스는 어떻게 살고, 상태는 어떻게 나뉘는가

> 대상: `main.rs`/`lib.rs`/`state.rs`/`tasks.rs`/`config.rs`/`error.rs` + `common/process.rs`/`config/` + 소스 전체 동시성 프리미티브 전수조사.

### 7.1 기동 순서 — main에서 서비스까지

`main.rs`는 30줄이다 — `run_server()` 호출과 종료코드 처리뿐. 실제 오케스트레이션은 `lib.rs::run_server()`(lib.rs:58) 한 함수에 순서대로 있다:

1. **설정**: config 디렉터리 결정(인자>cwd) → system.toml(정적: 포트/경로/TLS)+policy.toml(운영: bwe_mode/auto_layer/floor bearer) 로드. 파일 없으면 Default로 기동(랩 편의). 값 우선순위는 인자 > toml > 자동감지.
2. **로깅**: LOG_DIR 있으면 일별 로테이션 파일. flush guard를 `Box::leak`으로 프로세스 수명 고정(의도적 누수 — 주석으로 방어).
3. **생명선(lifeline)**: `OXLENS_LIFELINE=stdin`일 때만, **tokio가 아닌 std::thread**로 stdin EOF를 감시한다. supervisor(oxhubd)가 자식 spawn 시 stdin 파이프를 쥐고 있어 supervisor가 어떤 방식으로 죽든(kill -9 포함) fd가 닫혀 자식이 동반 종료된다. env opt-in인 이유: 수동 기동(tty/nohup)에서 즉시 EOF 오발동 방지. std::thread인 이유: tokio stdin은 blocking pool의 read()에 앉아 runtime 종료를 무한 대기시켜 graceful 종료가 전멸했던 0703 실측의 산물(lib.rs:176-177).
4. **자산 생성**: DTLS 인증서(인스턴스당 1회) → UDP 바인드(Linux는 SO_REUSEPORT multi-worker, 그 외 단일) → 전역 METRICS/telemetry/agg init → 이벤트 버스 → `AppState` 조립 → hooks 전역 컨텍스트.
5. **태스크 스폰**: UDP worker 0..N + 백그라운드 4종(§7.3) + gRPC 서버. **sfud는 gRPC만 연다** — WS는 hub의 일.
6. **종료 대기**: `ctrl_c | SIGTERM` → CancellationToken cancel → 전 태스크의 cancelled() 분기 발동 → 3초 drain → 정상 반환.

**supervisor 계약**(common/process.rs — 상수 3개가 전부): `EXIT_ADDR_IN_USE=100`(포트 점유는 재시도로 안 풀리는 영구 조건 — 이 코드로 죽으면 supervisor가 backoff 폭주 대신 Blocked 분류; 0612 고아 프로세스 restart #296 사고의 역산) + lifeline env 2종. 프로세스 생사의 계약이 코드 17줄로 응축돼 있고, 각 줄에 사고 이력이 붙어 있다.

### 7.2 AppState — 전역 상태의 단일 뿌리

`AppState`(state.rs:15-37)는 10개 필드가 전부다: `rooms: Arc<RoomHub>` + `endpoints: Arc<PeerMap>`(상태의 양대 뿌리), cert/socket/ip/port(전송 자산), bwe_mode/remb/floor_bearer(부팅 시 고정된 정책), `event_tx`(hub 이벤트 채널, None이면 standalone). Clone이 값 복제인 가벼운 핸들 묶음이라 태스크마다 자유롭게 복제해 넘긴다. **전역 가변 상태의 진입구가 이 구조체 하나**라는 점이 코드 추적성의 토대다 — "이 상태는 어디서 왔나"의 답이 항상 AppState 필드 경로로 환원된다.

한 가지 예외적 전역: `AUTO_LAYER_MODE: AtomicU8`(config.rs:92)와 policy `ArcSwap`. 후자는 주의가 필요하다 — **핫리로드 인프라는 남아 있지만 swap을 트리거하는 코드가 없다**(update_policy/reload_policy는 호출자 전무로 20260705 삭제). 즉 policy.toml은 사실상 부팅 1회 로드다. "ArcSwap이니 런타임 교체 가능"이라는 착시가 남아 있는 자리(§7.5).

### 7.3 백그라운드 태스크 — 심장박동 넷 + 편승 타이머

전부 `interval tick | cancelled` select 패턴(tasks.rs):

| 태스크 | 주기 | 하는 일 |
|---|---|---|
| floor timer | 2s | 화자 RTP 도착 시각으로 self-ping + T2(30s)/liveness(5s) 만료 revoke → apply_floor_actions |
| zombie reaper | 5s | last_seen 기반 Suspect(15s)/Zombie(20s) 천이·수확(제3장 §3.8) |
| stalled checker | 5s | 구독 스트림별 송신 카운터 델타=0 감지(정당사유 6종 제외) → TRACK_STALLED 통지(30s 쿨다운) |
| active speaker | 500ms | opt-in 방만 EWMA 판정 → 변동 시 DC 방송 |

그리고 **worker-0 편승 타이머**가 셋 더 있다(transport/udp/mod.rs:208-256, `is_primary` 가드): metrics flush(3s), TWCC FB/REMB(100ms/1s), RTCP 리포트+downlink tick(1s). 별도 태스크가 아니라 UDP worker-0의 select 루프 안이다 — 태스크 수를 아끼고 미디어 시계와 정렬하는 선택이지만, worker-0이 단일점이 된다(§7.5).

참고로 PLI Governor sweep 태스크는 0621에 폐기됐다 — 자동 레이어 다운/업그레이드와 안전망 로직이 오탐으로 화면을 얼려서, 키프레임 재시도 동력을 "수신측 주기 PLI + 서버 버스트"로 단순화했다. 태스크 하나가 사라진 것 자체가 설계 성숙의 기록이다.

### 7.4 동시성 전략 전수 — 어떤 상태에 어떤 도구인가

소스 전체 grep 전수 결과, 이 코드베이스의 동시성은 **네 계급**으로 정확히 나뉜다. 원칙: *읽기가 압도적인 것은 lock-free, 배타가 본질인 것만 Mutex, async 경계를 넘는 것만 tokio 동기화.*

**① Atomic (개수: U64 69·U8 47·Bool 26·U32 16 등)** — 단일 값 사실. phase/last_seen/extmap ID/게이트 플래그/카운터. CAS가 필요한 자리(egress spawn 1회 가드, suspect 진입)는 CAS로. 관측 카운터 전부가 이 계급이라 **계측이 락을 낳지 않는다**.

**② ArcSwap (도메인 전반)** — "읽기 수천/s, 쓰기 수 회/분"의 컨테이너. 트랙·스트림 인덱스, 구독자 목록(Weak Vec), sub_rooms, pub_room, trace 세션, policy. 쓰기는 복사본을 만들어 통째 교체(RCU)하므로 reader는 절대 기다리지 않는다.

**③ DashMap** — 읽기도 쓰기도 잦은 레지스트리: RoomHub.rooms, Room.participants, PeerMap 4인덱스, agg 집계. 샤드 락이라 전역 정지가 없다.

**④ std::sync::Mutex** — 배타가 본질인 상태만: SRTP 컨텍스트(암호 상태는 순서 의존 — 배타 불가피), rtp_cache/nack_generator/rr_stats/sr_stats(패킷 순서 의존 통계), forwarder(레이어 전환 원자성), FloorInner(발화권 원자성), PttRewriter 내부. **핫패스에서 잡는 Mutex는 전부 "소유자가 사실상 하나"가 되도록 배치됐다** — inbound SRTP는 같은 5-tuple이 같은 worker에 고정되고, outbound SRTP는 구독자당 egress task가 독점하며, forwarder는 fan-out 스레드와 1초 tick만 접촉한다. 락을 없앨 수 없으면 경합자를 없앤 것.

**tokio::sync는 단 1곳**(DemuxConn.rx — await를 넘는 수신자 보유), **RwLock도 단 1곳**(migration용 peer_addr). 이 희소성 자체가 규율의 증거다 — async Mutex가 흔한 코드베이스는 대개 락 정책이 없다는 뜻인데, 여기는 정확히 필요한 곳에만 있다.

**Weak 규율**: 역참조·fan-out 목록은 예외 없이 Weak(제3장). 순환 누수의 구조적 봉쇄.

### 7.5 [진단] 런타임·동시성

**강점**
1. **네 계급 규율의 일관성** — 필드 타입만 보면 그 상태의 온도(핫/콜드)와 접근 패턴을 알 수 있다. 신규 기여자에게 가장 좋은 가이드는 문서가 아니라 이 타입 규율이다.
2. **사고 역산 설계** — EXIT 100, stdin lifeline, std::thread 선택, graceful drain까지 프로세스 생사 경로 전부가 실제 사고(0612 포트 점유, 0703 SIGKILL 전멸)에서 역산됐고 근거가 주석에 있다.
3. **경합 제거의 배치적 해법** — "락 최소화"가 아니라 "경합자 최소화"(worker 고정, task 독점, tick 단일 스레드). 정량 증거로 lock_wait 계측까지 붙어 있다.

**리스크·냄새 (우선순위순)**
1. **worker-0 단일점** — metrics flush/REMB/RTCP 리포트/downlink tick/NACK 송신이 전부 worker-0 편승이다. worker-0이 굶으면(대량 미디어 수신 등) 관측·혼잡제어·회복 기계가 함께 둔화된다. 현 규모 무해하나, 부하 시험에서 worker-0 tick 지연을 관측 항목으로 넣을 가치가 있다.
2. **policy 핫리로드 착시** — ArcSwap 인프라만 남고 트리거는 삭제됐다. "policy.toml은 재기동 반영"을 운영 문서에 명시하거나, ArcSwap을 걷어내 착시 자체를 없애는 정리가 필요하다.
3. **미사용 의존성 후보** — axum/tower-http가 의존성에 있으나 sfud는 WS를 열지 않는다(시그널링 hub 이관의 잔재 추정). 빌드 시간·공급망 표면의 공짜 감축 후보 — 제거 전 전수 grep 1회면 확정된다.
4. **AutoLayerMode 전역 초기값 V2** — 로더가 무조건 set하므로 런타임은 안전하지만, 로더를 안 거치는 경로(일부 단위시험)에서 의도치 않게 V2가 켜진 채 도는 시험이 생길 수 있다. 초기값을 Off로 두고 시험이 명시 set하는 쪽이 원칙에 맞다.

---

## 제8장. 관측성 — 서버는 자신을 어떻게 설명하는가

> 대상: `trace.rs`(343) · `agg_logger.rs`/`telemetry_bus.rs`(shim) + `common/telemetry/` · `metrics/` 4파일 · `hooks/` + admin 평면 접점.

### 8.1 쉬운 그림 먼저 — 네 개의 눈

관측 수단이 네 축으로 분리돼 있고, 각각 답하는 질문이 다르다:

| 축 | 질문 | 형태 | 비용 |
|---|---|---|---|
| **metrics** | 얼마나 많이/빨리? | 숫자 카운터·타이밍 | atomic add, ~ns |
| **agg-log** | 어떤 사건이 몇 번? | 반복 이벤트 집계(3s 묶음) | DashMap inc |
| **telemetry_bus** | 지금 상태 스냅샷은? | JSON 이벤트 스트림 → hub/admin | try_send(가득 차면 버림) |
| **trace** | 그 패킷이 정말 지나갔나? | SRTP 평문 패킷 탭(랩 전용) | 무구독 시 비교 1회 |

공통 계약 하나가 전 축을 관통한다: **관측이 미디어를 절대 막지 않는다.** 카운터는 atomic, 전달은 try_send(채널이 차면 관측 데이터를 버리지 미디어를 안 세움), trace는 구독자가 없으면 load+비교로 끝(할당 0).

### 8.2 metrics — 숫자의 축

기반은 `common/telemetry`의 3원 primitive: `Counter`(flush 시 swap(0) — 구간 델타), `Gauge`(peek — 현재값), `TimingStat`(sum/count/min/max CAS — 평균·범위). `metrics_group!` 매크로가 카테고리 struct와 flush→JSON을 자동 생성한다(함정: 필드에 doc 주석을 달면 매크로가 깨진다 — 일반 주석만, 0703 실측).

`SfuMetrics`(metrics/sfu_metrics.rs)는 11개 카테고리(srtp/nack/pli/rtcp/bwe/relay/track/ptt/codec/dc/simulcast) + 타이밍 3종(decrypt, **lock_wait** — 핫패스 SRTP 락 대기 실측, egress_encrypt) + tokio 런타임 스냅샷(worker별 busy/steal/큐 깊이 — 3초 델타)으로 구성된다. 전역 `static METRICS: Registry`라 어디서든 `METRICS.get().pli.throttled.inc()` 한 줄 — Arc 배달이 없다.

flush는 worker-0의 3초 tick: 전 카테고리 JSON + 참가자별 파이프라인 통계(트랙/스트림 직속 카운터를 이 시점에 합산 — 저장은 트랙 차원, 출력은 user/room 차원이라는 Stats 정렬 원칙) → telemetry_bus로 발행.

### 8.3 agg-log — 사건의 축

"같은 사건이 초당 수십 번" 유형(stalled, suspect, gate resume, client_event...)을 그대로 로그로 찍으면 로그가 무기가 아니라 소음이 된다. `AggLogger`(common/telemetry/agg.rs)는 사건 키를 해시로 묶어 카운트만 올리고 3초 flush 때 한 줄로 낸다. 키 상한 1024(초과는 무시 — 메모리 가드), 방 종료 시 해당 방 키 청소. 발행처는 생명주기 hook(track:publish_active, subscribe:active, session:suspect/zombie/recovered), 태스크(subscribe:stalled), 시그널링(scope:changed, client_event:*) 등이다.

`hooks/`는 phase 천이(제3장의 3벌 상태기계)를 agg-log로 흘리는 횡단 계층인데, stream.rs만 실동작하고 floor.rs/media의 일부는 미래용 빈 틀이다(`#[allow(dead_code)]`) — "채워질 자리"가 표시된 상태.

### 8.4 telemetry_bus와 admin 평면 — 전달의 축

`EventBus`(common/telemetry/bus.rs): 발행측 mpsc(512) → 중계 태스크 → broadcast(256). 이벤트 3종(ServerMetrics/RoomSnapshot/AggLog). 소비자는 gRPC `SubscribeAdmin` 스트림 — telemetry 이벤트와 3초 주기 방 스냅샷을 병합해 hub(→oxcccd/oxadmin)로 흘린다. 클라이언트 telemetry는 hub→oxcccd 직행으로 일원화됐고 sfud는 경유하지 않는다(0620 진단 경로 통합).

운영 진입점은 oxadmin CLI → hub REST → 이 스트림/ADMIN op들이다. 스냅샷(제2장 §2.6)의 설계 원칙 — 자료구조 무접촉, 응답 시점 파생 계산, 킬스위치 off면 필드 자체 부재 — 가 관측 축에서도 지켜진다.

### 8.5 trace — 패킷의 축 (보안 1급)

`trace.rs`는 SRTP **복호 평문**을 gRPC 스트림으로 뽑는 랩 전용 탭이다 — 합법 도청 장치이며, 그래서 구조가 보안 우선이다: `#[cfg(feature="trace")]`로 **코드 자체가 빌드에서 사라지는** 게이트(런타임 플래그가 아님), 전역 단일 세션(동시 구독 1개 — Conflict 거부), 마지막 구독자 Drop 시 세션 자동 해제. emit 지점은 ingress/egress/게이트 드롭 등 실측 9곳 — 파일 헤더의 "6곳" 인벤토리는 낡았다(§8.6).

⚠️ **그런데 지금 `default = ["trace"]`다**(Cargo.toml:25). 배포 스크립트가 `cargo build --release`를 쓰므로, 이대로 상용에 가면 평문 미디어 탭이 상용 바이너리에 실린다. Cargo.toml 주석 스스로 "상용 진입 전 반드시 default = []로"라고 경고하는 **기지 항목**(개발 편의 의도)이지만, 이 진단서 기준 최고 우선 상용 전 체크리스트다(제9장 R1).

### 8.6 [진단] 관측성

**강점**
1. **축 분리의 명료함** — 숫자/사건/스냅샷/패킷이 서로 다른 배관을 타고, 각 배관의 손실 정책(버림)이 명시적이다. "관측이 시스템을 해치지 않는다"가 계약으로 지켜진다.
2. **저장 차원과 출력 차원의 분리** — 통계는 물리 트랙/스트림 직속(원자 사실), 집계는 flush 시점(파생). 이중 장부가 없다.
3. **관측이 디버깅 방법론과 결합** — lock_wait 타이밍, onepc_unrouted, nack.gated 같은 카운터는 "여기가 의심되면 이걸 봐라"가 설계에 선반영된 것들이다.

**리스크·냄새**
1. **trace default 포함** — §8.5. 상용 전 1순위(R1).
2. **인벤토리 드리프트** — emit "6곳" 주석 vs 실측 9곳. 보안 경계 자산의 목록이 부정확하면 감사 때 탭 누락 위험이 있다. 정확 인벤토리로 갱신 필요.
3. **버림의 침묵** — telemetry_bus try_send 드롭과 이벤트 채널 lag skip은 정책상 옳지만 드롭 카운터가 없다. "관측 데이터가 안 온다"와 "버려지고 있다"를 구분할 수단 하나(드롭 카운터)가 있으면 관측 체계가 자기 자신도 관측하게 된다.
4. **hooks의 빈 틀 누적** — floor/media hook 자리가 dead code로 상주. 의도된 예약이지만, 미구현 설계 박제 금지 원칙과의 긴장이 있다 — 채울 계획이 없으면 걷어내는 쪽이 원칙 정합.

---

## 제9장. 종합 진단 — S/W 전문가 관점의 총평

### 9.1 총평 한 단락

oxsfud는 **"실측 사고에서 역산된 설계"가 축적된, 규율이 살아 있는 27.5k줄**이다. 골격(2계층 도메인 모델, fan-out 방향역전, RTCP 종단자, 단일 스칼라 rewriter, 신호원 교체형 혼잡제어)은 견고하고, 동시성·관측성 규율은 타입 수준에서 일관된다. 반년간 대형 리팩토링을 반복하고도 구조 부채가 아니라 구조 자산이 쌓인 드문 사례다. 병은 골격이 아니라 가장자리에 있다 — ① 코드보다 뒤처진 주석·문서(유령 심볼이 이번 정독에서도 실제 비용을 냈다), ② 발화권 기계의 경계 조건 3건, ③ 미실측 튜닝 상수(v2), ④ 상용 전 체크리스트(trace). 즉 **다음 투자처는 새 구조가 아니라 경계 조건 봉합과 문서 정합**이다.

### 9.2 강점 요약 — 지켜야 할 것들

1. **원자 사실의 소유 구조** — 모든 식별자·통계·상태에 "홈"이 하나다(track_id는 Stream, ssrc는 Track, 판단은 transport...). 이번 자동 레이어 전환(신설 4파일)이 기존 구조 개조 없이 얹힌 것이 이 토대의 실증.
2. **핫패스 규율** — 조회 O(1), 목록 ArcSwap, 락은 경합자 제거로 무해화, 킬스위치 off=바이트 동일, 관측은 절대 비차단. 원칙이 선언이 아니라 검증 가능한 사실로 존재한다.
3. **사고의 자산화** — SnRangeMap seq 역행, 묵시 VP8, 돌림노래, +43ms 드리프트, SIGKILL 전멸… 주요 사고마다 (a) 근본 수리 (b) 주석 박제 (c) 회귀 시험이 세트로 남았다. 조직 학습이 코드에 저장되는 구조.
4. **후퇴 사다리** — v2→v1→off, DC→WS 폴백, take-over, 클라 주도 1PC 폴백. 신기능마다 후퇴 경로가 설계 단계에 포함된다.

### 9.3 리스크 순위표 — 이번 전수 정독의 발견 (기해소분 제외)

| # | 등급 | 항목 | 좌표 | 요지 |
|---|---|---|---|---|
| R1 | 상(상용 전) | trace default 포함 | Cargo.toml:25 | 평문 미디어 탭이 release 기본 빌드에 포함. 기지 항목이나 유일한 보안 1급 — 상용 체크리스트 1번 |
| R2 | 중 | Floor Idle release의 prev_speaker 오염 | floor.rs:408-413 | Idle 방에 비화자 release → 요청자가 "직전 화자"로 IDLE 방송에 실림. 클라 UI 사용처 확인 후 수리 |
| R3 | 중 | 엇갈린 clear의 화자 드롭 | ptt_rewriter.rs:736-752 | 큐 상황 floor 이벤트 인터리브 시 새 화자 음성 통째 Skip 가능. 테스트가 재연만 하는 미봉합 — clear에 대상 지정 태우면 닫힘 |
| R4 | 중 | liveness ping/revoke 임계 공유 | tasks.rs:62-69 | self-ping 창과 revoke 창이 같은 5s — 타이머 위상에 따라 짧은 패킷 공백이 곧장 revoke. ping 창 분리(예: 4s)로 봉합 |
| R5 | 중 | duration 파싱 후 무시 + 큐 grant override 소실 | floor_ops.rs:127, floor.rs:566 | wire와 동작 괴리(항상 30s). 활성화 or 필드 거절 결정 필요 — 활성화 시 큐 경유 소실 버그 동반 수리 |
| R6 | 중 | v2 튜닝 상수 미실측 + GRACE>REDEMOTE 암묵 불변식 | gcc.rs:5-6, config.rs:148 | GCC 이식값 실망 미검증(백로그 실망 시험이 실질 완결 조건), 상수 부등식은 const_assert 한 줄로 봉인 가능 |
| R7 | 중하 | 프로브 발사 실패의 침묵 | auto_layer.rs:193-204 | RTX 미협상 시 promote가 진전 없이 무한 재시도, 카운터 부재 — 관측 1개 추가 |
| R8 | 중하 | target_user 규약 산재 | sfu_service.rs:110, admin.rs:583 등 | envelope 덮어쓰기 우회 규약이 3곳 분산, 강제 장치 없음 — 신규 admin op의 함정. dispatch 층 일원화 후보 |
| R9 | 하(효율) | FullNonSim fan-out to_vec + audio rtp_cache 상주 | subscriber_stream.rs:587, publisher_track.rs:335 | 패킷당 N복사·미사용 캐시. 부하 실측 동반 별 토픽 |
| R10 | 하(확장) | worker-0 편승 타이머 단일점 + admin 스냅샷 O(전체) | udp/mod.rs:254, admin.rs:526 | 현 규모 무해. 부하 시험 관측 항목으로 등재 |

이번 정독의 오탐 1건도 기록한다: PLI throttle 필터 마스크 결함 보고(ingress_subscribe.rs:388)는 **재검증 결과 정상 코드**였다(주석이 "마스크를 쓰면 안 되는 이유"를 설명한 것을 결함 자백으로 오독). 병렬 정독 + 직접 재검증의 교차가 유효했다는 실증.

### 9.4 문서·주석 정합 목록 (코드가 앞선 곳)

이번 정독에서 두 정독 반이 유령 심볼 추적에 실제 품을 썼다 — 문서 부채는 미학이 아니라 비용 문제다.

1. **PROJECT_SERVER.md**: `WsBroadcast`의 per_user_payloads/binary_payload 서술 → v3 wire 단일화 반영 필요(현행: wire 단일 + per-user는 unicast 반복). `flush_ptt_silence` 언급 → 실체는 `clear_speaker`+`broadcast_silence_frames`.
2. **rtp_rewriter.rs:22-24**: "RTX gate 미배선, 결재 대기" → 0703 b25e9b9로 배선 완료. 주석이 코드보다 낡음.
3. **trace.rs:5 / lib.rs:20**: emit 호출부 "6곳" → 실측 9곳. 보안 자산 인벤토리 정확화.
4. **downlink.rs/bwe.rs/peer.rs 주석의 `SIMULCAST_AUTO_LAYER`/`BWE_V2`** → 현 게이트는 `AutoLayerMode`(auto_layer_enabled/bwe_v2_enabled).
5. **ingress_subscribe.rs:59**: `room.audio_rewriter` → Slot 이주 완료된 옛 이름.
6. **policy 핫리로드**: "ArcSwap 런타임 교체" 구전 → 트리거 삭제로 사실상 부팅 1회 로드. 운영 문서 명시 필요.

### 9.5 개선 우선순위 제언 (결재용)

1. **[즉결·저면적]** R4(ping 창 분리) · R6 후반(const_assert) · R7(프로브 카운터) · §9.4 주석 정정 일괄 — 전부 동작 위험 낮고 기계적.
2. **[확인 후 수리]** R2(클라 IDLE prev_speaker 사용처 실측 → 수리) · R3(clear 대상 지정 — floor 경로라 회귀 시험 동반).
3. **[설계 결정]** R5(duration 활성화 vs 필드 거절) · R8(target_user 규약 일원화 방식).
4. **[일정 결부]** R6 전반(실망 시험 묶음 — v2의 실질 완결 게이트, 기존 백로그와 동일) · R1(상용 전 체크리스트 — trace 제거 + FLOOR_MAX_BURST 등 랩 상수 재점검과 한 묶음).
5. **[별 토픽·실측 선행]** R9 핫패스 효율(부하 프로파일 먼저) · R10 확장성(부하 시험 설계에 관측 항목으로).

### 9.6 확장 관점의 구조 준비도

- **Hyb 1PC**: 완료(0709). egress 단일 진입(`egress_session()`)과 1PC RTCP 라우터가 기존 구조에 흡수됐고 2PC 무손상 원칙이 지켜졌다 — 도메인 모델이 연결 토폴로지 변화를 국소로 흡수한 실증.
- **규모 확장(방·참가자 증가)**: 핫패스는 준비돼 있다(O(1)+lock-free). 병목 후보는 주변부 — worker-0 편승 타이머, admin O(전체) 스냅샷, 콜드패스 선형 탐색(room.rs:212), DC 방송 O(N) 락. 전부 이 문서에 좌표가 있으니 부하 시험 때 이 목록이 곧 계측 지점이다.
- **미디어엔진 직접 장악(영상무전 재도전 등)**: 서버 쪽 준비도는 높다 — SDP-free·rewriter·프로브 페이싱 등 "브라우저가 안 주는 레버"를 제외한 전 레버가 이미 서버 소유다. 보류 사유(클라 send pacer)는 서버 구조 밖의 문제로 남아 있다.
- **상태 복구(장기)**: 인메모리 단일 진실 + 클라 재합류 복구는 현 규모의 정답. 다중 sfud·대규모 방에서 재합류 폭풍이 보이기 시작하면 그때가 상태 이전(핸드오버) 설계의 착수 시점이며, 그 전엔 설계 박제 금지 원칙대로 열어 두지 않는다.

---

*부록 없음 — 각 장의 소스 좌표가 곧 색인이다. 자매 문서: PROJECT_SERVER.md(구조 단일출처) · 20260703_sfud_source_audit.md(감사) · 20260711_auto_layer_final_report.md(자동 레이어 완결).*

---
