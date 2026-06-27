// author: kodeholic (powered by Claude)

# oxe2e 회귀 강화 — 작업 지침 (20260626c)

> **수행**: 김과장(Claude Code) / **결정**: 부장님(kodeholic)
> **설계 근거**: `20260626b_oxe2e_test_design.md`(이 지침은 그 W1~W5를 실행 스텝으로 푼다). 현행 위치 = `20260626a_oxe2e_currency_survey_done.md`.
> **성격**: 구현 작업. 단 **단계마다 빌드 통과 + 기존 회귀 green 유지**가 게이트. 한 번에 한 묶음, 정지점마다 보고→검토→커밋.

---

## §0 의무 점검 (시작 전)

1. 설계서 `20260626b` §3(분류→계층)·§4(W1~W5)·§8(기각) 숙지. **3층(framesDecoded/jb)은 안 건드린다.**
2. **W1~W3·W4a·W5 = 봇·judge·유닛 한정(서버 무변경).** **W4b(build_tracks_update 추출)만 서버 코드 리팩터 → 별도 GO 전까지 착수 금지.**
3. 새 도구·프레임워크 0. 케이스 남발 0. 봇 "정교화" 0(무가공이 정직).
4. 각 묶음 끝 = `cargo test` + `oxe2e` 커버 시나리오 PASS 확인 → **커밋 전** 보고.
5. 2회 같은 막힘 → 중단·보고.

---

## §1 컨텍스트 (한 문단)

봇이 가짜 ssrc로 서버 가드를 우회해(0625 §1.4) 회귀가 거짓 green이었고, judge 판정이 `count==0`이라 검은화면도 1패킷이면 통과했다. **봇을 정직화(W1)·원료 적재(W2)하고 judge를 등식으로 올려(W3) SFU가 만든 것을 2층에서 잡고, 비어있던 1층 통증자리(W4)를 채우고, 검증기를 음성으로 못박는다(W5).** 수신단(NetEQ/디코딩)은 3층으로 넘긴다.

---

## §2 전제 (설계서에서 확정 — 재확인 불요)

- 봇 송신 = canned(N 결정적), `RtpMini`(oxrtc rtp_receiver.rs:8-15)가 seq/ts/marker/pt 다 깐다(봇이 버릴 뿐).
- judge `evaluate`(judge/mod.rs:30) 이행=`count==0`(:55), 누수(c, :64) 음성 유지. caching/gating/교차 4 = 채점자 봇 밖, 안 건드림.
- 현행 toml 5개 = ①②③④⑤⑦⑧⑨ 커버, ⑥ 레이어전환만 빔.

---

## §3 작업 스텝 (안전순 — 묶음 = 정지점)

### ■ 묶음 A — W1 봇 정직화 (정지점 A)

- **A1.** `oxe2e/src/bot/mod.rs:492-505` simulcast entry `ssrc`가 `0`인지 확인(0625 S6 반영분). **모든** PUBLISH_TRACKS intent ssrc를 전수 점검 — 실클라 SDP enrich 계약과 다른 우회값(가짜 non-zero 등)이 남았으면 제거. non-sim=실 ssrc, sim=0.
- **게이트**: `cargo build`. `oxe2e scenario scenarios/simulcast_basic.toml` PASS(새 서버 가드 `!is_sim`과 짝 — 0625 §11 확인분 유지). conf_basic/ptt_rapid 무영향.
- **완료정의**: 봇이 서버 가드를 우회하는 비정상 값 0. 봇 송신 계약 == 웹 클라 계약.
- **보고**: 변경 파일 + 점검 결과. → 검토 → 커밋.

### ■ 묶음 B — W2 봇 수신 원료 적재 (정지점 B)

- **B1.** `bot/media.rs:251-255` `RecvLog`에 **per-ssrc seq 리스트(+ts)** 필드 추가(counts 병행 유지). 무가공 — 해석 없이 적재.
- **B2.** `bot/media.rs:282-287` 수신 루프에서 `rtp.seq`/`rtp.ts`를 B1 필드에 push(현 `rtp.ssrc`만 쓰던 자리).
- **B3.** `bot/mod.rs:52-75` `BotResult`에 대응 필드 추가. `take_recv`(mod.rs:582) + 채우는 두 지점(mod.rs:294-307 conf, :464-476 floor)에서 전달.
- **게이트**: `cargo build` + `cargo test -p oxe2e`. 5 시나리오 전부 기존대로 PASS(judge 미변경이라 동작 불변).
- **완료정의**: judge가 봇별·ssrc별 수신 seq 집합·ts 열을 읽을 수 있다(아직 안 씀).
- **보고**: 변경 파일 + BotResult 새 스키마. → 검토 → 커밋.

### ■ 묶음 C — W3 judge count→등식 + W5 음성 픽스처 (정지점 C) ★핵심

> 각 등식 = (1) 판정 추가 + (2) 그 등식이 깨진 픽스처에서 FAIL하는 `#[cfg(test)]`(W5)를 **짝으로**. "음성에서 안 떨어지는 단언은 단언 아님."

- **C1. seq 집합 완전성**(②전달): `judge::evaluate` (a)이행을 `count==0` → **수신 ssrc별 seq 집합 S에 min(S)~max(S) 결손 0**. 재정렬≠손실 → **집합**으로(도착 단조 아님). + 음성: seq 갭 주입 픽스처 → FAIL.
- **C2. 개수 등식**: |수신| == 봇 송신(canned N) − gated. **gated까지 결정적인 케이스만**(정적 conf 성립 / 화자전환은 약한 단언으로 격리). + 음성: 1패킷 누락 픽스처 → FAIL.
- **C3. ts 단조/변환**: ts 단조. α(conf relay)=원본 동일 / PTT=translate_rtp_ts. + 음성: ts 역행 픽스처 → FAIL.
- **C4. track_id 회신**(식별 4축 — ★0625 버그 직격): PUBLISH_TRACKS 응답 `tracks[].track_id`가 client_pub.mid마다 실렸나. + 음성: 응답 track_id 누락 픽스처 → FAIL.
- **C5. TRACKS_READY 존재**(①시그널링): JOIN→PUBLISH_TRACKS→TRACKS_READY opcode 순서 + TRACKS_READY 도달(검은화면 근본). + 음성: TRACKS_READY 삭제 픽스처 → FAIL.
- **C6. codec 정합**(④): server.codec == client 선언 == 수신 pt(track-identity codec_mismatch 차용). + 음성: codec mismatch 픽스처 → FAIL.
- **유지**: 누수(c)·caching·gating·교차 4 — 안 건드림.
- **게이트(각 C마다)**: `cargo test -p oxe2e`(음성 픽스처 포함) + `oxe2e` 5 시나리오 PASS. **0625 simulcast track_id 시나리오에 C4 verify 켜면 — 봇 정직화(묶음 A) 안 된 옛 봇에선 FAIL, 정직 봇에선 PASS**(failability 실증).
- **완료정의**: 검은화면(forward 0/TRACKS_READY 누락)·track_id 미회신·codec mismatch가 각각 다른 FAIL 메시지. `count==0` 단독 PASS 소멸. 각 등식이 음성 픽스처 보유.
- **보고**: C1~C6 각 등식 + 짝 음성 테스트. **C는 한 등식씩 정지점 가능**(C1 보고→검토→C2…)이거나 묶음 보고 — 부장님 택. → 검토 → 커밋.

### ■ 묶음 D — W4a 1층 release 순서 등식 (정지점 D, 독립·병행 가능)

- **D1.** `oxsfud` `peer.rs:1002` `release_subscribe_track` 본문 순서(mid_map.remove→streams 정리→mid_pool.release)를 `#[cfg(test)] mod tests`로. **3중 정합**(mid_map↔SubscriberStreamIndex↔mid_pool) 연산 후 일치. 순수 메서드(외부 의존 없음).
- **D2.** 음성(P-7): 순서를 뒤집은/한 단계 누락 픽스처 → 유닛 FAIL. ← **재입장 미노출 버그 자리** 직격.
- **게이트**: `cargo test -p oxsfud`(기존 211+ 유지 + 신규 PASS). 서버 동작 무변경(테스트만).
- **완료정의**: release 순서가 틀린 상태가 유닛에서 빨간불.
- **보고**: 신규 유닛 + 음성 픽스처. → 검토 → 커밋.

### ■ 묶음 E — W4b build_tracks_update 추출 + 조립 등식 (★별도 GO 전까지 착수 금지)

> **프로덕션 코드 리팩터.** 부장님 별도 사인 후. 여기 적되 GO 없이 시작 안 함.

- **E1.** `build_tracks_update` 순수 함수 신설 — add 경로 `json!` 인라인 5중복(track_ops.rs:270,490 / helpers.rs:294,307,536)을 한 함수로 추출(REQ-1.3). 입력=상태, 출력=Vec<Value>. `build_remove_tracks`(helpers.rs:434) 짝.
- **E2.** 조립 등식 유닛: "이 상태 → 이 페이로드"(transform=1층). promote 두 경로 수렴 = transform(상태→페이로드) 1층 + trigger(첫 RTP 시점 통지) 2층(C5와 연결).
- **게이트**: 추출 전후 `oxe2e` 5 시나리오 + `cargo test -p oxsfud` 동일 PASS(리팩터=동작 불변 증명). 회귀 보존 체크리스트(설계서 §7).
- **완료정의**: 인라인 0, 조립이 순수 함수 1곳, 두 경로 동일 상태→동일 페이로드 유닛 증명.

---

## §4 변경 영향 범위

| 묶음 | 레포/파일 | 서버 동작 |
|---|---|---|
| A | oxe2e bot/mod.rs | 무관(봇 송신) |
| B | oxe2e bot/media.rs, mod.rs | 무관(봇 수신 기록) |
| C | oxe2e judge/mod.rs, scenario verify_* | 무관(판정) |
| D | oxsfud 유닛(peer.rs #[cfg(test)]) | **무변경**(테스트만) |
| E | oxsfud track_ops.rs/helpers.rs | **변경(리팩터)** — 별도 GO |

→ A~D는 서버 코드 0줄. E만 서버 리팩터.

---

## §5 운영 룰

1. **정지점마다**: 작업 완료 → 보고서(변경 파일+요약) → 부장님 diff 검토 → **GO 후 커밋**(커밋을 검토 앞에 두지 않는다).
2. **context 레포 commit 금지** — 부장님이 직접. 본 지침/보고 파일 *작성*만.
3. **회귀시험**: 각 묶음 커밋 전 `oxe2e scenario scenarios/<커버>.toml` PASS. 서버 영향 묶음(E)은 release 빌드 + sfud 재기동 필요할 수 있음.
4. 판단 갈리면 묻기 전 정석 결정, 진짜 갈리는 것만 질문.

---

## §6 회귀시험 (커밋 전 게이트)

- **봇/judge 묶음(A~C)**: `cargo test -p oxe2e` + `oxe2e scenario scenarios/{conf_basic,ptt_rapid,simulcast_basic,duplex_cache,telemetry_collect}.toml` 전부 PASS. **음성 픽스처(C·D)는 깨진 입력에서 FAIL 확인까지가 PASS의 일부.**
- **유닛 묶음(D)**: `cargo test -p oxsfud` 기존 + 신규 PASS.
- **서버 묶음(E)**: 위 전부 + 리팩터 전후 동일 결과.

---

## §7 기각 (이 작업에서 안 함)

- 3층(framesDecoded/jb/NetEQ/디코딩) 자동화.
- exact diff / 풀 DST / 결함주입(후속).
- 1층 297 외 영역 더 쌓기 — W4 두 칸만.
- ⑥ 외 케이스 추가 — 등식 격상 후 ⑥만.
- E를 별도 GO 없이 착수.

---

## §8 순서 / self-check

- [ ] 설계서 §3·§4 숙지, 3층 안 건드림 인지.
- [ ] A(봇 정직) → B(원료) → C(judge 등식+음성) → D(1층 release, 병행) → **E는 GO 후**.
- [ ] 각 묶음 = 빌드+회귀 게이트 통과 후 커밋 전 보고.
- [ ] C·D 등식마다 음성 픽스처 짝(P-7).
- [ ] 서버 무변경(A~D) vs 리팩터(E) 경계 준수.

---

*author: kodeholic (powered by Claude)*
*작업 지침. W1~W5 실행 스텝. E(build_tracks_update 추출)만 서버 리팩터 = 별도 GO. 커밋은 정지점마다 검토 후.*
