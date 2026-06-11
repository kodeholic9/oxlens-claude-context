# 20260610 talkgroups 재구조화 Phase 1(서버)+Phase 2(클라)+Phase 3(청취축) 완료

> 설계: `design/20260610_talkgroups_applyevent_design.md` (검토 기록 `20260610_client_send_room_review.md` 후속).
> 커밋: 서버 `6877599` / 클라 `0df5408`. 부장님 결정: **모델 2 전면 reconcile** / ROOM_JOIN scope 동봉 /
> presence 단독 불인정 / pub wire 단수화(core 호환 미련 금지) / **scope.js 삭제** / hub selected 권위(A') **보류**.
> 지침: "과감한 재구조화 — 기존 구조 보존은 목표가 아니다."

## Phase 1 — 서버 (oxlens-sfu-server `6877599`)

- **S-a/S-b**: ROOM_JOIN·ROOM_LEAVE 응답 `scope:{sub,pub}` 동봉 (`helpers::scope_snapshot`) — "scope 바꾸는 op는 결과를 응답에"
- **S-c**: SCOPE 응답 pub 단수화 — `pub_rooms: Vec`(cross-room publish 폐기 화석) → `pub_room: Option`(serde `"pub"`). dead 필드 청산
- **S-e**: `auto_select_if_unset` **삭제** — sfud마다 독립 발사로 "발언축 1" 위반(F9). `RoomJoinRequest.select`(기본 true) 핸들러 명시 집행. false=affiliate
- **S-f**(hub): SCOPE 라우팅 힌트(`scope_room_hint`) — 구 session.room_id 폴백 오라우팅 결함 수정. **SCOPE=단일 sfud 귀속 계약**
- **S-g**: `pub_deselect` 신설 — cross-sfu select 이전 sfud 정리
- 검증: cargo 206+24 / oxe2e 4종(conf_basic·ptt_rapid·duplex_cache·simulcast_basic) / 라이브 wire 5항목 PASS

## Phase 2 — 클라 (oxlens-home `0df5408`)

- **`domain/talkgroups.js` 신설** — 방 관계 권위 1곳(구 3분산: engine.rooms/_pubRoomId + scope 서기 통합)
  - `applyEvent(sfuId, 스냅샷)` 유일 mutate — 직렬화 큐+멱등 / 전면 reconcile(sub 조립·철거, pub 조각 합성)
  - 재료 보관소(F6) / 강제 편입 pending+보고(F7) / cross-sfu select 분할 송신(S-g)
- **engine**: `_pubRoomId` 폐기, `_selectRoom`→`_migratePubAxis`(물리 전용), leave→request+reconcile 철거, auto-select 추측 2곳·scope:changed 2중 발화 제거
- **scope.js 삭제**(디렉토리째, 별칭 없음 — 데모 사용처 0 실측). floor 표면 실가치(roomId 동봉·DENIED enum)는 `ptt.on/off` 흡수 → 외부 표면 = **talkgroups(방 관계) + ptt(발화권)** 설계 §8.3 일치
- 검증: mock 12종 + 라이브(실 SDK×2-sfud node 직결 — join/affiliate/cross-sfu select/leave·조각 키 분리·Transport sfud별 분리) 전부 PASS

## Phase 3 — 청취축 단일 표면 + 다방 PTT 수신 (서버 `db930f7` / 클라 `4f27cc0`)

> 부장님 결정: TAKEN 어휘 단일(RoomEvent.SPEAKER 폐기) / 청취도 `ptt.on` 통합(무전기 멘탈 모델) /
> 콜백에 room 핸들 동봉. + scope.js 삭제(별도 지시, 클라 `0df5408` 직후 커밋에 포함).

- **표면**: `ptt.on(TAKEN/IDLE, ({room, roomId, speaker}))` affiliated 전 방 수신 / `talkgroups.on('changed')` / ptt 생성=첫 방 조립(`_ensurePtt`)
- **FSM**: 타방 TAKEN/IDLE = emit만(발언축 비오염 — 구 오염 결함 수정)
- **★발견 1 (클라)**: virtual slot pipe가 subscribe 합집합에서 0605 재작성 때 누락 — **PTT 수신 m-line 자체가 안 서던 구멍**(부채 D 라이브 0회의 실체). per-room slot(Map)화 + 합집합 포함으로 해소
- **★발견 2 (서버)**: datachannel 인입 floor 경로 `event_tx=&None` 하드코딩 — DC 미수립 참가자(청취 전용/cross-sfu) floor 영구 미달. **S-h: WS unicast fallback** + event_tx 5단 관통. oxrtc 봇 FLOOR_MBCP binary 면역(duplex_cache 회귀로 발견)
- **검증**: 라이브 — DC 없는 node 청취자가 봇 발화 TAKEN/IDLE 4건 WS fallback 수신(화자 식별/room 핸들/FSM 비오염). oxe2e 4종·mock 12종·tg_live 전 PASS
- **잔여**: PTT 음성(RTP) 라이브 = 브라우저 영역(voice_radio 데모 RUN, 부채 D G2 게이트). Phase 3b(강제 경로 발언축 파생) = S-d 동행 이월

## F11/F13 — hub 다방 배달 + "마지막 join 방" 힌트 폐기 (서버 `5a39e87` / 클라 `1e0b763`)

> 발단: A'(hub selected 권위) 숙고를 위한 **hub 구조 실측** 중 F11 발견 → 부장님 "F11 먼저 보강" →
> 보고의 "힌트로 강등" 문구에 부장님 "이것 때문에 정보가 오염되지 않니?" → 힌트 전면 폐기로 확대.

- **F11**: hub `set_client_room` 이 이전 방 제거 + 종료 통보가 마지막 방 sfu 에만 — **다방 청취 broadcast 배달이 hub 에서 끊겨 있었음**. `WsConn.rooms: HashSet` + add/remove(정밀)/전 방 순회 cleanup. 라이브(3방 가입, 전 방 도달/부분 탈퇴) PASS
- **F13 (부장님 지적)**: "마지막 join 방" 힌트(`WsConn.room_id`/`WsSession.room_id`)는 멀티룸에서 의미 없는 **오염값** → 필드 삭제 + dispatch/MODERATE 폴백 제거. **계약 = sfud행 op room_id 필수**(누락=명시 에러). 폐기로 표면화된 위반자 정정: 봇 PUBLISH/TRACK_STATE/ROOM_SYNC + **oxrtc send_tracks_ready**(TRACKS_READY 미도달 → SubscriberGate video resume 불발 = conf video 회귀, stash 이분으로 확정)
- **F12 (부수)**: ROOM_EVENT wire 키 `"type"` 인데 sdk room.js 가 `event_type` 독해 — participant_left(유령 타일 제거)가 **죽은 분기**였음. mock 도 같은 오류 가정이라 미검출(데모는 방어 코딩 생존). 정정
- C안(무상태 질의-병합) 숙고 재료 설계서 §8 등재 — hub selected 권위(A')는 계속 보류

## 묶음 1~3 — Pipe 송출 상태 재설계 (클라 `c0ca900`)

> 발단: 검토 기록 "부수 발견" 5건에 부장님 "계속 눈에 거슬리던 부분 — track 멤버 폐기 포함 진지하게,
> 작업 묶어 볼래" → 묶음 제시 → 코딩. 진행 중 "base 가 너무 많이 들고 있다" 지적 → 묶음 3 확장.

- **묶음1 (상태축 5→2)**: track 미러 폐기 → **파생 getter**(권위 sender.track ?? _heldTrack, 직접 대입
  즉사). _savedTrack→_heldTrack 의미 통합. _upstreamPaused/pauseUpstream 폐기 — device-mute 는
  suspend/resume 갈음(0609 §6.6 절충 대체). **종단 epoch** — lock 큐 잔여가 죽인 pipe 부활시키던
  interleaving 구멍(부수④) 봉쇄
- **묶음2 (게이트 일관성)**: holdRtp() 신설(RTP 차단 게이트화, 부수②), unbindSender() 경유(부수①),
  base sender setter 삭제(우회로 봉쇄), transport 헤더 거짓 정정(부수⑤ 문서분)
- **묶음3 (base 다이어트)**: 감사로 실증 — base 가 송수 합집합(send 전용 _sender 계열 + recv 전용
  rtx/pt/출력제어 + 死 fallback). 전용 멤버 각자 강하, base = 식별/intent+transceiver+element 만.
  base 헬퍼의 this.track 읽기는 프로토타입 체인으로 양표현(Local getter/Remote 데이터) 공통 해소
- 검증: mock 12종(sender mock 을 실 semantics 로 보강 — 가짜 mock 이 죽은 분기 못 잡던 F12 교훈 적용)
  + talkgroups 라이브 ALL PASS

## ★★ 교훈 (디버깅 장기화 회고 — 메모리 `feedback_wire_contract_consumers` 등재)

1. **전수조사 범위 누락이 최대 손실** — 힌트 폐기 전 "기대는 자" 조사를 웹 SDK 만 grep 하고 "op 0개" 단정. 소비자에는 **oxe2e 봇·oxrtc 라이브러리**(서버 레포 안의 클라이언트!)도 있었다. 처음에 봤으면 회귀 디버깅 자체가 없었음. → wire 계약 변경 시 조사 범위 = 웹 SDK + core + 데모 + 봇/oxrtc + Android, 조사 범위를 보고에 명시
2. **회귀엔 stash/커밋 이분이 첫 수** — 틀린 가설 검증·로그 타임존 오판·재기동 레이스("Address already in use", 구버전 잔존 서빙) 같은 인프라 잡음과 싸우다 결정 수단을 늦게 꺼냄. 답은 결국 이분이 줬다(커밋 상태 3/3 PASS → 델타 확정). `feedback_purpose_first`(인프라 디버깅 함정) 재발 사례
3. **검증 스크립트도 의심 대상** — F11 첫 검증 0건의 원인은 서버가 아니라 스크립트의 필드명 오류(`event_type` vs wire 진실 `type`). 단 이 한 바퀴가 F12(본체 죽은 분기)를 건짐 — mock 이 구현과 같은 오류 가정으로 작성되면 죽은 분기를 영원히 못 잡는다. **단언은 wire 실측 기준으로 작성**

## ★ 세션 중 발견 (설계서 F8~F10 등재)

- **F8**: Peer(scope 권위)=user×sfud 조각 — user-global 단일 진리 서버 부재 (라이브 실증으로 발견 → A안 채택 계기)
- **F9**: auto-select sfud별 독립 발사 + hub SCOPE 오라우팅 (→ S-e/S-f로 해소)
- **F10**: server_config에 sfu 식별자 부재 — 클라 조각 키 "default" 뭉개짐(cross-sfu에서 두 번째 join이 첫 sfud 방 철거 + TransportSet 오염, 0609d 미검증 영역의 실구멍) → **ICE 종단 ip:port 파생 키**로 클라 해소. hub sfu_id 동봉 시 자동 1순위

## 이월

- **hub user-global selected 권위(A'안)** — 부장님 보류("순발력으로 처리할 문제가 아니다"). F10의 sfu_id 동봉과 한 묶음 후보
- **Phase 3**: 강제 경로 발언축 파생(reconcile pub 축 본격) — S-d(SCOPE_EVENT emit)·pending 해소 wire와 동행
- **Phase 4**: 잔여 표면 정리(데모는 이미 무영향 — engine.joinRoom만 사용)
- 검토 기록 부수 발견 5건(transport sender 게이트 위반 등) + 청취 floor 처리 — 별 토픽 그대로

---
author: kodeholic (powered by Claude)
