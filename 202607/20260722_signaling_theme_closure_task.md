# 20260722 — 시그널링 테마 종결 (문서 정합 + 계약 검증 잔여)

상태: **Phase A~E 완료 (테마 종결)** — 커밋 B:1fc5ca8 / C:e9f952d / D:d7b1ed3 / E-1:68ed02e (push 미실행). op 42. 부장님 결재 대기: push·E-2 마스터 반영·종결 게이트(2층 전체+3층)·다음 테마.

본 파일은 지침 + 실행 기록 통합 파일이다. §0~§10 지침 영역은 김과장 수정 금지. 이견·판단은 하단 실행 기록에 적는다.
본 지침 작성 = 김대리. 신규 세션 김과장이 실행.

> **[김과장 메모 20260722]** 본 파일은 착수 시점 디스크에 없었고 부장님이 세션에 직접 지침 전문을 전달했다.
> §0~§10 지침 영역은 "김과장 수정 금지"라 **손실 있는 붙여넣기에서 재구성하지 않는다**(재구성 = 지침 영역 훼손 위험).
> 부장님의 정본 §0~§10 을 본 표시선 위에 삽입해 주십시오(또는 지시 시 김과장이 대화의 전달본으로 재구성).
> 하단 "실행 기록 (김과장)"은 §6/§8 에 따라 김과장이 채운다.

<!-- ↑↑↑ 여기(§0~§10 지침 영역)에 부장님 정본 지침 전문 삽입 ↑↑↑ -->

---

# 실행 기록 (김과장)

## Phase A — 2026-07-22 (문서·기록 정합, 코드 무변경)

### A-1. 커밋/push 상태 확정 (실측)

* HEAD = `5e880b5` (§9 기대치와 일치). 워킹트리 clean, 미커밋 잔여 0.
* 커밋 3종 실재 확인: `cdcc9d5`(1단계 정의 A~H) · `dd146dc`(Phase I 진단 3종) · `5e880b5`(2단계 이관).
* **push**: sfu-server `main` = `origin/main` = `5e880b5` (로컬 추적 in-sync, `git log @{u}..HEAD` 공집합). → push 반영된 것으로 보임. 단 이는 로컬 ref 기준, push 실행 주체는 부장님.
* **A-1 규명(20260721 파일 내부 모순)**: 상단 상태 줄("커밋 5e880b5")이 사실, 마지막 실행 기록 줄("커밋 대기/미커밋 누적")이 stale 이었음 → 양쪽 표기 일치시킴(상태 줄에 "origin/main 반영" 추가, 마지막 줄을 "커밋 완료 5e880b5"로 정정, [20260722 정정] 주석).
* ⚠ **지침 A-4 좌표 오류 발견(이견 — §7 준수, 사실만 기재)**: A-4 는 `git show 5e880b5 -- context/PROJECT_MASTER.md` 로 마스터 diff 를 보라 하나, **context 는 sfu-server 와 별개 레포**(`oxlens-claude-context.git`)다. 5e880b5 는 sfu-server 커밋이라 context 파일을 담지 않는다. 마스터 3곳 수정은 **context 레포 커밋 `92b8683`("20260722_1", 부장님 authored, 07-22 03:01)** 에 있다 — 하단 A-4 참조.

### A-2. 1단계 파일 정정 (20260720b_oxsig_body_types_task.md)

* 상태 줄: "완료 (Phase A~H, commit 대기)" → "Phase A~H + Phase I, 커밋 cdcc9d5+dd146dc, origin/main 반영".
* Phase A 실행 기록 접미사 오기: **"Req/Res/Est" → "Req/Res/Event"** 정정.
* **시험 수 산수 규명(실측 종결)**:

  | ref | oxsig `#[test]` | oxsig `pub struct` |
  |---|---|---|
  | `cdcc9d5` (1단계 A~H) | **64** | **71** |
  | `dd146dc` (Phase I) | **69** (+5) | **106** (+35) |
  | `5e880b5` = HEAD (2단계) | **74** | **106** |

  - 기준선 "63"은 오기 — 직전 Phase B~H 는 **64**. Phase I 는 **+5**(열거된 시험도 정확히 5건). `git show dd146dc`: `+5 #[test] / −0`(삭제 없음). 64+5=69 일관. 즉 **삭제된 시험은 없었고, "63 + 6"은 순수 계산 오기**.
  - 타입 "108종"도 오기 — Phase I 는 data.rs +16(6→22)·ext.rs +19(6→25) = **+35**, 71→**106**. "+18/+37/108"은 계산 오기. 실측 `git grep 'pub struct' -- crates/oxsig/src/message`.
  - **현재 권위값 = 106종 / 74 PASS.** (74 는 2단계 5e880b5 에서 도달; Phase I 세션 끝은 69.)

### A-3. SESSION_INDEX 정정

* **07-20b 항목**: "71종 8파일 … 64 PASS" → "1단계 A~H(71) + Phase I(+35) = **106종** … wire 형상 시험 **69 PASS**, 커밋 cdcc9d5+dd146dc".
  - ⚠ **지침 A-3 목표값과의 이견(실측 우선)**: 지침 A-3 은 "108종 / 74 PASS"로 고치라 하나, 실측상 **108→106**(Phase I 실증가 +35), **74→69**(74 는 07-21 세션값이라 07-20b 행에 넣으면 07-21 행 "274+25+74"와 이중계산·오귀속). SESSION_INDEX 행은 세션 단위 요약이므로 07-20b 행 = 그 세션 끝값 **106종/69 PASS**가 정합. 지침의 "108/74"는 그 자체가 상속된 오기 — Phase A 의 목적(실측 확정)에 따라 실측값 적용. **부장님 GO 시 이 판단 확인 요청**(원하시면 74/108 로 되돌림).
* **07-21 항목**: "push 미실행" → "push 반영(로컬 추적 main=origin/main)". 나머지 유지.

### A-4. 마스터 문서 수정 3곳 규명 (context 레포 `92b8683`, 부장님 authored — 되돌리지 않음, 사실만)

되돌리지 말 것(§7). 3곳 모두 2단계 결과와 정합하며 부장님 본인 커밋이라 "명시 지시 없는 마스터 수정"에 해당하지 않음.

1. **PROJECT_MASTER.md** (§시그널링 계약, 단일 진실 줄):
   ```
   - 단일 진실: `crates/oxsig/src/opcode.rs` (설계서·카탈로그 문서 폐기, 20260623)
   + 단일 진실: `crates/oxsig/src/opcode.rs` (설계서·카탈로그 문서 폐기, 20260623). **body 타입 단일 권위 = `crates/oxsig/src/message/`** (2단계 이관 20260721 — 요청 `XxxReq`/응답 `XxxRes`/이벤트 `XxxEvent`, hub/sfud/oxrtc/oxadmin 공유. 구 `oxsfud/signaling/message.rs` 소멸)
   ```
2. **PROJECT_SERVER.md** (디렉토리 트리, oxsig 항 신설 줄):
   ```
   + │   └── src/message/    ← **wire body 타입 단일 권위**(2단계 이관 20260721 — 8파일 도메인 nibble 축). 요청 `XxxReq`/응답 `XxxRes`/이벤트 `XxxEvent`. session/room/media/scope/data/ext/admin + ack(AckFail 2계 어휘). Value 잔존 = 정당한 곳만(ANNOTATE relay·진단 자유중첩·getStats 통째 spread)
   ```
3. **PROJECT_SERVER.md** (signaling/ 하위, message.rs 줄 교체):
   ```
   - │   │   ├── message.rs  — 패킷 타입 (common::Packet re-export) + ScopeUpdate/Set/EventPayload
   - │   │   └── handler/    — gRPC dispatch (8파일)
   + │   │   └── handler/    — gRPC dispatch (8파일). Packet=`common::signaling::Packet`, body 타입=`oxsig::message` 직접 참조 (**message.rs 삭제 20260721 2단계** — 구 요청 15종·ScopeEventPayload·RoomEventPayload 소멸, body 계약 oxsig 단일 권위)
   ```

### A-5. 2단계 §8 미충족분 보완

* 20260721 파일 하단에 **"§8 산출물 보완"** 절 append 완료: ①개명 타입 전수(구 17종 → 개명 13 + 동명 3 + 청산 1) ②도메인별 조립부 수(요청 소비처 9파일 · 응답/이벤트 Packet::ok/new 31곳 + tasks/ingress 인라인 + hub 인라인 ws12·moderate6·admin) ③SESSION_INDEX 에만 있던 문서 발견 2건(SCOPE_EVENT pub 단수 미반영 / 3층 spec수 14→15) 기재.

### 판단한 것 (요약)

* 실측이 지침의 상속 오기(108종·74 PASS·"63+6")를 정정 — Phase A 의 명시 목적("실측으로 사실 확정, 양쪽 표기 일치")에 따라 **실측값 우선** 적용. 지침 A-3/A-4 의 사실 오류 2건은 §7("지침 영역 수정 금지, 이견은 실행 기록")대로 본 실행 기록에만 적고 지침 §0~§10 은 손대지 않음.
* 코드 무변경(A 는 문서 작업). cargo/게이트 실행 없음(게이트 없는 Phase).

### 게이트 결과

* 없음(문서 정합 Phase, 코드 무변경).

### 정지점 보고 (Phase A 끝 — commit + 보고 + GO 대기)

* 수정 파일(전부 context 레포, 부장님 커밋 대기 — Claude 는 파일 수정만):
  - `202607/20260720b_oxsig_body_types_task.md` (A-2)
  - `202607/20260721_oxsig_body_migration_task.md` (A-1 상태/마지막 줄 + A-5 §8 보완 절)
  - `SESSION_INDEX_202607.md` (A-3)
  - `202607/20260722_signaling_theme_closure_task.md` (본 파일 — §0~§10 정본 삽입은 부장님 대기)
* **부장님 결정 요청 2건**:
  1. **A-3 07-20b 행 수치** — 실측 106종/69 PASS 적용함(지침의 108/74 는 상속 오기 규명). 이대로 확정? 아니면 다른 표기?
  2. **본 파일 §0~§10 정본** — 붙여넣기 재구성 위험 회피로 미기재. 부장님 삽입 vs 김과장 재구성 지시?
* GO 시 Phase B(ACTIVE_SPEAKERS 0x2500 철거 — 첫 코드 변경 Phase) 착수.

## Phase B — 2026-07-22 (ACTIVE_SPEAKERS 0x2500 철거)

### 제거 좌표 전수 (실측 재확인 후 착수)

grep 전수(`ACTIVE_SPEAKERS`/`0x2500`/`::SPEAKERS`) 결과, 실 코드 참조는 아래 3파일뿐. 나머지는 전부 주석/산 DC 코드.

| 파일 | 제거/변경 |
|---|---|
| `crates/oxsig/src/opcode.rs` | ①const `ACTIVE_SPEAKERS`(L100) → tombstone 주석 ②ALL_OPS 항목 ③event_category 목록 ④key_op_values assert ⑤catalog_size `44→43`(주석 changelog 추가) ⑥모듈 doc "5=Speakers" 제거 ⑦헤더 changelog 철거 기재. **헤더 "총 43 op" 는 이미 43 이었고(구 ADMIN_DOWNLINK_INJECT 추가 시 테스트만 44 로 고친 미정합), 이번 철거로 실 op 44→43 되며 헤더와 자동 일치** |
| `crates/common/src/signaling/mod.rs` | ①※ 주석 블록 ②`priority_of` 0x2500 arm ③`intent::SPEAKERS` const → **결번 주석**(1<<5 비움, MODERATE 1<<6 이동 금지) ④`intent_bit_of` 0x2500 arm ⑤`priority_info` 테스트 assert |
| `crates/oxrtc/src/signal_client.rs` | `common_requires_ack` catch-all `_ => op != ACTIVE_SPEAKERS` → `_ => true` (ACK 예외 3종 외 전 op ACK 의무. no-ack 특례 소멸) |

### 준수 확인

* **intent 1<<5 결번 유지** — SPEAKERS const 제거하되 값 미이동. MODERATE=1<<6 불변(클라 비트마스크 정합). ✓
* **DC 경로 무수정** — `tasks.rs`(build_speakers_dc_payload)·`config.rs`(broadcast 주기)·`domain/speaker_tracker.rs`·`ws/outbound.rs`(SVC_SPEAKERS/broadcast_dc_svc)는 손대지 않음. 산 코드. ✓
* **oxsig/message/ speakers 타입 없음** — 확인만(생성된 적 없음). ✓

### 게이트 결과 (김과장 범위)

* `cargo check --workspace` **무경고**.
* 단위: `cargo test -p oxsig` **74** · `-p common` **20** · `-p oxsfud` **274**(1 ignored) · `-p oxhubd` **25** — 전부 PASS. (제거한 두 assert 는 기존 테스트 함수 내부 줄이라 테스트 수 불변; catalog_size 는 43 으로 갱신되어 통과.)
* **2층 `run-all --core` = 부장님 확인 OK**(2026-07-22) — Phase B wire 회귀 없음 확정.
* **커밋 `1fc5ca8`**(소스 커밋은 김과장 몫으로 전환 — 부장님 지시 2026-07-22). main 직접, 브랜치 미분할. push 미실행(부장님 결재).

### 발견_사항 (보고만 — §5 범위 밖, 손대지 않음)

1. **stale 주석 2건** — 철거된 op 를 이름으로 참조하나 §5 Phase B 수정 허용 파일 밖:
   - `crates/oxsig/src/message/mod.rs:13` — "ACTIVE_SPEAKERS(0x2500)는 wire 미발송(DC 이관) — 타입 생성 금지"(§5 는 message/* 를 Phase D 필드추가만 허용).
   - `crates/common/src/ws/outbound.rs:264` — priority 분류 주석 "0x2500 Active Speakers"(§5 는 common/signaling/mod.rs 만 허용).
   둘 다 컴파일 무관(주석). 다음 정합 라운드 or 부장님 지시 시 청소.
2. **DC 경로가 "ACTIVE_SPEAKERS" 명칭 보존** — `tasks.rs:324`/`config.rs:430`/`speaker_tracker.rs:14` 가 DC payload·config·doc 에서 여전히 "ACTIVE_SPEAKERS"를 feature 명으로 사용. 산 코드라 유지가 정상이나, wire op 소멸 후 DC 층이 같은 이름을 쓰는 형국 — E-3 이월(DC body 계약)에서 재명명 검토 후보.

### 정지 상태

* Phase B 는 정지점 아님(정지점 = A끝 / C착수전 / C끝). 단 **Phase C 착수 전이 ★정지점**(FLOOR_MBCP 최고위험, 영향 범위 보고 + GO 필수)이므로 여기서 대기.
* **부장님 2건 대기**: ①Phase B 2층 `run-all --core` 결과 ②Phase C 착수용 영향 범위 실측 보고 요청 시 착수(아직 미실측 — GO 후 실측·보고).

## Phase C — 영향 범위 실측 (2026-07-22, ★착수 전 정지점 — 코드 무변경, GO 대기)

FLOOR_MBCP(0x2400) 는 ACTIVE_SPEAKERS 와 격이 다르다. **WS bearer 가 산 경로**이고 wire 필드·hub 라우팅·봇·OutboundQueue 유일 CRITICAL 예제까지 관통한다. grep 전수 + 핵심 경로 정독 결과:

### ★ 최중대 발견 — S-h(20260610) WS unicast fallback (bearer="dc" 에서도 산다)

`domain/floor_broadcast.rs:296-345` (`broadcast_floor_frame`/`send_floor_frame_to`)의 **dc 분기**는, DC 미수립 참가자에게 `send_dc_wrapped` 실패 시 **WS unicast fallback**(op=FLOOR_MBCP)을 쏜다. 주석 명시:

> "cross-sfu/청취 전용(affiliate) 참가자는 이 sfud 와 publish PC(DC)가 없어 floor 이벤트가 영구 미달 — bearer '세션 불변' 원칙은 송신 선택이지 **도달성 포기가 아님**."

즉 `bearer="ws"` 설정 경로뿐 아니라, **default `dc` 에서도 DC 없는 참가자(다방청취 listen-only·cross-sfu affiliate)의 floor 도달을 WS fallback 이 보장**한다. FLOOR_MBCP 철거 = 이 fallback 소멸 = **DC 없는 참가자 floor 이벤트 영구 미달**.

- 연결: [[project_multiroom_ptt_only]] — 다방청취는 PTT 전용, 청취자는 현재 화자를 알아야 함. listen-only 참가자가 해당 sfud 에 DC 를 갖는지 여부가 관건. **DC 미보유면 이 철거로 다방청취 floor 표시가 깨진다.**
- ★ **부장님 재확인 필요**: "WS fallback 포기 확정" 결정이 **이 S-h 도달성 손실(특히 다방청취/cross-sfu 청취자)**을 포함하는가? 포함이면 → 청취자 floor 도달 대안(DC 강제 수립? floor DC 전용 전제 성립?) 확인 후 착수. 미포함이면 → Phase C 재설계.

### wire 계약 영향

- **`server_config.floor_bearer` 는 wire 필드** (`oxsig/message/room.rs:183` RoomJoinRes → ROOM_JOIN 응답으로 클라 통보). WS bearer 제거 후 처분 결정 필요:
  - (a) 필드 존치·항상 `"dc"` → wire 불변(§2 정합). **추천.**
  - (b) 필드 제거 → wire 변경, §2("0x2400/0x2500 외 바이트 변경 금지") 위반. 기각 후보.

### 제거·판단 좌표 전수

| 파일 | 좌표 | 처분 |
|---|---|---|
| `oxsig/opcode.rs` | const(98)·body 포맷 주석(198)·`body_is_binary`(200-202)·ALL_OPS(257)·event_category(337)·key_op_values(434)·`body_is_binary` 테스트(380/385-390)·catalog_size **43→42** | 제거. ★`body_is_binary` = 유일 binary op 소멸 → **항상 false**. **함수 존치(stub)/폐기 판단 필요**(추천: 폐기 + 호출처 binary 분기 정리, 단 호출처 면적 확인 후) |
| `oxsig/header.rs` | 테스트 277-279 (`0x2400` 픽스처) | 다른 op 값으로 교체(단순 픽스처) |
| `common/signaling/mod.rs` | `priority_of` 0x2400=CRITICAL(44)·`intent_bit_of` 0x2400=FLOOR(83)·`intent::FLOOR`(1<<4, 73)·`priority_critical` 테스트(97)·`intent_event_categories` 테스트(123) | 제거. intent::FLOOR(1<<4) 결번 처리(값 이동 금지) |
| `common/ws/outbound.rs` | FLOOR_MBCP 를 **유일 CRITICAL(0) 예제**로 쓰는 테스트 다수(217/230/262/273/275/282) | ★CRITICAL 레벨 자체는 MODERATE_EVENT(0x2700)로 존속 → 테스트 예제를 **MODERATE_EVENT 로 교체**(레벨 삭제 아님) |
| `oxsfud/domain/floor_broadcast.rs` | `broadcast_floor_frame`/`send_floor_frame_to` ws 분기(287-295, 327-333) + **S-h dc-miss WS fallback**(303-313, 337-343) + `ws_wire_from_mbcp`/헤더 주석 | ws 분기 철거. ★S-h fallback 은 위 최중대 결정에 종속 |
| `oxsfud/signaling/handler/floor_ops.rs` | `handle_floor_binary`(37~) 전체 — WS bearer 진입 핸들러 | 철거(모듈 전체 후보) |
| `oxsfud/grpc/sfu_service.rs` | 84-88 op=FLOOR_MBCP → handle_floor_binary 분기 | 철거 |
| `oxsfud` bearer 배관 | `lib.rs`(119-123,171,244,301-305)·`state.rs`(31-59 floor_bearer)·`tasks.rs`(32,78-79)·`config`·`common/config/policy.rs`(80-91 bearer 필드)·호출처 helpers/room_ops/track_ops(bearer 인자) | ★**bearer 추상 붕괴 범위 결정 필요**: (a) "ws" arm 만 제거 vs (b) bearer 파라미터 전체 철거·dc 단일화. (b)가 깨끗하나 관통 대공사 |
| `oxhubd/ws/mod.rs` | FLOOR_MBCP passthrough(266-272)·room 라우팅 drop 경고(472-501)·헤더 주석(7) | 철거. 철거 후 binary op 부재 → WS JSON 전용(266-272 특례 제거 시 binary 수신은 JSON parse→conn close, 단 클라가 DC 전용이면 0x2400 WS 송신 없음) |
| `oxrtc/signal_client.rs` | 68-69 FLOOR_MBCP binary 파싱 분기 (S-h 주석) | 철거(봇도 DC 전용 전제) |
| `oxhubd/events/mod.rs`, `moderate/handler.rs` | 주석만(176, 6) | 주석 정합 |

### DC 본체 (존치 — 손대지 않음)

`datachannel/mod.rs`(SVC_MBCP), `mbcp_native.rs`(TLV), `broadcast_dc_svc`, `send_dc_to_peer`, `apply_floor_actions` 의 dc 경로 — 전부 산 코드.

### 게이트 계획 (부장님)

cargo check --workspace + 단위(oxsig/common/oxsfud/oxhubd) + **2층 run-all 전체**(--core 아님) + **3층 라이브 PTT 시나리오**(floor DC 전용 실동작 필수). PTT floor 가 DC 로만 도는지 3층 확증 없이는 종결 불가.

### ★ 부장님 결정 요청 (착수 전 GO 게이트)

1. **S-h 도달성(최중대)** — WS fallback 포기가 다방청취/cross-sfu 청취자 floor 미달을 포함하는가? 청취자 DC 보유 실측 필요할 수도.
2. **server_config.floor_bearer wire 필드** — 존치·항상 "dc"(추천) vs 제거?
3. **bearer 추상 범위** — "ws" arm 만 vs bearer 파라미터 전체 철거?
4. **body_is_binary** — 폐기(추천) vs 항상-false 존치?

위 4건 결정 + GO 전까지 **코드 무변경 대기**.

### 착수 (2026-07-22, 부장님 GO "계획대로 진행, 번복 안한다")

결정 4건 확정: ①S-h WS fallback 포기(번복 없음) ②floor_bearer wire 필드 존치·항상 "dc" ③bearer 추상 전체 철거·dc 단일화 ④body_is_binary 폐기.

**철거 실적 (17파일, floor_ops.rs 삭제, 순 −411줄)**:

| 파일 | 처분 |
|---|---|
| `oxsig/opcode.rs` | FLOOR_MBCP const·ALL_OPS·event_category·key_op_values·**body_is_binary 함수+테스트 2건 폐기**·catalog_size 43→42·모듈 doc "4=Floor"·헤더 "42 op" |
| `common/signaling/mod.rs` | priority 0x2400·intent_bit_of 0x2400·**intent::FLOOR(1<<4) 결번**·priority_critical/intent_event_categories 테스트 |
| `common/ws/outbound.rs` | 유일 CRITICAL 예제 FLOOR_MBCP → **MODERATE_EVENT(0x2700)** 교체(CRITICAL 레벨 존속) |
| `oxsfud/domain/floor_broadcast.rs` | ws_wire_from_mbcp 삭제·apply_floor_actions/broadcast_floor_frame/send_floor_frame_to 에서 **bearer+event_tx 제거**·ws 분기·**S-h WS fallback 제거**·debug 로그 [FLOOR:DC] |
| `oxsfud/signaling/handler/floor_ops.rs` | **파일 삭제**(handle_floor_binary WS 핸들러 전체) |
| `oxsfud/grpc/sfu_service.rs` | FLOOR_MBCP passthrough 분기 삭제 + 모듈 doc |
| `oxsfud/datachannel/mod.rs` | event_tx 배관 전면 제거(run_sctp_loop→process_association_events→handle_stream_event→handle_dc_binary→handle_mbcp) — DC 인입 floor 의 WS fallback 통로였음 |
| `oxsfud/{lib,state,tasks,transport/udp/mod}.rs` | floor_bearer + DC event_tx 배관 철거(config 미독·AppState 필드·run_floor_timer·run_sctp_loop 인자) |
| `oxsfud/signaling/handler/{room_ops,helpers,track_ops}.rs` | apply_floor_actions 호출 인자 정리. **room_ops server_config.floor_bearer = "dc" 고정**(wire 필드 존치) |
| `oxhubd/ws/mod.rs` | FLOOR_MBCP passthrough(266) + **forward_wire_to_sfud 함수 삭제** + 헤더 doc |
| `oxrtc/signal_client.rs` | wire_to_packet FLOOR_MBCP binary 분기 삭제 |

**게이트 결과 (김과장 범위)**:
* `cargo check --workspace` **무경고**.
* 단위: oxsig **72**(구 74 −2, body_format 테스트 폐기) · common **20** · oxsfud **274**(1 ign) · oxhubd **25** · oxrtc **6** — 전부 PASS.
* 컴파일 캐스케이드 해소 실증: event_tx 미사용 경고가 DC 배관 5단(handle_mbcp→handle_dc_binary→handle_stream_event→process_association_events→run_sctp_loop→transport)으로 전파 — 전부 제거로 수렴. **이것이 곧 "event_tx 는 오로지 S-h WS fallback 위해 DC 경로에 심겼다"는 증명**(다른 소비처 있었으면 경고가 거기서 멈춤).
* ★ **2층 `run-all` 전체 + 3층 라이브 PTT = 부장님 실행 대기**. floor DC 단일 전환이라 **3층 PTT 실동작(발화권 grant/taken/release DC 전달)** 확증 필수 — [[feedback_layer2_pass_not_final]].

**발견_사항 (보고만 — §5 범위 밖 stale 주석, 미수정)**:
1. `oxsig/message/mod.rs:12` — FLOOR_MBCP 참조 주석(message/* 는 Phase D 필드추가만 허용).
2. `oxhubd/events/mod.rs:176` · `oxhubd/moderate/handler.rs:6` — FLOOR_MBCP 참조 주석(ws 아님).
3. `oxsig/header.rs:277-279` — `round_trip_floor_mbcp_category` 테스트가 리터럴 0x2400 사용(const 아님 → 컴파일·PASS 정상). 이름만 stale, Event nibble 왕복 검증 자체는 유효. header.rs §5 미포함.
4. `common/config/policy.rs` FloorPolicy.bearer — lib.rs 미독 전환 후 **파싱만 되는 dead config**. 스키마/policy.toml 변경 위험 회피로 struct 존치. E-3 이월(dead config 청소).

### 정지점 (Phase C 끝 ★) — 부장님 대기

* **2층 `run-all` 전체 = 부장님 완료(2026-07-22)** — floor DC 단일 전환 봇 회귀 없음.
* **3층 라이브 PTT = 김과장 실행 완료(부장님 지시, 2026-07-22)** — `oxlens-home/qa/live` Playwright(hub1974+sfud 부장님 기동, fake media 실브라우저). **전체 20 → 18 passed / 1 failed / 1 skipped**.
  - failed = `onepc.spec.ts ONEPC-CONF-01`(framesDecoded>0) — **floor 무관 1PC 회의 시험**. **단독 재실행 5/5 통과**(ONEPC-PTT-01 무전 스모크 포함) → 직렬 스위트 SFU 상태 잔류 flaky 확정, **Phase C 회귀 아님**. [§6 판정 규칙 준수] 20260721 3층 기록의 동일 known-flaky(당시도 단독 5/5)와 대조 일치.
  - ★ **floor/PTT/다방 실동작 확증**: `conf_duplex`(half-duplex PTT), `conf_multiroom`(다방청취), `removal_leave_clean`(**다방 RA home+RB listen, crossSfu=true — S-h 영향 정확 대상**), `removal_select_migrate`(cross-sfu 발언방 전환 talk 이벤트 생존), 단독 `ONEPC-PTT-01`(floor 부여+청자 slot audio) — **전부 통과**. floor DC 단일 전환이 다방청취/cross-sfu 청취자 floor 도달을 깨지 않음을 실측 확인.
* 커밋: **e9f952d**(김과장 소스 커밋, main, push 미실행).
* **Phase C 게이트 전부 통과(2층 전체 + 3층). 정지점 GO 대기 → Phase D.**

## Phase D — 요청 타입 누락 필드 재검 (2026-07-22)

방법: oxsig 전 XxxReq(진단 3종·admin 제외) ↔ **클라 sdk0.2 생산부 실측** 대조. 표준 대조 금지(클라 실코드=계약). sdk0.2 body 빌더 전수 스윕 + oxsig 타입 정독.

### op별 대조표 (클라 송신 필드 ↔ oxsig 타입 ↔ 처분)

| op | sdk0.2 송신 필드 | oxsig 타입 | 어긋남 | 처분 |
|---|---|---|---|---|
| IDENTIFY 0x0002 | `token, user_id` (signaling.ts:389) | `user_id?` | **token 누락** | **★ token 추가** |
| TOKEN_REFRESH 0x0102 | `token` | `token` | — | 무변경 |
| ROOM_CREATE 0x1002 | `room_id, name, capacity?` | +active_speaker(서버기본) | 타입 초과만 | 무변경 |
| ROOM_JOIN 0x1003 | `room_id, role, select?, pc_mode?` | +participant_type?/intents? | 타입 초과만 | 무변경 |
| ROOM_LEAVE 0x1004 | `room_id` | +target_user?(admin) | 타입 초과만 | 무변경 |
| ROOM_SYNC 0x1005 | `room_id` | `room_id?` | — | 무변경 |
| PUBLISH_TRACKS 0x1101 | action,room_id,tracks[{kind,mid,duplex,simulcast,ssrc,source?,codec?,rtx_ssrc?}],extmap ids,video_pt?,rtx_pt? | 전부 보유 | — | 무변경 |
| TRACKS_READY 0x1102 | `room_id` | +ssrcs(화석) | 타입 초과만 | 무변경 |
| CAMERA_READY 0x1104 | `room_id` | `room_id` | — | 무변경 |
| SUBSCRIBE_LAYER 0x1105 | `room_id, targets[{user_id,rid}]` | 동일 | — | 무변경 |
| TRACK_STATE_REQ 0x1106 | `room_id, track_id, ssrc, muted|duplex` | 전부 보유 | — | 무변경 |
| SCOPE 0x1200 | `mode:'update', pub_select|pub_deselect` | ScopeUpdateReq 보유 | — | 무변경 |

**결론: 어긋남(클라 송신 ↔ 타입 미보유) = IDENTIFY.token 단 1건.** 나머지는 2단계 이관이 sdk0.2 좌표를 이미 교차해 전부 포섭(타입 doc 에 생산부 좌표 기재) — Phase D 가 그 완성도를 실증.

### 처분 (필드 추가만, wire 불변, 서버 동작 무변경)

* `oxsig/message/session.rs` **IdentifyReq 에 `token: Option<String>`(#[serde(default)]) 추가**. 서버 미파싱(인증=쿼리 token) 유지 — 계약(=클라 실발신) 표현용. doc 갱신.

### 발견_사항 (보고만 — sdk0.2 생산부 부재, 필드추가 아님)

1. **sdk0.2 미발신 요청 타입** — MESSAGE(MessageReq)·MODERATE(ModerateReq)·ROOM_LIST(타입없음): sdk0.2 송신처 0. 채팅/moderate 미배선(다른 클라/역할 UI or 미이식). 서버 파싱부 근거로 타입 존치.
2. **ScopeSetReq(mode='set')** — sdk0.2 는 'update' 만, 'set' 미발신. 타입 존치(서버 지원).
3. **MuteUpdateReq(0x1103)** — sdk0.2 미발신(TRACK_STATE_REQ 이관, 하위호환 생존).
4. **admin 3종** — 생산자=oxadmin, sdk0.2 범위 밖. 미대조.
5. **Android(oxlens-sdk-core)** — 범위 밖(휴면).

### 게이트

* `cargo check --workspace` **무경고** · oxsig **72**·oxsfud **274**·oxhubd **25** PASS. (token=Option+default, wire 하위호환·서버 미사용 → 회귀 불가.)
* 2층 `run-all --core` = 부장님 대기.
* 커밋: **d7b1ed3**(김과장 소스 커밋, main, push 미실행).

## Phase E — 종결 (2026-07-22)

### E-1. 카탈로그 최종 정합 (코드 — 완료)

* **op 총수 = 42** 확정 (44 → ACTIVE_SPEAKERS 철거 43 → FLOOR_MBCP 철거 42). `catalog_size` assert 42·헤더 "총 42 op"·changelog 3줄 일치. `cargo test -p oxsig catalog` PASS.
* **폐기 문서 참조 2건 정정**(실측: `context/design/` 디렉토리 부재→architecture/ rename 0620, `wire_v3_catalog` 부재):
  - opcode.rs 헤더 `설계서: context/design/20260516_signaling_v3.md §5` → **"단일 진실=본 파일, 설계서·wire 카탈로그 문서 폐기(20260623), body 권위=oxsig::message + PROJECT_MASTER op 표"**.
  - catalog_size 주석 `변경 시 설계서 + wire_v3_catalog 동시 갱신` → **"변경 시 PROJECT_MASTER op 표 갱신(구 문서 폐기 20260623)"**.

### E-2. 마스터 문서 현행화 **초안** (★ PROJECT_MASTER 직접 수정 금지 — 부장님 위치·형식 지정 대기)

아래는 PROJECT_MASTER.md 에 반영이 필요한 항목의 초안. 실측 근거 병기. **부장님 지정 전까지 마스터 파일 미수정.**

**(a) op 총수·산식** — L107 `총 44 op … → 44(ADMIN_DOWNLINK_INJECT)` →
> 총 **42 op**. 산식 꼬리: 44 → 43(ACTIVE_SPEAKERS 0x2500 철거 20260722) → 42(FLOOR_MBCP 0x2400 철거 20260722).

**(b) Event 카테고리 설명** — L99 `0x2000~0x2FFF Event (… body=JSON, FLOOR_MBCP 만 binary)` →
> `… body=JSON` (**"FLOOR_MBCP 만 binary" 삭제** — binary body op 소멸, 전 op JSON).

**(c) op 표 행**:
- L154 `0x2400 FLOOR_MBCP …` → **행 삭제/취소선**: `~~0x2400 FLOOR_MBCP~~ **철거 20260722** — WS bearer 포기, floor 발화권은 DC SVC_MBCP(mbcp_native TLV) 단일. 카탈로그 43→42`.
- L155 `0x2500 ACTIVE_SPEAKERS …` → **행 삭제/취소선**: `~~0x2500 ACTIVE_SPEAKERS~~ **철거 20260722** — wire 미발송, 화자 통보 DC SVC_SPEAKERS 단일. 카탈로그 44→43`.
- (L150 LAYER_CHANGED 0x2106 폐기 행 — 이미 취소선. 유지.)
- (L166 ADMIN_DOWNLINK_INJECT 0x3005 — 이미 존재. 유지.)

**(d) Floor 일원화 문구** — L170 `… bearer=ws fallback 시에도 동일 MBCP 바이너리를 WS binary 프레임으로 전달` → **문구 정정**:
> Floor Control 은 DataChannel MBCP(TS 24.380) **단일**(0x2400 FLOOR_MBCP op·WS bearer·S-h DC-miss WS fallback 전부 철거 20260722). DC 미수립 참가자 floor 미달은 DC 전용 전제.

**(e) v2→v3 매핑 꼬리** — L172 `… body=JSON 기본 + 0x2400 만 binary` → `body=JSON (0x2400 binary 철거 20260722, 전 op JSON)`.

**(f) body 계약 권위** — L91 이미 `body 타입 단일 권위 = crates/oxsig/src/message/`(부장님 92b8683). ✅ 반영됨.

**(g) 반쪽/특수 op 현행 상태 명기** (실측):
- **RECONNECT(0x0103)** — 서버 emit **생존**(oxhubd `rest/admin.rs:145-151`, admin graceful reconnect → broadcast_to_room/all_clients). sdk0.2 ops.ts 에 op **부재**(`RECONNECTING` 은 연결상태 문자열, 0x0103 아님) → 클라 미디코드(default 흡수). **반쪽 op(서버발신·클라무처리) 현행 유지**.
- **SCOPE_EVENT(0x2200)** — 타입 존재, **emit 0**(grep 확인) — 미구현(S-d 설계 대기) 상태 그대로.
- **MUTE_UPDATE(0x1103)** — sdk0.2 **미발신**(TRACK_STATE_REQ 0x1106 로 이관), 서버 **하위호환 파싱 경로 생존**(@handler/mod.rs:99). 마스터가 "클라 송신 폐기"면 절반만 사실(서버 경로 생존) — 정확히 기술 필요.

### E-3. 잔여 이월 목록 (본 테마 미착수 — 다음 테마 진입 근거)

1. **oxrtc 요청 조립 이관** — 봇이 `json!` 직접 조립(계약 타입 미사용). 계약 검증 도구가 계약을 안 쓰는 구조 → 2층 게이트 신뢰 한계.
2. **Android SDK(oxlens-sdk-core) 대칭** — Phase D 는 sdk0.2 만. Android 미대조(휴면).
3. **DC body 계약** — `build_speakers_dc_payload`·mbcp_native TLV 등. 빌더만 있고 파서·시험·문서 전무. wire 와 같은 평면인데 본 테마(wire 평면) 범위 밖.
4. **body 안 ok/op/pid 중복 실은 자리 청산** — 헤더가 단일 권위인데 body 에 중복.
5. **intent 기구 생사 처분** — 클라가 ROOM_JOIN.intents 미발신 → 비트마스크 전체 미행사. FLOOR(1<<4)/SPEAKERS(1<<5) 결번 추가로 누적. 기구 존폐 결정 필요.
6. **1단계 명명 이탈** — `AnnotateEventInjected`(어미 아님)·`ScopeEvent`(Res 인데 Event 이름, 응답과 공유)·`UserProbeReqEvent`/`UserProbeReplyReq`(op명↔접미사 엇갈림).
7. **진단 3종 sdk0.2 포팅** — TELEMETRY/CLIENT_EVENT/USER_PROBE_REPLY 타입은 sdk/(구 JS)에서 뽑음. sdk0.2 관측계층 미이식(v0.3 백로그). 포팅 시 재검(부장님 확정).
8. **stale 주석 청소** — Phase B/C 발견분: `oxsig/message/mod.rs`·`common/ws/outbound.rs`·`oxhubd/events/mod.rs`·`oxhubd/moderate/handler.rs`·`oxsig/header.rs`(round_trip_floor_mbcp_category 명칭) FLOOR_MBCP/ACTIVE_SPEAKERS 잔존 참조.
9. **dead config** — `common/config/policy.rs` FloorPolicy.bearer (lib.rs 미독 전환, 파싱만). policy.toml `[floor] bearer` 동반 청소.
10. **sdk0.2 미발신 요청 타입** — MESSAGE/MODERATE 클라 배선 or 타입 처분 결정(Phase D 발견).
11. **sdk0.2 op 카탈로그 동기** — ops.ts 에 FLOOR_MBCP·LAYER_CHANGED·(ACTIVE_SPEAKERS?) 잔존. 서버 철거분과 미동기(클라가 미발신이라 무해하나 카탈로그 표류).

### 게이트 (Phase E — 종결 게이트)

* `cargo check --workspace` **무경고** · 전 crate 단위(oxsig 72·common 20·oxsfud 274·oxhubd 25·oxrtc 6) — E-1 코드(주석 정정) 회귀 없음.
* ★ **2층 `run-all` 전체 + 3층 라이브 = 부장님**(종결 최종 게이트).
* 커밋: **(하단 참조 — E-1 opcode.rs 주석 정정)**.
* E-2 마스터 반영 = **부장님 위치·형식 지정 대기**(초안까지).

---

# 종결 보고 (시그널링 테마)

**커밋/push 상태**: 소스(oxlens-sfu-server) main 에 4커밋 — `1fc5ca8`(B) · `e9f952d`(C) · `d7b1ed3`(D) · `68ed02e`(E-1). **push 미실행**(origin/main=5e880b5, 부장님 결재). Phase A 는 context 문서만(부장님 context 레포 커밋). 워킹트리 clean.

**최종 op 총수**: **42** (44 → ACTIVE_SPEAKERS 0x2500 철거 43 → FLOOR_MBCP 0x2400 철거 42). opcode.rs 헤더·catalog_size assert·changelog 3중 일치.

**Phase D 어긋남 표**: sdk0.2 전 요청 op 대조 → 어긋남 **1건** = IdentifyReq 에 `token` 누락(클라 `{token,user_id}` 발신, 타입 `user_id` 만) → 추가. 나머지 12 op 는 2단계가 이미 포섭.

**게이트 종합**: cargo check --workspace 무경고(전 Phase) · 단위 oxsig 72·common 20·oxsfud 274·oxhubd 25·oxrtc 6 · 2층 run-all(A~C 부장님 확인) · 3층 라이브 PTT(C, 김과장 — floor/다방/cross-sfu 전부 통과, onepc flaky 단독 5/5). **Phase D 2층 --core·Phase E 종결 2층전체+3층 = 부장님 잔여**.

**잔여 이월 목록**: 11건 (E-3 참조) — oxrtc 조립 이관·Android 대칭·DC body 계약·ok/op/pid 중복·intent 기구 생사·명명 이탈·진단 sdk0.2 포팅·stale 주석 청소·dead config·MESSAGE/MODERATE 배선·sdk0.2 op 카탈로그 동기.

**발견_사항 종합**:
- Phase A: 지침 자체 오류 2건(A-4 context 레포 좌표·A-3 108/74 상속 오기) — 실행 기록에 규명, 지침 §0~§10 미수정.
- Phase B/C: stale 주석 6곳(§5 밖, 미수정) + DC 경로 "ACTIVE_SPEAKERS/floor" 명칭 보존.
- Phase D: sdk0.2 미발신 요청 타입(MESSAGE/MODERATE/ROOM_LIST)·ScopeSetReq('set' 미발신)·MuteUpdateReq 레거시.
- Phase E: RECONNECT 반쪽 op(서버발신·클라무처리) 생존·SCOPE_EVENT emit 0·MUTE_UPDATE 하위호환 생존.

**부장님 종결 결재 대기**: ①B~E push ②E-2 마스터 반영 위치·형식 ③Phase D 2층 --core + Phase E 종결 게이트(2층 전체 + 3층) ④다음 테마 지정.
