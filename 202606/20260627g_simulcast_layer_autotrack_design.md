<!-- author: kodeholic (powered by Claude) -->

# 20260627g — simulcast layer: 기아(실측) 우선 강등 + 의도 게이트 회복 (설계 rev2, 검사 대기)

> **목적**: 발신 BWE로 요청 layer(h)가 기아일 때, 서버가 **실측 기아 우선으로 도착 layer(l)로 강등**해 forward 하고, **회복은 사용자 의도(target_pref=h)일 때만**, **전환은 기존 `TRACK_STATE` op로 통보**, **oxadmin 으로 가시화**한다.
>
> **한 줄 결론**: layer 결정 권위는 **클라(SUBSCRIBE_LAYER=target_pref) 유지**. 그 위에 서버가 **추정이 아닌 실측(last_rtp 무도착=기아)** 기준으로만 개입한다 — 기아면 의도보다 우선해 강등, 회복은 의도가 h일 때만. forwarder·SUBSCRIBE_LAYER·방향역전·TRACK_STATE op 전부 보존, 추가만.
>
> **rev1 폐기**: 초안의 "서버 자동 layer 추종"은 2026-06-21 PLI Governor 가 **추정 기반 자동조정**으로 명시 폐기한 것의 부활이라 철회. rev2 는 **실측 기반 + 의도 게이트**로 그 폐기와 양립.
> **책임 분리(부장님)**: h 띄엄띄엄 = 클라(발신 BWE, 서버 불가항) / **l forward 못 함 = 서버**(본 설계).

---

## 1. 근거 — 패킷 확정 (sim03, 검정)

```
in  0x6F3C6DC4 (U02 l)  32225   ← l 풍부 도착
in  0x1B1A1490 (U02 h)    242   ← h 기아 (클라 BWE)
eg  0x096FD603 (→U01)     242   ← h(242)만 forward, l 32225 전부 drop
oxadmin U01: video RECEIVED +0 STALL / audio +150 정상
```
서버가 **안 오는 h 에 고정**돼 **오는 l 을 버린다** → 검정. (audio 정상 = simulcast forward 특정.)

## 2. 기존 구조 — 보존해야 할 것 (역사)

- **layer 권위 = 클라.** 웹 SDK `remote-stream.js`: Phase C 수동(setQuality) + Phase D adaptive(가시성/크기) → `SUBSCRIBE_LAYER`. 서버가 layer 를 *결정* 하지 않는다.
- **`forwarder = {current, target, rewriter}`**(설계서 0528) — 자료 그대로.
- **PLI Governor(2026-06-21)**: "**추정** 기반 자동조정 폐기 — 추정이 틀려 freeze. 레이어는 수동 SUBSCRIBE_LAYER 만." → **추정 금지**가 핵심 교훈.
- **`TRACK_STATE`(0x2102)**: 이미 이벤트 통보 op — `{active, source, duplex, muted}`, per-sub unicast 가능(`track_ops:346`).

## 3. ★ 6/21 폐기와 양립하는 이유 (어색 제거의 열쇠)

6/21 이 폐기한 것 = **추정**("최근 keyframe relay됨/PLI pending" 같은 간접 추정 → 오판 freeze).
본 설계의 강등 트리거 = **기아 실측**(`last_rtp` 무도착 — 직접 사실, 추정 0).
→ **추정을 안 쓰므로 6/21 정신(추정 제거)과 같은 철학.** 자동조정의 *부활* 이 아니라, *실측 사실에 대한 반응*이다. (rev1 은 이 구분 없이 "자동 추종"이라 뭉개 어색했다.)

## 4. 설계 (rev2)

### 자료 — forwarder 의미 정제 (필드 추가 최소)
- **`target_pref`** = 사용자 의도(클라 SUBSCRIBE_LAYER). **클라 권위, 유지.** (기존 `target` 을 "의도" 로 명명 정리.)
- **`current`** = 실제 송출 layer. (기존)
- publisher 물리 Track 에 **`last_rtp_ms`**(AtomicU64) — ingress 매 RTP 1 store(실측).

### D1. 기아 판정 (실측만)
`now - last_rtp_ms(layer) > STARVE_MS`(예: 300ms) = 그 layer 기아. 추정 없음.

### D2. 우선순위 정책 (부장님)
- **강등 (기아 > 의도)**: `current==target_pref` 인데 그 layer 기아 + 다른 layer live → `current := 도착 layer`. **의도(h) 무시하고 강등.** 도착 layer keyframe 필요 → D3.
- **회복 (의도 게이트)**: `target_pref==h` **그리고** h 가 UPSCALE_HOLD 동안 안정 도착 → `current := h`. **target_pref==l 이면 h 살아나도 회복 안 함.**
- **진동 방지**: 강등 빠르게(STARVE_MS), 회복 보수적(UPSCALE_HOLD, 예 2~3s). h 띄엄띄엄이면 회복 안 함 → l 고정.
- **평가 위치**: 주기 태스크(`tasks.rs` 합류 — hot-path 오염 0). PLI Governor 와 별개(거긴 throttle 전담, 여긴 layer 결정).

### D3. PLI 대상 교정 (이행 버그)
`track_ops:1083` 의 `rid=="h"` 고정 → **전환하려는 layer 의 ssrc**로 PLI. (강등 시 l keyframe, 회복 시 h keyframe 유도. switch 분기2 가 keyframe 필요하므로 짝.)

### D4. 통보 — 기존 TRACK_STATE 재사용
`current` 변경 시 그 subscriber 에게 **`TRACK_STATE`(0x2102) + `layer` 필드** 추가:
`{track_id, layer: "h"|"l", reason: "starve"|"recover"}`. **새 op 없음.** per-sub unicast(기존 경로). 클라는 UI/통계 반영(영상은 vssrc 동일이라 자동).

### D5. oxadmin 가시성
- `oxadmin user`: SUBSCRIBE 에 `simulcast=Y/N`, `current=h|l|pause`, `target_pref=...` 병합(서버 forwarder snapshot).
- `oxadmin room`: publisher layer liveness(h/l last_rtp, 기아 여부) — **발신(클라) vs 서버 문제 즉시 판별.**

### D6. attach 상속 (take-over/republish 빈틈)
`attach_track_to_stream` 에서 새 물리 layer 합류 시 **기존 subscriber 를 새 Track 에 상속**. (검정의 take-over 후 l 나중 도착분 attach 누락 보강. 내 attach 수정의 짝.)

---

## 5. 동작 (검정 → 복원)

```
target_pref=h, h 기아(242)/l 풍부(32225)
 → 주기태스크: last_rtp(h) > 300ms = 기아 실측
 → [강등: 기아>의도] current:=l, l ssrc PLI → l keyframe → switch → l forward
 → TRACK_STATE{layer:l, reason:starve} 통보 (U01)
 → U01 영상 복원(l, 끊김 없음)
 → h 회복 + 2~3s 안정 + target_pref==h → [회복: 의도게이트] current:=h, h PLI → switch
 → TRACK_STATE{layer:h, reason:recover}
 (target_pref==l 이면 h 살아나도 l 유지)
```

## 6. 원자 사실 5검증

1. **추정 안 쓰나?** 트리거 = last_rtp 실측만. 6/21 양립. ✓
2. **기아 우선?** 강등은 target_pref(의도) 무시하고 도착 layer. ✓
3. **회복 게이트?** target_pref==h 일 때만 h 복귀. l 의도면 유지. ✓
4. **통보 op 정합?** 기존 TRACK_STATE(이벤트 통보) + layer 필드, per-sub. 새 op 0. ✓
5. **switch 발동?** current:=target 후 그 layer PLI(D3) → keyframe → 기존 분기2. attach(D6) 전제. ✓

## 7. 영향 / 기존 구조 보존

**불변**: forwarder 분기(forward) / SUBSCRIBE_LAYER(=target_pref, 클라 권위) / 방향역전 물리 subscribers / vssrc 1개 통지 / 2계층 / PLI Governor throttle / TRACK_STATE op.
**추가만**: ① last_rtp_ms ② 주기 layer 평가(기아우선/의도게이트) ③ PLI 대상 교정 ④ TRACK_STATE layer 필드 ⑤ oxadmin forwarder/liveness ⑥ attach 상속.
**회귀 안전**: non-sim(forwarder=None) 무관. h 충분 시 기존 동일(current=target_pref=h).

## 8. 미결 / 검사 포인트

- **Q1 (wire 소비자)**: TRACK_STATE 에 `layer` 추가 → 웹 SDK 수신 핸들러 + 봇/Android 영향 전수. [[feedback_wire_contract_consumers]] 클라는 무시해도 안전(옵셔널 필드)인지 확인.
- **Q2 (임계값)**: STARVE_MS / UPSCALE_HOLD 초기값 — 실측 튜닝.
- **Q3 (last_rtp 재사용)**: rr_stats/sr_stats 에 유사 시각 있으면 신설 대신 재사용.

## 9. 검증 계획

- **2층(oxe2epy)**: 봇 pub h 송신 중단(l 만) → sub 가 vssrc 로 l 계속 수신(강등) + `TRACK_STATE{layer:l}` 수신 등식(`simulcast_downscale`). h 재개+target_pref=h → 회복 등식. failability: 본 설계 전 FAIL/후 PASS.
- **3층(최종)**: U02 대역 제한에서 U01 이 l 화질로 끊김 없이 + 클라 layer 통보 수신 + oxadmin 으로 current/simul 확인.
