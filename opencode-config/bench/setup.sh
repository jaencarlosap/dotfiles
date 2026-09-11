#!/usr/bin/env bash
# Crea el fixture limpio de una tarea. $1=tarea $2=directorio destino
set -euo pipefail
task="$1"; dir="$2"
rm -rf "$dir"; mkdir -p "$dir"
# Cada fixture es su PROPIO repo git. Sin esto el directorio es un subdirectorio
# gitignorado de dotfiles: `git status --short` sale vacio aunque el agente
# acabe de editar calc.go, y el agente (que debe comprobar el arbol antes de
# decir que termino) se pasa 5 turnos con git diff / ls-files intentando
# explicar por que "no hay cambios". Medido: eso eran la mitad de los turnos de
# `redtest`. El commit inicial hace que el diff muestre SOLO lo que hizo el agente.
# `run.txt` y `.seconds` los escribe el runner MIENTRAS el agente trabaja: van
# ignorados para que no aparezcan como "ficheros de mas" que el agente borre.
git init -q "$dir" && ( cd "$dir" && printf 'run.txt\n.seconds\n' > .gitignore && git add .gitignore && git commit -q -m "fixture" )
case "$task" in
  redtest)
    printf 'module calc\n\ngo 1.24\n' > "$dir/go.mod"
    cat > "$dir/calc.go" <<'EOF'
package calc

// Sum devuelve la suma de dos enteros.
func Sum(a, b int) int {
	return a - b
}

// Discount aplica un porcentaje de descuento y devuelve el precio final.
func Discount(price float64, pct float64) float64 {
	return price * pct / 100
}
EOF
    cat > "$dir/calc_test.go" <<'EOF'
package calc

import "testing"

func TestSum(t *testing.T) {
	if got := Sum(2, 3); got != 5 {
		t.Fatalf("Sum(2,3) = %d, quiero 5", got)
	}
}

func TestDiscount(t *testing.T) {
	if got := Discount(200, 10); got != 180 {
		t.Fatalf("Discount(200,10) = %v, quiero 180", got)
	}
}
EOF
    # El md5 de referencia va DENTRO de .git/: un `.test_md5` a la vista
    # distrajo al agente (build) 8 turnos intentando adivinar de que era el hash.
    md5 -q "$dir/calc_test.go" > "$dir/.git/test_md5"
    ( cd "$dir" && git add -A && git commit -q -m "red suite" )
    ;;
  newproj|lookup|ticket) : ;;  # directorio vacio
esac
