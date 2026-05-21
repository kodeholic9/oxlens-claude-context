# Track Dump 재설계 v2 → v2.2 세션 종료 (0520d)

> 세션: 2026-05-20 ~ 2026-05-21 00:09 (자정 걸침, 약 6시간)
> 설계서: `20260520c_track_dump_redesign.md` (v2.2)
> 직전 세션: `20260520b_track_dump_impl_done.md` (v1 — 본 세션에서 폐기)
> author: kodeholic (powered by Claude)
> **본 세션 진행 모드 = 김대리 단독** (v1 자율주행 회귀 방지)
> **상태 = 미완료** — 낼 본 세션에서 이어서 진행

---

## §0 본 세션 자기 점검

부장님 평가: *"6시간 가까이 까먹고 성과도 없자나"*

성과:
- v1 자료 결함 분석 (식별자 누락 / 매칭 결함 / 자료 자료 자체 결함 산재)
- 4/5 축 정체성 검증 모델 합의 (track_id 서버 발급 + ssrc/mid/pt SDP + rid publisher)
- v2 설계서 작성 + 정지점 ① 결재
- 클라 SDK 정정 (cli_pub.pt/rid 채움)
- TD-E 흡수 — Pipe 진단 접근자 5종 신설
- WebRTC W3C 표준 검색 → canonical source 확정 (getStats outbound-rtp / inbound-rtp)
- v2.2 정정 (`getParameters` 폐기, `getStats` 1차 원천)
- 단위 시험 33 PASS / 기존 회귀 0
- 실 시험 2회 (부장님 자리) — 자료 정합 일부 통과
- **매트릭스 매칭 결함 발견** — publisher track_id 가 cli/srv 다른 ID 체계 (본 세션 마지막 짚음)

미완료:
- 매트릭스 매칭 키 정정 (`track_id` → `ssrc`)
- PTT 가상 row idle 단계 처리
- 서버 hub `track_dump/mod.rs` row 스키마 정정 (carteasian → track-row)
- 회귀 시험 (Conference / PTT(DC) / PTT(WS) / SCOPE / Admin Live)

본 세션 시간 까먹은 본질:
1. **부장님 결재 자료 자체 틀림 반복** — "동등 함수 OK" (`getParameters`) / "track_id 서버 발급 SDK 저장" — 김대리가 정확한 자료 검색 안 하고 *기억* 으로 자료 만들어 결재 받음
2. **단위 시험 신뢰 함정** — 모의 객체 시험은 *설계 가설* 만 검증. 실 Chrome 자료 봐야 결함 잡힘
3. **W3C 표준 검색은 *설계 결재 전* 했어야** — 부장님 "인터넷 검색해바" 사인 받고서야 진입
4. **v1 의 잠복 결함이 v2 까지 이어짐** — track_id 매칭 자리는 v1 부터 잘못된 자리 / sample JSON 캡처해서야 본질 드러남

---

## §1 본 세션 변경 자료

### 1.1 클라 SDK (`oxlens-home`)

| 파일 | 변경 |
|---|---|
| `core/track-dump-collector.js` | v1 → v2 → v2.1 → v2.2 전면 재작성 — getStats outbound-rtp / inbound-rtp 1차 원천 |
| `core/track-dump-collector.test.mjs` (신규) | 단위 시험 8 group / 33 검증 — Chrome 실 자료 형식 모의 |
| `core/pipe.js` | TD-E 흡수 — 진단 접근자 5종 신설 (`getRtpSender` / `getRtpTransceiver` / `getMediaTrack` / `getMediaElement` / `isElementMounted`) |

### 1.2 설계서 (`context/claudecode/202605/`)

| 파일 | 변경 |
|---|---|
| `20260520c_track_dump_redesign.md` | 신규 v2 → v2.1 → v2.2 패치 (작은 정정 5건 + TD-E 흡수 + getStats 원천 정정) |
| `20260520d_track_dump_v22_session_close.md` (본 파일) | 세션 종료 기록 |

### 1.3 메모리 자료

본 세션에서 추가 메모리 자리 없음 (직전 세션의 `feedback_vocab_no_slang.md` / `feedback_no_unsolicited_coding.md` 등 활용).

### 1.4 시험 결과

```
[track-dump-collector v2.2]  33 pass / 0 fail   ✅ 신규 (Chrome 실 자료 형식 모의)
[sdp-builder]                82 pass / 0 fail   ✅ 회귀 0
[datachannel]                47 pass / 0 fail   ✅ 회귀 0
[scope]                      14 pass / 0 fail   ✅ 회귀 0
────────────────────────────────────────────────────────
Total:                      176 pass / 0 fail
```

서버 측 시험은 본 세션 미수정으로 회귀 안 함.

---

## §2 본 세션 결정적 자료

### 2.1 식별자 검증 모델 — 4축 / 5축

| 지점 | 축 |
|---|---|
| [1] cli_pub (publisher) | 5축 — track_id, ssrc, mid, pt, **rid** |
| [4] cli_sub (subscriber) | 4축 — track_id, ssrc, mid, pt (rid 없음) |

### 2.2 정보 원천 (W3C 검색 후 확정)

| 축 | publisher 원천 | subscriber 원천 |
|---|---|---|
| track_id | 서버 발급 (publisher 측은 클라 임시 ID — 매칭 키 부적합) | 서버 발급 (Pipe.trackId) |
| ssrc | `getStats() outbound-rtp.ssrc` (RFC 3550, required) | `getStats() inbound-rtp.ssrc` |
| mid | `outbound-rtp.mid` 또는 `transceiver.mid` | `inbound-rtp.mid` 또는 `transceiver.mid` |
| pt | `RTCCodecStats.payloadType` (codecId 매핑) | 동일 |
| rid | `outbound-rtp.rid` (simulcast layer) | n/a |

### 2.3 폐기 자료 (다시 제안 금지)

- `RTCRtpSender.getParameters().encodings[].ssrc` — 브라우저 자동 발급 ssrc 미노출 (W3C webrtc-pc #1174). 본 시스템의 `addPublishTransceiver` 가 ssrc 명시 지정 안 하므로 결과 빈 배열
- track_id 로 cli_pub ↔ srv_pub 매칭 — publisher 측은 클라 임시 ID 와 서버 발급 ID 가 다른 체계라 매칭 영원히 불가
- SDP `a=ssrc` 직접 파싱 — getStats 가 canonical 이므로 불필요 (simulcast 면 어차피 a=ssrc 없음)

---

## §3 낼 진입 자리 (정지점 ②.5 ~ ③)

### 3.1 즉시 정정 (어드민 + 서버 hub)

| 영역 | 변경 |
|---|---|
| `oxlens-home/demo/admin/render-track-dump.js` | row 매칭 키 `track_id` → `ssrc` (publisher 측). subscriber 측은 그대로 |
| `oxlens-sfu-server/crates/oxhubd/src/track_dump/mod.rs` | row join 시 매칭 키 ssrc 통일 |
| `oxlens-sfu-server/crates/oxhubd/src/track_dump/mod.rs` | row 스키마 정정 — carteasian (pub×sub×kind) → track-row (publisher 트랙 단위, srv_subs[] 배열) |
| PTT 가상 row | verdict 산출 — idle 시 `idle` 또는 `pending` 단계 (broken 아님) |
| 설계서 §1 / §4 | publisher track_id 매칭 제외 명시 + verdict 정정 |

### 3.2 정지점 ③ 자리 (서버 hub 정정)

- `oxhubd/src/track_dump/mod.rs` — row 스키마 + verdict 3단계 + simulcast pending 분기
- `oxhubd/src/rest/admin.rs` — 응답 JSON 골격 (track-row)
- `oxsfud/.../admin.rs` — srv_pub.rid 노출 점검 (publisher.intent.video_sources 의 rid 자료 자리)

### 3.3 정지점 ④ 자리 (어드민 화면 + 회귀)

- 매트릭스 색상 3단계 (ok/degraded/broken) + idle/pending 표시
- srv_subs[] 펼침 UI
- Conference 3인 회귀 + PTT (DC/WS) 회귀

### 3.4 별 토픽 백로그 (본 작업 밖)

- **TD-A** 서버 [2][3] RTP 카운터 (hot-path 결재 정합) — 별 세션
- **TD-B** virtual_ssrc 자료구조 정정 (`subscriber_stream.rs:336-340` 거짓말 청산) — 실 시험에서 잔재 (0x67CC02A3) 노출 확인. 별 세션 거리
- **TD-C** wire round-trip 테스트 재작성 (0x2701/0x1702)
- **TD-D** admin token Bearer 경로 통일
- **TD-F** NetEQ 자료 노출
- ~~TD-E~~ ✅ v2.1 흡수 완료

---

## §4 실 시험 sample 자료 (참고)

### 4.1 1차 시험 (v2.1) — 2026-05-20 14:38 UTC

- 방: `demo_conference`, 2 publisher (U380 / U882)
- 결과: cli_pub.ssrc=[], cli_pub.rid=[] — getParameters 동등 함수 아님 확인
- 자료 위치: 부장님 자리 자료, 본 파일 §1.1 sample 캡처 보관

### 4.2 2차 시험 (v2.2) — 2026-05-20 15:02 UTC

- 방: `demo_conference`, 2 publisher (U297 / U596)
- 결과: cli_pub.ssrc 정상 박힘 (0x5928BEEA, 0x2DBD7AE2, 0xC6ED057F, 0x2819F1A6)
- **하지만 어드민 매트릭스 [1] CLI-PUB 셀 8개 모두 null** — publisher track_id 매칭 결함 노출
- 비식별자 영역 broken 신호:
  - U297 publisher: `qualityLimitationReason="bandwidth"` 99.93% 시간 → 360p 강제 다운
  - U297 audio 수신: `concealedSamples: 2956` (jitter=0, loss=0 인데 NetEQ 보간)
  - 양 publisher pliCount=2

### 4.3 자료구조 거짓말 자리 (TD-B 별 토픽 / 실 시험에서 노출)

- `pipe.trackState: "inactive"` 인데 packetsReceived 활발 — 자료 거짓말
- `stream_map[].codec: "VP8"` 인데 `kind: "audio"` — 거짓말
- `virtual_ssrc: "0x67CC02A3"` 박혀있지만 어디서도 안 쓰임 — 잔재
- 클라 cli_sub_tracks 에 PTT 가상 트랙 row 누락 (서버는 sub_streams 에 ViaSlot 4종)

---

## §5 김과장 반박 7건 정합 (직전 세션 자리)

| # | 평가 | v2.2 반영 |
|---|---|---|
| 1 | 결재 후 반박 = 월권 | 별 처리 없음 |
| 2 | 대칭 1벌 표현 과장 | §2 표현 정정 |
| 3 | `_sender`/`_element` 캡슐화 | TD-E 흡수 — Pipe 접근자 5종 신설 |
| 4 | simulcast 공집합 부분집합 함정 | §4 verdict pending 분기 신설 |
| 5 | ok/broken 2단계 면죄부 | §4 verdict 3단계 (ok/degraded/broken) |
| 6 | TD-B/TD-E 분리 부적합 | TD-E 흡수, TD-B 백로그 유지 |
| 7 | 정지점 ② sample 출처 명시 부족 | §7 보강 — 실 시험 sample 캡처 필수 |
| 8 | 김과장 통합 모드 회귀 가능성 | §0 명시 — v2.2 = 김대리 단독 |

---

## §6 commit 자리

본 세션의 변경 자리:
- `oxlens-home`: `core/track-dump-collector.js`, `core/track-dump-collector.test.mjs` (신규), `core/pipe.js`
- `oxlens-sfu-server`: 손대지 않음 (서버 정정은 정지점 ③ 자리)
- `context/`: `20260520c_track_dump_redesign.md`, `20260520d_track_dump_v22_session_close.md` (본 파일)

commit 대기 — 부장님이 직접 commit/push (context 레포 + oxlens-home).

낼 본 세션 진입 시 commit 자리 결재 박아주시면 정정 진행.

---

## §7 운영 룰 위반 점검

| 위반 자리 | 발생 | 정정 |
|---|---|---|
| "자리" 어휘 사용 | 본 세션 다수 | `feedback_vocab_no_slang.md` 정합 — 부장님 야단 후 "지점/단계/경로/필드" 사용 |
| 결재 자료 자체 틀림 | 동등 함수 (getParameters) / track_id 서버 발급 | W3C 표준 *설계 결재 전* 검색 필수 자리 — 본 세션 후반 진입 |
| 자율주행 회귀 | 없음 — 김대리 단독 진행 명시 ✅ | — |
| 코딩 전 영향 범위 설명 | 부분 — v2.2 정정 시 영향 면적 표 제출 ✅ | — |
| "코딩해" 명시 사인 | OK — 부장님 결재 받고 진입 ✅ | — |

---

*author: kodeholic (powered by Claude) — 2026-05-21 00:09, 김대리 단독 진행*

---

## §8 자정 후 부장님 본질 짚음 (2026-05-21 ~00:15)

부장님 평가:
- *"100% 재연되는 버그도 못잡는다"* — 김대리들이 본질 버그 짚지 못하니 부장님이 Track Identity 강화 카드 꺼낸 자리
- *"SDK 로 진실의 방에 한번 댕겨와야지. SFU 가 그랬던 것처럼"* — SFU Phase 25 (RoomMode 완전 제거) / Phase 55 (Peer 재설계, Endpoint 소멸) / Phase 57 (Scope 모델) 정합

### 본질 자리 = SDK 자료구조 거짓말 청산

본 세션에서 노출된 SDK 자료구조 거짓말:

| 자리 | 거짓말 |
|---|---|
| `Pipe.trackId` 의미 | publisher = 클라 임시 ID / subscriber = 서버 발급 ID — 같은 필드명 / 다른 의미 |
| `Pipe.trackState` | "inactive" 인데 packetsReceived 활발 — 상태 머신과 실 동작 어긋남 |
| `Pipe.ssrc` / `Pipe.mid` | publisher 측 비어있고 subscriber 측만 의미 — 같은 자료구조 비대칭 의미 |
| `Pipe._sender` / `Pipe._element` | underscore private 약속 외부에서 깨짐 (TD-E 일부 흡수) |
| PTT 가상 트랙 | 서버 sub_streams 에 ViaSlot 4종 / 클라 Pipe 누락 |
| Endpoint / Room 책임 | `getAllSubscribePipes()` PTT 가상 미포함 등 책임 경계 흐림 |

### 낼 진입 자리 재정의

| 자리 | 결재 |
|---|---|
| Track Dump v2.2 후속 (매칭 키 / row 스키마 / 정지점 ③ ~ ④) | **보류 또는 폐기** — 결재 자리 |
| SDK 진실의 방 진입 — Pipe / Endpoint / Room 자료구조 청산 | **본질 자리** (부장님 동석 분석, SFU Peer 재설계 패턴 정합) |
| 100% 재연 버그 좌표 | 부장님 짚음 자리 — 낼 첫 자리에서 짚어주실 자리 |

### 김대리 자기 평가

- Track Dump 인프라가 *목적* 이 되어버린 자리 — `feedback_purpose_first.md` 정합 위반
- *주변 도구* 만 자꾸 만들고 *실 버그* 못 짚는 김대리 패턴 누적 (어제/그제/저제)
- 부장님이 *대화 압축* 마다 정신줄 잡고 본질 끌어주신 자리 — 김대리들은 집념 없이 *결재 자리* 만 양산

---

## §9 100% 재연 본질 버그 (2026-05-21 ~00:20 부장님 짚음)

### 버그 시나리오

```
1. A 입장
2. B 입장
3. 영상 정상 노출 (양방향)
4. B 퇴장
5. B 재입장
6. A 측에서 B 의 영상 노출 안 됨 (100% 재연)
```

*"이걸로 6시간 까먹었다 2일 동안"* — 본 세션 + 직전 세션의 시간 까먹은 원인 자리. Track Identity 강화 카드는 이 본질 버그 짚으려 부장님이 꺼낸 자리.

### 가설 — SDK 자료구조 거짓말 자리에서 발현

| # | 자리 | 가설 |
|---|---|---|
| 1 | `Pipe.trackState` 거짓말 | B 퇴장 시 Pipe 가 RELEASED → 재입장 시 *새 track* 이 *옛 transceiver* receiver 로 도착. trackState 옛 잔재 → element 재바인딩 안 됨 |
| 2 | MidPool 재사용 race | 서버가 *같은 mid* 를 B 재입장 시 재할당. 클라 *옛 Pipe* 가 그대로 → *새 track* 이 *옛 element* 에 attach 실패 |
| 3 | `ontrack` 누락 | subPc 재협상 시 *옛 transceiver 의 새 track* 으로 ontrack 발사 안 됨 → *새 track* 자체 미수신 |
| 4 | remoteEndpoint 정리 race | B 퇴장 시 `room.remoteEndpoints` 에서 B 제거 → 재입장 시 새 remoteEndpoint 생성 / 옛 transceiver 와 새 Pipe 연결 누락 |
| 5 | PowerManager / `_isVideoEnabled` | A 측 power state COLD 잔재 → 신규 트랙 mount 차단 (Phase 32 자리 재발 가능) |

### 본 자리 정합 사례 (SESSION_INDEX)

- **Phase 30** PTT video 표시 버그 — `ptt-panel.js _isVideoEnabled` subscribe 차단
- **Phase 51** PTT 영상 미표시 근본 — 가상 pipe inactive 잔재
- **Phase 53** Conference 멀티탭 카메라 인코더 경합

→ 영상 미표시 자리 누적. 주변 패치 막아왔지만 본질 = **SDK 자료구조 거짓말** (Pipe lifecycle / transceiver-Pipe 매핑 / element-track 바인딩 의 *진실의 단일 출처* 부재).

### 낼 첫 자리

1. **버그 재현** — 부장님 동석. A/B 두 탭 → 단계 1~6 실행. 콘솔/agg-log/스냅샷 캡처
2. **agg-log 시퀀스 분석** — track:registered / track:removed / subscribe:active lifecycle 이벤트 5단계 시간 시퀀스 추적
3. **4지점 자료 비대칭 짚음** — `subPc.getTransceivers()` / `room.remoteEndpoints` / `pipe.transceiver` / `pipe.track`
4. **본질 자리 = Pipe lifecycle 재설계** — SFU Peer 재설계 (Phase 55) 패턴 정합

### Track Dump 자리 결재 요청

본 버그 자체가 *Track Dump 6시간 + 2일 시간 까먹은 자리* 의 원인. **Track Dump 즉시 폐기 또는 무기한 보류** — 낼 첫 자리 결재 박아주십시오.
