#!/bin/bash
# devsec.sh — DevSecurityMX CLI v2.0
# Uso: ./devsec.sh <comando> [opciones]

set -euo pipefail

VERSION="2.0.0"
CMD="${1:-help}"
shift || true

# ── COLORES ────────────────────────────────────────────────────────────────
G='\033[0;32m'
R='\033[0;31m'
C='\033[0;36m'
Y='\033[1;33m'
D='\033[2m'
N='\033[0m'
BOLD='\033[1m'

# ── DEFAULTS ───────────────────────────────────────────────────────────────
PORT=""
MODE="normal"
VERBOSE=false
JSON=false
PORT_WEB=8000
OUTPUT=""
CHIP_FORCE=""
BAUD_FORCE=""
NO_GHIDRA=false
REPORT_ONLY=false
TIMEOUT=120
STRINGS_MIN=6
DUMP_SIZE=""
NO_FORENSICS=false
NO_HASH=false
NO_STRINGS=false
NO_ANALYZE=false
OPEN_WEB=false
QUIET=false
AUTO_WEB=false
DRY_RUN=false
FORMAT="txt"
TAG=""
NOTE=""

# ── PARSER ─────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port|-p)        PORT="$2";        shift 2 ;;
        --baud|-b)        BAUD_FORCE="$2";  shift 2 ;;
        --chip)           CHIP_FORCE="$2";  shift 2 ;;
        --timeout|-t)     TIMEOUT="$2";     shift 2 ;;
        --full)           MODE="full";      shift ;;
        --fast)           MODE="fast";      shift ;;
        --forensic)       MODE="forensic";  shift ;;
        --report-only)    REPORT_ONLY=true; shift ;;
        --dry-run)        DRY_RUN=true;     shift ;;
        --dump-size)      DUMP_SIZE="$2";   shift 2 ;;
        --strings-min)    STRINGS_MIN="$2"; shift 2 ;;
        --no-strings)     NO_STRINGS=true;  shift ;;
        --no-analyze)     NO_ANALYZE=true;  shift ;;
        --no-forensics)   NO_FORENSICS=true;shift ;;
        --no-hash)        NO_HASH=true;     shift ;;
        --no-ghidra)      NO_GHIDRA=true;   shift ;;
        --output|-o)      OUTPUT="$2";      shift 2 ;;
        --json)           JSON=true;        shift ;;
        --format)         FORMAT="$2";      shift 2 ;;
        --tag)            TAG="$2";         shift 2 ;;
        --note)           NOTE="$2";        shift 2 ;;
        --port-web)       PORT_WEB="$2";    shift 2 ;;
        --open)           OPEN_WEB=true;    shift ;;
        --auto-web)       AUTO_WEB=true;    shift ;;
        --verbose|-v)     VERBOSE=true;     shift ;;
        --quiet|-q)       QUIET=true;       shift ;;
        --version)        echo "devsec v$VERSION"; exit 0 ;;
        --days)           DAYS="$2";        shift 2 ;;
        --web)            WEB_HELP=true;    shift ;;
        *) shift ;;
    esac
done

DAYS="${DAYS:-30}"
WEB_HELP="${WEB_HELP:-false}"

# ── HELPERS ────────────────────────────────────────────────────────────────
_latest_dir() { ls -td devsec-out/*/ 2>/dev/null | head -n1 || true; }
_p()          { $QUIET || echo -e "$@"; }

# ── HELP ───────────────────────────────────────────────────────────────────
help() {
# ── Modo web: lanzar servidor y abrir docs en navegador ───────────────────
if $WEB_HELP; then
    _p "\n ${G}→${N} Abriendo documentación web en http://127.0.0.1:${PORT_WEB}/help\n"
    python3 -m pip install --user fastapi uvicorn &>/dev/null || true

    # Iniciar servidor en background si no está corriendo
    if ! lsof -i :"$PORT_WEB" &>/dev/null 2>&1; then
        python3 -m uvicorn server:app \
            --host 127.0.0.1 \
            --port "$PORT_WEB" \
            --log-level error &
        SERVER_PID=$!
        sleep 1
        _p " ${D}Servidor iniciado (PID $SERVER_PID). Ctrl+C para detener.${N}"
    fi

    # Abrir navegador
    xdg-open "http://127.0.0.1:${PORT_WEB}/help" 2>/dev/null \
        || open "http://127.0.0.1:${PORT_WEB}/help" 2>/dev/null \
        || _p " ${Y}Abre manualmente:${N} http://127.0.0.1:${PORT_WEB}/help"

    # Mantener proceso vivo para servir la página
    _p " ${D}Presiona Ctrl+C para cerrar el servidor.${N}\n"
    wait "$SERVER_PID" 2>/dev/null || true
    exit 0
fi
_p "
${BOLD}${C}DevSecurityMX CLI${N} ${D}v${VERSION}${N}
${D}MCU Firmware Audit Framework — ESP32 / ESP8266${N}

${BOLD}COMANDOS${N}
  ${G}scan${N}       Adquiere y analiza firmware del dispositivo
  ${G}analyze${N}    Muestra el reporte del último scan
  ${G}report${N}     Imprime reporte en texto plano
  ${G}list${N}       Lista todos los scans disponibles
  ${G}clean${N}      Elimina scans antiguos
  ${G}web${N}        Lanza el dashboard web
  ${G}met${N}        Muestra el pipeline de metodología
  ${G}version${N}    Muestra la versión
  ${G}help${N}       Muestra esta ayuda

${BOLD}CONEXIÓN${N}
  ${Y}--port,    -p${N}  <DEV>     Puerto serie          ${D}(ej: /dev/ttyUSB0)${N}
  ${Y}--baud,    -b${N}  <RATE>    Baud rate forzado     ${D}(ej: 115200)${N}
  ${Y}--chip${N}         <MODELO>  Forzar chip           ${D}ESP32 | ESP8266${N}
  ${Y}--timeout, -t${N}  <SEG>     Timeout de dump       ${D}[120]${N}

${BOLD}MODO DE OPERACIÓN${N}
  ${Y}--full${N}                   Dump completo + Ghidra
  ${Y}--fast${N}                   Dump rápido de 1MB
  ${Y}--forensic${N}               Solo forense, sin dump
  ${Y}--report-only${N}            Regenera reporte sin dump
  ${Y}--dry-run${N}                Simula sin ejecutar nada

${BOLD}DUMP${N}
  ${Y}--dump-size${N}    <HEX>     Tamaño personalizado  ${D}[0x400000]${N}

${BOLD}ANÁLISIS${N}
  ${Y}--strings-min${N}  <N>       Longitud mínima de strings  ${D}[6]${N}
  ${Y}--no-strings${N}             Omitir extracción de strings
  ${Y}--no-analyze${N}             Omitir análisis de riesgo
  ${Y}--no-forensics${N}           Omitir recolección forense
  ${Y}--no-hash${N}                Omitir cálculo de hashes
  ${Y}--no-ghidra${N}              No lanzar Ghidra en modo --full

${BOLD}OUTPUT${N}
  ${Y}--output,  -o${N}  <DIR>     Directorio destino personalizado
  ${Y}--json${N}                   Salida en JSON (analyze / report)
  ${Y}--format${N}       <FMT>     Formato de reporte: txt|json|both  ${D}[txt]${N}
  ${Y}--tag${N}          <LABEL>   Etiqueta identificadora del scan
  ${Y}--note${N}         <TEXTO>   Nota/comentario en el reporte

${BOLD}WEB${N}
  ${Y}--port-web${N}     <PORT>    Puerto del servidor web  ${D}[8000]${N}
  ${Y}--open${N}                   Abrir navegador automáticamente

${BOLD}LIMPIEZA${N}
  ${Y}--days${N}         <N>       Antigüedad para clean    ${D}[30]${N}

${BOLD}UX${N}
  ${Y}--verbose, -v${N}            Salida detallada
  ${Y}--quiet,   -q${N}            Silencioso (solo errores)
  ${Y}--version${N}                Muestra versión y sale
  ${Y}--web${N}                    Con --help: abre docs en el navegador

${BOLD}EJEMPLOS${N}
  ${D}# Abrir documentación web${N}
  ./devsec.sh --help --web

  ${D}# Scan completo con puerto y etiqueta${N}
  ./devsec.sh scan --port /dev/ttyUSB0 --full --tag produccion

  ${D}# Scan rápido, sin Ghidra, reporte en JSON${N}
  ./devsec.sh scan --fast --no-ghidra --format json

  ${D}# Solo forensics con dump de 2MB${N}
  ./devsec.sh scan --forensic --dump-size 0x200000

  ${D}# Ver último reporte en JSON${N}
  ./devsec.sh analyze --json

  ${D}# Dashboard en puerto 9090, abrir navegador${N}
  ./devsec.sh web --port-web 9090 --open

  ${D}# Listar scans y limpiar los de más de 7 días${N}
  ./devsec.sh list
  ./devsec.sh clean --days 7
"
}

# ── MET ────────────────────────────────────────────────────────────────────
met() {
_p "
${BOLD}${C}DevSecurityMX — Pipeline${N}

  ${G}[1]${N} Acquisition      → Dump de flash via esptool
  ${G}[2]${N} Processing       → Extracción de app, hashes SHA256
  ${G}[3]${N} Forensics        → dmesg, lsusb, info de sistema
  ${G}[4]${N} Analysis         → Strings, score de riesgo, findings
  ${G}[5]${N} Reverse Eng.     → Ghidra headless (modo --full)
  ${G}[6]${N} Reporting        → JSON + TXT estructurado con tags
  ${G}[7]${N} Visualization    → Dashboard web interactivo
"
}

# ── SCAN ───────────────────────────────────────────────────────────────────
scan() {
    ARGS=()

    # ── AUTO-DETECCIÓN DE PUERTO ──────────────────────────────────────────
    if [[ -z "$PORT" ]]; then
        PORT=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -n1 || true)
        [[ -n "$PORT" ]] && _p "${D}Auto-detect:${N} usando $PORT"
    fi

    # Validación
    if [[ -z "$PORT" ]]; then
        echo -e "${R}Error:${N} No se detectó ningún puerto serie"
        echo -e "${D}Tip:${N} conecta el dispositivo o usa --port"
        exit 1
    fi

    # Verificar acceso al puerto
    if [[ ! -r "$PORT" || ! -w "$PORT" ]]; then
        echo -e "${Y}WARN:${N} Sin permisos sobre $PORT"
        echo -e "${D}Sugerencia:${N} sudo usermod -aG dialout \$USER"
    fi

    ARGS+=("$PORT")

    # ── MODOS ─────────────────────────────────────────────────────────────
    [[ "$MODE" != "normal" ]] && ARGS+=("--$MODE")

    # ── FLAGS CORE ────────────────────────────────────────────────────────
    [[ -n "$BAUD_FORCE" ]] && ARGS+=("--baud" "$BAUD_FORCE")
    [[ -n "$CHIP_FORCE" ]] && ARGS+=("--chip" "$CHIP_FORCE")
    [[ -n "$OUTPUT"     ]] && ARGS+=("--output" "$OUTPUT")
    [[ -n "$DUMP_SIZE"  ]] && ARGS+=("--dump-size" "$DUMP_SIZE")
    [[ -n "$TAG"        ]] && ARGS+=("--tag" "$TAG")
    [[ -n "$NOTE"       ]] && ARGS+=("--note" "$NOTE")

    ARGS+=("--timeout" "$TIMEOUT")
    ARGS+=("--strings-min" "$STRINGS_MIN")
    ARGS+=("--format" "$FORMAT")

    # ── FLAGS BOOLEANOS ───────────────────────────────────────────────────
    $VERBOSE      && ARGS+=("--verbose")
    $QUIET        && ARGS+=("--quiet")
    $NO_GHIDRA    && ARGS+=("--no-ghidra")
    $NO_FORENSICS && ARGS+=("--no-forensics")
    $NO_HASH      && ARGS+=("--no-hash")
    $NO_STRINGS   && ARGS+=("--no-strings")
    $NO_ANALYZE   && ARGS+=("--no-analyze")
    $REPORT_ONLY  && ARGS+=("--report-only")

    # ── DRY RUN ───────────────────────────────────────────────────────────
    if $DRY_RUN; then
        _p "${Y}[DRY-RUN]${N} bash esp.sh ${ARGS[*]}"
        exit 0
    fi

    # ── EJECUCIÓN ─────────────────────────────────────────────────────────
    _p "${C}→${N} Ejecutando adquisición y análisis..."
    _p "${D}Comando:${N} bash esp.sh ${ARGS[*]}\n"

    if ! bash esp.sh "${ARGS[@]}"; then
        echo -e "\n${R}Error:${N} Falló el proceso de adquisición"
        echo -e "${D}Revisa logs en devsec-out/*/logs/${N}"
        exit 1
    fi

    _p "\n${G}✔ Scan completado correctamente${N}"

    if [[ "$AUTO_WEB" == true ]]; then
        _p "\n${C}→${N} Abriendo dashboard web automáticamente...\n"
        devsec web
    fi
}

# ── ANALYZE ────────────────────────────────────────────────────────────────
analyze() {
    DIR=$(_latest_dir)
    [[ -z "$DIR" ]] && { echo "No hay scans en devsec-out/"; exit 1; }
    $JSON \
        && cat "${DIR}report/report.json" \
        || cat "${DIR}report/report.txt"
}

# ── REPORT ─────────────────────────────────────────────────────────────────
report() {
    DIR=$(_latest_dir)
    [[ -z "$DIR" ]] && { echo "No hay reportes."; exit 1; }
    [[ "$FORMAT" == "json" ]] \
        && cat "${DIR}report/report.json" \
        || cat "${DIR}report/report.txt"
}

# ── LIST ───────────────────────────────────────────────────────────────────
list() {
    [[ ! -d "devsec-out" ]] && { _p "Sin scans."; exit 0; }
    _p "\n${BOLD}Scans disponibles:${N}\n"
    local i=1
    for d in $(ls -td devsec-out/*/); do
        local id="${d##devsec-out/}"; id="${id%%/}"
        local risk="—" chip="—" score="—" tag=""
        if [[ -f "$d/report/report.json" ]]; then
            risk=$(python3  -c "import json; d=json.load(open('$d/report/report.json')); print(d.get('risk','—'))"  2>/dev/null || echo "—")
            chip=$(python3  -c "import json; d=json.load(open('$d/report/report.json')); print(d.get('chip','—'))"  2>/dev/null || echo "—")
            score=$(python3 -c "import json; d=json.load(open('$d/report/report.json')); print(d.get('score','—'))" 2>/dev/null || echo "—")
            tag=$(python3   -c "import json; d=json.load(open('$d/report/report.json')); print(d.get('tag',''))"    2>/dev/null || echo "")
        fi
        local color=$G
        [[ "$risk" == "CRITICO" ]] && color=$R
        [[ "$risk" == "ALTO"    ]] && color=$Y
        [[ "$risk" == "MEDIO"   ]] && color=$Y
        local tag_str=""; [[ -n "$tag" ]] && tag_str=" ${D}[$tag]${N}"
        _p "  ${D}$i.${N} ${C}$id${N}${tag_str}"
        _p "     Chip: ${BOLD}$chip${N}  Score: ${BOLD}$score${N}  Risk: ${color}${BOLD}$risk${N}\n"
        ((i++))
    done
}

# ── CLEAN ──────────────────────────────────────────────────────────────────
clean() {
    [[ ! -d "devsec-out" ]] && { _p "Sin scans."; exit 0; }
    local count=0
    while IFS= read -r dir; do
        rm -rf "$dir"
        _p "${R}Eliminado:${N} $dir"
        ((count++)) || true
    done < <(find devsec-out -maxdepth 1 -mindepth 1 -type d -mtime +"$DAYS")
    _p "\n${G}Limpieza completa:${N} $count scan(s) eliminados (>$DAYS días)\n"
}

# ── BANNER WEB (MEJORADO) ──────────────────────────────────────────────────
banner_web() {
    LAST_SCAN=$(ls -td devsec-out/*/ 2>/dev/null | head -n 1 || true)
    RISK="N/A"
    COLOR="\033[0;37m"

    if [[ -n "$LAST_SCAN" && -f "${LAST_SCAN}report/report.json" ]]; then
        RISK=$(python3 -c \
            "import json; d=json.load(open('${LAST_SCAN}report/report.json')); print(d.get('risk','N/A'))" \
            2>/dev/null || echo "N/A")
        case "$RISK" in
            CRITICO) COLOR="\033[0;31m"  ;;
            ALTO)    COLOR="\033[1;31m"  ;;
            MEDIO)   COLOR="\033[1;33m"  ;;
            BAJO)    COLOR="\033[0;32m"  ;;
        esac
    fi

    local SCAN_LABEL="${LAST_SCAN##devsec-out/}"
    SCAN_LABEL="${SCAN_LABEL%/}"
    [[ -z "$SCAN_LABEL" ]] && SCAN_LABEL="None"

    echo -e "$COLOR"
    echo "=============================================================="
    echo " DevSecWeb — DevSecurityMX Red Team Interface"
    echo "--------------------------------------------------------------"
    printf " Target:    %s\n" "127.0.0.1:$PORT_WEB"
    printf " Operator:  %s@%s\n" "$USER" "$(hostname)"
    printf " Last Scan: %s\n" "$SCAN_LABEL"
    printf " Risk:      %s\n" "$RISK"
    echo "=============================================================="
    echo -e "\033[0m"
}

# ── WEB ────────────────────────────────────────────────────────────────────
web() {
    clear
    banner_web
    python3 -m pip install --user fastapi uvicorn &>/dev/null || true
    _p " ${G}→${N} http://127.0.0.1:${PORT_WEB}  (Ctrl+C para detener)\n"

    if $OPEN_WEB; then
        sleep 1 && (xdg-open "http://127.0.0.1:${PORT_WEB}" 2>/dev/null \
            || open "http://127.0.0.1:${PORT_WEB}" 2>/dev/null || true) &
    fi

    python3 -m uvicorn server:app \
        --host 127.0.0.1 \
        --port "$PORT_WEB" \
        --log-level warning
}

# ── ROUTER ─────────────────────────────────────────────────────────────────
case "$CMD" in
    scan)           scan    ;;
    analyze)        analyze ;;
    report)         report  ;;
    list)           list    ;;
    clean)          clean   ;;
    web)            web     ;;
    met)            met     ;;
    version)        echo "devsec v$VERSION" ;;
    help|--help|-h) help    ;;
    *) _p "${R}Comando desconocido:${N} $CMD\n"; help ;;
esac