# 세션: oxhubd 리팩토링 — 약한 고리 4건 + WS 고도화 설계 5건 구현

**날짜**: 2026-04-09 (야간)
**영역**: oxhubd 코드 품질 + 성능 + 보안 + WS 고도화
**상태**: 9건 완료, 빌드 성공. 우선순위+흐름제어는 설계 미완으로 미착수.

---

## 작업 내역 (9건 완료)

### 약한 고리 4건
1. **broadcast_to_room O(K) 2차 인덱스** — room_clients DashMap<room_id, HashSet<user_id>>
2. **WS disconnect → LeaveRoom** — best-effort gRPC 호출
3. **sfu() ArcSwap lock-free** — RwLock 제거, reconnect Mutex 분리
4. **admin REST JWT** — verify_admin 헬퍼

### WS 고도화 설계서 5건
5. **중복 연결 Last-in-wins (설계서 6번)** — conn_id AtomicU64, DUPLICATE_SESSION
6. **크기/rate 방어 (설계서 8번)** — 64KB + 60/s sliding window
7. **Event Intent (설계서 11번)** — 7비트 비트마스크, from_opcode, broadcast 필터
8. **Server Reconnect op=7 (설계서 12번)** — REST admin 엔드포인트
9. **Token Renewal op=8 (설계서 13번)** — hb_timer 경고 + 클라이언트 갱신

---

## 착수했다가 원복한 것

### 메시지 우선순위 (설계서 1번) — 원복 완료
- 2채널(urgent/normal) → 4채널(P0~P3) biased select 구현했으나 원복
- **원복 이유**: 흐름제어 없이 우선순위만 넣으면 무의미 (큐에 쌓이는 순간이 없으면 P0~P3 구분 불필요). 우선순위는 흐름제어의 종속 기능.

### 흐름제어 (설계서 2번) — 설계 논의만, 코드 변경 제로
- policy.rs에 ws_flow_window_size 추가했다가 제거 (쓰는 곳 없음)
- **미착수 이유**: 설계가 덜 됨. 큐 구조(mpsc vs 자체), 락 전략(1만 동접), 임계시간 체크, 메시지 상태 관리 미확정.

---

## 변경 파일 목록

| 파일 | 변경 |
|------|------|
| `common/src/signaling/opcode.rs` | RECONNECT=7, TOKEN_REFRESH=8 |
| `common/src/signaling/mod.rs` | DUPLICATE_SESSION + intent 모듈 |
| `common/src/config/policy.rs` | HubPolicy ws_max_message_bytes, ws_rate_limit_per_sec |
| `oxhubd/Cargo.toml` | arc-swap 의존성 |
| `oxhubd/src/state.rs` | room_clients + ArcSwap + conn_id + intents + broadcast intent 필터 |
| `oxhubd/src/ws/mod.rs` | LeaveRoom cleanup + conn_id + 크기/rate + intents + token renewal |
| `oxhubd/src/events/mod.rs` | broadcast_to_room intent_bit |
| `oxhubd/src/rest/admin.rs` | verify_admin JWT + reconnect 엔드포인트 |

---

## 흐름제어 설계 논의 요약 (다음 세션 참고)

### 업계 조사 결과
- **TCP backpressure** (대부분의 WS): 앱 레벨 프로토콜 불필요. 느린 클라이언트=disconnect
- **Discord**: seq 있지만 resume용. 흐름제어 아님
- **MQTT v5 Receive Maximum**: 부장님 방식과 동일. in-flight window + ACK 기반 quota

### 확인된 설계 방향
- 기존 pid = 서버→클라이언트 seq number (별도 seq 불필요)
- 기존 `ok: true` 응답 = ACK (별도 ACK opcode 불필요)
- in_flight = 보낸 수 - ACK 받은 수
- in_flight >= window_size → 전부 중단
- timeout 내 ACK 안 오면 disconnect → 큐 폐기 → ROOM_SYNC 복구
- 재전송 없음 (서버 hub). 클라이언트 SDK는 SENT 보관 + 재전송 필요 (비대칭)

### 미해결 설계 과제
- 큐 구조: mpsc(lock-free 파이프) + WS루프 내 VecDeque(single-thread) 조합? 자체 큐?
- 1만 동접 × 락: 현재 mpsc.tx.send()는 lock-free. 자체 큐면 Mutex 필요 → 경합
- 임계시간 체크: OutboundQueue에 last_acked_at + hb_timer 주기 체크
- 우선순위: 흐름제어 위에 얹는 종속 기능. 큐 구조 확정 후 P0~P3 추가

---

## 기각 사항

| 기각 | 이유 |
|------|------|
| Axum FromRequestParts extractor | Edition 2024 lifetime 충돌 |
| tx 비교로 중복 연결 감지 | UnboundedSender Eq 미구현 |
| 우선순위 선행 구현 | 흐름제어 없으면 무의미. 큐에 안 쌓이면 우선순위 동작 안 함 |
| 흐름제어 즉흥 코딩 | 큐 구조+락+타이머+상태관리 설계가 선행되어야 함 |

## 오늘의 지침 후보

- **우선순위는 흐름제어의 종속 기능** — 흐름제어가 큐에 메시지를 쌓아야 우선순위가 의미를 가짐
- **설계 복잡도에 따라 접근 방식을 달리해야** — 독립적 기능(JWT, 인덱스)은 바로 코딩. 얽힌 기능(흐름제어+우선순위+큐+락)은 설계 문서 먼저
- **MQTT v5 Receive Maximum = 검증된 패턴** — 메시지 무손실 프로토콜에서의 in-flight window 흐름제어

---

*author: kodeholic (powered by Claude)*
