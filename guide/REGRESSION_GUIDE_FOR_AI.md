# 회귀시험 (oxe2e) 가이드 — AI용

> **invoke 키워드: `회귀시험`** — 이 단어가 나오면 이 가이드를 먼저 로드한다.
> 로드 의무: 회귀시험 세션 전 필독 (`QA_GUIDE_FOR_AI.md` / `METRICS_GUIDE_FOR_AI.md`와 동급).
> author: kodeholic (powered by Claude)
> created: 2026-05-30

---

## §0 이게 뭔가 / 용어 (먼저 — 안 헷갈리게)

**시험 3계층**:
```
단위(cargo test)  →  회귀(oxe2e)  →  E2E/smoke(브라우저)
미디어 흐름 없음      헤드리스 봇 구조      실디코더/UX, 무겁다
                     라우팅, 빠름(3~5분)   QA_GUIDE_FOR_AI.md
```

- **회귀시험 = oxe2e** = 헤드리스 봇이 서버에 붙어 **구조 라우팅이 안 깨졌나**를 빠르게 확인하는 gate. 리팩토링·구현 후 "뭐 깨졌나" 싸게 검증.
- **"E2E"/"smoke" = 브라우저**(QA_GUIDE). oxe2e와 **다른 계층**이다. 이름이 비슷하다고 섞지 말 것.
- 본 가이드는 **회귀(oxe2e)** 전용.

**언제 돌리나**: 구현·리팩토링 작업 후, **커밋 전**. (작업 지침의 완료 조건 — 커버되는 시나리오 한정.)

---

## §1 어떻게 돌리나

**전제**: 서버(oxsfud + oxhubd) 기동 상태여야 한다.
- hub WS = `ws://127.0.0.1:1974/media/ws` (포트 1974, base_path `/media`).
- 방은 서버 `startup.rs`가 사전생성(`qa_test_01`~`03`). 봇은 join만, 방 생성 안 함.
- 서버 기동은 부장님 몫(또는 직접 띄운 뒤 실행).

**실행**:
```bash
RUST_LOG=info ./target/debug/oxe2e scenario scenarios/<name>.toml
```

**결과**:
- `✓ PASS` → exit 0
- `✗ FAIL` → exit 1 + 위반 항목(구간/봇/ssrc 명시). 이게 서버 로그 추적 단서.

---

## §2 현재 시나리오

| 시나리오 | 커버 | 판정 |
|---|---|---|
| `conf_basic` | full conference, 전환 없음 | fan-out 대칭, 약속↔이행 |
| `ptt_rapid`  | half-duplex floor(PTT) 회전 | floor 라우팅 + gating 음성(self/other/off 구간) |

---

## §3 판정 모델 (시나리오에 "검증 항목"을 쓰지 않는다 — 봇이 자동 판정)

- **약속 ↔ 이행**: 서버가 약속한 ssrc(TRACKS_UPDATE add + half는 ROOM_JOIN initial_tracks + floor Granted)가 **RTP로 도착**했나.
- **존재**: 조합 당위(N명 full → 각자 N-1명 수신)상 add가 다 왔나.
- **gating(half)**: floor Granted/Idle 이벤트로 구간을 나눠 —
  - OnSelf(자기 발화) = 미수신 정상 / OnOther(타화자) = 수신 정상 / Off(idle) = 미수신 정상.
  - **guard band**(전환 경계 양쪽 제외, 현재 250ms)로 silence flush·keyframe 잔류를 누수로 오판하지 않는다.

---

## §4 충실도 경계 ★ 뭘 믿고 뭘 못 믿나

- **잡는 것**: 구조 라우팅, fan-out 대칭, floor 라우팅, gating 음성, SSRC rewrite, 약속↔이행 정합.
- **못 잡는 것**: 실제 미디어 품질(디코딩 / NetEQ / jitter buffer / 영상 품질), UX. → **브라우저 E2E(QA_GUIDE)** 영역.
- 봇은 **Fake RTP**다 — RTP 헤더(SSRC/seq/ts/marker/PT) + mid extension만 충실, 페이로드는 더미. 원칙: *"서버가 읽는 것만 충실, 안 읽는 것은 더미."*
- **PASS ≠ 미디어 품질 보장.** 라우팅이 살아있다는 뜻이지 화질/음질이 좋다는 뜻이 아니다.

---

## §5 한계 (현재)

- **미커버 시나리오**: simulcast, mute, lifecycle(rejoin/zombie/take-over), cross-room. (추가 시 §6.)
- **admin 삼각검증**(track-dump 4-Point) 미구현 — 봇 단독 약속↔이행만. (설계서 §9 ssrc 조회 경로 미결.)
- **guard band 250ms**: hold가 짧은(≤1초) 시나리오와 충돌 가능 — 그땐 재조정 필요.

---

## §6 TOML 확장법 (새 시나리오 추가)

**스키마**:
```toml
[meta]
name = "<시나리오명>"
desc = "<설명>"

[server]
hub_url = "ws://127.0.0.1:1974/media/ws"
room    = "qa_test_0X"   # startup.rs 사전생성 방 (qa_test_01~03)
token   = ""             # 비우면 oxe2e가 REST 자동 발급

[[participants]]
id = "<봇 id>"
tracks = [
  { kind = "audio", duplex = "full" },   # kind: audio|video|screen
  { kind = "video", duplex = "half" },   # duplex: full|half
  # simulcast = true 는 스키마 예약 — 시나리오 미구현(충실도/판정 보강 필요)
]

[[timeline]]              # 각 [[timeline]] 한 줄 = phase 경계
at = <초>
do = "<액션>"
# 액션별 추가 필드 (아래)
```

**타임라인 액션**:
| 액션 | 필드 | 상태 |
|---|---|---|
| `join` | `at` | 구현됨 |
| `publish` | `at` | 구현됨 |
| `floor` | `at`, `actor`, `hold`(초) | 구현됨 |
| `wait` | `at`, `sec` | 구현됨 |
| `leave` / `rejoin` | `at`, `actor` | **예약**(미구현) |
| `subscribe_layer` | `at`, `actor`, `target`, `layer` | **예약**(미구현) |
| `mute` | `at`, `actor`, `kind` | **예약**(미구현) |

**확장 절차**:
1. `scenarios/<name>.toml` 작성 (참여자 조합 + 타임라인).
2. 방은 사전생성 방(`qa_test_01`~`03`) 사용. 더 필요하면 `startup.rs` 사전생성 목록 추가 (REST `POST /media/rooms`는 인증 갭으로 현재 불가 — 설계서 발견_사항).
3. **새 액션 어휘**(leave/subscribe_layer 등)면 → 봇 dispatch + judge 확장 필요(코딩).
4. **새 트랙 속성**(simulcast 등)이면 → 충실도(VP8 keyframe descriptor 등) + 판정(레이어별 vssrc) 보강 필요(코딩).
5. 돌려서 PASS 확인. 새 영역은 양성+음성(있는 경우) 둘 다 검산되는지 확인.

> 단순한 "참여자 조합 + 기존 액션"만이면 TOML 한 파일로 끝난다. 새 *동작*이 들어가면 봇/judge 코딩이 따라온다 — 이 경계를 먼저 판단할 것.

---

## §7 오진 방지 (QA_GUIDE 정신 계승)

1. **PASS를 미디어 품질로 읽지 말 것** — 충실도 경계(§4). 품질은 브라우저.
2. **FAIL은 봇 출력(구간/봇/ssrc)부터 → 서버 로그 추적** (2단계). 봇 숫자만으로 단정 금지.
3. **localhost에서 물리 유실은 없다** — 수신 0은 논리(라우팅/rewrite/gating)에서 찾는다.
4. **서버를 안 건드린 작업이면 회귀 PASS는 "안 깨졌다"의 근거** — 단 커버 안 된 영역(§5)은 PASS가 보증하지 않는다.

---

*author: kodeholic (powered by Claude)*
