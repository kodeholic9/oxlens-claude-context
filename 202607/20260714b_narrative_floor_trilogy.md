// author: kodeholic (powered by Claude)
# 발언권 — PTT Floor 3부작 인물 열전

**서사 기반 정적 분석 · 실험 기록 1호 (n=2 시도)**
2026-07-14 · 방법론: `20260714_narrative_analysis_method.md` v0.1 · 표적: floor.rs / floor_broadcast.rs / ptt_rewriter.rs (+조연 slot.rs)

---

## 0. 실험 조건 (정직 신고)

- **조건 C 변형**이다. 순수 C(§6.1 "새 세션, 프롬프트만 서사")가 아니다 — 이 세션은 방법론 문서 자체를 읽었고 4대 장치를 **의식적으로** 실행했다. 따라서 본 판은 A/B/C 판정에 산입하지 말 것. 산출물의 가치는 "신선한 표적에서 후보가 나오는가"(재현성)에 한정된다.
- 표적 선정 근거: `peer.rs`/`room.rs`는 발견 목록이 문서에 있어 오염. floor 3부작은 알려진 미해결 결함 목록 없음(SRV-0629, SnRangeMap 등 과거 사건은 전부 수리 완료로 기록됨).
- 통독 범위: floor.rs 764줄 + floor_broadcast.rs 439줄 + ptt_rewriter.rs 754줄 + slot.rs 247줄(서사 진행 중 필수 조연으로 발견되어 추가), 테스트 19개 포함. 무대 밖 확인: tasks.rs(40~95, 285~315), ingress_subscribe.rs(60~110), datachannel/mod.rs(535~560), config.rs 상수.
- **오탐 자백 1건**: `broadcast_dc_svc` 무호출(유령) 판독은 grep 필터 실수였다(`grep -v floor_broadcast`가 호출부 `floor_broadcast::broadcast_dc_svc`까지 걸러냄). tasks.rs:300 에서 살아있음을 재확인. **§5.2 규율(모든 발견은 소스로 되돌아가 확인)이 실제로 오탐 하나를 막았다.**

---

## 1. 무대

tokio 런타임 위, 방(Room) 하나가 극장이다. 조명은 50ms마다 한 번씩 깜빡인다(`tasks.rs` floor timer). 무대에 오르는 실행 흐름은 최소 넷:

| 흐름 | 진입 | 근거 |
|---|---|---|
| DC 핸들러 | FLOOR_REQUEST/RELEASE (DataChannel) | datachannel/mod.rs:548,589 |
| WS 핸들러 | FLOOR_REQUEST/RELEASE + ROOM_LEAVE + evict + hot-swap | floor_ops.rs:128,174 · room_ops.rs:432 · helpers.rs:663 · track_ops.rs:448 |
| floor 타이머 | 50ms sweep: RTP-liveness self-ping + check_timers | tasks.rs:40~95 |
| 예열 단역 | grant마다 태어나 20ms 간격 CN을 부치고 은퇴 | floor_broadcast.rs:223~256 |

**중요한 무대 사실**: 이 넷은 서로 다른 task다. 뒤에서 3막의 갈등이 정확히 여기서 나온다.

## 2. 등장인물

### FloorController — 중재관 (floor.rs:173)
방마다 한 명. 발언권의 **유일한 판정자**다. 자기 마음(`FloorInner`: state + queue + prev_speaker)을 **면회 예약제**(`Mutex`, floor.rs:174) 아래 두고, 한 번에 한 손님만 들인다. 면회 안에서의 판정은 흠잡을 데 없이 원자적이다 — 허가·선점·큐잉·회수가 전부 한 락 아래서 결정된다.

성격: **판정하되 집행하지 않는다.** 그는 지시서(`Vec<FloorAction>`)만 써서 내보낸다(floor.rs:7-8). 지시서가 무대 어디서 어떤 순서로 집행되는지는 그의 관심 밖이다. 이 무관심이 그의 비극이다.

말버릇: 그는 관대하다. 이미 발화 중인 자가 또 요청하면 다시 허가하고(floor.rs:259, idempotent), 아무도 발화하지 않는데 해제를 외치는 자에게도 "해제되었다"고 답한다(floor.rs:408-413, idempotent). 이 두 번째 관용이 3막에서 흉기가 된다.

### PttRewriter — 변장사 (ptt_rewriter.rs:75)
화자 N명의 목소리를 가상 SSRC 하나로 꿰매는 자. 마음이 **둘**이다: `inner`(RtpRewriter, seq/ts 산수)와 `state`(PttState, 화자 이름표) — 면회실도 두 개다(ptt_rewriter.rs:77,80). 두 방을 함께 잠글 때의 순서는 항상 state→inner(switch_speaker :151-152, rewrite :314→:322)라 교착은 없다.

성격: **자기가 아는 화자의 패킷만 꿰맨다**(rewrite :317-319, 불일치는 Skip). 화자가 누구인지는 남(Slot)이 알려준다. 그는 이름표를 확인하지만, **이름표를 떼라는 지시에는 누구 것인지 묻지 않는다**(clear_speaker :176, 인자 없음). 이것을 기억하라.

자산: arrival-time gap(:39-42), silence flush 3프레임(:204-233), 예열 CN(:254-300), republish 감지(:329-338). 주석 밀도가 셋 중 최고 — 폐기 사유(SnRangeMap :26-29, marker=1×3 :292-294)까지 박제된 모범 증언록.

### Slot — 무대감독 (slot.rs:68)
방의 가상 채널. **게시판**(`ArcSwap`)에 현재 발화자를 **짝사랑 쪽지**(`Weak<PublisherTrack>`)로 붙여둔다(slot.rs:83) — 배우가 무대를 떠나면 쪽지는 허공을 가리키고, 부를 때마다 생사를 확인한다(:143-149). 발화자 교대는 쪽지 교체 + 변장사에게 통보, 단 두 동작이다(set_publisher :174-178).

성격: **전달자다. 판단하지 않는다.** `release()`는 변장사의 `clear_speaker()`를 그대로 위임한다(:193-195) — 역시 **대상 없는 해제**다. 중재관은 "A의 해제인가"를 검사하고 통과시켰지만(floor.rs:370), 그 검사 결과는 지시서(`Released{prev_speaker}`)에 적혀 있을 뿐, 무대감독도 변장사도 **그 이름을 읽지 않는다**.

### apply_floor_actions — 집행관 (floor_broadcast.rs:75)
지시서를 받아 무대에 올리는 자: 슬롯 교대, 예열 단역 고용, PLI 요청, MBCP 방송. 스스로는 상태가 없다.

성격: **지시서 안에서는 순서를 지킨다**(Released 먼저, Granted 나중 — floor.rs 테스트 :602-619가 "clear→switch"를 보증). 그러나 **지시서와 지시서 사이의 순서는 아무도 보증하지 않는다.** 그는 중재관의 면회실 밖에서 일한다.

### 단역 — 예열 배우 (floor_broadcast.rs:235-255)
grant마다 태어나 20ms 간격으로 CN 한 장씩 부치는 파견직. 목에 **세대 번호표**(`priming_gen`, slot.rs:94)를 걸고, 자기보다 새 번호가 나오면 조용히 은퇴한다(:245-246). 화자 본인에게는 CN을 보내지 않는다(self-echo, SRV-0629의 흉터 — :249, :264). 상한 250장(config.rs:388). 잘 설계된 단역이다.

## 3. 소품

| 소품 | 정체 | 비고 |
|---|---|---|
| `FloorAction` | 지시서 | 운반 중 변질 없음. 문제는 배달 순서뿐 |
| `FloorState` | 중재관의 장부 | Idle/Taken 2상태. `MediaState::Failed` 같은 편도 없음 — 건강 |
| `QueueEntry` | 대기표 | user_id + priority + enqueued_at. **duration 칸이 없다** (→발견 D1) |
| `FloorConfig` | 방 규칙서 | `with_config` 호출자 0 — 항상 기본값(room.rs:84). 잠자는 소품 |
| silence flush / CN | 정적 3장 / 예열 1장 | 동형(ptt_rewriter.rs:244-247), seq/ts 연속성 공유 |

## 4. 3막

### 1막 — 평화로운 교대
A가 누른다. 중재관 면회실에서 Idle→Taken, 지시서 [Granted{A}] 발부(floor.rs:242-256). 집행관이 무대감독에게 A를 게시(slot.rs:174), 변장사가 이름표를 갈고 첫 패킷을 기다린다(ptt_rewriter.rs:166-170). 예열 배우가 CN을 부치기 시작하고, A의 진짜 첫 음성이 도착하는 순간 — 같은 면회실 안에서 — 배우는 은퇴 신호를 받는다(:262, "락이 보장" :253). A가 뗀다. [Released{A}, Granted{B}, QueueUpdated] — 대기자 B가 이어받는다. 정적 3장이 흐르고, B의 첫 패킷이 marker=1을 달고 나간다. **이 막에는 흠이 없다.** 테스트 19개가 이 막을 조밀하게 지킨다.

### 2막 — 강제 집행
높은 우선순위가 문을 두드리면 중재관은 현 발화자를 끌어내린다([Revoked, Granted], floor.rs:272-294 — 선점당한 자는 큐에 넣지 않는다, 3GPP 규격 :283). 30초를 넘기면 T2가(:452), RTP가 5초 끊기면 liveness가(:471) 회수한다. 타이머의 self-ping은 우아하다: 클라이언트 PING wire를 폐기하고, 화자의 RTP 도착 원자 시각(**벽보**)을 읽어 서버가 대신 ping한다(tasks.rs:63-67, floor.rs:59-62). 여기도 흠이 없다 — 단, 회수의 **집행**이 어느 무대에서 이뤄지는지 눈여겨보라. 타이머 task다.

### 3막 — 세 개의 진실, 잠기지 않은 문
이제 무대 전체를 보라. "지금 화자는 누구인가"라는 **원자 사실 하나를 세 곳이 따로 쥔다**:

1. 중재관의 장부 — `FloorInner.state.speaker` (floor.rs:54)
2. 무대감독의 게시판 — `Slot.current_publisher` (slot.rs:83)
3. 변장사의 이름표 — `PttState.speaker` (ptt_rewriter.rs:95)

(가상 SSRC도 세 곳에 있다 — slot.rs:73 이 스스로 "3중 보유"라 자백한다.)

장부는 면회실 안에서만 바뀐다. 그러나 게시판과 이름표는 **면회실 밖에서**, 지시서 배달 순서대로 바뀐다. 배달부(task)는 넷이고, 배달 순서는 보증이 없다.

그리고 해제 지시서에는 이름(`prev_speaker`)이 적혀 있는데, **게시판도 이름표도 그 이름을 읽지 않는다**(slot.rs:193, ptt_rewriter.rs:176 — 인자 없는 clear).

막이 오른다: A가 떼는 것과 거의 동시에 B가 누른다. 중재관은 순서대로 판정한다 — [Released{A}] 그리고 [Granted{B}]. 두 지시서가 **서로 다른 배달부**에게 들린다. Granted{B}가 먼저 집행된다: 게시판에 B, 이름표에 B. 늦게 도착한 Released{A}가 집행된다: **이름을 묻지 않는 clear가 B를 지운다.** 장부는 Taken{B}, 이름표는 None. B의 음성은 전량 Skip(ptt_rewriter.rs:317-319). 더 나쁜 것 — liveness ping은 rewrite 성공이 아니라 **RTP 도착 시각**을 읽으므로(tasks.rs:63-65) 계속 성공하고, 회수는 오지 않는다. B는 자기 burst가 끝날 때까지(최대 T2 30초) 벙어리다.

이 장면은 창작이 아니다. **변장사 자신의 테스트가 이 장면을 재연하고, 현 동작(Skip)을 단언한다** — `clear_after_switch_drops_new_speaker`, "★ 클로버 재연: apply 가 floor 락 밖 + clear_speaker 가 target-less" (ptt_rewriter.rs:733-752). 극장은 자기 결함을 알고 있고, 대본 각주에 적어두었으며, 아직 고치지 않았다.

---

## 5. F2 — 관계 비교표 (같은 자료를 만지는 자들)

### 큐를 만지는 다섯 손
| 함수 | 큐 변경 | QueueUpdated 발부 조건 | 근거 |
|---|---|---|---|
| request(큐 삽입) | push+sort | 큐 길이>1 이면 | floor.rs:344-349 |
| release(발화자) | pop(grant) | 무조건(비면 None) | :381-384 |
| release(비발화자) | retain | **실제 제거됐을 때만** | :396-402 |
| on_participant_leave(발화자) | retain+pop | 무조건 | :516-519 |
| on_participant_leave(비발화자) | retain | **무조건** (제거 없어도) | :522-529 |

→ 같은 사건(비발화자의 큐 이탈)을 release는 가드하고 leave는 가드하지 않는다. 큐가 붐비는 방에서 구경꾼이 나갈 때마다 대기자 전원에게 위치 통지 낭비 발송(**발견 D3**).

### 허가를 내리는 두 손
| | 직접 grant (request) | 큐 pop grant (_try_grant_next) |
|---|---|---|
| max_burst | 요청 duration 또는 `self.config` | **전역 상수** `config::FLOOR_MAX_BURST_MS` |
| duration_s 통지 | burst_ms/1000 | **전역 상수** FLOOR_DEFAULT_DURATION_S |
| 시계 | 호출자가 준 now_ms | **직접** SystemTime::now() |
| prev_speaker | None으로 소거 | None으로 소거 (일치) |
| 근거 | floor.rs:236-240 | :554-572 |

→ 세 칸 비대칭. 오늘은 duration이 전 호출처에서 None(datachannel/mod.rs:548, floor_ops.rs:128)이고 with_config 호출자가 0이라 **값이 우연히 일치**한다. 그러나 datachannel/mod.rs:547 주석이 "duration 반영은 미결(별도 토픽)"이라 명시했으므로, 그 미결이 배선되는 날 — 대기표(QueueEntry)에 duration 칸이 없어서 — 큐를 거친 발화만 조용히 기본값 30초로 되돌아간다. **예약된 결함**(발견 D1).

### 이름을 확인하는 손과 확인하지 않는 손
| 계층 | 해제 시 대상 검사 | 근거 |
|---|---|---|
| FloorController.release | `speaker == user_id` 검사 | floor.rs:370 |
| Slot.release | **없음** | slot.rs:193 |
| PttRewriter.clear_speaker | **없음** (멱등만) | ptt_rewriter.rs:176-184 |

→ 지시서에 이름이 있는데(`Released{prev_speaker}`) 하류 둘 다 읽지 않는다. 3막의 흉기(발견 D2).

## 6. F3 — 대칭 표 (빈칸)

### 방송 경로
```
floor 프레임 broadcast → DC 실패 시 WS unicast fallback ✅ (S-h, floor_broadcast.rs:303-313)
floor 프레임 unicast   → 동일 fallback              ✅ (:338-343)
Speakers(SVC_SPEAKERS) → fallback                    ❌ 빈칸 (broadcast_dc_svc :354-367, 반환값도 버림)
```
→ S-h 주석의 원칙: "bearer는 송신 선택이지 **도달성 포기가 아님**"(:305-306). 그 원칙을 Speakers 방송은 지키지 않는다 — cross-sfu/청취 전용(affiliate) 참가자는 active speaker 표시를 영구히 못 받는다(발견 D4, 의문 — UI 편의 기능이라 의도적 방치일 수 있음).

### 발견 못 한 빈칸의 정직 신고
grant 경로 대칭표(위)와 해제 5경로 비교표가 이번 판의 실질 수확이고, peer.rs 판의 `PublisherStreamIndex`급 구조 빈칸은 이 3부작에서 나오지 않았다. 없어서 못 그린 게 아니라 그렸더니 안 비었다 — floor 계열은 인덱스 층위가 얇아 대칭 깨질 표면 자체가 작다.

## 7. F4 — 주석 증언 대조

| 증언 | 위치 | 대조 결과 |
|---|---|---|
| "발급된 Vec<FloorAction> → apply_floor_actions **단일 진입점**" | floor.rs:21 | **반쪽 사실**. Granted/Released/Revoked/QueueUpdated는 apply가 집행하나 Denied/Queued **회신**은 각 핸들러가 직접 조립(floor_broadcast.rs:138-145, datachannel/mod.rs:553-560). 진입점이 사건 종류로 쪼개져 있음 — 문서 갱신감 |
| "NACK reverse_seq: … last_speaker fallback **자연 폐기**" | ptt_rewriter.rs:26-28 | **모순 아님** — 어휘 충돌. 폐기된 것은 seq 역산 fallback. `floor.last_speaker()`는 RTCP **라우팅** fallback으로 생존(ingress_subscribe.rs:83,96). 단 floor.rs:163,211 의 prev_speaker 용도 주석("NACK 역매핑 fallback")은 옛 어휘를 그대로 써서 다음 독자를 같은 함정에 빠뜨림 — 자구 수정감 |
| "★ 클로버 재연 … apply 가 floor 락 밖 + clear_speaker 가 target-less" | ptt_rewriter.rs:733-737 | **결함 경로 자인 + 현행 오동작을 단언하는 테스트**. 가드가 아니라 비석. 3막의 근거 |
| "wire FIELD_DURATION은 파싱되지만 현재 의도적으로 무시 — 미결" | datachannel/mod.rs:547 | 미결 자인. D1(예약된 결함)과 직결 |
| "부록 E.1 보존 의무 … 단순화 절대 금지" | slot.rs:78-79 | 금기 주석 — 준수 확인(자산 전부 현존: ptt_rewriter.rs:14-21) |

## 8. 발견 목록 (건조체)

> 표기: **[확인]** = 소스/테스트로 실증. **[의문]** = 동작은 확정이나 결함 여부·발현 조건에 판단 필요. 방법론 §5.2 — 확인 못 한 것은 결함이라 부르지 않는다.

**D1 [확인/잠복] 큐 경유 grant의 duration·config 미계승** — `_try_grant_next`가 방 설정(`self.config`)이 아닌 전역 상수 사용 + `QueueEntry`에 duration 부재 (floor.rs:554-572, :148-153). 현재는 duration 전 호출처 None(datachannel/mod.rs:548, floor_ops.rs:128)·with_config 호출자 0(room.rs:84)이라 무증상. duration 미결(datachannel/mod.rs:547) 배선 시 큐 경유 발화만 조용히 기본값 회귀. 시계도 유일하게 SystemTime 직취(:555).

**D2 [확인] 대상 없는 clear의 화자 덮어쓰기(클로버) 미봉합** — 해제 집행이 중재 락 밖 + `Slot.release`/`clear_speaker`가 `Released{prev_speaker}`의 이름을 검사하지 않음(slot.rs:193, ptt_rewriter.rs:176). 늦게 배달된 Released가 새로 게시된 화자를 지움 → floor=Taken{B}·rewriter=None 불일치 → B 음성 전량 Skip, RTP-liveness ping은 도착 시각 기반(tasks.rs:63-65)이라 회수 불발, 최대 T2 30s 벙어리. 재연 테스트 존재(ptt_rewriter.rs:733-752) — 기지(旣知)·미수리. 처방 방향(참고): clear에 대상 전달 후 현재 화자 불일치 시 무시, 또는 방 단위 apply 직렬화.

**D3 [확인/경미] 비발화자 퇴장 시 낭비 QueueUpdated** — `on_participant_leave` 비발화자 분기가 큐 변경 여부 무관하게 발부(floor.rs:522-529). 동일 사건의 `release` 경로는 가드함(:396-402). 대칭 위반, 트래픽 낭비.

**D4 [의문] Speakers 방송의 도달성 빈칸** — `broadcast_dc_svc`에 WS fallback 부재(floor_broadcast.rs:354-367), floor 프레임의 S-h 원칙(:305-306)과 비대칭. DC 없는 참가자(cross-sfu/affiliate)는 active speaker 정보 영구 미달. 의도(UI 편의라 방치) 여부는 부장님 판단 필요.

**D5 [확인/경미] 큐 재요청 시 우선순위 미갱신·허위 회신** — 대기 중 다른 priority로 재요청하면 응답에는 새 priority를 적으면서(floor.rs:304-309) 대기표는 옛 priority 유지·재정렬 없음. duration 재요청도 동일(발화 중 재요청 시 통지만 갱신, 타이머는 옛 값 — :259-265).

**D6 [의문/경미] 유령 Granted 방송** — grant 확정~집행 사이 참가자 퇴장 시 슬롯 미설정인 채 Granted/Taken 방송(floor_broadcast.rs:96-133). liveness가 5초 내 자가 회수하나 그동안 방 전체가 유령 화자를 표시. 경합 창 좁음.

**오탐 기록**: `broadcast_dc_svc` 유령 판독 1건 — grep 필터 실수, 소스 재확인으로 철회(§0).

## 9. 이 판이 방법론에 주는 증거

- **재현성**: 신선한 표적에서 후보 6건(확인 4, 의문 2) 생성. 다만 D2는 테스트 주석이 이미 자인한 기지 사항 — "새 발견"은 D1·D3·D5와 D2의 **미수리 상태 확정**이다.
- **장치별 기여**: D1·D3·D5 = F2(관계 비교표), D4 = F3(대칭표), D2 = F4(테스트 증언 승격)+F2. F1(전수)은 조연 slot.rs 발견(연결 고리가 표적 3파일 밖에 있었음)을 강제했다.
- **§5.2 실증**: 오탐 1건이 서사 단계에서 생성되었고 소스 회귀 규율이 걸러냈다. 서사는 그럴듯한 헛소리를 실제로 만든다 — 규율 없이는 위험하다는 문서의 경고가 맞다.
- **한계 재확인**: 본 판은 프라이밍된 세션(방법론 문서 숙지 상태)이므로 §6.1 A/B/C 판정 증거로 쓸 수 없다. 순수 실험은 여전히 미실행.

---

## 다음 단계 (부장님 결재 대상)

1. D1~D6 처분 판정 (특히 D2 수리 여부·방식, D4 의도 확인)
2. §6.1 순수 A/B/C 실험 (새 세션 3×3, peer.rs+room.rs)
3. 문서 2 (SOP) 작성 여부

| 날짜 | 버전 | 내용 |
|---|---|---|
| 2026-07-14 | 0.1 | 최초 작성. floor 3부작 통독 + slot.rs 조연 추가. 발견 6 + 오탐 1 |
