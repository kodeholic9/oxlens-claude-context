// author: kodeholic (powered by Claude)
# 외부평면 후속 — A(정합) + B(cross-sfu) 완료보고

> 작성: 2026-06-09. 선행: 외부평면 ①②(클라) + 서버 맞춤(60e6dba). 커밋: 클라 40c6465 / 서버 변경 없음.

---

## A — 정합 마무리

### A1. 0x1103 MUTE_UPDATE 완전 폐기 — ❌ 블록
- **Android SDK 가 0x1103 송신 중**(`OxLensClient.kt:523 notifyMuteServer`). 게다가 Android opcode 세트가 v3 와 다름(`MUTE_UPDATE=17`, `TRACK_STATE=102`, `TRACK_STATE_REQ` 없음) — 송신부 하나 교체로 안 끝나고 빌드 환경도 없음.
- → **서버 0x1103 핸들러 유지**(Android 하위호환, 死 아님). web `OP.MUTE_UPDATE` 상수도 문서화 순서("서버 폐기 후 제거")대로 유지. **완전 폐기 = Android 프로토콜 정리 선행**(별 작업).

### A2. 거짓 주석 정정 — ✅ 완료
- G1 muted·S2 pub_select 가 서버 처리됨(60e6dba) → "⚠ 가정/서버 미처리" 5건을 "서버 처리(60e6dba)"로 정정(`scope.js`/`local-endpoint.js`/`engine.js` ×3). `MUTE_UPDATE` 상수 주석에 Android 잔존 송신처 명시.

## B — cross-sfu select

### B (구현) — ✅ 코드 완료 / ⏸ 브라우저 미검증
- `LocalEndpoint.migratePublish` — 발언 트랙을 새 sfu PC 로 이전. `transport.deactivatePublishTrack`(transceiver inactive + sender=null, **track.stop 안 함**)으로 **같은 MediaStreamTrack 보존** → 새 transport republish(§4.3 mic 보존).
- `engine._selectRoom` cross-sfu 분기 — migratePublish + **ptt 재생성**(floor DC/power 새 transport, assembleRoom 패턴).
- **롤백 경로**(지침 §6) — republish 실패 시 옛 transport 복귀 재발행(트랙 보존). 실패해도 발언축 유실 방지.

### B 검증
- **node 유닛(`_op_check`)**: 트랙 보존(stop 금지)·새 transport 바인딩·구 sfu 정리·spec 보존·pipes 정리·**롤백**(republish 실패→옛 sfu) — PASS.
- ⏸ **브라우저 실검증 미완**: SDK cross-sfu select 는 실 RTCPeerConnection 협상이라 브라우저에서만 검증. 이 환경엔 헤드리스 자동화 없음. 수동 절차(2-sfu: qa_test_02@sfu-1 → select qa_test_01@sfu-2, conference 데모 콘솔 affiliate/select) 별도 전달.

---

## 검증 / 환경
- sdk 하니스 16/17 PASS(`_t3a` 선재). cargo(서버) 변경 없음.
- 멀티-sfu 확인: oxsfud 2개(50051/50052), oxhubd(1974). 방 배치 qa_test_01→sfu-2 / qa_test_02·03→sfu-1.

## 남은 것
- **B1 브라우저 실검증** — 부장님 수동 RUN(2-sfu).
- **A1 Android 0x1103 이관** — 별 repo, 프로토콜 세트 정리 선행.
- mute/scope oxe2e 시나리오(봇/judge 확장), `_t3a` 선재 FAIL, §8 복수트랙 이벤트 정밀 라우팅.

---

*author: kodeholic (powered by Claude)*
