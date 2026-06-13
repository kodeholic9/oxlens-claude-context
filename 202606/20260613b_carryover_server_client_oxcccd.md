// author: kodeholic (powered by Claude)
# 2026-06-13b 0613 이월 소진(서버 2 + 클라 2) + oxcccd 텔레메트리 데몬 1차

## 세션 성격
0613(검은 화면 해결) 후속. 이월 ①~④ 전수 소진 + oxcccd 설계서 검토→토폴로지 확정→1차 구현.
커밋 4: server `a51390f` / home `4269149`·`1083555` / server `d8b39a1`.
(context 설계서 개정분은 부장 커밋 몫 — 미커밋 잔존.)

---

## 한 것 (순서)

### 1. 서버 이월 ①② — 묵시 VP8 거절 + RTX SSRC 근본 수정 (`a51390f`)
- **① 묵시 VP8 박멸**: `VideoCodec::from_str_or_default`(미지정→조용히 VP8) 폐기 →
  `from_str_strict`(VP8|H264|VP9만 Some). PUBLISH_TRACKS(add) 입구에서 video intent codec
  미지정/오타 시 **등록 0건 전체 거절**(err 3002 "video codec required") + `video_no_codec`
  agg-log. 0613 검은 화면(구독 SDP pt↔codec 불일치) 서버측 봉쇄. wire 표 "codec 필수" 정합.
  - 부장 지시로 oxlabs/Android codec 송신 여부는 미고려(웹 폴백 `|| H264` 로 봉합됨).
- **② NEW rtx 매 패킷 반복 — 부장 추정 적중**: 클라가 PUBLISH_TRACKS `t.rtx_ssrc`(offer FID
  추출 실값)를 보내는데 서버가 버리고 `alloc_rtx_ssrc`(media+1000+counter) 조작값으로 대체 →
  `by_rtx_ssrc` 색인이 실 ingress rtx 와 영원히 불일치 → 매 패킷 cold path + info 폭주(1실행
  206회) + RTX 디캡슐(process_rtx_packet) 사장. v1 register_nonsim_tracks(Phase 19) 누락 회귀.
  - non-sim: intent `t.rtx_ssrc` 를 add_publisher_track→create_or_update_at_rtp 관통, 등록
    즉시 by_rtx_ssrc 색인(미제공 시만 alloc 폴백 — egress 선언용).
  - **sim: repair_rid RTP-first 학습**(부장 지적 — "SDP에 SSRC 없음=학습") `peer.learn_rtx_ssrc`.
  - non-sim intent 미제공 클라: rtx_pt 유일 매칭 시 학습, 모호 시 debug 강등.
  - with_removed: 학습 색인 동반 정리(Arc 동일성) — 잔존 시 오분류.
- 변경 7파일(types/track_ops/peer/publisher_track/publisher_track_index/ingress_publish/participant).
- 검증: cargo test 207/207(신규 peer_rtx_ssrc_intent_and_learning) + 회귀 conf_basic·ptt_rapid
  PASS + video_no_codec 오발동 0건. ※ rtx 학습 경로는 봇이 RTX 미발신이라 회귀 미커버(단위로 검증).

### 2. 클라 이월 ③ — recycle 정체 변조 게이트 격리 (`4269149`)
- **논점 정정(부장)**: 서버 mid 재사용(A 퇴장→B 입장 슬롯 재활용)은 정상(m-line 불가역).
  문제는 *재사용 단위* — 물리 슬롯(transceiver/mid)과 논리 정체(Pipe=누구의 트랙)가 한 객체에
  뭉쳐 Room 이 산발 Object.assign 으로 정체를 통째 변조 → 옛 참조 소비자(앱 핸들/streamHandle
  캐시/element dataset)가 통지 없이 새 사용자 트랙을 봄.
- **방향(부장)**: recycle 유지 + 이벤트 1개, 갱신은 수신처 책임.
  - `RemotePipe.rebind(next)` — 정체 교체 단일 게이트 + mount 중이면 element dataset 즉시 재기록.
  - `RemoteEndpoint.releasePipe/adoptPipe` — teardown 없이 키 이관 + 옛 핸들 캐시 evict(누수 차단).
  - `RoomEvent.STREAM_RECYCLED {stream, prev:{trackId,userId}, roomId}` — 소유 경계 밖(앱)만
    이벤트, 소유 객체는 직접 호출(bus 폐기 원칙 정합).
- 변경 5파일(remote-pipe/remote-endpoint/room/constants/c3_check). 글루 19/19(c3 신규 5 단언).
- ※ 미해결(이월 유지): 라이브 mid 재사용 재현 e2e(A퇴장→B입장 같은 mid → 이벤트+dataset 단언).
  서버 mid 재사용 유발 시나리오 장치가 본체 — 별건.

### 3. 클라 이월 ④ — R2 복구 발언축 _bindPubAxis 합류 (`1083555`)
- `_rebuildTransport`(R2 미디어 복구)가 `_bindPubAxis` 와 같은 일(PTT DC 정합+관측 재바인딩)을
  중복 구현하며 **lifecycle.ptt/telemetry.ptt 갱신 누락** → PTT 재생성 후 관측이 죽은 옛 PTT
  관측(floor/메트릭 stale). 정상 경로 2곳(_bindPubAxis/_migratePubAxis)은 둘 다 갱신 — 누락은
  중복에서 비롯. 한 줄 보강 대신 **합류로 단일화**.
  - _bindPubAxis: room 부재 허용(복구 경로) + 전 방 setPttVirtual 재주입(_migratePubAxis 패턴).
  - 합류 부수 동작(bindTransport/setRoom 추가 호출)은 동값 멱등.
- 변경 2파일(engine/recovery_check). 글루 19/19(R2-pub 에 lifecycle.ptt===engine.ptt 단언 신규).

### 4. oxcccd 설계서 검토 → 토폴로지 확정 → 개정 (context 미커밋)
- **소스 점검**으로 설계 초안 가정 보정 4곳:
  - §3 tap 위치: "ws dispatch"(실제 v3 빈 placeholder) → `ws/mod.rs::handle_client_message`
    sfud-forward 직전 + `events::dispatch_event`/`dispatch_admin_event` = **3 tap**.
  - §3 ★ TELEMETRY/CLIENT_EVENT 는 hub 로컬 소비 안 하고 sfud-bound passthrough → **room_id
    필수**(없으면 "no sfu for room" 으로 tap 도달 못 함). 클라 적재 여부 = 구현 전 확인 과제.
  - §7 proto: 현 WsMessage 는 oneof 폐기된 typed envelope(`bytes wire`) — 재활용 더 정합.
- **N-hub 토폴로지 확정(부장)**: oxcccd 전역 1개. owner hub(config 지정) 1개만 supervisor
  자식 spawn, **모든 hub 가 그 1개로 직결 push**. failover/2중화 본 세션 범위 밖. "우선순위"=
  로컬 owner 경로 우선(소유/관리 + 레이턴시 2층위), 승계 랭킹 아님.
- 설계서(`design/20260613_oxcccd_design.md`) 개정: §0 제약④ + §2a(owner/secondary config 분기)
  + §3 tap 3 표 + §7 proto 보정 + §9 failover 제외 + §10 기각 2.

### 5. oxcccd 텔레메트리 수집/조회 데몬 1차 구현 (`d8b39a1`)
- **신규 crate oxcccd**(전역 1개): store.rs(TelemetryStore trait + MemoryStore 방별 분리락·
  10분 front-drop·빈 방 제거) / service.rs(Report stream→op 분류+서버 ts stamp / Query) /
  main.rs(--grpc-listen + sweep 1분). SQLite 는 빈 trait 자리.
- **hub 통합(owner/secondary 코드 동일, config 분기)**: ccc/mod.rs(CccForwarder bounded 4096
  +try_send drop, inner channel 재연결 / query 헬퍼) + tap 3곳 + state ccc_tap ArcSwap attach
  + rest/telemetry.rs(GET samples/events, admin JWT) + proto CccService + config [ccc].
- system.toml: owner unit(oxcccd 50060) + [ccc] endpoint.
- 검증: 빌드 전체+release 3바이너리 / 단위 oxcccd 4·oxhubd 25·common 24 / 회귀 conf·ptt PASS /
  **라이브 e2e** — supervisor spawn(50060)→forwarder 연결(backoff 후)→conf_basic→tap②③ 수집→
  `GET /media/telemetry/rooms/qa_test_01/events` 5건 되읽음(source=sfu, ts stamp, room 키잉),
  type 필터·unknown room `[]` 정상.

---

## 결정 사항 (부장)
- 묵시 VP8 = reject(동적 판별 아님). oxlabs/Android codec 송신 여부 미고려.
- RTX: non-sim intent 관통 + sim RTP-first 학습.
- recycle: 게이트 격리 + STREAM_RECYCLED 1이벤트(갱신은 수신처). 라이브 e2e 는 별건 이월.
- R2 복구: _bindPubAxis 합류(중복 해소).
- oxcccd: 전역 1개. owner hub spawn, 모든 hub push. failover/2중화 범위 밖. 클라 room_id 적재
  가정 후 진행(완료 기록에 코멘트).

## 이월 (우선순위 순)
1. **★ [oxcccd 검증] 클라 TELEMETRY/CLIENT_EVENT room_id 적재 실측** — tap① 은 sfud-bound 라
   room_id 필수. 봇이 telemetry 미발신 → 클라 직접 발신(tap①) 경로 미검증. 실클라(웹 SDK)
   연결 시 telemetry.js/event-reporter.js room_id 적재 확인.
2. **[서버] codec 미지정 intent offer pt 동적 판별 or reject** — 클라 폴백으로 봉합됐으나 타
   클라(Android) 동일 함정 가능(이월 ① 의 동적 판별 변형 — 현재는 reject 채택).
3. **[클라] mid 재사용 라이브 재현 e2e**(이월 ③ 동반) — A퇴장→B입장 같은 mid → STREAM_RECYCLED
   +dataset 단언. 서버 mid 재사용 유발 시나리오 장치 본체.
4. rVFC 재설계(opacity 마스킹) — 부장 실측 후.
5. _rebuildTransport lifecycle.ptt 누락은 ④ 로 해소 — 잔여 복구 경로(rebuildTransport 의 ptt
   재바인딩) 라이브 검증은 실연결 시.
6. oxcccd 다음 단계: SQLite 실구현 / 경고 규칙 / export API / oxcccd 자체 REST(대량 폴링 시).
7. 실기기: 블루투스 분리/연결·iOS Safari·blockedBy 휴리스틱.
8. 복수 mic(G7) 실지원 시 서버 audio 단수 모델(audio_mid) 확장과 묶음.

## 검증
- 서버 단위: cargo test 207/207(rtx) + oxcccd 4 + oxhubd 25 + common 24.
- 클라 글루: 19/19(recycle 5 + R2 lifecycle.ptt 1 신규).
- 회귀: conf_basic·ptt_rapid PASS(ccc tap·codec·rtx 무영향).
- 라이브: oxcccd e2e 수집→조회 PASS. 스택(oxhubd+sfud1/2+oxcccd) 기동 유지 중.

---

*author: kodeholic (powered by Claude)*
