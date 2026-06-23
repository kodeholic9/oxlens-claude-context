# 20260622 — republish 검은화면 근본 수정 + libwebrtc video_replay E2E 검증 도구

> author: kodeholic (powered by Claude)
> 서버 커밋 2: `0c8dedc`(fix/ptt republish) · `6f0232c`(feat/oxadmin rtpdump). push 미실시(부장님 몫).

---

## 0. 한 줄

PTT **republish 검은화면**의 근본을 libwebrtc `video_replay` 오프라인 디코딩으로 규명·수정. republish(같은 화자·새 ssrc)가 `switch_speaker` 미경유라 슬롯 rewriter offset 재계산이 안 돼 **슬롯 egress ts 30억 역행 → 수신측 jitter estimator reset → 검은화면**. PttRewriter.rewrite 에서 **입력 SSRC 변화 감지 → 기존 전환 경로(prepare_source_switch+awaiting_first_packet) 재사용**. 라이브 검증 ts점프 2→0, jitter reset 1→0, 검은화면 재연 안 됨.

---

## 1. libwebrtc video_replay — 브라우저 없는 RTP 검증 도구 (신설)

브라우저 PTT 시험이 어려워 libwebrtc `rtc_tools/video_replay`로 SFU egress RTP 를 오프라인 디코딩해 검증하는 경로 구축.

- **빌드**: `~/repository/webrtc-src` → **`~/repository/src` 로 개명**(DEPS 경로가 `src/` 하드코딩, gclient 솔루션명 `src` 필수). depot_tools(`~/depot_tools`) + `.gclient`(managed:False) + `gclient sync`(deps 9.7G) + hooks. CLT-only는 `xcodebuild`/`find_sdk.py` 벽 → **full Xcode 16.2 설치**(macOS 14.6.1 상한, 16.3+는 Sequoia)로 돌파. shim 잔재 `~/repository/xcode-shim/`(폐기).
- **산물**: `~/repository/src/out/Default/video_replay`(arm64). 재빌드 `PATH=~/depot_tools:$PATH autoninja -C out/Default video_replay`.
- **`--verbose` 추가**(video_replay.cc, webrtc 빌드트리 — oxlens 커밋 아님): `webrtc::LogMessage::LogToDebug(LS_VERBOSE)` → 수신 파이프라인 인과 로그(`video_receive_stream2: No decodable frame requesting keyframe`, `Resetting jitter estimator due to bad render timing`, `forward_error_correction: Big gap in media seq`). 브라우저가 안 주는 **수신측 인과**를 토출.
- **함정/주의**: ssrc 십진변환 정확히(0x39AA3365=967455589). 코덱 동적(PT 102=H264, 페이로드 첫바이트 0x7c=FU-A). **키프레임 주기 100초+** → 짧은 캡처는 IDR 못잡아 0프레임 오판(120초+). `--ext_map=ABSSEND:2,TWCC:3`(안 주면 abs-send/transcc 무시 → jb 분석 무효). `--simulated_time`(실시간 대기 없이 즉시 재생).
- **범위 한계**: SR(RTCP)을 line 642 `IsRtpPacket` 가드에서 버림 → 디코딩 가능성만 검증, **jb/SR 타이밍은 못 봄**.

## 2. oxadmin trace 확장

- **`--rtpdump <file>`** (커밋 `6f0232c`): 받은 egress RTP 를 rtpdump(.rtp) 포맷으로 기록 → video_replay 입력. dir 플래그(`--out`)와 충돌 피해 파일 플래그는 `--rtpdump`. detail+통째 강제, `egress_rtp`만 기록(rtcp/gate_drop 제외), `wall_ts_us→offset_ms`. 단위테스트로 libwebrtc kRtpDump 스펙 일치 검증.
- **`--rotate`** (미커밋): ROTATE_SECS(60) 경과 후 **video 키프레임에서** 새 파일(`<prefix>.NNN.rtp`) → 각 파일 키프레임 시작(단독 디코딩). 무한 캡처(Ctrl+C graceful, tokio signal feature 추가) 시 파일 비대화 방지. **★잔존 버그**: `is_video_keyframe`가 PT 필터 없이 모든 패킷 검사 → opus 오디오 false-positive로 rot.002 오정렬(키프레임 없이 시작). H264 FU-A/STAP-A 구조 한정 + 크기 가드로 수정 필요.

## 3. ★ republish 검은화면 근본 + 수정 (커밋 `0c8dedc`)

**규명(3중 교차검증)**:
- **RTP 파싱**: 슬롯 egress(per-room virtual_ssrc) republish 경계 seq 26525→3516, **ts 3.58B→571M(30억 역행)**.
- **video_replay verbose**: `Resetting jitter estimator ... rtp_timestamp=2842601513`(파싱한 점프후 ts 정확 일치) + `Big gap in media seq` + `No decodable frame requesting keyframe`.
- **코드**: `rewrite_in_place` 의 "last+1 재계산"은 `pending_keyframe`일 때만 → `pending_keyframe`는 `switch_speaker`(화자전환)에서만 셋 → **republish(같은 화자·새 ssrc)는 switch_speaker 미경유** → 옛 offset+옛 ROC를 새 입력 스트림에 적용 → 불연속.

**수정**(`ptt_rewriter.rs` 단일, rtp_rewriter.rs 무변경): PttState에 `last_input_ssrc` 추가. `rewrite()`에서 입력 SSRC 변화 감지 → `inner.prepare_source_switch()`(pending_keyframe) + `awaiting_first_packet`(arrival-gap ts) = **기존 switch_speaker 경로 재사용**(0621a "캠 republish 한정 재설계" 완성). switch/clear_speaker에서 `last_input_ssrc=None` 리셋(이중발화 방지). RTX는 ingress 디캡슐, half-duplex라 simulcast off → 슬롯 rewriter는 미디어 ssrc만(오발 없음).

**검증**: 라이브 republish 7+회 스트레스 → 슬롯 egress **ts점프 2→0, jitter reset 1→0**, 부장님 라이브 **검은화면 재연 안 됨**. oxe2e 4/4 PASS(conf/ptt_rapid/duplex/sim), 단위 ptt 3/3. **잔존 seq blip 1회**(seq 447 역행, ts 연속 ratio 무관 — 트레이스 리오더 vs offset 엣지 미규명, 수신측 흡수).

---

## 4. 미해결 (내일)

- **★frozen(0621a 재확인) = 전달 계층 stall (video/audio 번갈아)**: 두 번 관측.
  - **video판(앞)**: SFU egress 슬롯 영상 1028패킷 연속인데 U01 RECEIVED +0(오디오는 도달).
  - **audio판(밤, 3인 R01 U01/U02/U03)**: U03 발화 중 U01/U02 **음성만** 끊김(영상 슬롯 0xFD1DA41D Δ+274 정상). 오디오 슬롯 0x409C8428 클라 RECEIVED +0·lastPkt ~100초 전·conceal Δ+144480. **캡처(emit)엔 오디오 슬롯 6000패킷/분 연속**(rewriter 정상). **emit RTP 상세분석=무결**: seq +1·ts +960(opus) 완벽 연속, 점프/역행/손상 0(중복 29122=U01+U02 2구독자 fan-out 아티팩트). 들리다 안들리다 transient(무조작 자연발생/복원).
  - **공통 결론**: emit RTP 깨끗한데 클라 미수신 = **순수 전달 문제, rewriter·republish fix 완전 결백**(데이터 2회 확인). per-stream stall(미디어 무관, video/audio 번갈아). **trace 사각**(socket.send **직전** emit까지만) → 캡처 패킷수가 "전송됨"을 증명 못 함.
  - **다음 1순위**: trace 점을 **socket.send 이후로** 밀어 실전송 결과(Ok/Err/bytes) 카운트 vs emit. 멈춤 순간 U01 webrtc-internals 동시. (transient — 복원 후 측정 무의미.)
- **화자전환 영상 1~2초 공백**(영상 느려짐, 음성 정상): rot.000에 ts갭 7개(매 전환). **ts==wall(ratio 1.0)** → rewriter 결백, "실제로 영상이 안 온" 것. 원인 = 새 발화자 키프레임 지연. 부장님 의심 = 전환 시 키프레임 3회 요청이 **PLI governor에 씹힘**(0621b 재설계 governor). 첫 발화자 cold 단독 아님(7개 분산). 다음: governor가 화자전환 PLI를 drop하는지.
- **회전 도구 rot.002 오정렬**: is_video_keyframe 오디오 false-positive 수정.

## 5. 방법론 교훈

- **도구를 만들기 전 증상 축부터 확인**: jb=2472ms는 `oxadmin user` 한 방에 있었음. 디코딩 깨짐(video_replay 영역) vs 타이밍/전달(범위 밖)을 먼저 가르기.
- **video_replay = 디코딩 가능성 검증기** (rewrite 비트스트림 무결). SR 타이밍/UDP 전달은 못 봄 → webrtc-internals/event_log/socket.send 계측.
- **transient는 복원 후 측정 무의미** — 멈춤 순간 포착(0621a 교훈 재확인).
- **덤프 먼저, 소스 나중** — RTCP 의심을 소스로 깠다가 부장님 질책. 받아둔 덤프부터 깔 것.

## 6. ★ 다음 세션 시작점 — audio dropout (RTCP/SR 분석)

**증상**: 3인 R01(U01/U02/U03), U03 발화 중 U01/U02 **음성만** 끊김(영상 정상). 들리다 안들리다 transient(무조작). audio 슬롯 0x409C8428 클라 RECEIVED +0인데 SFU emit은 6000/분 연속·RTP seq/ts 무결.

**덤프(이미 있음)**: `/tmp/mon.000~009.rtp` (오늘 18:56~19:05, `* * --inout` 회전). **audio 슬롯 RTP(0x409C8428) + RTCP SR 둘 다 포함**(초기 분석에 PT≈200 SR 패킷 확인 — `--rtpdump`가 egress_rtp만이라던 건 오판, RTCP 들어있음).

**할 일 (덤프부터):**
1. mon 에서 **RTCP SR 추출** — `byte1==200`(0xC8, SR). **RTCP는 sender ssrc=byte[4:8]**(RTP와 다름! 이전 분석이 byte[8:12]로 읽어 NTP를 ssrc로 오독), NTP=byte[8:16], RTP ts=byte[16:20]. audio 슬롯 SR = sender ssrc 0x409C8428.
2. 검증 3:
   - audio 슬롯 SR이 **음성 끊김 구간에 끊기나**(발행 중단?)
   - **NTP↔RTP 매핑 일관성**: NTP 단조? RTP ts 48kHz rate? 화자전환서 NTP/RTP 점프?
   - audio RTP(seq+1/ts+960 무결 확인됨)와 SR의 RTP ts 정합?
3. 이상 시 소스: `ingress_rtcp.rs:213-243`(슬롯 half SR, :228 translate_rtp_ts None→SR drop) / `rtcp_terminator.rs:396 translate_sr`(NTP 원본+가상 RTP ts) / `rtp_rewriter.rs:440 translate_rtp_ts`(pending_keyframe→None).
4. 가설(a) **SR NTP 점프/끊김 → 클라 NetEQ 음성 playout 붕괴**(부장님 의심, RTCP). 가설(b) **RTP 전달실패**(RECEIVED+0=0621a) → SFU 실 socket.send 카운트.
5. 원칙: **mon 덤프부터 깐다. 소스는 좁혀진 뒤.**


8:45, U03에서 U04 영상 느려짐
8:47:50, 돌림노래, 영상느려짐