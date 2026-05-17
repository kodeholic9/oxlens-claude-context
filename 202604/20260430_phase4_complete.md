# 2026-04-30 — Phase 4 (Track Lifecycle ingress 분기 제거 + publisher_stream.fanout / sub_stream.forward) **완료**

## 위치
**Phase 81 (= 설계서 §6 Phase 4) Step A + Step B 완료. cargo build PASS warning 0 + cargo test 244 PASS (회귀 0).**

설계서: `context/design/20260427_track_lifecycle_redesign.md` (rev.3) §1.1 §4.3 §6 Phase 4

설계서 §1.1 의 본질 문제 — `ingress::handle_srtp` 의 `match track_type {Pending/HalfNonSim/FullSim/FullNonSim}` 본문 분기 — 가 제거되어 P-3 ("enum match 본문 분기 금지, 객체 메서드") 원칙 정합. 이번 Phase 가 설계서 §1.1 의 핵심 가치 ("10년 결정") 의 본문 적용 단계.

---

## 결재 사항 (부장님 OK)

세션 시작 시 옵션 5건 묶음 결재 + GO:

1. **P-1**: `PublisherStream::fanout` + `SubscriberStream::forward` 두 메서드 분리. forward 안에서 publisher_ref Direct/ViaSlot 자료구조 분기.
2. **S-1**: forward 안 simulcast layer 매칭 (sub 마다 다른 SimulcastRewriter — 기존 fanout_simulcast_video 동등 의미).
3. **W-1**: PublisherStream::fanout 진입 직후 Half-duplex non-sim 인 경우 `Slot.rewriter.rewrite` 1회 (방마다). ⭐ 설계서 §4.3 의사코드 누락 보강 — PttRewriter 카운터 단일성 보존 + 부록 E.1 자산 8건 보존.
4. **Q-2**: Step A (publisher_stream.fanout 골격 + ingress 호출처 단일화) → build/test PASS → Step B (forward 본문 + 3 함수 제거). 핫패스라 분리.
5. **T-1**: TrackType enum 보존 (`[STREAM:REG]` / `[STREAM:NOTIFY]` / `notify_new_stream` 진단 라벨용, 본문 분기에서만 제거).

---

## Step A 완료 (build PASS, test 244 PASS)

±30L, 1 commit:

- `transport/udp/ingress.rs`:
  - `handle_srtp` 의 `match track_type {...}` 본문 분기 (-22L) → `stream.fanout(self, &plaintext, &rtp_hdr, &sender, stream_kind, is_detail).await` 단일 호출로 교체
  - `fanout_half_duplex` / `fanout_full_nonsim` / `fanout_simulcast_video` 3 메서드 visibility `async fn` → `pub(crate) async fn` 격상 (publisher_stream.rs 에서 위임 호출용)
- `room/publisher_stream.rs`:
  - `pub(crate) async fn fanout(...)` 추가 (+52L). 본문: 방 순회 + transport.fanout_*3 위임. 분기는 임시 `self.track_type()` (Step B 에서 자료구조 분기로 정리)
- ingress.rs 의 fanout 호출 직전 `Arc::clone` 패턴 — Guard 즉시 drop, await 너머 stream lifetime 안전.

### 빌드 + 테스트 결과 (Step A)
- `cargo build --release` 14.37초 PASS warning 0
- `cargo test`: oxsfud 244 / 전체 255 passed / 0 failed / 0 ignored

---

## Step B 완료 — wave-1∼3

±300L (자산 보존 + 자료구조 분기). **build PASS warning 0 + cargo test 244 PASS (warning 1건 사후 수정 후 0).**

### wave-1 ✅ publisher_stream.rs (fanout 본문 재작성 + W-1 헬퍼 추가)

`room/publisher_stream.rs`:
- `pub(crate) async fn fanout(...)` 본문 재작성 (-30L 임시 본문 + +90L 새 본문):
  - `is_half = self.duplex_load() == Half && !self.simulcast`
  - `is_simulcast_video = self.simulcast && self.kind == Video`
  - 방 순회 (sender.peer.pub_rooms.load() iter)
  - **W-1**: `is_half` 면 `self.prefan_out_via_slot(...)` 호출 → 결과 (Some/None) 저장. None 시 방 skip.
  - Video keyframe 검사 → publisher pli_state.on_keyframe_received (gov_layer = simulcast 면 from_rid, non-sim 면 High)
  - sub 순회 (transport.endpoint_map.subscribers_snapshot) → 각 sub 마다 vssrc 매칭으로 SubscriberStream lookup → `sub_stream.forward(...)` 호출 → 반환 `need_pli` 누적
  - simulcast PLI burst (방마다 1회, `pli_sent` 플래그) — 기존 fanout_simulcast_video 의 PLI 발사 그대로
- `fn prefan_out_via_slot(...) -> Option<Vec<u8>>` 헬퍼 추가 (+60L):
  - floor 검사 (current_speaker == sender 만 통과, 거부 시 metrics.ptt.rtp_gated)
  - Slot.rewriter.rewrite 1회 (Audio: silence flush 3프레임 / Video: keyframe 대기 + ts_guard_gap)
  - RewriteResult 분기 (Ok / PendingKeyframe / Skip) — metrics 보존 (audio_rewritten/video_rewritten/video_pending_drop/video_skip/keyframe_arrived)

### wave-2 ✅ subscriber_stream.rs (forward 메서드 추가)

`room/subscriber_stream.rs`:
- `pub(crate) fn forward(self: &Arc<Self>, publisher: &PublisherStream, target, room, plaintext, prefan_payload, rtp_hdr, is_keyframe, sender_user_id) -> bool` 추가 (+165L)

분기 (P-3 자료구조 정합):
1. **publisher_ref 자료구조 분기**: `is_via_slot = matches!(self.publisher_ref.load().as_ref(), PublisherRef::ViaSlot(_))`. ViaSlot 면 `prefan_payload` 사용 (None 시 false 반환), Direct 면 `plaintext` 사용.
2. **gate 검사** (Direct + Video 만 — Half 는 publisher 사이드 floor 가 책임).
3. **RoomScopedStats lazy create** (Entry::Occupied/Vacant). simulcast Video 는 `new_simulcast`, 그 외 `new_nonsim`. `created` 플래그 받음.
4. **simulcast layer 매칭** (S-1, layer_entry::Some 일 때만): pause / target_rid switch (keyframe 대기) / current_layer rewrite. SimulcastRewriter::rewrite + `needs_pli_retry` 검사 → `need_pli = created || retry_pli`.
5. **non-simulcast (layer_entry::None)**: ViaSlot Video 면 PT rewrite (target.expected_video_pt 기반 marker 보존), 아니면 그대로.
6. **egress_tx.try_send** + 통계 (egress_drop / egress_rtp / agg_logger egress_queue_full).
7. simulcast keyframe relayed → scoped.layer_entry 의 pli_state.on_keyframe_relayed.

### wave-3 ✅ ingress.rs (fanout_*3 함수 제거)

`transport/udp/ingress.rs` (-340L):
- `fanout_half_duplex` 본문 (~110L) 통째 제거 — 동등 처리 publisher_stream.rs::prefan_out_via_slot + subscriber_stream.rs::forward (PT rewrite 분기) 로 이주
- `fanout_full_nonsim` 본문 (~50L) 통째 제거 — 동등 처리 forward 의 Direct + non-sim 분기
- `fanout_simulcast_video` 본문 (~110L) 통째 제거 — 동등 처리 forward 의 layer_entry::Some 분기 + publisher_stream.fanout 의 PLI burst

### 빌드 + 테스트 결과 (Step B 1차)
- `cargo build --release` 14.15초 PASS — **warning 1건 발생** (`Layer` import unused at ingress.rs:11)
- `cargo test` 244 passed / 0 failed

### 사후 수정 (warning 0)
- `use crate::room::pli_governor::{self, Layer};` → `use crate::room::pli_governor;` (Layer 직접 사용 0, handle_srtp 의 RTP_GAP 부분은 `pli_governor::Layer::High` qualified 라 영향 없음)
- 부장님 build/test 재의뢰 → warning 0 + 244 PASS 확정.

---

## 부록 E.1 자산 보존 검증 (사후)

설계서 §부록 E.1 의 8건 자산 — Phase 1 PttRewriter 이주 시 보존 의무 — 가 Phase 4 의 publisher 사이드 prefan-out 이주 후에도 그대로:

| 자산 | 위치 | 보존 |
|------|------|------|
| `last_relay_at: Option<Instant>` | Slot.rewriter (PttRewriter 코드 자체) | ✅ (PttRewriter 호출 그대로) |
| arrival-time 기반 `virtual_base_ts` | 동상 | ✅ |
| Audio `ts_guard_gap=960` | 동상 | ✅ |
| Video `ts_guard_gap=3000` | 동상 | ✅ |
| Opus silence flush 3프레임 | Slot.release() (Phase 1 에서 활성화) | ✅ |
| `clear_speaker()` 멱등성 | Slot.release() | ✅ |
| `pending_keyframe` (video 키프레임 대기) | prefan_out_via_slot 의 RewriteResult::PendingKeyframe 분기 | ✅ |
| Video pending_compensation | PttRewriter 코드 자체 | ✅ |

⭐ 설계서 §4.3 의사코드는 prefan-out step 누락. W-1 보강 없이 직역하면 PttRewriter 의 ts_offset/seq_offset 카운터가 sub 마다 호출되어 N배 증가 → arrival-time drift 누적 재발 위험. 부장님 결재 시 W-1 옵션 김대리 추천 → 본 phase 작업 후 설계서 §4.3 보강 commit 별도 검토 의뢰 (부장님 결정).

---

## 김대리 자체 판단 사후 보고 6건

1. **Arc::clone 패턴** (Step A): ingress 의 fanout 호출 직전 Guard 즉시 drop, await 너머 stream lifetime 안전. dryRun 단계에서 검토 후 보강.
2. **is_keyframe fanout 사이드 1회 계산** (Step B wave-1): 방마다 keyframe 1회 검사, sub 마다 재계산 회피. forward 인자로 전달.
3. **forward sync** (Step B wave-2): egress_tx try_send / lock 만 동기 호출. fanout 만 async 유지, sub_stream 별 await 없음 — 핫패스 latency 최소화.
4. **is_detail 인자 fanout 시그니처 보존** (Step B wave-1): 현재 본문 미사용이지만 시그니처 유지 (Step C 적 확장용 placeholder, `let _ = is_detail` 로 dead 표시).
5. **3 함수 한 매칭 제거** (Step B wave-3): 함수별 3건 edit 대신 한 oldText (시작 = `fanout_half_duplex` 시그니처, 끝 = `fn resolve_stream_kind(` 직전) 으로 통째 매칭. 한국어 byte-level 매칭 정상 동작.
6. **warning 1건 사후 수정** (Step B 후): Phase 76 메타학습 ("warning 도 회귀 기준") 정합 — 부장님 build 의뢰 = 누락 검증 메커니즘. 즉시 수정 후 재의뢰.

---

## 기각된 옵션

| 옵션 | 기각 사유 |
|------|-----------|
| **P-2** (sub_stream.forward 안 만들기, fanout 단일 메서드) | 함수 비대 +250L, sub-side 분기 다 fanout 안에 |
| **P-3** (Slot::fanout / PublisherStream::fanout 진입점 둘) | 호출자 (handle_srtp) 가 분기 — P-3 원칙 우회 |
| **S-2** (publisher 사이드 RID 별 1회 처리) | Phase F Forwarder 일반화 영역, 본 phase 영역 밖 |
| **W-2** (sub_stream.forward 안에서 ViaSlot 검출 시 rewrite) | sub 마다 호출 → ts_offset/seq_offset 카운터 N배 증가 |
| **Q-1** (한방 1 commit) | 핫패스 변경이라 회귀 분기점 분리 — Q-2 가 안전 |
| **T-2** (TrackType enum 완전 제거) | 설계서 §6 Phase 4 위반 — admin/agg-log 라벨로 보존 의무 |
| 의사코드 §4.3 직역 (publisher_ref Arc::ptr_eq 검증 추가) | over-engineering — vssrc 매칭으로 충분, S-1 lazy upgrade None 으로 안전성 보장 |

---

## 메타학습

- ⭐⭐⭐ **설계서 §4.3 의사코드 한계 사전 발견 (W-1 prefan_out 누락)** — 옵션 묶기 단계에서 포착. Phase 80 의 "옵션 던지기 = 분석 부족" 의 반대 방향 (옵션 묶기 + 추천 + 김대리 의문 1건). 부장님 결재 시간 절약. 본 phase 의 가장 중요한 메타학습.
- ⭐⭐ **Step A/B 분리 (Q-2) 유효** — Step A 의 호출처 단일화 검증 후 Step B 의 본문 마이그. 회귀 분기점 분리. 한방 패턴 (Phase 80) 도 작동했으나 핫패스 변경은 분리가 안전.
- ⭐⭐ **warning 1건 = 함수 제거의 자연스러운 후폭풍** — Phase 76 메타학습 ("warning 도 회귀 기준") 정합. 부장님 build 의뢰 = 누락 검증 메커니즘 정상 작동.
- ⭐⭐ **3 함수 한 매칭 제거** — 함수별 3건 edit 대신 통째 매칭으로 변경 폭 검증 단순화. 한국어 byte-level 매칭이 핫패스 본문 (250L+) 에서도 정상 동작.
- ⭐ **forward 메서드 인자 다수 (9개)** — `self: &Arc<Self>` + publisher + target + room + plaintext + prefan_payload + rtp_hdr + is_keyframe + sender_user_id. 헬퍼 분리 유혹 있었으나 한 메서드로 묶음 (분기 표현 명확성 우선).
- ⭐ **publisher_stream.rs 의 transport 의존** — Step A 시점부터 `crate::transport::udp::UdpTransport` import 필요 (room → transport 의존 방향). UdpTransport 필드 모두 `pub(crate)` 격상 확인 후 진행 — 의존 방향 어색하지만 Phase 4 기본 비용으로 수용. Phase F 정리 검토 가능.

---

## 다음 phase

설계서 §6 Phase 4 완료 → Phase 5 진입 조건 만족.

**Phase 5 (SWITCH_DUPLEX op=52 폐기 vs 현구현 충돌 재확인)** ±300L 서버 + 클라 별도. 설계서 §6:
- "SWITCH_DUPLEX op=52 삭제. PUBLISH_TRACKS 안 ssrc 동일성 분기 + hot-swap 로직"
- "클라 SDK 는 다음 세션 (부장님 영역)"

부장님 결재 후 진입.

설계서 §4.3 의사코드 W-1 보강 commit 도 별도 검토 의뢰 가능.

---

*author: kodeholic (powered by Claude)*
