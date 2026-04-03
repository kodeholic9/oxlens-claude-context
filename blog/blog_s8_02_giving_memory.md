# AI에게 기억을 주는 법 — 세션 컨텍스트, SKILL.md, 기각 목록

> AI와 함께 코딩하기 시리즈 #2

AI는 어제 대화를 기억하지 못한다.

이건 비유가 아니라 기술적 사실이다. 새 대화창을 열면 이전 대화의 맥락이 전부 사라진다. 어제 같이 RTCP Terminator를 설계하고 구현하고 검증까지 마쳤더라도, 오늘 새 대화를 시작하면 RTCP Terminator가 뭔지부터 다시 설명해야 한다.

이 프로젝트 — Rust + WebRTC SFU 서버를 바닥부터 만드는 작업 — 에서 세션이 60개가 넘는다. 매 세션마다 처음부터 설명하면 프로젝트가 진행되지 않는다.

그래서 기억을 만들었다.

---

## 세션 컨텍스트 파일

`/repository/context/` 디렉토리에 세션마다 파일을 남긴다. 파일명은 `YYYYMMDD_토픽.md` 형식이다.

```
20260317_rtcp_terminator_sr_translation.md
20260320_simulcast_s3.md
20260321_floor_priority_queue.md
20260323_simulcast_pt_hardcoding_root_cause.md
20260325_pli_governor_resync_removal.md
20260326_simulcast_sdp_telemetry.md
```

하나의 파일에는 정해진 구조가 있다.

**완료된 작업.** 무엇을 했는지, 어떤 파일을 수정했는지, 테스트 결과가 어떠했는지. 3월 25일 PLI Governor 세션을 예로 들면, 신규 파일 `pli_governor.rs`를 만들었고, `ingress.rs`의 PLI 릴레이 경로를 3초 고정 스로틀에서 Governor로 교체했고, 4인 Simulcast 테스트에서 `pli_thrt=0`, `decoded_delta=71+`, `fps=24`, `loss=0%`를 확인했다고 기록되어 있다.

**기각된 접근법.** 이게 핵심이다. 다음 섹션에서 따로 다룬다.

**다음 세션 TODO.** 여기가 기억의 연결고리다. 다음 세션을 시작할 때 이 파일을 읽으면, "어디까지 했고 다음에 뭘 해야 하는지"가 즉시 잡힌다.

세션 간 핸드오프에서 맥락의 약 20%가 유실된다. 세션 컨텍스트 없이 새 대화를 시작하면 유실은 100%다. 20%와 100%의 차이는 프로젝트의 생사를 가른다.

---

## 기각 목록 — 같은 삽질을 두 번 하지 않는 장치

세션 컨텍스트에서 가장 중요한 부분은 "기각된 접근법"이다.

AI는 기억이 없으니까, 지난 세션에서 시도해서 실패한 방법을 다음 세션에서 다시 제안한다. 자신 있는 어투로. "이 방법이 맞습니다"라고. 지난주에 똑같은 방법을 시도해서 실패했는데도.

기각 목록은 이걸 막는 장치다. 실제 기록된 것들을 보자.

```
기각: PT 하드코딩 판별 (is_video_pt(pt) == 96 || 102)
이유: H264 PT가 브라우저/profile마다 다름. 업계 어디서도 안 씀.
```

```
기각: TRACKS_ACK mismatch → RESYNC
이유: subscribe PC 전체 재생성은 SimulcastRewriter 불연속 → decoded_delta=0.
     mismatch tolerate가 정답.
```

```
기각: inactive m-line port=0 + BUNDLE 제외
이유: BUNDLE 태그 이동 → Chrome transport 불일치 에러.
     mediasoup disabled 패턴(port=7, BUNDLE 잔류)이 정답.
```

```
기각: Rust FFI + libwebrtc static link + Android cdylib
이유: 이 조합의 성공 사례 없음. LiveKit도 Kotlin + AAR.
```

```
기각: getStats 폴링으로 simulcast SSRC 추출
이유: Chrome SDP에 SSRC 없고, getStats도 처음엔 안 나옴. 꼼수.
```

이 목록이 없으면 어떻게 될까. 3월 23일에 PT 하드코딩이 근본적으로 틀렸다는 결론을 내렸는데, 기록이 없으면 3월 25일에 AI가 "PT를 기반으로 분기하면 됩니다"를 다시 제안한다. 그리고 또 삽질한다.

기각 목록에 "왜 안 되는지"가 적혀 있으면, 새 세션에서 이 파일을 읽은 AI는 같은 제안을 하지 않는다. 한 번 겪은 삽질을 두 번 겪지 않는 구조다.

---

## SKILL.md — 프로젝트의 헌법

세션 컨텍스트가 날짜별 기록이라면, SKILL.md는 프로젝트 전체를 관통하는 마스터 문서다.

이 프로젝트에서는 `SKILL_OXLENS.md`라는 파일이 그 역할을 한다. 여기에 들어있는 것은 다음과 같다.

**소스 구조.** 서버의 디렉토리 구조, 각 파일의 역할, 시그널링 프로토콜의 opcode 표. 새 세션에서 "ingress.rs 보여줘"라고 하면 AI가 이 파일부터 읽고 맥락을 파악한다.

**아키텍처 원칙.** "SFU는 자체 클록으로 SR을 생성하지 않는다", "PT는 동적이며 하드코딩 금지", "인프라 PLI는 Governor를 bypass한다" — 이런 원칙들이 축적된다. 세션 컨텍스트에서 검증된 원칙만 여기로 올라온다.

**확정된 기각 목록.** 세션 컨텍스트의 기각 사항 중 프로젝트 전체에 영향을 미치는 것들이 여기에 모인다. "절대 하지 말 것" 목록이다. 현재 15개가 넘는다.

처음에는 이 문서 말고 `CLAUDE.md`라는 파일도 있었다. Claude Code라는 도구의 설정 파일이었는데, 이 프로젝트에서는 Claude Code를 사용하지 않는다. 대화 기반으로 작업한다. 두 문서가 동시에 존재하면서 내용이 중복되고, 어느 쪽이 최신인지 헷갈리는 문제가 생겼다. 3월 23일에 `CLAUDE.md`를 삭제하고 `SKILL_OXLENS.md`를 유일한 마스터 문서로 확정했다.

문서가 하나여야 한다. 두 개면 어느 쪽이 맞는지 모르고, 세 개면 아무도 안 읽는다.

---

## SESSION_INDEX.md — 60개 세션의 지도

세션 파일이 60개를 넘어가면 새로운 문제가 생긴다. 어떤 파일을 읽어야 하는지 모른다.

`SESSION_INDEX.md`가 이 문제를 해결한다. 전체 세션을 Phase별로 정리한 인덱스다.

```
Phase 4: RTCP Terminator + SR Translation (0317)
  - rtcp_terminator_sr_translation — RTCP Terminator v1 + SR Translation 완료

Phase 6: Simulcast (0320)
  - simulcast_s1 — Phase 0 구조 준비 + Phase 1 서버측
  - simulcast_s2 — Phase 1 클라이언트측
  - simulcast_s3 — Phase 3 가상 SSRC + SimulcastRewriter + 레이어 전환

Phase 11: Simulcast RTP-First 재설계 (0324)
  - simulcast_rtp_first_redesign — Phase A~C: is_video_pt 제거, stream_map 기반 라우팅
```

"Simulcast 관련 문제가 생겼다"고 하면, AI는 인덱스에서 Phase 6과 Phase 11을 찾고, 해당 세션 파일을 읽는다. 60개 파일을 전부 읽을 필요가 없다.

---

## 이 시스템이 실제로 동작한 순간

3월 26일. Subscribe PeerConnection의 SDP에서 `Failed to process the bundled m= section` 에러가 터졌다. 1편에서 다룬 그 에러다.

새 세션을 시작하고 세션 컨텍스트를 읽으니, 3월 25일 기록에 이런 내용이 있었다.

```
기각: TRACKS_ACK mismatch → RESYNC
이유: subscribe PC 전체 재생성은 기존 정상 스트림까지 파괴.
```

이 기록 덕분에 "subscribe PC를 전체 재생성하자"는 방향은 처음부터 배제됐다. 문제를 SDP의 inactive m-line 처리로 좁힐 수 있었고, 그 결과 mediasoup-client 소스를 역분석하는 데 시간을 집중할 수 있었다.

기각 목록이 없었다면? "RESYNC로 subscribe PC를 다시 만들면 되지 않나?"부터 시도하고, 또 실패하고, 시간을 낭비한 뒤에야 SDP 쪽을 보기 시작했을 거다.

---

## 정리

AI에게 기억을 주는 시스템은 세 층이다.

```
+------------------------------------------+
|  SKILL_OXLENS.md                         |
|  프로젝트 헌법. 구조, 원칙, 확정 기각 목록  |
+------------------------------------------+
          |
+------------------------------------------+
|  SESSION_INDEX.md                        |
|  60개+ 세션의 Phase별 인덱스              |
+------------------------------------------+
          |
+------------------------------------------+
|  YYYYMMDD_토픽.md (세션 컨텍스트)          |
|  완료, 기각, 다음 TODO                    |
+------------------------------------------+
```

새 세션을 시작하면 SKILL.md로 프로젝트 전체를 파악하고, SESSION_INDEX.md에서 관련 세션을 찾고, 해당 세션 컨텍스트를 읽어서 마지막 상태를 복원한다. 이 흐름이 20%의 유실을 만든다. 이 흐름이 없으면 100%다.

이 시스템은 AI 전용이 아니다. 인간 개발자가 팀에 합류할 때도 같은 문서를 읽으면 된다. 다만 AI와 일할 때 특히 효과적인 이유는, AI는 문서를 주면 정말로 전부 읽기 때문이다.

> **다음 편**: [AI와 함께 코딩하기 #3] 쓰레기를 넣으면 쓰레기가 나온다 — AI-Native 텔레메트리가 탄생한 이유

---

### 참고 자료

- [Anthropic — Claude 프롬프트 엔지니어링 가이드](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering) — 컨텍스트 제공 방법 공식 가이드

---

*이 글은 [OxLens](https://oxlens.com) — Rust로 만드는 경량 SFU 서버 프로젝트를 개발하면서 배운 것들을 정리한 시리즈입니다.*
