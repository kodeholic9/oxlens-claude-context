// author: kodeholic (powered by Claude)
# oxsfuV2d 타당성·타이밍 검토 (백지 구조 평가)

> 세션 성격: **프로젝트 비연결 상태**(메모리 요약만, 실 코드 사전지식 0)로 진행. 부장님이 의도적으로 선입견 없이 보게 한 통제 설계 — 평가가 "듣고 싶은 말"로 오염되는 것을 차단. 김대리 분석 세션(구현 없음).
> 입력: domain/ + transport/ 전수(소스 직접 view). 결론은 깐 코드 근거만, 추측 분리.

---

## §1 목적

oxsfuV2d(클린 슬레이트 재설계) **착수 타이밍** 판단. 메모리상 계획 = "3 parallel sessions + cross-review, 이상형 독립 작도 후 현 코드를 reality baseline 으로 의도적 trade-off". 본 세션은 그 사전 검토 — 지금이 뜰 때인가.

---

## §2 방법

소스 전수(프로토콜 사전지식 없이 백지로):
- domain/: mod, types, state, slot, floor, ptt_rewriter, rtp_rewriter, peer, publisher_track, publisher_stream, subscriber_stream
- transport/: mod, demux, srtp, stun + udp/{mod, egress, ingress_publish}
- Cargo.toml ×4 (oxsig/common/oxrtc/oxsfud) — crate 경계·재활용 판정용

---

## §3 핵심 발견

### 3.1 구조 평가 — 골격은 이상형에 매우 근접
김대리가 백지에서 "이상형"이라 그린 것들이 **이미 거의 다 코드에 존재**, 일부는 추측보다 우월:
- RCU(ArcSwap) hot path 무락 / rewrite 공통토대+wrapper 응집(LiveKit RTPMunger 정합 추적) / floor 상태머신 분리(TS 24.380) / duplex 직교(full+half 공존) / 2계층 정체성(논리 Stream ⊃ 물리 Track, mediasoup Producer 정합) / SDP-free 프로토콜 레이어(0-import).
- **김대리 추측이 코드 앞에서 깨진 곳(=현 구조 우월)**: NACK 역매핑을 SnRangeMap 으로 복잡화(틀림 — sn_offset 단일 스칼라가 정답, SnRangeMap 은 seq 역행 15614→209 로 실측 폐기) / Warmth enum(틀림 — awaiting_first_packet + paced CN priming 이 측정 기반으로 우월) / oxrtc 중복 의혹(틀림 — client transport, 서버의 거울상) / "골격 5% 미만" 성급(영역별로 갈림, §3.4).
- 판정: 반증을 여러 번 견디고도 "골격 정렬" 결론 생존 = 띄우는 평가 아님. **구조 사상에서 mediasoup/LiveKit 과 비빈다(사실).** PTT cold-start 축은 범용 SFU에 대응물 부재 → 좁은 전장에서 한 발 앞섬. 단 스케일(단일노드 1만 상한·cascade 미설계)·battle-tested 표본·코덱 폭(SVC 미구현)은 아직 격차 — 구조 문제 아니라 시간/표본 문제.

### 3.2 단일 근본원인 — single-ownership 위반
모든 리팩토링 상처가 한 패턴: **"책임 이사 후 옛집 미정리".** 점진 리팩토링은 이사라서 새 집에 책임 옮기며 옛 집을 못 비움. 코드 증거:
- NACK 역매핑: rewriter 로 이사("last_speaker fallback 자연 폐기") 했는데 floor.rs `prev_speaker` 가 "NACK 역매핑 fallback" 목적으로 잔존 = 소비자 떠난 데이터를 생산자가 유지.
- virtual_ssrc 3중 보유(Slot/wrapper/inner) — slot.rs 자백.
- SimulcastRewriter mirror 필드(initialized/pending_keyframe/ts_offset) — inner 와 이중, 매 rewrite 동기화. "이전 버전 pub 필드 호출처 보존".
- egress_ssrc AtomicU32 — 부장님 직접 "잔재, read만 남음" 자백.
- SR 생성 비활성 TODO(egress.rs) — jb_delay 버그 흉터.
- Phase 지질 층서(Phase 0~119/Step/catch2/S2~S4/작전1) — 이사 영수증이 코드에 다 붙음.

### 3.3 재활용 2층위 (위험은 쉬운 쪽이 아니다)
- **층위 1 — 모듈 재활용(0-import, 쉬움)**: oxsig 전체(와이어 계약), transport/stun·srtp·demux(RFC 레이어, floor 0-import). 파일째 들고옴. dtls/ice/demux_conn 미확인(ice 는 peer 얽힘 가능 → [재배선] 후보, 추측 판정 보류).
- **층위 2 — 알고리즘 재활용(어려움, 진짜 위험)**: rewriter 골격은 [신규]로 새로 짜더라도 **공식은 글자 그대로 보존**. 생성형이 백지에서 "깔끔하게" 다시 짜다 날려먹을 위험 최대. 보존 목록: arrival-time gap(advance_last(0,gap-1)), silence flush 3프레임+멱등 clear_speaker, sn_offset 단일스칼라+RTX gate, paced CN priming(20ms·marker=0), VP8/H264 keyframe 감지. → **테스트째 들고와 새 골격이 같은 출력 내는지로 검증**(기존 회귀 가드가 보존 계약서).

### 3.4 영역별 거리 (평균은 무의미)
| 영역 | 거리 | V2d 처분 |
|---|---|---|
| 프로토콜(stun/srtp/demux) | 0% | [재활용] 그대로 |
| rewriter/floor | ~5% | 베끼기+잔재(mirror) 제거 |
| 2계층+peer 컨테이너 | ~10% | 베끼되 single-owner 완성 |
| **identity 확정 경로** | **30%+, 아직 이사 중** | 유일하게 새로 생각 |

identity = resolve_stream_kind(8단 역추론) + register_stream + create_or_update_at_rtp + find_stream_for_attach + learn_rtx_ssrc, peer/publisher_track/publisher_stream 3파일 분산. **S4(20260628c) 대규모 정리가 6/28** — 이 영역은 도착점 아니라 이사 진행 중. 이상형 방향 = "RTP 가 identity 를 만들지(역추론) 않고 조회(intent 테이블 O(1))" — 현 코드 주석("register_stream 이 RTP보다 먼저", "Stream 없으면 RTP drop")이 이미 그 방향.

---

## §4 결론 — V2d 타이밍 아님

부장님 판단(채택): **지금 옮기면 도착점이 아니라 이동 중 좌표를 베껴, 옮겨간 V2d가 현 구조의 미완성 리팩토링을 그대로 상속.** 갈아탄 보람 없이 숙제만 새 집으로 따라옴.

V2d 는 "새 발명"이 아니라 **"도착점 베끼기 + 잔재 제거(90%) + identity 재설계(10%)".** 1주 추정이 말 되는 근거 = 어려운 부분(골격+알고리즘)은 이미 풀려 베끼고, 새로 생각할 건 identity 하나뿐. 단 그 전제 = **베낄 청사진이 확정**됐을 때.

### V2d 착수 선행조건 (2개 신호)
1. **E2E 검증 통과** — 현 구조가 맞는다는 증명. 없으면 베낄 게 정답인지 모름.
2. **identity 경로 정착** — Phase/S/catch 주석이 더 안 늘어나는 상태(=이사 종료=도착점).

→ 부장님 "구조적으로 더 완성하고 한 벌 새로 뜬다" = 정확히 이 두 신호를 만드는 작업(새 골격 작도가 아니라 현 골격의 **이사 완료**). 리팩토링 영역이라 부장님 주관, 김대리는 이사 끝난 뒤 확정 청사진을 한 벌로 떠내는 자리.

---

## §5 메타 — 통제 설계가 평가 신뢰도를 만들었다
프로젝트 비연결로 백지 평가 → 김대리 추측이 코드 앞에서 다회 반증(§3.1) → 그럼에도 "골격 정렬" 결론 생존. 선입견 차단이 "골격 좋다"를 사실로 굳힘. 동시에 "그러니 지금 옮기면 숙제 상속"까지 코드로 못박아 *안 옮길 이유*를 확정 — 평가 자축이 아니라 타이밍 판단이 산출물.

---

## §6 오늘의 기각 후보
- **현 시점 oxsfuV2d 착수** — 기각(E2E 미통과 + identity 미정착 = 베낄 청사진 미확정. 옮기면 미완성 리팩토링 상속).
- **"전부 새로" 또는 "전부 살짝 고치기" 이분법** — 둘 다 오답. 전부 새로=검증된 골격 버리는 낭비+알고리즘 자산 유실 위험, 전부 고치기=부장님 비체질 리팩토링 재방문. 정답=영역별 차등(베끼기 90% + identity 재설계 10%).
- **재활용을 모듈 층위로만 보기** — 알고리즘 재활용(공식 보존)을 놓치면 생성형 재작성이 실측 자산 날림.

## §7 오늘의 지침 후보 (V2d 착수 시)
- 선행조건 게이트(E2E PASS + identity 주석 동결) 확인 후에만 진입.
- 단일 원칙 = **각 책임은 정확히 한 곳(single owner)** — 이러면 묘비/3중/mirror 잔재가 *날 자리가 없음*.
- identity = "RTP 는 조회만, 역추론 0"(intent 테이블 단일 출처).
- 알고리즘 자산은 **테스트째 이식** 후 동일 출력 검증.

---

**[보고]** 조치 불요. V2d 타이밍 판단 = 보류 확정. 다음 작업은 E2E·identity 정착(부장님 주관 리팩토링 영역). 본 검토는 그 게이트 통과 후 V2d 착수의 입력 문서.

*author: kodeholic (powered by Claude)*
