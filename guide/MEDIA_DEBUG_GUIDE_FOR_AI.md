// author: kodeholic (powered by Claude)
# MEDIA_DEBUG_GUIDE_FOR_AI — 수신 미디어(검은 화면/무음) 디버깅 가이드

> 출처: 2026-06-13 "CONF-2 검은 화면" 실전 디버깅 (세션 `202606/20260613_*`).
> 키워드 "**미디어 디버깅**" / "**검은 화면**" / "영상 안 나옴" 시 이 가이드 로드.
> 원칙: 스냅샷에서 출발(AGG LOG → TRACK IDENTITY → 코드 경로) + **환경 정합 검증이 0순위**.

---

## §0. 디버깅 전 환경 정합 — 이걸 안 하면 전부 헛수고

실전에서 디버깅 절반이 "오염된 환경" 추적이었다. 코드를 의심하기 전에 반드시:

### 0-1. 서버가 어느 빌드인가
```bash
ps aux | grep -E "oxsfud|oxhubd" | grep -v grep     # 기동 시각(START 열) 확인
git log -1 --format="%h %ad %s" --date=format:"%m-%d %H:%M"   # 소스 HEAD
ls -la target/release/oxsfud                          # 바이너리 mtime
```
- **실행 중 프로세스는 기동 시점의 이미지** — 바이너리를 새로 빌드해도 프로세스 교체 전까지 옛 코드.
  실전: 기동(6/10 19시) < 바이너리(6/11 19:45) < HEAD(6/11 19:49) — wire 계약 커밋 2개가 미반영인
  채 클라(신 계약)와 시험되고 있었다.
- 프로세스의 **로그 파일은 lsof 로 확정**: `lsof -p <pid> | grep log` — 파일명 날짜는 기동일이라
  오늘 로그가 어제 파일에 쌓인다.

### 0-2. supervisor crash loop / 고아 프로세스
```bash
tail oxhubd.log.* | grep -i backoff    # "Backoff 300s (restart #N)" — N 이 크면 crash loop
```
- 실전: 고아 sfud(옛 기동)가 50051/19740 포트를 점유 → supervisor 자식이 bind 실패 →
  **296회 재시작 loop**. hub 는 고아 sfud 에 붙어 "동작은 되는" 상태라 겉으로 멀쩡해 보였다.
- 정화: hub 먼저 kill(재spawn 차단) → 고아 sfud kill → 새 빌드로 hub 재기동(supervisor 가 sfud spawn).

### 0-3. 클라 ES 모듈 캐시 — 같은 origin 재로드는 옛 모듈을 돌릴 수 있다
- 수정한 sdk 파일이 `fetch(url, {cache:"no-store"})` 로는 새 내용인데, **import 체인은 메모리/디스크
  캐시의 옛 모듈을 실행**하는 사례 실증(navigate 재로드로도 안 풀림).
- **확실한 우회 = 정적 서버 포트 변경**(다른 origin = 캐시 무관). 수정 후 시험 결과가 안 변하면
  코드를 의심하기 전에 이것부터.

### 0-4. 시각 정합
- 클라(브라우저) 타임라인 로그는 **UTC**, 서버 로그는 **KST** — 9시간 차. 클라 "14:02" = 서버 "23:02".
  서버 로그에서 클라가 만든 방 이름(`e2e_conf_xxxxx`)으로 grep 하는 게 시각보다 정확.

---

## §1. 계층 분해 진단 — "영상이 안 나온다"는 4개 축으로 쪼개야 한다

`stream.getStats()` (RTCStatsReport) 하나로 어느 축이 끊겼는지 즉시 갈린다:

| 축 | 판정 지표 | 끊겼을 때 의미 |
|---|---|---|
| ① 시그널링 | `STREAM_SUBSCRIBED` 발화 | **SDP 협상 산물일 뿐 — RTP 와 무관!** 이것만 단언하는 시험은 검은 화면을 PASS 시킨다 |
| ② 전달 | `inbound-rtp.packetsReceived` | 0 = forward/gate/ICE·DTLS 문제(서버측). >0 인데 안 보임 = ③④로 |
| ③ 디코딩 | `framesDecoded` + `pliCount` | pkts>0 + frames=0 + **수신측 pliCount 지속 증가** = 디코딩 실패 시그니처(전달 문제 아님) |
| ④ 코덱 정합 | `codecId → mimeType` | 수신 SDP 의 코덱 선언과 **송신측 실 인코딩** 대조 — 불일치 = PT 매핑 어긋남 |

실전 판독 예 (1.6s 간격 샘플):
```
pkts 18→82 (도달 OK) / kf=1, frames=0 (디코딩 실패) / pliSent 7→38 (디코더가 계속 살려달라)
/ mime=video/VP8 (수신 선언) vs 송신 인코딩 H264 → ④ 코덱 불일치 확정
```

### 즉석 진단 시나리오 (케이스 러너보다 분해능 높음)
e2e 페이지 콘솔(또는 playwright evaluate)에서 SDK 직접 import — me/peer 2엔진 + stats 폴링:
```js
const { Engine } = await import("/sdk/index.js");
// ... me/peer join → peer.publish → me 의 stream.getStats() 를 1.6s×5 폴링
// inbound-rtp(video): packetsReceived/framesDecoded/keyFramesDecoded/pliCount + st.get(r.codecId).mimeType
```
**대조 실험이 결정타**: 변인 하나만 바꿔 재실행(예: codec 명시 vs 미지정) — 실전에서 이 대조가
원인을 한 번에 갈랐다.

---

## §2. 서버 구독 게이트 체인 — 검은 화면 1차 용의자

서버는 mediasoup Consumer pause/resume 패턴:

```
publisher PUBLISH_TRACKS
→ 서버: 구독자별 TRACKS_UPDATE(add) + video SubscriberStream gate.pause(TrackDiscovery, 5s)
→ 클라: subscribe SDP 재협상 완료 후 TRACKS_READY{room_id} 송신   ★ 이게 빠지면:
→ 서버: gate.resume() + PLI burst(publisher 에 키프레임 요청)
```

- **TRACKS_READY 미송신 증상**: gate 는 5s 타임아웃으로 풀리지만 **그 경로엔 PLI 가 없다** →
  키프레임 없는 델타만 흘러 영영 검은 화면. 오디오는 멀쩡(gate 는 video 만 pause).
- 신 SDK 송신 지점: `engine._renegotiateSfu` — queueSubscribeRenego 완료 후 sfu 당 1회
  (서버 resume 은 peer 전체 스트림 순회라 1회면 충분).
- **서버 로그 체크포인트** (이 순서로 grep):
  ```
  [TRACK:REG]     ssrc/pt/track_id 등록 — pt 값을 여기서 확보
  [TRACK:NOTIFY]  구독자 통지(이때 gate pause)
  "TRACKS_READY gate resume subscriber=X → publisher=Y"
  [GATE:PLI] / [DBG:PLI] sent → user=Y    PLI 가 publisher 주소로 나감
  ```
- PLI 1회 후 무반응이어도 서버는 재시도 안 함 — **재PLI 는 수신자(브라우저)가 RTCP 로 보내는 것을
  Governor 가 forward** 하는 구조. 수신자가 RTP 를 한 패킷도 못 받으면 PLI 를 안 보낼 수 있다.

---

## §3. 코덱 계약 — 검은 화면 2차 용의자 (이번 근본 원인)

### 계약의 전모 (클라 3곳 + 서버 1곳이 한 사슬)
1. **실 인코딩**: `transport.setCodecPreferences` — `preferredCodec || "H264"` (transport.js)
2. **intent 등록**: PUBLISH_TRACKS body 의 `tracks[].codec`
   - sugar(enableCamera/_publishScreen): `preferredCodec || "H264"` ✓
   - **배치(engine.publish — 봇/BYO)**: `it.codec || preferredCodec || "H264"` (0613 수정 — 폴백이
     빠져 있던 게 근본 원인)
3. **서버 등록**: `VideoCodec::from_str_or_default` — **미지정이면 묵시 VP8** (types.rs)
4. **구독자 SDP**: 서버 통지의 codec + video_pt 로 클라가 빌드 → 디코더가 그 선언을 믿는다

### 고장 모드
```
인코딩 H264(pt=109) ≠ 서버 등록 VP8 → 구독 SDP "109=VP8" → H264 스트림을 VP8 디코더로
→ pkts 도달 + kf 카운트되나 frames=0 + PLI 폭주
```
- **세 폴백("H264")은 한 몸** — transport/sugar/배치 어느 하나라도 어긋나면 인코딩≠등록.
  preferredCodec 정책 변경 시 3곳 동시 확인.
- **서버측 함정 잔존**: 묵시 VP8 기본은 "PT 는 동적" 원칙과 어긋남 — codec 미지정 intent 는
  offer 의 pt 로 판별하거나 reject 가 정도. Android 등 타 클라가 같은 함정 가능(서버 이월).

---

## §4. 시험 원칙 — 이번에 실증된 것

- **"track 도착" 단언은 영상 시험이 아니다**: `STREAM_SUBSCRIBED` 는 SDP 산물.
  반드시 `framesDecoded > 0` 까지 단언(e2e CONF 케이스의 "검은 화면 가드" — cases.js).
  이 가드가 없던 동안 검은 화면이 PASS 로 통과했고, 가드를 넣자마자 잔여 원인을 정확히 잡았다.
- `runner.until` 은 async 판정 지원(getStats 폴링용).
- 코덱 미지정 경로(봇 = engine.publish 배치)가 sugar 경로와 다른 코드를 탄다 —
  **시험이 sugar 만 돌면 배치 경로 구멍을 못 본다.**

## §5. 관련 파일 지도

| 영역 | 파일 |
|---|---|
| 클라 코덱 사슬 | `sdk/transport/transport.js`(setCodecPreferences) / `sdk/engine.js`(publish norm) / `sdk/domain/local-endpoint.js`(sugar) |
| TRACKS_READY | `sdk/engine.js` `_renegotiateSfu` |
| 서버 게이트 | `crates/oxsfud/src/domain/subscriber_gate.rs` / `signaling/handler/track_ops.rs`(pause 277행·resume 788행 부근) |
| 서버 PLI | `domain/pli_governor.rs` / `transport/udp/pli.rs` |
| 서버 코덱 기본값 | `domain/types.rs` `VideoCodec::from_str_or_default` |
| e2e 가드 | `e2e/cases.js` confCase(framesDecoded) / `e2e/runner.js` until |

## §6. 미해결 이월 (이 가이드 갱신 트리거)

- 서버 `NEW rtx` 매 패킷 반복(ingress_publish.rs:294) — rtx ssrc 인덱스 미등록, cold path + 로그 폭주.
  영상 정상이라 기능 결함 아님(새 빌드 재현 206회/1실행).
- 서버 묵시 VP8 기본(§3) — offer pt 판별 또는 reject 로 전환 검토.

---

*author: kodeholic (powered by Claude)*
