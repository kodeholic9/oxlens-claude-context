// author: kodeholic (powered by Claude)
# 서버 맞춤 — TRACK_STATE_REQ muted 통합(G1) + SCOPE pub_select(S2) 완료보고

> 작성: 2026-06-09. 클라 선행: 외부평면 ①②(G1·G7 / G2~G5) 커밋 c3d5552·a52d02d.
> 대상: `oxlens-sfu-server/crates/oxsfud/` (별 repo). **커밋 전 상태** — diff 검토 후 GO 시 커밋.
> 배경: 클라가 이미 송신 중인 두 op 를 서버가 받도록 "서버를 맞춘다".

---

## 1. G1 — TRACK_STATE_REQ(0x1106) muted 수용 (MUTE_UPDATE 통합)

클라는 mute 를 `TRACK_STATE_REQ {track_id, ssrc, muted}` 로 보내지만 서버 0x1106 은 duplex 전용이었음(`duplex` 필수, muted 미처리). → body 분기 수용.

- **`message.rs TrackStateReq`**: `duplex: String` → `Option<String>`(serde default), `+muted: Option<bool>`. body 분기({muted?}/{duplex?}).
- **`track_ops.rs`**:
  - `handle_mute_update`(0x1103)의 mute 로직을 **`do_mute(...)` 공유 헬퍼로 추출**(mute_stream + TRACK_STATE{muted} fanout + video mute=VIDEO_SUSPENDED / unmute=PLI). 로직 **동일**(바이트 보존), `reply_op` 파라미터만 추가.
  - `do_track_state_req`: `req.muted` Some → `do_mute(reply_op=TRACK_STATE_REQ)`. None → 기존 duplex 전환(`req.duplex` Option unwrap, 없으면 3002). **duplex 경로 무변경.**
  - `handle_mute_update`(0x1103): 하위호환 잔존 — `do_mute(reply_op=MUTE_UPDATE)` 위임.
- 결과: 0x1106 이 mute(track_id 기반, camera/screen 구분)+duplex 단일 경로. 통지(TRACK_STATE 0x2102)는 이미 통합이라 무변경.

## 2. S2 — SCOPE pub_select (발언방 동적 전환)

클라 `select(R)` 이 `SCOPE {mode:update, pub_select:R}` 송신하나 서버 pub_room 변경 op 부재였음. → 수용.

- **`message.rs ScopeUpdateRequest`**: `+pub_select: Option<String>`(serde default).
- **`scope_ops.rs apply_scope_update`**: sub_add/sub_remove 적용 **후** pub_select 처리 — `R ∈ sub_rooms` 검증(pub⊆sub §4.2, 위반 시 warn+skip=부분성공) 후 **`peer.publish.select(R)`**(기존 메서드 재사용). 같은 SCOPE 에 affiliate+select 동봉 가능(순서: sub → pub).
- **server-authoritative 확정**: 응답 payload `pub_rooms` 가 `peer.publish_room()`(select 반영 후) 로 빌드 → 클라가 응답에서 새 pub_room 확인. 별도 통지 op 불요.
- info/agg 로그에 `pub_select` 결과 동반.

---

## 3. 검증

- **`cargo check --workspace` PASS** (oxsig/common/oxrtc/oxhubd/oxsfud/oxe2e 전부 clean).
- **저위험 근거**: ① duplex 전환 경로 바이트 보존(mute 분기를 앞에 추가 + Option unwrap만). ② `do_mute` 는 `handle_mute_update` 본문 **동일 추출**(0x1103 동작 불변). ③ pub_select 는 신규 필드 게이트 추가(기존 sub 처리 무변경). ④ `publish.select` 는 기존 메서드.
- **oxe2e 회귀**: `scenarios/duplex_cache.toml`(duplex 경로) 가 직접 커버 대상. oxe2e 는 라이브 스택(sfud+hub) 기동 필요 → 미실행. 필요 시 스택 기동 후 진행(부장님 판단 — 앞선 "회귀 불요" 기조).

---

## 4. 변경 파일

```
crates/oxsfud/src/signaling/message.rs            TrackStateReq(duplex Option+muted) / ScopeUpdateRequest(+pub_select)
crates/oxsfud/src/signaling/handler/track_ops.rs  do_mute 추출 + do_track_state_req muted 분기 + handle_mute_update 위임
crates/oxsfud/src/signaling/handler/scope_ops.rs  apply_scope_update pub_select 처리(pub⊆sub 검증 + publish.select)
```
(서버 repo = 내 3개 파일만, 선재 변경 0)

---

## 5. 정합 효과 (클라 ⊗ 서버)

- 클라 G1 mute(0x1106) → **이제 서버 처리**(남들 avatar 전환·VIDEO_SUSPENDED·PLI 동작). 클라 `OP.MUTE_UPDATE` 상수는 死op(서버 0x1103 핸들러 잔존이라 양쪽 안전, 후속 동시 제거 가능).
- 클라 G4 select(SCOPE pub_select) → **이제 서버 pub_room 변경 + 응답 확정**. 단 **same-sfu 라벨 전환만**(클라 cross-sfu republish 미구현 — §6 후속 그대로).

## 6. 남은 후속

- **cross-sfu select**: 발언 PC republish(클라 transport) — 서버 pub_room 은 이미 전환되나 미디어 경로 이동 미구현.
- **S3 presence 단독**: 미지원 유지(필요 시).
- 클라 `_selectRoom`/`scope.js` 의 "⚠ 서버 미처리" 주석 → 이제 처리됨으로 갱신(선택, 별 커밋).
- 0x1103 MUTE_UPDATE 완전 폐기(클라 상수 + 서버 핸들러 동시 제거) — 송신처 0 확인됨.

---

*author: kodeholic (powered by Claude)*
