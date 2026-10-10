"""打包 mod 并复制到创意工坊测试目录（PowerShell / cmd / bash 都能直接运行）。

用法：python mods/tools/pack_mod.py <MOD> [workshop_dir]
  1. mods/<MOD> 同步到 mods-unpacked/<MOD>
  2. 打包为 <工程根>/<MOD>.zip（内部路径 mods-unpacked/<MOD>/...，与 OneItemToRuleThemAll 一致，不含 .md）
  3. 复制 zip 到 workshop_dir（默认 1942280/3671094202）
"""
import os
import shutil
import sys
import zipfile

DEFAULT_WORKSHOP = r"D:\SteamLibrary\steamapps\workshop\content\1942280\3671094202"


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: python pack_mod.py <MOD> [workshop_dir]")
        return 2
    mod = sys.argv[1]
    if not mod.startswith("Mojimoon-"):
        mod = "Mojimoon-" + mod
    workshop = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_WORKSHOP
    project = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    src = os.path.join(project, "mods", mod)
    if not os.path.isdir(src):
        print("mod not found: " + src)
        return 2

    # 1. 同步到 mods-unpacked
    unpacked = os.path.join(project, "mods-unpacked", mod)
    if os.path.isdir(unpacked):
        shutil.rmtree(unpacked)
    shutil.copytree(src, unpacked)

    # 2. 打包（目录项也写入，与原版 mod 的 zip 结构一致）
    out = os.path.join(project, mod + ".zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("mods-unpacked/", "")
        for d, dirs, files in os.walk(unpacked):
            dirs.sort()
            rel = os.path.relpath(d, project).replace(os.sep, "/")
            z.writestr(rel + "/", "")
            for f in sorted(files):
                if f.lower().endswith(".md"):
                    continue
                p = os.path.join(d, f)
                z.write(p, os.path.relpath(p, project).replace(os.sep, "/"))
    print("packed " + out)

    # 3. 复制到创意工坊目录
    os.makedirs(workshop, exist_ok=True)
    shutil.copy2(out, os.path.join(workshop, mod + ".zip"))
    print("copied to " + os.path.join(workshop, mod + ".zip"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
