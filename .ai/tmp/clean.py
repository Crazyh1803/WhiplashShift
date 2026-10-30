import re, json
files = ["tools/city_pipeline/city_realism_families.py", "tools/city_pipeline/city_realism_parts.py", "tools/city_pipeline/city_realism_streets.py"]
res = {}
for fn in files:
    lines = open(fn, encoding="utf-8").read().split("\n")
    out = []
    for ln in lines:
        if re.match(r"^\s*pts( \+=|\s*=)", ln):
            continue
        ln = re.sub(r'"[^"]*" if False else ("[^"]*")', r"\1", ln)
        ln = ln.replace("sx0 + 2.4 if False else sx0 + 0.15", "sx0 + 0.15")
        if "if False" in ln:
            m = re.match(r"^(\s*)(\w+ \+= )(.*) if False else (.*)$", ln)
            if m:
                out.append(f"{m.group(1)}{m.group(2)}{m.group(4)}")
                continue
            m = re.match(r"^(\s*)(.*?) if False else (.*)$", ln)
            if m.group(3).strip() == "None":
                continue
            out.append(f"{m.group(1)}{m.group(3)}")
        else:
            out.append(ln)
    changed = True
    while changed:
        changed = False
        for i, ln in enumerate(out):
            s = ln.strip()
            if re.match(r"^(for|if|while)\b.*:\s*(#.*)?$", s):
                ind = len(ln) - len(ln.lstrip())
                j = i + 1
                while j < len(out) and not out[j].strip():
                    j += 1
                nxt = out[j] if j < len(out) else ""
                nind = len(nxt) - len(nxt.lstrip())
                if not nxt.strip() or nind <= ind or nxt.strip() == "pass":
                    del out[i:(j + 1 if nxt.strip() == "pass" else i + 1)]
                    changed = True
                    break
    src = "\n".join(out)
    compile(src, fn, "exec")
    open(fn, "w", encoding="utf-8", newline="\n").write(src)
    res[fn] = "ok"
print("AK: " + json.dumps(res))
