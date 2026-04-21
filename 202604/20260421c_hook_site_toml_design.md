# Hook System 설정 저장 위치 결정 — site.toml 신설

## 배경
부장님이 "훅 호출 URL을 어디에 적어둬야 되나" 고민으로 Hook System 작업 진도가 막혀 있었음. 본 세션에서 결정.

## 결정 사항

### 1. `site.toml` 신설
`system.toml` / `policy.toml` 과 나란히 **세 번째 readonly 설정 파일** 도입.

역할 분리:
| 파일 | 의미 | 재시작 |
|------|------|--------|
| `system.toml` | 인프라 정체성 (포트, 경로, TLS, JWT secret) | 필요 |
| `policy.toml` | 런타임 정책 (타이머, 대역폭, 방 정책) | 불필요 (ArcSwap) |
| **`site.toml`** (신규) | **사업/고객 정체성 (사이트 이름, 훅 URL)** | **필요 (readonly)** |

`system.toml`에 합치면 안 되는 이유: 인프라 설정(포트) 보러 들어간 사람이 고객 훅 URL 스크롤 하게 됨. 관심사 분리 실패.

### 2. 방별 훅 URL 미지원 확정
- B2B 1사 1서버 모델 → 서버 단위 훅 1세트면 충분
- 멀티테넌트 SaaS → DB 필수 영역 (DB 없이 파일로 버티는 건 설계 실패)
- 중간 영역 고객은 **실재하지 않음**
- pattern matching (`[[rooms]]`) 도입은 YAGNI

### 3. URL 리스트 지원 (단수→복수)
LiveKit self-hosted webhook 구조 준거:
```yaml
webhook:
  urls:
    - https://your-host.com/handler
```

OxLens도 단일 URL이 아닌 리스트로 설계. 근거:
- 고객사 메인 백엔드 + 데이터 분석 파이프라인 동시 구독
- 프로덕션 + 스테이징 미러링
- 운영 + 모니터링 SaaS(Datadog 등) 병행
- 구현 차이: `for url in urls { spawn_task(send(url)) }` 한 줄
- 나중에 추가하는 것보다 지금 넣는 게 API 호환성 측면에서 쌈

### 4. 시크릿은 환경변수 참조
`site.toml`이 git에 올라갈 가능성 있으므로 HMAC secret은 직접 기재 금지.
```toml
[hooks]
secret_env = "OXLENS_HOOK_SECRET"   # 키 이름만
```
마스터의 `.env / dotenvy 완전 삭제` 원칙은 "설정값을 .env에 분산 금지"이지 "환경변수 자체 금지"는 아님. (부장님 확인 필요)

### 5. Webhook payload 구조 (단일 URL + event 필드)
업계 전원 동일 방식:
- LiveKit, Stripe, GitHub, Slack 모두 단일 URL + payload `event`(또는 `type`) 필드로 분기
- URL path 분리 (`/webhook/floor.taken`) 는 고객사 방화벽/로깅 부담 증가
- 네이밍: `floor.taken`, `participant.joined` 같은 **dot notation** (와일드카드 필터 용이)

payload 스키마:
```json
{
  "event": "floor.taken",
  "id": "evt_01H...",
  "created_at": 1713696000,
  "site": "<site.name>",
  "data": { ... }
}
```

Rust enum + serde `#[serde(tag = "event", content = "data")]`로 깔끔하게 구현 가능.

### 6. Hook 실패 시 대안 — 현황만 파악 (선택 보류)
LiveKit 공식: "no guarantees around delivery" — 5회 재시도 후 포기가 업계 표준.
DLQ 패턴이 권고되나 영속 저장소(DB) 요구 → DB-less 원칙 충돌.

선택지 (부장님 판단 대기):
- A: 재시도만 (LiveKit 수준)
- B: JSONL 파일 DLQ (감사 증거 보존)
- C: REST 조회 API + ring buffer (풀 모델 백업)
- D: 완전체

현재는 A로 시작해도 충분하다는 게 본 세션 결론. Phase 2/3는 고객사 요구 들어올 때 결정.

## 최종 site.toml 초안

```toml
[site]
name = "<사이트 식별자>"

[hooks]
urls = [
    "https://<customer>/oxlens/webhook",
]
secret_env = "OXLENS_HOOK_SECRET"
events = ["floor.taken", "floor.idle", "participant.joined", "participant.left"]

[hooks.retry]
max = 3
backoff_ms = 500
timeout_ms = 5000
```

## 마스터 문서 업데이트 필요 사항

`구현 예정` 섹션의:
> Hook System: Webhook 14종 + REST API + **RoomStore trait**

여기서 `+ RoomStore trait`는 **삭제 대상**. DB 없이 가는 이상 불필요. 훅 URL은 `site.toml` 읽어서 `Arc<SiteConfig>`로 전역 공유만 하면 됨.

## 오늘의 기각 후보

- **방별 훅 URL 파일 관리** — B2B는 전역 1개로 충분, SaaS는 DB 필수. 중간 없음.
- **`system.toml`에 훅 설정 합치기** — 관심사 혼합. 운영 실수 유발.
- **RoomStore trait 도입** — 훅 URL이 방 단위 상태가 아니니까 불필요.
- **URL path 기반 event 분기** — 업계 전무. 단일 URL + payload 필드가 표준.

## 오늘의 지침 후보
(이 세션에서 도출된 신규 지침 없음 — 관련 지침은 20260421d 파일 참조)

## 후속 작업
1. `common/src/config/site.rs` 신설 (`system.rs` 패턴 복제, ArcSwap 없음)
2. `oxhubd`에 `HookDispatcher` (HTTP POST + HMAC-SHA256 + 재시도)
3. Webhook 14종 이벤트 정의 (Rust enum + serde tag)
4. `PROJECT_MASTER.md`의 Hook System 항목에서 `+ RoomStore trait` 문구 제거

---
author: kodeholic (powered by Claude)
