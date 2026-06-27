<!-- author: kodeholic (powered by Claude) -->

# 20260625 — simulcast PUBLISH_TRACKS 응답 track_id 회신 + sentinel placeholder 폐기 (작업 지침)

> **목적**: simulcast 카메라 발행 시 `PUBLISH_TRACKS` 응답에 `track_id`가 안 실려 클라가 `pipe.trackId`를 학습 못 하는 결손(warn `no track_id for mid=3`)을 근본 해소한다. 동시에 그 결손의 원흉인 **물리 placeholder(sim_group sentinel ssrc) 우회 설계를 폐기**하고, vssrc·intent 메타의 보관 권한을 **논리 `PublisherStream`으로 이관**한다.
>
> **한 줄 결론**: simulcast의 `track_id`는 `user_{vssrc}`이고 vssrc는 **논리 stream 소유**다. 그런데 현재는 vssrc를 얻겠다고 **물리 placeholder 트랙**을 sentinel ssrc로 만들고, 그마저 옛 `if t.ssrc==0 { continue }` 가드(2026-04-04)에 막혀 simulcast는 PUBLISH_TRACKS 시점에 아무것도 안 만든다 → 응답 `tracks:[]`. **논리 stream을 PUBLISH_TRACKS에서 직접 만들어 vssrc를 그 자리에서 확정·회신**하면, sentinel 물리 placeholder는 통째로 불필요해진다. RTP-first는 그 논리 stream에 real 물리 트랙을 합류시키는 역할만 남는다.
>
> **선행 조사 사실**: 본 문서 §1~§3. **불변 원칙**: Simulcast SSRC는 SDP에 없다(RTP rid 학습) / 식별 3평면(track_id·vssrc·real ssrc) / 2계층(논리 Stream ⊃ 물리 Track) / half→simulcast 강제 off.

---

## 1. 사실 관계 (코드 실증)

### 1.1 증상
- 웹 클라 simulcast 카메라 발행 → `local-endpoint.js:591` `[LEP] PUBLISH_TRACKS ok: no track_id for mid=3 — trackId not learned`.
- 원인: 서버 `PUBLISH_TRACKS` OK 응답의 `tracks` 배열이 비어서 `_learnTrackId`가 `mid=3` 매칭 실패 → `pipe.trackId = null`.

### 1.2 서버가 응답에 track_id를 안 싣는 경로
`track_ops.rs:142-143`:
```rust
for t in &req.tracks {
    if t.ssrc == 0 { continue; }   // ← simulcast(ssrc=0) 통째 skip
    ...
    resp_tracks.push(json!({ "mid": t.mid, "track_id": resp_track_id }));  // line 231 도달 못 함
}
```
- 웹 클라 enrich(`transport.js:383-390`)는 **simulcast 트랙의 ssrc를 채우지 않는다**(SDP에 없음). 그래서 intent `ssrc=0`으로 도착 → 가드 `continue`.
- non-sim(mic/full camera)은 enrich가 SDP에서 ssrc를 채워 `ssrc!=0` → 가드 통과 → 응답에 track_id 실림. **그래서 non-sim만 정상**.

### 1.3 가드는 placeholder 설계보다 오래된 화석
- `if t.ssrc==0 { continue }` = 2026-04-04(`6746692c`).
- catch2 3-D(2026-05-29)가 "simulcast도 placeholder 사전등록"(`alloc_sim_group` sentinel)을 도입했으나, **옛 가드가 그 앞에서 쳐서 placeholder 분기(`is_placeholder_register`, line 169~)가 simulcast에선 영영 도달 불가**. 절반만 깔린 설계.

### 1.4 봇이 가드를 가짜 ssrc로 우회 → 회귀시험 거짓 양성
`oxe2e bot/mod.rs:492-505` (simulcast인데도 non-zero ssrc 박음):
```rust
//   entry ssrc 는 의미 없음(서버가 sentinel 로 대체)이나
//   t.ssrc==0 가드(track_ops) 통과용 non-zero 필요 — 모든 PUBLISH_TRACKS 트랙 공통 계약.
```
- 봇은 `ssrc_h`(가짜 non-zero)를 보내 가드를 통과 → placeholder 등록 → track_id 회신받음. **oxe2e는 항상 green**.
- 웹 클라만 정직하게 `ssrc=0` → 버그 노출. **테스트가 실제 클라 계약과 불일치**.

### 1.5 simulcast 영상 forward 자체는 동작 (검은 화면 아님)
- `ingress_publish.rs:492` `create_or_update_at_rtp`가 첫 RTP에서 real ssrc로 트랙 등록 + `notify_new_stream`이 **다른 subscriber에게** TRACKS_UPDATE 발송. placeholder 없어도 forward는 됨.
- 손실은 **publisher 본인의 `trackId` 학습**뿐. trackId는 클라에서 오직 `setTrackState`(mute/duplex)에만 쓰임(`local-endpoint.js:622-627`). 따라서 **simulcast 카메라 mute가 서버에 전달 안 됨**(trackId=null → 전송 skip)이 실제 사용자 영향. (duplex 전환은 simulcast에서 어차피 클라 skip §11.)

---

## 2. vssrc·track_id 계보 (현재 as-is, simulcast)

| 시점 | 사건 | 식별자 |
|---|---|---|
| ① SDP 협상 | non-sim ssrc는 SDP에 박힘 / **sim ssrc는 SDP에 없음** | — |
| ② PUBLISH_TRACKS 송신 | intent `{mid:3, ssrc:0, simulcast:true}` | intent ssrc=0 |
| ③ 서버 처리 | `ssrc==0` 가드로 **skip** → 물리·논리·vssrc·track_id **전부 미생성** → 응답 `tracks:[]` | (없음) |
| ④ 클라 setTrack | RTP 송출 개시 (OK 받은 뒤 `holdRtp` 해제) | — |
| ⑤ 첫 RTP 도착 | `create_or_update_at_rtp`→`attach_track_to_stream`→`PublisherStream::new` | **vssrc=rand 생성, track_id=user_{vssrc} 생성** |
| ⑤ notify | `subscriber_ssrc = simulcast_video_ssrc() = vssrc` → TRACKS_UPDATE를 **다른 sub에게만**(본인 제외) | egress=vssrc |

**핵심**: vssrc는 `PublisherStream::new`(`publisher_stream.rs:75`, `attach_track_to_stream`에서 호출) 시 1회 생성. 현재 simulcast는 그게 **⑤ RTP-first**에서야 일어나 응답 타이밍(③)을 놓침.

### 2.1 intent-first는 모든 클라 규격 (fallback 명분 폐기)
- 웹 클라: `_publishTracks`가 ①stage(holdRtp=RTP 차단) → ②PUBLISH_TRACKS await OK → ③setTrack(RTP 개시) 직렬. **OK 전 RTP 불가**.
- 봇: `mod.rs:175` PUBLISH_TRACKS 먼저 → 이후 RTP task.
- **부장님 지침: 이 순서로 안 보내면 규격 위배.** 따라서 "intent 없이 RTP 먼저" 시나리오는 없다 → **RTP-first의 vssrc 신규 생성 분기는 과감히 걷어낸다**(죽은 길).

---

## 3. 메타 보관 역할 — 실제 소비됨 (sentinel 통째 폐기 불가, 이관 필수)

`ingress_publish.rs:420-442` (RTP-first가 메타를 어디서 얻나):
```rust
let tracks_for_meta = peer.publish.tracks.load();   // ← 기존 물리 트랙 = placeholder
let vs = mid 매칭 or 같은 source 첫 video 트랙;
(
    parsed_rid,                                  // RTP extension 자급
    vs.map(|v| v.video_codec),                   // ← placeholder 조회
    vs.map(|v| v.source),                        // ← placeholder 조회
    vs.map(|v| v.actual_rtx_pt).unwrap_or(0),    // ← placeholder 조회
    vs.map(|v| v.simulcast).unwrap_or(false),    // ← placeholder 조회 ★
)
```
- `actual_pt`만 `rtp_hdr.pt`로 자급(line 456). **codec / rtx_pt / source / simulcast 판정은 placeholder에서 읽는다**.
- 특히 `is_sim_source = vs.simulcast`. **placeholder가 없으면 simulcast 여부조차 false로 오판** → real 트랙이 non-sim으로 등록됨(현 웹 클라 simulcast가 서버에서 simulcast로 안 잡힐 위험의 출처).

→ **결론**: 물리 placeholder를 없애려면 그 메타(codec·rtx_pt·source·simulcast·mid·duplex)를 **논리 `PublisherStream`이 보관**하고, ingress의 메타 조회를 **물리 인덱스(`publish.tracks`) → 논리 인덱스(`publish.streams`)로 교체**해야 한다. 이게 작업의 척추.

---

## 4. 설계 결정

**D1. vssrc·intent 메타의 단일 보관처 = 논리 `PublisherStream`.**
- simulcast: PUBLISH_TRACKS에서 **물리 트랙 없이 논리 stream을 직접 생성** → vssrc eager 발급 → `track_id=user_{vssrc}`를 응답에 회신. 메타(codec/rtx_pt/source/simulcast/mid/duplex)를 stream에 박는다.
- RTP-first: real 물리 트랙을 **기존 논리 stream에 attach**(`(kind,source)` 매칭) → vssrc/track_id 유지. 새 stream 생성·새 vssrc 발급 안 함.

**D2. sentinel/placeholder 물리 트랙 폐기.** `alloc_sim_group`·`sim_group_counter`·`is_placeholder`(0xF000_0000)·placeholder 제거 루프 전부 제거.

**D3. RTP-first vssrc 신규 발급 fallback 폐기.** intent-first 규격이므로 논리 stream은 RTP 도착 전 항상 존재. `attach_track_to_stream`이 "기존 stream 없음" 분기로 simulcast를 만나면 = 규격 위배 → 에러 로그(조용한 새 vssrc 발급 금지).

**D4. 봇 정직화.** `oxe2e bot` simulcast entry `ssrc: 0`. 가드 제거 후 웹 클라와 동일 계약.

---

## 5. 작업 항목 (순서 = 안전 순)

> 각 단계는 빌드 통과 + 기존 테스트 green 유지 가능한 최소 단위. 한 번에 한 묶음.

### S1. `publisher_stream.rs` — 논리 stream에 intent 메타 필드 + 빈 stream 생성 경로
- 필드 추가: `video_codec`, `actual_pt`, `actual_rtx_pt`, `mid`(ArcSwap), `duplex`. (simulcast 여부는 `vssrc!=0`로 이미 표현 가능하나, non-sim/half 구분 위해 명시 플래그 또는 duplex 보관.)
- 물리 트랙 없이 생성하는 생성자/헬퍼: `PublisherStream::new`는 이미 `first_track_ssrc`로 track_id 생성 가능(simulcast면 vssrc 기반이라 ssrc 무관). **빈 `tracks` Vec 상태가 유효함을 보장**(순회처 점검 → S6 리스크).

### S2. `peer.rs` — 논리 stream 단독 등록 + 메타 조회 헬퍼
- `ensure_publish_stream(source, kind, simulcast, 메타...)`: `(kind,source)` 기존 stream 있으면 메타 갱신, 없으면 빈 stream 생성·등록. PUBLISH_TRACKS에서 호출.
- `find_stream_for_meta(mid, kind)`: ingress 메타 조회용(현 `tracks_for_meta` 로직을 논리 stream 기준으로 이식 — mid 매칭 → 같은 source 첫 video 폴백).
- 제거: `alloc_sim_group`, `sim_group_counter`.

### S3. `track_ops.rs` `do_publish_tracks` — 가드 교체 + 분기 정리
- `if t.ssrc==0 { continue }` → **`if t.ssrc==0 && !is_sim { continue }`** (non-sim ssrc=0=파싱 실패는 기존대로 skip 보존; sim은 통과). `is_sim`은 `track_type==FullSim` 권위 사용.
- simulcast(FullSim): `ensure_publish_stream`(논리 stream + vssrc + 메타) → `resp_tracks.push({mid, track_id=stream.track_id()})`. **물리 트랙 add_publisher_track 호출 안 함**.
- non-sim(FullNonSim/HalfNonSim): 기존대로 `add_publisher_track`(real ssrc) + 논리 stream + resp_tracks. (메타도 stream에 동기화 — ingress 조회 통일 위해.)
- 제거: `is_placeholder_register`, `register_ssrc=alloc_sim_group`, `register_simulcast`.

### S4. `ingress_publish.rs` — 메타 조회 물리→논리 + placeholder 루프 제거 + attach 유지
- `tracks_for_meta = peer.publish.tracks.load()` → `peer.find_stream_for_meta(...)`(논리). codec/rtx_pt/source/simulcast/duplex를 **논리 stream에서** 읽는다.
- placeholder 제거 루프(`479-490`) 삭제.
- `create_or_update_at_rtp`로 real 물리 트랙 생성 → `attach_track_to_stream`이 **기존 논리 stream에 합류**(vssrc 유지). 기존 stream 없으면(simulcast인데) 규격위배 로그(D3).
- `actual_pt`는 `rtp_hdr.pt` 자급 유지.

### S5. `publisher_track.rs` / `admin.rs` — sentinel 잔재 제거
- `publisher_track.rs:546` `is_placeholder` 제거.
- `admin.rs:99` `"is_placeholder"` 출력 제거.
- `ingress_publish.rs:482` placeholder 필터 제거(S4에 흡수).

### S6. `oxe2e bot/mod.rs` — simulcast 정직화
- `492-505` simulcast entry `ssrc: ssrc_h` → `ssrc: 0`. 주석 갱신(가드 폐기, 논리 stream 직생성 계약).
- RtpSender(ssrc_h/ssrc_l)는 그대로(실제 RTP 송출 ssrc). entry ssrc만 0.

### S7. 회귀시험
- simulcast 시나리오: 응답 track_id 회신 확인 + forward 정상.
- conference(full non-sim) / PTT(half) 시나리오: 무영향 확인.
- 봇 ssrc=0 변경이 non-sim/audio 경로 안 건드리는지(가드 `!is_sim` 분기) 확인.

---

## 6. 기존 기능 보존 체크리스트 (회귀 금지)

- [ ] **non-sim full camera / mic**: enrich가 ssrc 채움 → `ssrc!=0` → 가드 `!is_sim` 무관하게 통과. 응답 track_id 기존대로. **변화 0**.
- [ ] **SDP 파싱 실패 non-sim(ssrc=0)**: `ssrc==0 && !is_sim` → 여전히 skip. 기존 보호 유지.
- [ ] **PTT half-duplex**: simulcast 강제 off → FullSim 아님 → 논리-only 경로 안 탐. 슬롯/virtual_ssrc 경로 무변경.
- [ ] **republish**: unpublish가 논리 stream 폐기 → republish가 PUBLISH_TRACKS에서 새 논리 stream(새 vssrc). 클라도 새 trackKey/trackId 재발급(설계 §4.3). 일관.
- [ ] **subscriber egress_ssrc 단일화**(`e94339e`): producer-push 갱신 경로가 논리 stream vssrc를 본다 — vssrc 이관 후에도 동일 동작 확인.
- [ ] **clear_speaker 멱등 / silence flush**: 무관(half 경로).

---

## 7. 기존 구조 보존 (불변 원칙 정합)

- **식별 3평면 유지**: track_id(불투명, 논리 stream 소유) / vssrc(값) / real ssrc(물리). 본 작업은 vssrc 발급을 **정상 위치(PUBLISH_TRACKS)로 당길 뿐** 평면 구조 불변.
- **2계층(논리 ⊃ 물리) 강화**: 메타 home이 논리 stream으로 모임 = 본래 설계 의도에 더 부합(물리 placeholder는 우회였음).
- **PT 동적 판별 유지**: codec/pt는 intent·RTP에서 오고 하드코딩 없음.
- **Simulcast SSRC는 SDP에 없다**: 그대로. real ssrc는 RTP rid로만 학습. vssrc는 서버 발급(egress).
- **track_id 역추출 금지**: 키 조회만. 본 작업 신규 헬퍼도 선형 조회(파싱 없음).

---

## 8. 리스크 / 주의점

1. **빈 논리 stream 순회 가정**: PUBLISH_TRACKS~첫 RTP 사이 stream.tracks가 비어 있음. `tracks_load().iter()` 순회처(pli_state, mute_stream, snapshot, fan-out)가 빈 Vec에 안전한지 점검. mute_stream은 빈 stream이면 no-op이어야.
2. **detach 빈 stream 폐기와의 상호작용**(`peer.rs:750` remaining==0 폐기): 빈 논리 stream을 만든 직후 어떤 경로가 detach를 호출하면 안 됨. detach는 물리 트랙 제거 시만 호출되므로, 물리 트랙이 아직 없는 빈 stream은 detach 대상이 아님 → 안전(확인).
3. **ingress 메타 조회 mid 매칭 보존**: 현 `tracks_for_meta`의 "mid 매칭 → 같은 source 첫 video 폴백" 2단 로직을 논리 stream 조회로 **그대로** 이식. h/l 두 물리 트랙이 한 논리 stream 공유하므로 stream 단위 조회로 충분.
4. **non-sim ssrc==0 가드 대체 위치**: `is_sim` 판정(`track_type` 파생)이 가드 시점에 계산 가능해야. duplex/sim은 ssrc 비의존이므로 가드를 그 계산 뒤로 내리거나 inline 판정.
5. **`simulcast_video_ssrc = first_stream_of_kind(Video)`**: camera+screen 동시 simulcast 시 "첫 video stream" 단수 가정이 깨짐(별 source인데 vssrc 하나로 오선택 위험). 이번 시험은 camera 단일이라 안 드러나나, **논리 stream을 source별로 만드는 본 작업에서 source 정합 조회로 함께 정리** 권장(notify의 subscriber_ssrc를 해당 source stream의 vssrc로). → **D6 반영 완료**.

6. **★ placeholder 물리 트랙의 2번째 역할 — `resolve_stream_kind` mid 분류 (회귀시험이 잡음)**:
   placeholder 물리 트랙은 ingress 에서 ①메타 조회(codec/rtx_pt/duplex) ②`resolve_stream_kind` 의 **mid→video 분류** 두 역할을 겸했다. S4 는 ①만 이관 → 첫 회귀(simulcast_basic)에서 video RTP 가 `[STREAM] NEW unknown (will resolve on next intent)` 로 **분류 실패·미등록** → `video add 약속 미수신` FAIL.
   수정: `resolve_stream_kind`(ingress_publish.rs:369 뒤)에 **논리 stream mid 폴백** 추가 — 물리 mid 매칭 실패 시 논리 Stream 의 메타 mid 로 `Video/FullSim` 분류. 재시험 PASS.
   **교훈**: 물리 placeholder 폐기 시 그것이 겸하던 **모든** 역할(메타 home + resolve 분류 자료원)을 빠짐없이 논리 Stream 으로 이관해야 한다. 단위테스트는 못 잡고 회귀(oxe2e)가 잡았다.

## 11. 회귀시험 결과 (20260625, 커밋 전)

| 시나리오 | 결과 | 비고 |
|---|---|---|
| simulcast_basic | ✓ PASS | 약속 2건(audio+video) 수신 2종/744패킷 — video add 통지 + vssrc forward 정상 |
| conf_basic | ✓ PASS | full conference 무영향 |
| ptt_rapid | ✓ PASS | half-duplex floor 라우팅 + gating + oxcccd 교차확인 무영향 |

- 단위테스트: oxsfud 211 PASS / 빌드 경고 0.
- 봇은 `ssrc=0` 정직 계약(debug 바이너리) — 새 서버 가드와 짝. 옛 서버엔 못 돌린다(가드 막힘).

---

## 9. 결정 사항 (정석 확정 20260625)

- **D5 (구 Q1) — 메타 조회 통일.** non-sim도 메타를 논리 stream에 동기화하고 ingress 조회를 `publish.streams` 단일 경로로 통일. 이원 분기 안 남긴다(S3에서 non-sim도 stream 메타 동기화).
- **D6 (구 Q2) — source 정합 포함.** §8-5 `first_stream_of_kind(Video)` source 오선택을, 논리 stream을 source별로 만드는 김에 **이번 작업에 포함**해 정리한다. notify의 `subscriber_ssrc`를 해당 source stream의 vssrc로.
- **D7 (구 Q3) — 클라 변경 없음.** track_id가 응답으로 학습되면 클라 `setTrackState`가 기존 경로 그대로 mute를 송신(현재 trackId=null이라 skip됐을 뿐). 별도 클라 작업 불필요 — 서버 응답 회신만 고치면 simulcast 카메라 mute가 자동 복원.

---

## 10. 한 줄 요약

> vssrc·메타의 집을 **물리 placeholder → 논리 PublisherStream**으로 옮긴다. 그러면 PUBLISH_TRACKS가 vssrc를 그 자리에서 확정해 응답으로 회신하고, sentinel/placeholder/RTP-first 신규발급 fallback이 통째로 사라진다. 봇의 가짜 ssrc 우회도 제거되어 회귀시험이 실제 클라 계약과 일치한다.
