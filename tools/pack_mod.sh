#!/usr/bin/env bash
# 打包 mod 并复制到创意工坊测试目录。
# 用法（Git Bash）：bash mods/tools/pack_mod.sh <MOD> [workshop_dir]
#   1. mods/<MOD> 同步到 mods-unpacked/<MOD>
#   2. 打包为 <工程根>/<MOD>.zip（内部路径 mods-unpacked/<MOD>/...，与 OneItemToRuleThemAll 一致，不含 README）
#   3. 复制 zip 到 workshop_dir（默认 1942280/3671094202）
set -eu
MOD=${1:?usage: pack_mod.sh <MOD> [workshop_dir]}
HERE=$(cd "$(dirname "$0")" && pwd)
PROJECT=$(cd "$HERE/../.." && pwd)
WORKSHOP=${2:-/d/SteamLibrary/steamapps/workshop/content/1942280/3671094202}

rm -rf "$PROJECT/mods-unpacked/$MOD"
mkdir -p "$PROJECT/mods-unpacked"
cp -r "$PROJECT/mods/$MOD" "$PROJECT/mods-unpacked/$MOD"

cd "$PROJECT"
python - "$MOD" <<'PY'
import os, sys, zipfile
mod = sys.argv[1]
root = os.path.join("mods-unpacked", mod)
out = mod + ".zip"
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("mods-unpacked/", "")
    for d, dirs, files in os.walk(root):
        dirs.sort()
        rel = os.path.relpath(d, ".").replace(os.sep, "/")
        z.writestr(rel + "/", "")
        for f in sorted(files):
            if f.lower().endswith(".md"):
                continue
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, ".").replace(os.sep, "/"))
print("packed", out)
PY
mkdir -p "$WORKSHOP"
cp "$PROJECT/$MOD.zip" "$WORKSHOP/"
echo "copied to $WORKSHOP/$MOD.zip"
