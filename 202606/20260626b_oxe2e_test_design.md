// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 테스트 설계 + 작업 지침 (20260626b)

> **성격**: 설계서. "코딩해" 전. 부장님(kodeholic) 검토 → GO 후 착수.
> **출발**: `20260626_oxe2e_regression_requirements.md`(요구) + `20260626a_oxe2e_currency_survey_done.md`(현행 실측) + 0624/0624b/0624c(돌림노래 = 디코더 경계) + 0625(simulcast track_id = wire 경계) + MEDIA_DEBUG(흐름 4축) + track-identity(식별 4축).
> **규모 약속**: 새 도구·프레임워크 **0개**. 봇·judge·ccc·297 유닛 그대로 두고 **5군데만** 손본다. 3층(디코딩/NetEQ)·풀 DST·케이스 남발·거대 추상 = 안 한다.

---

## 1. 한 줄 결론

> 봇을 실제 클라처럼 **정직하게(P-3)** 만들고, **SFU가 만든 것**을 `count==0`에서 **등식**으로 올려 2층에서 잡는다. **수신단(NetEQ·디코딩 = jb·framesDecoded)은 3층으로 넘긴다.** 1층은 순수 transform 등식.

---

## 2. 왜 (한 화면)

- 부장님 통증 "회귀가 잘 뚫린다"의 실체 = **0625 §1.4**: 봇이 simulcast인데 가짜 non-zero ssrc를 박아 `t.ssrc==0` 가드를 우회 → oxe2e 항상 green. 웹 클라만 정직(ssrc=0)해서 track_id 미회신 버그 노출. **봇이 무가공 속기사가 아니라 "가드 통과하려 거짓말"하는 상태였다.**
- 회귀가 못 잡은 또 한 겹(0625 §8.6): placeholder 폐기 시 resolve_stream_kind 누락 → **단위테스트는 못 잡고 봇 정직화 후 회귀가 잡았다.**
- 반대편 경계(0624c): 돌림노래 = 수신 NetEQ가 업링크 지터 증폭. **SFU wire는 무죄(1:1 pass-through, lost=0)**, 봇 canned라 재현조차 불가. → **2층 천장 밖 = 3층.**

---

## 3. 분류 체계 → 계층 (부장님 골격: 분류 → 세분화 → 맵핑)

### 3.1 식별 4축 (정적 — 누가 무엇을 약속/실제). 출처: `build_track_identity`(oxhubd telemetry.rs:110)
| 축 | 값 | 봇이 채우나 | 계층 |
|---|---|---|---|
| client_pub (클라가 보냄) | ssrc/codec/pt/mid/kind | 봇 wire raw(canned라 앎) | 2층 |
| server_pub (서버 등록) | track:registered codec/pt + **PUBLISH_TRACKS 응답 track_id** | O(응답/ccc) | 1층(발급 등식)+2층(교차) |
| server_sub (서버 전달) | subscribe:active vssrc + TRACKS_UPDATE add | O | 1층(vssrc 발급)+2층 |
| client_sub (클라가 받음) | 봇 수신 ssrc/seq/ts | 봇 wire raw | 2층 |

정합 = 4점 ssrc-join + **track_id 회신**(client_pub.mid → server_pub.track_id) + **codec_mismatch**(server vs client).

### 3.2 흐름 4축 (동적 — 미디어가 흐르나). 출처: MEDIA_DEBUG §1
| 흐름 축 | 미디어 값 | 증상(안 맞으면) | 계층 |
|---|---|---|---|
| ① 시그널링 | TRACKS_READY 도달, opcode 순서 | 검은화면(gate 안 풀림) | **2층** |
| ② 전달 | packetsReceived, **seq 연속·개수 등식·ts 단조** | 검은화면/무음(forward 0), 멈춤(갭) | **2층** |
| ④ 코덱 | server.codec == client 선언 == 수신 pt | 검은화면(디코더 오선택) | **2층** |
| ③ 디코딩 | **framesDecoded / jb / pliCount** | 검은화면(pkts>0인데 안 그려짐), 지연/멈춤 | **3층 천장 — 넘김** |

### 3.3 경계 = framesDecoded/jb (실측 2점이 떠받침)
| | wire 안쪽 (2층) | 디코더/수신단 (3층) |
|---|---|---|
| 사례 | 0625 track_id 미회신 | 0624c 돌림노래(jb 807ms) |
| SFU wire | 버그 | **무죄(1:1, lost=0)** |
| 봇 | 정직화하면 잡음 | 불가(canned라 출렁 재현 못 함) |

> **분계선**: "SFU가 만든 것"(조립·라우팅·rewrite·통지) = 2층 / "SFU 통과 후 수신단"(NetEQ 증폭·디코딩·재생) = 3층.

---

## 4. 작업 항목 (5군데 — 순서 = 안전순)

> 각 항목 = 작업지침 1개. 현행 위치 + 등식 + 영향범위 + 완료정의 + 계층. 경로는 `crates/...`.

### W1. 봇 정직화 (P-3) — "가드 통과하려 거짓말" 제거
- **현행**: `oxe2e/src/bot/mod.rs:492-505` simulcast entry ssrc — 0625 S6에서 `ssrc=0`로 일부 정직화됨. **이걸 전면 원칙으로 못 박는다**: 봇이 보내는 모든 intent ssrc는 *실제 클라가 SDP enrich에서 채우는 그대로*. simulcast=SDP에 ssrc 없음 → 0. non-sim=SDP ssrc → 채움.
- **등식 없음(원칙)**: 봇 송신 계약 == 웹 클라 송신 계약. 둘이 다르면 회귀가 거짓.
- **영향범위**: bot/mod.rs 송신부만. judge·서버 무관.
- **완료정의**: 봇이 서버 가드를 우회하는 비정상 값(가짜 non-zero ssrc 등)을 단 하나도 안 보냄. simulcast_basic이 **새 서버 가드(`!is_sim`)와 짝으로** PASS(0625 §11 이미 확인).
- **계층**: 2층 전제(나머지 W가 이 위에 선다).

### W2. 봇 수신 원료 적재 (REQ-2.2) — 등식의 재료
- **현행**: `RtpMini`(oxrtc rtp_receiver.rs:8-15)가 **seq/ts/marker/pt를 이미 깐다**. 봇은 `bot/media.rs:282-287`에서 `rtp.ssrc`만 쓰고 버림. `RecvLog`(media.rs:251-255)=counts만. `BotResult.received`(mod.rs:52-75)=`HashMap<u32,u64>`.
- **변경**: `RecvLog`/`BotResult`에 **per-ssrc seq 리스트(+ts)** 추가. 무가공(P-3) 유지 — 해석 없이 받은 seq/ts 그대로 적재. (counts는 등식으로 대체되나 호환 위해 병행 가능.)
- **영향범위**: bot/media.rs(적재) + bot/mod.rs(BotResult 필드 + take_recv mod.rs:582). judge가 소비. 서버 무관.
- **완료정의**: judge가 봇별·ssrc별 수신 seq 집합·ts 열을 읽을 수 있다.
- **계층**: 2층 토대.

### W3. judge `count==0` → 등식 (REQ-2.1) — "잘 뚫린다" 직접 해소
- **현행**: `judge::evaluate`(judge/mod.rs:30). (a)이행 = `count==0`이면 FAIL(:55) → **1패킷이면 PASS**. (c)누수(:64)는 음성 단언 *있음* → **유지**.
- **격상 (등식 3종 + 식별/흐름 단언)**:
  1. **seq 집합 완전성**(②전달): 수신 ssrc별 seq 집합 S에 min(S)~max(S) 결손 0. localhost 무손실 → 갭=논리 버그. **재정렬≠손실 → 집합으로 본다**(도착 단조 아님, REQ-2.1 단서).
  2. **개수 등식**: |수신| == 봇 송신(canned, N 결정적) − gated. **gated까지 결정적인 케이스만**(정적 conf=성립, 화자전환=약한 단언으로 격리, REQ-2.1 단서). 무게는 구조 불변식에.
  3. **ts 단조/변환식**(③의 wire 단서): ts 단조. α(conf relay)=원본 동일, PTT=translate_rtp_ts.
  4. **track_id 회신**(식별 4축): PUBLISH_TRACKS 응답 tracks[].track_id가 client_pub.mid마다 실렸나. ← **0625 버그를 직접 잡는 단언**.
  5. **TRACKS_READY 존재**(①시그널링): JOIN→PUBLISH_TRACKS→TRACKS_READY opcode 순서 + TRACKS_READY 도달(검은화면 근본).
  6. **codec 정합**(④): server.codec == client 선언 == 수신 pt. (track-identity codec_mismatch 차용.)
- **현행 유지**: caching/gating/교차 4(telemetry/rtx/gate_resume/floor_granted) — 채점자 봇 밖(P-2) 이미 있음. 안 건드림.
- **영향범위**: oxe2e/src/judge/mod.rs + scenario verify_* 플래그. 서버 무관.
- **완료정의**: 검은화면(forward 0/TRACKS_READY 누락) + track_id 미회신 + codec mismatch가 각각 다른 FAIL 메시지로 떨어진다. count==0 단독 PASS 소멸.
- **계층**: 2층 본체.

### W4. 1층 빈 통증자리만 (REQ-1.1) — 무게중심 하향
> 297 유닛이 두터우나 **버그가 사는 두 칸이 비었다**(survey §F). 양 채우기 아님 — 이 둘만.
- **W4a. ③ release_subscribe_track 순서 등식**: `peer.rs:1002` 본문 순서(mid_map.remove→streams 정리→mid_pool.release)를 유닛으로. **재입장 미노출 버그 자리.** 3중 정합(mid_map↔SubscriberStreamIndex↔mid_pool) 연산 후 일치. (순수 메서드 — now 등 외부 의존 없음.)
- **W4b. ① TRACKS_UPDATE 조립 등식 + promote 수렴**:
  - **선결(코드 리팩터 — 별도 GO 필요)**: `build_tracks_update` **함수 부재**. add 경로가 `json!` 인라인 5중복(track_ops.rs:270,490 / helpers.rs:294,307,536). 순수 함수로 추출해야 유닛이 문다(REQ-1.3). **이 추출은 프로덕션 코드 변경이므로 부장님 별도 사인 후.**
  - 추출되면: "이 상태 → 이 페이로드" 등식(transform=1층). promote 두 경로 수렴 = transform(상태→페이로드)은 1층 / trigger(첫 RTP 시점 통지 유발)는 2층(W3-5와 연결).
- **영향범위**: W4a=oxsfud 유닛 추가(코드 변경 0). W4b=리팩터 선결(GO 후) + 유닛.
- **완료정의**: release 순서를 뒤집은 픽스처에서 유닛 FAIL. 조립 등식이 두 경로 동일 상태 → 동일 페이로드 증명.
- **계층**: 1층.

### W5. 검증기 음성 픽스처 (P-7, REQ-4.4) — 녹색불이 거짓말 안 하게
- **현행**: judge 자체 테스트(judge/mod.rs:482-531) = caching 2개뿐. evaluate/gating 누수 음성 분기엔 `#[cfg(test)]` 없음.
- **변경**: W3 신규 등식마다 **오염 픽스처**에서 FAIL 뱉는지 유닛으로 증명 — seq 갭 주입/약속외 ssrc 누출/track_id 누락/codec mismatch/TRACKS_READY 삭제. "음성 픽스처에서 안 떨어지는 단언은 단언이 아니다."
- **도구 음성도(0624b §4 교훈)**: neteq replay 절대값처럼 **도구가 거짓 신호** 줄 수 있음 → judge가 의존하는 외부값(ccc 등)이 비었을 때 verify_*가 FAIL하는지(0613d 이월 3번)도 음성으로.
- **영향범위**: oxe2e/src/judge/mod.rs `#[cfg(test)]`. 코드 변경 0(테스트만).
- **완료정의**: W3의 모든 신규 등식이 각자 음성 픽스처를 갖고, 깨진 입력에서 반드시 빨간불.
- **계층**: 검증기 자체(메타).

---

## 5. 계층별 최종 적재 (한눈에)

**1층 (cargo test — 순수 transform)**: release_subscribe_track 순서·3중 정합(W4a) / TRACKS_UPDATE 조립 등식·promote transform(W4b) / 기존 297 유지.

**2층 (oxe2e 봇 — 실제 시그널·RTP)**: 봇 정직(W1) / seq·ts 원료(W2) / 등식 6종(W3: seq 완전성·개수·ts·track_id 회신·TRACKS_READY·codec) / 음성 픽스처(W5) / 기존 caching·gating·교차 4 유지.

**3층 (안 함 — 넘김)**: framesDecoded·jb·NetEQ 증폭·디코딩·재생 품질. 단서(발신 IAT 출렁)는 wire에 보이니 2층이 "도착 간격 이상"으로 **관측만**, 판정 안 함.

---

## 6. 케이스 매트릭스 (REQ-2.3 — 빈칸 ⑥만 신설, 남발 안 함)
현행 toml 5개 = ①②③④⑤⑦⑧⑨ 커버(survey 조사5). **⑥ 레이어전환만 빔** + 봇에 SUBSCRIBE_LAYER 발신 경로 없음. → W3 등식이 서면 ⑥ 추가(봇 dispatch + judge). **나머지 케이스는 추가 안 함** — 등식 격상이 먼저, 케이스 수 늘리기 아님.

---

## 7. 회귀 보존 / 불변 원칙

- W1~W3은 **봇·judge만** — 서버 코드 무변경(W4b 리팩터만 예외, 별도 GO).
- 기존 conf_basic/ptt_rapid/simulcast_basic/duplex_cache/telemetry_collect 전부 PASS 유지가 각 W의 완료 조건.
- 불변 원칙 정합: PT 동적(codec 등식도 값 대조지 하드코딩 아님) / track_id 불투명(회신 단언은 존재·매칭만, 역추출 0) / SR 자체생성 금지(ts 등식은 relay 검증) / 봇 무가공(W2 적재는 해석 없음).

---

## 8. 기각 (안 하는 것 — 반복 유혹 차단)

- 3층(디코딩/NetEQ/framesDecoded/jb) 설계 — 부장님 지침, 천장 밖.
- exact diff(덤프 그대로 기준) — 등식(불변식)만.
- 풀 DST(VOPR) — 과잉. (결함주입은 W 이후 후속.)
- 1층 전 영역 297 더 쌓기 — 빈 통증자리 2칸(W4)만.
- 케이스 남발 — ⑥만, 등식 격상 후.
- 봇 "정교하게" — 정교할수록 거짓. 무가공이 정직(W1).
- count==0 유지 — W3가 등식으로 교체.

---

## 9. 순서 / 정지점

1. **W1 봇 정직화** → simulcast_basic PASS 유지(서버 가드 짝). 
2. **W2 봇 원료** → judge가 seq/ts 읽힘.
3. **W3 judge 등식** → 0625 track_id·검은화면 FAIL로 떨어지는지(음성으로). ★"잘 뚫린다" 직접 해소 지점.
4. **W5 음성 픽스처** → W3 등식마다 짝(동시 진행 가능).
5. **W4a 1층 release 순서** → 독립, 병행 가능.
6. **W4b build_tracks_update 추출** → ★코드 리팩터, 부장님 별도 GO 후. 그 다음 조립 등식·promote 수렴.

각 정지점: 작업 완료 → 보고서(변경 파일+요약) → 부장님 diff 검토 → GO 후 커밋. 커밋 전 회귀(oxe2e 커버 시나리오) PASS.

---

## 10. 한 줄 요약

> 봇을 정직화(W1)하고 원료를 들리고(W2), judge를 count→등식으로 올려(W3) SFU가 만든 것을 2층에서 잡고, 비어있던 1층 통증자리 2칸(W4)을 채우고, 검증기를 음성으로 못박는다(W5). framesDecoded/jb는 3층으로 넘긴다. 새 인프라 0, 5군데, 거품 없음.

---

*author: kodeholic (powered by Claude)*
*설계서. "코딩해" 전. W4b(build_tracks_update 추출)만 코드 리팩터라 별도 GO. 나머지는 봇·judge·유닛.*
