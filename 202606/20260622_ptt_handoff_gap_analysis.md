# 20260622 — PTT 화자전환 핸드오프 갭 (영상 늦음 / 돌림노래) 현상·원인·조치

> author: kodeholic (powered by Claude)
> status: **검토 대기 (코딩 전)** — 부장님 검토 후 코딩 여부 결정
> 근거 데이터: `/tmp/trace4.000.rtp` (oxadmin trace `* * --inout`, R01/sfu-2, 20:47:17~20:48:03, 46초)
> 관련: [[20260622_republish_rewrite_fix_libwebrtc_videoreplay]] (같은 날 슬롯 rewriter seq 역행 수정 `162f50b` — 본 건과 별개, 그 fix는 정상 작동 확인됨)

---

## 0. 한 줄

PTT 4인 회의에서 **화자전환마다 음성·영상이 최대 ~1.3초 끊기고**(영상 늦게 따라옴), 끊긴 뒤 **3 수신측 재생이 어긋나 "돌림노래"로 들린다.** 갭의 *발생원*은 새 화자 cold-start(첫 RTP 늦게 도착)지만, **SFU가 그 공백을 보정(comfort-noise 브리징)하지 않고 출력 공백 + 큰 ts 점프를 그대로 흘려 수신측 NetEQ를 붕괴**시키는 것이 결함. SFU 보정으로 체감 갭·돌림노래 제거 가능.

---

## 1. 현상 (관측)

- 환경: 4인(U01~U04) 반이중(half-duplex) PTT, room R01.
- **영상 늦게 따라옴**: 화자가 바뀌면 새 화자 영상이 1~2초 늦게 붙는다.
- **돌림노래**: 음성이 라운드(돌림노래)처럼 어긋나 들린다. 부장님 가설 = 수신측 3개가 서로 다른 시점에 재생.
- 부장님이 **체감할 정도** → 갭이 상당히 크다는 전제로 규명 요구.

---

## 2. 측정·근거 (trace4.000.rtp 전수)

### 2.1 측정 기준
- rtpdump 레코드 `offset` = **SFU egress 이벤트 emit 시각**(캡처 시작 기준 ms). 트레이스 점은 socket.send 직전 emit.
- "갭" = 연속한 egress 패킷의 emit 시각 차(SFU 출구 벽시계 공백). RTP `ts`(48kHz 미디어시간) 차와 교차검증.

### 2.2 floor 회전 (46초에 5회) — PT111 ingress(raw publisher) 활동 구간
```
0x9808221F(0~14.9s) →[1272ms]→ 0x3D52E16E(16.1~27.3s) →[70ms]→
0x846E1046(27.4~35.2s) →[533ms]→ 0x258D74DF(35.7~40.0s) → 0x9808221F(40.1~46s)
```

### 2.3 audio 슬롯 egress 갭 전수 (>50ms)
| 시점 | 갭 | 종류 |
|---|---|---|
| 14.9→16.1s | **1272ms** | 화자전환 1→2 (영상도 1305ms 정지) |
| 20.7~21.7s | 390/115/91/119/158/69ms | 화자2 발화 중 입력 끊김+버스트 |
| 27.3→27.4s | 70ms | 화자전환 2→3 |
| 35.2→35.7s | 533ms | 화자전환 3→4 (영상 567ms 정지) |

→ 갭은 **거의 전부 화자전환 지점**, 크기 **70ms~1272ms로 극심하게 가변**.

### 2.4 1272ms 갭 정밀 (최악 사례)
- 옛 화자(0x9808221F) 입력 마지막: **14879ms** (직전까지 20ms 끊김없이 연속)
- 새 화자(0x3D52E16E) 입력 첫 패킷: **16144ms** (그 전 0패킷)
- 슬롯 egress 재개: **16151ms** — 새 입력 받고 **7ms 만에 중계**
- egress 재개 패킷: seq +4(silence 3 + 1), **ts +63552 ≈ 1324ms 점프**

→ **1265ms 동안 어떤 화자도 입력을 보내지 않음.** SFU는 새 입력을 즉시 전달.

### 2.5 영상 — 같은 시점 정지
- video 슬롯 30fps 정상(프레임간격 median 33ms), 단 **1305ms@14.86s + 567ms@35.7s 정지** = audio 갭과 동일 핸드오프.

### 2.6 SFU 출력 자체의 무결성 (보정 외 영역은 깨끗)
- fan-out 3복사본(3 구독자) 발송 시차: **median 0ms, max 1ms** (audio) / max 6ms (video). **SFU 발송 시차 아님.**
- slot egress seq **역행 0** (seq 역행 버그 `162f50b` fix 정상 작동).

---

## 3. 원인

### 3.1 발생원 — floor 핸드오프 dead-time (입력단, cold-start)
PTT 클라는 **발화권을 받은 뒤에야 RTP를 보낸다**(전환 전 새 화자 입력 0패킷 확인). 따라서 핸드오프에 다음 사슬이 통째로 들어감:
```
옛 화자 stop → (장치/마이크 wake) → floor request 송신 → grant 수신 → 첫 인코딩/전송
```
이 사슬 길이 = 갭(70ms~1272ms). 가변성·1.3초의 내부 분해는 **floor 신호 타임라인(DC/MBCP, agg-log)** 영역이라 RTP 덤프로는 못 깐다.

### 3.2 결함 — SFU의 보정 미수행 (★ 본 문서의 핵심)
SFU 현재 핸드오프 동작:
```
옛 화자 → [silence 3프레임=60ms] → [나머지 ~1.2초 출력 공백] → 새 화자 첫 패킷(ts +1.3초 점프)
```
- `ptt_rewriter.rs clear_speaker()` 가 silence를 **고정 3프레임(60ms)**만 발행하고 멈춤 (`SILENCE_FLUSH_COUNT=3`).
- 그 뒤 새 화자 도착까지 **출력 공백** → 수신측 지터버퍼 starvation.
- 새 화자 첫 패킷에 **arrival-gap을 ts로 그대로 박음**(`rewrite()` is_first → `last_relay_at`→gap_ticks→advance_last) → 수신측 NetEQ에 **1.3초 ts 점프** 투하.

**결과**:
- **돌림노래** = 큰 갭(특히 1.3초) 후 3 수신측 NetEQ가 starvation+큰 ts 점프를 **각자 다른 방식/시점으로 흡수·복구** → 재생 재개 시점 어긋남(라운드). 갭이 클수록 어긋남이 큼. *(인과는 측정이 아닌 추론 — 수신측 getStats/이벤트로 보강 가능.)*
- **영상 늦게 따라옴** = 같은 핸드오프에 영상도 정지 + 새 화자 **키프레임 대기**(video rewriter `pending_keyframe` drop) 추가 지연.

> 정리: **갭의 원인은 핸드오프, 갭을 키워 체감시키는 것은 SFU의 보정 부재.** 후자가 SFU 결함이며 본 조치의 대상.

---

## 4. 조치방안

### 안 A — comfort-noise 브리징 (권장)
핸드오프 dead-time를 silence/CNG 프레임으로 **연속 발행**해 출력 공백을 메운다.
- `clear_speaker` 후 새 화자 도착까지 **20ms 주기로 silence 프레임 계속 발행**(ts 연속 +960, seq +1).
- 새 화자 첫 패킷은 **브리징한 silence ts에 그대로 이어감 → 큰 ts 점프 제거**(arrival-gap 점프 폐기).
- 효과: 수신측 지터버퍼 안 굶음 → **돌림노래 소멸 + 체감 갭 제거**. 화자 사이엔 자연스러운 무음만.

**lip-sync 트레이드오프가 사실상 없음**: 갭 전체(예 1.3초=65프레임)를 silence로 채우면 ts 총 전진량이 기존 점프와 동일 → lip-sync 관계 보존, **전달만 공백→연속으로 전환**. 즉 현재의 "arrival-gap ts 보존" 의도를 깨지 않으면서 연속성만 얻음.

**영향범위**:
- `ptt_rewriter.rs` — `clear_speaker`(고정 3프레임 → 브리징 시작), `rewrite()` first-packet(arrival-gap ts 점프 제거/이어가기).
- `tasks.rs` — 핸드오프 silence 타이머(floor 점유 중 활성 입력 없을 때 20ms tick; 새 입력 도착/floor 해제 시 정지). floor timer/active-speaker tick 선례 재사용.
- `slot.rs` — 슬롯이 타이머 발행 대상(구독자 fan-out) 연결.
- **PTT(half-duplex 슬롯) 경로 한정.** full conference/duplex(슬롯 미경유)는 무관 — 단 회귀로 확인 필수.

**리스크/검증 필요**:
- silence flush **멱등성**(`clear_speaker` 이중호출·duplex 전환 TRACK_STATE_REQ 경유 시 이중 발행 금지) — 현 멱등 가드 유지.
- 브리징 **종료 조건** 누수 없게(새 입력·floor 해제·타임아웃). 무한 발행 방지.
- 타이머 hot-path lock 회피(슬롯 상태 read 최소).
- 수신측 실측(돌림노래 소멸·갭 체감 제거)으로 인과 확정.

### 안 B — arrival-gap ts 점프 클램프 (저비용 부분 완화)
`rewrite()` first-packet의 gap_ticks를 **상한(예 200ms)으로 클램프**.
- 장점: 거의 한 줄, 즉효로 NetEQ 충격 완화.
- 한계: **출력 공백(starvation)은 그대로** 남음(돌림노래 부분 잔존). 실 1.3초 갭을 200ms로 압축 → **lip-sync 드리프트** 누적.
- 위치: `ptt_rewriter.rs rewrite()` gap_ticks 산출부.
- 용도: 안 A 전 임시 완화 / 안 A와 병행 상한.

### 안 C — 핸드오프 사슬 단축 (직교, 클라/floor 영역)
1.3초 자체를 줄이는 방향. cold-start 사슬 분해(floor 이벤트 타임라인 필요) 후:
- 클라 **마이크 warm 유지 + grant 즉시 전송**, 또는 grant 전 pre-arm.
- floor grant RTT/governor 단축.
- 장점: 근본(갭 자체) 축소. 단점: 클라/시그널링 변경, 효과 가변. **SFU 보정(안 A)과 독립·병행.**

### 영상 (별건)
영상 늦음은 안 A로 안 풀림(audio 전용). 새 화자 **키프레임 지연 / PLI governor**가 원인 — 기존 미해결 항목([[20260622_republish_rewrite_fix_libwebrtc_videoreplay]] §4 "화자전환 영상 공백")과 동일. 별도 트랙.

---

## 5. 권고

1. **안 A(브리징)** 가 근본 보정 — lip-sync 보존하며 돌림노래·체감 갭 제거. 1순위.
2. **안 B(클램프)** 는 안 A 착수 전 즉효 완화로 병행 가능.
3. **안 C / 영상** 은 직교 트랙 — floor 이벤트 타임라인 확보 후 별도 판단.

## 6. 코딩 전 결정 필요 (부장님)
- 안 A 채택 여부 + 타이머를 tasks.rs 슬롯 tick으로 둘지 슬롯 자체 소유로 둘지.
- arrival-gap ts 점프를 **제거**(안 A)할지 **클램프**(안 B)만 할지 — lip-sync 정책.
- 회귀 범위: ptt_rapid + conf_basic + duplex_cache(전환 경유) 필수.

## 7. 미해결 / 다음
- 돌림노래 인과(NetEQ divergence)는 **추론** — 수신측 webrtc-internals/getStats로 확정 필요.
- 1.3초 사슬 내부 분해 = floor 이벤트 타임라인(DC/MBCP, agg-log) 필요(RTP 덤프 범위 밖).
- 갭 가변성(70ms vs 1272ms) 원인 미규명 — floor 타임라인으로.

---

## 부록 A. 핵심 수치
- 캡처: 46초, audio 슬롯 distinct 2169패킷(3 fanout), video 1327프레임.
- 최악 갭 1272ms: in 마지막 14879ms → in 첫 16144ms → egress 재개 16151ms(+7ms).
- fanout 발송 시차 median 0 / max 1ms. seq 역행 0.
