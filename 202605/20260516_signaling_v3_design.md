# 20260516 — Signaling Protocol v3 wire 재설계

## 한 줄 요약

v2 의 산발 opcode + JSON-only Text wire + dual envelope 문제 진단 → 8B 바이너리 헤더 + 16진 opcode 카테고리 + ACK 의무화 + gRPC typed envelope 단일화 + Pan-Floor 삭제. 설계서 단일 합의 완료. 코드 변경 0줄 (다음 세션 코딩 진입).

---

## 컨텍스트

부장님 5월 호흡 ("max 요금제 6월 복귀 전, PRO 안에서 5월 내재화") 의 후속으로 시그널링 프로토콜 의문 제기. v2 가 시작은 깔끔했지만 PTT, Cross-Room (Scope), Moderate, DataChannel 등 거치며 op 0~170 산발 + JSON Text + Binary 이중 wire + bearer=ws fallback self-envelope 등 누적된 잡식 상태.

김대리 진단 5건:
1. op 번호 무계획 (같은 대역 C→S/S→C/internal 혼재)
2. wire 이중 분기 (Text + Binary)
3. flag/priority/intent/ACK 정보 중복
4. ACK 정책 실효성 미강제
5. gRPC WsMessage oneof + binary self-envelope 비대칭

부장님 결정: v3 wire 전면 재설계. wire-incompatible break 받아들임.

---

## 결정 사항 (v3 핵심 7건)

### 1. Wire 포맷 — 고정 8B 바이너리 헤더 + 가변 body 단일

```
[ver:1B][flags:1B][op:2B BE][pid:4B BE][body...]
```

- WS Text frame 폐기. Binary frame 단일.
- flags bit 0-1 = `ack_state` enum (00=MSG/01=ACK_OK/10=ACK_FAIL/11=reserved), bit 2-7 reserved.
- ver = 0x01 v3 first release. 미래 wire break 시 0x02.
- body 포맷 op 가 결정 (0x2400 FLOOR_MBCP 만 MBCP TLV, 그 외 JSON).
- body length 별도 필드 없음 (WS frame length - 8). MQTT fixed header 패턴.

### 2. opcode 16진 카테고리 nibble

상위 4비트 = 카테고리. 카테고리 결정으로 dispatch/priority/intent/ACK 전부 자동.

| 대역 | 카테고리 |
|------|---------|
| 0x00xx | Handshake (pid=0, ACK 없음) |
| 0x01xx | Session (HEARTBEAT 등) |
| 0x10xx~0x17xx | C→S Request (Room/Media/Scope/Data/Extension) |
| 0x20xx~0x27xx | S→C Event (Room/Media/Scope/Data/Floor/Speakers/Moderate) |
| 0x30xx | Admin Event |
| 0xE0xx | Internal (hub↔sfud 비노출) |
| 0xF0xx | Error |

### 3. SCOPE_UPDATE + SCOPE_SET → SCOPE 1개 op + body mode 분기

0x1200 SCOPE. body `{ mode: "update"|"set", ... }`. dispatch 단순화.

### 4. ACK 의무화

`requires_ack(op)` lookup. ACK 불필요 = 6종 (HELLO/IDENTIFY/IDENTIFY_RESULT/ACTIVE_SPEAKERS/SESSION_DISCONNECT/ERROR). 나머지 전부 ACK 필수. C→S Request 응답이 곧 ACK (응답 데이터 + 재전송 트리거 통합). S→C Event 도 빈 ACK 회신 의무.

송신측: OutboundQueue 정책 유지 (pid sending 큐 + ACK 수신 시 제거 + timeout=30s WS 끊김, 재전송 안 함). ACK_FAIL 은 application logic 으로 전달.

### 5. gRPC typed envelope

```proto
message WsMessage {
  string user_id = 1;          // hub 가 인증된 세션에서 주입 (보안 경계)
  string room_id = 2;
  string target = 3;           // 빈 = broadcast, 특정 user = unicast
  repeated string exclude = 4;
  bytes wire = 5;              // 클라 wire passthrough
}
```

oneof{json,binary} 폐기. per_user_payloads 패턴 폐기 (한 WsMessage 당 한 wire, target unicast). self-encoded `[env_len][env_json][payload]` envelope 폐기.

### 6. Pan-Floor 기능 삭제

svc=0x03, PAN TLV 4종, PanCoordinator, panRequest/panRelease API 전체 삭제. 단일방 floor-control 전제. SFU 간 단일방 공유는 별도 설계 (본 작업 범위 밖).

### 7. SMS submit/report 패턴 명시화 — wire ACK ≠ application READY

부장님 SMS 비유 인용. TRACKS_UPDATE wire ACK (SMSC store 완료, 빠름) ↔ TRACKS_READY (수신단말 도착 완료 = SDP renego 완료, 느림) 별개 레이어. `TRACKS_ACK` (v2) → `TRACKS_READY` (v3 op=0x1102) 개명.

PUBLISH_TRACKS / SUBSCRIBE_LAYER 도 동일 분리 필요한지 추후 검토 (§14 클라 책임).

---

## 결정 완료 후속 (본문 반영, §14 에서 제거)

| 항목 | 결정 |
|------|------|
| HEARTBEAT 빈도 | 현행 유지 (hub 10초, policy.toml `[hub] heartbeat_interval_ms=10_000`) |
| HEARTBEAT 응답 형식 | wire ACK_OK 회신이 양방향 keepalive ("나 살았다 + 너 살았네 퉁"). v2 별도 HEARTBEAT_ACK 폐기 |
| error code 표현 | string. binary=numeric / JSON=string 매체별 적용 원칙 (§2.8). HTTP/SMTP=numeric, AWS/Stripe/Slack/JSON:API/RFC 9457=string. JSON body 안 code 절약 미미 vs 디버깅 가독성 이득 큼. Rust enum + serde SCREAMING_SNAKE_CASE 직렬화 |
| 미래 NACK 케이스 | code 카탈로그 신규 코드 추가 방식. wire 변경 없음 |

---

## 결정 보류 (§14)

### 클라이언트 책임 영역 (3건)

1. **Reconnect 시 pending 메시지 replay** — 클라 책임. 서버는 shadow state 복원 그대로. 클라 작업 세션에서 결정.
2. **PUBLISH_TRACKS / SUBSCRIBE_LAYER SUBMIT/REPORT 분리** — 클라 책임. wire ACK 받지 않고 다음 패킷 보내는 패턴이면 sliding window=8 차서 자연 backoff. 추가 op 도입 여부는 클라 작업 세션.
3. **ANNOTATE / TELEMETRY ACK 비용** — 측정 후 fire-and-forget 추가 여부 결정. 현재는 ACK 필수.

### 본 작업 범위 밖 (1건)

1. **SFU 간 단일방 공유** — Pan-Floor 폐기 후 별도 설계.

---

## 기각 후보 (오늘)

1. **op 번호 dense 재할당** (0~80 연속) — 카테고리 nibble 없으면 dispatch if-else 더미. v2 의 잘못 반복.
2. **flag bit 에 priority/intent/body_format/ack_req 명시 인코딩** — op 와 정보 중복. HTTP Content-Type / IP protocol 카테고리 라벨 패턴 위반.
3. **`Packet { op, pid, ok, d, err }` flat 구조체 유지** — header view + body view 분리해야 wire 와 자료구조 일치.
4. **`WsMessage { oneof json, binary }` proto 유지** — hub-sfud 비대칭. typed envelope (user_id/room_id/target/exclude/wire) 가 정공.
5. **`[env_len:u16][env_json][payload]` self-encoded envelope (binary path)** — proto field 로 typed 가능한데 굳이 self-encode.
6. **`retryable` 필드** — code 카탈로그가 perm/temp 분류 책임. 별도 flag 이중화 금지.
7. **`Packet::err` numeric code** — JSON 안에서 string 이 정석 (§2.8).
8. **별도 HEARTBEAT_ACK 메시지** — wire ACK 가 통합. 이중 정의 폐기.
9. **TRACKS_ACK 이름 유지** — wire ACK 와 의미 충돌. TRACKS_READY 가 정확.
10. **TRACKS_UPDATE 의 wire ACK 를 SDP renego 후 보내기** (wire ACK + application READY 통합안) — SDP renego 1~2초 지연으로 ACK timeout 위험 + OutboundQueue window 차서 다음 이벤트 못 보냄. 두 단계 분리가 정공 (SMS submit-report vs status-report 패턴).
11. **Pan-Floor 보존** — 단일방 floor-control 전제로 충분. SFU 간 단일방 공유는 본 작업 범위 밖이라 PAN TLV/PanCoordinator 모두 짐.
12. **MBCP 옵션 A (TS 24.380 표준 준수 재정렬)** — 메시지 타입/TLV 전면 재매핑 비용 대비 표준 단말 상호운용 이득 없음 (웹 PTT 타겟). 이전 세션 결정 재확인.
13. **에러 코드 numeric 으로 단축** — JSON body 안 12B 차이 (per ACK fail) × 매우 낮은 빈도 = 절약 미미. 가독성 손해 큼.

---

## 지침 후보 (오늘)

1. **카테고리 nibble + self-describing body** — opcode 가 카테고리만, 내용물 세부 분류는 body 안 type. HTTP/IP/Ethernet/WS frame 전부 같은 패턴. 정보 중복 금지.
2. **op 가 정책 결정** — ACK 필요 여부, priority, intent, body 포맷 전부 op lookup. flag 비트 신설 금지.
3. **error code 매체별 표현** — binary wire = numeric (HTTP status, SMS RP-Cause, MQTT reason code, AMQP). JSON wire = string (RFC 9457, AWS, Stripe, Slack, JSON:API). 우리는 헤더 binary + body JSON 이라 헤더는 numeric, body 안 code 는 string.
4. **wire ACK ≠ application READY** — SMS submit-report (SMSC store 완료, 빠름) vs status-report (수신단말 도착, 느림) 패턴. 같은 op 에 합치지 않음. TRACKS_UPDATE/TRACKS_READY 가 표준 예.
5. **handshake 는 pid 메커니즘 밖** — HELLO/IDENTIFY/IDENTIFY_RESULT pid=0. 다음 메시지가 진행 신호. ACK 없음.
6. **HEARTBEAT 가 wire ACK 와 결합 → 양방향 keepalive 자동** — 별도 HEARTBEAT_ACK 메시지 안 필요. "내가 살았다 + 너도 살았네 퉁."
7. **OutboundQueue 재전송 안 함, ACK fail 재시도는 application 책임** — wire 와 application 레이어 분리. wire 가 자동 재시도 정책 결정 금지.
8. **wire-incompatible break 받아들이기** — v2 호환 안 됨. 서버/클라 동시 배포 강제. rollback = 이전 버전 재배포. 단계 배포 시도하면 양쪽 모두 복잡해짐.
9. **enum + serde rename_all = "SCREAMING_SNAKE_CASE"** — Rust 측 typo 컴파일 에러 + wire 측 string. gRPC enum 패턴 차용.
10. **proto 의 oneof 보다 typed envelope** — 라우팅 메타는 named field, body 는 bytes wire passthrough. JSON 경로/binary 경로 비대칭 제거.

---

## 다음 액션

부장님 확인 후 진행 예정 (이번 세션 종료 후 결정):

1. git branch 정책 (권장: `feature/signaling-v3`)
2. review checkpoint 4시점 (권장: step 3 proto → step 8 common → step 15 sfud → step 16 cargo test 통과)
3. §14 미해결 3건 (클라 책임) 은 코딩 중 막힘 없으면 그대로 진행

부장님 결정 받은 후 §11.1 마이그레이션 18 step 순서 진입.

---

## 산출물

- **설계서**: `context/design/20260516_signaling_v3.md` — 15장 (변경 요약 / 배경 / 핵심 원칙 8개 / Wire 포맷 / ACK 정책 / opcode 카탈로그 / ACK Body 스키마 / gRPC Envelope / 흐름 다이어그램 4종 / 폐기·신규·보존 표 / 불변식 10개 / 마이그레이션 18 단계 / 검증 전략 / 단위 테스트 명세 / 미해결 / 참고 자료)

---

## 메타학습

- ⭐⭐⭐⭐ **부장님 직설 한 마디가 큰 결정 단축** — "이거 이름이 좀 헷갈리지 않아?" (TRACKS_ACK) / "용량 줄이고 싶은데 가독성 걸려" (string vs numeric). 김대리가 옵션 3개 박고 권장 박으면 부장님이 결정. 김대리 측 토론 시간 절약.
- ⭐⭐⭐⭐ **SMS 비유 인용이 본질 매치 확인 도구** — 부장님 "submit-report 나누거든" 한 마디가 wire ACK ≠ application READY 두 레이어 원칙을 즉시 확정. 통신사 SI 경험이 wire 설계 본능. 김대리는 카탈로그 정리 역할.
- ⭐⭐⭐ **결정 권장은 단어 선택이 결정적** — "TRACKS_READY 권장" 명시 + 이유 3줄. 부장님이 "a 로 가" 한 줄. 옵션 나열만 하면 부장님 다시 묻는 라운드 추가. 김대리 의무 = 권장안 + 근거.
- ⭐⭐⭐ **`vibe-explain` skill 검색 회수** — 부장님이 "vide-explain 인가" 모호하게 기억. 첫 검색 (conversation_search) 실패 → 두 번째 (web_search "claude skill vibe-explain") `explain-code` skill 발견 → 부장님 "개인이 만든 거" 단서 → 세 번째 검색 (vibe coded skill) `codebase-to-course` by Zara 정확히 매치. **부장님 단서 한 마디씩 김대리가 검색 키워드 좁히는 패턴**. 김대리가 처음에 비슷한 이름 검색만 하면 안 나옴 — 의도/맥락 키워드로 좁혀야.
- ⭐⭐⭐ **PROJECT_MASTER 의 정보 충실도 = 김대리 답변 정확도** — policy.toml 위치, 현재 값, 도메인별 [heartbeat] vs [hub] 분리 등 정확하게 박혀있어서 김대리가 즉시 답 박음.
- ⭐⭐ **세션 끝 정리 시 review-protocol 스킬 초안 작성도 시도** — 부장님이 "다음 세션에서" 보류. 작성한 초안은 `context/SKILL_oxlens-review-protocol.md` 위치. 의도 100% 매치 안 됨 (explain 섹션 빠짐). codebase-to-course 패턴 + review checkpoint 패턴 결합이 정답으로 보임. 다음 세션 작업.

---

*author: kodeholic (powered by Claude)*
