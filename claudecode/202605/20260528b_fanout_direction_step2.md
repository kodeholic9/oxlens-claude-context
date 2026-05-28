# 작업 지침 — Step 2: broadcast 도입 + Full 경로 lookup 폐기 (+ Step 1 발굴 이슈 반영)

**문서 ID**: `20260528b_fanout_direction_step2.md`
**작성**: 김대리 (claude.ai)
**대상**: 김과장 (Claude Code)
**설계서**: `context/design/20260528_fanout_direction_redesign.md` §8 Step 2
**선행**: `20260528a_fanout_direction_step1_done.md` (Step 1 완료, 217 PASS)
**부장님 GO**: 대기

---

## §0 의무 점검 (착수 전 반드시)

1. `cargo test -p oxsfud` baseline = **217 PASS** (Step 1 후, 214 + 신규 3). 본 작업 종료 시 217+ 유지.
   - ※ 설계서/Step1 지침의 "299" 는 **김대리 오인용** (PROJECT_MASTER 워크스페이스 숫자). `-p oxsfud` 단일 크레이트 정답 = 214. 본 지침 214/217 로 확정.
2. 설계서 §6.1(broadcast) + §8 Step 2 통독.
3. 본 Step 은 **핫패스 변경** (위험 중). Full 트랙의 fan-out 경로를 subscribers 순회로 교체. **Half(PTT) 는 기존 경로 그대로.**

---

## §1 컨텍스트

### 1.1 Step 1 완료 상태

- `PublisherStream.subscribers: ArcSwap<Vec<Weak<SubscriberStream>>>` 신설 완료
- `collect_subscribe_tracks` 가 Direct pref 의 SubscriberStream 을 publisher 에 attach (병행, fanout 미사용)
- 단위 테스트 3건 PASS

### 1.2 Step 2 목표

`PublisherStream::fanout` 의 **Full 트랙 sub 순회**를 `self.subscribers` 직접 순회로 교체. `subscribers_snapshot(fan_room)` + `find_subscriber_stream_by_vssrc(vssrc)` lookup 을 Full 경로에서 폐기.

### 1.3 Step 1 발굴 이슈 2건 (본 지침 반영)

| 이슈 | 출처 | 본 지침 처리 |
|---|---|---|
| **중복 Weak 누적** | done §3.1 | **Phase A 에서 옵션 1 반영** — broadcast 전환 전 필수 (중복 송신 차단) |
| clippy bit mask 버그 (`ingress_subscribe.rs:422`) | done §3.2 | **§11 별 토픽 기록만** — Step 2 영향 범위 외, 안 건드림 |

---

## §2 결정된 사항

### 2.1 설계서 §4 pin (불변)

이름 유지 / Track home = PublishContext / Slot 현행 유지 / Push 모델.

### 2.2 Step 2 추가 결정 (실물 점검 기반)

1. **target 조회는 기존 방식 보존** — `fan_room.get_participant(subscriber_id)`. forward 가 `target: &Arc<RoomMember>` 의존 (sub_stats = room-scope). subscribers 순회로 sub_stream 을 얻되, target 은 기존과 동일 조회. **Step 2 는 cross-room 정합을 새로 고치거나 깨지 않음** (기존 fanout 과 동일 조회식).
2. **Half(ViaSlot) 는 기존 경로 전부 유지** — Step 1 에서 subscribers 에 Half 안 채움. Half 가 broadcast 타면 아무도 못 받음. `is_half` 분기로 기존 경로 보존.
3. **forward 시그너처 안 바꿈** — 9 매개변수 유지 (PacketContext 는 Step 4). Step 2 는 sub 순회 소스만 교체.
4. **vssrc 계산은 Full 경로에서 미사용** — subscribers 직접 보유라 vssrc lookup 불필요. Half/simulcast 의 vssrc 계산은 기존 위치 유지 (Half 경로가 씀).

---

## §3 결정 추천 (정지점)

### ★ 정지점 1개 — Phase D 끝

Step 2 는 핫패스 변경. Phase A~D 일괄 진행 후:
1. commit
2. 부장님 보고 + GO

※ 브라우저 E2E smoke 는 김과장 범위 아님 (claude.ai + Claude in Chrome 영역). 김과장은 `cargo test` + `clippy` 까지. E2E 검증은 부장님/김대리가 별도.

---

## §4 단계별 작업

### Phase A — 중복 Weak 옵션 1 반영 (Step 1 발굴 이슈)

**파일**: `crates/oxsfud/src/room/publisher_stream.rs`

`attach_subscriber` 를 **subscriber_id 유일성 보장**으로 수정. 같은 subscriber_id 의 살아있는 Weak 가 이미 있으면 중복 push 안 함 (dead 는 청소).

```rust
    pub fn attach_subscriber(&self, weak: Weak<crate::room::subscriber_stream::SubscriberStream>) {
        // 신규 weak 의 subscriber_id 추출 (등록 직후라 upgrade 성공 기대).
        let Some(new_arc) = weak.upgrade() else { return; };
        let new_id = new_arc.subscriber_id.clone();
        drop(new_arc);

        let cur = self.subscribers.load_full();
        let mut new = Vec::with_capacity(cur.len() + 1);
        let mut already = false;
        for w in cur.iter() {
            match w.upgrade() {
                Some(s) if s.subscriber_id == new_id => {
                    // 같은 subscriber 의 살아있는 weak 이미 존재 — 중복 방지 (idempotent).
                    already = true;
                    new.push(w.clone());
                }
                Some(_) => new.push(w.clone()),  // 다른 살아있는 weak 유지
                None => {}                         // dead 청소
            }
        }
        if !already {
            new.push(weak);
        }
        self.subscribers.store(Arc::new(new));
    }
```

**단위 테스트 추가** (subscribers_tests):

```rust
#[test]
fn attach_subscriber_idempotent_no_duplicate() {
    // 같은 SubscriberStream Arc 를 2회 attach → count 1 (중복 방지)
}
```

> 근거: done §3.1 옵션 1. attach 가 단일 진입점 — 중복 방지도 그 자리. "subscribers Vec 에 subscriber 당 1 weak" 불변식 (설계서 §1.2 단일 진실 원칙).

### Phase B — broadcast_full 메서드 신설

**파일**: `crates/oxsfud/src/room/publisher_stream.rs`

`fanout` 의 sub 순회 + simulcast PLI burst 블록을 Full 트랙용 별 메서드로. **self.subscribers 순회, vssrc lookup 없음.**

```rust
    /// Full 트랙 (FullNonSim/FullSim) fan-out — self.subscribers 직접 순회.
    /// vssrc lookup 폐기 (subscribers 가 곧 이 publisher 의 다운스트림).
    /// target RoomMember 는 기존 fanout 과 동일하게 fan_room.get_participant 조회
    ///   (cross-room 정합 보존 — forward 가 sub_stats(room-scope) 의존).
    /// Half(ViaSlot) 는 본 메서드 안 탐 — fanout 의 is_half 분기에서 기존 경로 유지.
    fn broadcast_full(
        &self,
        transport: &crate::transport::udp::UdpTransport,
        fan_room: &Arc<crate::room::room::Room>,
        plaintext: &[u8],
        rtp_hdr: &crate::transport::udp::rtcp::RtpHeader,
        publisher: &Arc<crate::room::peer::Peer>,
        is_keyframe: bool,
        is_simulcast_video: bool,
    ) {
        let mut pli_sent = false;
        let publisher_uid = publisher.user_id.as_str();

        for weak in self.subscribers.load().iter() {
            let Some(sub_stream) = weak.upgrade() else { continue; };
            // self-skip 방어 (collect_subscribe_tracks 가 exclude 하지만 방어적).
            if sub_stream.subscriber_id.as_ref() == publisher_uid { continue; }

            // target 조회 — 기존 fanout 과 동일식 (cross-room 정합 보존).
            let target = match fan_room.get_participant(sub_stream.subscriber_id.as_ref()) {
                Some(m) => m,
                None => continue,
            };
            if !target.is_subscribe_ready() { continue; }

            // forward — 기존 시그너처 그대로. Full 이므로 prefan_payload = None.
            let need_pli = sub_stream.forward(
                self,
                &target,
                fan_room,
                plaintext,
                None,            // Full 경로 prefan 없음
                rtp_hdr,
                is_keyframe,
                publisher_uid,
            );

            // simulcast PLI burst (방마다 1회) — 기존 fanout 의 해당 블록 그대로 이주.
            if need_pli && !pli_sent && is_simulcast_video {
                pli_sent = true;
                let pli_ssrc = {
                    let streams = publisher.publish.streams.load();
                    streams.find_ssrc_by_rid("h").or_else(|| {
                        streams.iter()
                            .find(|s| s.kind == TrackKind::Video && !s.is_rtx() && s.rid_load().is_none())
                            .map(|s| s.ssrc)
                    })
                };
                if let (Some(ssrc), Some(pub_addr)) = (pli_ssrc, publisher.publish.media.get_address()) {
                    if publisher.is_publish_ready() {
                        crate::transport::udp::pli::spawn_pli_burst(
                            publisher, ssrc, pub_addr, transport.socket.clone(),
                            &[0, 200, 500, 1500], "SIM:PLI",
                            crate::room::pli_governor::Layer::High,
                        );
                        crate::metrics::sfu_metrics::METRICS.get().simulcast.pli_burst_sent.inc();
                    }
                }
            }
        }
    }
```

> 이 메서드는 기존 fanout 의 sub 순회 블록을 **거의 그대로** 떼어낸 것. 차이: `subscribers_snapshot` 순회 → `self.subscribers.load()` 순회, vssrc lookup (`find_subscriber_stream_by_vssrc`) 폐기 (weak.upgrade 가 곧 sub_stream).

### Phase C — fanout 에서 is_half 분기

**파일**: `crates/oxsfud/src/room/publisher_stream.rs`

`fanout` 의 sub 순회 블록 (`let mut pli_sent = false;` 부터 for 루프 끝까지) 을 분기로 교체:

```rust
            // === sub 순회 — is_half 분기 (Step 2, 2026-05-28) ===
            if is_half {
                // Half(PTT/ViaSlot): 기존 경로 유지 (subscribers 미사용 — Step 4 통합 전까지).
                //   prefan_payload + subscribers_snapshot + find_subscriber_stream_by_vssrc.
                let mut pli_sent = false;
                let publisher_uid = publisher.user_id.as_str();
                for sub_peer in transport.endpoint_map.subscribers_snapshot(fan_room.id.as_str()) {
                    if sub_peer.user_id == publisher_uid { continue; }
                    let target = match fan_room.get_participant(&sub_peer.user_id) {
                        Some(m) => m, None => continue,
                    };
                    if !target.is_subscribe_ready() { continue; }
                    let sub_stream = match target.peer.find_subscriber_stream_by_vssrc(vssrc) {
                        Some(s) => s, None => continue,
                    };
                    let need_pli = sub_stream.forward(
                        self, &target, &fan_room,
                        plaintext, prefan_payload.as_deref(), rtp_hdr, is_keyframe, publisher_uid,
                    );
                    // Half 는 simulcast 아님 → PLI burst 분기 미발동. pli_sent 미사용.
                    let _ = (need_pli, &mut pli_sent);
                }
            } else {
                // Full (FullNonSim/FullSim): 방향 역전 — self.subscribers 직접 순회.
                self.broadcast_full(
                    transport, &fan_room, plaintext, rtp_hdr,
                    publisher, is_keyframe, is_simulcast_video,
                );
            }
```

**주의 — 김과장 판단 자리:**
- 기존 fanout 의 `vssrc` 계산 (`let vssrc = if is_simulcast_video {...} else if is_half {...} else {...}`) 은 **is_half 경로만 사용**. Full 경로는 broadcast_full 이 vssrc 안 씀. → vssrc 계산을 is_half 블록 안으로 옮기거나, 기존 위치 유지하되 Full 에선 미사용 (`let _ = vssrc;` 경고 회피). **김과장이 컴파일 경고 보고 판단** (선조치 후 보고).
- `prefan_payload` 는 is_half 전용 (기존도). Full 경로 진입 시 prefan_payload 는 None 이어야 함 (is_half=false → prefan_out_via_slot 미호출). 기존 로직 그대로면 정합.

### Phase D — 검증 (김과장 범위)

1. `cargo test -p oxsfud` → **217+ PASS** (Phase A 신규 테스트 포함)
2. `cargo clippy -p oxsfud` 신규 코드 경고 없음
3. 컴파일 에러 0

※ 브라우저 E2E smoke 는 김과장이 하지 않는다. cargo test/clippy 까지가 김과장 검증. 핫패스 변경의 실동작 검증(conference/simulcast/cross-room/Half)은 부장님/김대리가 claude.ai + Claude in Chrome 으로 별도 수행.

---

## §5 변경 영향 범위

| 파일 | 변경 | 비고 |
|---|---|---|
| `room/publisher_stream.rs` | attach_subscriber 옵션1 (Phase A) + broadcast_full 신설 (Phase B) + fanout is_half 분기 (Phase C) + 테스트 1건 | 핵심 |

**안 건드리는 것**:
- `ingress*.rs` fanout 호출처 (set_phase 자리 그대로 — fanout 시그너처 불변)
- `SubscriberStream::forward` (시그너처 불변 — Step 4)
- `publisher_ref` / `SubscribeMode` (Step 3)
- Half/PTT/Slot 경로 로직 (is_half 분기로 기존 보존)
- `ingress_subscribe.rs:422` clippy 버그 (§11 별 토픽)

---

## §6 운영 룰

1. **정지점 1개** (§3) — Phase D (cargo test/clippy) 후 commit + 보고 + GO.
2. **추가 변경 금지** — §5 외 손대지 말 것. clippy 버그도 안 건드림 (§11 기록만).
3. **2회 실패 시 중단**.
4. **시그니처 선조치 후 보고** — vssrc 계산 위치 / get_participant 인자 타입 / 컴파일 경고 회피는 김과장 판단 후 사후 보고.

---

## §7 기각 접근법 (이 Step 에서 하지 말 것)

- **Half 도 subscribers 순회로** — Step 1 에서 Half attach 안 함. Half 가 broadcast 타면 못 받음. is_half 분기로 기존 경로 유지 필수. Half subscribers 통합은 Step 4.
- **forward 시그너처 변경 (PacketContext)** — Step 4.
- **publisher_ref 폐기** — Step 3. (broadcast_full 은 publisher_ref 안 씀 — 폐기는 Step 3 에서 안전하게)
- **target 조회 방식 변경** — 기존 fan_room.get_participant 보존. cross-room 정합을 Step 2 에서 새로 건드리지 않음.
- **clippy bit mask 버그 정정** — 별 토픽 (§11).

---

## §8 산출물

- commit: `feat(sfu): Full 트랙 fan-out 을 subscribers 순회로 (방향 역전 Step 2) + attach 중복 방지`
- 완료 보고: `context/202605/20260528b_fanout_direction_step2_done.md` (**202605/ 자리 — claudecode/ 아님**)
  - Phase A~D 검증 결과 (test 수, clippy) — E2E 는 김과장 범위 아님
  - vssrc 계산 위치 처리 방식 (선조치 보고)
  - **발견 사항**: Half/Full 분기로 인한 fanout 비대 여부 (Step 4 통합 시 해소 예정 — 기록만)
  - Step 3 진입 전 확인 자리

---

## §9 시작 전 확인

1. baseline 217 PASS?
2. 설계서 §6.1 + §8 Step 2 읽었는가?
3. **Half 는 기존 경로 유지 (is_half 분기)** — 이해했는가?
4. 검증은 cargo test/clippy 까지 (E2E 브라우저 검증은 김과장 범위 아님).

---

## §10 직전 작업 처리

Step 1 (`20260528a`) 완료 + commit 됨. done 파일 `context/202605/` 로 현행화됨. 본 Step 은 그 위 진입.

---

## §11 별 토픽 기록 (Step 2 범위 외)

### clippy bit mask 버그 — `ingress_subscribe.rs:422`

```rust
.filter(|b| (b.get(1).copied().unwrap_or(0) & 0x7F) != config::RTCP_PT_PSFB)
```

`RTCP_PT_PSFB = 206`. `_ & 0x7F` 결과는 0~127 → 206 과 절대 안 같음 → 필터 항상 통과 (PSFB 안 걸러짐). RTP PT 마스크(0x7F)를 RTCP PT(8bit 전체)에 잘못 적용한 것으로 보임. **별 토픽 정정 필요** — RTCP PSFB 필터 동작 검증 + 마스크 제거 여부. 본 Step 안 건드림 (Step 1 done §3.2 정합).

---

*author: kodeholic (powered by Claude) — 김대리, 2026-05-28*
