// author: kodeholic (powered by Claude)
# OxLens Web SDK — 이상적 외부 공개 표면 (공통 원칙 + 카테고리 인덱스)

> 짝 문서: `20260606_client_api_categories.md` (현황 **인벤토리** — 3사 vs 우리 표면 대조, 판정 없음).
> 본 문서 = 그 위의 **이상적 설계의 총론** — 전 카테고리 관통 공통 원칙 P1~P5 + 카테고리별 설계문서 인덱스.
> **0606e 정리**: 본래 여기 있던 C1 본문은 `20260606_client_api_c1_connection.md` 로 분리·승격(C2~C7 과 파일 구조 일관성 — 카테고리 본문은 각 파일, 본 문서는 공통 원칙만).
> 상태: **탐색/제안** (결재 전). C1~C7 확정 후 권위 설계서 `20260603_client_rewrite_core_design.md` 에 정식 승격.
> 조사 ground truth: mediasoup-client v3.20 / livekit client-sdk-js v2.19 / lib-jitsi-meet (reference 실소스 전수).

---

## 카테고리 (7) + 설계문서 인덱스

각 카테고리의 **본문(심화)은 독립 파일**. 본 문서는 공통 원칙만 보유.

| # | 카테고리 | 설계문서 | 상태 |
|---|---|---|---|
| C1 | 연결 / 세션 | `20260606_client_api_c1_connection.md` | ✅ 작성(0606e 분리·승격) |
| C2 | 송신 / 발행 | `20260606_client_api_c2_send.md` | ✅ 작성 |
| C3 | 수신 / 구독 | `20260606_client_api_c3_recv.md` | ✅ 작성 |
| C4 | 장치 | `20260606_client_api_c4_device.md` | ✅ 작성 |
| C5 | 데이터 / 제어 | — | ⏳ 미착수 |
| C6 | 관측 / 이벤트 / 에러 | `20260606_client_api_c6_observability.md` | ✅ 작성 |
| C7 | PTT / 무전 (고유) | `20260606_client_api_c7_ptt.md` | ✅ 작성 |

> C5(데이터/제어 — DataChannel·메시지·command·RPC·DTMF·WS op 등록·Annotation·CLIENT_EVENT·Moderate)만 독립 파일 미작성. 현황은 대조표 `categories.md` §5 참조.

---

## 공통 설계 원칙 (전 카테고리 관통)

- **P1 — 관심사 격리**: 각 카테고리 표면은 자기 관심사만. C1 연결옵션에 미디어 품질·수신 배선이 섞이면 오염.
- **P2 — facade만 노출**: Transport/Signaling/TransportSet 등 내부 평면은 외부 비노출. mediasoup식 transport 직접 노출 안 함(B2B 고객이 PC를 다룰 이유 없음). livekit형 고수준 facade가 B2B 정석.
- **P3 — 상수화**: 이벤트명·상태값·종료사유는 raw string 금지. SDK export 상수(enum 류)로 조회/비교/분기. (livekit `RoomEvent`/`ConnectionState`/`DisconnectReason` 동형. 우리 매직넘버 금지 원칙의 클라판.)
- **P4 — server-authoritative**: 전송 정책(ICE/코덱)은 `server_config` 단일 권위. SDP-free 귀결 — 클라 `rtcConfig` 주입구 두지 않음.
- **P5 — 프리셋 비의존**: SDK 는 역할(talker/viewer) 모름. 품질/역할은 primitive 인자로 받고, 프리셋→인자 변환은 앱 레이어.

---

## 카테고리 공통 구조 (각 설계문서 §틀)

C1~C7 설계문서는 동일 틀을 따른다(일관성):

- **§0 한 줄 정의** — 그 카테고리가 무엇을 책임지나 + C1 경계(다른 카테고리로 보내는 것).
- **§1 업계 사고방식** — mediasoup/livekit/jitsi 모델 차이(왜 우리가 이 모델인가).
- **§2 우리 현행 실측** — `sdk/` 실소스 대조(트리/구조). 창작 금지, 실측만.
- **§3 핸들/핵심 개념** — 외부에 쥐어줄 핸들(LocalStream/RemoteStream/Engine·Room 등).
- **§4 표면 전수** — 업계 vs 우리 표(# 매김, 상태 = 갭/OK/누락/우위).
- **§5 핵심 갭 심화** — 가장 무거운 신규.
- **§6 이상적 외부 평면** — 현실 시나리오 샘플(코드) + 핸들 표면 요약 표 + 상수.
- **§7 의도적 비대칭** — 업계엔 있으나 우리 구조가 흡수/배제(누락 아님).
- **§8 현재→이상적 델타** — 실제 고칠 것(★ 우선순위).
- **§9 기각된 접근**.

---

*공통 원칙 총론. 카테고리 본문은 각 `c?_*.md`. C1~C7 확정 후 `20260603_client_rewrite_core_design.md` 승격.*
