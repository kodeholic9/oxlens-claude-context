#!/usr/bin/env bash
# context 기록 규약 검사기 (ctxlint — doclint(내용 갭 감사)와 별개 개념) — PROJECT_MASTER.md §기록 규칙(R1~R7) 을 기계로 강제한다.
# 규칙을 문서에만 적어두면 계속 샌다(2026-06 인덱스 규칙이 실증). 세션 종료 전 반드시 통과시킨다.
#
#   ./ctxlint.sh            기준일(2026-08-02) 이후 신규 파일만 검사
#   ./ctxlint.sh --since 20260901
#   ./ctxlint.sh --all      과거 포함 전수 (참고용 — R7 상 과거는 개명하지 않으므로 실패가 정상)
#
# author: kodeholic (powered by Claude)

set -u
cd "$(dirname "$0")"

SINCE=20260802
ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --all)   ALL=1; shift ;;
    *) echo "usage: $0 [--since YYYYMMDD] [--all]" >&2; exit 2 ;;
  esac
done
[ "$ALL" = 1 ] && SINCE=00000000

fail=0
note() { printf '  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL %s\n' "$1"; }

# 검사 대상: YYYYMM/ 하위 md 중 기준일 이후
targets=()
while IFS= read -r f; do
  b=$(basename "$f")
  d=${b:0:8}
  case "$d" in ''|*[!0-9]*) continue ;; esac   # 날짜로 시작하지 않는 파일은 대상 외
  [ "$d" -ge "$SINCE" ] && targets+=("$f")
done < <(find 2[0-9][0-9][0-9][0-9][0-9] -name '*.md' 2>/dev/null | sort)

echo "== context ctxlint (기준일 $SINCE, 대상 ${#targets[@]}건) =="

# ---- R1: 종류별 디렉토리 신설 금지 ----------------------------------------
allowed_dirs='guide biz blog lesson qa'
for d in */; do
  d=${d%/}
  case "$d" in
    2[0-9][0-9][0-9][0-9][0-9]) continue ;;
  esac
  echo " $allowed_dirs " | grep -q " $d " || bad "R1 허용되지 않은 디렉토리: context/$d/ — 세션 기록은 YYYYMM/ 평면에 둔다"
done

# ---- R2: 파일명 kind 접미사 -----------------------------------------------
for f in "${targets[@]}"; do
  b=$(basename "$f" .md)
  case "$b" in
    *_task|*_design|*_analysis|*_note) ;;
    *) bad "R2 kind 접미사 없음: $f"
       note "→ _task / _design / _analysis / _note 중 하나로 끝나야 한다" ;;
  esac
done

# ---- R3: _done 별도 파일 금지 ---------------------------------------------
for f in "${targets[@]}"; do
  case "$(basename "$f")" in
    *_done.md|*_complete.md)
      bad "R3 완료 보고 별도 파일: $f"
      note "→ 지침을 쓴 _task 파일에 '## 완료 · YYYYMMDD' 를 append 한다" ;;
  esac
done

# ---- R4: _task 는 frontmatter status 를 갖는다 -----------------------------
for f in "${targets[@]}"; do
  case "$(basename "$f")" in *_task.md) ;; *) continue ;; esac
  head -1 "$f" | grep -q '^---$' || { bad "R4 frontmatter 없음: $f"; continue; }
  fm=$(sed -n '2,/^---$/p' "$f")
  echo "$fm" | grep -q '^status:' || bad "R4 frontmatter 에 status 없음: $f"
  st=$(echo "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1 | tr -d ' ')
  case "$st" in
    open|done|dropped|'') ;;
    *) bad "R4 status 값이 규격 밖($st): $f — open|done|dropped" ;;
  esac
  # 지침 절 존재
  grep -q '^## 지침' "$f" || bad "R4 '## 지침' 절 없음: $f"
  # 닫힌 작업은 완료 절이 같은 파일에 있어야 한다
  if [ "$st" = done ]; then
    grep -q '^## 완료' "$f" || bad "R4 status=done 인데 '## 완료' 절 없음: $f"
  fi
done

# ---- R5: SESSION_INDEX 행 길이 --------------------------------------------
# 인덱스는 한 줄 요약이다. 요약 칸이 120자를 넘으면 본문이 새어든 것으로 본다.
for idx in SESSION_INDEX_*.md; do
  [ -e "$idx" ] || continue
  m=${idx#SESSION_INDEX_}; m=${m%.md}
  [ "$ALL" = 1 ] || [ "${m}01" -ge "${SINCE:0:6}01" ] || continue
  n=0
  while IFS= read -r line; do
    case "$line" in
      '|'*'|'*) ;;
      *) continue ;;
    esac
    echo "$line" | grep -qE '^\|[[:space:]]*-{2,}' && continue   # 구분행
    echo "$line" | grep -qE '^\|[[:space:]]*(날짜|date)' && continue  # 헤더
    len=${#line}
    if [ "$len" -gt 200 ]; then
      n=$((n+1))
      [ "$n" -le 3 ] && note "  ${idx}: ${len}자 — $(echo "$line" | cut -c1-70)…"
    fi
  done < "$idx"
  [ "$n" -gt 0 ] && bad "R5 $idx: 과다 길이 행 ${n}건 (200자 초과) — 한 줄 요약 + 파일명 + status 로 줄인다"
done

# ---- R6-a: 마스터 문서의 참조 경로가 실재하는가 -----------------------------
for m in PROJECT_MASTER.md PROJECT_SERVER.md PROJECT_WEB.md; do
  [ -e "$m" ] || continue
  grep -oE '`context/[0-9]{6}/[A-Za-z0-9._-]+\.md`' "$m" | tr -d '`' | sort -u | while read -r ref; do
    [ -e "${ref#context/}" ] || echo "DANGLING $m → $ref"
  done
done > /tmp/ctxlint_dangling.$$
if [ -s /tmp/ctxlint_dangling.$$ ]; then
  while IFS= read -r l; do bad "R6 참조 경로 부재: ${l#DANGLING }"; done < /tmp/ctxlint_dangling.$$
fi
rm -f /tmp/ctxlint_dangling.$$

# ---- R6-b: 소스 주석의 context 문서 참조가 실재하는가 -----------------------
# doclint 는 문서만이 아니라 "문서를 가리키는 모든 것"을 포괄한다. 소스 주석의
# 설계서 경로가 죽으면 코드에서 근거로 못 걸어간다 — 20260802 실측 17곳 적발
# (폐지된 context/design/·context/claudecode/ 를 가리키고 있었다).
SRC_ROOTS="../oxlens-sfu-server/crates ../oxlens-sfu-server/oxe2epy ../oxlens-home/sdk0.2/src ../oxlens-home/qa"
: > /tmp/ctxlint_src.$$
for root in $SRC_ROOTS; do
  [ -d "$root" ] || continue
  grep -rhoE 'context/[A-Za-z0-9_][A-Za-z0-9_./-]*\.md' "$root" 2>/dev/null
done | sort -u | while read -r ref; do
  [ -e "${ref#context/}" ] || echo "$ref" >> /tmp/ctxlint_src.$$
done
if [ -s /tmp/ctxlint_src.$$ ]; then
  while IFS= read -r ref; do
    bad "R6 소스 주석의 죽은 문서 경로: $ref"
    where=$(for root in $SRC_ROOTS; do [ -d "$root" ] && grep -rln "$ref" "$root" 2>/dev/null; done | head -3 | tr '\n' ' ')
    note "→ $where"
  done < /tmp/ctxlint_src.$$
fi
rm -f /tmp/ctxlint_src.$$

# ---- 결과 ------------------------------------------------------------------
echo
if [ "$fail" -eq 0 ]; then
  echo "OK — 위반 0건"
  exit 0
else
  echo "위반 ${fail}건 — PROJECT_MASTER.md §기록 규칙 참조"
  exit 1
fi
