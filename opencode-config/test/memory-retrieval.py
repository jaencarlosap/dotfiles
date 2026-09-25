#!/usr/bin/env python3
"""Mide el acierto de la busqueda de memoria en tres variantes, para decidir
con datos (y no por intuicion) si la tabla de sinonimos aporta algo.

  python3 test/memory-retrieval.py            # las tres variantes
  python3 test/memory-retrieval.py --verbose  # ademas, que falla en cada una
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(HERE)
MEM = os.path.join(REPO, "memory")
CASES = json.load(open(os.path.join(HERE, "memory-retrieval.json")))["cases"]


def run(cmd, env):
    e = {**os.environ, "OPENCODE_MEMORY_DIR": MEM, **env}
    r = subprocess.run(cmd, capture_output=True, text=True, env=e, cwd=REPO)
    return r.stdout + r.stderr


VARIANTS = {
    # lexico de memory.sh (palabras + tabla de sinonimos), sin indice ni vectores
    "lexico (respaldo, sin tabla)": (lambda q: ["bash", "bin/memory.sh", "search", *q.split()],
                       {"MEMORY_INDEX_MIN": "999999", "MEMORY_VENV": "/nonexistent", "MEMORY_EMBED_URL": "http://127.0.0.1:1/x"}),
    # indice: FTS5 solo (sin embedder)
    "fts5 solo": (lambda q: ["python3", "bin/_memory_index.py", "search", *q.split()],
                  {"MEMORY_VENV": "/nonexistent", "MEMORY_EMBED_URL": "http://127.0.0.1:1/x"}),
    # indice hibrido: FTS5 + vectorial con el embedder local. NO usa la tabla.
    "hibrido (sin tabla)": (lambda q: ["python3", "bin/_memory_index.py", "search", *q.split()], {}),
}


def main():
    verbose = "--verbose" in sys.argv
    print(f"  {len(CASES)} preguntas\n")
    for name, (build, env) in VARIANTS.items():
        ok, fails = 0, []
        for c in CASES:
            out = run(build(c["q"]), env)
            if c["expect"] in out:
                ok += 1
            else:
                fails.append(c["q"])
        pct = 100 * ok / len(CASES)
        print(f"  {name:22s} {ok:2d}/{len(CASES)}  ({pct:.0f}%)")
        if verbose and fails:
            for f in fails:
                print(f"       ✗ {f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
