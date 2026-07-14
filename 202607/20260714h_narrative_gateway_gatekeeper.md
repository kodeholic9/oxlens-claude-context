// author: kodeholic (powered by Claude)
# 성문의 문지기 — STUN·DTLS·SRTP·demux 경비 열전

**서사 기반 정적 분석 · 실험 기록 7호**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 전편: floor(1)·domain(2)·udp(3)·handler(4)·datachannel(5)·backstage(6)
표적: `crates/oxsfud/src/transport/` 성문 계층 7파일 **904줄** (stun·dtls·srtp·demux·demux_conn·ice·mod, 테스트 포함 전문 통독, 하위 에이전트 위임 없음)

---

## 0. 실험 조건과 표기 규약 (정직 신고)

- **프라이밍 세션 연속** — 방법론 + 전편 6편 숙지. **§6.1 A/B/C 판정 산입 불가.** 산출물 가치 = 미답 표적 재현성 + 3호 §1 "문지기 의전"(서사만 서술)의 소스 실증.
- 통독: stun(381) · dtls(131) · srtp(167) · demux(65) · demux_conn(105) · ice(44) · mod(11). 테스트 4블록 포함 전문.
- 무대 밖 확인(부분 열람): transport/udp/mod.rs(handle_stun 전문 466~530, accept_dtls·export_srtp_keys 483~500) · domain/peer.rs(inbound/outbound_srtp·install_srtp_keys:158~221·session) · domain/peer_map.rs(latch_addr·find_by_ufrag·by_addr) · config.rs(DEMUX 상수) · lib.rs(201, fingerprint 로그).
- 표기: 행위 = `파일.rs::함수:줄` 전체 형식. 판단·은유 = [판단]. 발견 = [확인](소스 실증) / [의문](동작 확정, 결함 여부 판단 필요).
- 기지 제외: D·E·U·H·P·BS 계열은 신규 집계 제외. 성문 계층이 3호 §1 의전의 실체이므로 교차 확인은 §9.

---

## 1. 무대 — 하나의 문, 첫 바이트로 갈래

포트 하나로 STUN·DTLS·SRTP 가 전부 들어온다(RFC 5764 Bundle). 성문 앞에 선 첫 문지기는 **첫 바이트만 본다**(demux::classify:20-31). 0x00~0x03=STUN, 0x14~0x3F=DTLS, 0x80~0xBF=SRTP, 그 외 Unknown — RFC 5764 §5.1.2 의 정본 범위를 config 상수로 뽑았다(config::DEMUX_*). [판단] 문지기가 여권을 펴보지 않고 표지 색만 보고 창구를 배정하는 격 — 빠르고, 이 단계의 판별은 프로토콜 종류일 뿐 신원이 아니다. 신원 검문은 안쪽 세 창구가 각자 한다.

무대의 물리 사실 셋:

1. **서버는 controlled agent 다.** ICE-Lite(ice.rs:4-8) — candidate 수집도 연결성 검사 발신도 안 하고, 클라 STUN Binding Request 에만 응답한다. 통행증(ufrag 8자 / pwd 22자)만 발급하고(ice.rs:20-26) 검문 자체는 udp/mod.rs::handle_stun 이 한다(ice.rs:10-11 자인).
2. **밀실 악수는 passive.** DTLS 는 서버가 늘 수동(dtls.rs:80 `is_client=false`). self-signed cert 생성(dtls.rs:37-48), extended_master_secret Require(다운그레이드 방어, dtls.rs:61). 악수 후 RFC 5705→5764 로 SRTP 키 60바이트를 뽑는다(dtls.rs:104-121).
3. **봉인은 두 방향, 두 열쇠.** SRTP client_key=inbound(브라우저→서버 복호), server_key=outbound(서버→브라우저 암호)(dtls.rs:5-8, peer.rs:220-221). 방향이 정확히 갈린다.

## 2. 등장인물

### demux::classify — 첫인상 문지기 (demux.rs:20)
첫 바이트로 프로토콜을 가른다. 빈 버퍼는 Unknown(:21-23). 성격: **판단하지 않고 분류만 한다.** RFC 5764 정본 범위를 상수로 위임 — 매직넘버를 config 로 뽑은 모범. 테스트가 STUN/DTLS/SRTP/빈/미지 5경계를 조인다(:37-64). 건강.

### stun::parse / verify — 신분 검문소 (stun.rs:64·196)
STUN 메시지를 zero-copy 로 뜯고(:64-123), MESSAGE-INTEGRITY 를 HMAC-SHA1(ICE pwd 키)로 검증한다(:196-222). 성격: **엄격하게 뜯고 상수시간으로 비교한다** — magic cookie 검사(:78), length %4 검사(:83), 경계 초과 시 break(:103), MI 비교는 constant-time(:216-221). MI 앞부분까지만 HMAC(길이 필드 조정, :210-213) — RFC 정본 절차. [판단] 검문소 자체는 정확하다. 문제는 이 검문소를 **언제 통과시키는가**이며, 그 순서 결정은 검문소 밖(handle_stun)에 있다(→GW1).

### handle_stun — 걸쇠 담당관 (udp/mod.rs:466, 무대 밖)
STUN 을 받아 주소를 걸쇠(latch)로 물리고 응답한다. 성격: **먼저 물리고 나중에 검문한다** — ufrag 로 peer 를 찾아 latch_addr(주소 확정)·ICE migration(DTLS/SCTP 이주)·last_seen(연명)을 실행한 **뒤에야** MESSAGE-INTEGRITY 를 검증한다(udp/mod.rs:485-524). 이 순서가 3막의 비극이다(→GW1).

### accept_dtls — 밀실 악수관 (dtls.rs:71)
passive DTLS 핸드셰이크. 성격: **상대 얼굴을 확인하지 않는다** — `insecure_skip_verify: true`(dtls.rs:62). self-signed 를 수락하되, **클라 cert fingerprint 를 대조하지 않는다**(WebRTC 표준의 SDP a=fingerprint 검증 부재 — SDP-free 구조). 악수 성공 = 암호화 채널이되 endpoint 인증은 ICE pwd 에 위임(→GW2).

### SrtpContext — 봉인관 (srtp.rs:16)
webrtc-srtp 래핑. install_key 전엔 KeyNotInstalled 로 전부 거부(:26-42). 성격: **열쇠 없이는 아무것도 열지 않는다** — Option<Context> None 게이트가 네 메서드(en/decrypt rtp/rtcp) 모두에 균일(:48-86). roundtrip 테스트가 봉인/개봉 대칭을 조인다(:145-166). 건강.

### DemuxConn — 가상 회선 (demux_conn.rs:31)
실 UDP 소켓과 DTLSConn 사이의 어댑터. peer_addr 를 Arc<RwLock> 로 공유해 STUN re-latch 시 외부 갱신을 받는다(:27-28·72). 성격: **주소를 한 곳에 모아 원자로 바꾼다** — send 는 read lock, migration 은 write lock(:76-82). recv 는 채널에서 읽되 buf 초과분을 조용히 자른다(:63, →GW5).

### IceCredentials — 통행증 발급소 (ice.rs:15)
ufrag/pwd 를 getrandom 으로 뽑는다(:21-26). 성격: **무작위를 36진수로 접는다** — `b % 36`(:36)이 256 을 36 으로 접어 미세 편향(→GW4). Default 미구현(→GW6).

## 3. 3막

### 1막 — 첫 바이트의 평화
패킷이 온다. 첫 문지기가 첫 바이트로 창구를 배정한다(demux::classify). STUN 은 검문소로, DTLS 는 밀실로, SRTP 는 봉인관으로. 이 분류는 신원이 아니라 종류라 빠르고 흠이 없다 — RFC 5764 정본, config 상수, 테스트 5경계. **이 막은 건강하다.**

### 2막 — 검문소의 뒤바뀐 순서
STUN Binding Request 가 검문소(handle_stun)에 온다. 정석이라면 순서는 "신원 확인(MI) → 확정(latch)"이다. 그러나 담당관은 반대로 한다(udp/mod.rs:466-524):

1. username 에서 server_ufrag 추출(:476-481)
2. **latch_addr(ufrag, remote)** — 주소를 걸쇠로 물림(:485)
3. **ICE migration** — old≠remote 면 DTLS/SCTP 세션을 remote 로 이주(:490-500)
4. **last_seen 갱신** — liveness 연명(:502)
5. **그 다음에야** verify_message_integrity(:519)

그리고 latch_addr 는 즉시 부작용을 낸다 — session.latch_address(addr) 로 세션 주소를 확정하고, **by_addr 인덱스(SRTP hot-path 의 addr→peer 조회 키)에서 old 주소를 제거하고 remote 를 삽입한다**(peer_map.rs:latch_addr 본문, `by_addr.remove(old_addr)` + `insert(addr)`). MI 검증은 그 **뒤에** 오고, 실패하면 return 할 뿐 **1~4 를 롤백하지 않는다**(udp/mod.rs:519-523).

[판단] 이것이 이번 막의 비극이다. **ufrag 만 아는 자가 유효한 MESSAGE-INTEGRITY 없이 STUN Binding Request 를 보내면**, 검문(MI)에서 응답은 못 받지만 그 전에:
- by_addr 인덱스가 그 자의 주소로 교체 → 정상 클라의 미디어 수신 경로가 끊기고 서버 SRTP egress 가 그 주소로 향함(미디어 탈취 또는 DoS)
- DTLS/SCTP egress 도 그 주소로 이주(migrate)
- last_seen 연명으로 zombie reaper 회피

RFC 8445/8489 는 연결성 검사를 MESSAGE-INTEGRITY 로 인증한 **후에만** candidate 를 확정하라 한다. 여기선 확정이 인증을 앞선다. 정상 클라의 주기적 consent STUN 이 곧 재latch 하므로 탈취 창은 STUN 주기만큼이나, "인증 전 상태 변경"은 명백한 순서 결함이다. 완화 요인: ufrag 는 시그널링(WSS)로만 노출 + off-path 는 8자 random(36^8≈2.8조) 추측난 + remote 주소 스푸핑 필요(BCP 38 미적용 망 한정). 그러나 on-path(동일 NAT·스니핑) 공격자에겐 문이 열려 있다. 라이브 재현 전이므로(§5.2) "결함"이 아니라 강한 [확인]으로 둔다 — 소스 순서가 명백히 인증을 뒤에 둔다(→GW1).

### 3막 — 밀실은 얼굴을 안 본다
DTLS 악수관이 클라와 밀실에서 악수한다(accept_dtls). extended_master_secret 를 Require 로 다운그레이드를 막고(dtls.rs:61), 악수 후 SRTP 키 60바이트를 정확한 방향으로 뽑아 봉인관에 심는다(client=inbound, server=outbound — peer.rs:220-221, RFC 5764 §4.2 정합). 봉인은 흠이 없다.

그러나 악수관은 상대 얼굴을 확인하지 않는다 — `insecure_skip_verify: true`(dtls.rs:62). WebRTC 표준(RFC 8827)은 DTLS cert 의 fingerprint 를 시그널링(SDP a=fingerprint)으로 교환해 악수 상대가 그 시그널링 주체와 동일함을 대조한다 — MITM 방지의 핵심. 이 서버는 SDP-free 라 그 대조 채널이 없고(dtls.rs 주석·lib.rs:201 은 **서버 자기** fingerprint 만 로그), 결과적으로 **endpoint 인증축이 DTLS-fingerprint 에서 ICE pwd(STUN MI)로 옮겨져 있다**. 그런데 2막에서 봤듯 그 MI 마저 부작용(latch)을 게이트하지 못한다. [판단] SDP-free 는 설계 선택이고 ICE pwd 로 인증을 모으는 것도 일관된 판단일 수 있으나, 그 단일 인증축(MI)이 GW1 에서 새면 성문 전체가 ufrag 유출 하나에 걸린다 — GW1 과 GW2 는 독립 결함이 아니라 **같은 인증축의 앞뒤**다(→GW2).

---

## 4. F2 — 관계 비교표

### handle_stun 실행 순서 vs 정석 (인증 게이트 위치)
| 단계 | 현행 순서 | 정석(RFC 8445) | 근거 |
|---|---|---|---|
| ufrag 추출 | 1 | 1 | udp/mod.rs:476-481 |
| latch_addr(by_addr 교체) | **2** | 인증 후 | udp/mod.rs:485 · peer_map latch_addr |
| ICE migration(DTLS/SCTP 이주) | **3** | 인증 후 | udp/mod.rs:490-500 |
| last_seen 연명 | **4** | 인증 후 | udp/mod.rs:502 |
| **MESSAGE-INTEGRITY 검증** | **5** | **2 (확정 전)** | udp/mod.rs:519 |
| 실패 시 롤백 | **없음(return만)** | 확정 안 했으니 불요 | udp/mod.rs:519-523 |

→ 확정(2~4)이 인증(5)을 앞선다 = 인증 전 상태 변경(**GW1**).

### SRTP 키 방향 (건강 대칭 — 음수 검증)
| 열쇠 | 방향 | 용도 | install 대상 | 근거 |
|---|---|---|---|---|
| client_key/salt | 브라우저→서버 | decrypt(inbound) | inbound_srtp | dtls.rs:5-6 · peer.rs:220 |
| server_key/salt | 서버→브라우저 | encrypt(outbound) | outbound_srtp | dtls.rs:7-8 · peer.rs:221 |

→ RFC 5764 §4.2 layout 과 install 방향 완전 일치. 그렸더니 안 빈 표(음수 결과).

### 인증축 (SDP-free 의 대가)
| 인증 수단 | 표준 WebRTC | 이 서버(SDP-free) | 근거 |
|---|---|---|---|
| DTLS cert fingerprint 대조 | ✅ SDP a=fingerprint | **❌ insecure_skip_verify** | dtls.rs:62 |
| STUN MESSAGE-INTEGRITY(ICE pwd) | ✅ | ✅ (단 GW1 로 부작용 미게이트) | stun.rs:196 · udp/mod.rs:519 |

→ 인증이 MI 단일축인데 그 축이 GW1 에서 샌다(**GW2** ↔ GW1 결합).

## 5. F3 — 대칭표 (빈칸)

### STUN 견고성 검사 (build vs verify)
```
magic cookie   → parse 검사 ✅ (stun.rs:78)
length %4      → parse 검사 ✅ (stun.rs:83)
MESSAGE-INTEGRITY → build 有(:178) · verify 有(:196) ✅
FINGERPRINT    → build 有(:186) · verify ❌ 빈칸 (수신 STUN 의 CRC 무검증)
```
→ FINGERPRINT 를 만들되 받은 것은 안 본다(**GW3**). demux first-byte 가 이미 프로토콜을 구분하므로 STUN-vs-타프로토콜 견고성 역할은 중복 — 실해 낮음 [판단], 표준 체크 생략으로 기록.

### SrtpContext 키-미설치 게이트 (4메서드 대칭)
```
decrypt_rtp  → None → KeyNotInstalled ✅ (:48-50)
decrypt_rtcp → None → KeyNotInstalled ✅ (:58-60)
encrypt_rtp  → None → KeyNotInstalled ✅ (:68-70)
encrypt_rtcp → None → KeyNotInstalled ✅ (:78-80)
```
→ 빈칸 없음. 네 방향 균일 게이트(음수 결과, 건강).

## 6. F4 — 주석 증언 대조

| 증언 | 위치 | 대조 결과 |
|---|---|---|
| "For ICE, the key is simply the password of the peer being authenticated" | stun.rs:225 | **준수.** handle_stun 이 session.ice_pwd 로 MI 키 생성(udp/mod.rs:518). 단 검증 시점이 latch 뒤(GW1) |
| "insecure_skip_verify: true" (주석 없음, self-signed 수락) | dtls.rs:62 | **의문.** WebRTC self-signed 는 정상이나 fingerprint 대조 부재 = SDP-free 대가. 명시 결정 주석 없음 → GW2 |
| "peer_addr를 Arc<RwLock>로 공유하여 STUN re-latch 시 외부에서 갱신 … SCTP/DTLS egress가 갱신된 주소로 전송" | demux_conn.rs:11-13 | **정합 확인** + **GW1 의 부작용 경로 자인** — re-latch 가 egress 주소를 바꾼다는 것이 곧 인증 전 latch 의 위험 표면 |
| "STUN Binding Request 처리 자체는 udp/mod.rs handle_stun 이 담당 — 이 모듈은 credentials 생성만" | ice.rs:10-11 | **준수.** 검문 로직이 handle_stun 에 집중 — GW1 의 좌표가 여기로 확정 |
| "context param MUST be &[] (empty), otherwise ContextUnsupported" | dtls.rs:102-103 | **준수.** export_keying_material(label, &[], len)(:109) — 함정 회피 명문 |

## 7. 발견 목록 (건조체, 신규 = GW)

> **[확인]** = 소스/테스트 실증 · **[의문]** = 동작 확정, 결함 여부 판단 필요. 라이브 재현 미실행 — 심각도 잠정.

**GW1 [확인/보안-주요] handle_stun 인증 전 상태 변경 — latch/migration/liveness 가 MI 검증에 선행** — udp/mod.rs:485-502 가 latch_addr(주소 확정 + by_addr 인덱스 old 제거/remote 삽입) · ICE migration(DTLS/SCTP egress 이주) · last_seen 갱신을 실행한 뒤, :519 에서야 verify_message_integrity. 실패 시 return 만(롤백 없음, :519-523). ufrag 만 아는 자가 유효 MI 없이 STUN 을 보내면 by_addr 이 그 주소로 교체 → 정상 클라 미디어 경로 절단 + 서버 SRTP/DTLS egress 탈취 + reaper 회피. RFC 8445/8489 위반(연결성 검사 인증 후 확정). 완화: ufrag WSS 노출 한정 + off-path 추측난(36^8) + 주소 스푸핑 필요. on-path 공격 노출. 수리 방향(참고): verify_message_integrity 를 latch/migration 앞으로 이동(인증 실패 시 무부작용 return). **라이브 실측 지침**: 유효 ufrag + 무효 MI STUN 주입 후 by_addr 갱신·egress 주소 변화 관측.

**GW2 [의문/보안] DTLS fingerprint 대조 부재 — 인증 단일축(MI)의 취약 결합** — dtls.rs:62 insecure_skip_verify=true + SDP-free 로 클라 cert fingerprint 미대조(RFC 8827 표준의 SDP a=fingerprint 검증 없음). endpoint 인증이 ICE pwd(STUN MI) 단일축에 의존 → 그 축이 GW1 에서 부작용 미게이트. SDP-free 설계 선택의 대가인지, MI 가 GW1 수리로 견고해지면 수용 가능한지 부장님 판정. 명시 결정 주석 부재.

**GW3 [확인/경미] STUN FINGERPRINT 수신 무검증** — stun.rs 가 build_binding_response 에 FINGERPRINT 를 넣되(:186) 수신 STUN 의 CRC 는 verify_message_integrity 도 parse 도 검사 안 함. demux first-byte 분류(demux.rs:20)가 프로토콜 구분을 이미 하므로 STUN 견고성 역할 중복 — 실해 낮음. 표준 체크 생략 기록.

**GW4 [확인/경미] ICE 문자열 modulo bias** — ice.rs:36 `b % 36` 이 256 을 36 으로 접어 문자 0~3(값 '0'~'3')이 미세 과다(256=7×36+4). ufrag 8자/pwd 22자 엔트로피 약간 편향. getrandom 소스는 CSPRNG 라 실질 추측난 유지 — 경미. rejection sampling 으로 균등화 가능.

**GW5 [확인/경미] DemuxConn.recv 조용한 절단** — demux_conn.rs:63 `data.len().min(buf.len())` 로 DTLS 레코드가 buf 초과 시 무경고 절단. DTLS 레코드는 MTU 이하 + 호출자 buf 2048(mod.rs)이라 실발생 곤란 — 무해하나 silent truncation.

**GW6 [의문/경미] IceCredentials Default 미구현** — ice.rs:20 new() 만, Default 없음. clippy new_without_default 후보. 관례 정리감.

**관찰(결함 아님)**: STUN MI constant-time 비교(stun.rs:216-221) · XOR-MAPPED-ADDRESS IPv4/IPv6 정확(port^0x2112, IP^cookie/tid, :241-270) · build_binding_response length 3단 갱신 정확(MI/FP 자기포함, :174-190) · compute_hmac_sha1 expect 안전(HMAC 임의 키 길이, :277) · DemuxConn peer_addr RwLock 원자 migration · extended_master_secret Require(다운그레이드 방어).

**영웅 명단 (음수 발견)**: SRTP 4메서드 키-게이트 균일 + roundtrip 테스트 · SRTP 키 방향 정확(RFC 5764 §4.2) · STUN MI HMAC-SHA1 상수시간 · demux classify RFC 5764 정본 + 5경계 테스트 · export_keying_material context=&[] 함정 회피 명문 · DemuxConn RwLock migration 원자.

## 8. 자백 절 (서사 단계 판정 교정)

1. **GW3(FINGERPRINT 무검증)을 처음 "보안 결함"으로 의심 → "경미"로 격하.** 수신 STUN 의 FINGERPRINT CRC 를 안 보는 것을 무결성 구멍으로 세웠다가, (a) 진짜 인증은 MESSAGE-INTEGRITY(HMAC-SHA1 ICE pwd)이고 (b) STUN-vs-타프로토콜 견고성 판별은 demux first-byte(demux.rs:20)가 이미 수행함을 확인 — FINGERPRINT 는 표준 견고성 보조일 뿐 인증 아님. 격하. [판단] "검증 안 함"이 다 결함은 아니다 — 그 검증이 **무엇을 위한** 것인지(인증 vs 견고성)를 가른 뒤 심각도 판정.
2. **SRTP 키 방향 오배선 의심 → 철회.** client_key 를 outbound 에 심었을까 의심했으나 peer.rs:220-221(inbound←client, outbound←server) + dtls.rs:5-8 layout 이 RFC 5764 §4.2 와 정확히 일치 — 음수 결과로 §4 표 기록.

## 9. 교차 확인 절 — 3호 §1 의전의 소스 실증

| 3호 서술 | 성문 계층 소스 확인 |
|---|---|
| "STUN 이 오면 주소를 걸쇠(latch)로 물리고" | latch_addr(peer_map) 실체 확인 + **순서 결함 발견 = GW1** (3호는 의전만 서술, 순서 미검) |
| "이사(NAT rebind) 감지되면 DTLS 세션까지 통째 이주" | udp/mod.rs:490-500 migrate 확인 — GW1 의 부작용 경로(인증 전 이주) |
| "USE-CANDIDATE 가 악수 개시, 열쇠(SRTP)가 걸리는 순간 게이트" | accept_dtls→export_srtp_keys→install(peer.rs:220) 사슬 확인. has_use_candidate(stun.rs:138) 존재하나 handle_stun 이 소비하는지는 무대 밖(별건) |
| "악수 10초 안 끝나면 Failed, 그 방은 편도(기지 E8)" | udp/mod.rs:483 timeout(accept_dtls) 확인 — MediaState::Failed 편도(2호 E8)의 상류 |
| "락 없는 원자 필드 문화의 물리 기반(4-tuple 해시)" | DemuxConn RwLock peer_addr + by_addr DashMap — migration 원자성 확인 |

[판단] 3호가 "문지기의 의전"을 아름답게 서술했으나 **순서를 검증하지 않았다.** 7호가 그 의전의 소스를 열어 latch 가 인증을 앞선다는 것을 발견했다 — 서사가 매끄러우면(§5.2) 그 매끄러움이 순서 결함을 덮는다. 3호 서술 "주소를 물리고 … 이주시킨다"의 **접속사 순서**가 곧 결함이었는데, 서사 독자(당시 나)는 그 순서를 정상 의전으로 읽었다. 방법론 교훈: **서술한 동작의 순서도 소스로 검증 대상** — "A 하고 B 한다"의 A→B 가 정석 순서인지 물어야 한다.

## 10. 방법론 기록 (실험 7호)

- **수확**: 신규 6건 — [확인] 4(GW1·GW3·GW4·GW5) · [의문] 2(GW2·GW6) + 자가 철회/격하 2(§8).
- **장치별 기여**: GW1 = **F2(실행 순서표 — 현행 vs 정석 인증 게이트 위치)** + 3호 서사 순서 재검(§9) · GW2 = F2(인증축 표, SDP-free 대가) · GW3 = F3(build vs verify 견고성 빈칸) · GW5 = F4/코드(silent 절단) · SRTP 방향·게이트 = F2/F3 음수(건강).
- **이번 막의 백미** [판단]: GW1. 6호 BS1(방향 반전)에 이어 미답 표적에서 보안-주요 1건 — 성문 통독의 정당성 실증. 그리고 **§9 교훈이 방법론에 새 규율 제안**: 전편이 서술한 **동작의 순서**(latch → migrate)를 후편이 소스로 재검하니 결함이 나왔다. 서사는 "무엇을 하는가"를 잡지만 "**어떤 순서로** 하는가"는 소스를 열어야 한다 — 매끄러운 접속사("~하고 ~한다")가 순서 결함을 숨긴다. 4호 E4(부재 주장)·6호 BS1(상수 방향)에 이은 세 번째 "실측 없이 넘긴 것" 족보.
- **음수 결과 기록**: SRTP 키 방향·4메서드 게이트·demux 분류·STUN MI 상수시간은 전부 건강. 성문 계층은 표준 구현이 깔끔하되(암호 primitive 는 검증된 crate 위임) **정책 순서(GW1)와 SDP-free 인증축(GW2)** 두 곳이 뚫린 형태.
- **한계**: 프라이밍 세션(판정 산입 불가) · GW1·GW2 라이브 미재현(심각도 잠정) · 암호 primitive(webrtc-srtp/dtls/hmac)는 외부 crate(무대 밖) · handle_stun 은 무대 밖(udp/mod.rs) 부분 열람 — GW1 좌표는 확정이나 has_use_candidate 소비 등 주변은 별건.

---

## 다음 단계 (부장님 결재 대상)

1. **GW1 수리 결재(보안)** — verify_message_integrity 를 latch_addr/migration/last_seen **앞으로** 이동, 인증 실패 시 무부작용 return. 라이브 실측(무효 MI STUN 주입 → by_addr 불변 확인)으로 게이트.
2. **GW2 설계 판정** — SDP-free 의 DTLS fingerprint 미대조가 의도된 대가인지, GW1 수리 후 MI 단일축으로 충분한지. 명시 결정 주석화.
3. GW3(FINGERPRINT verify 추가 여부)·GW4(rejection sampling)·GW5(절단 경고)·GW6(Default) 소청소.
4. 잔여 막: grpc/lib 기동 · common::telemetry(agg/bus 실구현) · oxhubd(H7 판정 걸림) — 별도 세션.

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. 성문 계층 7파일 904줄 전수. 신규 GW1~GW6(확인 4·의문 2) + 격하/철회 2. ★GW1 handle_stun 인증 전 상태변경(latch/migrate/liveness 가 MI 검증 선행 — ICE hijacking) ★GW2 SDP-free DTLS fingerprint 미대조 |
