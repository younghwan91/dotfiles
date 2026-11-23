"""트렌딩 README 의 이미지·브랜딩·푸터 재기 — 이미지 출처·형식·alt·width, 머리의 로고·이름·태그라인, 끝맺음(라이선스·감사·커뮤니티 등).

    python3 readme_assets.py <README 들을 모은 폴더>
"""
import glob
import re
import sys
from collections import Counter

IMG_URL = re.compile(r"""!\[([^\]]*)\]\(([^)\s]+)|<img\b[^>]*?\bsrc=["']([^"']+)["'][^>]*>|<source\b[^>]*?\bsrcset=["']([^"']+)["']""", re.I)


def host(u):
    if "shields.io" in u or "badge" in u or "badgen" in u:
        return "badge"
    if "user-attachments/assets" in u:
        return "github-upload(user-attachments)"
    if "user-images.githubusercontent.com" in u or "private-user-images" in u:
        return "github-upload(old)"
    if "raw.githubusercontent.com" in u or "/raw/" in u or "?raw=true" in u:
        return "raw.githubusercontent"
    if re.match(r"https?://", u):
        if "star-history" in u:
            return "star-history"
        if "contrib.rocks" in u or "contributors-img" in u or "opencollective" in u:
            return "contributors-img"
        return "external-site"
    return "repo-relative"


def fmt(u):
    m = re.search(r"\.(png|gif|svg|webp|jpe?g|mp4|webm|avif)(\?|$)", u, re.I)
    return (m.group(1).lower().replace("jpeg", "jpg") if m else ("(upload-id)" if "user-attachments" in u else "?"))


hosts, fmts = Counter(), Counter()
alt_total = alt_ok = widths = linked = 0
brand = Counter()
foot = Counter()
n = 0
for f in sorted(glob.glob(sys.argv[1] + "/*.md")):
    with open(f, encoding="utf-8") as fh:
        t = fh.read()
    n += 1
    lines = t.splitlines()
    top = "\n".join(lines[:30])
    for m in IMG_URL.finditer(t):
        alt, u1, u2, u3 = m.group(1), m.group(2), m.group(3), m.group(4)
        u = u1 or u2 or u3
        h = host(u)
        hosts[h] += 1
        if h == "badge":
            continue
        fmts[fmt(u)] += 1
        whole = m.group(0)
        if whole.startswith("!["):
            alt_total += 1
            alt_ok += bool(alt.strip())
        elif whole.lower().startswith("<img"):
            alt_total += 1
            a = re.search(r"""\balt=["']([^"']*)["']""", whole)
            alt_ok += bool(a and a.group(1).strip())
            widths += bool(re.search(r"\bwidth=", whole))
    linked += len(re.findall(r"\[!\[[^\]]*\]\([^)]*\)\]\(|<a [^>]*>\s*<img", t))
    # 브랜딩
    logo = re.search(r"logo|banner|wordmark|icon", top, re.I) and re.search(r"<img|!\[|<picture", top)
    brand["logo_or_banner_top"] += bool(logo)
    brand["dark_mode_picture"] += "prefers-color-scheme" in t
    brand["banner_full_width"] += bool(re.search(r'width=["\']?(100%|[89]\d\d)', top))
    brand["h1_text_name"] += bool(re.search(r"^# \S|<h1", top, re.M))
    brand["bold_tagline_top"] += bool(re.search(r"^\s*(<p[^>]*>\s*)?\*\*[^*]{15,}\*\*|<b>[^<]{15,}</b>|<strong>[^<]{15,}</strong>", top, re.M))
    brand["social_links_top"] += bool(re.search(r"discord|twitter\.com|x\.com/|linkedin|youtube", top, re.I))
    brand["translations_top"] += bool(re.search(r"한국어|日本語|中文|简体|Español|Deutsch|Français|README\.[a-z-]+\.md", top))
    # 푸터: 마지막 35줄과 마지막 ## 절들
    tail = "\n".join(lines[-35:])
    last_h2 = [h.strip().lower() for h in re.findall(r"^## (.+)$", t, re.M)][-3:]
    foot["license_section_last3"] += any("licen" in h or "許可" in h or "许可" in h or "协议" in h for h in last_h2)
    foot["contributors"] += bool(re.search(r"contrib\.rocks|all-contributors|## contributors|贡献者", t, re.I))
    foot["star_history"] += "star-history" in t.lower()
    foot["sponsors_tail"] += bool(re.search(r"sponsor|backer|赞助|후원", tail, re.I))
    foot["made_by_tail"] += bool(re.search(r"made (with|by)|built (with|by)|crafted by|❤️|♥", tail, re.I))
    foot["back_to_top"] += bool(re.search(r"back to top|⬆|↑ top|\(#readme\)|\(#top\)", t, re.I))
    foot["acknowledg"] += bool(re.search(r"acknowledg|thanks|credits|致谢", t, re.I))
    foot["citation"] += bool(re.search(r"@(article|misc|software|inproceedings)\{|## citation|cite this", t, re.I))
    foot["community_tail"] += bool(re.search(r"discord|slack|community|x\.com|twitter", tail, re.I))
    foot["trademark_or_security_tail"] += bool(re.search(r"trademark|security", tail, re.I))
    foot["ends_with_license_line"] += bool(re.search(r"(MIT|Apache|GPL|BSD|license)", "\n".join(lines[-6:]), re.I))

print(f"표본 {n}곳\n\n이미지 출처(배지 포함 횟수)")
for k, v in hosts.most_common():
    print(f"  {k:34} {v}")
print("이미지 형식(배지 제외)")
for k, v in fmts.most_common():
    print(f"  {k:12} {v}")
print(f"alt 글 있음 {alt_ok}/{alt_total} · <img> 에 width {widths} · 링크로 감싼 그림 {linked}")
print("\n브랜딩(README 수)")
for k, v in brand.items():
    print(f"  {k:24} {v}/{n}")
print("\n푸터(README 수)")
for k, v in foot.items():
    print(f"  {k:30} {v}/{n}")
