#!/usr/bin/env python3
"""Logica de mcp.sh (ver bin/mcp.sh para el porque). Un solo fichero para poder
testearlo directo: MCP_MCPORTER_BIN apunta a un mcporter falso en los tests."""
import fnmatch
import json
import os
import shlex
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CATALOG = os.environ.get("MCP_CATALOG", f"{HOME}/.mcporter/mcporter.json")
POLICY = os.environ.get("MCP_POLICY", os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "mcporter", "policy.json"))
MAX_CHARS = int(os.environ.get("MCP_MAX_CHARS", "6000"))
CACHE_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "mcp-sh-cache")
CACHE_TTL = int(os.environ.get("MCP_CACHE_TTL", "600"))
MCPORTER = os.environ.get("MCP_MCPORTER_BIN", "mcporter")

USAGE = """mcp.sh — every MCP server you have, as commands. Run with bash.

  mcp.sh list                          servers in the catalog (name, what for, auth hint)
  mcp.sh tools <server> [filter]       tool signatures, compact; [write] marks the ones that change things
  mcp.sh describe <server>.<tool>      one tool in full: parameters, types, what each means
  mcp.sh call <server>.<tool> k=v ...  run a read tool  (key=value; strings with spaces: key="a b"; key=@file)
  mcp.sh call --write <server>.<tool> k=v ...   run a tool that creates/changes/sends (asks the user first)
  mcp.sh status [server]               connect and report: authenticated? how many tools?

Rules: the output is the fact — ids, URLs and numbers come from it, never from
you. A tool `tools` does not list cannot be called. If a call says
"unauthorized" or "needs auth", the user must run `mcporter auth <server>` once.
"""


def die(msg, rc=1):
    print(msg, file=sys.stderr)
    sys.exit(rc)


def load_json(path, what):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        die(f"no {what} at {path} (make install links it)")
    except json.JSONDecodeError as e:
        die(f"{what} is not valid JSON ({path}): {e}")


def servers():
    return load_json(CATALOG, "MCP catalog").get("mcpServers", {})


def policy_for(server):
    pol = load_json(POLICY, "MCP policy")
    return pol.get("servers", {}).get(server) or pol.get("default", {}), server in pol.get("servers", {})


def matches(name, patterns):
    n = name.lower()
    return any(fnmatch.fnmatch(n, p.lower()) for p in patterns or [])


def verdict(server, tool, write):
    p, _ = policy_for(server)
    if matches(tool, p.get("deny")):
        return "deny"
    if matches(tool, p.get("write")):
        return "allow" if write else "write-required"
    return "allow"


def run(args, stdin_null=True):
    return subprocess.run([MCPORTER, *args], capture_output=True, text=True, stdin=subprocess.DEVNULL if stdin_null else None)


def tools_json(server):
    os.makedirs(CACHE_DIR, exist_ok=True)
    f = os.path.join(CACHE_DIR, f"{server}.json")
    if os.path.exists(f) and time.time() - os.path.getmtime(f) < CACHE_TTL:
        with open(f) as fh:
            return json.load(fh)
    r = run(["list", server, "--json"])
    try:
        d = json.loads(r.stdout)
    except json.JSONDecodeError:
        die(f"{server}: mcporter did not return tools:\n{(r.stderr or r.stdout).strip()[-600:]}\nIf it needs login: mcporter auth {server}")
    if d.get("tools"):
        with open(f, "w") as fh:
            json.dump(d, fh)
    return d


def tool_names_quiet(server):
    """Nombres de tools de un servidor sin morir ni imprimir si no responde
    (un servidor sin auth no debe ensuciar la resolucion de otro)."""
    f = os.path.join(CACHE_DIR, f"{server}.json")
    try:
        if os.path.exists(f) and time.time() - os.path.getmtime(f) < CACHE_TTL:
            with open(f) as fh:
                return [t["name"] for t in json.load(fh).get("tools") or []]
        r = run(["list", server, "--json"])
        d = json.loads(r.stdout)
        if d.get("tools"):
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(f, "w") as fh:
                json.dump(d, fh)
        return [t["name"] for t in d.get("tools") or []]
    except Exception:
        return []


def type_of(v):
    t = v.get("type")
    if isinstance(t, list):
        t = "|".join(x for x in t if x != "null")
    if t == "array":
        t = f"{(v.get('items') or {}).get('type', 'any')}[]"
    return t or ("enum" if "enum" in v else "any")


def clip(text, limit=MAX_CHARS, hint="Narrow the call (limit=, filters) or raise MCP_MAX_CHARS."):
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n  [...truncated: {len(text) - limit} chars more. {hint}]"


def cmd_list(_):
    srv = servers()
    if not srv:
        print("no MCP servers in the catalog")
        return
    for name, cfg in srv.items():
        _, own = policy_for(name)
        print(f"- {name}: {cfg.get('description', '')}")
        print(f"    policy: {'own' if own else 'default'}; tools: mcp.sh tools {name}   auth: mcporter auth {name}")


def cmd_tools(a):
    if not a:
        die(USAGE)
    server, filt = a[0], (a[1].lower() if len(a) > 1 else "")
    if server not in servers():
        die(f"no server named {server}. Catalog: {', '.join(servers()) or '(empty)'}")
    d = tools_json(server)
    tools = d.get("tools") or []
    if not tools:
        die(f"{server}: no tools returned (status: {d.get('status', '?')}). If it needs login: mcporter auth {server}")
    p, _ = policy_for(server)
    shown = hidden = 0
    for t in tools:
        n = t["name"]
        if matches(n, p.get("deny")):
            hidden += 1
            continue
        if filt and filt not in n.lower() and filt not in (t.get("description") or "").lower():
            continue
        sch = t.get("inputSchema") or {}
        props = sch.get("properties") or {}
        req = set(sch.get("required") or [])
        params = ", ".join(f"{k}{'' if k in req else '?'}: {type_of(v)}" for k, v in props.items())
        tag = " [write]" if matches(n, p.get("write")) else ""
        desc = (t.get("description") or "").strip().split("\n")[0]
        if len(desc) > 110:
            desc = desc[:107] + "..."
        print(f"{n}({params}){tag}\n    {desc}")
        shown += 1
    if shown == 0:
        print(f"no tool in {server} matches '{filt}'")
    foot = f"  {shown} tool(s)" + (f", {hidden} hidden by policy" if hidden else "")
    print(foot + f". Details: mcp.sh describe {server}.<tool>")


def split_sel(sel, what):
    """<server>.<tool>. Sin servidor se resuelve solo: un modelo escribio
    `mcp.sh call notion-create-pages` diez veces seguidas y solo recibia el
    texto de uso. Si el nombre de la tool identifica un unico servidor, se usa
    y se avisa; si es ambiguo o no existe, se listan los selectores exactos."""
    sel = sel or ""
    srv = servers()
    if "." in sel:
        s, t = sel.split(".", 1)
        if s in srv:
            return s, t
        # "notion-create-pages.x"? o un servidor mal escrito
        die(f"no server named {s}. Catalog: {', '.join(srv) or '(empty)'}. Use <server>.<tool>, e.g. {next(iter(srv), 'server')}.<tool>")
    if not sel:
        die(f"use: mcp.sh {what} <server>.<tool>")
    # 1) el nombre de la tool empieza por el nombre de un servidor (notion-search -> notion)
    by_prefix = [x for x in srv if sel.lower().startswith(x.lower())]
    # 2) busqueda en las listas de tools (cacheadas) de todos los servidores
    found = []
    for x in srv:
        if sel in tool_names_quiet(x):
            found.append(x)
    cands = found or by_prefix
    if len(cands) == 1:
        print(f"[mcp.sh] no server given: using {cands[0]}.{sel} — write it that way next time", file=sys.stderr)
        return cands[0], sel
    if len(cands) > 1:
        die(f"'{sel}' exists in several servers: " + ", ".join(f"{x}.{sel}" for x in cands) + ". Say which one.")
    die(f"'{sel}' is not <server>.<tool> and no server has a tool named that. Servers: {', '.join(srv) or '(empty)'}. "
        f"List a server's tools with: mcp.sh tools <server> <word>")


def cmd_describe(a):
    s, t = split_sel(a[0] if a else "", "describe")
    v = verdict(s, t, False)
    if v == "deny":
        die(f"{s}.{t} is not available (policy). See: mcp.sh tools {s}")
    tool = next((x for x in tools_json(s).get("tools", []) if x["name"] == t), None)
    if not tool:
        die(f"no tool named {t} in {s}. See: mcp.sh tools {s}")
    sch = tool.get("inputSchema") or {}
    props = sch.get("properties") or {}
    req = set(sch.get("required") or [])
    print(t + ("   [write: needs --write]" if v == "write-required" else ""))
    desc = (tool.get("description") or "").strip()
    print("  " + desc[:700].replace("\n", "\n  ") + (" ..." if len(desc) > 700 else ""))
    print("  parameters:")
    for k, val in props.items():
        extra = f" one of {val['enum']}" if "enum" in val else ""
        dd = (val.get("description") or "").strip().replace("\n", " ")
        if len(dd) > 160:
            dd = dd[:157] + "..."
        print(f"    {k}{'' if k in req else '?'}: {type_of(val)}{extra}  {dd}")
        for line in nested_shape(val):
            print("      " + line)
    if not props:
        print("    (none)")
    ex = example_call(s, t, props, req, v == "write-required")
    if ex:
        print("  example (shape only — replace the values):")
        print("    " + ex)


def nested_shape(val, depth=0):
    """Una capa de la forma interna de un object/array: es lo que un modelo no
    ve en la firma y rellena de memoria (p.ej. el formato REST de Notion en
    lugar del mapa plano que pide el MCP)."""
    if depth > 1:
        return []
    inner = val
    prefix = ""
    if val.get("type") == "array" and isinstance(val.get("items"), dict):
        inner = val["items"]
        prefix = "each item: "
    props = inner.get("properties") or {}
    out = []
    if props:
        req = set(inner.get("required") or [])
        fields = []
        for k, v in props.items():
            fields.append(f"{k}{'' if k in req else '?'}: {type_of(v)}")
        closed = inner.get("additionalProperties") is False
        out.append(prefix + "{ " + ", ".join(fields) + " }" + ("   (no other keys)" if closed else ""))
        for k, v in props.items():
            if v.get("type") == "object" and v.get("additionalProperties") and not v.get("properties"):
                out.append(f"  {k}: flat map name -> {type_of_any(v['additionalProperties'])}")
            dd = (v.get("description") or "").strip().replace("\n", " ")
            if dd:
                out.append(f"  {k}: {dd[:140]}{'...' if len(dd) > 140 else ''}")
    elif inner.get("type") == "object" and isinstance(inner.get("additionalProperties"), dict):
        out.append(prefix + "flat map name -> " + type_of_any(inner["additionalProperties"]))
    return out


def type_of_any(v):
    if "anyOf" in v:
        return "|".join(type_of(x) for x in v["anyOf"] if x.get("type") != "null")
    return type_of(v)


def placeholder(v, name=""):
    t = v.get("type")
    if isinstance(t, list):
        t = next((x for x in t if x != "null"), "string")
    if "enum" in v:
        return v["enum"][0]
    if t == "string":
        return f"<{name or 'text'}>"
    if t in ("integer", "number"):
        return 1
    if t == "boolean":
        return True
    if t == "array":
        items = v.get("items") or {}
        return [placeholder(items, name.rstrip("s"))]
    if t == "object":
        props = v.get("properties") or {}
        if props:
            req = set(v.get("required") or [])
            keys = [k for k in props if k in req] or list(props)[:2]
            return {k: placeholder(props[k], k) for k in keys}
        return {"<name>": "<value>"}
    return "<value>"


def example_call(server, tool, props, req, write):
    if not props:
        return ""
    parts = []
    for k in [k for k in props if k in req] or list(props)[:2]:
        v = props[k]
        ph = placeholder(v, k)
        if isinstance(ph, (dict, list, bool, int, float)):
            parts.append(f"{k}:='{json.dumps(ph, ensure_ascii=False)}'")
        else:
            parts.append(f'{k}="{ph}"')
    return f"mcp.sh call {'--write ' if write else ''}{server}.{tool} " + " ".join(parts)


JSONISH = ("object", "array", "boolean", "integer", "number")


def coerce_args(server, tool, rest):
    """`k=v` manda v como TEXTO; `k:=v` como JSON. Un modelo pequeno confunde
    las dos y el servidor contesta "expected object, received string" — eso se
    leyo como "el MCP esta roto" en un PC. Aqui se mira el esquema de la tool:
    si el parametro es object/array/boolean/number y el valor parsea como JSON,
    se manda tipado. Lo que ya viene con := , @fichero o --args no se toca."""
    try:
        tools = tools_json(server).get("tools") or []
        schema = next((x for x in tools if x["name"] == tool), {}).get("inputSchema") or {}
        props = schema.get("properties") or {}
    except SystemExit:
        return rest, []
    fixed, notes = [], []
    for arg in rest:
        if "=" in arg and not arg.startswith("-") and ":=" not in arg:
            k, val = arg.split("=", 1)
            typ = (props.get(k) or {}).get("type")
            if isinstance(typ, list):
                typ = next((x for x in typ if x != "null"), None)
            if typ in JSONISH and not val.startswith("@"):
                try:
                    json.loads(val)
                    fixed.append(f"{k}:={val}")
                    notes.append(k)
                    continue
                except json.JSONDecodeError:
                    pass
        fixed.append(arg)
    return fixed, notes


def validate_args(server, tool, rest):
    """Comprueba en local lo que el servidor rechazaria: claves de primer nivel
    que no existen y, un nivel mas adentro, claves no admitidas en objetos con
    additionalProperties=false (el caso real: `title` suelto en pages[0] cuando
    el esquema pide properties:{title:...}). Mensajes con la correccion."""
    try:
        tools = tools_json(server).get("tools") or []
        schema = next((x for x in tools if x["name"] == tool), None)
    except SystemExit:
        return []
    if not schema:
        return [f"no tool named '{tool}' in {server}: mcp.sh tools {server} <word>"]
    props = (schema.get("inputSchema") or {}).get("properties") or {}
    out = []
    for arg in rest:
        if arg.startswith("-") or "=" not in arg:
            continue
        k, val = arg.split("=", 1)
        typed = k.endswith(":")
        k = k.rstrip(":")
        if props and k not in props:
            out.append(f"'{k}' is not a parameter. Parameters: {', '.join(props)}")
            continue
        if not typed or val.startswith("@"):
            continue
        try:
            data = json.loads(val)
        except json.JSONDecodeError:
            continue
        spec = props.get(k) or {}
        item_spec = spec.get("items") if spec.get("type") == "array" else spec
        items = data if isinstance(data, list) else [data]
        allowed = (item_spec or {}).get("properties") or {}
        if not allowed or (item_spec or {}).get("additionalProperties") is not False:
            continue
        for i, item in enumerate(items):
            if not isinstance(item, dict):
                continue
            bad = [x for x in item if x not in allowed]
            if bad:
                where = f"{k}[{i}]" if isinstance(data, list) else k
                fix = ""
                if "title" in bad and "properties" in allowed:
                    fix = ' — for a title use "properties": {"title": "..."}'
                out.append(f"{where}: unknown key(s) {', '.join(repr(b) for b in bad)}. Allowed: {', '.join(allowed)}{fix}")
    return out


def error_hints(server, tool, out):
    low = out.lower()
    hints = []
    if "unauthori" in low or "401" in low or "oauth" in low or "needs auth" in low:
        hints.append(f"the user must run once:  mcporter auth {server}")
    if "received string" in low or "expected object" in low or "expected array" in low or "unrecognized key" in low:
        hints.append("the argument SHAPE is wrong (a key at the wrong level, or JSON sent as text). Run "
                     f"mcp.sh describe {server}.{tool} and copy its nested shape and example; do not use the shape of the "
                     "vendor's REST API from memory (e.g. Notion's title:[{text:{content}}] is NOT what this MCP takes). "
                     "This is an argument error, not a server bug")
    if "not found in the data source" in low or "property" in low and "not found" in low:
        hints.append("the database has its own property names: the error above lists the valid ones; the title property is not always 'Name'. "
                     "Fetch the collection:// first and use those exact keys")
    if "validation_error" in low and not hints:
        hints.append("the server rejected the arguments: read the message above literally, it names the field. Fix the call; do not conclude the tool is broken")
    return hints


def cmd_call(a):
    write = False
    if a and a[0] == "--write":
        write = True
        a = a[1:]
    s, t = split_sel(a[0] if a else "", "call [--write]")
    rest = a[1:]
    v = verdict(s, t, write)
    if v == "deny":
        die(f"BLOCKED by policy: {s}.{t} is not available from here. See what is: mcp.sh tools {s}", 2)
    if v == "write-required":
        die(f"{s}.{t} changes things. Re-run as:  mcp.sh call --write {s}.{t} {' '.join(shlex.quote(x) for x in rest)}   (the user will be asked to confirm)", 3)
    rest, coerced = coerce_args(s, t, rest)
    problems = validate_args(s, t, rest)
    if problems:
        die(f"{s}.{t}: not sent — the arguments do not match the tool's schema:\n  - " + "\n  - ".join(problems) +
            f"\nSee: mcp.sh describe {s}.{t}   (nested shape + example). This is an argument error, not a server bug.", 4)
    r = run(["call", f"{s}.{t}", *rest, "--output", "text"])
    if r.returncode != 0:
        out = (r.stderr or "") + (r.stdout or "")
        msg = f"{s}.{t} failed (exit {r.returncode}):\n" + "\n".join(out.strip().splitlines()[-8:])
        for h in error_hints(s, t, out):
            msg += f"\n-> {h}"
        die(msg, r.returncode)
    if coerced:
        print(f"[mcp.sh] sent as JSON (schema says object/array/number): {', '.join(coerced)} — next time write k:=...", file=sys.stderr)
    sys.stdout.write(clip(r.stdout))
    if not r.stdout.endswith("\n"):
        print()


def cmd_status(a):
    r = run(["list", *a[:1], "--status"])
    lines = [l for l in (r.stdout + r.stderr).splitlines() if l.strip()]
    print("\n".join(lines[-20:]))
    sys.exit(r.returncode)


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(USAGE)
        return
    cmd, a = argv[0], argv[1:]
    fn = {"list": cmd_list, "tools": cmd_tools, "describe": cmd_describe, "call": cmd_call, "status": cmd_status}.get(cmd)
    if not fn:
        die(USAGE)
    fn(a)


if __name__ == "__main__":
    main(sys.argv[1:])
