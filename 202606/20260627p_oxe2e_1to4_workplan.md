# oxe2e 1~4 통합 작업 지침 (김과장 실행)

- author: kodeholic (powered by Claude)
- 작성: 2026-06-27 (세션 0627p)
- 상위: `20260627l_oxe2e_invariant_workplan.md` (전체 순서) / 명세 `20260627k` 대장
- 전제: 0a(f50a8e4)·0b(5962c99) 커밋 완료. **0c(cross-sfu)는 막힘으로 건너뜀**
  (봇 sfu-이동 PC 모델 미지 + cross-room forward 반쪽 토대 → 부장님 지시 20260627: 0c 보류, 1부터).

---

## 0. 공통 규율 (1~4 전부 적용)

- **failability(갈래B) 의무**: 새 등식은 일회성 합성 금지 → `tests/test_equations.py` **영구 음성 픽스처 의무**.
  등식마다 짝: 정상1 + 위반N + skip(해당시). 음성 픽스처 없는 등식 = 죽은 게이트 → 등록 금지.
- **막히면 질문 게이트**: 각 칸 선행조사(loader/봇 확장)에서 **1회 막히면 즉시 부장님 보고**.
  2회 삽질 금지(0c·Rust+Android 교훈). 미지를 추측으로 코딩 금지.
- **완료 4종**: 코드 변경 + 호출처 갱신 + 구 경로 제거 + 주석 일치.
- **봇 = 무가공 속기사**(공리 1): send(canned)/recv(raw)만. PASS/FAIL 판정 금지.
- **단계 게이트**: 직전 칸 라이브 PASS + 커밋 후 다음 칸 진입. 부장님 결재 없이 다음 칸 코딩 금지.
- **순서 고정**: 1 → 2 → 3 → 4. (2·3·4 는 선행 난이도 다름 — 막히면 그 칸만 known-gap 두고 다음으로.)

---

## 1. floor 손바뀜 seam (단일 sfu — 안 막힘, 첫 타자)

### 명제 (PTT 본질)
발화권 손바뀜 = SFU 가 한 fan-out slot 의 송신원을 바꿔 끼우는 순간(ptt_rewriter SSRC/seq/ts offset).
gating_correct 가 ±250ms guard 로 **면제하는 바로 그 구간**을 정면으로 본다.

### 실측 근거 (김대리, dump_ptt_voice 직접 파싱)
손바뀜 ±250ms 에 실제 28패킷(botB 15 + botA 13) 흐르는데 현재 0 검증.
slot seq 가 화자 A→B 바뀌어도 141→145(+4) 연속(ptt_rewriter 동작)인데 seq_completeness 가 slot 제외라 미검증.

### 등식 `floor_seam` (3 술어)
손바뀜 경계(옛 화자 RELEASE send ~ 새 화자 GRANTED recv)에서:
- (a) **청자 무음 갭** = 옛 화자 마지막 slot 패킷 → 새 화자 첫 slot 패킷 ts_mono 갭 ≤ 임계.
- (b) **slot 연속성** = 손바뀜 가로질러 slot vssrc 의 seq/ts 단조(화자 바뀌어도 같은 slot=연속. 점프 시 FAIL).
- (c) **제3자 누수 0** = ±guard 내 흐른 패킷이 "직전 화자 잔류 OR 신규 화자"로만 설명. 그 외 유입 = FAIL.

### 선행 측정 (등식 짜기 전 — 임계 (a) 근거)
dump_ptt_voice 의 513ms 중 **순수 서버 전환 비용** 분리. 현 ptt_voice 는 release→request 간격 0.5s(의도분).
→ 그 간격을 0 에 가깝게 좁힌 yaml(ptt_voice_seam.yaml)로 재측정해 서버가 더하는 실 전환 갭만 추출.
이 값이 (a) 임계의 근거. **막히면(전환 갭이 비결정·들쭉날쭉) 보고** — (a) 는 known-gap 두고 (b)(c) 만.

### 갈래B
ptt_rewriter offset 망가뜨리면 → (b) FAIL. 옛 화자 잔류를 새 화자 구간에 새게 하면 → (c) FAIL. 합성/fault 실증.

### 봇 의존성
거의 없음(ptt_voice 봇 그대로). loader 에 slot seq/ts 추출은 이미 있음(rtp_recv).

---

## 2. S3 누설 종단 (RTCP Terminator)

### 명제
두 RTP 세션 사이 RTCP 누설 교차 0. 서버→sub봇 SR 은 publisher SR relay(translate)지 자체생성 아님.
서버→pub봇 RR 에 subscriber RR 내용 누설 없음.

### ★선행 조사 (필수 — 막히면 보고)
**현 loader 는 RTCP 를 타입명만 적재**(`type(pk).__name__`). SR sender ssrc·NTP, RR report block source ssrc
**미파싱** → S3 현 dump 로 불가(김대리 실측, 0627k §5). 선행:
- loader 가 RtcpPacket 내용(SR: ssrc/ntp/rtp_ts, RR: report block ssrc/fraction_lost) 적재하도록 확장.
- SR 쪽 추가 잠금: GAP-rtcp-sr — 봇 canned 라 publisher SR 미송신 → 서버 relay 할 SR 없음.
  → **RR 누설검사**는 loader 확장만으로 가능(봇 RR 자동송신 여부 먼저 확인). **SR translate 검사**는 봇 SR 송신까지 필요.
- **봇 RR 자동송신 안 하면** SR·RR 둘 다 막힘 → S3 known-gap 두고 3번으로. (이 칸은 막힐 확률 높음 — 게이트 엄수.)

### 등식 `rtcp_terminate` (loader 확장 성공 시)
- 서버→sub봇 SR 의 ssrc/ntp 가 publisher 송신값 파생인가(자체생성 아님).
- 서버→pub봇 RR 에 subscriber 가 보낸 RR 내용이 안 섞였나.

### 갈래B
서버가 SR 자체클록 생성 / subscriber RR 을 publisher 에 relay → 내용 불일치 FAIL. 합성 실증.

---

## 3. L4 복구 발화 (손실 시 NACK/RTX/PLI)

### 명제
봇이 seq 갭 주입 → 서버 NACK 발화, RTX(PT=97) 재전송 도착, 갭 메워짐. keyframe 필요 시 PLI.
(현 oxe2epy 는 무손실 localhost 전제라 손실을 안 만듦 = 구조적 빈칸.)

### 선행 (봇 + loader)
- 봇: 결함주입(`fault: drop`)은 이미 있음(bot.py fault_drop_rate). 단 **그건 봇이 송신을 빠뜨려 상대 seq 결손**을 만드는 것 → 그 결손에 서버가 NACK 보내나? 봇이 NACK/RTX 를 수신·관측하나 확인.
- loader: 서버→봇 RTCP NACK, RTX(PT=97) RTP 적재. (2번 loader RTCP 확장과 겹침 — 2 먼저면 토대 공유.)
- **막히면(봇이 NACK/RTX 관측 못 함) 보고** → L4 known-gap.

### 등식 `recovery_signal`
- 봇 seq 갭 구간 → 서버 NACK 발화 관측 → RTX 재전송 도착 → 갭 메워짐(seq_completeness 가 RTX 후 0).

### 갈래B
서버 NackGenerator 끄면 갭 영구 잔존 → FAIL. fault 주입 실증.

---

## 4. L1 경합/급사 (floor 수렴)

### 명제
동시 FLOOR_REQUEST → 정확히 1 GRANTED + 나머지 Denied/Queue. holder 급사(DC 끊김) → 유한시간 내 회수.

### ★선행 (가상시계 — 최대 난점)
동시성·타이밍 시험의 천적은 flakiness. **가상시계·시드 고정·이벤트 순서 강제 없으면 비결정 → noise 생성기.**
- 현 oxe2epy 결정성: 시드(`--seed`) 있음(0627h). 단 **시간 자체를 결정론 제어하는지**는 미확인 → 조사.
- 봇: 같은 ms 동시 FLOOR_REQUEST 송신 + holder 중도 DC 끊기.
- **막히면(동시성이 비결정이라 floor 결과 들쭉날쭉) 보고** → L1 known-gap. 이 칸이 가장 막힐 확률 높음.

### 등식 `floor_convergence`
- 동시 요청 구간: GRANTED 정확히 1 + 나머지 Denied/Queue (2명 grant=FAIL, 0명=FAIL).
- holder 급사 후: 유한시간 내 다음 화자 GRANTED 도달(영구 점유=FAIL).

### 갈래B
중재 로직 깨면 0/2명 grant → FAIL. 회수 타이머 끄면 급사 후 영구 점유 → FAIL.

---

## 5. 보고

각 칸 완료 시 `context/202606/20260627<suffix>_oxe2e_<칸>_done.md`:
- 선행 조사 결과(특히 막힘 여부) + 등식 + 갈래B 음성픽스처 + 라이브 PASS/FAIL + 회귀 수 + 커밋 해시.
- 막힌 칸은 KNOWN_GAPS 등록분 명시 + 다음 칸으로.

**김과장 첫 행동 = 1번 선행 측정**(ptt_voice_seam.yaml 로 순수 전환 갭 추출) → floor_seam 등식.
2·3·4 는 선행 조사에서 막히면 그 칸 known-gap 두고 다음으로 — 순서는 지키되 막힘에 멈추지 말 것.
