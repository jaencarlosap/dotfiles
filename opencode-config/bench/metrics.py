import sqlite3, json, collections, sys, os
DB='/Users/jaencarlos/.local/share/opencode/opencode.db'
db=sqlite3.connect(f'file:{DB}?mode=ro',uri=True); c=db.cursor()

def stats_for(directory):
    """Metricas de la ULTIMA sesion que corrio en ese directorio."""
    rows=list(c.execute("SELECT id, model, time_created FROM session WHERE directory=? ORDER BY time_created DESC", (directory,)))
    if not rows: return None
    sid, model, _ = rows[0]
    calls=0; errs=0; skills=[]; blocks=0; cmds=[]; tools=collections.Counter()
    for (d,) in c.execute("SELECT data FROM part WHERE session_id=? ORDER BY time_created", (sid,)):
        try: o=json.loads(d)
        except Exception: continue
        if o.get('type')!='tool': continue
        calls+=1; t=o.get('tool'); tools[t]+=1
        st=o.get('state') or {}
        if t=='skill': skills.append(((st.get('input') or {}).get('name','?')))
        if st.get('status')=='error':
            errs+=1
            if 'BLOCKED' in str(st.get('error','')): blocks+=1
        if t=='bash':
            cmd=str((st.get('input') or {}).get('command',''))[:120]
            if cmd: cmds.append(cmd)
    cnt=collections.Counter(cmds)
    repes=sum(v-1 for v in cnt.values() if v>1)
    peor=max(cnt.values()) if cnt else 0
    # Tokens, del propio `usage` que devuelve el servidor (lo guarda opencode en
    # cada mensaje del asistente). `prompt0` = input del PRIMER turno = coste
    # fijo real del prompt (system + tools + mensaje del usuario); `turns` =
    # vueltas del bucle; `out` = output + reasoning de toda la sesion.
    turns=0; prompt0=None; out=0; agent=None
    for (d,) in c.execute("SELECT data FROM message WHERE session_id=? ORDER BY time_created", (sid,)):
        try: o=json.loads(d)
        except Exception: continue
        if o.get('role')!='assistant': continue
        agent=agent or o.get('agent')
        tk=o.get('tokens') or {}
        if not tk: continue
        turns+=1
        if prompt0 is None: prompt0=tk.get('input',0)+((tk.get('cache') or {}).get('read',0))
        out+=(tk.get('output') or 0)+(tk.get('reasoning') or 0)
    try: model=json.loads(model).get('id')
    except Exception: pass
    return dict(model=model, agent=agent, calls=calls, errs=errs, blocks=blocks, repes=repes, peor=peor,
                skills=sorted(set(skills)), bash=tools.get('bash',0), turns=turns, prompt0=prompt0, out=out)

if __name__=='__main__':
    print(json.dumps(stats_for(sys.argv[1]), ensure_ascii=False))
