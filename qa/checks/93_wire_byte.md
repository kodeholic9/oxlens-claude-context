# 93_wire_byte.md — DC byte-level wire

> **catalog 매핑**: `20_wire.md`
> **마지막 갱신**: 2026-04-26
> **항목 갯수**: 12

---

| ID | 시험 항목 | 객관 근거 | catalog | 상태 |
|---|---|---|---|:---:|
| W-01 | `buildFrame(svc, payload)` 헤더 | byte[0]==svc, byte[1:3]==len BE | `20_wire §2` | ⬜ |
| W-02 | `parseFrame` truncated → null | data.length<3 또는 len>data.length-3 | 동일 | ⬜ |
| W-03 | MBCP byte0 = V\|R\|A\|Type | 0x10 ackReq + 0x0F type, V=00 R=0 | `20_wire §3 헤더` | ⬜ |
| W-04 | TLV 직렬화 순서 (표준→Pan→자체확장) | 서버 mbcp_native.rs 와 byte diff = 0 | `20_wire §3 TLV` | ⬜ |
| W-05 | FIELD.PRIORITY=0 (1B) | TLV id 0, len 1, value priority 0~7 | 동일 | ⬜ |
| W-06 | FIELD.DESTINATIONS=0x18 (count + [len+utf8]) | id 0x18, count + parts | 동일 | ⬜ |
| W-07 | FIELD.PUB_SET_ID=0x19 (utf8) | id 0x19, len + utf8 | 동일 | ⬜ |
| W-08 | FIELD.PAN_SEQ=0x10 (u32 BE 4B) | id 0x10, len 4, value u32 BE | `20_wire §3 Pan-Floor` | ⬜ |
| W-09 | FIELD.PAN_DESTS=0x11 (count + [len+utf8]) | id 0x11 | 동일 | ⬜ |
| W-10 | FIELD.PAN_PER_ROOM=0x12 (count + [len+utf8+result(1)]) | id 0x12, result byte 0/1/2 | 동일 | ⬜ |
| W-11 | FIELD.VIA_ROOM=0x17 (utf8) | id 0x17, FLOOR_TAKEN broadcast 시 포함 (i 세션 별건 2) | `99_invariants.md` | 👁 |
| W-12 | MSG type 표준 정렬 (QUEUE_POS_REQUEST=8, QUEUE_INFO=9, ACK=10) | byte0 & 0x0F == 8/9/10 | `20_wire §3 MSG` | 👁 |

---

> ⚠️ byte 단위 검증은 실제 `buildMsg()` / `buildFrame()` 출력을 직접 `assertEq(view[N], expected)` 로. 상수 일치만으론 wire 일치 보증 안 됨.
> ⚠️ W-04: 서버 mbcp_native.rs 의 직렬화 순서와 SDK datachannel.js 의 if-block 순서가 일치해야 wire diff = 0.
