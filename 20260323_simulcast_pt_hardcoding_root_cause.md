# 세션 컨텍스트: Simulcast non-simulcast publisher fix + PT 하드코딩 근본 문제 발견

> 날짜: 2026-03-23
> 서버 버전: v0.6.6 (진단 로그 추가 상태, 버전 bump 보류)
> 관련 파일: `ingress.rs`, `track_ops.rs`, `config.rs`, `media-session.js`

---

## 이번 세션 요약

### 1. track_ops.rs SUBSCRIBE_LAYER PLI fallback 완료
- 이전 세션에서 ingress.rs 4곳 수정 완료 (fanout fallback, PLI fallback, RTCP/NACK 역매핑)
- 이번 세션에서 **track_ops.rs:378** SUBSCRIBE_LAYER PLI lookup fallback 1곳 추가
- rid 없는 publisher에 대해 `or_else(|| tracks.iter().find(|t| t.kind == Video && t.rid.is_none()))` 패턴

### 2. 배포 후 테스트 — U128(iPhone) video 여전히 릴레이 안 됨
- 5곳 수정 후 빌드/배포/테스트했으나 SUBSCRIBE 섹션에 U128 video 없음
- LOSS CROSS-REFERENCE에서도 U128→*:video 항목 없음

### 3. 근본 원인 추적 과정

#### 3-1. 진단 로그 추가 (`[SIM:DIAG]`)
- `fanout_simulcast_video` 안에 track lookup 결과 로그 추가
- 결과: **U128의 `[SIM:DIAG]` 로그가 전혀 안 찍힘** → fanout_simulcast_video에 진입하지 않음

#### 3-2. 진단 로그 추가 (`[PT:DIAG]`)
- ingress.rs handle_srtp의 PT 정규화 직후에 원본 PT 로그 추가
- 결과 확정:
```
[PT:DIAG] user=U128 ssrc=0x31C71CFB raw_pt=98 is_video=false is_audio=false tracks=0
```

#### 3-3. 원인 확정: **PT 하드코딩**
- iPhone Safari는 H264를 **PT=98** (두 번째 H264 profile)로 전송
- 서버의 `is_video_pt()` = `pt == 96(VP8) || pt == 102(H264)` → **PT=98 인식 불가**
- PT=98은 video도 audio도 아닌 "미지의 패킷" → simulcast 경로도 normal fanout도 안 탐 → **블랙홀**
- `tracks=0`은 PUBLISH_TRACKS가 3초 후에 도착하기 때문 (getStats 폴링 대기)

---

## 기각된 접근법 (절대 하지 말 것)

### 1. PT 하드코딩 판별 — `is_video_pt()` / `is_audio_pt()` / `is_rtx_pt()`
- **왜 안 되는가**: H264만 해도 PT가 96, 98, 100, 102, 103, 107, 109, 115, 117, 119 등 브라우저/profile마다 다름
- **업계 현황**: mediasoup, LiveKit(Pion), Janus 어디서도 PT 하드코딩으로 video/audio 판별하지 않음
- mediasoup: Router 내부 코덱 맵 + PT rewrite per consumer
- Pion/LiveKit: SSRC → codec 매핑 (OnTrack 콜백)
- Janus: RTP header extension에서 rid 파싱 → SSRC 동적 매핑

### 2. getStats 폴링으로 simulcast SSRC 추출 (현재 방식)
- **왜 안 되는가**: Chrome simulcast에서 SDP에 SSRC가 없고, getStats도 처음엔 안 나옴
- 200ms × 15회 = 3초 폴링은 꼼수이며, iPhone Safari에서는 rid도 안 나옴
- 3초 동안 이미 RTP가 서버에 도착하지만 SSRC 미등록 상태

### 3. SSRC 사전 등록 기반 설계 (PUBLISH_TRACKS에서 SSRC 받아서 등록)
- **왜 안 되는가**: Chrome RID 기반 simulcast는 SDP에 SSRC를 넣지 않음 (Chrome M74+)
- getStats에서 뽑는 것도 위 2번과 같은 이유로 불안정
- PUBLISH_TRACKS 전에 RTP가 먼저 도착하는 타이밍 문제 해결 불가

### 4. PT 정규화를 앞단에서 하면 뒷단 로직 재사용 가능하다는 주장
- **왜 틀렸는가**: "PT가 유한하고 예측 가능하다"는 전제가 틀림
- 현실: 브라우저마다, profile마다 PT가 다르고 하드코딩으로 커버 불가능
- 앞단 정규화 자체는 나쁘지 않지만, 정규화의 **입력이 PT 하드코딩이면 안 됨**

---

## 확정된 설계 원칙: RTP RtpStreamId header extension 기반 동적 매핑

### 업계 표준 (Janus 방식, RFC 8853 준거)

**핵심 메커니즘:**
1. RTP 패킷 수신 시 **RtpStreamId RTP header extension** (`urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id`)에서 rid 파싱
2. rid ↔ SSRC 동적 매핑 테이블 구축 (첫 패킷에서 자동)
3. 매핑 확립 후에는 SSRC 기반 demux로 전환 (성능)
4. 미지의 SSRC 등장 시 다시 rid extension 검사 (SSRC 변경 대응)

**Janus 블로그 (Lorenzo Miniero, 2019) 핵심 인용:**
- "you don't really need SSRCs in the SDP to be able to demultiplex traffic if rid values are advertised and used"
- "inspecting RTP extensions to derive the proper rid/SSRC mappings implicitly"
- "Once these relationships are established properly, Janus can start using SSRCs for demultiplexing packets instead (which is more efficient than comparing strings)"

**RFC 8853:**
- "The RTP header extension for RtpStreamId is offered to avoid issues with the initial binding between RTP streams (SSRCs) and the RtpStreamId identifying the simulcast stream and its format."

### 이 설계의 이점
- PUBLISH_TRACKS / getStats 폴링 불필요 (또는 보조 수단으로만)
- PT 하드코딩 불필요 — rid/SSRC로 트랙 식별 후 codec 정보 연결
- iPhone(rid 없음) = 단일 video → rid 없으면 "default" 트랙으로 자연스럽게 처리
- Chrome/Firefox/Safari 모두 동작 보장
- SSRC 변경(충돌 등)에도 대응 가능

### RTX 식별
- `urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id` extension으로 RTX 트랙 식별
- rid extension의 자매 extension

---

## 다음 세션 작업

### Phase 1: RTP header extension 파서 구현
- `rtp-stream-id` (rid) extension 파싱 함수
- `repaired-rtp-stream-id` (RTX rid) extension 파싱 함수
- SDP offer에서 extmap ID 추출 (클라이언트마다 다를 수 있음)

### Phase 2: 동적 SSRC ↔ rid 매핑 테이블
- Participant에 `ssrc_rid_map: HashMap<u32, String>` 추가
- 첫 RTP 패킷에서 rid extension → SSRC 매핑 자동 등록
- 미지의 SSRC 도착 시 rid extension 재검사

### Phase 3: ingress.rs 리팩터링
- `is_video_pt()` / `is_audio_pt()` / `is_rtx_pt()` 제거
- SSRC → rid → track kind/codec 기반 경로 분기
- PT 정규화는 track 정보 기반으로 유지 (actual_pt → standard_pt)

### Phase 4: PUBLISH_TRACKS 역할 축소
- SSRC 등록 목적이 아닌, codec/bitrate/twcc 등 메타데이터 전달용으로 변경
- 또는 PUBLISH_TRACKS 자체를 제거하고 서버가 RTP에서 모든 정보 추출

### 임시 핫픽스 (Phase 1~4 완료 전)
- 당장 U128 iPhone 영상 릴레이를 위한 최소 수정이 필요하면:
  - ingress.rs에서 SSRC가 tracks에 등록된 경우 `track.kind`로 video 판별 (PT 무관)
  - tracks 미등록 SSRC는 drop (PUBLISH_TRACKS 후부터 동작)
  - 이건 **임시**이고, 최종 목표는 rid 기반 동적 매핑

---

## 현재 코드 상태 (커밋 전)

### 수정 완료 (5곳 rid-less publisher fallback)
1. `ingress.rs` fanout_simulcast_video: `sender_rid.unwrap_or("h")`
2. `ingress.rs` PLI h_ssrc lookup: `or_else(rid.is_none() fallback)`
3. `ingress.rs` subscriber RTCP 역매핑: 동일 패턴
4. `ingress.rs` NACK 역매핑: 동일 패턴
5. `track_ops.rs` SUBSCRIBE_LAYER PLI lookup: 동일 패턴

### 추가된 진단 로그 (배포 후 제거 예정)
- `[SIM:DIAG]` — fanout_simulcast_video 진입 시 track info 출력
- `[PT:DIAG]` — PT 정규화 후 결과 출력 (첫 5패킷)
- 키프레임 감지 codec 기반 분기 추가 (`sender_codec == H264 || rtp_hdr.pt == H264_PT`)

### Git 커밋 메시지 (5곳 fallback 수정분)
```
fix: simulcast relay fallback for rid-less publisher (e.g. iPhone Safari)

- ingress.rs: sender_rid None → treat as "h" layer (fanout_simulcast_video)
- ingress.rs: PLI/RTCP/NACK reverse mapping fallback for rid-less video tracks
- track_ops.rs: SUBSCRIBE_LAYER PLI lookup fallback for rid-less publisher
```

### push-rpi.sh
- sftp 기반 RPi 배포 스크립트 작성 (서버 레포 루트)
- 크로스 컴파일 안 되므로 실제로는 git push → RPi pull → build 사용

---

## 파일 관리 결정

- **CLAUDE.md 삭제** — Claude Code 전용이며 사용하지 않음
- **SKILL_OXLENS.md** — 유일한 마스터 프로젝트 문서. 모든 아키텍처 원칙/기각 사항 여기에 집약
- 세션 컨텍스트는 기존대로 `context/YYYYMMDD_토픽.md` 유지

---

*author: kodeholic (powered by Claude)*
