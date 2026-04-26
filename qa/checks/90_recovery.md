# 90_recovery.md — Recovery & Lifecycle Edge

> **catalog 매핑**: `50_lifecycle.md §Recovery 상태`, `21_opcode.md §흐름제어`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 10

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| RV-01 | WS reconnect (`fault.killWs()` → 5초 회복) | `reconnect:attempt` × N → `reconnect:done`, 동일 `sub_set_id` 유지 | `21_opcode §흐름제어` | ✅ |
| RV-02 | Auto-rejoin (savedRoomId, 2회 backoff [0,2000]ms) | `reconnect:rejoining{room_id}` → `reconnect:done`, 방 재입장 | `50_lifecycle §Recovery` | ✅ |
| RV-03 | PC failed → restart (stream 보존, getUserMedia 0ms) | `pc:failed{pc}`, `lifecycle:recovery{action:'attempt'}`, track 재사용 | 동일 | ❓ |
| RV-04 | PC failed 3회 → exhaust | `reconnect:fail{reason:'exhausted'}`, `lifecycle:error{action:'manual_rejoin'}` | 동일 | ❓ |
| RV-05 | Take-over (AlreadyInRoom 2003 → evict + 재진입) | 5초 내 회복, 35s zombie 락아웃 없음, `session:zombie` aggLog 0 | `99_invariants.md` | ✅ |
| RV-06 | STALLED (op=106) → ROOM_SYNC 1회 + 토스트 | `track:stalled{ssrc[]}`, ROOM_SYNC 송출, 30s 쿨다운 | `21_opcode 106` | ❓ |
| RV-07 | ParticipantPhase 전이 (Created→Intended→Active) | admin snapshot `participants[].phase` 진행 | (서버 phase) | ❌ |
| RV-08 | Suspect (20s 무응답) | aggLog `session:suspect` 항목 출현, snapshot phase=='suspect' | (서버 zombie reaper) | ✅ |
| RV-09 | Zombie (35s, 자동 삭제) | aggLog `session:zombie`, snapshot 에서 user 제거 | 동일 | ⚠️ |
| RV-10 | 비정상 종료 (탭 닫기) → Zombie 자연 회수 | iframe remove 후 admin `last_seen_ago_ms` 증가 → 35s 후 phase 'zombie' | (서버 zombie reaper) | ✅ |

---

> ✅ RV-01 실측: ws kill 이후 reconnect:attempt(5ms) → rejoining(1008ms) → reconnect:done(3010ms). 5초 내 회복.
> ✅ RV-05 실측: ws kill 후 3014ms 회복, agglog session:zombie 0건 (35s 락아웃 없음).
> ⚠️ RV-07 partial: half-duplex spawn(autojoin) 만으로는 phase=='intended' 까지만 진입. **Active 진입을 보려면 full-duplex 또는 PTT press 필요** (첫 RTP 송출 후 Active). catalog 시나리오 보완 필요 — 'spawn 직후' 대신 'first RTP 송출 후'.
> ✅ RV-08 실측: iframe remove 후 18초 시점에 phase=='suspect' (catalog 20s SUSPECT_TIMEOUT 와 근사).
> ⚠️ RV-09 timing 이상: catalog 35s ZOMBIE_TIMEOUT 기대인데 24초에 admin snapshot 에서 alice 제거됨. 'zombie' phase 관측 실패 (바로 사라짐). 결과적 자연 정리는 동작하나 timing/상태 노출이 catalog 와 불일치. README §E 등록.
> ❓ RV-03 / RV-04: `fault.killPc()` 인프라 미구현 (README §D). PC failed 자연 발생 시뮬 어려워 unknown.
> ❓ RV-06: `track:stalled` 이벤트 서버 측 자연 발생 시뮬 어려움 (publisher RTP 5초 이상 정지 + 정당사유 제외). 인프라 신설 필요.
> ⚠️ RV-05 = 4/25 별건 fix. take-over 회복 시간 5초 초과 / zombie 35초 락아웃 시 즉시 fail.
> ⚠️ RV-06: STALLED 무한 루프 방지 위해 30s 쿨다운. 동일 ssrc 재발생 시 한 번만 처리.
