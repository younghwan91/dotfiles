"""트렌딩 README 의 성격 재기 — 레이아웃·글자 쓰임·말투. 폴더의 *.md 를 읽어 비율·중앙값을 찍는다(references/style.md 의 표).

    python3 readme_nature.py <README 들을 모은 폴더>
"""
import glob
import os
import re
import statistics as st
import sys

EMOJI = re.compile(r"[\U0001F300-\U0001FAFF☀-➿⭐✅❌]")
HYPE = re.compile(r"\b(blazing|lightning|powerful|revolutionary|ultimate|seamless(ly)?|effortless(ly)?|"
                  r"supercharge|game[- ]chang|best[- ]in[- ]class|world[- ]class|incredibly|insanely|magic(al)?)\b", re.I)


def cjk(t):
    return len(re.findall(r"[぀-ヿ㐀-鿿가-힣]", t)) > 200


def measure(t):
    lines = t.splitlines()
    head = "\n".join(lines[:45])
    prose = re.sub(r"```.*?```", "", t, flags=re.S)
    plain = re.sub(r"<[^>]+>|!\[[^\]]*\]\([^)]*\)", "", prose)
    plain = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", plain)
    heads = re.findall(r"^(#{1,6}) (.+)$", t, re.M)
    h2 = [h for lv, h in heads if lv == "##"]
    bullets = re.findall(r"^\s*[-*] (.+)$", prose, re.M)
    words = re.findall(r"[A-Za-z']+", plain)
    sents = [s for s in re.split(r"(?<=[.!?])\s+", plain) if len(re.findall(r"[A-Za-z]+", s)) > 3]
    first_para = next((p for p in re.split(r"\n\s*\n", plain) if len(re.findall(r"[A-Za-z]+", p)) > 6
                       and not p.strip().startswith("#")), "")
    return {
        "cjk": cjk(t),
        "centered_hero": bool(re.search(r'align=["\']?center', head)),
        "dark_mode_logo": "prefers-color-scheme" in head,
        "h1_count": sum(1 for lv, _ in heads if lv == "#"),
        "h2": len(h2),
        "h2_emoji": sum(1 for h in h2 if EMOJI.search(h)),
        "h2_sentence_case": sum(1 for h in h2 if re.match(r"[A-Z][a-z]+( [a-z][\w-]*)+$", h.strip())),
        "h2_title_case": sum(1 for h in h2 if len(h.split()) > 1 and all(w[:1].isupper() for w in re.findall(r"[A-Za-z][\w-]*", h) if len(w) > 3)),
        "h2_question": sum(1 for h in h2 if h.strip().endswith("?")),
        "badges": t.count("shields.io") + t.count("/badge.svg"),
        "badges_in_hero": head.count("shields.io") + head.count("/badge.svg"),
        "link_row": bool(re.search(r"\]\([^)]+\)\s*[·|•]\s*\[", head)),
        "img_in_first_screen": bool(re.search(r"!\[|<img", "\n".join(lines[:40]).split("shields.io")[0] if False else "\n".join(lines[:40]).replace("shields.io", ""))),
        "side_by_side": bool(re.search(r"width=\"?(4\d|5\d|3\d|2\d)%", t)),
        "tables": len(re.findall(r"^\|[-: |]+\|$", t, re.M)),
        "details": t.count("<details"),
        "alerts": len(re.findall(r"^> \[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]", t, re.M)),
        "hr": len(re.findall(r"^(---|\*\*\*)\s*$", t, re.M)),
        "code_blocks": sum(1 for ln in lines if ln.strip().startswith("```")) // 2,
        "code_lang_tagged": len(re.findall(r"^```[a-zA-Z]+", t, re.M)),
        "bullets": len(bullets),
        "bold_lead_bullets": sum(1 for b in bullets if re.match(r"\*\*[^*]+\*\*", b)),
        "emoji_bullets": sum(1 for b in bullets if EMOJI.match(b.strip())),
        "bold_per_100w": round(100 * len(re.findall(r"\*\*[^*]+\*\*", prose)) / max(1, len(words)), 2),
        "inline_code_per_100w": round(100 * len(re.findall(r"`[^`\n]+`", prose)) / max(1, len(words)), 2),
        "em_dash": prose.count("—"),
        "you": sum(1 for w in words if w.lower() in ("you", "your", "you're", "you'll", "yours")),
        "we": sum(1 for w in words if w.lower() in ("we", "our", "we're", "us")),
        "exclaim": plain.count("!") - plain.count("!["),
        "hype": len(HYPE.findall(plain)),
        "med_sentence_words": st.median([len(re.findall(r"[A-Za-z]+", s)) for s in sents]) if sents else 0,
        "first_para_words": len(re.findall(r"[A-Za-z]+", first_para)),
        "has_numbers_claim": bool(re.search(r"\b\d+(\.\d+)?\s*(x|×|%|ms|s|MB|k|K)\b", plain)),
        "lines": len(lines),
    }


rows = {}
for f in sorted(glob.glob(sys.argv[1] + "/*.md")):
    with open(f, encoding="utf-8") as fh:
        rows[os.path.basename(f)[:-3]] = measure(fh.read())
en = {k: v for k, v in rows.items() if not v["cjk"]}
n = len(en)


def share(key):
    return f"{sum(1 for v in en.values() if v[key])}/{n}"


def med(key):
    return st.median([v[key] for v in en.values()])


print(f"표본 {len(rows)}곳(영어 {n}, CJK {len(rows) - n}) — 아래 비율·중앙값은 영어 README 기준\n")
print("레이아웃")
for k in ("centered_hero", "dark_mode_logo", "link_row", "img_in_first_screen", "side_by_side"):
    print(f"  {k:24} {share(k)}")
for k in ("h1_count", "h2", "badges", "badges_in_hero", "tables", "details", "alerts", "hr", "code_blocks", "lines"):
    print(f"  {k:24} 중앙 {med(k)}  (범위 {min(v[k] for v in en.values())}~{max(v[k] for v in en.values())})")
print("글자 쓰임")
for k in ("h2_emoji", "h2_sentence_case", "h2_title_case", "h2_question", "bullets", "bold_lead_bullets", "emoji_bullets",
          "bold_per_100w", "inline_code_per_100w", "em_dash", "code_lang_tagged"):
    print(f"  {k:24} 중앙 {med(k)}  (합 {sum(v[k] for v in en.values())})")
print("말투")
for k in ("you", "we", "exclaim", "hype", "med_sentence_words", "first_para_words"):
    print(f"  {k:24} 중앙 {med(k)}  (범위 {min(v[k] for v in en.values())}~{max(v[k] for v in en.values())})")
print(f"  {'has_numbers_claim':24} {share('has_numbers_claim')}")
print("\nCJK README:", {k: {x: v[x] for x in ('h2', 'h2_emoji', 'emoji_bullets', 'centered_hero')} for k, v in rows.items() if v['cjk']})
