# 리팩토링 2차 — 함수 정리, 조기 리턴, 중복 제거

> 이전 세션: 리팩토링 1차 (handler 분할 + ingress 함수 분해) → v0.6.1
> 원칙: 동작 변경 Zero. 코드 정리만.

---

## 1차 완료 사항

- handler.rs 1,753줄 → handler/ 7파일 (최대 548줄)
- ingress.rs handle_srtp 400줄 → 124줄 + 4메서드 추출
- README.md 전면 현행화, CHANGELOG v0.6.1
- doc/SESSION_REFACTOR2_20260320.md에 상세 분석 있음 (잘못된 위치지만 내용은 유효)

---

## 2차 작업 — 공통 헬퍼 3개 추출이 핵심

### (A) PLI burst spawn 헬퍼 → helpers.rs

5곳에서 거의 동일한 PLI burst 코드 반복:
- track_ops.rs: handle_subscribe_layer, handle_camera_ready, handle_mute_update
- floor_ops.rs: handle_floor_request
- ingress.rs: fanout_simulcast_video

delays 배열만 다름: [0,150] / [0,500,1500] / [0,200,500,1500]

→ `spawn_pli_burst(participant, ssrc, pub_addr, socket, delays)` 추출

### (B) subscribe tracks 수집 헬퍼 → helpers.rs

3곳에서 "다른 참여자 트랙 (rid=l 제외, video→가상 SSRC)" 동일 로직:
- room_ops.rs: handle_room_join (existing_tracks)
- room_ops.rs: handle_room_sync (subscribe_tracks)  
- track_ops.rs: handle_tracks_ack (resync_tracks)

→ `collect_subscribe_tracks(room, exclude_user) -> Vec<serde_json::Value>` 추출

### (C) PTT silence flush 헬퍼 → helpers.rs

3곳에서 동일:
- floor_ops.rs: handle_floor_release
- room_ops.rs: handle_room_leave
- room_ops.rs: cleanup

→ `flush_ptt_silence(room)` 추출

---

## 2차 작업 — 파일별 세부

### room_ops.rs (548줄)
- handle_room_join ~140줄 → (B) 적용 + 보일러플레이트 정리
- handle_room_leave + cleanup PTT 코드 중복 → (C) 적용
- 조기 리턴 패턴 (session→room→participant 4줄 체인 반복)

### track_ops.rs (547줄)
- handle_tracks_ack expected set + resync_tracks → (B) 적용
- PLI burst spawn 3곳 → (A) 적용

### floor_ops.rs (249줄)
- handle_floor_request PLI burst → (A) 적용
- handle_floor_release silence flush → (C) 적용

### ingress.rs (1,305줄)
- fanout_simulcast_video PLI burst → (A) 적용 검토 (ingress는 &self 메서드라 helpers.rs 직접 못 씀 → 별도 판단)
- handle_nack_block SSRC 역매핑 → resolve_nack_ssrc() 추출 선택적

### lib.rs (491줄)
- run_floor_timer + run_zombie_reaper → tasks.rs 분리
- load_env_file, env_or, detect_local_ip, create_default_rooms → startup.rs 분리
- broadcast_to_room_all → handler/helpers.rs broadcast_to_room과 중복 통합

---

## 진행 순서

1. helpers.rs에 (A)(B)(C) 추가 → 빌드
2. room_ops.rs 적용 → 빌드
3. track_ops.rs 적용 → 빌드
4. floor_ops.rs 적용 → 빌드
5. ingress.rs (A) 적용 판단 → 빌드
6. lib.rs 분리 → 빌드

---

## 주의

- PLI burst helpers.rs 추출 시 delays가 함수마다 다름 → &[u64] 파라미터
- ingress.rs는 impl UdpTransport이라 handler/helpers.rs 직접 호출 불가 → 별도 판단
- lib.rs broadcast_to_room_all은 run_floor_timer/run_zombie_reaper에서 사용 → 통합 시 import 경로 주의
- 매 파일 수정 후 cargo build --release 확인
