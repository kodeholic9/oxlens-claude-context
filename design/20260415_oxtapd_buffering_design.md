# oxtapd 보완 설계 — 시그널링 분리 + RTP→파일 버퍼링

> 작성일: 2026-04-15
> 기존 설계서: `design/20260413_oxtapd_design.md` 보완
> author: kodeholic (powered by Claude)

---

## 1. 시그널링 클라이언트 분리 (미완 — 상세 설계 필요)

### 1.1 문제

현재 SignalClient가 WS stream을 `&mut self`로 독점 소유.
RoomRecorder 메인 루프에서 `tokio::select!`로 UDP recv와 WS event를 동시 대기하려면
WS 수신이 독립되어야 한다.

### 1.2 방향

SignalClient를 읽기/쓰기 분리:

```
SignalClient::into_split() → (SignalWriter, mpsc::Receiver<Packet>)
```

- **SignalWriter**: heartbeat, tracks_ack 등 송신 전용
- **mpsc::Receiver<Packet>**: 이벤트 수신, select!에서 사용

```
SignalClient task (spawn)
  └── ws.next() 루프 → event_tx.send(Packet)

RoomRecorder 메인 루프
  └── tokio::select! {
        pkt = event_rx.recv() => { ... }   // WS 이벤트
        (n, _) = udp.recv_from() => { ... } // RTP
        _ = rr_tick.tick() => { ... }       // RTCP RR
        _ = hb_tick.tick() => { ... }       // heartbeat
        _ = stop_rx.recv() => { break }     // shutdown
      }
```

### 1.3 상태: 미완

구체 설계는 다음 세션에서 진행. into_split() 시그니처, 에러 처리, reconnect 흐름 등 상세화 필요.

---

## 2. RTP 수신 → 파일 저장 버퍼링 설계

### 2.1 문제

UDP recv는 µs 단위 핫패스. 파일 write는 ms 단위 (NAS 네트워크 지연 포함).
같은 루프에서 동기로 돌리면 UDP 수신이 밀린다.

### 2.2 설계: BufferPool (Kafka Producer 패턴)

#### 구조

```
UDP recv task (핫패스, µs)
  │
  │  pool.allocate() → batch
  │  batch.append(record) 반복
  │
  │  linger_ms OR batch_size 도달
  │  → ready_tx.send(batch)      ← mpsc, lock 없음
  │  → pool.allocate() 새 배치
  │
  ▼
[mpsc channel]
  │
  ▼
Writer task (여유, ms)
  │  ready_rx.recv()
  │  → 배치 순회, OXR record header의 SSRC로 트랙 파일 식별
  │  → 해당 BufWriter<File>에 write
  │  → pool.deallocate(buf)       ← free list 반환
```

#### BufferPool

```rust
struct BufferPool {
    free: Mutex<VecDeque<ByteBuffer>>,   // lock 경합 유일 지점
    buf_capacity: usize,                  // 버퍼당 고정 크기 (예: 256KB)
    pool_size: usize,                     // 버퍼 개수 (예: 4)
}

impl BufferPool {
    fn allocate(&self) -> Option<ByteBuffer>  // free에서 pop
    fn deallocate(&self, buf: ByteBuffer)     // free에 push
}
```

- free list Mutex: VecDeque push/pop 한 번, 나노초 단위, 실질 경합 없음
- 고정 N개 → 메모리 총량 예측 가능

#### RecordBatch

```rust
struct RecordBatch {
    buf: ByteBuffer,           // pool에서 할당받은 버퍼
    cursor: usize,             // write 위치
    first_append_us: u64,      // 시간 임계 기준점
}

impl RecordBatch {
    fn append(&mut self, record: &[u8]) → bool   // 단일 소유자, lock 없음
    fn is_full(&self) -> bool                     // cursor >= batch_size
    fn is_expired(&self, now_us: u64) -> bool     // now - first_append > linger_us
}
```

- append는 단일 소유자(recv task)만 호출 → lock 불필요
- 배치 소유권이 recv → channel → writer로 이동, 동시 접근 없음

#### flush 트리거 (이중 임계)

```
크기 임계: batch.cursor >= batch_size (예: 64KB)
시간 임계: now - batch.first_append_us >= linger_us (예: 100ms)

둘 중 먼저 도달하는 조건에서 flush.
```

Kafka `linger.ms` + `batch.size` 패턴과 동일.

### 2.3 lock 경합 분석

| 지점 | 주체 | lock 종류 | 빈도 | 비용 |
|------|------|-----------|------|------|
| batch.append() | recv task 단독 | 없음 | 매 패킷 | 0 |
| pool.allocate() | recv task | Mutex (짧음) | flush 시 1회 | ns |
| ready_tx.send() | recv task | mpsc (lock-free) | flush 시 1회 | ns |
| ready_rx.recv() | writer task | mpsc (lock-free) | flush 시 1회 | ns |
| 파일 write | writer task 단독 | 없음 | flush 시 N회 | ms |
| pool.deallocate() | writer task | Mutex (짧음) | flush 시 1회 | ns |

**핫패스(UDP recv → batch append)에 lock 제로.**

### 2.4 버퍼 꽉 찬 경우 (backpressure)

정상 경로: oxtapd는 NACK 가능한 정상 WebRTC subscriber.
writer가 잠깐 밀려 UDP recv가 늦어져도 패킷 유실은 NACK→RTX로 복구.

비정상 (네트워크 스토리지 지속 장애):
1. pool.allocate() 실패 (free 비어있음)
2. → 현재 배치에 계속 append 시도, 불가하면 드롭
3. → META에 `gap:dropped` 이벤트 기록 (후처리에서 구간 표시)
4. → 경고 메트릭 + 로그
5. → 지속되면 녹화 일시 중단 판단

### 2.5 방별 독립 파이프라인

```
Room A: UDP socket A → BufferPool A → writer task A → 트랙 파일들
Room B: UDP socket B → BufferPool B → writer task B → 트랙 파일들
Room C: UDP socket C → BufferPool C → writer task C → 트랙 파일들
```

- 방별 tokio task 독립
- 방별 BufferPool 독립 → 방 간 간섭 없음
- 한 방의 스토리지 stall이 다른 방에 영향 없음

### 2.6 Writer task 내부 (SSRC 분배)

```rust
async fn writer_loop(
    pool: Arc<BufferPool>,
    mut ready_rx: mpsc::Receiver<RecordBatch>,
    mut track_files: HashMap<u32, BufWriter<File>>,  // SSRC → 파일
) {
    while let Some(batch) = ready_rx.recv().await {
        // 배치 내 OXR record 순회
        for record in batch.iter_records() {
            match record.record_type {
                RecordType::Rtp => {
                    let ssrc = parse_ssrc(record.payload);
                    if let Some(writer) = track_files.get_mut(&ssrc) {
                        writer.write_all(record.raw_bytes());
                    }
                }
                RecordType::Meta => {
                    // META는 모든 트랙 파일에 기록
                    // 또는 방 레벨 메타 파일에 기록
                }
            }
        }
        // 버퍼 반환
        pool.deallocate(batch.into_buf());
    }
}
```

- track_files는 writer task 로컬 → 경합 없음
- 새 SSRC 등장 시 TRACKS_UPDATE 이벤트로 파일 생성
- 트랙 제거 시 파일 finalize

### 2.7 메모리 예산

```
단일 방: 버퍼 4개 × 256KB = 1MB
방 3개 동시: 3MB
방 10개 동시: 10MB
```

policy.toml 설정:
```toml
[recording.buffer]
pool_size = 4            # 방당 버퍼 개수
buf_capacity_kb = 256    # 버퍼당 크기 (KB)
linger_ms = 100          # 시간 임계 (ms)
batch_size_kb = 64       # 크기 임계 (KB)
```

### 2.8 저장 경로

RPi 로컬 저장은 테스트용. 운영 환경은 NAS/네트워크 스토리지.

```toml
[recording]
base_path = "/mnt/nas/recordings"    # NFS/CIFS 마운트 포인트
```

BufferPool이 흡수하는 대상은 SD카드 GC가 아니라 네트워크 지연.

---

*author: kodeholic (powered by Claude)*