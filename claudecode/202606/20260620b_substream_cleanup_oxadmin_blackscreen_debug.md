# 세션 기록 2026-06-20b — SubscriberStream 회수 근본화 + oxadmin 가시화 + 검은화면 디버깅(미해결)

> 0620a(egress_ssrc 단일화) 후속. half 누적 근본 수정 + reindex 청산 / oxadmin 트랙 상태 가시화 + trace --secs / 클라 subscribe mid 재사용(Duplicate a=mid) / **검은화면(half PTT 콜드스타트) 디버깅 — 미해결**.

---

## 1. 한 일 (커밋별)

### 1-1. 근본 수정 — unpublish=SubscriberStream 회수 + reindex 청산 (서버 `82cb214`)
- 0620a 미해결 "half pub → Direct 누적" 근본: **unpub(PUBLISH_TRACKS remove)이 mid_map/mid_pool 만 풀고 SubscriberStream 보존** → 다음 pub 이 새 mid 뽑아 누적.
- 부장 지침: "switch 아닌 unpublish 인데 트랙 왜 유지? mid 만 보존(재활용)하고 stream 은 제거." → 정석.
- `track_ops.rs` `handle_publish_tracks_remove`: full+half 모두 `release_subscribe_track`(mid_map+stream+mid_pool 통합 회수). switch(`TRACK_STATE_REQ`)만 캐싱 보존.
- **e94339e(0620a) egress reindex 우회 폐기** — 근본(unpub=stream 제거)이 이를 불요화: `add_subscriber_stream` reindex 분기 / `reindex_subscriber_egress` / `with_reindexed_egress` 제거. (republish=remove→add 라 add 경로가 새 stream+정확 egress 자연 생성.)
- 검증: oxe2e 5/5 + **lab 6단계 실측**(full→unpub→republish→half switch→half unpub→half pub) SUB_STREAMS **4 유지(누적 0)** + 단위 207.

### 1-2. oxadmin 트랙 상태 가시화 + trace --secs (서버 `f9980a3`)
- `oxadmin room` 을 trace 없이 흐름 즉판:
  - **`--out` active `(*)`**: per-slot `rewriter.speaker`(release 시 정리) AND 등록 track half AND subscriber≠발화자 self. Direct=publisher full+alive. (3단계 정교화: has_publisher latch→rewriter.speaker→half gate→self 제외)
  - **`speaking:`** floor 발화자.
  - **PKTS/DROP**: 누적 in(`rtp_in`)/in_drop(gated+pending), out(`rtp_relayed`)/out_drop. 
- `admin.rs` derive_sub_active + 필드. `ptt_rewriter.has_speaker`/`slot.is_speaking`(읽기 전용, hot-path 불가침). `oxadmin trace --secs N`(자동 종료, tokio time).

### 1-3. 클라 subscribe mid 재사용 robust화 — Duplicate a=mid (클라 `a0582fd`)
- 증상: U02 republish 시 클라 `subscribe re-nego: Duplicate a=mid '3'` → setRemoteDescription 실패 → 영상 m-line 미부착.
- 근본: 서버가 mid 1:1 권위 할당하는데 클라 `_recycleByMid` 가 **inactive pipe 만** 재사용 → remove 유실/순서로 옛 pipe active 잔존 시 신규 m-line 추가 → 중복.
- `room.js _recycleByMid`: active 제약 해제(같은 mid=stale→rebind, inactive 우선) + 동일 mid 잔여 제거. `sdp-builder.js`: mid dedup 이중 안전망. 웹 한정(Android/봇 별개).
- **★라이브 미검증** — 부장 화면 재로드 안 한 상태였음. 다음 세션 확인 필수.

### 1-4. floor max burst 30s→24h (서버 config.rs, **미커밋**)
- 디버깅 중 PTT 발언 30초 자동 revoke(`FLOOR_MAX_BURST_MS`)로 trace 타이밍 압박 → 24h(86_400_000). **상용 복귀 시 30_000 원복**. 디버깅 임시라 미커밋(working tree 유지).

---

## 2. 커밋
| 해시 | 레포 | 내용 |
|------|------|------|
| `82cb214` | sfu-server | unpublish=SubscriberStream 회수 + reindex 청산 |
| `f9980a3` | sfu-server | oxadmin active(*)/발화자/in·out·drop + trace --secs |
| `a0582fd` | oxlens-home | subscribe mid 재사용 robust화 (Duplicate a=mid) |
| (미커밋) | sfu-server | config.rs FLOOR_MAX_BURST_MS 24h (디버깅) |

---

## 3. 검은화면 디버깅 — ★ 미해결 (다음 세션 1순위)

### 증상
- **half(PTT) 발언 시 검은화면 간헐** + 화질 뭉개지다 선명 + **3초 이전 화면부터 보이다 따라잡음**. **full 로 시작하면 무증상.**

### trace/로그 실증 (확정 사실)
- slot egress(`0xE194429D`, sfu-1) 3495패킷 캡처(0xE194429D.log, 부장 보관). **키프레임(H264 IDR FU `7c:85`) 단 1개** — 캡처 28초(2588/3495) 지점. 나머지 1117 프레임 전부 델타. → 첫 28초 키프레임 없어 검은.
- PT=`0x66`=102(H264, ingress 109→egress 102 정상 매핑), ssrc/seq/ts rewrite 정상, egress **realtime·연속**(버스트 아님) — forward/PT/playout-timing 무죄.
- 서버 TWCC: ingress(`collect_rtp_stats` line 179-220)에서 **drop 전 기록**(rr_stats/rtp_in/twcc record, half/full 무관). feedback 전송(`egress.rs:94 send_twcc_to_publishers`, video_ssrc=first_track_of_kind(Video)=half 포함) **코드상 정상**.

### 부장 가설(유력, 미확정) — 클라 인코더 콜드 스타트
- `oxlens-home/sdk/ptt/power.js`: 발화권 없이 30초 → **COLD → track 반납**(replaceTrack(null)+removeStreamTrack), 발화 시 **getUserMedia 재취득=새 인코더=콜드 스타트** → BWE 콜드(저비트레이트→키프레임 자제 28초) + Chrome **allocation probe 미발동**(20260405 메모리 일치).
- full 무증상 = power FSM(half pipe 전용) 안 탐 → 콜드 스타트 없음.
- 미해결: 서버 feedback 은 코드상 도는데도 콜드면 → 클라 probe 미발동 확정 필요. **clmd `twcc_sent` metric / U02 RTCP trace 실측 미완.** 해결 후보 = 빈 video transceiver 선생성 + replaceTrack(BWE 보존, 20260405).

---

## 4. 검증
- 빌드(release) + 단위 207 PASS / oxe2e 5/5 / lab 6단계(누적 0).
- 검은화면·클라 mid: lab 라이브 미확정.

## 5. 미해결 / 다음 세션
1. **검은화면 근본** — 콜드스타트 BWE probe 미발동(클라) 확정 + replaceTrack/transceiver 보존 해결.
2. **클라 mid 재사용(`a0582fd`) 라이브 검증** — 화면 hard reload 후 Duplicate a=mid 소멸 확인.
3. **config.rs floor 24h 원복** (디버깅 종료 시).

## 6. 교훈 (반복 금지)
- **sfu 노드 미확인 — trace 헛다리**: R01 재기동으로 sfu-2→sfu-1 이동했는데 옛 `--sfu sfu-2` 박아 trace 0건 → "도구 결함" 오판. **`oxadmin rooms` 로 sfu 먼저 확인**. slot virtual_ssrc 도 재기동마다 바뀜 → `room <id>` 현재값 복붙.
- **추측 단정 반복**: "옛 pipe active 잔존"(remove=inactive 와 모순), "내 클라 수정이 영상 깸"(화면 재로드 안 함=반영 안 됨), "과거 누적"(카운터 증가=현재 흐름) — 모두 trace/사실 확인 전 단정. 부장 반증 신호("정상일 수도/재로드 안 했는데/맞는 대화 하냐") 즉시 수용.
- **카운터(누적) ≠ trace(현재)** — PKTS 카운터로 "흐른다" 단정 금지, trace 실증.
