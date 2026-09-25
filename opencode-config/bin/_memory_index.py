#!/usr/bin/env python3
"""Indice de busqueda de la memoria. Escala en tres niveles, y el nivel lo
decide el tamano, no el usuario:

  1. palabras + sinonimos (en memory.sh, sin indice)     ~126 ms, 0 dependencias
  2. SQLite FTS5 (ranking BM25)                          se usa desde MEMORY_INDEX_MIN hechos
  3. vectorial (embeddings + coseno con numpy)           solo si el lexico no encuentra nada

Los ficheros .md siguen siendo la FUENTE DE VERDAD: esto es un indice derivado
y borrable (`memory/index.db`, gitignored). Si se borra o se corrompe, se
reconstruye solo; nunca contiene nada que no este en un .md.

No se usa sqlite-vec a proposito: en este Mac solo carga con el python de
Homebrew (3.14) y ahi fastembed no instala (onnxruntime no tiene wheels).
Con <10k hechos, un producto escalar con numpy tarda microsegundos, asi que la
extension no aporta y si costaria un interprete mas.

El embedder es opcional y vive en su propio venv (MEMORY_VENV, por defecto
~/.cache/opencode-memory-venv): sin el, los niveles 1 y 2 funcionan igual.
"""
import glob
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys

HOME = os.path.expanduser("~")
MEM = os.environ.get("OPENCODE_MEMORY_DIR", f"{HOME}/.config/opencode/memory")
DB = os.environ.get("MEMORY_INDEX_DB", os.path.join(MEM, "index.db"))
VENV = os.environ.get("MEMORY_VENV", os.path.join(HOME, ".cache", "opencode-memory-venv"))
MODEL = os.environ.get("MEMORY_EMBED_MODEL", "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
# Embedder por HTTP: el modelo local que ya sirve llama-swap. Medido el
# 2026-09-25: Qwen3-Embedding-0.6B (1024 dims) acierta 5/5 en las preguntas
# donde el MiniLM del venv acertaba 2/5 —fallaba incluso en ingles— y responde
# en 150-230 ms en caliente (1.5 s la primera, por el swap de modelo).
EMBED_URL = os.environ.get("MEMORY_EMBED_URL", "http://pcgamer:1234/v1/embeddings")
EMBED_MODEL_HTTP = os.environ.get("MEMORY_EMBED_MODEL_HTTP", "qwen-embed")
EMBED_TIMEOUT = float(os.environ.get("MEMORY_EMBED_TIMEOUT", "20"))
REPO_MEM = ".agent/memory.md"


def sources():
    """Ficheros que componen la memoria, en orden de importancia."""
    out = []
    p = os.path.join(MEM, "preferences.md")
    if os.path.exists(p):
        out.append(p)
    out += sorted(glob.glob(os.path.join(MEM, "topics", "*.md")))
    out += sorted(glob.glob(os.path.join(MEM, "recipes", "*.md")))
    if os.path.exists(REPO_MEM):
        out.append(os.path.abspath(REPO_MEM))
    return out


def entries():
    """Una entrada por linea util: (fichero, linea, texto)."""
    for f in sources():
        try:
            lines = open(f, encoding="utf8", errors="replace").read().splitlines()
        except OSError:
            continue
        for i, l in enumerate(lines, 1):
            t = l.strip()
            if not t or t.startswith(("#", "<!--")):
                continue
            yield f, i, t.lstrip("- ").strip()


def fingerprint():
    h = hashlib.sha256()
    for f in sources():
        try:
            h.update(f.encode())
            h.update(str(os.path.getmtime(f)).encode())
        except OSError:
            pass
    return h.hexdigest()[:16]


def connect():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    db = sqlite3.connect(DB)
    db.execute("create table if not exists meta(k text primary key, v text)")
    db.execute("create table if not exists facts(id integer primary key, file text, line integer, text text, emb blob)")
    db.execute("create virtual table if not exists fts using fts5(text, content='facts', content_rowid='id')")
    return db


def stale(db):
    row = db.execute("select v from meta where k='fingerprint'").fetchone()
    return (row[0] if row else None) != fingerprint()


def build(db, verbose=False):
    """Reconstruye el indice lexico. Conserva los embeddings de las entradas
    cuyo texto no cambio: reembeddear todo en cada guardado seria absurdo."""
    old = {t: e for t, e in db.execute("select text, emb from facts where emb is not null")}
    db.execute("delete from facts")
    db.execute("delete from fts")
    rows = [(f, i, t, old.get(t)) for f, i, t in entries()]
    db.executemany("insert into facts(file,line,text,emb) values(?,?,?,?)", rows)
    db.execute("insert into fts(rowid, text) select id, text from facts")
    db.execute("insert or replace into meta values('fingerprint',?)", (fingerprint(),))
    db.commit()
    kept = sum(1 for r in rows if r[3] is not None)
    if verbose:
        print(f"  indice: {len(rows)} entradas, {kept} con embedding reutilizado")
    return len(rows)


def embedder_tag():
    """Identifica QUE produjo los vectores guardados. Si cambia, los de antes
    no sirven: un vector de 384 dims (MiniLM) junto a uno de 1024 (Qwen3) hacia
    reventar la busqueda con 'inhomogeneous shape'. Paso de verdad al migrar el
    embedder el 2026-09-25."""
    return f"http:{EMBED_MODEL_HTTP}" if http_embedder_ok() else (f"venv:{MODEL}" if venv_python() else "none")


def ensure(db, verbose=False):
    if stale(db):
        build(db, verbose)
    # Vectores de otro modelo: se tiran (el indice lexico no se toca).
    tag = embedder_tag()
    if tag != "none":
        row = db.execute("select v from meta where k='embedder'").fetchone()
        if row and row[0] != tag:
            n = db.execute("select count(*) from facts where emb is not null").fetchone()[0]
            db.execute("update facts set emb=null")
            db.execute("insert or replace into meta values('embedder',?)", (tag,))
            db.commit()
            if verbose or n:
                print(f"  (embedder cambio: {row[0]} -> {tag}; {n} vectores invalidados, se rehacen con `memory.sh index --embed`)", file=sys.stderr)
        elif not row:
            db.execute("insert or replace into meta values('embedder',?)", (tag,))
            db.commit()


# ── nivel 3: embeddings ──────────────────────────────────────────────────
def venv_python():
    p = os.path.join(VENV, "bin", "python")
    return p if os.path.exists(p) else None


def http_embedder_ok():
    """¿Responde el embedder del servidor local? Se comprueba con una llamada
    minima y cache en proceso: si no hay red a pcgamer, se cae al venv (si
    esta) y, si tampoco, al nivel lexico."""
    global _HTTP_OK
    if _HTTP_OK is not None:
        return _HTTP_OK
    _HTTP_OK = embed_http(["ping"]) is not None
    return _HTTP_OK


_HTTP_OK = None


def embed_http(texts):
    import urllib.error
    import urllib.request
    body = json.dumps({"model": EMBED_MODEL_HTTP, "input": texts}).encode()
    req = urllib.request.Request(EMBED_URL, body, {"Content-Type": "application/json"})
    try:
        r = urllib.request.urlopen(req, timeout=EMBED_TIMEOUT)
        d = json.loads(r.read())
        return [x["embedding"] for x in d["data"]]
    except (urllib.error.URLError, KeyError, json.JSONDecodeError, TimeoutError, OSError):
        return None


def embedder_available():
    return http_embedder_ok() or venv_python() is not None


def embed_texts(texts):
    """Primero el servidor local (150-230 ms); si no hay red, el venv."""
    if http_embedder_ok():
        v = embed_http(texts)
        if v:
            return v
    py = venv_python()
    if not py:
        return None
    code = (
        "import sys,json\n"
        "from fastembed import TextEmbedding\n"
        f"m=TextEmbedding({MODEL!r})\n"
        "data=json.load(sys.stdin)\n"
        "print(json.dumps([[round(float(x),6) for x in v] for v in m.embed(data)]))\n"
    )
    r = subprocess.run([py, "-c", code], input=json.dumps(texts), capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        print(f"  (embedder fallo: {r.stderr.strip().splitlines()[-1][:160] if r.stderr.strip() else '?'})", file=sys.stderr)
        return None
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError):
        return None


def pack(vec):
    import array
    return sqlite3.Binary(array.array("f", vec).tobytes())


def unpack(blob):
    import array
    a = array.array("f")
    a.frombytes(blob)
    return list(a)


def cmd_embed(_args):
    if not embedder_available():
        print(f"  no hay embedder: crea el venv con `make memory_vectors` (o MEMORY_VENV=<ruta>)")
        return 1
    db = connect()
    ensure(db)
    todo = db.execute("select id, text from facts where emb is null").fetchall()
    if not todo:
        print("  todos los hechos ya tienen embedding")
        return 0
    vecs = embed_texts([t for _, t in todo])
    if not vecs:
        return 1
    db.executemany("update facts set emb=? where id=?", [(pack(v), i) for (i, _), v in zip(todo, vecs)])
    db.commit()
    print(f"  {len(todo)} entradas embebidas (dim {len(vecs[0])})")
    return 0


def vector_search(db, query, limit):
    rows = db.execute("select id, file, line, text, emb from facts where emb is not null").fetchall()
    if not rows:
        return []
    qv = embed_texts([query])
    if not qv:
        return []
    try:
        import numpy as np
    except ImportError:
        return []
    # La dimension de referencia es la de la CONSULTA, no la mayoritaria: si la
    # consulta trae 1024 y en la base quedan vectores de 384 (embedder viejo),
    # el producto escalar falla igual. Se descarta lo que no encaje y se avisa.
    dim = len(qv[0])
    vecs = [(r, v) for r, v in ((r, unpack(r[4])) for r in rows) if len(v) == dim]
    bad = len(rows) - len(vecs)
    if bad:
        print(f"  ({bad} vectores de otra dimension ignorados; corre `memory.sh index --embed`)", file=sys.stderr)
    if not vecs:
        return []
    rows = [r for r, _ in vecs]
    V = np.array([v for _, v in vecs], dtype="float32")
    V /= np.linalg.norm(V, axis=1, keepdims=True) + 1e-9
    q = np.array(qv[0], dtype="float32")
    q /= np.linalg.norm(q) + 1e-9
    sims = V @ q
    order = np.argsort(-sims)[:limit]
    # Umbral medido con este modelo (paraphrase-multilingual-MiniLM): un acierto
    # real cae en 0.42-0.62 y el ruido en 0.24-0.33. Con 0.15 "siempre" habia
    # resultado: preguntar por espacio en disco devolvia hechos de Jira porque
    # eran los menos malos. Mas vale decir que no hay nada parecido.
    floor = float(os.environ.get("MEMORY_VECTOR_MIN", "0.40"))
    return [(rows[i][1], rows[i][2], rows[i][3], float(sims[i])) for i in order if sims[i] >= floor]


# ── comandos ─────────────────────────────────────────────────────────────
def cmd_build(_args):
    db = connect()
    n = build(db, verbose=True)
    return 0 if n else 1


def cmd_stats(_args):
    db = connect()
    ensure(db)
    n = db.execute("select count(*) from facts").fetchone()[0]
    e = db.execute("select count(*) from facts where emb is not null").fetchone()[0]
    print(f"  entradas indexadas : {n}")
    print(f"  con embedding      : {e}" + ("" if e else "   (nivel vectorial apagado)"))
    print(f"  base               : {DB} ({os.path.getsize(DB) if os.path.exists(DB) else 0} bytes, derivada y borrable)")
    if http_embedder_ok():
        print(f"  embedder           : {EMBED_MODEL_HTTP} via {EMBED_URL}")
    elif venv_python():
        print(f"  embedder           : venv local {VENV} (sin red al servidor)")
    else:
        print("  embedder           : ninguno (nivel vectorial apagado)")
    print(f"  umbral FTS5        : desde {os.environ.get('MEMORY_INDEX_MIN', '150')} entradas (ahora {'SI' if n >= int(os.environ.get('MEMORY_INDEX_MIN', '150')) else 'no'} se usa)")
    return 0


def fts_search(db, terms, limit):
    q = " OR ".join(f'"{t}"*' for t in terms if re.search(r"\w", t))
    if not q:
        return []
    try:
        rows = db.execute(
            "select f.file, f.line, f.text, bm25(fts) from fts join facts f on f.id=fts.rowid "
            "where fts match ? order by bm25(fts) limit ?", (q, limit)).fetchall()
    except sqlite3.OperationalError:
        return []
    return [(r[0], r[1], r[2], -r[3]) for r in rows]


def rrf(lists, k=60):
    """Reciprocal Rank Fusion: la forma estandar de combinar dos rankings sin
    tener que normalizar puntuaciones que no son comparables (BM25 vs coseno).
    Cada lista aporta 1/(k+posicion) a cada documento."""
    score, keep = {}, {}
    for lst in lists:
        for rank, hit in enumerate(lst):
            key = (hit[0], hit[1])
            score[key] = score.get(key, 0.0) + 1.0 / (k + rank + 1)
            keep[key] = hit
    return [keep[key] for key in sorted(score, key=lambda x: -score[x])]


def cmd_search(args):
    """Busqueda HIBRIDA: FTS5 (lexico, exacto con identificadores) + vectorial
    (semantico, cruza idiomas) fusionados con RRF. Ninguno gana solo: el lexico
    no sabe que "credenciales" es "login", y el vectorial no distingue
    `--no-oauth` de `--no-browser`."""
    limit = int(os.environ.get("MEMORY_SEARCH_MAX", "20"))
    db = connect()
    ensure(db)
    lex = fts_search(db, args, limit)
    vec = vector_search(db, " ".join(args), limit) if embedder_available() else []
    if lex and vec:
        hits, how = rrf([lex, vec])[:limit], "hibrido fts5+vector"
    elif vec:
        hits, how = vec, "vector"
    else:
        hits, how = lex, "fts5"
    if not hits:
        print("no match in memory for: " + " ".join(args))
        if how == "vector":
            print("  (tampoco por significado: nada con similitud suficiente. Ese conocimiento no esta guardado)")
        return 0
    for f, line, text, score in hits:
        short = f.replace(MEM + "/", "memory/")
        sim = f"  [{score:.2f}]" if how == "vector" else ""
        print(f"{short}:{line}: - {text}{sim}")
    print(f"  ({len(hits)} via {how})")
    return 0


def cmd_has_embedder(_args):
    """Para que memory.sh decida sin duplicar la logica. Silencioso a proposito."""
    return 0 if embedder_available() else 1


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    fn = {"build": cmd_build, "embed": cmd_embed, "stats": cmd_stats, "search": cmd_search, "has-embedder": cmd_has_embedder}.get(cmd)
    if not fn:
        print(f"unknown: {cmd}", file=sys.stderr)
        return 1
    return fn(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
