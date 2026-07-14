// author: kodeholic (powered by Claude)
# 패킷의 여정 — transport/udp 영웅 서사시

**서사 기반 정적 분석 · 실험 기록 3호**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 전편: floor 3부작(1호) · domain 인구조사(2호)
표적: `crates/oxsfud/src/transport/udp/` **전체 12파일 6,534줄** (테스트 포함 전문 통독)

---

## 0. 실험 조건과 범위 (정직 신고)

- 프라이밍 세션 연속 — A/B/C 판정 산입 불가. 표기 규약: 행위 서술 = `파일.rs::함수:줄`, 판단 = `[판단]`.
- 통독: mod(594) · ingress(215) · ingress_publish(714) · ingress_subscribe(718) · ingress_rtcp(641) · rtcp(693) · rtcp_terminator(617) · twcc(1143) · egress(470) · auto_layer(294) · pli(127) · rtp_extension(320).
- 무대 밖(부분): stun/dtls/demux/srtp(transport 상위), config 상수, peer.rs 좌표 재참조. datachannel 하위는 본 막 범위 밖.

## 1. 무대 — 단일 소켓의 왕국

포트 하나로 모든 것이 들어온다. 첫 바이트로 신분을 가른다(mod.rs::run:240-247 — STUN/DTLS/SRTP/Unknown). 워커 N명이 같은 포트를 나눠 듣지만(SO_REUSEPORT, mod.rs:580-593) **시계와 나팔은 워커-0만 분다**: 3s 메트릭, 100ms BWE(TWCC/REMB+NACK), 1s RR+auto tick(mod.rs:254-274). 커널의 4-tuple 해시가 같은 클라이언트를 항상 같은 워커에 보내므로 한 peer의 패킷 처리는 자연 직렬이다. [판단] 이 무대 설계가 domain 막에서 본 "락 없는 원자 필드" 문화의 물리적 기반이다.

문지기의 의전: STUN이 오면 주소를 **걸쇠**(latch)로 물리고(mod.rs::handle_stun:381), 이사(NAT rebind)가 감지되면 DTLS 세션까지 통째로 이주시킨다(mod.rs:387-397, DtlsSessionMap::migrate:106-114). USE-CANDIDATE가 악수(DTLS)를 개시하고, 열쇠(SRTP)가 걸리는 순간 게이트가 열린다(mod.rs:489-517). 악수가 10초 안에 안 끝나면 `Failed` — 그리고 domain 막에서 봤듯 그 방은 편도다(mod.rs:548-557, 기지 E8).

## 2. 1막 — 세관 (ingress_publish)

미지의 SSRC가 도착하면 세관원은 **4계단 심문**을 한다(ingress_publish.rs::resolve_stream_kind:223-389): ① 기존 명부(by_ssrc/by_rtx_ssrc — fast path) ② rid 확장(simulcast 의도 보유 시) ③ rtx_pt 유일 매칭(intent 미제공 클라 폴백) ④ MID 확장. 전부 실패하면 "미지 — 다음 intent에서 해소"(:376-388, agg-log 관측 동반). 조용한 드롭이 없다 — 모든 기각에 사유 카운터가 붙는다. [판단] 07-03 감사가 심은 "조용한 드롭 금지" 문화가 이 파일에서 가장 잘 보인다.

RTX의 신원 학습은 3단이다: intent 실값(등록 시 색인) → repair_rid RTP-first 학습(:281-298) → rtx_pt 유일 매칭 학습(:301-322). 학습되면 cold path가 스스로 닫힌다(peer.rs::learn_rtx_ssrc:1021-1037). [판단] "조용한 최적화에 관측점을 단다"(:1027-1035)까지 포함해 모범.

그러나 이 세관에 **가드 없는 재-정지 단추**가 있다. helpers 경로는 "★ 새 구독에만 — ROOM_SYNC가 기존 구독에 매번 pause하면 영상 끊김(회귀)"이라는 비석과 함께 가드를 세웠는데(helpers.rs:473-476), 같은 일을 하는 notify 경로는 무가드다(ingress_publish.rs::notify_new_stream:671-676). 통지 선별이 **물리 트랙 단위**(!is_notified, :546-553)라 h/l 두 layer가 시차를 두고 등록되면 같은 논리 트랙이 **두 번 통지**되고, 멱등 반환된 기존 스트림에 5초 게이트가 다시 걸린다(발견 U1). h/l이 함께 출발하는 평시엔 무증상, h가 지각하는 바로 그 시나리오(작전1의 repub)에서 발현한다.

## 3. 2막 — 우편 체계의 세 가지 단절 (NACK/RTX)

구독자가 "n번 소포가 안 왔소"(NACK)라고 외치면, 우체국은 창고(rtp_cache)에서 사본을 꺼내 재발송(RTX)한다. 이 체계에 세 가지 단절을 발견했다.

### U2 — 오디오 소포는 애초에 창고에 안 들어간다
창고 주석은 이렇게 약속한다: "audio cache 신설 — PTT NetEQ collapse 정합. Audio 트랙도 NACK 응답 자료원 박힘"(publisher_track.rs:393-395, Phase C.2 v4 결재 b2). **전 소스에서 `cache.store` 호출은 두 곳뿐이고 둘 다 video 전용이다**(ingress_publish.rs:192 — `if stream_kind == Video` 안, :128 — video RTX 디캡슐). 오디오 캐시는 전 오디오 트랙에 **할당만 되고 한 번도 쓰이지 않는다**. 읽기 쪽도 이중 차단: PTT 오디오 NACK은 가상→실 SSRC 역매핑 없이 가상 SSRC로 publisher를 찾다 실패하고(ingress_subscribe.rs:511-513 — PttVideo 분기 :495-509는 역매핑함, F2 비대칭), 그 실패는 매번 `nack_pub_not_found` 경보 카운터를 울린다(:525-535). 회의 오디오라면 rtx_ssrc 부재로 조용히 끝난다(:548-563). **약속-배선-소비 3층이 전부 끊긴 유령 기능** — Phase C.2의 의도(수리 완성)인지 폐기 결정 누락인지 부장님 판정 필요.

### U5 — 두 개의 자(尺)
이 왕국엔 RTP 헤더 길이를 재는 자가 둘 있다. 바른 자는 X비트(헤더 확장)를 잰다 — `rtp_payload_offset`(ptt_rewriter.rs:425-439), egress의 인라인 계산(egress.rs:246-254), 확장 파서들(rtp_extension.rs:32-95, twcc.rs:44-113). 굽은 자는 `12+CC×4`에서 멈춘다 — `parse_rtp_header`(rtcp.rs:27-40, `header_len` 필드). 문제는 **RTX 소포의 겉봉(OSN) 위치를 굽은 자로 잰다**:

- 재발송 조립: `build_rtx_packet`(rtcp.rs:355-390)이 창고 원본의 payload를 `12+CC×4` 이후로 취한다. 원본에 확장이 있으면(실브라우저는 TWCC 확장 때문에 사실상 상시 X=1) **확장 블록이 OSN 뒤로 밀린 기형 패킷**이 나간다 — 수신 Chrome은 X=1을 보고 OSN 자리를 확장 헤더로 읽는다.
- 수신 해체: `process_rtx_packet`(ingress_publish.rs:100-119)이 같은 자로 OSN을 읽는다 — Chrome발 RTX(역시 확장 동반)에서 **확장 첫 2바이트를 원본 seq로 오독**할 수 있다.

[판단] 이것이 실환경에서 실제로 깨지는지는 미확정이다 — 2층 봇 픽스처가 X=0이면 회귀는 전부 통과하고(위양성), 서버 카운터(rtx_sent)는 송신만 증명하지 클라 수용을 증명하지 않는다. NACK 복구가 조용히 죽어 있고 그 공백을 PLI 에스컬레이션(NACK_ESC, ingress_subscribe.rs:597-614)이 메워 왔을 가능성이 있다. **판정 실측 지침**: ① 단위 — X=1(BEDE+TWCC ext) 원본으로 build_rtx_packet 왕복 파싱 시험 ② 라이브 — 수신측 getStats retransmittedPacketsReceived / pcap의 RTX 패킷 구조 육안.

### U6 — 회신 없는 음성 우체국
TWCC 회신(FB)은 video 트랙 보유자에게만 부친다 — `let ssrc = match video_ssrc { None => continue }`(egress.rs:108-114). 기록기는 kind 무관 전 패킷의 도착시각을 적는데(ingress_publish.rs:211-218), **오디오 전용 publisher(음성 무전!)는 회신을 영영 못 받는다**. transport-wide 신호의 media_ssrc는 명목상 아무 값이어도 되므로, 이 continue는 회의-영상 시절의 가정이다. [판단] 음성 PTT 송신측 GCC가 무신호로 도는 것 — Opus 저대역이라 실해는 작을 수 있으나, PTT가 주력 제품인 이상 "송신 혼잡 제어 부재"는 명시적 결정으로 승격해야 한다.

## 4. 3막 — 회신 제조창 (rtcp_terminator / ingress_rtcp)

서버는 두 세션의 종단이다: 수신자로서 RR을 **자기 통계로 직접 만들고**(rtcp_terminator.rs::RrStats — RFC 3550 A.1/A.3/A.8 충실 구현, probation·wraparound 포함), 송신자로서의 SR은 **절대 자작하지 않는다**. 기각 사유가 비석으로 서 있고("서버 클록 NTP → jb_delay 폭등", :318-321) — 백미는 그 기각을 주석이 아니라 **타입으로 강제**한 것이다: `build_sender_report`와 `wallclock_to_ntp`가 `#[cfg(test)]`로 물리 봉인되어 프로덕션에서 부를 수 없다(:322, :367). [판단] 기각 접근법 박제의 최상급 형태 — 방법론 F4가 찾아다니는 "금기"가 컴파일러 게이트가 된 사례.

SR은 번역만 한다: NTP 원본 유지, PTT는 slot rewriter의 같은 offset으로 ts 변환(ingress_rtcp.rs::build_sr_translation:429-453 — RTP forward와 동일 인스턴스라 자동 정합), simulcast는 현재 레이어 불일치 SR을 버린다(:472-477). 1PC 라우터는 분류표 전체가 테스트로 봉인됐다(ingress_rtcp.rs:514-640). 과거의 함정도 비석이 됐다: "RTCP PT에 `& 0x7F` 적용 시 PSFB 필터 무력화"(ingress_subscribe.rs:384-386).

## 5. 4막 — 기상 특무대 (auto_layer)

2호에서 예고한 대로 확인했다: 1초 tick이 `target.is_none() && effective != current`일 때 target을 놓으므로(auto_layer.rs:157-178) **v1/v2 모드에서는 h 재등장 승격이 1초 내 자가 치유**된다. 2호의 E2(promote_subscribers_high 옛 배관)는 **off 모드 전용 결함으로 확정** — off는 tick 자체가 안 돈다(mod.rs:271-273).

프로브 집행기는 절제가 몸에 뱄다: overuse 감지 즉시 중단(:222-227), egress 큐 포화 즉시 중단 — "프로브가 미디어를 밀어내면 본말전도"(:233-240), 완주 후에만 실측 반영(:244-249). [판단] 5일짜리 코드가 왕국에서 가장 신중한 인물이라는 2호의 관찰이 이 막에서도 유지된다.

## 6. F2/F3 — 표

### 두 개의 자 (헤더 길이 계산기)
| 사용처 | X비트 처리 | 근거 |
|---|---|---|
| rtp_payload_offset (키프레임 감지) | ✅ | ptt_rewriter.rs:425-439 |
| find_extension (rid/mid/twcc 파서) | ✅ | rtp_extension.rs:37-58, twcc.rs:49-77 |
| egress sr_stats payload 산출 | ✅ | egress.rs:246-254 |
| ensure_twcc_seq (스탬퍼) | ✅ | twcc.rs:562-612 |
| **parse_rtp_header.header_len → RTX OSN 위치** | **❌** | rtcp.rs:27-40 → ingress_publish.rs:100-119, rtcp.rs:355-390 |

### NACK 역매핑 4경로 (ingress_subscribe.rs::handle_nack_block)
| lookup_kind | 가상→실 SSRC | seq 역산 | RTX gate | 결과 |
|---|---|---|---|---|
| Simulcast | ✅ current rid | ✅ reverse_seq | ✅ :471 | 정상 |
| PttVideo | ✅ 화자 video | ✅ slot reverse | ✅ :497 | 정상 |
| **PttAudio** | **❌ 가상 그대로** :511-513 | ❌ | ❌ | pub_not_found 사망+경보 |
| Conference | (원본이라 불요) | 불요 | ❌ (video면 개인 rewriter 없음—해당 없음) | audio는 rtx_ssrc 부재로 사망 |

### 재-pause 가드
| 경로 | "새 구독에만" 가드 | 근거 |
|---|---|---|
| helpers::collect_subscribe_tracks | ✅ has_subscriber_stream_mid | helpers.rs:473-476 (회귀 비석 동반) |
| ingress notify_new_stream | ❌ | ingress_publish.rs:671-676 |

### 회신 대상
```
TWCC 기록   → 전 RTP (kind 무관)                ✅ ingress_publish.rs:211-218
TWCC 회신   → video 트랙 보유 publisher 만       ❌ 빈칸 egress.rs:108-114 (audio-only 미회신)
서버 RR     → 전 비-RTX 트랙 (audio 포함)        ✅ egress.rs:308-312
서버 NACK   → video 만 (nack_generator video 한정) — 설계 명시(audio RTX 미정합) publisher_track.rs:397-401
```

## 7. 발견 목록 (건조체)

**U2 [확인] 오디오 NACK 응답 사슬 3중 절단 + 유령 캐시** — 약속 주석(publisher_track.rs:393-395) vs `cache.store` 전수 2곳 video 전용(ingress_publish.rs:128·192) = 오디오 캐시 무기록. PttAudio NACK 미역매핑(ingress_subscribe.rs:511-513, PttVideo :495-509와 비대칭)으로 pub_not_found 사망 + 경보 오염(:525-535). audio rtx_ssrc 부재(:548-563). 메모리 낭비 RTP_CACHE_SIZE/트랙. 처분: 완성(store 배선+역매핑+same-ssrc retx 설계) 또는 폐기(캐시 할당 회수+주석 정정) 양자택일.

**U5 [의문/강] RTX OSN 위치의 굽은 자** — parse_rtp_header가 X비트 무시(rtcp.rs:27-40). 조립(rtcp.rs::build_rtx_packet:355-390)·해체(ingress_publish.rs::process_rtx_packet:100-119)가 이 header_len으로 OSN을 배치/추출 → 확장 동반 패킷(실브라우저 상시)에서 기형 RTX 왕복 개연. 봇 픽스처 X=0이면 회귀 위양성. **실측 전 결함 단정 금지** — 판정 지침 §3 (X=1 왕복 단위시험 + 수신측 retransmittedPacketsReceived).

**U1 [확인/조건부] notify 경로 중복 통지 + 게이트 재-pause 무가드** — 물리 트랙 단위 통지 선별(ingress_publish.rs:546-553)로 h/l 시차 등록 시 같은 논리 트랙 재통지, 기존 스트림에 5s pause 재적용(:671-676). helpers 가드(helpers.rs:473-476)와 비대칭. 발현: h 지각(작전1 repub) — E2·U1이 같은 시나리오에서 겹침.

**U6 [확인/의문-영향] TWCC 회신 video 전용** — egress.rs:108-114. 오디오 전용(음성 PTT) publisher 는 TWCC FB 미수신 → 송신 GCC 무신호. 의도 여부 결정 승격 필요.

**U3 [확인/경미] PLI 버스트 취소/저장 범위 비대칭** — 취소는 peer 전 Stream(pli.rs:56 → peer.rs:723-727), 저장은 대상 Stream 1(pli.rs:123-125). camera 버스트가 무관한 screen 버스트를 abort. multi-source publisher 한정.

**U7 [확인/이론] mid>255 별칭** — ingress_publish.rs:634 `mid_u8 = … else 0` — 절단이 skip이 아니라 mid 0 위장(기존 mid 0 스트림 멱등 반환), wire 통지는 실 mid(u32). 2호 E7의 확장. 도달 곤란 — 기록만.

**관찰(결함 아님)**: 100ms NACK/TWCC 타이머가 전 방×전 참가자×전 트랙 순회(egress.rs:38-90) — 현 규모 무해, capacity 시험 시 재조명 [판단]. detect_video_rtp_gap이 peer 단위 집계라 multi-video-track에서 개별 트랙 gap 은폐(ingress.rs:189-213) — F4 in-band demote가 실질 커버.

**영웅 명단 (음수 발견)**: twcc.rs — 빌더/파서 상호 역함수 시험(:1059-1080)에 스탬퍼는 바른 자 사용. rtcp_terminator.rs — 기각 접근법의 `#[cfg(test)]` 물리 봉인(:322·:367). ingress_rtcp.rs — 1PC 분류표 전수 시험. auto_layer.rs — 전환 중 무개입 규칙(:11-14)으로 F4와의 경합을 규칙으로 해소.

## 8. 방법론 기록 (실험 3호)

- 신규: 확인 4(U1·U2·U3·U7) + 의문 2(U5·U6). U2·U5가 주요.
- 장치 기여: U2 = **F4 정면**(주석의 약속 vs grep 전수 배선 0 — Engler식 belief 위반의 교과서 사례, n=1 주석으로 성립). U5 = **F3**(같은 일을 하는 계산기 대칭표에서 한 칸만 굽음). U1 = F2(helpers/notify 쌍대). U6 = F3(회신 대상 표의 빈칸).
- 2호와의 연쇄: E2의 발현 조건이 본 막에서 확정(off 전용), U1이 같은 시나리오에 겹침 — **막 간 교차 검증이 단독 막보다 정밀도를 올린다** [판단].
- 한계: U5는 서사가 만든 가장 위험한 부류의 후보다 — 이야기가 아름답다(두 개의 자). §5.2 규율대로 실측 전 "결함"이라 부르지 않는다.

## 다음 단계 (부장님 결재 대상)

1. **U5 실측** (X=1 왕복 단위시험 1개면 판정 — 최우선 [판단])
2. U2 처분 양자택일(완성 vs 폐기), U6 결정 승격, U1·U3 소수리
3. 잔여 막: datachannel(1.6k) · signaling/handler(3.4k) · tasks/hooks — 별도 세션 권고(주의력 신선도)

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. udp 12파일 6,534줄 전수. 신규 U1~U7(확인 4·의문 2·이론 1) + 영웅 명단 |
