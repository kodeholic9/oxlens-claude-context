# 세션 컨텍스트: oxtapd 녹화 데몬 — type:recorder + 실 연동 시험 (2026-04-14)

## 목표
- oxsfud participant `type:recorder` 구현 (투명 참가자)
- oxtapd 실 서버 연동 시험 (WS→ICE→DTLS→SRTP→OXR 기록)
- WS split reader/writer 정석 구조로 전환

## 완료 사항

### 1. oxsfud `type:recorder` 투명 참가자 (7파일)
- `config.rs`: `PARTICIPANT_TYPE_USER=0`, `PARTICIPANT_TYPE_RECORDER=1` 상수
- `participant.rs`: `participant_type: u8` 필드, `is_recorder()` 헬퍼, `new()` 파라미터 추가
- `message.rs`: `RoomJoinRequest.participant_type: Option<u8>` (기존 클라이언트 None→0)
- `room.rs`: capacity 체크에서 recorder 제외, `user_count()` 신설, `member_infos()`/`member_ids()` recorder 필터
- `room_ops.rs`: JOIN/LEAVE에서 recorder이면 ROOM_EVENT broadcast 스킵
- `tasks.rs`: zombie reaper에서 recorder leave broadcast 스킵
- `admin.rs`: users/recorders 분리, `"recorders"` 키로 별도 표시, `"rec"` 플래그 포함

### 2. Room `rec` 플래그
- `room.rs`: `rec: AtomicBool` + `set_rec()`/`is_rec()`
- `startup.rs`: `demo_conference`, `demo_video_radio` 방에 `rec=true`
- `system.toml`: `[recording]` 섹션 추가 (base_path, retention_days, segment_*_secs)

### 3. oxtapd 설정 로드
- `config.rs`: `TapConfig::from_config_dir()` — system.toml에서 [hub]+[recording] 파싱
- `main.rs`: `--config-dir` 기반으로 전면 재작성 (CLI 인수 --hub-ws/--jwt-secret/--base-path 제거)
- `Cargo.toml`: `toml = "0.8"` 의존성 추가

### 4. oxtapd 프로토콜 수정
- TRACKS_UPDATE 파싱: action을 최상위에서 읽도록 수정 (기존: 트랙 내부에서 찾음)
- ROOM_EVENT 파싱: `"action"` → `"type"` 필드 (서버 프로토콜: `participant_joined`/`participant_left`)
- `track_writer.rs`: 파일명에 SSRC 포함 (`20260414_143550_F1B2857D_audio.oxr`)

### 5. oxrtc signal_client.rs 전면 재작성 (WS split)
- `PreSplit` — split 전 핸드셰이크 전용 (HELLO → IDENTIFY → ROOM_JOIN)
- `SignalWriter` — struct + method (send_ack, send_heartbeat, send_tracks_ack, send_leave, close). pid 내부 관리
- `SignalReader` — struct + method (recv). select! arm에서 즉시 수신
- `connect_and_join()` — 핸드셰이크 완료 후 split → SignalSession 반환
- `parse_packet()` — Value 파싱 후 Packet 수동 변환 (hub OutboundQueue pid 중복 필드 대응)
- 50ms 폴링 제거 → select! arm 즉시 수신

### 6. 실 시험 결과 (3차)
- 5명 참가자 전원 감지 ✅
- 11개 OXR 파일 생성 (audio 5 + video 5 + screen 1) ✅
- video 52~57KB RTP 데이터 포함 ✅
- 서버 스냅샷: `sub_relayed=20428(+2197)`, gate 전부 open ✅

## 미완료 / 다음 세션 TODO

### 빌드 확인
- SignalWriter/SignalReader 구조 전면 재작성 후 빌드 미확인 (세션 종료)

### supervisor 재시작 루프
- 현재: task 죽으면 로그만 찍고 끝. 재시작 안 함
- 필요: task 죽음 감지 → exponential backoff → 자동 재시작
- 24시간 운영 데몬에 필수

### run() 내부 재접속
- 현재: WS 끊기면 break → 함수 리턴 → task 종료
- 필요: WS 끊김 → writers finalize (세그먼트 경계) → backoff → WS+ICE+DTLS 재수립 → 메인 루프 재진입
- connect_and_join 실패 시에도 재시도 (hub 아직 미기동 대비)

### 49초 지연 확인
- WS split으로 해결됐는지 시험 필요
- 이전: poll_events 50ms sleep → heartbeat request() 중 이벤트 수신 불가
- 이후: select! arm에서 즉시 수신 → 지연 0ms 기대

### hub→oxtapd 명령 채널
- 설계 문서 5절: rec 플래그 변경 → hub가 oxtapd에 녹화 시작/중지 명령
- 방식 미결정 (REST / 내부 WS / gRPC)
- Room rec 플래그 + startup.rs 설정은 완료, 명령 전달 채널 미구현

## 기각된 접근법

- **50ms poll_events**: SignalClient가 WS를 단독 소유하여 select! arm 불가 → sleep(50ms)로 폴링. hub OutboundQueue ACK 미응답 → 이벤트 지연/연결 끊김. WS split이 정답
- **자유 함수 + 날 변수 (C 스타일)**: `send_ack(&mut writer, &mut pid)` — 상태 흩어짐. SignalWriter struct + method가 Rust 정석
- **SignalClient 단일 struct 유지**: split 불가 → select! arm에 WS reader 넣을 수 없음. 핸드셰이크 후 split이 정석
- **hub OutboundQueue 윈도우 꽉 참 분석**: ❌ 오진. 윈도우 가득 차면 타이머 만료 → 연결 끊김이지, 이벤트 지연이 아님

## 지침 후보 (PROJECT_MASTER 반영 검토)

- **oxtapd 재접속 필수**: 24시간 데몬은 WS 끊김/서버 재시작 대비 재접속 루프 필수. 일회성 connect_and_join 금지
- **WS split = 정석**: tokio select!에서 WS 수신하려면 reader/writer split 필수. 폴링 금지
- **상태 묶어서 struct**: writer+pid처럼 항상 같이 다니는 변수는 struct로. 자유 함수에 &mut 난발 금지

---

*author: kodeholic (powered by Claude)*
