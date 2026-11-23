#!/usr/bin/env bash
# claude/skills/* — Agent Skills 규격(이름 = 폴더, 설명 1~1024자)과 readme-update 스크립트가 실제로 도는지.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0 fail=0
ok() { pass=$((pass + 1)); }
no() { fail=$((fail + 1)); echo "FAIL $1"; }

for d in "$REPO"/claude/skills/*/; do
  n=$(basename "$d")
  if python3 - "$d/SKILL.md" "$n" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
assert m, "frontmatter 없음"
fm = dict(re.findall(r"^(\w[\w-]*): *(.*)$", m.group(1), re.M))
assert fm.get("name") == sys.argv[2], ("name 이 폴더와 다르다", fm.get("name"))
assert re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?", fm["name"]) and "--" not in fm["name"]
assert 1 <= len(fm.get("description", "")) <= 1024, len(fm.get("description", ""))
assert len(text.splitlines()) <= 500, "SKILL.md 500줄 초과"
PY
  then ok; else no "spec $n"; fi
done

S="$REPO/claude/skills/readme-update/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/docs/images" "$T/scripts"; : > "$T/docs/images/a.png"; : > "$T/scripts/run.py"; : > "$T/docs/other.md"
cat > "$T/README.md" <<'MD'
# demo

## Quick start

see [other](docs/other.md)

## 1. Long part

![pic](docs/images/a.png) and [code](scripts/run.py) and [back](#quick-start) and [same](#1-long-part)

## License

MIT
MD
( cd "$T" && python3 "$S/move_sections.py" --start "## 1. Long part" --end "## License" --out docs/guide.md --title Guide >/dev/null )
if grep -q '](images/a.png)' "$T/docs/guide.md" && grep -q '](../scripts/run.py)' "$T/docs/guide.md" \
   && ! grep -q '## 1. Long part' "$T/README.md" && grep -q '## License' "$T/README.md"; then ok; else no move_sections_rebases_links; fi
if python3 "$S/check_links.py" "$T/README.md" >/dev/null; then ok; else no check_links_clean_readme; fi
# README 에 남은 절을 가리키던 #앵커는 README 쪽으로 바뀌고, 옮긴 절끼리의 앵커는 그대로다
if grep -q '](../README.md#quick-start)' "$T/docs/guide.md" && grep -q '](#1-long-part)' "$T/docs/guide.md" \
   && python3 "$S/check_links.py" "$T/docs/guide.md" >/dev/null; then ok; else no move_sections_keeps_anchors; fi
# 검사기는 없는 앵커를 잡는다
echo '[x](#nowhere)' >> "$T/docs/guide.md"
if ! python3 "$S/check_links.py" "$T/docs/guide.md" >/dev/null; then ok; else no check_links_catches_dangling_anchor; fi
if python3 "$S/readme_stats.py" "$T/README.md" | grep -q 'README.md'; then ok; else no readme_stats_runs; fi
if bash "$S/find_readme_refs.sh" "$T" >/dev/null; then ok; else no find_refs_runs; fi
# 새 가이드에는 목차·영어 안내(README 가 영어), 끝 가로줄은 안 딸려 간다
if grep -q '<!-- toc -->' "$T/docs/guide.md" && grep -q 'New here?' "$T/docs/guide.md"; then ok; else no move_sections_toc_and_language; fi
# 글자 그대로 옮겼는지 — 옛 README 의 줄은 새 README·docs 어딘가에 남는다, 지운 줄은 드러난다
printf '# demo\n\n## Quick start\n\nsee [other](docs/other.md)\n\n## 1. Long part\n\n![pic](docs/images/a.png) and [code](scripts/run.py) and [back](#quick-start) and [same](#1-long-part)\n\n## License\n\nMIT\n' > "$T/old.md"
if python3 "$S/verify_moved.py" --before "$T/old.md" --after "$T/README.md" "$T/docs" >/dev/null; then ok; else no verify_moved_finds_moved_lines; fi
sed -i 's/^MIT$/Apache/' "$T/README.md"
if ! python3 "$S/verify_moved.py" --before "$T/old.md" --after "$T/README.md" "$T/docs" >/dev/null; then ok; else no verify_moved_flags_lost_line; fi
mkdir -p "$T/samples"; cp "$T/README.md" "$T/samples/a.md"
if python3 "$S/readme_nature.py" "$T/samples" | grep -q "레이아웃"; then ok; else no readme_nature_runs; fi

echo "test_skills: $pass/$((pass + fail)) pass"
[ "$fail" -eq 0 ]
