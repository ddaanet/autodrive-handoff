import subprocess, os, re, sys, csv
ROOT="/Users/david/code"
P=".claude/handoff-task.md"; T=".claude/handoff-todo.md"
def g(repo,*a):
    return subprocess.run(["git","-C",repo,*a],capture_output=True)
LI=re.compile(r'^\s*(?:[-*+]|\d+[.)])\s+')
CB=re.compile(r'^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]')
H=re.compile(r'^\s{0,3}#{1,6}\s')
H2=re.compile(r'^\s{0,3}##\s+(.*\S)')
rows=[]
os.makedirs("/tmp/claude/survey/blobs",exist_ok=True)
for d in sorted(os.listdir(ROOT)):
    repo=f"{ROOT}/{d}"
    if not os.path.exists(repo+"/.git"): continue
    out=g(repo,"log","--all","--format=%H %cI","--",P).stdout.decode().split("\n")
    cs=[l.split() for l in out if l.strip()]
    cs.sort(key=lambda x:x[1])
    # sort by committer time (ISO with tz: convert)
    from datetime import datetime
    cs.sort(key=lambda x:datetime.fromisoformat(x[1]))
    prev=None
    for sha,date in cs:
        r=g(repo,"show",f"{sha}:{P}")
        if r.returncode!=0: continue
        b=r.stdout
        if b==prev: continue
        prev=b
        todo=g(repo,"cat-file","-e",f"{sha}:{T}").returncode==0
        t=b.decode("utf-8","replace")
        lines=t.split("\n")
        if lines and lines[-1]=="": lines=lines[:-1]
        body=[l for l in lines if l.strip() and not H.match(l)]
        li=[l for l in lines if LI.match(l)]
        cb=[l for l in lines if CB.match(l)]
        h2=[H2.match(l).group(1) for l in lines if H2.match(l)]
        bodytxt="\n".join(l for l in lines if not H.match(l))
        fn=f"{d}_{sha[:8]}.md"
        open("/tmp/claude/survey/blobs/"+fn,"w").write(t)
        rows.append([d,date,sha[:8],len(b),len(t),len(t.split()),len(lines),len(body),len(li),len(cb),len(h2),"|".join(h2),int(todo),len(bodytxt),len(bodytxt.split())])
hdr="repo date sha bytes chars words lines body_lines list_lines checkbox_lines n_h2 h2_titles todo body_chars body_words".split()
with open("/tmp/claude/survey/versions.tsv","w") as f:
    w=csv.writer(f,delimiter="\t"); w.writerow(hdr); w.writerows(rows)
print(len(rows))
