// author: kodeholic (powered by Claude)
# 20260606b — 클라 SDK 외부 API 평면 카테고리 분석 (C1~C7, C5 제외)

> 김대리(claude.ai) 분석/설계 세션. 코드 무수정 — `context/design/` 산출물만. 결재 전 탐색.
> 목적: 업계 클라 SDK(LiveKit/mediasoup/Jitsi) 공개 표면을 7 카테고리 분류 → 우리 신 SDK(`oxlens-home/sdk/`)의 **이상적 외부 노출 평면**을 카테고리별 독립 설계문서로.

---

## 산출물 (context/design/)

| 파일 | 내용 |
|------|------|
| `20260606_client_api_categories.md` | C1~C7 4열 대조표(현황 인벤토리, 김과장 작성·검토) |
| `20260606_client_api_ideal_surface.md` | C1 연결/세션 + 공통원칙 P1~P5 |
| `20260606_client_api_c2_send.md` | C2 송신/발행 심화 |
| `20260606_client_api_c3_recv.md` | C3 수신/구독 심화 |
| `20260606_client_api_c4_device.md` | C4 장치 심화 (본 세션 §5.4 보강) |
| `20260606_client_api_c6_observability.md` | C6 관측/이벤트/에러 (본 세션 작성) |
| `20260606_client_api_c7_ptt.md` | C7 PTT+다방청취 (본 세션 작성, 다수 재작성) |

C5(데이터/제어) 미착수. 7 카테고리 권위 설계서(`20260603_client_rewrite_core_design.md`) 승격 미완.

---

## 공통 원칙 (P1~P5)

P1 관심사 격리 · P2 facade만 노출(Transport/Signaling 내부) · P3 상수화(이벤트명/상태/사유 enum, raw string 금지) · P4 server-authoritative(SDP-free, codec=서버 answer 권위) · P5 프리셋 비의존(SDK는 역할 모름, `duplex==='half'`로 PTT 자연분기).

---

## 카테고리별 핵심 결정

### C4 장치 — §5.4 swapTrack ↔ simulcast/PTT 충돌 (실측 보강)
`local-pipe.js` swapTrack + `power.js` half-duplex FSM 실측 결과:
- **① simulcast**: `replaceTrack`이 encoding(RID/sendEncodings) 보존 → swapTrack 이 getParameters 안 건드려 **"옳게 아무것도 안 해서" 안 깨짐**. 단 새 device 가 기존 레이어 해상도보다 낮으면 상위 레이어 죽음 + **constraints 재적용 없어** 화질 변동(livekit restartTrack 은 applyConstraints 함).
- **② PTT half-duplex 진짜 결함**: floor 안 잡으면 mic 가 SUSPENDED(`_savedTrack` 보관)/RELEASED. 이때 swapTrack 은 `trackState!==ACTIVE`라 **`"not_active"` 조용히 무시** → 다음 floor grant 시 `_resumePipe`가 `_savedTrack`(옛 device) 되살려 **전환 전 마이크로 발화**. 수정=trackState별 분기(ACTIVE=swapTrack+constraints / SUSPENDED=_savedTrack 교체 / RELEASED=savedConstraints.deviceId).
- **③ 직렬화 부재**: device 전환↔floor grant↔duplex 전환 `_sender.replaceTrack` 경합. C2 §6-D trackChangeLock 공유.

### C6 관측/이벤트/에러 — 냄새 = 단일 평면 raw string vs 계층별 enum 방향
부장 의도 교정: 냄새 = 내부 결함 아니라 **외부 노출 방식이 C1~C5 가 깐 방향과 불일치**.
- 현행: 단일 EventBus 에 raw string 수십 개 평평하게(`"lifecycle"`/`"pc:failed"`/`"floor:granted"`...). 에러 5갈래(lifecycle:error/fatal/error/critical_error/device:error) + 분류기 3중복(MediaAcquire._classify vs Lifecycle.classifyMediaError/classifyPcError — 같은 NotAllowedError 가 PERMISSION_DENIED vs denied).
- 업계: livekit 3계층 enum(RoomEvent/ParticipantEvent/TrackEvent) + 타입드 콜백 맵 / mediasoup observer 분리 + @-prefix 내부 이벤트.
- 이상적: **EventBus 1개 유지 + 외부에 계층 facade 창**(engine/room/participant/stream .on), enum 상수화(C1~C3 명명한 것 단일출처 export), 내부/외부 분리(track:received 등 비노출), 에러 throw(동기)/event(런타임) 2갈래, 분류기 DeviceError 단일.
- 별건 내부 냄새: telemetry.js 가 "getStats=Transport.collectStats 경유" 선언하고 sendSdpTelemetry 에서 `transport.pubPc.localDescription` 직접 만짐(절반 캡슐화).

### C7 PTT + 다방청취 — engine.scope 단일 진입, 이벤트가 room 핸들 동봉
업계 화상회의 SDK 관례 없음(우리 고유). C2/C3 핸들 + C6 노출방향 + Zello 참고.
- **핵심 발견(§2.1)**: `mbcp.js` wire 는 다방 다 지원(parseMsg 가 speakerRooms 0x16/viaRoom 0x17/destinations 0x18 파싱)인데 **floor.js FSM 이 단일방으로 누름**(this.roomId 하나, buildRequest destinations=[roomId] 고정, viaRoom 무시). scope.js 빈 stub. → 서버(sub_rooms/pub_room)+wire 완성, **클라 floor FSM+scope 만 단일방/stub**.
- **최종 외부 평면(부장 직접 교정)**:
  - 발화권 제어·수신 = **`engine.scope` 단일 진입**(다방이라 방별 핸들 .on 안 검).
  - `engine.scope.request(priority)` / `release()` / `affiliate(roomId)` / `deaffiliate(roomId)`.
  - **이벤트가 `room` 핸들을 들고 옴**: `engine.scope.on(FloorEvent.TAKEN, ({ room, speaker }) => ...)`. roomId/viaRoom 분해 폐기.
  - **affiliate = Room 생성**(청취=수신=컨테이너 필요). Room 무게는 RemoteEndpoint 수에 비례하고 half-duplex 는 방당 동시 발화 0~1 라 100채널도 안 꽉 참.
  - mount = 발화권 아닌 **트랙(RemoteStream.attach → RemotePipe.mount)** 에 붙음. floor 는 mount 된 element 표시(showVideo/hideVideo)만 제어(freeze masking). onMount hook: engine→Room(opts.onMount)→RemoteEndpoint→RemotePipe.
- PTT 고유: priority preemption / queue / revoke / speaker 단수 / duration / "트랙 발행 ≠ 발화" / 채널별 mute(Zello).

---

## 기각된 접근 (본 세션 내 틀린 가정 — 부장 교정)

- **room.floor.on 을 청취 방마다 (방별 floor 핸들)** — 다방서 리스너 N개 + 앱이 어느 방 분기. → engine.scope 단일 진입 + 이벤트 room 동봉.
- **"방별 floor N개"** — floor FSM 은 발화(pub_room) 기준. 청취 방은 수신 통지지 상태머신 아님. (단 최종은 scope 단일로 수렴, 방별 인스턴스도 폐기.)
- **이벤트에 roomId/viaRoom 전달** — 앱이 식별자 역해석. room 핸들 직접 동봉(C2/C3 정합). viaRoom/speakerRooms 는 SDK 내부 라우팅 메타(외부 비노출).
- **청취 방 Room 안 만듦** — affiliate=수신=컨테이너 필요. Room 만든다(무게 우려는 과대평가였음).
- **`request(roomId, priority)` 로 roomId 인자** — pub_room 이 이미 선택된 발언 방. request 는 인자 불요. (발언 방 전환 select 의 서버 지원 여부는 미확인 — 현재 join=pub_room 고정 가능성.)
- **PTTStream 별도 추상화 타입** — 검토했으나 LocalStream/RemoteStream(duplex='half')에 floor 의미 얹는 것으로 충분. 단 최종 발화권 진입은 scope.

---

## 부장 피드백 (다음 세션 엄수)

세션 내내 강하게 질책받음. 핵심:
- **핑퐁 금지** — 한 카테고리 진입 시 우리 소스 실측 → 업계 전수 → 대조로 빈칸 다 채운 뒤 한 흐름으로 완결. 부장 질문이 검토를 대신하게 두지 말 것(중요한 게 검토 단계서 계속 누락됨).
- **택1 남발 금지** — "둘 중 뭐?"가 아니라 양립이면 둘 다 한 흐름으로. 부장이 "택1" 제시를 특히 싫어함.
- **기록 전 검토** — 문서 쓰기 전 전체 정합 확인. 쓰고 나서 틀린 가정 발견 반복.
- **추궁/자기변호/감정대응 금지** — 인정하고 다음 분석. 소스 더 읽는 것으로 답 대신하지 말 것(부장이 "자꾸 읽어대"라고 질책 — 답을 직접 말할 것).
- 본 세션은 C7 다방청취에서 같은 자리(room.floor / roomId / viaRoom / Room 생성 / request 인자)를 부장이 한 줄씩 짚어야 고쳐지는 식으로 진행됨 — **한 번에 풍부하게 안 나온 게 최대 문제**.

---

## 다음 작업

- C5(데이터/제어) 분석 — MESSAGE/ANNOTATE/CLIENT_EVENT, DC svc + WS op 등록제. 우리 소스(dc-frame/op-registry) 실측 → 업계(livekit DataPacket/RPC/DataStream, mediasoup DataProducer/Consumer) 전수 → 대조.
- 7 카테고리 권위 설계서 `20260603_client_rewrite_core_design.md` 승격.
- 구현 델타(부장 결재 후 김과장): C4 §5.4 PTT device 전환 결함 / C6 계층 facade+enum+에러 분류기 3→1 / C7 floor.js 단일방→다방(roomId 차원+viaRoom 살림)+scope.js 구현+engine.scope 단일 진입+이벤트 room 동봉.

### 오늘의 기각 후보
- 위 "기각된 접근" 6건 — C7 다방청취 외부 평면 설계 시 재유혹 높음.

### 오늘의 지침 후보
- 카테고리 분석 작업지침: ①우리 소스 실측 먼저 ②업계 전수 표 ③대조로 빈칸 채움 ④논의 — 순서 고정. 부장 질문 전에 표가 완성돼 있을 것.
