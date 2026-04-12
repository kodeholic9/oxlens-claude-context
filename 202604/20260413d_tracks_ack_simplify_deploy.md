# 20260413d — TRACKS_ACK 서버 단순화 + 배포 스크립트 개선 + nginx WS 경로 수정

## 요약

서버 do_tracks_ack SSRC 비교/mismatch 경로 전량 제거 (190→83줄). 배포 스크립트 전면 개선 (oxsfud+oxhubd 이중 바이너리 관리). RPi 배포 시 nginx WS 프록시 경로 불일치 발견 및 수정.

---

## 완료 항목

### 1. do_tracks_ack 단순화 (track_ops.rs)
- SSRC 비교/mismatch 경로 전량 제거 (190→83줄, -107줄)
- RESYNC 영구 폐기 후 synced/mismatch 두 경로가 동일 동작 → 단일 경로 통합
- 남은 것: gate.resume_all() + PLI burst + record_stalled_snapshot() + `{ synced: true }`
- expected SSRC 집합 구축 (gated_publishers, half-duplex virtual SSRC 포함 ~50줄) 삭제
- mismatch 경로 (중복 gate.resume_all + PLI burst ~45줄) 삭제

### 2. TracksAckRequest 하위 호환 (message.rs)
- `ssrcs: Vec<u32>` → `#[serde(default)]` 추가
- 서버는 더 이상 SSRC 비교 안 함. 하위 호환용 유지

### 3. ack_mismatch 메트릭 제거 (sfu_metrics.rs)
- `TrackMetrics`에서 `ack_mismatch: Counter` 삭제
- track_ops.rs의 `METRICS.get().track.ack_mismatch.inc()` + agg-log 삭제

### 4. deploy-oxlens.sh 전면 개선
- oxsfud + oxhubd 이중 바이너리 관리 (시작: sfud→hubd, 종료: hubd→sfud)
- `.env` 의존 제거 → `RUST_LOG` 인라인 + `--config-dir config/` 명시 전달
- `protobuf-compiler` 빌드 의존성 추가
- 빌드 실패 감지 보강 (tee + target 바이너리 존재 이중 확인)
- 로그 로테이션 (7일 초과 자동 정리)
- `log-sfu` / `log-hub` 개별 로그 명령
- PID 파일 2개 (oxsfud.pid, oxhubd.pid)
- status에 config 날짜 + 디스크 사용량 표시

### 5. nginx WS 프록시 경로 수정 (RPi)
- 문제: hub base_path="/media"로 WS가 `/media/ws`에 마운트 → nginx `/ws` → `localhost:1974/ws` (404)
- 수정: nginx `proxy_pass http://localhost:1974/media/ws;`
- oxlens.com 서버 블록만 수정 (jjangnan.xyz는 별도)

---

## 수정 파일 목록

| 파일 | 변경 | 상태 |
|------|------|------|
| `crates/oxsfud/src/signaling/handler/track_ops.rs` | do_tracks_ack 단순화 (190→83줄) | ✅ |
| `crates/oxsfud/src/signaling/message.rs` | TracksAckRequest.ssrcs #[serde(default)] | ✅ |
| `crates/oxsfud/src/metrics/sfu_metrics.rs` | ack_mismatch 제거 | ✅ |
| `deploy-oxlens.sh` | 전면 개선 (2 바이너리, 로그 로테이션 등) | ✅ |
| RPi `/etc/nginx/sites-enabled/oxlens.com` | proxy_pass /media/ws 경로 수정 | ✅ |

---

## 교훈

- **bash `if !` 함정**: `if ! func; then`으로 호출하면 함수 내부에서 `set -e`가 비활성화됨. `cargo build | tail` 파이프 실패가 무시되어 빌드 실패인데도 "빌드 완료" 출력. 바이너리 존재 여부로 이중 확인 필요
- **PID 파일명 마이그레이션**: 구 스크립트 `oxsfu.pid` → 신 스크립트 `oxsfud.pid`. is_running()이 못 찾아서 프로세스 미정지 → `Text file busy`. 일회성이라 수동 처리
- **nginx proxy_pass 경로**: hub의 WS가 `/media` 하위에 nest되어 실제 경로가 `/media/ws`. 정석은 WS를 루트에 merge하는 것이나, nginx 수정으로 빠르게 해결
- **로그 이중 생성**: nohup stdout 리다이렉트 + tracing-appender 자체 파일 로깅 = 이중. nohup 쪽은 startup 에러 안전망

## 기각된 접근법

- **서버 WS 루트 마운트 (`merge` 대신 `nest`)** — 정석이지만 빌드+배포 필요. nginx 수정이 더 빠르고 서버 변경 없음. 향후 정리 시 전환 가능
- **`{ synced: true }` 응답 제거** — 클라이언트 signaling.js에서 console.log만 찍고 있어 제거 가능했으나, 부장님 판단으로 유지

---

*author: kodeholic (powered by Claude)*
