# OP.CUSTOM — 고객 도메인 앱을 위한 Pass-through Message Channel

> author: kodeholic (powered by Claude)  
> date: 2026-04-22  
> status: DRAFT (설계 리뷰 대기)

---

## 1. 개요

### 1.1 목적

OxLens Hub의 WebSocket 통로를 활용해, **고객이 자기 도메인 앱(판서, 설문, 퀴즈, 실시간 게임 등)을 OxLens 위에 자유롭게 구축할 수 있는 범용 relay 채널**을 제공한다.

### 1.2 비목적

- OxLens 서버가 고객 도메인 기능을 **직접 제공하지 않는다**.
- 메시지 포맷, 비즈니스 로직, 상태 관리, 저장, UI — **전부 고객 책임**.
- OxLens는 송신자 신원 보증(`from`), 라우팅(`to`), rate/size 보호 외에 **어떤 서비스도 제공하지 않는다**.

### 1.3 한 줄 요약

> **OxLens는 통로만 판다. 그 위에 뭘 만들지는 고객이 정한다.**

---

## 2. 배경 및 동기

### 2.1 현재 한계

현재 OxLens는 특정 도메인 기능(PTT Floor, Moderated Floor, Annotation 등)을 op로 직접 정의해 제공한다. 새로운 고객 요구 — 판서, 설문, 퀴즈, 도면 공유, 실시간 포지션 공유 — 이 들어올 때마다 OxLens 코어에 기능을 추가하면 두 가지 문제가 발생한다.

1. **Slack clone 함정**: 고객마다 원하는 기능이 조금씩 다르다 (이모지 반응, 파일 첨부, 스레드, 번역, 링크 프리뷰 등). 이를 OxLens가 모두 구현하면 무한 확장되고, 결국 Slack/Zoom clone이 된다.
2. **sfud "empty shell" 원칙 잠식**: OxLens의 상태 마스터/미디어 엔진이 도메인 기능으로 오염된다.

### 2.2 해결 방향

고객이 자기 도메인에 맞는 메시지 포맷을 **스스로 정의**하고, OxLens는 그 내용에 **무관심한 relay**로만 동작한다. Slack Platform, Discord Bot, MQTT 같은 성공한 메시징 플랫폼의 공통 패턴을 OxLens Hub에 도입한다.

### 2.3 첫 판매 상품

첫 번째 고객앱은 **Canvas Extension** (판서). 본 문서는 Canvas 및 후속 앱들이 공통으로 의존할 **OP.CUSTOM 프로토콜**을 정의한다. Canvas 자체 설계는 별도 문서(`20260422_canvas_extension_design.md`, 후속)에서 다룬다.

---

## 3. 설계 원칙

### 3.1 경계 원칙

| 층 | 책임 | 참고 |
|---|---|---|
| **OxLens Core** | 라우팅, 신원 보증, rate/size cap | 본 문서 |
| **고객 Extension** | 메시지 포맷, 비즈니스 로직, 상태 관리 | 앱별 문서 |

### 3.2 핵심 원칙

1. **Payload 무관심**: 서버는 `d.payload`를 절대 파싱하지 않는다.
2. **Envelope 라우팅**: 라우팅 정보는 패킷 envelope (`from`, `to`)에 둔다. payload 안에 묻지 않는다.
3. **신원 보증**: `from`은 서버가 JWT로부터 주입. 클라이언트 지정 무효.
4. **방 경계 강제**: `to.room`은 송신자가 조인한 방만 허용. cross-room 주입 금지.
5. **sfud 무관**: 본 op은 hub-only. sfud 변경 없음.
6. **열거 방지**: 참가자 존재 여부를 응답으로 노출하지 않는다.

### 3.3 네트워크 프로토콜 통례 준수

envelope vs payload 분리는 통신 프로토콜의 표준 관례다. 라우팅이 payload에 섞여 있으면 op별로 라우팅 어휘가 달라져 일관성이 깨진다.

| 계층 | envelope | payload |
|---|---|---|
| IP | src/dst IP | TCP segment |
| TCP | src/dst port | app data |
| SMTP | From/To/Cc | body |
| HTTP | Host/method/path | body |
| AMQP/MQTT | routing key/topic | payload |
| **OxLens** | **from/to** | **d** |

---

## 4. 프로토콜 명세

### 4.1 Envelope 구조 (신규 표준)

모든 OxLens 시그널링 패킷은 다음 envelope 형태를 **선택적으로** 지원한다.

```jsonc
{
  "op": <u16>,               // opcode
  "from": <string | null>,   // 송신자 user_id (서버→클라 방향에서 의미)
  "to":   <RoutingTarget | null>,  // 라우팅 대상
  "d":    <object>,          // 도메인 페이로드
  "pid":  <u32>              // 패킷 ID (ACK 매칭용)
}
```

- 기존 op들(1~199)은 envelope `from`/`to`를 **무시**한다 (하위호환).
- `OP.CUSTOM` (200) 이후 신규 op들이 envelope를 정식 사용한다.

### 4.2 RoutingTarget 타입

```jsonc
{
  "room":  <string>,              // 필수: 대상 방 ID
  "users": <string[] | null>,     // 옵션: 해당 방 내 특정 사용자들
  "echo":  <bool, default false>  // 옵션: 송신자 본인 에코 여부
}
```

#### 라우팅 패턴

| 지정 | 의미 |
|---|---|
| `{room: "A"}` | 방 A의 전원 (본인 제외) |
| `{room: "A", echo: true}` | 방 A의 전원 (본인 포함) |
| `{room: "A", users: ["u1","u2"]}` | 방 A의 u1, u2에게만 |
| `{room: "A", users: [...], echo: true}` | 지정 user들 + 본인도 |

#### 미래 확장 (v1 포함 안 함)

- `{role: "moderator"}` — role 기반 fan-out. Moderate extension 의존 발생 → v1 제외.
- `{rooms: ["A","B"]}` — 다중 방 동시 송출. 클라 루프로 해결 가능 → v1 제외.
- `{all: true}` — 서버 전체 브로드캐스트. 별도 op(`OP.BROADCAST_ALL`)로 분리 → v1 제외.

### 4.3 Client → Server 패킷

```jsonc
{
  "op": 200,
  "from": null,                    // 무시됨 (서버가 JWT에서 주입)
  "to": {
    "room": "room_abc",
    "users": ["user_x"],           // 옵션
    "echo": false                  // 옵션, 기본 false
  },
  "d": {
    "ns": "canvas",                // 네임스페이스 (고객/앱 식별)
    "payload": { ... }             // opaque, 고객 정의
  },
  "pid": 42
}
```

### 4.4 Server → Clients (fan-out) 패킷

```jsonc
{
  "op": 200,
  "from": "user_sender_id",        // 서버가 JWT로부터 주입, 신뢰 가능
  "to": {
    "room": "room_abc",
    "users": null                  // broadcast면 null, targeted면 사본
  },
  "d": {
    "ns": "canvas",
    "payload": { ... }             // 원본 그대로
  },
  "pid": 42                        // 포맷 대칭 유지용 (수신자에게 비의미)
}
```

### 4.5 네임스페이스 (ns) 규칙

- 문자열, **1~32자**
- 허용 문자: `[a-z0-9_-]` (영소문자, 숫자, 언더스코어, 하이픈)
- 계층 표현 가능: `acme.dispatch.v1` 같은 점 구분자 허용 (확장 여지)
- 서버는 **형식만** 검증. 의미는 해석하지 않는다.
- 텔레메트리 카테고리로만 사용 (ns별 트래픽량 관찰용)

### 4.6 Payload 제약

- JSON object. Binary는 v1 지원 안 함 (향후 별도 op 또는 envelope 확장).
- 최대 크기: `policy.toml`의 `custom.max_payload_bytes` (기본 64KB)
- 구조/스키마: **서버 검증 없음**. 고객앱 전적 책임.

---

## 5. 서버 동작 계약

### 5.1 처리 순서

```
1. JWT 검증 (기존 ws 인프라)
2. op = 200 분기
3. Envelope 파싱
4. to.room 유효성 검증
5. 송신자 rate/size cap 검증
6. from 주입 (JWT.user_id)
7. 라우팅 대상 세션 해석
8. fan-out
9. 송신자에 ok:true 응답
```

### 5.2 라우팅 검증 규칙

**Phase 1 (현재 — 한 세션 = 한 방)**
- `to.room`이 세션의 `SessionPhase.Joined(room_id)`와 일치해야 한다.
- 불일치 시 `ok:false, code:"not_joined"` + 메시지 drop. 연결은 유지.

**Phase 2 (cross-room federation 이후 — 한 세션 = 여러 방)**
- `to.room`이 세션의 `joined_rooms: Set<RoomId>`에 포함되어야 한다.
- 그 외 Phase 1과 동일.

**프로토콜 변경 0줄.** 서버 검증 로직만 집합 체크로 확장.

### 5.3 fan-out 규칙

| 조건 | 대상 |
|---|---|
| `users == null && echo == false` | to.room 세션 전원 중 송신자 제외 |
| `users == null && echo == true` | to.room 세션 전원 (송신자 포함) |
| `users != null && echo == false` | `users` ∩ `to.room 세션들` — 송신자 |
| `users != null && echo == true` | `users` ∩ `to.room 세션들` (송신자 포함 가능) |

- `users`에 지정됐지만 해당 방에 현재 없는 user_id는 **조용히 무시**.
- 지정됐지만 존재하지 않는 user_id도 **조용히 무시**.
- 송신자에게 전달 건수나 무시된 user 정보 **노출 금지** (enumeration 방지).

### 5.4 `from` 주입 규칙

- 클라이언트가 `from` 필드를 채워 보내도 서버는 **무시하고 덮어쓴다**.
- 주입 값: JWT 검증 단계에서 얻은 `user_id` (WsSession 이 이미 보유).
- 이로써 `from`은 수신자 입장에서 **100% 신뢰 가능**.

### 5.5 ok 응답

```jsonc
// 성공
{"op": 200, "pid": 42, "ok": true}

// 실패
{"op": 200, "pid": 42, "ok": false, "code": "<error_code>"}
```

성공 응답은 **전달 건수를 포함하지 않는다**. 실패 응답은 사유를 최소한으로만 알린다.

### 5.6 에러 코드

| code | 의미 |
|---|---|
| `not_joined` | `to.room`이 송신자가 조인한 방이 아님 |
| `invalid_ns` | ns 형식 위반 (길이, 허용 문자) |
| `invalid_to` | to 구조 오류 (room 누락, users 타입 오류 등) |
| `payload_too_large` | payload 크기 초과 |
| `rate_limited` | 송신 빈도 초과 |
| `server_error` | 내부 오류 (fan-out 실패 등) |

클라이언트는 `rate_limited` 이외의 에러는 **앱 버그로 간주**하고 재시도하지 않는다.

---

## 6. 보안 경계

### 6.1 OxLens 책임 범위

| 보증 | 수단 |
|---|---|
| 송신자 신원 | JWT → from 주입 |
| 방 경계 | 조인된 방에만 송출 가능 (검증) |
| 수신자 격리 | `users` 지정 시 방 밖으로 누수 없음 |
| 트래픽 보호 | rate/size cap |

### 6.2 OxLens 책임 범위 밖

- **Payload 내용의 악의성**: 고객앱 책임. OxLens는 파싱 안 함.
- **고객앱 권한 체계**: "누가 뭘 할 수 있는지"는 고객앱이 자체 정의 (Moderate와 연계할 수도, 독립적일 수도).
- **고객앱 데이터 저장**: OxLens는 relay만. 지속성 없음.
- **Late joiner 상태 동기화**: 고객앱이 앱 레이어에서 처리 (예: "snapshot 요청→응답" 패턴).

### 6.3 공격 벡터 방어

| 공격 | 방어 |
|---|---|
| 타 방 메시지 주입 | `to.room` 검증 |
| 위조 송신자 (`from` 스푸핑) | 서버 주입으로 무효화 |
| 참가자 enumeration | 존재 여부 응답 비공개 |
| 트래픽 폭주 | sender 기준 rate cap |
| 거대 payload로 OOM | size cap + drop |
| cross-tenant 누수 | 방 경계가 곧 tenant 경계 |

---

## 7. Rate & Size Cap

### 7.1 정책

| 항목 | 기본값 | 설정 위치 |
|---|---|---|
| `max_payload_bytes` | 65,536 (64KB) | `policy.toml [custom]` |
| `max_msgs_per_sec` | 30 | `policy.toml [custom]` |
| `max_msgs_per_min` | 1200 | `policy.toml [custom]` (burst 허용용 2중 윈도우) |

### 7.2 적용 원칙

- **Sender 기준**: fan-out 대상이 몇 명이든 무관하게, 송신자 1인당 한도.
- **Per-connection**: 한 user가 여러 WS 세션(탭)을 가지면 각각 독립 카운트.
- **초과 시**: 개별 메시지만 drop, 연결은 유지, `ok:false code:"rate_limited"` 응답.
- **ArcSwap**: policy.toml 교체로 런타임 조정 가능 (기존 인프라).

### 7.3 대규모 데이터 전송 전략

64KB는 대부분 앱에 충분하지만, 판서 snapshot 같은 큰 데이터에서는 부족할 수 있다. 해결은 **고객앱 레이어의 chunking**:

```
앱이 자체 message id + chunk index로 분할:
  payload: {t:"snapshot", sid:"xxx", idx:0, total:5, chunk:"..."}
  payload: {t:"snapshot", sid:"xxx", idx:1, total:5, chunk:"..."}
  ...
```

OxLens는 관여하지 않는다.

---

## 8. 하위호환 정책

### 8.1 기존 op (1 ~ 199)

- envelope 필드(`from`, `to`)는 **무시**된다.
- 현재 `d` 안의 필드 구조 그대로 유지.
- 기존 클라이언트 코드 변경 없이 동작.

### 8.2 신규 op (200 이상)

- 신규 op 설계자가 envelope 사용 여부를 **선택**한다.
- 라우팅이 필요한 op는 envelope 사용 권장.
- 도메인별 내부 상태 변화만 알리는 op는 envelope 없이 d로도 무방.

### 8.3 OP.MESSAGE (op=20) 처리

현재 `OP.MESSAGE d: {text}` 는 방 broadcast 전용이고 귓속말/targeted 기능이 없다. 채팅 기능을 제대로 만들려면 `to` 라우팅이 필요한데, 이는 OP.CUSTOM의 영역이다.

**정책:**
1. **현재 버전**: OP.MESSAGE 유지 (하위호환).
2. **다음 메이저 버전**: `deprecated` 공지. 로그 경고.
3. **이후**: 삭제.
4. **대체재**: `core/extensions/chat.js` 레퍼런스 Extension (OP.CUSTOM `ns="chat"` 기반). 별도 설계 문서에서 다룸.

이로써 OxLens는 "채팅조차 OP.CUSTOM 위에 얹은 플랫폼"이 된다 — 고객 설득력 강화.

---

## 9. Cross-Room 지원

### 9.1 Phase별 동작

**Phase 1 (현재)**
- 한 세션 = 한 방.
- 고객앱은 `to.room`에 자기 현재 방 ID를 찍는다.
- 서버: 세션의 현재 room과 일치 확인.

**Phase 2 (Cross-Room Federation 이후)**
- 한 세션 = 여러 방.
- 고객앱은 어느 방으로 송출할지 `to.room`에 명시.
- 서버: 세션이 해당 방에 조인된 상태인지 확인.

### 9.2 Cross-Room 시나리오 예시

```
지휘관 세션: rooms = {방A, 방B}

지휘관이 방A에 판서:
  → OP.CUSTOM {to:{room:"A"}, d:{ns:"canvas", payload:{t:"stroke",...}}}
  → 방A 참가자들만 수신

지휘관이 방B에 다른 판서:
  → OP.CUSTOM {to:{room:"B"}, ...}
  → 방B 참가자들만 수신
```

**프로토콜 한 벌로 Phase 1/2 모두 커버.** 프로토콜 수명이 길다.

### 9.3 Phase 2 전환 시 필요한 코드 변경

- hub `WsSession` 의 `SessionPhase.Joined(RoomId)` → `SessionPhase.Joined(JoinedRooms)` 확장
- 라우팅 검증: 단일 비교 → 집합 포함 체크
- **OP.CUSTOM 프로토콜 자체는 변경 0**

---

## 10. 영향 범위 (코드 변경 추정)

### 10.1 common

| 파일 | 변경 |
|---|---|
| `common/signaling/opcode.rs` | `CUSTOM = 200` 상수 추가. `error_code` 확장 (`not_joined` 등) |
| `common/signaling/envelope.rs` (신규) | `Envelope`, `RoutingTarget` 구조체 + serde |

### 10.2 oxhubd

| 파일 | 변경 |
|---|---|
| `oxhubd/src/ws/dispatch/mod.rs` | op=200 분기. envelope 파싱, `to.room` 검증, `from` 주입, fan-out |
| `oxhubd/src/state.rs` | `room_clients` 2차 인덱스 활용 (이미 있음), user→세션 lookup 유틸 |
| `oxhubd/src/metrics.rs` | `custom` 카테고리 추가: `msg_total`, `bytes_total`, `drop_rate_limited`, `drop_size`, `drop_not_joined`, per-ns 카운터 |
| `policy.toml` | `[custom]` 섹션 (cap 값) |

### 10.3 oxsfud

**변경 없음.** sfud는 OP.CUSTOM을 완전히 무관심하게 지나친다.

### 10.4 SDK (oxlens-home core)

| 파일 | 변경 |
|---|---|
| `core/signaling.js` | OP.CUSTOM 송수신 헬퍼. envelope 구조 생성/파싱 |
| `core/extensions/` (후속) | canvas, chat 등 Extension 추가 |
| `core/constants.js` | `OP_CUSTOM = 200` |

### 10.5 SDK (Android)

Phase 1 판매에 Android 클라가 필요하면 동일 구조 이식. 아니면 보류.

### 10.6 추정 작업량

- 서버: 2~3일 (envelope 타입 + dispatch + metrics + policy + unit test)
- SDK: 1~2일 (signaling.js 확장 + 기본 send/recv helper)
- 총 코어 작업: **약 1주**
- Canvas/Chat Extension은 별도 문서에서 산정

---

## 11. 텔레메트리

### 11.1 Hub 카운터 (추가)

```
custom.msg_total              총 송수신 메시지
custom.bytes_total            총 바이트
custom.fan_out_total          총 fan-out 전송 건수 (1 msg → N 수신)
custom.drop_rate_limited      rate cap 초과 drop
custom.drop_size              size cap 초과 drop
custom.drop_not_joined        to.room 검증 실패 drop
custom.drop_invalid           형식 오류 drop
custom.ns.<n>.count        ns별 메시지 수 (top-N만 집계)
```

### 11.2 어드민 대시보드

Hub Gateway 섹션에 **Custom Channel** 서브섹션 추가:
- 초당 메시지/바이트
- 활성 ns 리스트 (top 10)
- drop 사유별 비율

---

## 12. 미래 확장

아래 항목은 **v1 포함 안 함**. 필요 발생 시 별도 설계.

| 항목 | 언제 필요해질까 |
|---|---|
| Binary payload | 대용량 이미지/이진 데이터 전송 앱 |
| `to.role` | Moderate 통합이 자연스러워질 때 |
| `to.rooms[]` 다중 방 | 클라 루프로 충분. 실제 수요 발생 시 |
| `OP.BROADCAST_ALL` | 전사 공지 기능 요청 발생 시 |
| Reliable 전송 보장 | 앱이 자체 retry로 해결 가능. 강한 수요 시 |
| 서버 side buffering/replay | 원칙 위배. 다른 설계로 분리 |
| SDK Android Extension 모델 | 판매 대상 Extension 이식 결정 시 |

---

## 13. 기각된 대안

### 13.1 라우팅을 payload에 묻기

```jsonc
// 기각
{op: 200, d: {ns, to:{...}, payload: {...}}}
```

**기각 사유**: 서버가 payload를 파싱해야 라우팅 가능 → "payload 무관심" 원칙 붕괴. payload가 opaque여야 고객이 포맷을 자유롭게 정할 수 있다. envelope 레벨 라우팅은 네트워크 프로토콜 통례(IP, TCP, SMTP, HTTP, AMQP)와도 일치.

### 13.2 room_id 없이 세션 컨텍스트만 사용

**기각 사유**: Phase 2 cross-room federation에서 한 세션이 여러 방에 조인할 때, "어느 방으로 보낼지" 지정 불가. 프로토콜 수명이 Phase 1으로 한정됨. `to.room` + 서버 검증이 올바른 구조.

### 13.3 targeted fan-out을 v2로 미룸

**기각 사유**: Canvas late joiner snapshot 유즈케이스에서 1:1 targeted가 v1 필수. broadcast only면 snapshot이 방 전원에게 뿌려져 트래픽 폭증.

### 13.4 role 기반 `to` (`{role: "moderator"}`) v1 포함

**기각 사유**: Moderate extension 의존 발생 → OxLens 코어 독립성 위반. Moderate는 고객이 선택적으로 쓰는 extension이어야 한다. v2 이후 필요 시 재검토.

### 13.5 전달 건수 응답

```jsonc
// 기각
{"ok": true, "delivered": 5, "skipped": ["u1", "u2"]}
```

**기각 사유**: 참가자 enumeration 공격 벡터. 악의 클라가 user_id 브루트 포싱으로 방 참가자 목록을 파악 가능. 성공 여부만 알림.

### 13.6 DC bearer 사용

**기각 사유**: 
- DC는 Publish PC에 딸려 있어 영상 미송출 참가자(viewer, audience)는 DC가 없음 → 모든 사용자 커버 불가.
- DC를 범용 앱에 열면 OxLens 내부 전략 자원(PTT Floor, 향후 reliable 메시지)의 설계 여지 침식.
- 대부분의 앱(채팅, 설문, 판서 stroke 완성본)은 50~200ms 지연으로 충분.
- 필요한 경우 고객앱이 자체 optimistic local apply로 체감 지연 상쇄 가능.

WS-only가 v1 결정.

### 13.7 서버 replay buffer

**기각 사유**: OxLens가 메시지 상태를 저장/재송신 → "통로만 판다" 원칙 위배. Late joiner 동기화는 고객앱이 "join_req → snapshot" 패턴으로 앱 레이어에서 해결. OxLens는 stateless.

### 13.8 `to`를 `d` 안에 두기 (OP.CUSTOM까지 유지)

**기각 사유**: 라우팅은 envelope 레벨 정보. op별로 라우팅 어휘가 달라지면 새 op 추가 시마다 재설계 비용. envelope 표준화가 장기적으로 유리.

### 13.9 전 op envelope 즉시 마이그레이션

**기각 사유**: 기존 op 1~199, 클라/서버 전체 수정 → 리스크 대비 이득 불명. 신규 op부터 envelope 적용, 기존 op는 envelope 필드 무시하는 하위호환 정책이 안전.

### 13.10 `OP.APP` / `OP.PASS` 명명

**기각 사유**: "APP"은 의미가 너무 포괄적이라 다른 용도와 충돌 여지. "PASS"는 동사로 오해 가능. "CUSTOM"이 "고객/사용자 정의"를 가장 명확히 전달.

---

## 14. 후속 설계 문서

본 문서는 프로토콜 기반만 다룬다. 실제 구현되는 Extension 및 연계 기능은 별도 문서:

| 문서 | 범위 |
|---|---|
| `20260422_canvas_extension_design.md` | Canvas Extension (판매 상품 1호): 좌표계, 내부 메시지 타입, late joiner sync, UI, 내보내기 |
| 후속 | Chat Extension (레퍼런스/판매 2호): OP.MESSAGE 대체 구조 |
| 후속 | Hook 시스템과의 연계 (필요 시): 외부 webhook으로 ns별 이벤트 fan-out |

---

## 15. 확인 요청 사항

설계 문서 확정 전 부장님 재확인 필요한 항목:

1. **네임스페이스 충돌 방지 전략**: ns를 점 구분자로 계층화 가능하게(`acme.dispatch.v1`) 허용했는데, 충돌 방지를 위해 고객에게 "자사 도메인 prefix 권장"을 가이드할지.
2. **Rate cap 기본값**: 30 msg/s, 64KB. 판서 stroke 중에 커서 라이브 전송하면 부족할 수 있음. Canvas 설계에서 resampling으로 해결 예정이지만, 기본값 재검토 필요할지.
3. **ok 응답 형식**: 현재 다른 op들은 `ok` 필드만 있는지, `code` 관례가 기존에 있는지 확인 후 통일.
4. **Phase 2 cross-room 전환 시 `SessionPhase` 수정 범위**: 본 문서에서는 개념만 언급. 실제 전환은 cross-room federation Phase 2 설계 문서에서 다뤄짐.

---

## 부록 A — 샘플 시나리오

### A.1 캔버스 stroke 브로드캐스트

```jsonc
// user_alice가 방의 모두에게 stroke 전송
// Client → Server
{
  "op": 200,
  "to": {"room": "room_xyz"},
  "d": {
    "ns": "canvas",
    "payload": {
      "t": "stroke_add",
      "id": "s_001",
      "points": [{"x":100,"y":200,"p":0.5}, ...],
      "color": "#000",
      "width": 3
    }
  },
  "pid": 100
}

// Server → 방의 다른 참가자들
{
  "op": 200,
  "from": "user_alice",
  "to": {"room": "room_xyz", "users": null},
  "d": { ... 원본 payload ... },
  "pid": 100
}
```

### A.2 Late joiner snapshot (targeted)

```jsonc
// user_charlie (새 참가자) → 방 전체에 "snapshot 줘" 요청
{
  "op": 200,
  "to": {"room": "room_xyz"},
  "d": {"ns": "canvas", "payload": {"t": "join_req"}},
  "pid": 1
}

// user_alice (진행자)가 user_charlie에게만 snapshot 전송
{
  "op": 200,
  "to": {"room": "room_xyz", "users": ["user_charlie"]},
  "d": {
    "ns": "canvas",
    "payload": {
      "t": "snapshot",
      "strokes": [ ...기존 모든 stroke... ],
      "background": {...}
    }
  },
  "pid": 500
}
// → 서버는 user_charlie에게만 fan-out. 방의 다른 참가자에겐 안 감.
```

### A.3 Cross-room 지휘 (Phase 2)

```jsonc
// 지휘관 세션이 {방A, 방B} 조인 중

// 방A에만 캔버스 공지
{"op":200, "to":{"room":"A"}, "d":{"ns":"canvas", "payload":{"t":"announce", "text":"현장1 주의"}}, "pid":10}

// 방B에만 채팅
{"op":200, "to":{"room":"B"}, "d":{"ns":"chat", "payload":{"text":"현장2 수고","format":"text"}}, "pid":11}

// 양쪽 메시지는 완전히 격리된 방 경계로 전달됨
```

### A.4 귓속말 (Chat extension 예시)

```jsonc
// user_alice → user_bob 귓속말
{
  "op": 200,
  "to": {"room": "lobby", "users": ["user_bob"]},
  "d": {
    "ns": "chat",
    "payload": {"text": "회의 끝나고 잠깐 얘기해요", "private": true}
  },
  "pid": 77
}
// 방의 다른 사람은 못 받음. user_bob만 수신.
// user_bob 앱이 UI에 "🔒 private" 표시하는 건 앱 책임 (payload.private 해석).
```

---

## 부록 B — 구현 체크리스트 (요약)

### B.1 common
- [ ] `opcode.rs`: `CUSTOM = 200`, 에러 코드 enum 확장
- [ ] `envelope.rs`: `Envelope<D>`, `RoutingTarget` 구조체

### B.2 oxhubd
- [ ] `ws/dispatch/mod.rs`: op=200 분기
- [ ] `ws/dispatch/custom.rs` (신규): envelope 파싱, 검증, fan-out
- [ ] `state.rs`: user_id → session_id lookup 헬퍼
- [ ] `metrics.rs`: `custom` 카테고리
- [ ] unit test: 라우팅 검증 4종, rate limit, size limit, enumeration 방지

### B.3 policy.toml
- [ ] `[custom]` 섹션: `max_payload_bytes`, `max_msgs_per_sec`, `max_msgs_per_min`

### B.4 SDK
- [ ] `constants.js`: `OP_CUSTOM = 200`
- [ ] `signaling.js`: `sendCustom(ns, to, payload)`, custom 메시지 이벤트
- [ ] 테스트: echo, targeted, not_joined 에러 핸들링

### B.5 어드민
- [ ] Hub Gateway 섹션에 Custom Channel 서브섹션
- [ ] ns별 top-N 카운터 시각화

### B.6 문서
- [ ] PROJECT_MASTER.md에 OP.CUSTOM 등재 (시그널링 테이블)
- [ ] SESSION_INDEX.md 한 줄 등록

---

*end of document*
