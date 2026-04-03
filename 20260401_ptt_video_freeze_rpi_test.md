# 세션 컨텍스트: PTT 실기기 비디오 프리즈 디버깅

> 날짜: 2026-04-01
> 버전: v0.6.9
> 참가: 얼박사(부장) + 김대리(Claude)

---

## 요약

RPi 환경 5대 실기기(안드로이드 2, 태블릿 1, iOS 1, 맥북 1) PTT 테스트에서 비디오 프리즈 발생. 두 차례 테스트로 근본 원인을 추적.

**Critical 버그**: Phase D(RTP-First Discovery)에서 non-simulcast까지 RTP-first를 적용한 설계 실수로, RTX SSRC가 video로 오등록 → PLI가 RTX SSRC로 발사 → 인코더 무응답 → 키프레임 영구 미도착 → 발화자 비디오 전면 실패.

**Secondary 이슈**: PTT 화자 전환 시 서버의 dynamic_ts_gap 계산과 실제 수신측 arrival gap 불일치 → 매 전환당 +43ms 일방향 drift 누적. 장시간 세션에서 jb_delay 증가.

---

## 1차 테스트 (19:35~19:38)

- **조건**: 기본 설정 (hotStandbyMs=1초, coldMs=10초)
- **현상**: 전원 비디오 freeze + fps_zero + video_recv_stall 연쇄 발생
- **분석 결과**:
  - U168(iOS) jb_delay=462ms, U041/U995 jb_delay 측정 불가(decoded_delta=0)
  - jb_delay가 체류시간에 정비례 (drift 누적 패턴)
  - 서버 로그 drift 분석: 147초간 24회 전환, 누적 +909ms, rate 6.18ms/s
  - U168 RTX SSRC(0x3A230071, pt=99) unknown으로 등록 → recv_stats에 jitter=181,393,086 오염
- **1차 서버 로그**: 서버 재시작으로 소실 (2차 테스트 로그만 보존)

## 2차 테스트 (20:29~20:32)

- **조건**: hotStandbyMs=300000 (5분간 HOT 유지, pending compensation 가설 검증)
- **현상**: U041 발언 2회 모두 비디오 미노출 (이전 화자 마지막 프레임 정지), 나머지 화자는 양호
- **핵심 발견**:

### U041 RTX SSRC 오등록

```
20:29:29.653 [STREAM] NEW video rid=1 ssrc=0x5AAC7497 pt=120  ← RTX가 먼저 도착, video로 오등록!
20:29:29.655 [STREAM] NEW video rid=1 ssrc=0x025FE8BA pt=119  ← 진짜 미디어 2ms 후 도착
20:29:29.713 PUBLISH_TRACKS intent: pt=119, rtx=120            ← intent 60ms 후 도착
```

- rid="1"은 **RID가 아니라 MID 값**. non-simulcast(PTT)에서 Chrome은 RID/RRID를 안 보내고 MID만 보냄
- intent 미도착 상태에서 `config::RID_EXTMAP_ID` 기본값 fallback → MID를 RID로 오독
- U041 발언 2회 모두: PLI → 0x5AAC7497(RTX) → 인코더 무시 → keyframe 0개 → vid_pending=4307

### decoder_impl_change (전원 동시 HW→SW fallback)

```
20:31:54 U321 MediaCodecVideoDecoder → libvpx (fallback)
20:31:54 U995 MediaCodecVideoDecoder → libvpx
20:31:54 U027 VideoToolboxVideoDecoder → libvpx
```

---

## 근본 원인 분석

### Phase D 설계 실수

Phase D(RTP-First Stream Discovery)는 simulcast에서 Chrome SDP에 SSRC가 없어 도입.
하지만 **non-simulcast에서는 SDP에 SSRC가 있고**, 업계 3사(mediasoup/Janus/LiveKit) 모두 SDP 교환 시점에 SSRC/RTX SSRC를 사전 확보.

OxLens는 SDP-free 시그널링이라 SDP를 안 보지만, PUBLISH_TRACKS(intent)에 SSRC를 포함하는 것으로 동등한 효과 달성 가능 — **Phase D 이전에 실제로 이렇게 동작하고 있었음**.

Phase D에서 simulcast용 RTP-first 코드를 non-simulcast까지 통째로 적용한 것이 실수.

### non-simulcast vs simulcast RTP 차이

| | Simulcast | Non-simulcast (PTT) |
|---|---|---|
| Chrome extension | RID + RRID(RTX) | MID만 |
| RTP만으로 RTX 구분 | ✅ RID vs RRID | ❌ 불가 |
| SDP에 SSRC | ❌ 없음 | ✅ 있음 (a=ssrc-group:FID) |
| 필요한 접근법 | RTP-first (rid extension) | SSRC 사전등록 (intent 기반) |

---

## 수정 방향 (확정)

**경로 분리:**

- **Non-simulcast**: PUBLISH_TRACKS에 SSRC 포함 → media SSRC / RTX SSRC 사전등록 → RTP 도착 시 알려진 테이블 lookup (Phase D 이전 방식 = 업계 표준)
- **Simulcast**: SSRC 사전등록 불가 → RTP-first discovery 유지 (rid/rrid extension 기반)

---

## 기각된 접근법 ⭐

### 1. SR Translation 완전체가 주범이라는 가설 (기각)
- SR은 lip sync 용도(NTP↔RTP 매핑). SR 부재가 디코더를 죽이지 않음.
- jb_delay 누적을 SR 탓으로 봤으나, 2차 테스트에서 주범이 RTX 오등록으로 확인됨.
- SR Translation은 여전히 미구현(미완)이지만, 비디오 freeze의 직접 원인은 아님.

### 2. pending_compensation 부재가 drift 주범이라는 가설 (기각)
- HOT 유지(hotStandbyMs=300초) 테스트에서도 동일 패턴의 문제 발생.
- drift 자체는 존재하지만(매 전환 +43ms), 비디오 완전 멈춤의 주범은 아님.

### 3. "intent 미도착 시 Unknown 보류 → 재분류" (기각 — 땜질)
- RTP-first 구조를 유지하면서 Unknown으로 보류 → intent 도착 후 재분류하는 방식.
- 레이스 컨디션 자체는 그대로 남아있고, intent 올 때까지 패킷을 버리는 비효율.
- 부장님 지적: "남들처럼 하면 안 되냐?" → non-simulcast에서는 SSRC 사전등록이 정답.
- 문제를 회피한 것이지 제거한 것이 아님.

### 4. "2차 rid 판별에서 intent.rid_extmap_id==0이면 건너뛰기" (기각 — 부분 수정)
- 오독을 막기는 하지만, 근본 설계(non-sim도 RTP-first)는 그대로.
- 업계 선례와 다른 독자 경로를 유지하는 꼴.

---

## ts_gap drift (Secondary 이슈, 미해결)

### 실측 데이터 (1차 테스트 서버 로그 기반)
- 147초간 24회 비디오 화자 전환
- 매 전환당 평균 drift: +43ms (이상치 제외), +69ms (전체)
- 양수(arrival > ts) 16건 vs 음수(ts > arrival) 5건 → 일방향 편중
- 누적: +909ms / 147초 = 6.18ms/s drift rate

### 원인 추정
- 서버의 dynamic_ts_gap(cleared_at→switch_speaker) < 실제 arrival gap
- WS 전달 + replaceTrack + 인코더 startup 시간이 ts_gap에 미반영
- 오디오도 같은 원리로 ~0.6ms/s drift 존재 (but 체감 안 됨)

### 해결 방향 (미착수)
- `dynamic_ts_gap`을 "마지막 릴레이 패킷 arrival → 새 첫 릴레이 패킷 arrival"의 서버 시간 차이로 계산
- 또는 서버 wallclock 기반 SR 생성 (PTT에서 서버가 가상 스트림의 실질적 송신자이므로)

---

## 추가 발견

### iOS(U168) RTX PT 오염 (1차 테스트)
- U168 SDP: H264(96),rtx(97),H264(98),**rtx(99)**,...
- ssrc=0x3A230071 pt=99 → unknown으로 등록 → recv_stats에 jitter=181,393,086 오염
- config::is_rtx_pt() 하드코딩에서 pt=99를 RTX로 인식 못함
- RTX SSRC 사전등록 수정 시 함께 해결됨

### decoder_impl_change (2차 테스트)
- 전원 동시에 HW→SW 디코더 fallback (libvpx)
- 디코더가 소화 못하는 패킷(RTX 오등록된 SSRC의 패킷?) 수신 시 발생 추정
- 추가 조사 필요

---

## 김대리 반성

1. SR 문제에 과몰입하여 핵심(RTX 오등록)을 늦게 발견
2. "왜 디코더가 죽느냐"는 부장님 질문에 솔직히 모른다고 했어야 했는데, SR 가설을 밀어붙임
3. 수정 방향에서 땜질(Unknown 보류) 제안 — 부장님이 "남들처럼 하면 안 되냐"로 정답 유도
4. 김대리 행동 원칙 1번 "추정하지 말고 선례를 찾자"를 부장님이 직접 시범

---

## TODO

- [x] **Critical**: non-simulcast PUBLISH_TRACKS에 SSRC 포함 → register_nonsim_tracks() 함수 분리 ✅
- [x] **Critical**: non-sim/sim 경로 완전 분리 (ingress 미변경) ✅
- [ ] 맥북 4클라이언트 검증: Conference ❌ PTT ❌ Simulcast ✅
- [ ] **High**: ts_gap drift 수정 (서버 arrival time 기반 gap 계산)
- [ ] **Medium**: iOS RTX PT 하드코딩 문제 (사전등록으로 자동 해결 예상)
- [x] SKILL_OXLENS.md 업데이트 ✅
- [x] SESSION_INDEX.md Phase 19 추가 ✅
- [ ] 다음 세션: 트랙별 simulcast 분기 + half-duplex/full-duplex 트랙 설정

---

*author: kodeholic (powered by Claude)*
