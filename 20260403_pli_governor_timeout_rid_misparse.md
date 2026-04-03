# 세션: PLI Governor 영구 고착 수정 + rid 오독 수정

- **날짜**: 2026-04-03
- **버전**: v0.6.12-dev
- **영역**: 서버 (pli_governor.rs, ingress.rs, room.rs)
- **이전 세션**: `20260402_duplex_phase2_ingress_migration.md`

---

## 1. 완료 작업

### A. room.rs 주석 현행화 (5곳) ✅
- PTT → half-duplex 용어 전환

### B. SKILL_OXLENS.md DuplexMode 반영 (블록 제공, 부장님 적용 필요)

### C. PLI Governor 영구 고착 수정 (pli_governor.rs) ✅
- `needs_keyframe_since` + `needs_keyframe_layer` 필드 추가
- step 1 타임아웃 안전망 (h=1.5s, l=500ms) → fall-through 재시도
- step 3/4 since 기록, on_keyframe_relayed since 클리어

### D. Simulcast PLI 릴레이 h SSRC 치환 (ingress.rs) ✅
- PLI(PSFB) → h SSRC, NACK → 현재 레이어 SSRC (기존)

### E. intent 미도착 시 rid 파싱 금지 (ingress.rs) ✅
- `has_rid_hint = intent.rid_extmap_id != 0` 가드
- config::RID_EXTMAP_ID=4 fallback → Chrome MID=4 충돌 방지

---

## 2. 버그 재현 조건

### PLI Governor (이전 서버 로그)
- 3탭 sim, SUBSCRIBE_LAYER h→l → Chrome PLI → l SSRC 릴레이 → 무시 → pending 영구

### rid "1" 오독 (이번 세션)
- RTP 18ms 선착 → intent.rid_extmap_id=0 → fallback 4=MID → rid="1" → video 3중 notify → BUNDLE 충돌

---

## 3. 기각된 접근법

- DuplexMode가 PLI Governor 원인 → Conference에서 track_duplex=Full, 기존과 동치
- needs_keyframe 별도 상수 → 기존 PLI_RETRY_TIMEOUT과 동일 의미
- config::RID_EXTMAP_ID fallback 유지 → Chrome publish extmap 충돌 불가피

---

## 4. 수정 파일

| 파일 | 수정 |
|------|------|
| room.rs | 주석 5곳 |
| pli_governor.rs | 타임아웃 안전망 |
| ingress.rs | PLI h SSRC 치환 + rid 파싱 가드 |

---

## 5. 다음 작업

- [ ] 빌드 + PC 테스트 (sim 3~4탭, PTT)
- [ ] SKILL_OXLENS.md 블록 적용
- [ ] SESSION_INDEX.md 업데이트

---

*author: kodeholic (powered by Claude)*