<!-- author: kodeholic (powered by Claude) -->

# 20260624(저녁) — PTT vs 화상통화 라이브 재시험 (재현 가능 보고서)

> 목적: 돌림노래가 PTT 고유인지 환경 artifact인지 라이브로 가름 + oxadmin `stat` 다중화.
> 결론(요약): **getStats(브라우저 실측 jb) = PTT 폭주(U03 741ms) / 화상통화 정상(40~50ms) → 돌림노래 = PTT 고유·실재.** neteq_rtpplay replay 절대값은 아티팩트 확인 → §4 주의.
> 모든 데이터: `~/repository/testlogs/202606/`. 분석도구: `~/repository/webrtc-checkout/src/out/Default/neteq_rtpplay`(빌드됨).

---

## 1. 데이터 인벤토리 (`~/repository/testlogs/202606/`)

| 파일 | 정체 | 비고 |
|---|---|---|
| `cap_0625_01.pcap` (17.5MB) | **PTT** 19:18, `sudo tcpdump -i lo0 udp port 19740` | SFU 송수신 양방향. root 소유, 읽기 가능 |
| `stat_0625_01.log` | **PTT** 19:18 getStats (U01,U02,U03) | ★ 실측 jb — 신뢰 |
| `evlog_0625_20260624_1940_<P>_<R>.log` | **PTT** 19:40 Chrome RTC event log (tcpdump 없음) | render proc 135/138/146 = 3탭. 큰 파일(_169/_159/_25)=subscribe PC |
| `stat_vc_01.log` | **화상통화** 19:55 getStats | ★ 실측 jb — 신뢰 |
| `vclog__20260624_1955_<P>_<R>.log` | **화상통화** 19:55 RTC event log | 큰 파일(135_171/138_161/146_27)=subscribe PC |

**핵심 ssrc**:
- PTT 슬롯 audio = **`0xD173A941`** (PT111, per-room vssrc, pcap egress 8750패킷).
- 화상통화 audio = **`0xd9f5cd22`(U01)**, **`0xc3600fc9`(U02)**, U03 audio별도. (video: 3ecab576/bdc6984e/fe71f4ee — 분석은 audio만.)

---

## 1.5 데이터 생성 방법 (캡처) — 재현용

### (A) pcap — tcpdump (SFU 송수신 와이어). **sudo 필요 = 부장님 실행**
```bash
# lo0 = 브라우저가 같은 맥(loopback). 다른 기기면 en0(=192.168.0.25).
# udp port 19740 = sfu-1 미디어 포트(sfu-2=19741). -s0 = 전체(SRTP라도 RTP헤더 평문).
sudo tcpdump -i lo0 -s0 -w ~/repository/testlogs/202606/cap_<label>.pcap udp port 19740
# 시험 중 켜두고 끝나면 Ctrl+C. 파일 root 소유지만 0644 → 읽힘.
```
- src=19740 → SFU 송신(egress), dst=19740 → SFU 수신(ingress). 양방향 다 잡힘.
- Claude는 비대화형 sudo 불가 → **이 한 줄은 부장님이.**

### (B) Chrome RTC event log — webrtc-internals (수신 탭 실제 도착 타이밍). Claude 불가, 부장님.
1. 브라우저에서 `chrome://webrtc-internals/` 열기 (한 페이지가 그 Chrome의 모든 PC 감시).
2. **"Create diagnostic packet recordings"** 펼치고 → **"Enable diagnostic packet and event recording"** 체크.
   - (위의 "diagnostic audio recordings"=.wav는 불요.)
3. 저장 대화상자 → base 경로/이름 지정: `~/repository/testlogs/202606/<label>` (예 `evlog_0625`).
   Chrome이 `_<날짜>_<시각>_<renderProcID>_<recordingID>.log` 붙임. **PC마다 파일 1개**(탭마다 publish+subscribe → **큰 파일=subscribe=수신 RTP**).
4. 체크된 채로 **시험**(지금부터 캡처 → 반드시 켜고 나서 시험).
5. **체크 해제**(또는 페이지 닫기) → flush.
- 내용 = RTP/RTCP **헤더만**(payload·PII 없음) → neteq_rtpplay에 `--replacement_audio_file` + `--ssrc` 동반(§2-b). 상한 60MB/5파일.

### 분담
- **stat·neteq_rtpplay 분석** = Claude(sudo 불요, 백그라운드 캡처 가능).
- **tcpdump·event log 생성** = 부장님(sudo / 브라우저 UI).
- 파일명 라벨 = `<HHMM>_<NN>` 또는 `<시나리오>` — pcap·stat·event log 같은 라벨로 짝.

---

## 2. 재확인 방법 (명령어)

### (a) getStats 실측 jb — ★ 신뢰 데이터
stat 로그는 텍스트. 컬럼 = `TIME USER rxA pps lost disc jb jbT glch acc dec | rxV ...`. user별 jb:
```bash
cd ~/repository/testlogs/202606
python3 -c "
from collections import defaultdict; import statistics
pu=defaultdict(list)
for ln in open('stat_0625_01.log'):
    p=ln.split()
    if len(p)<8 or not p[1].startswith('U'): continue
    j=p[6].replace('ms','')
    if j.lstrip('-').isdigit(): pu[p[1]].append(int(j))
for u,v in sorted(pu.items()): print(u,'jb med',statistics.median(v),'max',max(v))
"
# stat_vc_01.log 로 바꾸면 화상통화
```
결과: PTT U03=741/U01=446/U02=114ms · 화상통화 U01=46/U02=40/U03=50ms.

### (b) RTC event log → 진짜 NetEQ (neteq_rtpplay)
이벤트 로그는 **헤더만(payload 없음)** → 더미 PCM 필요. 다중 ssrc라 **`--ssrc` 필수**.
```bash
# 더미 PCM (48k 16bit mono 10s 사인) 1회 생성
python3 -c "import struct,math;open('/tmp/rep.pcm','wb').write(b''.join(struct.pack('<h',int(2000*math.sin(2*math.pi*440*i/48000))) for i in range(480000)))"

# PTT 탭 (슬롯 ssrc 0xD173A941)
~/repository/webrtc-checkout/src/out/Default/neteq_rtpplay --opus 111 --ssrc 0xD173A941 \
  --replacement_audio_file /tmp/rep.pcm --pythonplot --output_files_base_name=/tmp/ev \
  ~/repository/testlogs/202606/evlog_0625_20260624_1940_146_25.log /tmp/ev.pcm

# 화상통화 탭은 --ssrc 0xd9f5cd22 (또는 0xc3600fc9), vclog__..._1955_146_27.log
# 결과 파싱: /tmp/ev.py 의 target_delay_y / arrival_delay_y
python3 -c "
import re,statistics
t=open('/tmp/ev.py').read()
def a(n): m=re.search(n+r'=\s*\[([^\]]*)\]',t); return [float(x) for x in m.group(1).split(',') if x.strip()]
print('target med',statistics.median(a('target_delay_y')),'arrival med',statistics.median(a('arrival_delay_y')))
"
```
결과: PTT arrival ~663~816ms / 화상통화 ~1ms. **단 절대값 신뢰 금지 — §4.**

### (c) pcap 슬롯/송수신 분석 (lo0, DLT_NULL)
```bash
python3 - <<'PY'
import struct
d=open('cap_0625_01.pcap','rb').read();pos=24
while pos+16<=len(d):
    s,u,incl,_=struct.unpack('<IIII',d[pos:pos+16]);pos+=16
    if pos+incl>len(d):break
    r=d[pos:pos+incl];pos+=incl;ip=r[4:]          # DLT_NULL=4B family
    if len(ip)<20 or ip[9]!=17:continue
    udp=ip[(ip[0]&0xf)*4:]; sp,dp=struct.unpack('>HH',udp[:4]); pl=udp[8:]
    if len(pl)<12 or (pl[0]&0xc0)!=0x80:continue
    # sp==19740 = SFU 송신(egress), dp==19740 = SFU 수신(ingress)
    # SRTP라도 RTP헤더 평문: seq=pl[2:4] ts=pl[4:8] ssrc=pl[8:12] PT=pl[1]&0x7f
PY
```
슬롯 ssrc=0xD173A941. ingress(dp=19740) vs egress(sp=19740) 패킷 간격/지터 비교 가능.

---

## 3. 결과 (재현된 수치)

| 측정 | PTT | 화상통화 | 신뢰 |
|---|---|---|---|
| **getStats jb max** | U03 **741** / U01 446 / U02 114ms | 46 / 40 / 50ms | ★ 신뢰 |
| event log→neteq arrival med | 663~816ms | ~1ms | △ 아티팩트(§4) |
| pcap SFU egress 간격 | median 20ms p95 22ms | (미측정) | 참고 |

→ **getStats만으로 결론**: 돌림노래 = **PTT 고유·실재**. 화상통화는 같은 3탭/맥에서 깨끗.

---

## 4. ★ neteq_rtpplay replay 절대값 신뢰 금지 (근거)

PTT event log의 `arrival_delay`를 2초 구간별로 보면 **1397ms→24ms로 84초간 단조 감소**(클럭 드리프트/replay 아티팩트, 깨끗한 지터 아님). 재현:
```bash
python3 -c "
import re,statistics,collections
t=open('/tmp/ev.py').read()
def a(n): m=re.search(n+r'=\s*\[([^\]]*)\]',t); return [float(x) for x in m.group(1).split(',') if x.strip()]
ax,ay=a('arrival_delay_x'),a('arrival_delay_y'); b=collections.defaultdict(list)
for x,y in zip(ax,ay): b[int(x//2)].append(y)
for k in sorted(b): print(k*2,'s median',int(statistics.median(b[k])))
"   # → 1397,1397,1307,...,255,83,24 (단조 감소)
```
원인: ① 헤더만 로그 → replacement-tone로 DTX 소실 過대예측, ② replay 내부 tick_timer vs 로그 arrival 클럭 차 = 램프. **그래서 절대 ms 금지, getStats(브라우저 자체 jb)만 ground truth.** (김대리가 이 replay 수치로 tcpdump/수신·송신/silence-flush를 반복 오판함 — 도구 과신.)

---

## 5. 완료 산출물

- **oxadmin `stat` 다중 user + `--out`** (oxadmin/main.rs, 커밋 `f4209a9`, 빌드·10테스트 PASS):
  `stat U01,U02,U03 [--interval N] [--out f]` — 한 틱 동일 TIME + USER 컬럼(입체), tee. 단일 user는 종전대로. RUN_GUIDE §4-S 갱신.
- neteq_rtpplay 빌드(`~/repository/webrtc-checkout/src/out/Default/`) — 단 §4.

---

## 6. 미해결 / 다음

1. **PTT의 *어디서* jb 폭주가 오는지 미규명.** 슬롯(silence-flush/idle/handoff/rewriter ts) 중 무엇인지 — **replay 말고 getStats를 구간별(talkspurt 시작/idle)로** 실측해 짚을 것.
2. oxadmin stat 다중화 — **커밋 완료 `f4209a9`**.
3. priming(예열)은 유지 — [[20260624_ptt_priming_live_neteq_rootcause.md]].

_기록 끝._
