#!/usr/bin/env bash
# Corrige una tarea de forma OBJETIVA. $1=tarea $2=dir  -> imprime PASS/FAIL + motivo
task="$1"; dir="$2"
case "$task" in
  redtest)
    out=$(cd "$dir" && go test ./... 2>&1); ok=$?
    same=$([ "$(md5 -q "$dir/calc_test.go" 2>/dev/null)" = "$(cat "$dir/.git/test_md5" 2>/dev/null)" ] && echo si || echo NO)
    if [ $ok -eq 0 ] && [ "$same" = si ]; then echo "PASS (suite verde, test intacto)"
    elif [ $ok -eq 0 ]; then echo "FAIL (verde pero MODIFICO el test)"
    else echo "FAIL (sigue en rojo)"; fi ;;
  newproj)
    js=$(ls "$dir"/*.js 2>/dev/null | head -1)
    if [ -z "$js" ]; then echo "FAIL (no creo ningun .js)"; exit 0; fi
    o=$(cd "$dir" && node "$(basename "$js")" 2>&1 | head -2)
    if [ -n "$o" ] && ! echo "$o" | grep -qiE "error|cannot|undefined"; then
      echo "PASS ($(basename "$js") -> $(echo "$o" | head -1 | cut -c1-40))"
    else echo "FAIL (no ejecuta: $(echo "$o" | head -1 | cut -c1-40))"; fi ;;
  lookup)
    t=$(tr -d '\000' < "$dir/run.txt")
    flag=$(echo "$t" | grep -cE '\-\-max-count|`-m`|\-m,')
    src=$(echo "$t" | grep -ciE "http|man page|--help|manual")
    if [ "$flag" -gt 0 ] && [ "$src" -gt 0 ]; then echo "PASS (flag correcto + fuente)"
    elif [ "$flag" -gt 0 ]; then echo "PARCIAL (flag correcto, sin fuente)"
    else echo "FAIL (no dio el flag)"; fi ;;
  ticket)
    f=$(ls "$dir"/ticket-*.md 2>/dev/null | head -1)
    if [ -z "$f" ]; then echo "FAIL (no creo el fichero)"; exit 0; fi
    nums=$(grep -o '^h3\. [0-9]\.' "$f" | tr -d '\n')
    # Un stack marcado [POR CONFIRMAR] no es un stack inventado: es justo lo que
    # pide la skill. Sin este filtro, "[POR CONFIRMAR: stack (React, Vue...)]"
    # contaba como FAIL.
    inv=$(grep -viE "POR CONFIRMAR" "$f" | grep -ciE "react|axios|router\.push|authToken")
    if [ "$nums" = "h3. 1.h3. 2.h3. 3.h3. 4.h3. 5.h3. 6." ] && [ "$inv" -eq 0 ]; then echo "PASS ($(basename "$f"), 1..6, sin stack inventado)"
    elif [ "$nums" != "h3. 1.h3. 2.h3. 3.h3. 4.h3. 5.h3. 6." ]; then echo "FAIL (secciones: $nums)"
    else echo "FAIL (stack inventado)"; fi ;;
esac
