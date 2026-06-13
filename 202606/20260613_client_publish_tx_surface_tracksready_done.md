// author: kodeholic (powered by Claude)
# 2026-06-13 클라 발행 트랜잭션 재편 + 표면 정리 + 검은 화면 해결(2겹 원인)

## 세션 성격
0612c(미디어 평면 수정) 연속 세션 후반부. domain 검토(부장 의구심 2건)에서 파생된 구현 +
e2e 검은 화면 디버깅·**해결**. 커밋 5: `8233b74` / `3ad5d00` / `b7dfa00` / `6fdc26a` / `be50c6c`.
★ 디버깅 확인 사항 상세 = **`guide/MEDIA_DEBUG_GUIDE_FOR_AI.md`** (부장 지시로 가이드 승격 —
"미디어 디버깅"/"검은 화면" 키워드 시 로드).

---

## 한 것 (순서)

### 1. domain 검토 (부장 의구심 — trackKey 권위 vs m:{mid} 임시키 / assembleRoom 이름·역할)
- **`m:{mid}` 임시키 = 역사적 잔재 확정**: pipes Map 이 trackId 키 시절 설계에 G7(trackKey)이
  속성으로만 얹힘. 실측 — `LocalEndpoint.getPipe(trackId)` 호출처 0, 모든 조회는 trackKey/source
  선형. **Map 키 = trackKey(발급 즉시 불변)가 정답.** 수신축 track_id 키는 실수요 있어 보존
  (송수신 키 비대칭 = §13.4 의도된 건강한 비대칭).
- **assembleRoom 이름·역할 불일치 확정**: Room 생성 4줄 + 엔진 전역 부수효과(PTT 재생성/관측
  평면). 분해 처방.
- 死코드 4종 발견: removePipe/getPipe(LocalEndpoint)/onFloorEvent(Room)/getMediaElement 중복(pipe).
- ※ 판정 정정 1: addPipe 는 체크 픽스처 시딩용 실사용 — "호출처 0" grep 때 tests/ 제외 실수.

### 2. _publishMany 검토 + 재편 — `8233b74`
- **실결함 3건**(부장 의구심 적중): A) 1·2단계(addPublishTrack/renego) 실패 시 선행분 좀비 무청소
  B) _rollbackPublish 가 _stream/lifecycle 미청소 C) 신규 발행 실패 시 acquire track 고아(장치 점유).
- 재편: `_publishTracks`(wire op 와 1:1 개명) = _stagePipes → _registerTracks → _startRtp +
  **_unwindPublish 단일 청소**(단계 불문 동일). `preserveTracks` 옵션 — migratePublish(롤백 재발행)
  ·engine.publish(BYO 앱 소유)만 보존, SDK acquire 는 stop.
- trackKey 키잉 동반: 임시키/재키잉/학습실패 잔존 경로 폐기. _learnTrackId = 속성 학습만.

### 3. VideoSurface rVFC 게이트 제거 — `3ad5d00` (부장 결정)
- **영구 미노출 기전**: rVFC 는 숨김(offscreen)·백그라운드 video 에서 발화 미보장 — "보이려면
  프레임, 프레임 콜백은 보여야"의 순환 대기. unmute 1회 대기도 동류라 동반 제거.
- 동기 즉시 적용으로 단순화. 보존: 사유 합성(_hiddenBy)/display:none 금지/play 재시도.
- 트레이드오프(실측 대상): 표시 전환 순간 첫 프레임 전 블랙/잔상 가능. **재설계 후보 = opacity
  마스킹**(보이는 상태에선 rVFC 발화 보장 — 순환 끊김).

### 4. 미개시 일괄 — `b7dfa00`
- **onMount 재배선**: join opts 패스스루 폐기 → assembleRoom 이 `device.applyOutput` 직접 주입.
  콜백이 talkgroups _materials 에 묵는 구조 소멸. applyOutput = 신규 mount element 에 sink/글로벌
  mute/volume 즉시 적용(setSinkId "다음 mount" 갭 해소). 경위: Phase 3a v1 이식 잔재(공급자 0
  죽은 배관) — bus 해체 탓 아님. **부장 static 전역화 제안은 기각 합의** — DeviceManager 는 세션
  상태 보유자(_selected/_sinkUnsupported), 전역 접근 = "누가 부르는지 모르는 호출"(bus 폐기 교훈
  역행). 직접 호출의 직관성은 조립부 주입으로 충족.
- **assembleRoom 분해**: 수신축 순수 조립 / _bindPubAxis(발언축+관측 평면) — reconcile pub 축
  흡수 선행.
- attach() Safari/FF 0ms 재대입 경합 가드 / RemoteEndpoint.streamHandle(trackId 당 1핸들 캐시 —
  on/off 짝·대역폭 상태 분열 해소, 소비처 3곳) / shared/ua.js(UA 3곳 통합) / 소생 duplex warn.

### 5. e2e 검은 화면 디버깅 — `6fdc26a` (★부분 해결 — 미종결)
- 증상: CONF-2 "봇 영상 1본 수신" PASS 인데 봇 타일 검정.
- **원인 1 확정 — TRACKS_READY 포팅 누락**: 서버는 TRACKS_UPDATE 때 video 구독 gate 를
  pause(TrackDiscovery 5s, track_ops.rs:277) → 클라 TRACKS_READY 수신 시 resume + **PLI burst**.
  신 SDK 는 상수만 포팅, 송신처 0(v1 은 sdp-negotiator 3곳). gate 는 5s 타임아웃으로 풀려도
  PLI 부재 → 키프레임 없는 델타만 → 검은 타일. 오디오 멀쩡(_gate 는 video 만)·체크 PASS
  (STREAM_SUBSCRIBED=SDP 산물) 전부 정합.
- 수정: _renegotiateSfu 가 재협상 완료 후 TRACKS_READY{room_id} 송신(sfu 당 1회 — 서버 resume
  은 peer 전체 순회).
- **시험 구멍 폐쇄**: CONF 케이스에 framesDecoded>0 단언("happy path 통과=완료 금지" 실증 사례)
  + runner.until async 판정.
- 재실행 결과: 여전히 FAIL(가드가 정확히 잡음) — 원인 1 만으로 미해소 → 아래 6 으로 계속.

### 6. 서버 동반 묶음 — 검은 화면 **해결** + 검토 2건 종결 (`be50c6c`)
- **환경 정합이 0순위였음**: 떠 있던 sfud = 6/10 옛 빌드 고아(wire 커밋 2개 미반영) + supervisor
  자식 296회 crash loop(고아의 포트 점유) + 클라 ES 모듈 캐시(수정이 실행에 미반영 — 포트 변경으로
  우회) + 클라 로그 UTC vs 서버 KST 9h 차. → 정리 후 HEAD 빌드 재기동.
- **원인 2(근본) — codec 등록 불일치**: 배치 발행(engine.publish — 봇/BYO)만 intent codec 폴백
  부재 → undefined → 서버 `VideoCodec::from_str_or_default` **묵시 VP8 등록** → 구독 SDP 가
  pt=109 를 VP8 선언 → 실 인코딩(transport setCodecPreferences 폴백 H264)과 불일치 →
  **pkts 도달+kf 1 인데 frames 0 + 수신측 PLI 폭주**. 라이브 대조 실험(codec 명시=정상/미지정
  =frames 0 + mime VP8)으로 확정. 수정 = `|| "H264"` 한 줄(sugar 와 비대칭 해소).
- **검증: CONF-2/CONF-3 라이브 전체 PASS**(framesDecoded 가드 포함). playwright 로 직접 구동.
- **검토 2건 종결**: ② unpublish {kind:"audio"} = 서버 audio 단수 모델(audio_mid 단일 슬롯)과
  정합 — 제4조 위반 아님(복수 mic 는 서버 모델 확장 별건). ③ TRACK_STATE_REQ ssrc=0 = 무해
  확정(서버 track_id 우선, ssrc 는 ssrc-only 클라 폴백+echo).

### 7. 후반부 — 문서·운영 체계 (커밋: context aa07f2c·f328867·3af0e6c / home 125ba67 / server 005f3a2)
- **마스터 3종 현행화**(부장 지시): MASTER 가이드 표 신설(키워드 로드 의무 단일 출처)·wire 표 6곳
  (auto-select 폐기/G1/per-track mid/pub_select/codec 필수)·마일스톤(신 SDK 재작성 통째 누락 보완)·
  원칙 갱신 2+신규 4·기각 6 추가. WEB(trackKey/rVFC/하이브리드/TRACKS_READY)·SERVER(S-e~g/게이트
  클라 의무/묵시 VP8 함정) 동반.
- **supervisor 고아/crash loop 차단**(서버): common/process.rs 계약 신설 — ① EADDRINUSE → exit 100
  → maybe_restart 즉시 Blocked(+lsof 안내, Backoff 폭주 차단) ② stdin 생명선(spawn piped + env
  opt-in — kill -9 에도 fd 정리로 EOF 동반 종료. opt-in = 수동 기동 /dev/null 즉사 방지).
  부장 검토로 pidfile flock 기각(포트 bind 가 자연 차단 — YAGNI). 라이브 4검증 + 단위 신규 +
  회귀 PASS. ★재기동 race 가 Blocked 분류를 실전 재현(구 동작이면 또 296회 폭주 자리).
- **e2e 타임라인 시각 UTC→로컬**: fmtT 의 toISOString(UTC, Z 잘림) → toTimeString(서버 KST 정합).
  MEDIA_DEBUG §0-4 해소 표기.
- **WEBSDK_GUIDE_FOR_AI 신설**(부장 결정: 단일 파일/guide 하위/시험 작성용): 외부 평면 전수
  카테고리 8종 + 시험 도구(§9) + 커버리지 매핑표(§11 — "전 기능 녹음" 검증 장치) + 공개 표면
  경계 선언(index.js 내부 export 사용 금지). 검증된 샘플만.

---

## 결정 사항 (부장)
- pipes Map = trackKey 키잉 채택 / assembleRoom 분해 / rVFC 게이트 제거(실측 후 재강구).
- DeviceManager static 전역화 기각(상태 보유자 + bus 폐기 교훈).
- 검은 화면 디버깅 확인 사항 → **가이드 승격**(MEDIA_DEBUG_GUIDE_FOR_AI.md).
- 고아 대책: pidfile flock 기각(포트 bind 중복 — 고전 답습 YAGNI) / bind 영구 분류 + stdin 생명선 채택.
- WEBSDK 가이드: 단일 파일·guide/·FOR_AI 관례·AI 시험 작성용(+부장 독자).

## 이월 (우선순위 순)
1. **[서버] codec 미지정 intent 의 묵시 VP8 기본** — offer pt 동적 판별 또는 reject 로 전환
   ("PT 는 동적" 원칙 정합. 클라 폴백으로 봉합됐으나 Android 등 타 클라 동일 함정 가능).
2. **[서버] `NEW rtx` 매 패킷 반복**(ingress_publish.rs:294) — rtx ssrc 인덱스 미등록 → cold path
   + 로그 폭주(1실행 206회). 영상 정상이라 성능/위생 결함.
3. room recycle 블록(pipe 정체 가변·dataset stale) — mid 재사용 재현 = e2e 동반.
4. _rebuildTransport 의 lifecycle.ptt 재바인딩 누락(복구 경로 — _bindPubAxis 합류 검토 동반).
5. rVFC 재설계(opacity 마스킹) — 부장 실측 후.
6. 실기기: 블루투스 분리/연결(②fallback·⑥추종)·iOS Safari·blockedBy 메시지 휴리스틱.
7. 복수 mic(G7) 실지원 시 — 서버 audio 단수 모델(audio_mid) 확장과 한 묶음.
8. index.js 공개/내부 2계층 분리 — WEBSDK 가이드 서문이 경계 선언으로 임시 봉합(별건 후보).

## 검증
- 글루 19/19 PASS (mp_check 75 체크 + c3 TRACKS_READY 단언).
- e2e 라이브: CONF-2 가드 FAIL 로 잔여 원인 실증 → codec 수정 후 **CONF-2/CONF-3 전체 PASS**.

---

*author: kodeholic (powered by Claude)*
