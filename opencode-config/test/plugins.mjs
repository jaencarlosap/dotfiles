// Tests de los plugins que pueden BLOQUEAR al agente. Sin dependencias:
//   node --experimental-strip-types test/plugins.mjs       (o: make test-plugins)
//
// Se ejecutan contra directorios temporales propios, asi que no dependen del
// cwd (una version anterior si, y dio dos falsos fallos al correrla desde otro
// sitio: el test leia el README.md del repo real).
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from "fs"
import { tmpdir } from "os"
import { join, dirname } from "path"
import { fileURLToPath } from "url"
import { execFileSync } from "child_process"

const HERE = dirname(fileURLToPath(import.meta.url))
const tmp = (name) => mkdtempSync(join(tmpdir(), `opencode-${name}-`))
let pass = 0, fail = 0
const t = async (n, f) => {
  try { await f(); console.log(`  ✅ ${n}`); pass++ }
  catch (e) { console.log(`  ❌ ${n}\n       ${e.message}`); fail++ }
}

// ── anti-slop-guard ──────────────────────────────────────────────────────
{
  const dir = tmp("guard")
  const hooks = await (await import(join(HERE, "..", "plugin", "anti-slop-guard.ts"))).default({ directory: dir })
  const before = hooks["tool.execute.before"], after = hooks["tool.execute.after"]
  const SID = "s1"
  const blocks = async (args, tool = "write", callID = "c") => {
    try { await before({ tool, sessionID: SID, callID }, { args }); return null } catch (e) { return e.message }
  }
  writeFileSync(join(dir, "existing.txt"), "original\n")
  writeFileSync(join(dir, ".agent_progress.md"), "x\n")

  console.log("anti-slop-guard:")
  await t("bloquea write sobre fichero existente NO leido", async () => {
    const m = await blocks({ filePath: join(dir, "existing.txt"), content: "x" })
    if (!m?.includes("already exists")) throw new Error("no bloqueo: " + m)
    if (m.includes(dir)) throw new Error("mensaje con ruta ABSOLUTA (el modelo la copia mal)")
  })
  await t("permite write si ya lo leyo en esta sesion", async () => {
    await after({ tool: "read", sessionID: SID, args: { filePath: join(dir, "existing.txt") } }, { output: "" })
    const m = await blocks({ filePath: join(dir, "existing.txt"), content: "x" })
    if (m) throw new Error("bloqueo indebido: " + m)
  })
  await t("solo hay UN fichero de progreso: bloquea las variantes tecleadas mal", async () => {
    // REAL: `.agents/progress.md` (con `s`) acabo COMMITEADO en
    // stremio-iptv-addon (488524b). Un typo crea un directorio nuevo y el repo
    // acaba con tres sitios donde mirar el estado.
    for (const p of [".agents/progress.md", "agent/progress.md", ".opencode/progress.md"]) {
      const m = await blocks({ filePath: join(dir, p), content: "# GOAL\n" })
      if (!m?.includes(".agent/progress.md")) throw new Error("no redirigio a la ruta buena: " + p + " -> " + m)
      if (!m.includes('singular')) throw new Error("no explico el typo: " + m)
    }
    const ok = await blocks({ filePath: join(dir, ".agent", "progress.md"), content: "# GOAL\n" })
    if (ok) throw new Error("bloqueo la ruta canonica: " + ok)
  })
  await t("bloquea ficheros de relleno (SUMMARY/ANALYSIS/RESUME)", async () => {
    for (const f of ["RESUME.md", "IMPLEMENTATION_SUMMARY.md", "ANALYSIS.md"])
      if (!(await blocks({ filePath: join(dir, f), content: "x" }))) throw new Error("no bloqueo " + f)
  })
  await t("bloquea duplicados SOLO si existe el original", async () => {
    for (const o of ["foo.py", "api.ts", "main.go"]) writeFileSync(join(dir, o), "x")
    for (const f of ["foo_v2.py", "api_new.ts", "main.go.bak"]) {
      const m = await blocks({ filePath: join(dir, f), content: "x" })
      if (!m?.includes("already exists")) throw new Error("no bloqueo " + f + ": " + m)
    }
  })
  await t("NO bloquea nombres legitimos acabados en _new/_old", async () => {
    for (const f of ["brand_new.go", "is_new.ts", "mark_old.py"]) {
      const m = await blocks({ filePath: join(dir, f), content: "x" })
      if (m) throw new Error("falso positivo en " + f + ": " + m)
    }
  })
  await t("NO bloquea README.md ni ficheros nuevos", async () => {
    for (const f of ["README.md", "server.go"])
      if (await blocks({ filePath: join(dir, f), content: "x" })) throw new Error("bloqueo indebido " + f)
  })
  await t("NO bloquea el fichero de progreso (ambas convenciones)", async () => {
    // REGRESION: el guard solo conocia `.agent_progress.md`, asi que en un
    // RESUME bloqueaba `.agent/progress.md` — el agente lo lee con `cat` (bash,
    // que no marca como leido) y al reescribirlo se lo comia el bloqueo.
    const { mkdirSync } = await import("fs")
    mkdirSync(join(dir, ".agent"), { recursive: true })
    writeFileSync(join(dir, ".agent", "progress.md"), "# GOAL\nx\n")
    for (const f of [".agent_progress.md", ".agent/progress.md"]) {
      const m = await blocks({ filePath: join(dir, f), content: "x" })
      if (m) throw new Error("bloqueado " + f + ": " + m)
    }
  })
  await t("avisa si un edit borra una declaracion", async () => {
    const out = { output: "Edit applied." }
    await after({ tool: "edit", sessionID: SID, args: { filePath: join(dir, "x.go"),
      oldString: "func Set(k string) {}\nfunc Len() int { return 0 }", newString: "func Len() int { return 0 }" } }, out)
    if (!out.output.includes("func Set")) throw new Error("sin aviso: " + out.output)
  })
  await t("avisa si un WRITE completo borra declaraciones", async () => {
    const f = join(dir, "keep.go")
    writeFileSync(f, "package main\n\nfunc Existing() int { return 1 }\n")
    await after({ tool: "read", sessionID: SID, args: { filePath: f } }, { output: "" })
    await before({ tool: "write", sessionID: SID, callID: "w1" }, { args: { filePath: f, content: "package main\n" } })
    const out = { output: "Wrote file successfully." }
    await after({ tool: "write", sessionID: SID, callID: "w1", args: { filePath: f, content: "package main\n" } }, out)
    if (!out.output.includes("func Existing")) throw new Error("sin aviso: " + out.output)
  })
  await t("NO avisa al crear un fichero nuevo", async () => {
    const out = { output: "ok" }
    await before({ tool: "write", sessionID: SID, callID: "w2" }, { args: { filePath: join(dir, "nuevo.go"), content: "func A() {}" } })
    await after({ tool: "write", sessionID: SID, callID: "w2", args: { filePath: join(dir, "nuevo.go"), content: "func A() {}" } }, out)
    if (out.output.includes("GUARD")) throw new Error("aviso falso")
  })
  await t("bloquea apagar un test (t.Skip, it.skip, pytest.mark.skip)", async () => {
    // Ni las reglas ni el prompt de `auto` lo prohibian: verificado antes de
    // escribir el guard. Un test saltado da verde y el defecto sigue vivo.
    const casos = [
      { filePath: join(dir, "api_test.go"), oldString: "func TestA(t *testing.T){", newString: 'func TestA(t *testing.T){ t.Skip("flaky")' },
      { filePath: join(dir, "tests/test_api.py"), oldString: "def test_a():", newString: "@pytest.mark.skip\ndef test_a():" },
      { filePath: join(dir, "src/api.spec.ts"), oldString: 'it("works"', newString: 'it.skip("works"' },
      { filePath: join(dir, "api.test.js"), oldString: 'describe("x"', newString: 'describe.only("x"' },
    ]
    for (const args of casos) {
      const m = await blocks(args, "edit")
      if (!m?.includes("BLOCKED")) throw new Error("no bloqueo: " + args.filePath + " -> " + m)
    }
    // El mensaje tiene que dar salida: en un run real el usuario PIDIO saltarlo
    // y el modelo se limito a negarse. Ahora se le dice que relaye el escape.
    const m = await blocks(casos[0], "edit")
    if (!m.includes("OPENCODE_GUARD_OFF=1")) throw new Error("el mensaje no ofrece la salida al usuario")
    if (!m.includes("failing-test")) throw new Error("el mensaje no apunta a la skill")
  })
  await t("NO bloquea QUITAR un skip ni un edit normal de test", async () => {
    const casos = [
      { filePath: join(dir, "api_test.go"), oldString: 'func TestA(t *testing.T){ t.Skip("x")', newString: "func TestA(t *testing.T){" },
      { filePath: join(dir, "api_test.go"), oldString: "func TestA(", newString: "func TestA(t *testing.T){ assertEqual(2, sum(1,1))" },
      { filePath: join(dir, "main.go"), oldString: "x", newString: "// t.Skip(1) en un fichero que NO es test" },
    ]
    for (const args of casos) {
      const m = await blocks(args, "edit")
      if (m) throw new Error("falso positivo: " + args.filePath + " -> " + m)
    }
  })
  await t("bloquea una ruta absoluta fantasma (dedazo al reescribirla)", async () => {
    // Los DOS modelos lo hicieron: qwen se comio las barras
    // (`/Users/jaencarlos-Documents-personal-dotfiles/...`) y gpt-oss cambio una
    // letra del UUID (`...1f12-4e03...` por `...1f12-4d03...`) y escribio un
    // proyecto entero en un arbol fantasma dando la tarea por terminada.
    const m = await blocks({ filePath: "/private/tmp/no-existe-este-arbol-xyz/sub/index.js", content: "x" }, "write")
    if (!m?.includes("does not exist")) throw new Error("no bloqueo la ruta fantasma: " + m)
    if (!m.includes("RELATIVE")) throw new Error("no propone la ruta relativa: " + m)
  })
  await t("NO bloquea /tmp ni rutas absolutas dentro del proyecto", async () => {
    const { mkdirSync } = await import("fs")
    mkdirSync(join(dir, "src"), { recursive: true })
    for (const f of ["/tmp/probe.js", join(dir, "src", "nuevo.js"), "relativo.js"]) {
      const m = await blocks({ filePath: f, content: "x" }, "write")
      if (m) throw new Error("falso positivo en " + f + " -> " + m)
    }
  })
  await t("adelanta un edit que NO iba a casar, con la linea real", async () => {
    // Fallo cronico nº1 en la base de sesiones: 35 "Could not find oldString"
    // en 15 sesiones distintas. El error de opencode no dice en QUE difiere.
    writeFileSync(join(dir, "sum.go"), "package main\n\nfunc Sum(a, b int) int {\n\treturn a - b\n}\n")
    const m = await blocks({ filePath: join(dir, "sum.go"), oldString: "    return a - b", newString: "    return a + b" }, "edit")
    if (!m?.includes("line 4")) throw new Error("no señalo la linea real: " + m)
    if (!m?.includes("whitespace or indentation differ")) throw new Error("no explico la causa: " + m)
    const ok = await blocks({ filePath: join(dir, "sum.go"), oldString: "\treturn a - b", newString: "\treturn a + b" }, "edit")
    if (ok) throw new Error("bloqueo un edit que SI casaba: " + ok)
  })
  await t("bloquea un edit que no cambia nada (oldString == newString)", async () => {
    const m = await blocks({ filePath: join(dir, "sum.go"), oldString: "return a - b", newString: "return a - b" }, "edit")
    if (!m?.includes("identical")) throw new Error("no bloqueo: " + m)
  })
  await t("un `read` de ruta inventada dice DONDE esta el fichero", async () => {
    // Fallo cronico nº2: 31 "File not found" en 18 sesiones distintas.
    const { mkdirSync } = await import("fs")
    mkdirSync(join(dir, "internal", "api"), { recursive: true })
    writeFileSync(join(dir, "internal", "api", "handler.go"), "package api\n")
    const m = await blocks({ filePath: join(dir, "src", "handler.go") }, "read")
    if (!m?.includes("internal/api/handler.go")) throw new Error("no ofrecio la ruta real: " + m)
    const m2 = await blocks({ filePath: join(dir, "src", "inexistente.go") }, "read")
    if (!m2?.includes("glob")) throw new Error("no dijo como buscarlo: " + m2)
    const ok = await blocks({ filePath: join(dir, "internal", "api", "handler.go") }, "read")
    if (ok) throw new Error("bloqueo un read de fichero que existe: " + ok)
  })
  await t("un bloqueo repetido ESCALA y acaba en STOP (el bucle de 92 intentos)", async () => {
    // REGRESION REAL (ses_f779a0b74, 2026-09-09): el modelo pidio
    // `scrapper-puppeteer/...` (una `p` de mas), el guard le dio la ruta buena,
    // y lo reintento 92 veces IDENTICAS en 7 minutos hasta que el usuario mato
    // el proceso. El loop-breaker no lo vio: este plugin carga antes y LANZA en
    // `tool.execute.before`, asi que la llamada nunca llega a su hook.
    const { mkdirSync } = await import("fs")
    mkdirSync(join(dir, "scraper-puppeteer"), { recursive: true })
    writeFileSync(join(dir, "scraper-puppeteer", "embed-resolver.js"), "module.exports = {}\n")
    const malo = join(dir, "scrapper-puppeteer", "embed-resolver.js")

    const m1 = await blocks({ filePath: malo }, "read")
    if (!m1?.includes("scraper-puppeteer/embed-resolver.js")) throw new Error("no ofrecio la ruta buena: " + m1)
    if (!m1.includes('you wrote "scrapper-puppeteer"')) throw new Error("no señalo el segmento equivocado: " + m1)

    await blocks({ filePath: malo }, "read")            // 2º
    const m3 = await blocks({ filePath: malo }, "read") // 3º -> escala
    if (!m3?.includes("3x")) throw new Error("no escalo al tercer intento: " + m3)
    if (!m3.includes("character by character")) throw new Error("no dio la instruccion corta: " + m3)

    await blocks({ filePath: malo }, "read")
    const m5 = await blocks({ filePath: malo }, "read") // 5º -> alto
    if (!m5?.includes("STOP")) throw new Error("no paro al quinto: " + m5)
    if (!m5.includes("answer the user now")) throw new Error("no le dijo que conteste: " + m5)

    // La ruta BUENA sigue funcionando: la escalada es por llamada, no global.
    const ok = await blocks({ filePath: join(dir, "scraper-puppeteer", "embed-resolver.js") }, "read")
    if (ok) throw new Error("bloqueo la ruta correcta: " + ok)
  })
  await t("bloquea leer .env por bash (el deny de `read` no cubre bash)", async () => {
    for (const cmd of ["cat .env", "head -5 .env", "grep KEY .env", "xxd .env | head", "cp .env /tmp/x"]) {
      const m = await blocks({ command: cmd }, "bash")
      if (!m?.includes("BLOCKED")) throw new Error("no bloqueo: " + cmd)
    }
  })
  await t("NO bloquea .env.example ni bash normal", async () => {
    for (const cmd of ["cat .env.example", "go test ./...", "git status", "npm run build"]) {
      const m = await blocks({ command: cmd }, "bash")
      if (m) throw new Error("bloqueo indebido: " + cmd + " -> " + m)
    }
  })
  await t("bloquea un comando que NO existe (el bucle de 229 pasos)", async () => {
    // REGRESION REAL: el agente corrio `ripgrep --help 2>&1 | grep -i max` en
    // bucle. `ripgrep` se llama `rg`; el "command not found" iba por stderr y
    // su propio `2>&1 | grep` lo convertia en salida VACIA -> reintento igual.
    for (const cmd of ['ripgrep --help 2>&1 | grep -i "max"', "notacommand -x", "cat foo.txt | frobnicate"]) {
      const m = await blocks({ command: cmd }, "bash")
      if (!m?.includes("is not a command")) throw new Error("no bloqueo: " + cmd + " -> " + m)
    }
  })
  await t("el mensaje dice QUE hacer, no solo que pare", async () => {
    const m = await blocks({ command: "ripgrep foo" }, "bash")
    for (const hint of ["web.sh", "docs.sh", "2>/dev/null"])
      if (!m?.includes(hint)) throw new Error("el error no menciona " + hint + ": " + m)
  })
  // ── Lecturas que se comen el contexto ──────────────────────────────────
  // REGRESION REAL (stremio-iptv-addon, sesion ses_f77dc102, 2026-09-09):
  // 40 llamadas, 121.519 chars de salida, DOS compactaciones en 8 minutos.
  // Estos cuatro casos son los que la causaron.
  await t("bloquea `cat` de un fichero grande, con el coste en tokens", async () => {
    writeFileSync(join(dir, "grande.js"), "// linea\n".repeat(2000))   // ~18 KB
    writeFileSync(join(dir, "chico.js"), "// linea\n".repeat(20))
    const m = await blocks({ command: "cat grande.js" }, "bash")
    if (!m?.includes("BLOCKED")) throw new Error("no bloqueo el cat grande: " + m)
    if (!m.includes("tokens")) throw new Error("no dijo el coste: " + m)
    if (!m.includes("grep -n")) throw new Error("no dijo la alternativa: " + m)
    for (const cmd of ["cat chico.js", "cat grande.js | head -50", "cat grande.js | grep foo"]) {
      const ok = await blocks({ command: cmd }, "bash")
      if (ok) throw new Error("bloqueo indebido: " + cmd + " -> " + ok)
    }
  })
  await t("bloquea `read` de un fichero grande sin offset/limit", async () => {
    const m = await blocks({ filePath: join(dir, "grande.js") }, "read")
    if (!m?.includes("BLOCKED")) throw new Error("no bloqueo: " + m)
    if (!m.includes("offset/limit")) throw new Error("no ofrecio la salida: " + m)
    const ok = await blocks({ filePath: join(dir, "grande.js"), offset: 100, limit: 40 }, "read")
    if (ok) throw new Error("bloqueo un read acotado: " + ok)
    const ok2 = await blocks({ filePath: join(dir, "chico.js") }, "read")
    if (ok2) throw new Error("bloqueo un fichero pequeño: " + ok2)
    // REGRESION T2c: el coste se mide con la numeracion de lineas que añade
    // `read`, no con el tamaño en disco. 1.600 lineas cortas = 11.2 KB en
    // disco (pasaria) pero ~22 KB en el contexto (no pasa).
    writeFileSync(join(dir, "frontera.js"), "x\n".repeat(5600))   // 11.2 KB, 5.600 lineas
    const m3 = await blocks({ filePath: join(dir, "frontera.js") }, "read")
    if (!m3?.includes("BLOCKED")) throw new Error("no conto la numeracion de lineas: " + m3)
  })
  await t("bloquea `docker logs` sin acotar, permite el acotado", async () => {
    const m = await blocks({ command: "docker logs mi-contenedor 2>&1" }, "bash")
    if (!m?.includes("BLOCKED")) throw new Error("no bloqueo: " + m)
    if (!m.includes("AGENTS.md")) throw new Error("no mando a mirar el AGENTS.md: " + m)
    for (const cmd of [
      "docker logs --tail 100 mi-contenedor",
      "docker logs --since 30m mi-contenedor",
      "docker logs mi-contenedor | grep -i error",
      "docker compose logs --tail 50",
    ]) {
      const ok = await blocks({ command: cmd }, "bash")
      if (ok) throw new Error("bloqueo indebido: " + cmd + " -> " + ok)
    }
  })
  await t("bloquea RELEER el mismo fichero si no ha cambiado, no si lo editaste", async () => {
    // En la sesion real `sololatino.js` se leyo dos veces (cat + read): 17.315
    // chars por el mismo contenido.
    const f = join(dir, "releido.js")
    writeFileSync(f, "// linea\n".repeat(1000))   // ~9 KB, pasa de 4.000
    await after({ tool: "read", sessionID: SID, args: { filePath: f } }, { output: "" })
    const m = await blocks({ filePath: f }, "read")
    if (!m?.includes("already read")) throw new Error("no bloqueo la relectura identica: " + m)
    // REGRESION T2 (2026-09-09): la v1 del guard bloqueaba CUALQUIER segunda
    // lectura, tambien la de otro tramo — que es lo que el guard de fichero
    // grande le pide hacer. 13 de 18 lecturas bloqueadas y el modelo en bucle.
    for (const r of [{ offset: 1, limit: 50 }, { offset: 51, limit: 50 }, { offset: 101, limit: 120 }]) {
      const ok = await blocks({ filePath: f, ...r }, "read")
      if (ok) throw new Error(`bloqueo un tramo NUEVO (offset ${r.offset}): ` + ok)
    }
    // ...pero el MISMO tramo dos veces, no.
    await after({ tool: "read", sessionID: SID, args: { filePath: f, offset: 51, limit: 50 } }, { output: "" })
    const m2 = await blocks({ filePath: f, offset: 51, limit: 50 }, "read")
    if (!m2?.includes("already read")) throw new Error("no bloqueo el mismo tramo repetido: " + m2)
    await new Promise((r) => setTimeout(r, 12))
    writeFileSync(f, "// otra cosa\n".repeat(1000))   // cambia el mtime
    const ok = await blocks({ filePath: f, offset: 1, limit: 10 }, "read")
    if (ok) throw new Error("bloqueo una relectura legitima tras editar: " + ok)
  })
  await t("NO bloquea por un `|` dentro de comillas (falso positivo real)", async () => {
    // REGRESION: el agente verificaba su propio servidor con
    //   curl ... && curl -v ... | grep -E "HTTP|status|ok"
    // El `|` del regex partia el comando, `status` quedaba de cabeza y el guard
    // lo bloqueaba. Un falso positivo aqui para al agente en seco.
    for (const cmd of [
      'curl -s http://localhost:8080/health && curl -v http://localhost:8080/health 2>&1 | grep -E "HTTP|status|ok"',
      'grep -E "foo|bar" file.txt',
      "echo \"a|b\" | tr \"|\" \",\"",
      "ls $(dirname $(command -v go))",
    ]) {
      const m = await blocks({ command: cmd }, "bash")
      if (m) throw new Error("falso positivo: " + cmd + " -> " + m)
    }
  })
  await t("NO bloquea el CUERPO de un heredoc (falso positivo real)", async () => {
    // REGRESION: el modelo escribio un fichero JS con `cat > f <<'EOF' ... EOF`.
    // Cada linea del cuerpo parecia un comando y `const now = new Date();`
    // bloqueaba la escritura entera.
    const heredoc = ["cat > /tmp/x.js <<'EOF'", "#!/usr/bin/env node", "const now = new Date();", "console.log(now);", "EOF"].join("\n")
    const sinComillas = ["cat > f.py <<PY", "import sys", "print('hola')", "PY"].join("\n")
    for (const cmd of [heredoc, sinComillas]) {
      const m = await blocks({ command: cmd }, "bash")
      if (m) throw new Error("falso positivo en heredoc: " + m)
    }
    // Pero un comando inexistente DESPUES del heredoc sigue cayendo.
    const m = await blocks({ command: ["cat > a.txt <<EOF", "hola", "EOF", "notacommand -x"].join("\n") }, "bash")
    if (!m?.includes("is not a command")) throw new Error("dejo pasar un comando malo tras el heredoc")
  })
  await t("NO bloquea comandos reales, alias del bin, ni sintaxis de shell", async () => {
    // `web.sh`/`docs.sh` viven en el bin de opencode, que NO esta en el PATH de
    // este proceso: si el guard no lo añade a mano, bloquea sus propias
    // herramientas. `webfetch` existe como alias desde el bucle de arriba.
    for (const cmd of [
      "rg --help | head -5", "web.sh search \"algo\"", "docs.sh npm zod", "webfetch https://x.dev",
      "for f in *.go; do echo $f; done", "FOO=1 make build", "git status && npm test",
      "sudo ls /", "./scripts/build.sh", "$EDITOR file.txt",
    ]) {
      const m = await blocks({ command: cmd }, "bash")
      if (m) throw new Error("falso positivo: " + cmd + " -> " + m)
    }
  })
  await t("bloquea la fontaneria MCP y redirige a las tools reales", async () => {
    for (const tool of ["list_mcp_resources", "list_mcp_resource_templates", "read_mcp_resource"]) {
      const m = await blocks({}, tool)
      if (!m?.includes("BLOCKED")) throw new Error("no bloqueo " + tool)
      if (!m.includes("jiraAdmin_")) throw new Error("no redirige a la tool real: " + tool)
    }
  })
  await t("NO bloquea las tools del servidor MCP (esas si sirven)", async () => {
    for (const tool of ["jiraAdmin_confluence-search", "duckduckgo_search", "jiraAdmin_jira-ticket-details"]) {
      const m = await blocks({ query: "x" }, tool)
      if (m) throw new Error("bloqueo indebido " + tool + ": " + m)
    }
  })
  await t("OPENCODE_GUARD_OFF=1 lo desactiva", async () => {
    process.env.OPENCODE_GUARD_OFF = "1"
    const m = await blocks({ filePath: join(dir, "RESUME.md"), content: "x" })
    delete process.env.OPENCODE_GUARD_OFF
    if (m) throw new Error("sigue bloqueando")
  })
  rmSync(dir, { recursive: true, force: true })
}

// ── ground-truth ─────────────────────────────────────────────────────────
{
  const dir = tmp("ground")
  execFileSync("git", ["init", "-q", "."], { cwd: dir })
  execFileSync("git", ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"], { cwd: dir })
  const hooks = await (await import(join(HERE, "..", "plugin", "ground-truth.ts"))).default({ directory: dir })
  const tf = hooks["experimental.chat.messages.transform"]
  // Por defecto simula un turno POSTERIOR (ya hablo el asistente): la puerta de
  // contexto solo se inyecta en el primero, asi que los tests del repo-state
  // tienen que vivir fuera de ella o se mezclarian los dos comportamientos.
  const run = async ({ first = false } = {}) => {
    const msgs = first
      ? [{ role: "user", parts: [{ type: "text", text: "do the thing" }] }]
      : [
          { role: "user", parts: [{ type: "text", text: "antes" }] },
          { role: "assistant", parts: [{ type: "text", text: "ok" }] },
          { role: "user", parts: [{ type: "text", text: "do the thing" }] },
        ]
    const o = { messages: msgs }
    await tf({}, o)
    return o.messages[o.messages.length - 1].parts[0].text
  }
  console.log("\nground-truth:")
  await t("repo limpio y sin progreso -> no inyecta", async () => {
    if ((await run()) !== "do the thing") throw new Error("inyecto sin motivo")
  })
  await t("primer turno -> inyecta la puerta de contexto", async () => {
    const txt = await run({ first: true })
    if (!txt.includes("<context-gate")) throw new Error("no inyecto la puerta: " + txt)
    for (const hint of ["KNOWN or UNKNOWN", "web.sh search", "enough-context", "Six lookups"])
      if (!txt.includes(hint)) throw new Error("la puerta no menciona '" + hint + "'")
  })
  await t("turnos posteriores -> NO repite la puerta", async () => {
    // Repetirla cada vuelta seria pagar ~120 tok/turno por un recordatorio que
    // solo sirve al empezar.
    const txt = await run()
    if (txt.includes("<context-gate")) throw new Error("la repitio en un turno posterior")
  })
  await t("OPENCODE_GATE_OFF=1 apaga solo la puerta", async () => {
    process.env.OPENCODE_GATE_OFF = "1"
    const txt = await run({ first: true })
    delete process.env.OPENCODE_GATE_OFF
    if (txt.includes("<context-gate")) throw new Error("sigue inyectando la puerta")
  })
  await t("repo sucio -> inyecta git status", async () => {
    writeFileSync(join(dir, "nuevo.txt"), "x")
    const txt = await run()
    if (!txt.includes("<repo-state") || !txt.includes("nuevo.txt")) throw new Error("no inyecto")
  })
  await t("encuentra VERIFIED FACTS en .agent/progress.md (ruta actual)", async () => {
    // REGRESION: solo miraba `.agent_progress.md`, asi que con la convencion
    // actual los facts NO se inyectaban nunca.
    const { mkdirSync } = await import("fs")
    mkdirSync(join(dir, ".agent"), { recursive: true })
    writeFileSync(join(dir, ".agent", "progress.md"), "# GOAL\nx\n\n# VERIFIED FACTS\n- dato en la ruta nueva\n")
    const txt = await run()
    if (!txt.includes("dato en la ruta nueva")) throw new Error("no encontro los facts en .agent/progress.md")
    rmSync(join(dir, ".agent"), { recursive: true, force: true })
  })
  await t("inyecta solo la seccion VERIFIED FACTS", async () => {
    writeFileSync(join(dir, ".agent_progress.md"), "# GOAL\nsecreto\n\n# VERIFIED FACTS\n- gin v1.12.0 — source: docs.sh go\n\n# NEXT STEP\ny\n")
    const txt = await run()
    if (!txt.includes("gin v1.12.0")) throw new Error("sin facts")
    if (txt.includes("secreto")) throw new Error("inyecto el fichero entero")
  })
  await t("respeta el limite de tamano", async () => {
    writeFileSync(join(dir, ".agent_progress.md"), "# VERIFIED FACTS\n" + Array.from({ length: 300 }, (_, i) => `- fact ${i} bla bla bla bla`).join("\n"))
    const inj = (await run()).slice("do the thing".length)
    if (inj.length > 1400) throw new Error(inj.length + " chars, demasiado")
  })
  await t("OPENCODE_GROUND_OFF=1 lo desactiva", async () => {
    process.env.OPENCODE_GROUND_OFF = "1"
    const txt = await run(); delete process.env.OPENCODE_GROUND_OFF
    if (txt !== "do the thing") throw new Error("sigue inyectando")
  })
  rmSync(dir, { recursive: true, force: true })
}

// ── slim-tools ───────────────────────────────────────────────────────────
{
  const hooks = await (await import(join(HERE, "..", "plugin", "slim-tools.ts"))).default({})
  const tf = hooks["experimental.chat.system.transform"]
  console.log("\nslim-tools:")
  // FORMA REAL: opencode manda TODO el system prompt en UNA sola string
  // (prompt del agente + reglas + skills). La v1 de este hook se probo con un
  // array de strings separadas — una forma que no existe — y por eso no se
  // detecto que blanqueaba el prompt entero. Estos tests usan la forma real.
  const RULES_DISK = [
    readFileSync(join(HERE, "..", "rules", "engineering-discipline.md"), "utf8").trim(),
    readFileSync(join(HERE, "..", "rules", "knowledge-protocol.md"), "utf8").trim(),
  ]
  const combinado = (cabeza) => [`${cabeza}\n\n${RULES_DISK[0]}\n\n${RULES_DISK[1]}\n\n<available_skills>x</available_skills>`]

  await t("quita las reglas a un NON-CODING sin borrar su prompt", async () => {
    const cabeza = "NON-CODING AGENT: skip engineering rules\n" + "Actuas como PM. ".repeat(40)
    const o = { system: combinado(cabeza) }
    await tf({}, o)
    const r = o.system[0]
    if (r.includes("Engineering discipline")) throw new Error("no quito las reglas")
    if (!r.includes("Actuas como PM")) throw new Error("REGRESION v1: borro el prompt del agente")
    if (!r.includes("available_skills")) throw new Error("se llevo el bloque de skills")
    if (r.trim().length < 200) throw new Error("dejo el prompt casi vacio: " + r.trim().length)
  })
  await t("NO toca a un agente normal (sin la marca)", async () => {
    const o = { system: combinado("You are an autonomous software engineering agent. ".repeat(10)) }
    const antes = o.system[0]
    await tf({}, o)
    if (o.system[0] !== antes) throw new Error("modifico el prompt de `auto`")
  })
  await t("red de seguridad: nunca deja el system casi vacio", async () => {
    // Un agente cuyo prompt es SOLO la marca: quitar las reglas lo dejaria
    // en nada. Debe preferir no tocar nada antes que blanquearlo.
    const o = { system: [`NON-CODING AGENT: skip engineering rules\n\n${RULES_DISK[0]}`] }
    await tf({}, o)
    if (o.system[0].trim().length < 200) throw new Error("blanqueo el prompt (la red de seguridad no salto)")
  })
  await t("recorta la descripcion de bash y conserva lo critico", async () => {
    const long = "Executes a given bash command " + "x".repeat(4000) +
      "\nBe aware: OS: darwin, Shell: zsh\nUse `/tmp/oc` for temporary work outside\nexceeds 400 lines or 16000 bytes"
    const o = { description: long, parameters: {} }
    await hooks["tool.definition"]({ toolID: "bash" }, o)
    if (o.description.length > 1500) throw new Error("no recorto")
    for (const k of ["workdir", "400", "16000", "/tmp/oc", "darwin"])
      if (!o.description.includes(k)) throw new Error("perdio dato critico: " + k)
  })
  await t("no toca otras herramientas", async () => {
    const o = { description: "x".repeat(3000), parameters: {} }
    await hooks["tool.definition"]({ toolID: "read" }, o)
    if (o.description.length !== 3000) throw new Error("toco `read`")
  })
  await t("mete el bin de opencode en el PATH sin duplicar", async () => {
    const o = { env: { PATH: "/usr/bin" } }
    await hooks["shell.env"]({}, o); await hooks["shell.env"]({}, o)
    const hits = o.env.PATH.split(":").filter((x) => x.endsWith("opencode/bin"))
    if (hits.length !== 1) throw new Error("PATH: " + o.env.PATH)
  })
}

// ── ticket-format ────────────────────────────────────────────────────────
{
  const hooks = await (await import(join(HERE, "..", "plugin", "ticket-format.ts"))).default({})
  const tf = hooks["experimental.text.complete"]
  console.log("\nticket-format:")
  await t("renumera las secciones cuando el modelo repite la 5", async () => {
    const o = { text: ["h3. Titulo: X", "h3. 1. Resumen", "h3. 2. Contexto", "h3. 3. Criterios",
                       "h3. 4. DoD", "h3. 5. Notas", "h3. 5. Documentacion"].join("\n\n") }
    await tf({}, o)
    if (!o.text.includes("h3. 6. Documentacion")) throw new Error("no renumero: " + (o.text.match(/^h3\. \d+\./gm) || []).join(" "))
  })
  await t("NO toca texto que no es un ticket", async () => {
    const orig = "Claro, mira el punto h3. 5. de ese documento"
    const o = { text: orig }; await tf({}, o)
    if (o.text !== orig) throw new Error("modifico texto normal")
  })
  await t("NO toca un ticket ya bien numerado", async () => {
    const orig = ["h3. Titulo: X", "h3. 1. A", "h3. 2. B", "h3. 3. C"].join("\n\n")
    const o = { text: orig }; await tf({}, o)
    if (o.text !== orig) throw new Error("cambio un ticket correcto")
  })
  await t("renumera tambien el FICHERO que escribe la skill", async () => {
    // La skill `jira-ticket` ya no deja el ticket en el chat: lo escribe en
    // `ticket-<algo>.md`. Sin esto, el renumerado arreglaba el texto del chat y
    // el fichero —el que se lee y el que acaba en Jira— se quedaba con el
    // `h3. 5.` duplicado.
    const before = hooks["tool.execute.before"]
    const mal = ["h3. Titulo: X", "", "h3. 1. Resumen", "h3. 2. Contexto", "h3. 5. DoD", "h3. 5. Notas", "h3. 5. Documentacion"].join("\n")
    const a = { content: mal }
    await before({ tool: "write" }, { args: a })
    const nums = a.content.match(/^h3\. \d+\./gm).join(" ")
    if (nums !== "h3. 1. h3. 2. h3. 3. h3. 4. h3. 5.") throw new Error("mal renumerado: " + nums)
  })
  await t("un `edit` PARCIAL no se renumera (seria peor el remedio)", async () => {
    // Renumerar un fragmento desde 1 convertiria la seccion 5 en la 1.
    const before = hooks["tool.execute.before"]
    const frag = { newString: "h3. 5. Notas Tecnicas\n* algo" }
    await before({ tool: "edit" }, { args: frag })
    if (!frag.newString.startsWith("h3. 5.")) throw new Error("toco un fragmento: " + frag.newString)
    // Pero un edit que reemplaza el ticket COMPLETO si.
    const full = { newString: ["h3. Titulo: X", "h3. 1. A", "h3. 5. B", "h3. 5. C"].join("\n") }
    await before({ tool: "edit" }, { args: full })
    if (!full.newString.includes("h3. 3. C")) throw new Error("no renumero un ticket completo: " + full.newString)
  })
  await t("no toca un fichero que NO es un ticket", async () => {
    const before = hooks["tool.execute.before"]
    const readme = { content: "# Mi README\n\nh3. 5. esto no es un ticket\n" }
    await before({ tool: "write" }, { args: readme })
    if (!readme.content.includes("h3. 5. esto no es un ticket")) throw new Error("modifico un fichero normal")
  })
  await t("OPENCODE_TICKETFMT_OFF=1 lo desactiva", async () => {
    process.env.OPENCODE_TICKETFMT_OFF = "1"
    const orig = ["h3. Titulo: X", "h3. 1. A", "h3. 5. B", "h3. 5. C"].join("\n\n")
    const o = { text: orig }; await tf({}, o)
    delete process.env.OPENCODE_TICKETFMT_OFF
    if (o.text !== orig) throw new Error("sigue activo")
  })
}

// ── loop-breaker ─────────────────────────────────────────────────────────
{
  const hooks = await (await import(join(HERE, "..", "plugin", "loop-breaker.ts"))).default({})
  const before = hooks["tool.execute.before"], after = hooks["tool.execute.after"]
  // Devuelve "BLOCKED" si el hook corta, o ejecuta y registra la salida.
  const run = async (cmd, out = "", sid = "s") => {
    try { await before({ tool: "bash", sessionID: sid }, { args: { command: cmd } }) }
    catch (e) { return e.message }
    await after({ tool: "bash", sessionID: sid, args: { command: cmd } }, { output: out })
    return null
  }

  console.log("\nloop-breaker:")
  await t("corta al TERCER intento identico (el bucle de 229 pasos)", async () => {
    const cmd = 'webfetch "https://x.dev" 2>/dev/null | grep -i optional'
    if (await run(cmd, "", "a")) throw new Error("bloqueo en el 1er intento")
    if (await run(cmd, "", "a")) throw new Error("bloqueo en el 2o intento")
    const m = await run(cmd, "", "a")
    if (!m?.includes("BLOCKED (loop)")) throw new Error("no bloqueo el 3er intento: " + m)
  })
  await t("cambiar el grep tras el pipe NO cuenta como intento nuevo", async () => {
    // El bucle real alternaba `| grep -i max` y `| grep -i limit`.
    if (await run('ripgrep --help 2>&1 | grep -i "max"', "", "b")) throw new Error("1er intento")
    if (await run('ripgrep --help 2>&1 | grep -i "limit"', "", "b")) throw new Error("2o intento")
    const m = await run('ripgrep --help 2>&1 | grep -i "count"', "", "b")
    if (!m?.includes("BLOCKED (loop)")) throw new Error("no lo pillo por la clave de cabeza: " + m)
  })
  await t("el mensaje dice como salir (sin filtros, web.sh, skill)", async () => {
    for (const cmd of ["foo --bar", "foo --bar"]) await run(cmd, "", "c")
    const m = await run("foo --bar", "", "c")
    for (const hint of ["no `| grep`", "web.sh search", "unstick", "different approach"])
      if (!m?.includes(hint)) throw new Error("falta la pista '" + hint + "': " + m)
  })
  await t("un `|` entre comillas no crea una clave de cabeza falsa", async () => {
    // Misma regresion que en anti-slop-guard: aqui solo ensuciaria las claves,
    // pero el criterio es el mismo — un `|` dentro de comillas no es tuberia.
    const a = 'grep -E "HTTP|status" log.txt'
    const b = 'grep -E "HTTP|error" log.txt'
    if (await run(a, "hit", "q")) throw new Error("1er intento")
    if (await run(b, "hit", "q")) throw new Error("bloqueo dos greps DISTINTOS como si fueran el mismo")
  })
  await t("corta una tool que NO es bash repetida con los mismos argumentos", async () => {
    // Caso real: con el MCP de Jira caido, el modelo llamo a
    // `jiraAdmin_jira-ticket-create` 201 veces en un run. No lo pillaba porque
    // (a) solo se miraba bash y (b) una tool que falla puede no llegar al
    // `after`, asi que no habia salida que comparar. Ahora se cuentan INTENTOS.
    const call = async (tool, args, sid = "mcp") => {
      try { await before({ tool, sessionID: sid }, { args }); return null }
      catch (e) { return e.message }
    }
    const args = { projectKey: "FAC", summary: "Filtrar facturas" }
    for (const i of [1, 2, 3]) if (await call("jiraAdmin_jira-ticket-create", args)) throw new Error("bloqueo en el intento " + i)
    const m = await call("jiraAdmin_jira-ticket-create", args)
    if (!m?.includes("BLOCKED (loop)")) throw new Error("no bloqueo el 4o intento: " + m)
    if (!m.includes("Do NOT invent a result")) throw new Error("no avisa contra inventarse el resultado")
    // Otros argumentos = otra llamada, no es el mismo bucle.
    if (await call("jiraAdmin_jira-ticket-create", { projectKey: "OTRO", summary: "X" }))
      throw new Error("bloqueo una llamada con argumentos distintos")
  })
  await t("NO corta `skill`, `question` ni `todowrite` repetidos", async () => {
    // Cargar dos veces la misma skill es ruido, no un bucle: bloquearlo dejaria
    // al modelo sin su procedimiento justo cuando lo necesita.
    const call = async (tool, args) => {
      try { await before({ tool, sessionID: "exentos" }, { args }); return null }
      catch (e) { return e.message }
    }
    for (const i of [1, 2, 3, 4, 5]) {
      if (await call("skill", { name: "jira-ticket" })) throw new Error("bloqueo una skill repetida")
      if (await call("question", { text: "¿seguro?" })) throw new Error("bloqueo una pregunta repetida")
    }
  })
  await t("NO corta si la salida CAMBIA (polling legitimo)", async () => {
    for (const out of ["starting", "healthy", "healthy 1/1", "done"])
      if (await run("docker compose ps", out, "d")) throw new Error("bloqueo un polling que avanzaba")
  })
  await t("NO corta tras un edit: el mundo cambio", async () => {
    if (await run("go test ./...", "FAIL", "e")) throw new Error("1er intento")
    if (await run("go test ./...", "FAIL", "e")) throw new Error("2o intento")
    await after({ tool: "edit", sessionID: "e", args: { filePath: "a.go" } }, { output: "" })
    if (await run("go test ./...", "FAIL", "e")) throw new Error("bloqueo un reintento legitimo tras editar")
  })
  await t("avisa (sin bloquear) tras 15 comandos sin tocar un fichero", async () => {
    // Caso real: proyecto terminado en el paso ~20 y 100 pasos mas de "verificar"
    // variando el grep lo justo para no repetir clave. No se bloquea: un
    // analisis legitimo es todo lectura. Se le habla por la salida.
    const out = { output: "" }
    for (let i = 1; i <= 14; i++) {
      out.output = "linea " + i
      await after({ tool: "bash", sessionID: "n", args: { command: "ls -" + i } }, out)
      if (out.output.includes("loop-breaker")) throw new Error("aviso demasiado pronto (" + i + ")")
    }
    out.output = "linea 15"
    await after({ tool: "bash", sessionID: "n", args: { command: "ls -15" } }, out)
    if (!out.output.includes("[loop-breaker] 15 commands")) throw new Error("no aviso al 15: " + out.output)
    if (!out.output.startsWith("linea 15")) throw new Error("se cargo la salida original")
  })
  await t("el contador se reinicia al editar un fichero", async () => {
    const out = { output: "x" }
    for (let i = 1; i <= 14; i++) await after({ tool: "bash", sessionID: "r", args: { command: "ls -" + i } }, { output: "x" })
    await after({ tool: "edit", sessionID: "r", args: { filePath: "a.go" } }, { output: "" })
    await after({ tool: "bash", sessionID: "r", args: { command: "ls -15" } }, out)
    if (out.output.includes("loop-breaker")) throw new Error("no reinicio el contador tras el edit")
  })
  await t("las sesiones no se contaminan entre si", async () => {
    for (const i of [1, 2, 3]) await run("ls -la", "same", "s1")
    if (await run("ls -la", "same", "s2")) throw new Error("la sesion s2 hereda el historial de s1")
  })
  await t("al TERCER bloqueo el mensaje cambia y se hace imperativo", async () => {
    // MEDIDO: en una sesion real el modelo se comio el MISMO bloqueo 85 veces
    // con `cat /tmp/clock-app/print-time.js`. El mensaje largo dejaba de calar.
    const cmd = "cat /tmp/clock-app/print-time.js"
    for (const i of [1, 2]) await run(cmd, "", "esc")
    const m1 = await run(cmd, "", "esc")
    if (!m1?.includes("BLOCKED (loop)")) throw new Error("el 3er intento no bloqueo")
    await run(cmd, "", "esc")
    const m3 = await run(cmd, "", "esc")
    if (!m3?.startsWith("STOP.")) throw new Error("no escalo el mensaje: " + m3)
    if (!m3.includes("`read` tool")) throw new Error("no ofrece la alternativa real (tool read): " + m3)
  })
  await t("OPENCODE_LOOP_OFF=1 lo desactiva", async () => {
    process.env.OPENCODE_LOOP_OFF = "1"
    for (const i of [1, 2, 3, 4]) {
      const m = await run("stuck --forever", "", "f")
      if (m) { delete process.env.OPENCODE_LOOP_OFF; throw new Error("sigue activo: " + m) }
    }
    delete process.env.OPENCODE_LOOP_OFF
  })
}

// ── carga de plugins (como los carga opencode, no como los importa un test) ──
{
  const { readdirSync } = await import("fs")
  const dir = join(HERE, "..", "plugin")
  console.log("\ncarga de plugins:")
  await t("cada plugin exporta SOLO `default`", async () => {
    // REGRESION CARA: se exportaron dos helpers (`export function segments`) de
    // anti-slop-guard. opencode trata CUALQUIER named export como una factory de
    // plugin y la invoca con su PluginInput -> `cmd.split is not a function` ->
    // "failed to load plugin" y el guard dejo de existir EN SILENCIO durante
    // varios runs. Los tests seguian en verde porque importan `default` a mano:
    // por eso este test mira la FORMA del modulo, no su comportamiento.
    for (const f of readdirSync(dir).filter((f) => f.endsWith(".ts") || f.endsWith(".js"))) {
      const mod = await import(join(dir, f))
      const extra = Object.keys(mod).filter((k) => k !== "default")
      if (extra.length) throw new Error(`${f} exporta ademas: ${extra.join(", ")} — opencode los cargaria como plugins`)
      if (typeof mod.default !== "function") throw new Error(`${f}: default no es una funcion`)
    }
  })
  await t("cada plugin arranca y devuelve hooks", async () => {
    for (const f of readdirSync(dir).filter((f) => f.endsWith(".ts") || f.endsWith(".js"))) {
      const mod = await import(join(dir, f))
      const hooks = await mod.default({ directory: process.cwd(), client: {}, project: {}, $: () => {} })
      if (!hooks || typeof hooks !== "object") throw new Error(`${f}: no devolvio hooks`)
    }
  })
}

console.log(`\n  ${pass} pass, ${fail} fail`)
process.exit(fail ? 1 : 0)
