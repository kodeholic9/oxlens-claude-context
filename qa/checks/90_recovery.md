# 90_recovery.md — Recovery & Lifecycle Edge

> **catalog 매핑**: `50_lifecycle.md §Recovery 상태`, `21_opcode.md §흐름제어`
> **마지막 갱신**: 2026-04-26 (Phase 67 §F: RV-09 timing catalog 보정 — SUSPECT 15s, ZOMBIE 20s, zombie phase 노출 기대 제거)
> **항목 갯수**: 10

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| RV-01 | WS reconnect (`fault.killWs()` → 5초 회복) | `reconnect:attempt` × N → `reconnect:done`, 동일 `sub_set_id` 유지 | `21_opcode §흐름제어` | ✅ |
| RV-02 | Auto-rejoin (savedRoomId, 2회 backoff [0,2000]ms) | `reconnect:rejoining{room_id}` → `reconnect:done`, 방 재입장 | `50_lifecycle §Recovery` | ✅ |
| RV-03 | PC failed → restart (stream 보존, getUserMedia 0ms) | `pc:failed{pc}`, `lifecycle:recovery{action:'attempt'}`, track 재사용 | 동일 | ❓ |
| RV-04 | PC failed 3회 → exhaust | `reconnect:fail{reason:'exhausted'}`, `lifecycle:error{action:'manual_rejoin'}` | 동일 | ❓ |
| RV-05 | Take-over (AlreadyInRoom 2003 → evict + 재진입) | 5초 내 회복, 20s zombie 락아웃 없음, `session:zombie` aggLog 0 | `99_invariants.md` | ✅ |
| RV-06 | STALLED (op=106) → ROOM_SYNC 1회 + 토스트 | `track:stalled{ssrc[]}`, ROOM_SYNC 송출, 30s 쿨다운 — trigger: `__qa__.fault.publisherRtpStop({kind})` → ~5초 후 서버 STALLED checker | `21_opcode 106`, `40_qa_ui §Fault Injection` | ⬜ |
| RV-07 | ParticipantPhase 전이 (Created→Intended→Active) | admin snapshot `participants[].phase` 진행. **Active 진입은 첫 RTP 송출 후** (full-duplex 트랙 또는 PTT press 필요) | (서버 phase) | ⚠️ |
| RV-08 | Suspect (15s 무응답) | aggLog `session:suspect` 항목 출현, snapshot phase=='suspect' | (서버 zombie reaper) | ✅ |
| RV-09 | Zombie (20s, 자동 삭제) | aggLog `session:zombie`, snapshot 에서 user 제거. **zombie phase 는 대개 관측 불가** — reaper 한 cycle 안 전이+삭제되어 admin snapshot 노출 시간 0 (관측성 구조). 사라짐을 확인하는 것이 정답 | 동일 | ✅ |
| RV-10 | 비정상 종료 (탭 닫기) → Zombie 자연 회수 | iframe remove 후 admin `last_seen_ago_ms` 증가 → ~20s 후 user 제거 | (서버 zombie reaper) | ✅ |

---

> ✅ RV-01 실측: ws kill 이후 reconnect:attempt(5ms) → rejoining(1008ms) → reconnect:done(3010ms). 5초 내 회복.
> ✅ RV-05 실측: ws kill 후 3014ms 회복, agglog session:zombie 0건 (35s 락아웃 없음).
> ⚠️ RV-07 partial: half-duplex spawn(autojoin) 만으로는 phase=='intended' 까지만 진입. **Active 진입을 보려면 full-duplex 또는 PTT press 필요** (첫 RTP 송출 후 Active). catalog 시나리오 보완 필요 — 'spawn 직후' 대신 'first RTP 송출 후'.
> ✅ RV-08 실측: iframe remove 후 약 18초 시점에 phase=='suspect' (SUSPECT_TIMEOUT=15s + REAPER_INTERVAL=5s polling 변동 안 일치).
> ✅ RV-09 (Phase 67 재판정, 4/26): catalog 35s 기다림은 4/25e 이전 옥 값 잔재. 현 ground truth = `config.rs` 차 확인 완료 — SUSPECT_TIMEOUT_MS=15_000, ZOMBIE_TIMEOUT_MS=20_000, REAPER_INTERVAL_MS=5_000. 실측 24s = 20+(0~5) polling 변동 이론치. zombie phase 미관측은 reaper 가 phase=Zombie 전이 직후 endpoints.remove() 로 삭제하면서 admin snapshot 노출 시간이 0 이라 나타나는 관측성 구조. 자연 정리 자체는 정상 동작. 결함 아님.
> ❓ RV-03 / RV-04: `fault.killPc()` 인프라 이미 구현 (Phase 65 §D). PC failed 자연 발생 시뮬 가능. **시험 미실행** — 다음 cycle 에서 검증 → 상태 ❓→✅/⚠️.
> 📝 RV-06 (Phase 65 §D, 4/26): fault hook 인프라 신설 (`fault.publisherRtpStop({kind})`). pipe.track.stop() 으로 RTP 정지 + SDK lifecycle 변경 없음 → 서버 STALLED checker 가 ~5초 후 op=106 trigger. 다음 cycle 에서 검증.
> ⚠️ RV-05 = 4/25 별건 fix. take-over 회복 시간 5초 초과 / zombie 20초 락아웃 시 즉시 fail.
> ⚠️ RV-06: STALLED 무한 루프 방지 위해 30s 쿨다운. 동일 ssrc 재발생 시 한 번만 처리.
