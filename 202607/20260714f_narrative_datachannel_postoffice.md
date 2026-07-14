// author: kodeholic (powered by Claude)
# 지하 우체국 — datachannel(SCTP/DCEP/MBCP) 3부작 열전

**서사 기반 정적 분석 · 실험 기록 5호**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 전편: floor(1호)·domain(2호)·udp(3호)·handler(4호)
표적: `crates/oxsfud/src/datachannel/` **전체 3파일 1,770줄** (테스트 포함 전문 통독, 하위 에이전트 위임 없음)

---

## 0. 실험 조건과 표기 규약 (정직 신고)

- **프라이밍 세션 연속** — 방법론 + 전편 4편 숙지 상태. **§6.1 A/B/C 판정 산입 불가.** 산출물 가치 = 신선 표적 재현성 + 전편 발견(D1·D2·D4·H1·destinations Deny)의 wire 층 교차 확인.
- 통독: mod(788) · mbcp_native(787) · dcep(193). 테스트 3블록(mod 5개·mbcp 30개·dcep 3개) 포함 전문.
- 무대 밖 확인(부분 열람): domain/floor_broadcast.rs(52~210·298~371, MBCP 빌더 소비처) · domain/peer.rs(resolve_floor_target:698·has_half_duplex:979·publish_room) · signaling/handler/floor_ops.rs(WS bearer 대조) · tasks.rs(299 broadcast_dc_svc) · config.rs(SCTP/MBCP 상수) · **oxlens-home/sdk0.2/src/internal/transport/transport.ts:481**(클라 실 DC 라벨) · speaker_tracker.rs(128).
- 표기: 행위 서술 = `파일.rs::함수:줄` 전체 형식. 판단·은유 = [판단]. 발견 = [확인](소스 실증) / [의문](동작 확정, 결함 여부 판단 필요).
- 기지 제외: D·E·U·H 계열은 신규 집계 제외. datachannel 이 그 발견들의 **wire bearer 쪽**이므로 교차 확인은 §9.

---

## 1. 무대 — 야간 우체국은 재전송을 안 믿는다

publish PC 의 DTLS 터널 안, SCTP 한 가닥이 흐른다. 그 위에 우체국이 선다 — user 당 하나, `run_sctp_loop`(mod.rs:84-200)가 종신 근무하는 야간 국장이다. 무대의 물리 사실 셋:

1. **국장은 혼자다.** publish PC 하나당 task 하나(mod.rs:84). select 루프가 DTLS 수신·50ms 타이머·broadcast 송신(dc_rx) 세 문을 지킨다(mod.rs:117-188). 4-tuple 해시로 한 클라가 늘 같은 워커에 오는 무대(3호 §1)와 같은 결 — 한 peer 의 DC 처리는 자연 직렬.
2. **분류는 외주다.** sctp-proto(Sans-I/O)가 청킹·재조립·SACK 을 처리하고(Endpoint/Association), 국장은 poll 로 이벤트만 긁는다(process_association_events:202-238). DCEP 과 MBCP 는 sctp-proto 가 모르는 상위 약속이라 손으로 짰다(mod.rs 주석 4-5).
3. **채널은 신뢰하지 않는다.** 클라가 여는 채널은 `unreliable`(ordered:false, **maxRetransmits:0** — transport.ts:481). SCTP 레벨 재전송이 0회다. [판단] 이 사실이 3막의 심장이다 — 우체국이 재전송을 SCTP 에 맡기지 않으니, 신뢰가 필요한 등기(ACK 요구 메시지)는 **국장이 직접 T132 대장을 들고** 재전송한다(mod.rs:636-677). 그런데 그 대장은 한 방향으로만 돈다.

의전: 클라가 DCEP OPEN 을 보내면 심사관이 라벨을 확인하고(dcep::parse → handle_dcep:361), "unreliable"이면 창구를 열고 대기 편지를 쏟아낸다(drain_pending_buf_and_mark_ready:409-434). 그 뒤로 Binary 프레임이 `[svc(1)|len(2)|payload]`(build_frame:52-60)로 오면 svc 로 갈래를 튼다 — MBCP(0x01)만 처리, Speakers(0x02)는 카운트만 하고 버린다(mod.rs:293-305).

## 2. 등장인물

### run_sctp_loop — 야간 국장 (mod.rs:84)
publish PC 의 DTLS task 가 고용한 종신직. 마음(association·channels·pending_acks·mbcp_stream_id)을 스택에 들고 혼자 지킨다(mod.rs:101-104) — 공유 상태가 아니라 **task-local**이라 락이 없다. 성격: **연결이 끊기면 미련 없이 퇴장한다** — AssociationLost 신호에 unreliable_tx 를 None 으로, ready 를 false 로 내리고 문을 닫는다(mod.rs:190-199). [판단] 임종은 깔끔하나 **유언장에 floor 가 없다**(→§9 교차, E1 의 DC 판).

### dcep — 개설 심사관 (dcep.rs:77)
RFC 8832 의 얇은 판. OPEN 을 12바이트 헤더 + 가변 label/protocol 로 뜯고(parse_open:116-147), ACK 는 1바이트로 답한다(build_ack:150-152). ChannelType 6종을 완비했으나(dcep.rs:34-57) **국장은 그 타입을 읽지 않는다** — 라벨만 본다(mod.rs:376). 성격: 관대한 파서 — from_utf8_lossy 로 깨진 라벨도 문자열로 만든다(dcep.rs:134). 화석 하나를 품고 있다(테스트 라벨 "mbcp", 실 계약은 "unreliable" — →P3).

### mbcp_native — 번역과 (mbcp_native.rs)
TS 24.380 §8.2 TLV 를 손으로 짠 사전. parse(120-254)는 13개 필드를 뽑고, build(260-334)는 그중 12개를 되짓는다. 성격: **관대하게 읽고 엄격하게 쓴다** — parse 는 미지 필드 무시(:234)·절단 시 부분 반환(:145-153·:207-208·:226-227), build 는 오름차순 고정 직렬화(:263)로 wire diff 비교를 돕는다. TLV 30개 테스트가 대칭을 조인다. 클라 `mbcp.ts` 와 "정확히 대칭"을 자임(:5).

### handle_mbcp_from_datachannel — 발언권 접수창구 (mod.rs:478)
DC bearer 의 floor 진입점. WS 창구(floor_ops.rs)와 **의도적으로 복제된 쌍둥이**(floor_ops.rs 주석 3-4). 성격: has_half_duplex 게이트(mod.rs:487)로 무전 자격을 먼저 확인하고, REQUEST 는 destinations 로 대상 방을 정하되(:514, resolve_floor_target), RELEASE 는 pub_room 으로만 간다(:573 — 감사 20260703 ③ 비석 준수).

### pending_acks — 미수령 등기 대장 (mod.rs:76·103)
ACK 를 요구하고 나간 편지의 명부. T132(config.MBCP_T132_MS)마다 재전송, C132_MAX 초과 시 포기(check_retransmits:636-677). 성격: **msg_type 으로만 편지를 식별한다**(:312 retain) — 같은 타입 두 통이 동시에 걸려 있으면 ACK 한 통이 둘 다 지운다(→P4, 경합 좁음).

### 소품
- **DC frame** `[svc|len:u16|payload]`(build_frame:52) — svc 0x01(MBCP)/0x02(Speakers). len 이 u16 이라 payload>65535 는 debug_assert 만(:54) — MBCP 는 작아 무해.
- **MBCP TLV** `[id|len|value]` — 표준 ID 0~12 + 자체확장 0x14~0x18(cross-room). 4바이트 align 미적용(자체 포맷 옵션 B, :19).
- **MbcpNative** — parse 결과 13필드. destinations/speaker_rooms 만 Vec(다방), 나머지 단수(:92-114).

## 3. 3막

### 1막 — 창구 개설과 밀린 편지
클라가 unreliable 채널을 연다. 심사관이 라벨을 확인하고(dcep.rs:134·mod.rs:376), 통과하면 국장이 세 일을 한다 — mbcp_stream_id 기록(:381), **밀린 편지 방출**(drain_pending_buf_and_mark_ready:409-434), 창구 등록(:391) 후 DCEP ACK(:396). 밀린 편지란: 채널이 열리기 전 도착한 broadcast 가 pending_buf 에 쌓여 있던 것 — ready 플래그가 서기 전(Ordering::Release, :433)까지의 편지를 순서대로 흘려보낸다. [판단] "채널 열리기 전 온 FLOOR_TAKEN 을 잃지 않는다"는 배려 — 잘 짜인 개설 의식. 라벨이 "unreliable"이 아니면 창구도 안 열고 ACK 도 안 보낸다(:384-389 else return) — 거부가 조용하지 않다(unknown_label 카운터).

### 2막 — 번역과의 거울
번역과는 이 우체국의 백미다. parse 와 build 가 거울처럼 마주 선다. 표준 필드(priority·duration·cause·queue_pos·granted_id·queue_size·ack_type)는 단순 왕복이고, 자체확장 둘(speaker_rooms·destinations)은 `count + [len+utf8]×count` 중첩 인코딩을 쓴다(parse:199-233, build:293-315). 30개 테스트가 왕복·순서보존·유니코드·절단·빈값생략을 조인다(:571-704). [판단] 3호 U5(두 개의 자)를 낳은 "조립기·해체기가 같은 자를 쓰는가"라는 질문을 여기 정면으로 들이대도 — **번역과는 통과한다.** parse 의 offset 전진(:150·:155)과 build 의 offset 전진(:324-331)이 같은 `2+len` 산수를 쓰고, 중첩 인코딩의 내부 커서(p)도 대칭(:203-213 vs :294-301). 그렸더니 안 빈 표다(§5).

단 한 필드가 거울에서 벗어난다: **duration.** parse 는 u16 을 정교하게 뽑는데(:163-168, 2바이트면 BE, 1바이트면 승격), 그 값을 **아무도 request 에 넘기지 않는다** — DC(:548)·WS(floor_ops.rs:128) 둘 다 `request(..., None)`. 정교한 파서가 허공을 뽑는다(기지 D1 의 wire 층 실증, →§9).

### 3막 — 등기와 유실, 한 방향으로만 도는 대장
이제 신뢰의 비대칭. 서버가 클라에게 보내는 편지 중 ACK 를 요구하는 것들(GRANTED·REVOKE — build 시 ack_req=1)은 T132 대장에 올라 재전송된다(mod.rs:333-343 등록, :636-677 재전송). 클라가 ACK 를 보내면 msg_type 매칭으로 대장에서 지운다(:308-319). C132_MAX 넘으면 포기하고 지운다(:651-656) — **포기를 클라에게 알리지 않는다.** floor 는 Taken 인데 클라는 GRANTED 를 못 받은 채 방치될 수 있다(→P1, 경합 좁음).

그런데 반대 방향엔 대장이 없다. 클라→서버 요청(REQUEST·RELEASE)이 SCTP 에서 유실되면? 채널이 maxRetransmits=0(transport.ts:481)이라 **SCTP 도 재전송 안 하고, 서버엔 재전송 대장도 없다**(pending_acks 는 서버 발신 전용). 서버는 REQUEST 를 아예 못 받았으니 침묵하고, 클라는 GRANTED 를 기다리며 멈춘다. WS 창구는 TCP 위라 이 유실이 없다(floor_ops.rs 주석 "WS 경로는 T132 재전송 없으므로 ACK 자체만"). **같은 floor 상태머신인데 bearer 에 따라 신뢰성 등급이 다르다**(→P2, 의문). [판단] "unreliable+0"은 저지연 우선의 의도적 선택일 수 있다 — PTT 는 놓친 버튼을 사람이 다시 누른다. 그러나 그 감수가 명문 결정인지 상속된 기본값인지는 소스에 없다.

임종 장면 하나 더: 국장이 AssociationLost 로 퇴장할 때(mod.rs:190-199) unreliable_tx/ready 는 내리지만 **floor 점유는 안 푼다.** DC task 종료 = publish DTLS 터널 붕괴 신호인데, 그 순간 이 user 가 발화 중이었다면 점유가 남는다 — 회수는 RTP-liveness(5s, tasks.rs:63-67)나 zombie reaper 에 위임된다. 2호 E1(좀비 floor 누락)의 상류가 여기다(→§9).

---

## 4. F2 — 관계 비교표

### parse 13필드 × 소비 방향 (편도인가 왕복인가)
| 필드 | parse 위치 | 서버 소비처 | 판정 |
|---|---|---|---|
| msg_type/ack_req | :126-127 | 분기·T132 | 왕복 |
| priority | :158-161 | request 인자(mod.rs:512) | 왕복 |
| **duration_s** | :163-168 (u16 정교) | **없음** (request..None) | **편도 파싱 — D1** |
| destinations | :218-232 | resolve_floor_target(:514) | 왕복(len>1 Deny) |
| cause/ack_type | :170-192 | ACK 매칭(:308) | 수신 왕복 |
| user_id(granted_id) | :180-182 | (수신 시 미사용 — 서버는 peer.user_id 신뢰) | 편도(수신측) |
| prev_speaker | :193-195 | (수신 시 미사용) | 편도(수신측) |
| speaker_rooms/via_room | :199-217 | (수신 시 미사용 — 서버 발신 전용 메타) | 편도(수신측) |

→ user_id/prev_speaker/speaker_rooms/via_room 은 **서버가 보낼 때만 채우고, 받을 때는 안 읽는다**(peer.user_id 를 신뢰). parse 가 이들을 뽑는 것은 클라 대칭 검증용 + 미래 대비. [판단] 편도 파싱이 결함은 아니다 — mbcp_native 는 양방향 공용 사전이라 방향별 미사용 필드가 자연스럽다. 단 duration 만은 "서버가 받아 쓰기로 한" 필드가 절단된 것(D1).

### 재전송 대장의 방향 (신뢰 비대칭)
| 방향 | 재전송 주체 | 근거 |
|---|---|---|
| 서버→클라 (GRANTED/REVOKE, ack_req=1) | 서버 T132 (pending_acks) | mod.rs:636-677 |
| 클라→서버 (REQUEST/RELEASE) | **없음** (SCTP maxRetransmits=0 + 서버 대장 없음) | transport.ts:481 | 
| WS bearer 전 방향 | TCP (SCTP 무관) | floor_ops.rs 주석 |

→ DC 요청 유실 = 무재전송 무통지 침묵(**P2**).

### DC bearer vs WS bearer — floor 창구 쌍둥이 대칭 (4호 반쪽 완성)
| 항목 | DC (mod.rs) | WS (floor_ops.rs) | 대칭 |
|---|---|---|---|
| has_half_duplex 게이트 | :487 | :65 | ✅ |
| REQUEST 대상 = destinations | :514 resolve_floor_target | :91 resolve_floor_target | ✅ |
| target room ≠ envelope 처리 | :531 room_hub.get(target) | :109-123 (분기) | ✅ |
| RELEASE 대상 = pub_room | :573 (감사 ③) | :163-171 (감사 ③) | ✅ |
| QUEUE_POS 폴백 | pub_room→**sub_rooms 임의 1방**(:598-603) | pub_room→**envelope room**(:186-188) | **❌ H13 재확인** |
| ACK(T132) | 서버 재전송 대장 有(:334) | "ACK 자체만"(재전송 無) | 설계 비대칭(P2) |
| Denied/Queued 회신 | dc_replies 직접 조립(:552-560) | send_floor_unicast_ws(:132-146) | ✅(경로만 다름) |

### cause code 생산 (표준 code vs 실 운반)
| 빌더 호출 | code 인자 | cause_text | 근거 |
|---|---|---|---|
| DC deny (route/room/floor) | **항상 1** | deny.cause_text() / "denied: …" | mod.rs:525·537·554 |
| WS deny (동일 3처) | **항상 1** | 동일 | floor_ops.rs:102·118·134 |
| REJECT_OTHER_ROOM_ACTIVE(100) | — | 정의만, 호출 0 | mbcp_native.rs:46 |

→ 표준 code 는 늘 BUSY(1), 진짜 사유는 cause_text 문자열이 운반. cross-room 거절 전용 code 100 은 사장(**P5**).

## 5. F3 — 대칭표 (빈칸)

### MBCP 6빌더 × via_room 동봉 (4호 D4 와 대조되는 건강 대칭)
```
build_granted    → via_room 동봉 ✅ (:359-366)
build_taken      → via_room 동봉 ✅ (:369-382)
build_idle       → via_room 동봉 ✅ (:385-391)
build_deny       → via_room 동봉 ✅ (:394-401)
build_revoke     → via_room 동봉 ✅ (:404-410)
build_queue_info → via_room 동봉 ✅ (:420-428)
```
→ **빈칸 없음.** 6빌더 전부 via_room 으로 "어느 방 사건인지" 클라 라우팅 키를 실는다(2026-04-25 정렬). [판단] 4호 D4(Speakers 방송 fallback 빈칸)와 정확히 대조 — 같은 파일군에서 floor 프레임은 via 대칭이 완벽하고 Speakers(svc 0x02)만 빠졌다. 음수 결과로 기록.

### svc 수신 처리 대칭
```
SVC_MBCP(0x01)     → handle_mbcp_from_datachannel ✅ (mod.rs:460)
SVC_SPEAKERS(0x02) → 카운트 후 reject ❌ (mod.rs:295·301 — 서버→클라 단방향, tasks.rs:299 발신)
0x80~0xFE (app)    → 카운트만 (:296)
```
→ Speakers 는 서버 발신 전용(active speaker 표시). 수신 카운터(unreliable_recv_speakers:295)는 정상 클라면 0 — 오작동/악성 탐지용 유령 카운터(**P6**, 경미).

### speaker_rooms 공급 (다방 형식 × 단방 공급)
```
mbcp_native 형식     → Vec<String> 다방 지원 (:108-111, "U가 R1,R2,R3 송출 중" UI)
floor_broadcast 공급 → publish_room() 단일방만 (:123-127, 0 or 1개)
```
→ 형식은 다방인데 공급은 1방. 다방 동시 발화(Phase 2)가 미구현이라 정합 — **잠복 자산**(결함 아님, 기록). resolve_floor_target 도 len>1 Deny(peer.rs:704-706)라 입구부터 단방 강제 — 일관.

## 6. F4 — 주석 증언 대조

| 증언 | 위치 | 대조 결과 |
|---|---|---|
| "클라이언트 sdk0.2/…/mbcp.ts 와 **정확히 대칭**" | mbcp_native.rs:5 | **부분 확인.** DC 라벨 실계약("unreliable" transport.ts:481)과 서버 수락(mod.rs:376) 일치. 단 dcep 테스트 픽스처는 "mbcp"(dcep.rs:161-175) — 실계약과 불일치하는 화석 → **P3** |
| "wire FIELD_DURATION 파싱되나 의도적 무시(None) — 미결" | mod.rs:547 · floor_ops.rs:127 | **자인 재확인.** parse 는 u16 정교(:163-168)한데 소비 0 — D1 의 wire 층 실증 |
| "R = Reserved (0)" / "V(2bit)=00 만 지원" | mbcp_native.rs:9·125 | **준수.** parse 가 V·R 무시하고 하위 4bit 만(:126), build 가 상위 4bit 0 보장(:321). 테스트 :777-785 |
| "count==1 만 허용 — ≥2 는 Denied(resolve_floor_target)" | mbcp_native.rs:106-107 | **배선 확인.** parse 는 다방 destinations 뽑되(:218-232) resolve_floor_target 이 len>1 Deny(peer.rs:704-706). 감사 20260703 destinations Deny 배선의 wire 층 |
| "SVC_PFLOOR=0x03 Pan-Floor 폐기" | mod.rs:48·mbcp_native.rs:431-434 | **준수.** 상수·빌더·TLV 0x10~0x13·테스트 전부 제거 확인(grep). 폐기 흔적을 git 좌표로 남김(모범) |
| "1~99 표준 예약 / 100+ OxLens 확장" REJECT_OTHER_ROOM_ACTIVE=100 | mbcp_native.rs:43-46 | **미배선.** build_deny 전부 code=1(§4 표) — 100 정의만 → **P5** |
| "unreliable pending drained" (ready 전 편지 보존) | mod.rs:409-434 | **준수 확인** — Ordering::Release 로 drain 후 ready. 개설 경합 안전 |

## 7. 발견 목록 (건조체, 신규 = P)

> **[확인]** = 소스/테스트 실증 · **[의문]** = 동작 확정, 결함 여부 판단 필요. 라이브 재현 미실행 — 심각도 잠정.

**P1 [확인/경미] T132 give-up 의 무통지 + floor 불일치 창** — check_retransmits 가 C132_MAX 초과 시 pending 을 조용히 swap_remove(mod.rs:651-656). 클라에 실패 통지 없음 → GRANTED 미수신 시 floor=Taken(서버) vs idle(클라) 불일치가 재전송 소진까지 지속. RTP-liveness(5s)나 클라 QUEUE_POS 폴링이 사후 정정. 경합 좁음(C132_MAX회 재전송 후).

**P2 [의문] DC bearer 요청 방향 무재전송 — bearer 간 신뢰 등급 비대칭** — 서버→클라는 T132 재전송 대장 보유(mod.rs:636-677)하나, 클라→서버 REQUEST/RELEASE 는 SCTP maxRetransmits=0(transport.ts:481) + 서버 수신 재전송 대장 부재. DC REQUEST 유실 = 무재전송·무통지 침묵(클라 무한 대기, 사람 재누름 의존). WS bearer 는 TCP 라 이 유실 없음(floor_ops.rs 주석). 같은 floor 상태머신의 bearer 별 신뢰성 등급 차이가 명문 결정인지 상속 기본값인지 소스에 근거 없음 — 결정 승격 필요.

**P3 [확인/문서] dcep 테스트 라벨 화석** — dcep.rs:161-175 테스트가 label="mbcp"·maxRetransmits=1 사용. 실 계약은 label="unreliable"·maxRetransmits=0(transport.ts:481, 서버 수락 mod.rs:376 DC_LABEL_UNRELIABLE). 서버 동작 정상(실 라벨 매칭)이나 테스트 픽스처가 실 wire 와 달라 미래 독자 오도 — 방법론 F4(주석·테스트 1급 증거)상 정정 대상. [자백: 서사 단계에서 "라벨 불일치 = DC 채널 영영 안 열림" 결함으로 의심했다가 클라 소스 실측으로 철회 → §8]

**P4 [의문/경합좁음] T132 ACK 의 msg_type-only 매칭** — pending_acks.retain(p.msg_type != ack_type)(mod.rs:312) 이 msg_type 만 비교. 같은 타입 두 편지 동시 pending(예: 재-GRANTED) 시 ACK 한 통이 둘 다 소거. 단일 floor·단일 assoc 이라 같은 타입 연속 pending 드묾 — 실질 경합 좁음. seq/nonce 부재.

**P5 [확인/경미] REJECT_OTHER_ROOM_ACTIVE(100) 사장 + cause code 뭉갬** — mbcp_native.rs:46 정의만, build_deny 호출 6곳 전부 code=1(BUSY) 하드코딩(mod.rs:525·537·554, floor_ops.rs:102·118·134). cross-room 거절도 BUSY 로 뭉개지고 진짜 사유는 cause_text 문자열이 운반. 클라가 표준 code 로 분기하면 오분류 — 현재 클라는 cause_text 표시라 무증상 [판단]. code 100 배선 또는 정의 제거 택일.

**P6 [확인/경미] SVC_SPEAKERS 수신 유령 카운터** — mod.rs:295 unreliable_recv_speakers 증가 후 :301 에서 svc!=MBCP reject. Speakers 는 서버→클라 단방향(tasks.rs:299 broadcast_dc_svc 발신). 정상 클라는 미발신 → 카운터 상시 0, 오작동/악성 탐지용으로만 의미. 죽은 관측점 후보.

**P7 [의문/경미] DC task 종료 시 floor 미해제** — run_sctp_loop 가 AssociationLost 로 break 시(mod.rs:190-199) unreliable_tx/ready 만 정리, floor.on_participant_leave 미호출. 발화 중 DTLS 붕괴 시 점유 잔류 → RTP-liveness(5s)/zombie reaper 위임. 2호 E1(zombie floor 누락)의 상류 트리거 — E1 수리(zombie 경로 floor 정리)가 이 경로도 커버하는지 확인 필요(DC 종료≠zombie 판정 즉시).

**관찰(결함 아님)**: build_frame len as u16 절단(mod.rs:54, MBCP 소형이라 무해) · 중복 unreliable OPEN 시 mbcp_stream_id 덮어쓰기 + channels 중복 push(mod.rs:381·391, 드묾) · ChannelType 6종 완비하나 국장 미사용(dcep.rs:34-57, 라벨만 판별) — 미래 대비 자산 [판단].

**영웅 명단 (음수 발견)**: MBCP 6빌더 via_room 균일 동봉(§5, D4 와 대조) · parse/build 거울 대칭 30테스트(U5 형 절단 결함 부재) · drain_pending_buf ready 경합 안전(Ordering::Release) · Pan-Floor 폐기의 git 좌표 박제(mbcp_native.rs:431-434) · destinations len>1 Deny 배선(감사 ③ wire 층) · unknown_label 조용한 거부 아님(카운터, mod.rs:387).

## 8. 자백 절 (서사 단계 오탐, 소스 회귀로 철회)

1. **DC 라벨 불일치 = 채널 미개설 결함 의심 → 철회.** dcep.rs 테스트가 label="mbcp"인데 서버는 "unreliable"만 수락(mod.rs:376)이라 "클라가 mbcp 를 보내면 DC floor 전체 사망"을 의심했다. **클라 실 소스 확인**(transport.ts:481 `createDataChannel('unreliable', ...)`)으로 실 라벨=서버 기대 일치 확정 — 테스트 픽스처만 화석(P3, 문서 격하). [판단] 4호 §9 교훈("부재·불일치 주장은 실측 전 결함이라 부르지 않는다")을 이번엔 crate 경계 밖(클라 TS) 실측으로 지켰다.
2. **speaker_rooms 다방 형식 vs 단방 공급 = 절단 결함 의심 → 철회.** 형식은 Vec 다방인데 공급은 publish_room 단일(floor_broadcast.rs:123)이라 U2(오디오 캐시)형 "약속-공급 절단"을 의심했으나, resolve_floor_target 입구부터 단방 강제(peer.rs:704) + Phase 2(다방 발화) 명시 이연(mbcp_native.rs:107)이라 **정합된 잠복 자산**으로 확정.

## 9. 교차 확인 절 — 전편 발견의 bearer 쪽 검증

| 전편 발견 | datachannel 쪽 확인 |
|---|---|
| **D1 (duration 미결)** | wire 층 실증. parse 가 u16 정교(mbcp_native.rs:163-168)한데 DC(mod.rs:548)·WS(floor_ops.rs:128) request(..None) — "정교한 파서가 허공을 뽑음" 확정. 배선 시 mbcp_native.duration_s 를 request 3인자로 넘기면 됨(파서는 이미 준비) |
| **D2 / H1 (floor release 경로)** | DC RELEASE = pub_room(mod.rs:573, 감사 ③ 준수) 재확인. 4호 H1(track_ops half→full 이 envelope room) 대조 — DC/WS 는 통일됐고 handler 의 3번째 경로만 누락이라는 4호 결론 재보강 |
| **D4 (Speakers fallback 빈칸)** | 근인 확정. SVC_SPEAKERS 는 build_frame(svc, ..) 로 DC 직송(floor_broadcast.rs:360), WS fallback 부재. 수신측도 DC 전용(mod.rs:301 reject) — DC 미수립 청취자(cross-sfu/affiliate)는 active speaker 영구 미달. floor 프레임(6빌더 via 대칭)과의 비대칭이 wire 층에서 재확인 |
| **destinations≥2 Deny (감사 20260703)** | 배선 wire 층 확인. parse 다방 추출(mbcp_native.rs:218-232) → resolve_floor_target len>1 Deny(peer.rs:704-706). 테스트 test_destinations_multi_room_roundtrip(:586)은 parse 왕복만 보증, Deny 는 domain 층 |
| **E1 (zombie floor 누락)** | 상류 트리거 발견 = P7. DC task 종료(AssociationLost)가 floor 미해제라 발화 중 DTLS 붕괴 시 점유가 zombie 판정까지 잔류. E1 수리 범위에 "DC 종료 경로"도 포함되는지 점검 필요 |

## 10. 방법론 기록 (실험 5호)

- **수확**: 신규 7건 — [확인] 4(P1·P3·P5·P6) · [의문] 3(P2·P4·P7) + 자가 철회 2(§8, 그중 1건은 crate 밖 클라 실측으로 철회).
- **장치별 기여**: P2·P1 = F2(재전송 방향 표 — "대장이 한 방향으로만 돈다") · P3 = F4(주석·테스트 vs 클라 실계약) · P5 = F2/F4(cause code 생산 표 + "1~99/100+" 주석 대조) · P6 = F3(svc 수신 대칭) · P7 = F2(bearer 종료 경로 vs floor cleanup). **§5 두 대칭표(via_room 6빌더·speaker_rooms 공급)는 그렸더니 안 비었다** — 음수 결과로 기록(D4 와 대조되는 건강 확인).
- **이번 막의 백미** [판단]: 없음 — 이 우체국은 **건강한 표적**이다. parse/build 거울(U5 형 결함 부재), via_room 6빌더 균일, 개설 경합 안전, 폐기 git 박제. 3호 udp·4호 handler 가 결함 밀집지였다면 datachannel 은 "잘 지어진 인프라"의 대조군이다. 수확이 경미(P1·P5·P6)·의문(P2·P4·P7)에 몰린 것 자체가 진단 — **번역/전송 계층은 성숙했고, 미결은 전부 상위(floor duration·cross-room·bearer 신뢰 등급) 정책 결정**이다.
- **crate 경계 교훈**: P3 오탐을 클라 TS(transport.ts) 실측으로 철회했다. 4호 E4 정정("부재 주장은 grep 범위 밖을 봐야")의 확장 — **불일치 주장은 대칭의 반대편(여기선 클라)을 실측하기 전 결함이라 부르지 않는다.** 서버 테스트 픽스처는 클라 실계약의 증거가 아니다.
- **한계**: 프라이밍 세션(판정 산입 불가) · 전 건 라이브 미재현(P2 의 유실 확률·P7 의 잔류 창은 실측 전 잠정) · sctp-proto 내부(청킹·SACK)는 외주라 무대 밖.

---

## 다음 단계 (부장님 결재 대상)

1. **P2 결정 승격** — DC bearer 요청 신뢰 등급(unreliable+0)이 명문 결정인가. WS 대비 floor 요청 유실 감수를 문서화하거나, 서버측 REQUEST 수신 확인(클라 재요청 트리거) 설계 판단.
2. **D1 배선 재확인** — mbcp_native.duration_s 파서는 준비 완료. request 3인자 배선 시 4호 문서 QueueEntry duration 칸(D1)과 묶어 처리.
3. **P7 ↔ E1 수리 범위 점검** — zombie floor 정리(E1) 수리 시 DC task 종료 경로도 커버하는지.
4. P3(테스트 라벨 정정)·P5(code 100 배선/제거)·P6(Speakers 수신 카운터 처분) 소청소 묶음.
5. 잔여 막: 무대 뒤(tasks·hooks·trace) · 성문 계층(stun·dtls·srtp) · oxhubd(H7 판정 걸림) — 별도 세션.

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. datachannel 3파일 1,770줄 전수. 신규 P1~P7(확인 4·의문 3) + 자가 철회 2(1건 클라 실측). 건강한 표적 대조군 — 미결은 전부 상위 정책 |
