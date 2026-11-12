# 列出 mod_main.gd 被加载时（mod 的 _init 阶段）连带编译的原版脚本：preload / extends 以及按名字引用的全局类，递归。
# 只应是数据类脚本；出现 unit.gd / turret.gd / main.gd / 界面脚本，说明其他 mod 给它们装的扩展会接不上子类（正式版崩溃）。
# 用法：python mods/tools/check_init_deps.py 1.2 mods/Mojimoon-BroEditor [要查引用链的脚本路径…]
import re,os,sys,collections
root,mod=sys.argv[1],sys.argv[2]
files={};cls={}
def add(base,prefix):
    for d,_,fs in os.walk(base):
        if prefix=="" and ("mods-unpacked" in d or ".import" in d or os.sep+"mods" in d or os.sep+"addons" in d): continue
        for f in fs:
            if f.endswith(".gd"):
                p=prefix+os.path.relpath(os.path.join(d,f),base).replace("\\","/")
                s=re.sub(r"#.*","",open(os.path.join(d,f),encoding="utf-8",errors="ignore").read())
                files[p]=s
                m=re.search(r"^class_name\s+(\w+)",s,re.M)
                if m and prefix=="": cls[m.group(1)]=p
add(root,""); name=os.path.basename(mod.rstrip("/")); pre="mods-unpacked/"+name+"/"; add(mod,pre)
def deps(p):
    s=files[p]; out={}
    for m in re.finditer(r'(?:preload\(|extends\s+)"res://([^"]+\.gd)"',s): out[m.group(1)]="preload/extends"
    s2=re.sub(r'"[^"\n]*"',"",s)
    for w in set(re.findall(r"\b[A-Z]\w+\b",s2)):
        if w in cls and cls[w]!=p: out.setdefault(cls[w],w)
    return out
st=pre+"mod_main.gd"; prev={st:None}; q=collections.deque([st])
while q:
    p=q.popleft()
    if p not in files: continue
    for d,why in deps(p).items():
        if d not in prev: prev[d]=(p,why); q.append(d)
van=sorted(p for p in prev if not p.startswith("mods-unpacked/"))
print(name,": vanilla scripts compiled at mod init:",len(van))
for t in sys.argv[3:]:
    if t in prev:
        chain=[];p=t
        while prev[p]: chain.append(f"{p} <-[{prev[p][1]}]"); p=prev[p][0]
        print("  REACHES "+"  ".join(chain))
if len(van)<40: print("  ",van)
