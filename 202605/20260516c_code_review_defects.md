# 코드 리뷰 부정합 발굴 — 누적 목록

> 부장님 5월 코드 내재화 과정에서 발견된 부정합/설계 의문/버그 누적.
> 이 파일이 단일 출처. 크런치 모드 진입 시 우선순위 매기고 수정 여부 결정.

---

## 5/6 발굴 (10건)

| # | 분류 | 제목 | 요약 |
|---|------|------|------|
| 1 | 설계 | SessionPhase에 Joined 묻어 있음 | 다방 시나리오에서 Identified ⇄ Joined 핑퐁. 단조 phase에 토글 멤버십 욱여넣음. → AuthPhase + joined_rooms 분리 후보 |
| 2 | 설계 | ParticipantPhase 이름/추상화 단위 오류 | 실제는 pub-track 단위 lifecycle. user 단위로 잘못 추상화. → PubTrackPhase 재명명 후보 |
| 3 | 성능 | Room 목록 JSON 런타임 오버헤드 | JSON `Value` 런타임 탐색/캐스팅. Native struct로 수집·정렬 후 일괄 직렬화로 리팩터 |
| 4 | 정리 | message.rs 중복 PT/MID 필드 | Request 레벨 video_pt/rtx_pt/audio_mid/video_mid — Item에 이미 존재. 하위호환 잔재 |
| 5 | 의문 | Hot path lock 회피 — 측정 없는 원칙 | 방당 30명, 1만 user 상한에서 mediasoup/LiveKit 패턴 무비판 복사인지 검증 필요 |
| 6 | 의문 | TrackType match 분기 — 억지 일반화 의심 | 4종 본문이 거의 안 겹침. Phase ① 일반화로 +200L. Strategy 패턴을 일반화로 포장했을 가능성 |
| 7 | 설계 | SubscribeMode 이름과 실제 어긋남 | enum은 단일이지만 실제 라우팅 상태(layer/gate/last_seq) 분산. ViaSlot이 다른 3개와 추상화 레벨 불일치 |
| 8 | 설계 | Phase 전이가 fanout 핫패스에 박힘 | Track이 자기 phase 자기 관리 원칙 깨짐. "첫 RTP 잡는 자연스러운 자리"라는 편의 |
| 9 | 의문 | PLI Governor 인과관계 — 본질은 시간 임계치 | "I-Frame 관측" 한다지만 timeout fallback 필수. 텔레메트리 금지 원칙과 경계 미정의 |
| 10 | 의문 | RTX 통계 제외 — 적용 범위 미세 정의 부족 | recv_stats 제외 옳음, send_stats 제외 의문. NACK/RTX 폭증 진단 신호 막힘 |

---

## 5/15 발굴 (7건)

| # | 분류 | 제목 | 요약 |
|---|------|------|------|
| 11 | 구조 | PeerMap.by_ufrag/by_addr에 RoomMember 잔존 | `register_session()`이 `or_insert_with`로 첫 JOIN의 RoomMember 영구 고정. Cross-room에서 stale RoomMember hot path 유입 위험. 수정안: `(Arc<Peer>, PcType)`으로 축소. **호출처 영향 미조사** |
| 12 | 거짓주석 | EndpointMap 미존재 vs 주석 "이동 완료" | room.rs 주석 + PROJECT_MASTER에 "Step 4에서 EndpointMap으로 이동" — 실제 코드에 EndpointMap 없음. 계획을 사실처럼 기술 |
| 13 | 구조 | fanout에서 Peer 찾고 RoomMember 이중 조회 | SubscriberIndex → Arc\<Peer\> 후 Room.get_participant로 RoomMember 재조회. 핫패스 DashMap 조회 중복 |
| 14 | 구조 | is_subscribe_ready() Peer 경로인데 RoomMember 경유 | target.is_subscribe_ready()가 결국 peer.subscribe.media.is_media_ready(). RoomMember 불필요 |
| 15 | 코드 | clock_rate PT 기반 추정 | sub_stream.kind 사용 가능한데 PT로 추정. 구조적으로 틀린 코드 |
| 16 | 설계 | PliPublisherState.layer_idx() 비직관 | Pause→0 매핑이 High와 동일 인덱스. 3종 enum을 [2] 배열에 우겨넣음 |
| 17 | **버그+구조** | **PLI Governor 이슈 종합 (5건)** | 아래 상세 |

### #17 PLI Governor 종합

**근본 문제**: PLI Governor가 Track/Peer 레벨의 관계를 모른 채 독립적으로 존재. publisher 1:subscribers N 관계가 자료구조로 표현되지 않음.

| ID | 분류 | 내용 |
|----|------|------|
| I-1 | **버그 (독립)** | `check_stable_reset` — `downgrade_count == 0` 조기 반환으로 `consecutive_pli_count` 영구 누적 → 정상 유저 오발 강등 |
| I-2 | 구조 | pub/sub 갱신 분리 → 호출자가 쌍을 맞춰야 함, timeout이 유일한 안전망 |
| I-3 | 구조 | publisher 교체 시 `pli_pending` 잔존 → 새 publisher PLI 차단 |
| I-4 | 구조 | pub→sub 상태 전파 로직이 함수 본문 곳곳에 산재 |
| I-5 | 설계 | PLI 상태가 Track/Peer 소유권 밖에 존재 |

**재설계 방향 (A안 기반)**:
- I-1 fix: `check_stable_reset` downgrade_count==0 조기 반환 제거
- I-2 fix: `on_keyframe_delivered(pub, sub, layer)` 단일 진입점으로 pub/sub 동시 갱신 강제
- I-3 fix: `PliPublisherState`를 교체 가능한 독립 생명주기로 선언, 교체 시 `::new()` 강제
- I-2/3/4/5는 같은 뿌리 — Track 레벨 귀속 시 자연 해소. I-1은 독립 버그로 선행 수정

---

## 요약 통계

- 총 17건 (독립 기준, 18/19는 17에 흡수)
- 버그: 1건 (#17 I-1)
- 거짓 주석: 1건 (#12)
- 구조적 부정합: 5건 (#11, #13, #14, #17 I-2~I-4)
- 설계 의문: 6건 (#1, #2, #7, #8, #16, #17 I-5)
- 코드 품질: 2건 (#4, #15)
- 성능: 1건 (#3)
- 검증 필요: 3건 (#5, #6, #9, #10)

---

## 오늘의 기각 후보

- (없음 — 발굴 위주 세션)

## 오늘의 지침 후보

- 리팩터링 완료 보고 시 체크리스트 적용: 자료구조 이주 / 호출부 새 경로 사용 / 옛 경로 잔존 없음 / 주석-코드 일치. 4가지 다 맞아야 완료.

---

*author: kodeholic (powered by Claude)*
