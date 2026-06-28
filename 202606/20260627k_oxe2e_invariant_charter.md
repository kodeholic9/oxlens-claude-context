# oxe2e 불변식 대장 (S/L/C Invariant Charter)

- author: kodeholic (powered by Claude)
- 작성: 2026-06-27 (세션 0627k)
- 상태: **명세 결재 대기**
- 배경: 부장님 진단 — "oxe2epy가 정답만 유도하는 시험만 한다" + "무전 다방 시험은 왜 없나"

---

## 0. 왜 이 문서가 필요한가 (진단)

케이스를 나열하면 영원히 케이스 추가 게임이다. "무슨 시험이 빠졌나"가 아니라
**"서버가 어떤 입력·환경에서도 절대 어기면 안 되는 속성의 닫힌 목록"** 을 먼저 박아야,
그 위에서 케이스가 기계적으로 떨어지고 커버리지("이만하면 됐다")를 잴 수 있다.

현행 13등식(+identity)을 실측 매핑한 결과(§2), **무게중심이 정합성(C)에 쏠려 있고
안전성(S) 축을 정면으로 보는 등식이 단 하나도 없다.** 우리는 멀티테넌트 B2B SaaS다.
격리·권한·누설·자원 = 한 참가자가 옆 테넌트를 훼손하면 상용 자체가 끝나는 돈 1순위 불변식인데,
그게 통째로 비어 있다. **"정답만 유도"의 정체 = 정합성 축만 측정하고 안전성 축을 안 본다.**

빈칸의 근본 원인 하나 더: S·L 빈칸 대부분이 **봇이 "정상 속기사"로만 설계됐기 때문**에 생긴다.
모든 봇이 약속대로 정상 송신하니 악조건·악의·경합·고갈을 *입력으로 만들 방법이 없다.*
**잠긴 건 등식이 아니라 봇/loader의 관측·행동 레퍼토리다.** (known_defects.py가 GAP-twcc를
"봇 확장 후"로 다루는 그 사고방식 그대로 — 봇/loader 능력 = 시험 사정거리.)

---

## 1. 대장 — 3축 12 불변식

축은 셋. **안전성(S, 절대 안 됨) / 생명성(L, 결국 됨) / 정합성(C, 출력==입력).**
각 불변식은 [정의] / [PASS 술어] / [갈래B = 서버를 어떻게 망가뜨리면 이 시험이 FAIL로 도나]
/ [관측 의존성 = 봇·loader가 무엇을 할 수 있어야 하나] 4종으로 정밀화한다.
갈래B를 증명 못 하는 칸은 공허한 PASS다(공리 2의 안전성 칸 일관 적용).

### 안전성 (S) — 어떤 입력에도 절대 깨지면 안 됨

**S1 격리** — A의 어떤 행동도 B의 미디어·세션을 훼손 못 함.
- PASS: 봇 A가 악조건(깨진 simulcast/순서위반/과다)을 송신해도, 봇 B의 수신 RTP가 정상 봇만 돌린 기준선과 동일(seq/count/codec 무변).
- 갈래B: A의 깨진 입력이 B의 fan-out 경로를 오염시키도록 서버를 고치면 B 기준선이 어긋나 FAIL.
- 의존성: **봇 "악조건 송신 모드" 신설** + 정상 기준선 dump 비교. (現 봇 불가)

**S2 권한** — 자기 자원만 변경.
- PASS: 봇이 남의 floor revoke / 무권 방 publish 시도 → 서버 Denied, 대상 자원 상태 무변.
- 갈래B: 권한 체크를 제거하면 무권 op가 통과해 대상 상태가 바뀜 → FAIL.
- 의존성: **봇 "무권 op 송신"** + 대상 상태 관측. (現 봇 불가)

**S3 누설 종단 (RTCP Terminator)** — 두 RTP 세션 사이 RTCP 누설 교차 0.
- PASS: 서버→subscriber봇 SR은 publisher SR의 relay(translate_sr)지 서버 자체생성 아님
  (NTP/RTP-ts가 publisher 송신값 파생). 서버→publisher봇 RR에 subscriber RR 내용 누설 없음.
- 갈래B: 서버가 SR을 자체 클록으로 생성하거나 subscriber RR을 publisher에 relay하면 → 내용 불일치 FAIL.
- 의존성: **loader RTCP 내용 파싱 확장**(現 타입명만 적재 — §5 실증). SR쪽은 GAP-rtcp-sr(봇 SR 송신)에 추가로 묶임.

**S4 자원 유계** — 어떤 입력도 무한 소비 불가, 고갈 시 거부지 크래시 아님.
- PASS: MID 풀 / dc_pending_buf(MAX=64) 한계 초과 입력 → 서버 거부 응답, 프로세스 생존, 기존 참가자 무영향.
- 갈래B: 한계 가드 제거 시 OOM/패닉/기존참가자 단절 → FAIL(생존 단언 깨짐).
- 의존성: **봇 "과다 생성 모드"** + 서버 생존/거부 관측. (現 봇 불가, 우선순위 하)

### 생명성 (L) — 경합·장애 후 결국 수렴

**L1 floor 수렴** — 경합·장애 후 유한시간 내 정확히 1명(또는 명시 idle), holder 급사 시 회수.
- PASS: 동시 FLOOR_REQUEST → 정확히 1 GRANTED + 나머지 Denied/Queue. holder 급사(DC 끊김) → 유한시간 내 회수, 다음 화자 발화 가능.
- 갈래B: 중재 로직 깨면 0명 또는 2명 동시 grant → FAIL. 회수 타이머 끄면 급사 후 영구 점유 → FAIL.
- 의존성: **봇 동시요청·중도이탈** + **가상시계 결정성 선결**(비결정이면 noise). (現 부분)

**L2 식별 연속성** — track_id 사슬이 republish·재연결·promote 전이를 가로질러 안 끊김.
- PASS: republish/RECON/simulcast promote 뒤에도 client_pub→…→client_sub track_id 사슬 유지.
- 갈래B: 재연결 시 track_id 재발급하도록 고치면 사슬 끊겨 FAIL.
- 의존성: **봇 republish/reconnect 시퀀스**(現 identity는 단발 publish만 — promote만 커버).

**L3 세션 생존** — 정상 참가자가 idle·전환 중 부당하게 안 죽음.
- PASS: 송신0 sub가 오래 idle해도 reaper에 안 걸림(consent 주기). full↔half 전환 중 개인 mid 보존.
- 갈래B: consent 끄면 idle sub가 zombie 회수 → FAIL(capacity ready-sync 진범 재현).
- 의존성: **봇 idle 유지 + consent 송신 관측**(現 duplex_transition이 전환만 부분 커버).

**L4 복구 발화** — 손실·재정렬 시 wire 복구 신호 발화.
- PASS: 봇이 seq 갭 주입 → 서버 NACK 발화, RTX(PT=97) 재전송 도착, 갭 메워짐. keyframe 필요 시 PLI.
- 갈래B: NACK 생성 끄면 갭 영구 잔존 → FAIL.
- 의존성: **봇 결함주입(seq 갭) + loader NACK/RTX 관측**(現 무손실 전제라 손실을 안 만듦 = 구조적 빈칸).

### 정합성 (C) — 출력 == 입력

**C1 미디어 보존** — seq/ts/codec/SSRC가 fan-out 가로질러 보존(재인코딩 0).
- PASS: seq 결손0(재정렬≠손실) / ts 단조 / 수신 pt==약속 pt / 꼬리 recv_max==send_max.
- 갈래B: 이미 충실(seq_completeness/ts_monotonic/codec_match/count_eq). **현행 무게중심.**
- 의존성: 충족(現 등식 정상 동작).

**C2 시각 인과** — 단일 시계 위 인과 정합.
- PASS: floor grant→첫 audio ≤ priming 임계. request→grant 순서. video gate 지연 한계 내.
- 갈래B: gating 시각 술어가 깨지면 timeline violations.
- 의존성: 부분(現 priming→guard·gating_correct 시각 기반).

**C3 전이 정합** — full↔half·mute 3-state·floor 5-state가 정의된 전이도만 따름.
- PASS: full→half active:false 통지 도달 / floor 5-state 정상 전이 / mute 3-state 전이.
- 갈래B: 정의 안 된 전이가 통지되면 FAIL.
- 의존성: 부분(現 duplex_transition=full→half만, gating=floor만. mute·half→full·5-state 전체 ✗).

---

## 1.5 위상(Topology) 차원 — 대장에 곱해지는 축 (부장님 지적 "무전 다방")

**대장 12불변식은 그 자체로 1차원이 아니다. 위상을 곱한 12 × 위상이다.**
현 oxe2epy 는 봇·orchestrator·스키마 전부 **single-room × single-sfu 에 못박혀 있다**(실측:
orchestrator `room=f"{sc['room']}_{pid}"` 단수, 전 봇 동일 방 join, `request_floor()` destinations 무인자,
cross-sfu 라우팅 없음). 본구현이 봇 폭을 **기능 종류**(audio/video/simulcast/PTT/floor/duplex)로만
넓혔지 **위상**으로 안 넓혔다. → cross-room PTT(제품 차별점, cross-room × SFU 3~5대)가 시험 위상에서 전무.
ptt_voice.yaml 도 단일 방 화자전환만(A→release→B).

위상 축:

| 축 | 값 |
|---|---|
| room | single-room \| **cross-room**(다방 청취 affiliate / 다방 발화 destinations) |
| sfu | single-sfu \| **cross-sfu**(room→sfu 1:1, 발화 전환 = 옛 sfu pub_deselect + 새 sfu pub_select 분할) |

cross-room/sfu 에서만 생기는 위험(단방엔 없음):

| 불변식 | cross-room/sfu 의미 | 현 상태 |
|---|---|---|
| S1 격리 | 방 A 발화 audio 가 방 B 청취자에게 새나(다방 fan-out 누수) | ▱ 빈칸 |
| L1 floor 수렴 | cross-sfu 발화 전환 중 floor 정확히 1명 유지 | ▱ 빈칸 |
| L2 식별 | cross-sfu 방 이동 발화 시 track_id 연속 | ▱ 빈칸 |
| S3 누설 | cross-sfu RTCP 종단(노드 간 누설 0) | ▱ 빈칸 |
| S2 권한 | FIELD_DESTINATIONS count≥2 → Phase 1 Denied 실제로 막나 | ▱ 빈칸 |

**지금 시험 가능 범위(서버 Phase 1 제약)**: count≥2 동시발화는 Denied(→ S2 거부 시험거리) /
청취 affiliate 다방 격리(S1) 가능 / cross-sfu 발화 전환(L1·L2) 가능.
**의존성**: orchestrator room 단수→복수 + 봇 다방 join + floor destinations + 2-sfu 배치
(capacity 봇 cross-sfu wire 선례 참조). **우선순위 재고**: cross-room floor 는 단일방 PTT 가 이미
도는 점 감안 시 임팩트가 S3 보다 큼(차별점 최위험 경로). 비용 = 봇 다방 + 2sfu 확장.

---

## 2. 현행 등식 → 불변식 매핑 (실측, equations.py/identity.py 대조)

| 등식 (실측) | 닿는 불변식 | 강도 | 한계 |
|---|---|---|---|
| seq_completeness | C1 | 강 | — |
| ts_monotonic | C1 | 강 | — |
| codec_match | C1 | 강 | — |
| count_eq (꼬리) | C1 | 강 | gating skip |
| identity_5point | L2 + C1 | 강 | **단발 publish만** |
| send_honest | C1 + S1(누수측) | 중 | 정상전제 |
| leak_zero | S1(수신누수) | 중 | **정상전제 — 악조건 A 없음** |
| track_id_returned | L2 | 중 | — |
| gating_correct | L1 + C2 + C3(floor) | 강 | **정상전환만(경합·급사 ✗), single-room** |
| duplex_transition | C3 + L3 | 중 | full→half만 |
| simulcast_entry_ssrc_zero / rid_only | C3(가드) | 가드 | — |
| simulcast_track_id_match | L2 | (격리중) | SRV-0625 |
| rtcp_present | S3 + L4 | 약 | **"있나"만 — 내용 ✗** |

> 전 등식이 암묵적으로 single-room × single-sfu(위상 1점). §1.5 위상 빈칸은 이 표에 안 나타남.

---

## 3. 빈칸 + 우선순위 (리스크 × 비용)

| 불변식 | 상태 | 우선 | 잠금(의존성) |
|---|---|---|---|
| C1 미디어 보존 | ███ 충실 | — | — |
| C2 시각 인과 | ██ 부분 | — | — |
| C3 전이 정합 | ██ 부분 | 후 | 봇 mute·half→full·5-state |
| L2 식별 연속성 | ██ 부분 | 중 | 봇 republish/reconnect |
| **cross-room floor (위상)** | ▱ 빈칸 | **1?** | **봇 다방 join + 2-sfu + floor destinations** |
| S3 누설 종단 | ▱ 빈칸 | 2 | loader RTCP 파싱(+SR은 봇 SR) |
| L4 복구 발화 | ▱ 빈칸 | 3 | 봇 seq갭 주입 + loader NACK/RTX |
| L1 경합/급사 | █ 빈칸 | 4 | 봇 동시요청/이탈 + 가상시계 |
| S1 격리(single) | ▱ 빈칸 | (임팩트1) | 봇 악조건 모드(큰 작업) |
| S2 권한 | ▱ 빈칸 | 하 | 봇 무권 op |
| S4 자원 유계 | ▱ 빈칸 | 하 | 봇 과다생성 |

> 우선순위는 **리스크×비용**. cross-room floor 가 제품 차별점·최위험인데 단일방 PTT 가 이미 도므로
> 증분 임팩트 1위 후보. 단 봇 다방+2sfu 확장 비용 큼 → S3(저비용)과 1순위 다툼은 부장님 결재.

---

## 4. 봇/loader 능력 의존성 그래프

빈칸은 등식이 아니라 능력에 잠겨 있다. 능력 1개가 풀리면 칸 여러 개가 열린다.

```
[orchestrator 다방 + 봇 다방 join + 2-sfu 배치] → cross-room 위상 해제(S1다방/L1전환/L2연속/S2 destinations)
[loader RTCP 내용 파싱]      → S3(RR쪽) 부분 해제
       └ +[봇 publisher SR 송신] → S3(SR translate) 완전 해제, GAP-rtcp-sr 해소
[봇 seq갭 주입]+[loader NACK/RTX 관측] → L4 해제
[가상시계 결정성]            → L1 시험 가능(없으면 noise)
       └ +[봇 동시요청/중도이탈]  → L1 해제
[봇 악조건 송신 모드]+[정상 기준선 비교] → S1(single) 해제 (최대 작업)
[봇 republish/reconnect]    → L2 완전 해제
[봇 무권 op]                → S2 해제
[봇 과다 생성]              → S4 해제
```

---

## 5. S3 첫 적용 실증 (명세 검증)

대장의 첫 칸을 실제 dump/loader에 대본 결과 — **"S3 비용 0" 주장(채팅 1~2차) 철회.**

- loader.py rtcp 처리: `p.rtcp_recv[user].append(type(pk).__name__)` — **타입 이름만 적재.**
  SR sender ssrc·NTP, RR report block source ssrc 등 **내용물 미파싱.**
- 따라서 rtcp_present("RTCP 오나")는 가능하나, S3("relay냐 자체생성이냐 / 누설이냐")은 **현 dump로 불가.**
- 최소 선행: loader가 RtcpPacket 내용(SR: ssrc/ntp/rtp_ts, RR: report block ssrc/fraction_lost) 적재.
- SR쪽 추가 잠금: GAP-rtcp-sr — 봇 canned RTP라 publisher SR 미송신 → 서버 relay할 SR 없음.
  → RR 누설검사는 loader 확장만으로 가능(봇 RR 자동송신 여부 확인 필요), SR translate 검사는 봇 SR 송신까지.

**교훈**: 대장을 깔고 실측하니 "공짜 칸"이 loader 의존으로 드러났다. 추측 결재였으면 헛삽질.
이게 §0 "능력=사정거리"의 첫 실증.

---

## 6. known-gap 편입 (조용한 skip 금지)

대장 빈칸을 known_defects.py KNOWN_GAPS와 동급으로 명시 등록(미등록 빈칸 금지):

| id | 불변식 | covered_by(해제 조건) |
|---|---|---|
| GAP-TOPO-crossroom-floor | §1.5 위상 | orchestrator 다방 + 봇 다방 join + 2-sfu + floor destinations |
| GAP-S1-isolation | S1(single) | 봇 악조건 송신 모드 + 정상 기준선 비교 |
| GAP-S2-authz | S2 | 봇 무권 op 송신 (+ destinations count≥2 Denied) |
| GAP-S3-rtcp-terminate | S3 | loader RTCP 내용 파싱 (+SR은 봇 SR 송신) |
| GAP-S4-resource-bound | S4 | 봇 과다 생성 |
| GAP-L1-floor-contention | L1 | 봇 동시요청/이탈 + 가상시계 |
| GAP-L2-identity-continuity | L2 | 봇 republish/reconnect (現 promote만) |
| GAP-L4-recovery-signal | L4 | 봇 seq갭 주입 + loader NACK/RTX |

(기존 GAP-rtcp-sr / GAP-duplex-half-to-full / GAP-layer-switch / GAP-twcc 와 병존.)

---

## 7. 결재 요청

1. **대장(S/L/C 12) + 위상 차원(§1.5) 채택** — oxe2e 커버리지의 닫힌 좌표계로 확정.
2. **현행 등식 매핑(§2)·빈칸(§3) 승인** — 안전성 축 전무 + 위상 전무 진단 동의 여부.
3. **착수 칸 결정** — cross-room floor(차별점 최위험·고비용) vs S3(저비용·loader 선행) vs S1(임팩트1·최고비용).
4. known-gap 편입(§6) — 빈칸의 명시 등록 승인.

> 코딩(orchestrator 다방화·loader 확장·등식 추가·봇 능력 신설)은 착수 칸 결정 + "코딩해" 지시 후 착수.
> 본 문서는 명세까지.
