// author: kodeholic (powered by Claude)

# oxe2epy 본구현-1 완료 보고 — audio conf 수직 관통 (20260627b)

> **상태**: ✅ 완료. `run conf_audio` 한 커맨드로 봇→덤프→검증기→리포트 **PASS**. 라이브 1회 실증.
> **지침**: `20260627b_oxe2e_impl1_vertical_slice.md` / **설계**: `20260627_oxe2e_python_redesign.md`.
> **선행**: spike S1~S4(`20260627a`). / **루트**: `oxlens-sfu-server/oxe2epy/`.

---

## 0. 한 줄 결과

audio full conf 1케이스가 **봇(무가공 송수신)→단일시계 덤프→검증기(등식+4축)→리포트**까지 끝까지 관통한다. `python -m oxe2epy run conf_audio` → **✓ PASS(위반 0)**. "전체 파이썬 회귀 게이트"가 최소형으로 실재 — 이 위에 검증 항목·패킷종류를 함수 추가로 넓혀간다.

---

## 1. 라이브 실증 (서버 가동 중 1회)

```
[oxe2e] conf_audio ✓ PASS — 위반 0
덤프 952 이벤트: send/sig 4, recv/sig 4, send/rtp 472, recv/rtp 472
```
- 2봇(botA 0xA0000001 / botB 0xA0000002) audio full conf, 5초.
- 검증 통과: seq 완전성(결손 0) + ts 단조 + 4축 ssrc-join.
- 덤프 파일 `oxe2epy/dump_conf_audio.jsonl`(단일 시계 jsonl) 남음 — 사후 검증/재현 가능.

> 분업(§6-6): 김과장은 코드 + 검증기 음성시험(pytest)까지 자기 사이클에서 닫음. 라이브는 서버 가동 중이라 1회 돌려 수직 관통 실증(부장님 재확인 = `run conf_audio`).

---

## 2. 구조 (spike 승격 + 본 구현)

```
oxe2epy/oxe2epy/
├── bot/              # spike 승격: transport/signaling/wire/rtp_tx/rtp_rx/bot. 판정 0(무가공)
├── dump/recorder.py  # 단일 시계 이벤트 jsonl (ts_mono, user, dir, kind, raw/json)
├── orchestrator.py   # YAML → 봇 N spawn → 액션(join/connect/publish/wait). 단일 asyncio=단일 시계
├── verifier/         # ★봇 코드 import 안 함 — 덤프 파일만(출처 분리, 공리 1)
│   ├── loader.py     #   jsonl → 구조화(rtp_recv/send, publish_req/resp, tracks_update_add)
│   ├── equations.py  #   ★플러그형 레지스트리(@equation): seq_completeness, ts_monotonic
│   └── identity.py   #   4축 join: client_pub↔server_pub↔server_sub↔client_sub
├── report.py / run.py / __main__.py   # python -m oxe2epy run <scenario>
scenarios/conf_audio.yaml   # 2봇 audio full
tests/test_equations.py     # 검증기 음성시험(메타) — 8 passed
```

---

## 3. 검증 토대 (이번이 잡는 것)

- **seq 완전성**: 수신 ssrc별 seq 집합 min~max 결손 0(재정렬≠손실). spike S3가 토대 증명.
- **ts 단조**: seq 순(송신 순서) ts 비감소.
- **4축 ssrc-join**: client_pub(봇 PUBLISH_TRACKS 요청 ssrc/mid) ↔ server_pub(응답 track_id) ↔ server_sub(상대 TRACKS_UPDATE add owner/ssrc/track_id) ↔ client_sub(봇 수신 RTP ssrc). ssrc 3점 일치 + track_id 2점 일치.

### 검증기 음성시험 (pytest, 메타) — 8 passed
seq 갭/ts 역행/identity 누락(track_id·client_sub) → **FAIL 단언**, 재정렬·완전 join → PASS. "음성에서 안 떨어지는 단언은 단언이 아니다"(묶음 C 재이식).

---

## 4. 부장님 방침("넓혀가기")을 구조에 박은 것

- **검증기 플러그형**: `equations.py` 의 `@equation("name")` 데코레이터 레지스트리. 다음 슬라이스가 `codec_match`/`track_id_returned`/`leak_zero`/`count_eq`/`rtcp_*`/`twcc_*` 를 **함수 1개 등록으로** 켠다.
- **RTCP 훅 자리**: `transport.py` `intercept_rtcp()` = 자리만(NotImplementedError + 본문 위치 주석). RTCP/twcc 검증은 본구현-2.
- **봇 판정 0 불변**: 봇은 recorder 로 raw 적재만. 검증은 verifier 단독(덤프 파일).
- **underscore 격리**: `_send_rtp`/`_handle_rtp_data`/`_set_role` 전부 `transport.py`.

---

## 5. 영향 범위 / 변경

- `oxlens-sfu-server/oxe2epy/` 만(서버 레포 루트 직속, crates 밖 → cargo 무관). 서버/웹/Rust oxe2e 코드 변경 0.
- 신규 의존: pyyaml, pytest (기존 aiortc/websockets/pyjwt 유지).
- `.gitignore`: oxe2epy/.venv, __pycache__, *.egg-info, dump_*.jsonl 제외.
- spike 스크립트(`spikes/`)는 자산 유지(bot.py recorder=optional 이라 호환).

---

## 6. 다음 슬라이스 진입 = 가

- 수직 관통 게이트 실재 → 이제 "폭 넓히기"가 함수/케이스 추가가 됨.
- 본구현-2 후보: 등식 확장(codec/track_id 회신/누수/개수) + RTCP/twcc(훅 본문) + simulcast/PTT/video 봇 경로(rid/SCTP) + 인과 타임라인 + 케이스 매트릭스. 별도 지침.

---

*author: kodeholic (powered by Claude)*
*본구현-1: audio conf 수직 관통 PASS. 검증기 플러그형 + RTCP 훅 자리로 "넓혀가기" 구조화. 라이브 1회 실증.*
