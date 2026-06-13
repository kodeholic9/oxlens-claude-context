// author: kodeholic (powered by Claude)
# oxtapd — 녹음/녹화 데몬 설계 (현행화)

> 작성 2026-06-13. **2026-04-13 설계서(`20260413_oxtapd_design.md`)의 현행화본.**
> 4월 이후 변경(oxrtc 실현 / supervisor 도입 / wire v3 / cross-sfu / 식별 평면)을 반영.
> 4월 본의 OXR 포맷·META·분할·업계대비는 유효 → 유지. 본 문서가 현행 단일 출처.
> **⏸ 구현 보류** (2026-06-13 부장님 결정) — 설계 기록만, 착수 시점 미정. §14 업계 분배 선례 반영.

---

## 0. 현행화 델타 (4월 → 0613) — 먼저 무엇이 바뀌었나

| 4월 설계 | 현행 사실 | 영향 |
|---|---|---|
| liboxrtc **신규 개발 필요** (최대 블로커) | **`oxrtc` 로 이미 구현** (구 liboxrtc, lib.rs 가 "for oxtapd" 명시). oxe2e 가 실사용 중 | 블로커 해소. oxtapd 는 `oxrtc` path dep |
| §13 미결 "hub→oxtapd 명령 채널 / 배포 형태" | **supervisor 도입**(0603). hub 가 자식 spawn/감시 | 배포=hub supervisor 자식. ready=GrpcConnect (oxcccd 동형) |
| opcode 정수(0/100/141…) | **wire v3 16진**(0x0001/0x2001/0x2400…). FLOOR_TAKEN/IDLE → FLOOR_MBCP binary 통합 | §8 opcode 표 전면 교체. floor 인터리빙은 MBCP 파싱(oxrtc.dc) |
| 단일 SFU 전제 | **cross-sfu**(방→sfu 1:1, room_sfu 매핑) | oxtapd 가 녹화 시 hub 가 알려준 **해당 sfu** 에 접속 |
| `Participant.participant_type` | participant.rs 해체 → **RoomMember**. config 에 `PARTICIPANT_TYPE_RECORDER=1` 선반영 | type 자리는 이미 있음. RoomMember/IDENTIFY 반영만 |
| META `track:add` 의 ssrc 식별 | **식별 3평면**(track_id/vssrc/실ssrc, 0603) | META 트랙 식별자 = track_id 우선 |

**유지(변경 없음)**: OXR append-only 포맷(§6) / META 인터리빙(§6.3) / 물리 분할·carry-over(§7) / oxtap-mux(§10) / 업계 대비·기각(§11~12).

---

## 1. 개요

### 1.1 목적
- OxLens SFU 의 녹음/녹화 데몬. 방 단위 미디어 + 시그널링 메타데이터 기록.
- 타겟: 파견센터·보안·물류·발전소 (B2B, 24시간). **녹화 없으면 계약 불가** = 제품화 최대 블로커.

### 1.2 명칭 (현행)
- **oxtapd** — 녹화 데몬
- **`oxrtc`** — WebRTC **client** transport (구 liboxrtc. **이미 구현**, 서버 워크스페이스 멤버). oxtapd + oxe2e + oxlab-bot 공유
- **OXR** — 자체 녹화 포맷 (append-only)
- **oxtap-mux** — OXR → WebM/IVF 후처리 CLI (향후)

### 1.3 핵심 원칙 (불변)
- **SFU 변경 최소** — oxtapd 는 일반 subscriber 와 동일 경로로 미디어 수신
- **정상 WebRTC 경로** — ICE+DTLS+SRTP, plain RTP 포워딩 없음
- **투명 참가자** — `type:"recorder"`, 다른 참가자에 비노출·인원 카운트 제외
- **RTP 원본 보존** — 트랜스코딩 0, CPU≈0
- **메타 인터리빙** — 시그널링 이벤트를 미디어와 같은 파일에 (PTT floor 포함 — 업계 유일)

---

## 2. 아키텍처 (현행)

### 2.1 워크스페이스 실측 (2026-06-13)

```
oxlens-sfu-server/crates/
├── common · oxsig · oxrtc · oxsfud · oxhubd · oxcccd · oxe2e   ← 현재 멤버
└── (신규) oxtapd          ← 녹화 데몬 (추가 예정)
    (향후) oxtap-mux       ← OXR 후처리 CLI

* oxrtc = 구 liboxrtc. 이미 존재 (ice_client/dtls_client/srtp_session/
          rtp_receiver/rtcp_sender/signal_client/dc/error). oxtapd 는 이걸 path dep.
* liboxrtc 신규 크레이트 = 불필요 (이름이 oxrtc 로 흡수됨).
```

### 2.2 프로세스 관계 (supervisor + cross-sfu)

```
 systemd -> oxhubd -+- supervisor -+- oxsfud (N node)
                    |              +- oxcccd
                    |              +- oxtapd          <- 신규 자식, ready=GrpcConnect
                    +- WS 게이트웨이 + REST
                    +- gRPC --> oxtapd (녹화 시작/중지 명령 + room_sfu 주소 동봉)
                                   |
                  oxtapd -WS(시그널링)+UDP(SRTP)-> oxsfud[해당 방의 sfu]
                          (oxrtc client, recorder subscriber)
```

- **hub = 기동 + 명령만**. 미디어는 oxtapd <-> sfud **직결**(oxcccd 와 결정적 차이 — oxcccd 는 sfud 안 닿음).
- cross-sfu: 방은 1개 sfu 에 1:1 배치. 녹화 명령 시 hub 가 `room_sfu` 로 **해당 sfu 의 ws/udp 주소**를 oxtapd 에 동봉 → oxtapd 가 그 sfu 에 접속.

---

## 3. oxrtc — client transport (이미 구현, 신규 개발 아님)

4월 "liboxrtc 신규" 항목은 **종결**. `oxrtc` 가 그 역할로 구현돼 있고 oxe2e 가 검증 중.

```
oxrtc/src/  (실측)
├── ice_client.rs     — STUN binding (client)
├── dtls_client.rs    — DTLS handshake (client role)
├── srtp_session.rs   — SRTP decrypt (수신)
├── rtp_receiver.rs   — RTP seq 추적 / gap / depacketize
├── rtcp_sender.rs    — RR / NACK / PLI 생성
├── signal_client.rs  — WS 시그널링 (v3 wire)
├── dc.rs             — DataChannel client (MBCP floor 수신 ★ floor 인터리빙 필수)
└── error.rs
```

- oxtapd 는 `oxrtc = { path = "../oxrtc" }`. **검증 부담 거의 0** (oxe2e 가 동일 transport 로 회귀 중).
- 남은 확인: oxe2e 사용 범위가 RR/NACK/PLI/dc 전부인지 vs 일부인지 — 일부면 oxtapd 가 미사용 경로를 처음 밟음(§13 확인 항목).

---

## 4. recorder 참가자 타입 (현행)

- config 에 **`PARTICIPANT_TYPE_RECORDER = 1` 이미 선반영** (oxsfud/config.rs).
- 반영 필요: `RoomMember` 가 type 보유 + IDENTIFY `type` 파싱 → sfud 전달.
- recorder 차이: ROOM_EVENT broadcast 제외 / 참가자 목록·인원수 제외 / publish 불가(subscribe only) / admin snapshot 별도 표시. **TRACKS_UPDATE·FLOOR·MODERATE 이벤트는 수신**(META 기록 위해).
- 변경 범위: oxsfud(RoomMember type + broadcast/카운트 필터) + oxhubd(IDENTIFY type passthrough). 4월 설계의 fan-out 필터 그대로, RoomMember 구조에 맞게.

---

## 5. 녹화 정책 + 명령 채널 (현행)

### 5.1 명령 채널 = hub → oxtapd gRPC (oxcccd 정합)
4월 미결(REST/WS/gRPC 택1) → **gRPC 확정**. oxcccd 가 hub→자식 gRPC 를 이미 쓰므로 정합. supervisor 가 기동한 oxtapd 에 hub 가 gRPC 로:
- `StartRec { room_id, sfu_ws_addr, sfu_udp_addr }` — room_sfu 매핑으로 해당 sfu 주소 동봉
- `StopRec { room_id }`

### 5.2 시작/중지 흐름
```
[시작] REST/클라 ROOM_CREATE{rec:true} -> hub rec 감지 -> room_sfu 조회
        -> hub -gRPC StartRec(room_id, 해당 sfu addr)-> oxtapd
        -> oxtapd: oxrtc 로 그 sfu 에 WS 접속 -> IDENTIFY{type:"recorder"} -> ROOM_JOIN
        -> subscribe 협상 -> SRTP 수신 시작
[중지] ROOM_UPDATE{rec:false}/방삭제 -> hub -StopRec-> oxtapd -> ROOM_LEAVE -> 파일 finalize
[복구] oxtapd 재기동 -> hub 가 rec=true 방 목록으로 StartRec 재발행 (supervisor backoff 후)
```

### 5.3 Room rec 플래그
- ROOM_CREATE / ROOM_UPDATE 에 `rec:bool`. hub 가 감시. (sfud 미디어 무관 — hub 정책)

---

## 6. OXR 파일 포맷 (4월 유지 + 식별 평면 정합)

append-only / RTP+META 인터리빙 / 무변환. (4월 §6 그대로)

**File Header**: magic `"OXR1"` / version / room_id / created_at(epoch_us) / codec_audio/video / carry_over(JSON).
**Record**: `type(u8: 0x01=RTP, 0x02=META) | ts_us(u64 wall-clock) | len(u16) | payload`.

### META 이벤트 (식별자 현행화)
floor:taken/idle · participant:join/leave · track:add/remove · mute · duplex:changed · grant/revoke · segment:boundary · rec:start/stop.
- **track:add 식별 = `track_id`(불투명) 우선** + kind/duplex/mid 동반 (구 ssrc 단독 → 0603 식별 3평면 정합). PTT 는 가상 ssrc 가 wire 값이므로 RTP record 의 ssrc 와 META track_id 매핑을 carry_over 에 보존.
- **floor:taken/idle 출처 = MBCP(0x2400) binary 파싱** (oxrtc.dc). 구 FLOOR_TAKEN(141)/IDLE(142) 정수 op 폐기 반영.

---

## 7. 물리 분할 (4월 유지 — config 이미 존재)

system.toml `[recording]` **이미 선반영**: `segment_continuous_secs=300`(5분) / `segment_utterance_secs=3600`(PTT 1h) / `segment_moderate_secs=3600` / `retention_days=30` / `base_path`.
- oxtapd 가 TRACKS_UPDATE 의 duplex 로 시나리오 자동 판별 → 분할 단위 결정.
- carry-over: 분할 시 다음 파일 헤더에 화자/참가자/트랙·SSRC 매핑 기록 → 각 파일 독립 해석.
- **분산 주의(§14)**: tap 다중이면 base_path 는 공유 스토리지(NFS/S3)여야 통합 조회 가능.

---

## 8. 시그널링 — oxtapd 수신 opcode (wire v3 전면 교체)

| v3 op | 이름 | oxtapd 동작 |
|---|---|---|
| 0x0001 | HELLO | heartbeat_interval |
| 0x2001 | ROOM_EVENT | META participant:join/leave |
| 0x2101 | TRACKS_UPDATE | META track:add/remove + subscribe 갱신 |
| 0x2102 | TRACK_STATE | META mute / duplex:changed |
| 0x2400 | FLOOR_MBCP (**binary**) | MBCP TLV 파싱 → META floor:taken/idle (oxrtc.dc) |
| 0x2700 | MODERATE_EVENT | META grant/revoke |

기존 시그널링 경로 100% 재사용. 별도 채널 없음. (SubscribeAdmin 확장·gRPC 전용 채널 = 4월 기각 유지)

---

## 9. oxtapd 내부 구조

```
oxtapd/src/
├── main.rs          — 데몬 시작 + gRPC server(StartRec/StopRec 수신)
├── config.rs        — system.toml [recording] 참조
├── recorder_mgr.rs  — RoomRecorder 생명주기 (hub 명령 → task per room)
├── room_recorder.rs — 방 단위 세션 (oxrtc client 1개 = recorder subscriber)
├── track_writer.rs  — 트랙별 RTP+META 인터리빙 쓰기
├── oxr/{format,writer,reader}.rs — OXR 포맷
└── retention.rs     — retention_days 자동 삭제
```
- ready=GrpcConnect 판정용으로 gRPC server(StartRec/StopRec)가 bind 되면 supervisor 가 ready 인식 (oxsfud 패턴 동일).
- 다중 방 = tokio task per RoomRecorder.

---

## 10~12. oxtap-mux / 업계 대비 / 기각 (4월 유지)

- **oxtap-mux**(향후 CLI): `convert/list-utterances/extract-utterance/timeline/info`. 무변환 depacketize → container mux.
- **업계 대비**: 정상 WebRTC subscriber 방식 + PTT floor 인터리빙 + 완전 NACK/PLI + 발화 단위 META 논리 분할 = 차별점. (상세 = §14)
- **기각 유지**: plain RTP 포워딩 / SFU 내부 직접 덤프 / str0m·webrtc-rs / MJR·PCAP / 발화마다 파일 분할 / SubscribeAdmin 확장 / gRPC 전용 미디어 채널 / pp 명칭.
- **기각 추가(0613)**: liboxrtc 신규 크레이트 — oxrtc 로 흡수됨, 중복 생성 금지.

---

## 13. 미결 / 시작 전 확인

### 해소됨 (4월 미결 → 닫힘)
- hub→oxtapd 명령 채널 → **gRPC StartRec/StopRec**. / 배포 형태 → **hub supervisor 자식**. / liboxrtc → **oxrtc 실현**.

### 남은 미결
| 항목 | 비고 |
|---|---|
| oxrtc 사용 범위 확인 | oxe2e 가 RR/NACK/PLI/dc 전부 밟는가 일부인가 — oxtapd 가 미사용 경로 처음 밟으면 검증 필요 |
| tap 분배 / multi-hub | §14 — 구현 보류 |
| Simulcast 레이어 선택 | high 만 녹화? 설정? (4월 미결 유지) |
| 디스크 용량 모니터링 | 임계치 알림 / 자동 중단 |
| OXR 압축 | zstd 추후 |
| oxtap-mux 구현 시점 | oxtapd 안정화 후 |

### 착수 시 1순위 (보류 해제 후)
1. **oxrtc 실사용 범위 실측** (oxe2e 가 어디까지 검증했나 = oxtapd 신규 위험 면적)
2. recorder type RoomMember/IDENTIFY 반영 (config 자리 이미 있음)
3. oxtapd 골격 + gRPC StartRec/StopRec + room_recorder(oxrtc client 1개)

---

## 14. 클러스터링·녹음 분배 — 업계 선례 (2026-06-13 조사)

> 출처: LiveKit Egress (blog.livekit.io/livekit-universal-egress, docs.livekit.io, github.com/livekit/egress),
> Jitsi Jibri (jitsi handbook, deepwiki jitsi/infra-configuration). "어떤 방을 누가 녹음하나" +
> multi-hub 권위 질문에 대한 조사. **구현 보류 — 설계 기록.**

### 14.1 녹음 방식 두 갈래 — 우리는 무변환 극단

| | composite (Jibri / LiveKit RoomComposite) | track/raw (우리 oxtapd) |
|---|---|---|
| 방식 | **헤드리스 Chrome 봇**이 회의에 participant 로 접속 → 가상 디스플레이(Xvfb) 렌더 → 화면 캡처 → GStreamer/ffmpeg 인코딩 | RTP subscribe → 트랙별 원본 그대로 덤프(무변환) |
| 산출물 | 즉시 재생되는 합성 회의 영상(레이아웃 포함) | 트랙별 raw + floor 메타 (재생은 oxtap-mux 후처리) |
| 비용 | Chrome 무겁다(2~6 CPU), **1 인스턴스=1 방**, 트랜스코딩 | CPU≈0, **1 tap=N 방**, 무변환 |

- "봇을 회의에 앉혀 그 화면을 녹화"하는 방식. composite(여러 타일을 한 화면으로 합성)를 위해 브라우저 재활용.
- 우리 타겟(보안/감사/PTT)은 합성 영상보다 **트랙별 원본 + "누가 언제 발화" 타임라인**이 핵심 → 무변환+메타 인터리빙이 도메인 적합. "회의 다시보기 UX" 요건 시 후처리(oxtap-mux)가 그 자리.
- LiveKit 도 Chrome 없는 **track egress** 모드 존재 — 우리는 그 무변환 극단.

### 14.2 분배 메커니즘 — 공통 뼈대 + 갈리는 축

| 축 | LiveKit Egress | Jibri (Jitsi) |
|---|---|---|
| 발견/등록 | Redis Pub/Sub 큐 | XMPP MUC(JibriBrewery) 등록 |
| 할당 방향 | **worker pull** (워커가 자기 부하 보고 집어감) + reservation | **중앙 push** (Jicofo 가 가용 Jibri 선택·dispatch) |
| 인스턴스 | 1 인스턴스=1 방, isolated handler process | single-use, 1 jibri=1 녹음, 완료 후 recycle |
| 상태 권위 | Redis 중앙 | XMPP/Prosody MUC 중앙 |
| 저장 | S3/Azure/GCP | 로컬→업로드 |

**공통 (둘 다)**: ① 녹음 = SFU 와 분리된 별도 서비스 + 별도 머신 ② **공유 상태 저장소가 라우팅/할당 권위**(hub-local 아님) ③ pool 운영(방 수만큼 + autoscale) ④ 방에 (투명) participant join ⑤ SFU hot-path 격리 1원칙 ⑥ 분산이면 공유 스토리지 필수.

**갈리는 축은 할당 방향 하나**: pull(LiveKit, Redis 큐 전제) vs push(Jitsi, 중앙 할당).

### 14.3 우리에게 주는 함의 (권고 — 결재 전)

1. **"누가 녹음하나" = 공유 상태 저장소로 푸는 게 업계.** 우리 `room_sfu`/(미래)`room_tap` 가 hub-local in-memory DashMap → multi-hub 면 권위 분열, 원천 불가.
2. **단, 단일 hub 면 그 문제 자체가 안 생긴다.** LiveKit 도 single-node=외부 의존 0, Redis 는 분산에만. → 1차 권고 = **단일 hub** (hub3 HA 는 Redis 도입 시점으로 미룸 — 업계도 그 순서).
3. **할당 방향 = 중앙 push(Jibri형)가 우리에 자연.** hub 가 이미 room_sfu 권위 쥔 중앙 → tap 도 hub 가 가용 tap 골라 StartRec push. LiveKit worker-pull 은 Redis 큐 전제라 단일 hub 엔 과함.
4. **우리 강점 = 무변환 1 tap=N 방.** 업계 1:1 은 트랜스코딩(Chrome/GStreamer) 때문. 우리는 인스턴스 수가 훨씬 적게 듦 (connection/디스크 한계는 측정 전 단정 금지).
5. **공유 스토리지 = 분산 시 필수.** tap 2+ 면 OXR 가 tap 별 분산 → base_path 로컬이면 통합 조회/후처리 불가. NFS/S3 전제 박아둘 것.

### 14.4 분배 설계 미결 — ⏸ 구현 보류 (2026-06-13)

아래는 설계 기록만, 착수 시점 미정 (측정·요건 전 과투자 회피):
- `tap_registry` + `room_tap` + `place_tap` — sfu 동형(room_sfu 패턴 복사), 중앙 push 할당
- tap 가용성/부하 보고 (Jibri free-pool / LiveKit available metric 대응)
- 공유 스토리지(NFS/S3) 전환 — OXR base_path 추상화
- multi-hub(HA) → Redis 공유 스토어 (sfu/tap/shadow 전부 영향, 별 대형 토픽)

---

*author: kodeholic (powered by Claude)*
