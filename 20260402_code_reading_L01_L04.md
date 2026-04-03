# 세션: SFU 코드 리딩 L01~L04 (Phase 1 완료)

- **날짜**: 2026-04-01 ~ 04-02
- **주제**: Phase 1 — 서버 뼈대 전체 코드 리딩
- **산출물**: 커리큘럼 L01~L04 완료

---

## 완료 회차

### L01: config.rs — 설정과 상수 ✅ (04-01)
- pub const 패턴, 타입 선언 (u8/u16/u32/u64/usize)
- enum (BweMode, RoomMode) + #[derive] 매크로
- fn 함수 선언, 클로저 |v| 문법
- .env 오버라이드 패턴 (resolve_remb_bitrate)
- Duration::from_millis() vs 숫자 직접 사용
- PT 하드코딩 현장 확인 (is_video_pt 함수의 한계)
- demux 상수: 첫 바이트로 STUN/DTLS/RTP 분류

### L02: error.rs — 에러 처리 체계 ✅ (04-01)
- thiserror 크레이트, #[error("...")] 매크로
- enum LightError — 에러 카탈로그 (1xxx~9xxx 체계)
- 데이터를 품는 enum 변형: Internal(String)
- impl 블록: &self = JS의 this (읽기전용), Self = 자기 타입
- Result<T, E> = try/catch 대신 반환값으로 성공/실패 표현
- LightResult<T> 타입 별칭 = Result<T, LightError>
- ? 연산자 = 에러 자동 전파 (잡는 게 아니라 위로 넘김)
- **발견**: 코드가 light-livechat 시절 이력 보유 (LightError → LiveError 이전)

### L03: state.rs / main.rs / startup.rs — 서버 부팅 ✅ (04-02)
- #[tokio::main] — Tokio 비동기 런타임 설치
- if let Err(e) — 단일 패턴 매칭
- Arc<T> — 여러 쓰레드 안전 공유 (카운터 기반, GC 대체)
- AppState 구조체 — 서버 전역 상태 (Vuex store 비유)
- pub vs pub(crate) — 의도 표현 (외부 공개 vs 내부 전용)
- Vec<String>, .position(|a| ...) — 배열 + 탐색
- Option<T> (Some/None) — null 대체
- <T: FromStr> — 제네릭 (타입을 매개변수로)
- &str vs String — 빌린 문자열 vs 소유 문자열
- 부팅 흐름: .env 로드 → IP 감지 → AppState 생성 → 기본 방 → UDP bind → WS listen

### L04: room.rs / participant.rs — 핵심 자료구조 ✅ (04-02)
- **Room 3중 인덱스**: participants(user_id), by_ufrag(ufrag), by_addr(addr) — O(1) 조회
- **RoomHub 역인덱스**: ufrag_index, addr_index — 방 모를 때 방부터 찾기
- **find_by_addr()**: 서버에서 가장 뜨거운 함수 (RTP마다 호출, O(1)×2)
- **latch()**: STUN 래칭 + NAT rebinding 처리
- 인덱스 정합성: add/remove 시 3개 인덱스 동시 갱신
- **Participant 6그룹**: 신원+WS, 2PC(publish/subscribe MediaSession), 트랙+캐시, 품질(recv/send_stats), Simulcast+Gate+Governor, PipelineStats
- MediaSession: ufrag + ice_pwd + address + SRTP context
- RtpCache: seq % 512 링버퍼 (NACK→RTX용)
- PipelineStats: AtomicU64 × 10 카운터 (어드민 진단 원본)
- Track: ssrc, kind, video_codec, source(camera/screen), rid(simulcast)
- mpsc::UnboundedSender — WS 메시지 전송 채널

---

## 학습한 Rust 문법 (Phase 1 누적)

| 문법 | JS 대응 | 회차 |
|------|---------|------|
| pub const NAME: Type = val | export const | L01 |
| u8, u16, u32, u64, usize | number | L01 |
| fn name(arg: Type) -> Ret | function | L01 |
| enum { A, B } | Object.freeze | L01 |
| \|v\| expr | (v) => expr | L01 |
| #[derive(...)] | (없음) | L01 |
| use crate::module::item | import from '@root/' | L01 |
| Result<T, E>, Ok/Err | try/catch | L02 |
| ? 연산자 | if(err) return err | L02 |
| impl Type { fn(&self) } | class { method() } | L02 |
| type Alias<T> = Type<T, X> | (없음) | L02 |
| #[tokio::main] | Node.js event loop | L03 |
| if let Err(e) = ... | catch만 있는 try | L03 |
| Arc<T> | GC / Vuex $store | L03 |
| pub(crate) | (export 안 한 것) | L03 |
| -> Self | constructor | L03 |
| Vec<T> | Array | L03 |
| Option<T> (Some/None) | value / null | L03 |
| <T: Trait> | (없음) | L03 |
| &str vs String | 둘 다 string | L03 |
| (A, B) 튜플 | [a, b] 구조분해 | L04 |
| AtomicU64 | (없음) | L04 |
| Mutex<T> | (없음) | L04 |
| mpsc::Sender | EventEmitter | L04 |
| DashMap<K, V> | concurrent Map | L04 |

---

## 부장님 질문 & 인사이트

- **GlobalMetrics가 왜 AppState에 있나?** → static 싱글톤 대신 AppState에 넣은 이유: 테스트 격리 + 프로세스 분리 대비
- **pub(crate) 왜 쓰나?** → 의도 표현. JS의 _ prefix 관례를 컴파일러가 강제
- **Arc 소유권 괴리** → "기본을 안전하게, 공유는 명시적으로" 철학
- **인지부채** → 코드를 못 읽는 게 진짜 부채. 코드 리딩이 상환 방법
- **첫 커밋 2026-03-03** → 29일 만에 현재 규모

---

## 다음 세션

- **Phase 2: 시그널링** — L05: opcode.rs + message.rs (패킷 정의)
- 소스 필요: `src/signaling/opcode.rs`, `src/signaling/message.rs`

---

*author: kodeholic (powered by Claude)*
