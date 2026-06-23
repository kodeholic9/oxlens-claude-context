// author: kodeholic (powered by Claude)
# 설계 — oxadmin trace (패킷 단위 in/out 진단 탭, 랩 전용)

> 2026-06-15. oxadmin `trace` 서브커맨드 = **랩 전용 패킷 디버깅 탭**.
> oxadmin 운영 CLI(`20260613_oxadmin_design.md`)와 같은 바이너리지만, 성격(랩 전용 · feature flag ·
> 평문 미디어 보안 격리)이 운영 제어/조회와 달라 **독립 설계서**로 둔다.
> 본 문서 = 부장님 ↔ 김대리 합의의 **단일 출처**. 구현(김과장) 입력.

---

## §0. 한 줄 요약

특정 `user + ssrc` 의 RTP/RTCP 패킷이 SFU 안에서 **ingress → (변환/gate) → egress** 까지
어떻게 흐르고 **어디서 죽는지**를 평문 전수로 떠내는 디버깅 탭.
- 상용 바이너리에는 **컴파일 단계에서 부재**(feature flag) — hot-path 오염 + 평문 미디어 유출을 한 경계로 동시 차단.
- 서버(sfud)는 **원시만 토출**, 코덱·프레임 판별 안 함. **분석은 AI(김대리)**.

---

## §1. 목적 / 빈 자리

SFU 는 본질이 "받아서 → 변형 → 보낸다" 인데 그 **중간이 블랙박스**다. 기존 진단은 전부 패킷 단위가 아님:

| 도구 | 보는 것 | 한계 |
|---|---|---|
| Track Dump | 양단 `getStats()` 스냅샷 비교 | 패킷 단위 아님 |
| AGG Log / SfuMetrics | 이벤트·집계 | 개별 패킷 아님 |
| getStats 4축 (MEDIA_DEBUG_GUIDE) | 클라 측 사후 숫자 | 서버 내부 안 보임 |

→ "이 seq 가 ingress 엔 왔는데 egress 엔 왜 없지?" 를 **패킷 짝 단위**로 보는 자리가 빈다.
0613 검은 화면(코덱 오등록)도 이게 있었으면 "ingress=H264 / egress SDP=VP8" 을 그 줄에서 즉시
봤다. **서버 문제냐 단말 문제냐 / P냐 I냐**를 가르는 도구.

---

## §2. 보안 — 이 도구의 본질부터 (1급)

**trace 의 정체 = SRTP 복호 평문 미디어를 외부 스트림으로 뽑는 탭 = 합법 도청 도구.**
hexdump 를 디패킷타이즈하면 실제 음성(Opus)·영상(VP8/H264) 이 복원되고, user/ssrc/room 메타까지
노출된다. 통신비밀·개인정보 정면. **운영에 새는 순간 도청 백도어.**

### 경계 = 바이너리 분리 (단일·완전)

- trace 관련 hot-path 코드 전부 `#[cfg(feature = "trace")]`.
- **상용 default 빌드 = 코드 물리적 부재** → hot-path 침습 0 + 평문 미디어 탭 0. **한 경계로 둘 다.**
- 랩 빌드만 `cargo build --features trace`.

> 코드가 상용 바이너리에 **없으면** 그 기능으로 인한 사고가 날 수 없다. 이게 가장 깨끗한 보안 경계.
> feature flag = 단순 기능 분리가 아니라 **컴파일 격리 = 보안 경계**.

### 유일하게 남는 것 = 빌드 위생

- 상용 릴리스 = trace feature **default off** (명시해야만 on).
- CI 릴리스 잡에서 trace 묻어 나가지 않게.
- 이건 다층 방어가 아니라 **flag 가 의도대로 작동하게** 하는 위생.

---

## §3. 아키텍처 — sfud 직접 빨대

```
터미널 A:  oxadmin trace <user> <ssrc> --in   ─┐
                                                ├─ gRPC TracePackets ─► sfud (랩 빌드)
터미널 B:  oxadmin trace <user> <ssrc> --out  ─┘        (hub 우회)
```

- **hub 우회, sfud gRPC 직접 dial.** 이유 = 패킷 트레이스는 **고빈도**라, hub 이벤트 경로
  (`event_tx`/`bin_event_tx` + OutboundQueue, P0 floor/gate 가 흐르는 평면)에 태우면 **제어 평면을
  진단 폭주로 오염**시킨다. 절대 금지.
- **전용 proto RPC** (기존 `SubscribeAdmin` 재사용 ✗ — 이벤트 타입/필터/라이프사이클 다름):
  ```proto
  rpc TracePackets(TraceFilter) returns (stream TraceEvent);
  message TraceFilter { string user_id = 1; uint32 ssrc = 2; Dir dir = 3; bool detail = 4; }
  ```
- **같은 타겟 다구독 = `tokio::broadcast`.** 터미널 A(`--in`)·B(`--out`) 가 같은 broadcast 구독,
  방향 필터는 각 스트림 task 가 적용. *다른* 타겟 동시 trace 는 reject(디버깅 전용, 한 번에 한 흐름).
- **feature off 빌드** = 핸들러가 `"trace disabled in this build"` 명시 거부(메서드 미등록보다 친절).

---

## §4. 필터 — (user, ssrc, dir) 트리플 1~2개 (제약 없음 = dumb-and-generic)

`oxadmin trace <userA> <ssrcA> <dirA> [<userB> <ssrcB> <dirB>] [--detail] [--bytes N]`
(dir = `--in | --out | --inout`)

- **트리플 1~2개, 각 dir 완전 자유.** 1개 = 한 흐름. 2개 = 두 흐름(흔히 송신 끝 in + 수신 끝 out 으로
  A→B 경로 격리에 쓰지만, **도구가 그 의미를 강제하지 않는다**). `in|out` 고정·2개일 때 inout 배제 같은
  제약 안 둔다 — *어떻게 쓸지 아직 모른다(부장님). 필터는 순수 매칭, "짝/경로" 의미는 도구 밖(AI 분석·
  사용자)이 출력 보고 부여.* = **trace 판 dumb-and-generic.** (섣부른 의미 부여 = 미확정 사용처에 정책
  새기기 → 기각, §10.)
- **방향 필터 hot-path 비용 0** — 각 trace point 는 자기 dir 에 매칭하는 트리플이 있을 때만 emit.
- **타겟 역해석(보조)** — 트리플의 ssrc 가 한 평면만 가리킬 때 반대 평면 자동 확장
  (`lookup_publisher_for_ssrc` / `find_stream_by_vssrc`, simulcast h/l + vssrc). **양 끝을 직접 명시하면
  역해석 불필요(더 정확)** — 역해석은 "한 끝만 줄 때" 보조로 강등.
  → **PTT slot(`slot.virtual_ssrc`) 커버 여부 = 코딩 1순위 확인** (half-duplex 가 trace 의 진짜 가치 지점).
- 1~2 트리플은 **한 `TracePackets` 호출** 안 (같은 타겟을 터미널 2개로 나눠 보던 방식도 그대로 가능).
- **sfu 해소 = (가) 확정** — 1차 단일 sfu 자동 / multi 는 `--sfu <id>` 명시. oxadmin 이 `sfus` REST 로
  addr 획득 후 직접 dial.

---

## §5. Trace Point — SRTP 경계 기준, 짝 보존

"평문으로 받는다" 가 위치를 강제한다. **모든 패킷이 모든 위치에서 결과를 남긴다**(pass/변환/drop+사유) —
누락 0 이라야 `in N개 ↔ out N개` **짝이 맞는다.**

| 위치 | 시점 | result | 파일(추정) |
|---|---|---|---|
| ingress RTP | SRTP **unprotect 후** (평문) | pass | `ingress_publish.rs` |
| ingress RTCP | SRTCP unprotect 후 (평문) | pass | `ingress_rtcp.rs` |
| ingress decrypt_fail | unprotect **실패** (평문 못 만듦) | `decrypt_fail` | unprotect 경로 |
| egress RTP | rewrite 후 · **protect 전** (평문) | pass | `egress.rs` |
| egress RTCP | SR/RR 생성 후 · protect 전 (평문) | pass | `egress.rs` |
| egress gate_drop | `SubscriberGate.is_allowed()==false` | `GATE:<PauseReason>` | gate/fanout 지점 |

- **gate drop** = 암호화 단계로 안 넘어가고 버려지는 패킷. 평문은 있으나 안 나감 →
  `subscriber_gate.rs` 의 `PauseReason`(TrackDiscovery/SimulcastPause/…) 을 사유로 동반.
- **decrypt_fail** = 평문이 안 만들어지는 유일 예외 → 원시 섹션은 **암호문** 그대로 + 사유.

---

## §6. 데이터 구조 — 2섹션 (메타 / 원시)

trace event 하나 = **메타 + 원시**. 핵심: **메타엔 "원시 패킷에 없는, 서버만 아는 처리 맥락"만.**

| 섹션 | 필드 | 비고 |
|---|---|---|
| **메타** | `wall_ts`(us) · `dir`(in/out) · `point` · `result`(pass / GATE:reason / decrypt_fail) · **`origin_seq`** | 패킷 자체엔 없는 것 |
| **원시** | 평문(또는 복호실패 시 암호문) RTP/RTCP **통째** hexdump | seq/ts/pt/marker/ssrc/payload 는 **여기서 AI 가 깐다** |

- **짝 맞추기 = `origin_seq` 하나만 동봉.** rewrite(PTT/simulcast)로 ingress seq ≠ egress seq 라,
  egress 이벤트에 **rewrite 전 원본 seq** 를 동봉. (out seq 는 원시 헤더에 이미 있으므로 메타 중복 ✗.)
  → 터미널 A 의 `in seq` ↔ 터미널 B 의 `origin_seq` 로 join.
- 원시는 **통째**(`--bytes N` 으로만 자름). 코덱 헤더·프레임 타입은 앞쪽이지만, 자름 정책을 기본에
  안 박는다(디버깅 전용, 양은 user+ssrc+dir 로 이미 좁혀짐).

---

## §7. 모드 — simple / detail = 2섹션과 정확히 매핑

별도 개념 아님. **원시 섹션을 붙이냐 마냐:**

- **simple** = 메타 섹션만 (패킷당 한 줄)
  `[wall_ts] DIR point result origin_seq` — 흐름·짝·drop 사유를 한눈에.
- **detail** = 메타 + 원시 hexdump (패킷당 블록) — AI 가 헤더/페이로드까지 깜.

---

## §8. 분석은 AI — 서버는 끝까지 dumb

**서버가 kf 플래그·코덱 판별을 만들지 않는다.** 근거 둘:

1. **dumb SFU 원칙** — hot-path 에 코덱 파싱(VP8 P bit, H264 NAL) 끼우면 지능 침습.
2. **AI-Native ("오염된 정보 주면 AI 도 쓸모없다")** — 디버깅 도구가 **디버깅 대상의 자기 판별을
   믿으면 안 된다.** 서버가 `kf=true` 로 주면, 그 판별이 틀린 게 바로 버그일 때 AI 가 오염된 결론을
   믿는다(0613 코덱 오등록이 정확히 이 함정). 원시를 줘야 AI 가 "이건 H264 NAL 인데 서버는 VP8 로
   다루네" 를 직접 잡는다.

### AI 분석 워크플로 (detail hexdump 입력)

- **RTP 헤더** — 12B 고정 + CSRC + ext → seq/ts/pt/marker/ssrc
- **VP8** — payload descriptor(X/S/PID) → payload header **P bit**(0=keyframe)
- **H264** — NAL type(5=IDR, 7=SPS, 8=PPS → keyframe / 1=non-IDR → P)
- **Opus** — TOC 바이트
- **RTCP** — PT(200=SR/201=RR/206=PSFB) → PSFB FMT(1=PLI), RTPFB(1=NACK) 분해
- **짝** — A `in seq` ↔ B `origin_seq` join → "seq 1234 = ingress IDR 도착 / egress GATE_DROP(TrackDiscovery)" 진단

---

## §9. 활용 시나리오

1. **사람 실시간 tail** — 터미널 2개(`--in`/`--out`) 나란히, 눈으로 대조.
2. **`oxadmin trace … > pkt.log` 리다이렉트 → AI 직독** — 유닉스 파이프라인. detail 을 파일로 떨궈
   김대리에게 붙여 분석.
3. **oxe2e / 김과장 자동 감지**(후속 토픽) — 회귀시험 sfud 를 trace 빌드로 띄우고 시나리오 중
   `oxadmin trace` 자동 실행 → 출력 파싱으로 "ingress N ↔ egress N 짝 / 비정상 gate drop" 자동 단언.
   회귀 gate 의 **미디어 평면 해상도**를 올림(현재 oxe2e 는 구조 라우팅만). **설계가 막지만 않게** 함.

---

## §10. 기각 / 주의 (반복 유혹 차단)

- **서버가 kf/코덱 판별** — dumb 위반 + AI-Native 오염. 원시만, 분석은 AI.
- **`origin_seq` + `out_seq` 쌍 동봉** — 과함. `origin_seq` 만(out 은 원시 헤더에 있음).
- **detail 기본 64B 자름** — 기각. 통째(`--bytes` 로만 조정).
- **hub 경유 중계** — 제어 평면 폭주 오염. sfud 직접 빨대.
- **`SubscribeAdmin` 재사용** — 이벤트 타입/필터/라이프사이클 다름. 전용 RPC.
- **다층 방어**(런타임 이중 옵트인 / 부팅 배너 / healthz 알람) — "상용에도 코드 들어간다" 는 잘못된
  전제 위 자물쇠. **바이너리 분리가 완전하면 군더더기.** feature flag + 빌드 위생으로 종결.
- **hot-path 런타임 atomic gate 상시 컴파일** — 랩 전용이라 상용 hot-path 침습 근거 0. `#[cfg]` 로
  상용 부재가 정답("가볍다" 는 "심어도 된다" 의 근거가 못 됨).
- **동시 다중 타겟** — 단일 타겟(같은 타겟 N구독은 broadcast 로 OK).
- **필터에 "짝/경로" 의미 강제**(2 트리플 = in|out 고정 등) — 사용 패턴 미확정. 필터는 순수 매칭, 의미는
  도구 밖. dir 완전 자유(§4).

---

## §11. 미확정 (코딩 시 확인 — 설계 결정은 전부 섰음)

- **[확인] PTT slot 역해석** — `(user,ssrc)` → `slot.virtual_ssrc` 까지 자동 확장되는지 코딩 1순위.
- **[확인] trace point 실제 함수/파일명** — §5 표는 PROJECT_SERVER 기준 추정. 김과장 cargo 인루프 확정.

> sfu 해소(가)·필터 자유·feature flag·2섹션·origin_seq 짝·분석 AI — **설계 결정 종결.**

---

## §12. 산출물

- **proto**: `TracePackets(TraceFilter) returns (stream TraceEvent)` + `TraceEvent{meta, raw}`.
- **oxsfud** (전부 `#[cfg(feature="trace")]`): trace target(broadcast) state + SRTP 경계 6 trace point
  + ssrc→stream 역해석 + gRPC `TracePackets` 핸들러.
- **oxadmin**: `trace` 서브커맨드(gRPC 스트림 클라 — tonic 의존 신규) + simple/detail 라인 렌더 +
  `run()` 내 특수 분기(`shutdown` 패턴 참고).
- **Cargo**: `trace` feature 정의 + 릴리스 default off.
- **(후속)** oxe2e trace 빌드 연동 — 별 토픽.

---

*author: kodeholic (powered by Claude)*
