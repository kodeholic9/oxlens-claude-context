# 세션 컨텍스트: Conference 비심방 비디오 미노출 + PT 구조 전환

> 날짜: 2026-04-02
> 버전: v0.6.9
> 참가: 얼박사(부장) + 김대리(Claude)

---

## 요약

Conference 비심방(non-simulcast)에서 비디오가 전혀 노출되지 않는 문제.
근본 원인: `register_nonsim_tracks()`에서 `actual_pt` fallback 누락 → PT normalization 미작동 → publisher PT(109)와 subscribe SDP PT(102) 불일치 → `decoded_delta=0`.

해결 방향: PT normalization 자체를 전면 제거. publisher PT 그대로 릴레이 + subscribe SDP에 publisher 실제 PT 반영.

---

## 근본 원인

### actual_pt fallback 누락 (Phase 19에서 작성한 코드)

```rust
// intent 구성 (68행 — 이미 있던 코드, 정상)
pt: t.pt.unwrap_or_else(|| req.video_pt.unwrap_or(0)),

// register_nonsim_tracks (651행 — Phase 19에서 작성, 버그)
let actual_pt = t.pt.unwrap_or(0);  // fallback 없음 → 0 → normalization 미작동
```

같은 파일, 같은 구조체, 같은 필드. 20줄 위에 있는 패턴을 복사하면 3분컷이었음.

---

## PT 구조 전환 (2026-04-02 확정)

### PT normalization 전면 제거

**Before**: ingress에서 publisher PT → 서버 표준 PT로 변환 + subscribe SDP에 고정 PT
- hidden dependency: 두 곳이 짝이 맞아야 함. 한쪽 빠뜨리면 조용히 실패.

**After**: publisher PT 그대로 릴레이 + subscribe SDP에 publisher 실제 PT 선언
- 변환 레이어 없음 = 깨질 곳 없음. sim/non-sim 공통.

### 전환 근거
- SimulcastRewriter는 SSRC/seq/ts만 건드리고 PT는 안 봄 → simulcast에서도 normalization 불필요
- mediasoup의 PT 리매핑은 router 내부 아키텍처(PipeTransport, cascade) 때문. OxLens에 해당 없음
- BUNDLE PT 충돌(같은 PT 다른 코덱)은 OxLens에서 발생 불가 — m-line별 별도 publisher + SSRC 기반 demux
- publisher마다 PT가 달라도(iOS/Android/Firefox) 각자 m-line에서 독립 선언

---

## 수정 내역

### 서버 (3곳)

**1. ingress.rs — PT normalization 블록 전면 삭제**
- `if room.simulcast_enabled { ... }` 블록 제거 → 주석 4줄로 교체
- sim/non-sim 공통으로 publisher PT 그대로 릴레이

**2. helpers.rs — collect_subscribe_tracks()에 video_pt/rtx_pt/codec 추가**
- ROOM_JOIN 시 기존 트랙에 publisher 실제 PT 정보 포함
- `t.actual_pt > 0`이면 `video_pt`, `t.actual_rtx_pt > 0`이면 `rtx_pt`, `video_codec`은 항상

**3. track_ops.rs — register_nonsim_tracks() 두 가지 수정**
- actual_pt fallback: `t.pt.unwrap_or(0)` → `t.pt.unwrap_or_else(|| req.video_pt.unwrap_or(0))`
- actual_rtx_pt 추가: 이전엔 0 하드코딩
- TRACKS_UPDATE broadcast에 video_pt/rtx_pt/codec 추가

### 클라이언트 (1곳)

**4. sdp-builder.js — buildSubscribeRemoteSdp()에서 publisher PT 반영**
```js
if (kind === 'video' && track.video_pt && track.codec) {
  trackCodecs = trackCodecs.map(c => {
    if (c.name.toUpperCase() === track.codec.toUpperCase()) {
      return { ...c, pt: track.video_pt, rtx_pt: track.rtx_pt ?? c.rtx_pt };
    }
    return c;
  });
}
```

---

## 기각된 접근법 ⭐

### 1. "actual_pt만 고치고 PT normalization 유지" (기각 — hidden dependency)
- 동작은 하지만 ingress normalization + subscribe 고정 PT가 짝이 맞아야 하는 구조 유지
- 부장님 지적: "단순함을 전제로 디버깅 지옥을 경험하는 것"

### 2. "simulcast만 normalization 유지" (기각 — SimulcastRewriter가 PT 안 봄)
- SimulcastRewriter.rewrite()는 buf[2..4](seq), buf[4..8](ts), buf[8..12](SSRC)만 수정
- PT(buf[1])는 건드리지 않음. 다른 단말에서 동일 문제 재발 위험

### 3. "subscribe SDP에 publisher PT + ingress normalization 동시 적용" (첫 번째 삽질)
- subscribe SDP PT=109인데 ingress가 PT=102로 변환 → 반대 방향 불일치
- pt_norm=536 카운터가 증거

---

## SKILL_OXLENS.md 최적화

- 행동 원칙: 3개 (1줄씩, 핵심만). 원칙 1번 "자기 코드 → 선례 → 코딩"으로 개정.
- 아키텍처 원칙: 16개 → 6개 (반복 위험 높은 것만)
- 기각된 접근법: 29개 → 6개 (설계 시 재등장할 것만)
- 구현 완료된 세부 원칙은 코드 주석 + context/design/에만 기록
- ⚠️ SKILL 파일 반영 확인 필요 (실수로 placeholder 덮어씀, 부장님이 수동 복구)

---

## 지침 후보 백로그

다음 승격 심사에서 논의:

1. **조용한 fallback 금지** — `unwrap_or(0)` 같은 silent fallback 대신 agg_log로 즉시 노출. PT=0, is_rtx_pt() 하드코딩 등 3주간 같은 패턴 3회 반복.
2. **분석 우선순위: agg_log → 텔레메트리 → 서버 로그** — agg_log는 스냅샷 첫 화면에 노출. 서버 로그는 묻힘.
3. **불완전 데이터 downstream 전달 금지** — 서버: video 트랙에 PT 없으면 등록 자체 차단 + agg_log. 클라이언트: pushCritical. 사용자: toast 알럿.
4. **is_rtx_pt() 하드코딩 fallback 제거** — intent에 rtx_pt 없으면 버그. 조용히 fallback할 게 아니라 agg_log.

---

## 맥북 검증 상태

- [x] Conference 비심방: 비디오 정상 노출 ✅ (PT normalization 기반, 23:14 테스트)
- [ ] Conference 비심방: PT normalization 전면 제거 후 재검증
- [ ] PTT: 미검증 (audio concealment 100%, ts_gap drift 잔존)
- [ ] Simulcast: PT normalization 제거 후 재검증
- [ ] SESSION_INDEX.md 업데이트

---

## TODO (다음 세션)

- [ ] Conference 비심방 + Simulcast + PTT 3종 검증 (PT normalization 전면 제거 상태)
- [ ] PTT ts_gap drift 디버깅
- [ ] is_rtx_pt() 하드코딩 fallback → agg_log 전환
- [ ] video 트랙 PT 누락 시 agg_log + 등록 차단
- [ ] 불완전 트랙 정보 시 클라이언트 pushCritical + 사용자 toast
- [ ] PIPELINE STATS에 publisher actual video_pt/rtx_pt 추가 (어드민 스냅샷에서 PT 불일치 즉시 확인용)
- [ ] SKILL_OXLENS.md 최적화 버전 반영 확인
- [ ] SESSION_INDEX.md Phase 20 추가

---

*author: kodeholic (powered by Claude)*
