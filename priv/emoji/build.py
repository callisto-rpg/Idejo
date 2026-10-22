# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Builds priv/emoji/emoji.json from gemoji and lists the Twemoji SVGs it needs (TP-17).
# Usage: python3 -I priv/emoji/build.py GEMOJI_INDEX_JS TWEMOJI_SVG_DIR priv/emoji/emoji.json
# then copy each entry's "file".svg from TWEMOJI_SVG_DIR to priv/static/emoji/.
import json, re, sys, os
src, svgdir, out = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding="utf-8").read()
start = text.index("export const gemoji = [") + len("export const gemoji = ")
end = text.index("\n]\n", start) + 2
body = text[start:end]
body = re.sub(r"'((?:[^'\\]|\\.)*)'", lambda m: json.dumps(m.group(1).replace("\\'", "'")), body)
body = re.sub(r"(\n\s*)(\w+):", r'\1"\2":', body)
items = json.loads(body)

def twemoji_name(e):
    if "‍" not in e:
        e = e.replace("️", "")
    return "-".join("%x" % ord(c) for c in e)

kept, missing = [], []
for it in items:
    code = twemoji_name(it["emoji"])
    if not os.path.exists(os.path.join(svgdir, code + ".svg")):
        code = twemoji_name(it["emoji"].replace("\ufe0f", ""))
    if os.path.exists(os.path.join(svgdir, code + ".svg")):
        kept.append({"emoji": it["emoji"], "names": it["names"], "category": it["category"], "file": code})
    else:
        missing.append((it["emoji"], it["names"]))
json.dump(kept, open(out, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(len(items), "gemoji;", len(kept), "with a Twemoji image;", len(missing), "missing:", missing[:10])
