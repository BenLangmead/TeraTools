#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "# sdsl API touchpoints in project sources (excluding thirdparty)"
rg -n --no-heading "sdsl::" src/include src/Tera*/*.cpp || true

echo
echo "# direct sdsl includes in project sources"
rg -n --no-heading "#include\s*[<\"]sdsl/" src/include src/Tera*/*.cpp || true

echo
echo "# linked sdsl symbols per binary"
for bin in src/TeraMS/TeraMS src/TeraLCP/TeraLCP src/TeraIndex/TeraIndex src/TeraMEM/TeraMEM; do
  if [[ -x "$bin" ]]; then
    echo "## $bin"
    nm -C "$bin" | rg " sdsl::" | sed 's/^/  /' || true
  else
    echo "## $bin (missing; build target not present)"
  fi
  echo
done

echo "# sdsl headers transitively included from int_vector.hpp"
python - <<'PY'
from pathlib import Path
import re
root=Path('src/thirdparty/include/sdsl')
start='int_vector.hpp'
inc_re=re.compile(r'#include\s+"([^"]+)"')
seen=set(); stack=[start]
while stack:
    f=stack.pop()
    if f in seen: continue
    seen.add(f)
    p=root/f
    if not p.exists():
        continue
    for line in p.read_text(errors='ignore').splitlines():
        m=inc_re.search(line)
        if m:
            h=m.group(1)
            if (root/h).exists():
                stack.append(h)
for h in sorted(seen):
    print(h)
print(f"total_headers={len(seen)}")
PY
