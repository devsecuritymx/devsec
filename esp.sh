#!/bin/bash
# esp.sh — DevSecurityMX · Firmware Acquisition & Analysis Core v2.0
# Uso: ./esp.sh [PORT] [opciones]

set -euo pipefail
umask 077

# ── COLORES ────────────────────────────────────────────────────────────────
R='\033[0;31m' Y='\033[1;33m' G='\033[0;32m' C='\033[0;36m' D='\033[2m' N='\033[0m'

ts()   { date +"[%H:%M:%S]"; }
log()  { $QUIET || echo -e "$(ts) ${D}···${N} $1"; echo "$(ts) INFO:  $1" >> "$LOG"; }
ok()   { $QUIET || echo -e "$(ts) ${G}OK ${N} $1"; echo "$(ts) OK:    $1" >> "$LOG"; }
warn() { $QUIET || echo -e "$(ts) ${Y}WARN${N} $1"; echo "$(ts) WARN:  $1" >> "$LOG"; }
die()  {           echo -e "$(ts) ${R}ERR ${N} $1"; echo "$(ts) ERROR: $1" >> "$LOG"; exit 1; }
verb() { $VERBOSE && echo -e "$(ts) ${D}DBG ${N} $1" || true; }

# ── DEFAULTS ───────────────────────────────────────────────────────────────
PORT=""
MODE="normal"
VERBOSE=false
QUIET=false
BAUD_FORCE=""
CHIP_FORCE=""
TIMEOUT=120
DUMP_SIZE=""
STRINGS_MIN=6
NO_GHIDRA=false
NO_FORENSICS=false
NO_HASH=false
NO_STRINGS=false
NO_ANALYZE=false
REPORT_ONLY=false
OUTPUT=""
FORMAT="txt"
TAG=""
NOTE=""

# ── PARSER ─────────────────────────────────────────────────────────────────
# Primer arg posicional sin '--' = puerto
if [[ $# -gt 0 && "${1:-}" != --* ]]; then
    PORT="$1"; shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port|-p)        PORT="$2";         shift 2 ;;
        --baud|-b)        BAUD_FORCE="$2";   shift 2 ;;
        --chip)           CHIP_FORCE="$2";   shift 2 ;;
        --timeout|-t)     TIMEOUT="$2";      shift 2 ;;
        --full)           MODE="full";        shift ;;
        --fast)           MODE="fast";        shift ;;
        --forensic)       MODE="forensic";    shift ;;
        --report-only)    REPORT_ONLY=true;   shift ;;
        --dump-size)      DUMP_SIZE="$2";     shift 2 ;;
        --strings-min)    STRINGS_MIN="$2";   shift 2 ;;
        --no-strings)     NO_STRINGS=true;    shift ;;
        --no-analyze)     NO_ANALYZE=true;    shift ;;
        --no-forensics)   NO_FORENSICS=true;  shift ;;
        --no-hash)        NO_HASH=true;       shift ;;
        --no-ghidra)      NO_GHIDRA=true;     shift ;;
        --output|-o)      OUTPUT="$2";        shift 2 ;;
        --format)         FORMAT="$2";        shift 2 ;;
        --tag)            TAG="$2";           shift 2 ;;
        --note)           NOTE="$2";          shift 2 ;;
        --verbose|-v)     VERBOSE=true;       shift ;;
        --quiet|-q)       QUIET=true;         shift ;;
        *) shift ;;
    esac
done

# ── WORKSPACE ──────────────────────────────────────────────────────────────
TS=$(date +"%Y-%m-%d_%H-%M-%S")
if [[ -n "$OUTPUT" ]]; then
    WD="$OUTPUT/$TS"
else
    WD="devsec-out/$TS"
fi

LOG_DIR="$WD/logs"
LOG="$LOG_DIR/run.log"
DUMP="$WD/dump/firmware.bin"
APP="$WD/dump/app.bin"

mkdir -p "$WD"/{logs,dump,analysis,report,forensics}
touch "$LOG"

# ── BANNER ─────────────────────────────────────────────────────────────────
$QUIET || {
echo -e "${C}"
cat <<'EOF'
 ██████╗ ███████╗██╗   ██╗███████╗███████╗ ██████╗
 ██╔══██╗██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝
 ██║  ██║█████╗  ██║   ██║███████╗█████╗  ██║
 ██║  ██║██╔══╝  ╚██╗ ██╔╝╚════██║██╔══╝  ██║     ███╗
 ██████╔╝███████╗ ╚████╔╝ ███████║███████╗╚██████╔╝╚██║
 ╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚══════╝ ╚═════╝  ╚═╝
EOF
echo -e "${N}"
printf " ${D}Operator:${N}  %s@%s\n" "$USER" "$(hostname)"
printf " ${D}Workspace:${N} %s\n"   "$WD"
printf " ${D}Mode:${N}      %s\n"   "$MODE"
[[ -n "$TAG"  ]] && printf " ${D}Tag:${N}       %s\n" "$TAG"
[[ -n "$NOTE" ]] && printf " ${D}Note:${N}      %s\n" "$NOTE"
echo ""
}

log "Inicializando — modo: $MODE"

# ── DEPENDENCIAS ───────────────────────────────────────────────────────────
for dep in esptool.py strings dd sha256sum; do
    command -v "$dep" &>/dev/null || warn "Dependencia no encontrada: $dep"
done
pip install --quiet esptool &>/dev/null || true

# ── GHIDRA XTENSA ──────────────────────────────────────────────────────────
if [[ ! -d "ghidra-xtensa" ]]; then
    if command -v git &>/dev/null; then
        log "Clonando ghidra-xtensa..."
        git clone https://github.com/Ebiroll/ghidra-xtensa.git ghidra-xtensa
        ok "ghidra-xtensa clonado"
    else
        warn "Git no disponible; instala ghidra-xtensa manualmente"
    fi
fi

# ── HEX TOOL ───────────────────────────────────────────────────────────────
if   command -v xxd     &>/dev/null; then HEX="xxd"
elif command -v hexdump &>/dev/null; then HEX="hexdump -C"; warn "xxd no disponible"
else die "Sin herramienta hex (xxd / hexdump)"; fi

# ── PUERTO ─────────────────────────────────────────────────────────────────
[[ -z "$PORT" ]] && PORT=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | head -n1 || true)
[[ -n "$PORT" ]] || die "No se detectó dispositivo serie"
ok "Puerto: $PORT"
verb "Port path: $PORT"

# ── CHIP ───────────────────────────────────────────────────────────────────
if [[ -n "$CHIP_FORCE" ]]; then
    CHIP="$CHIP_FORCE"
    ok "Chip forzado: $CHIP"
else
    log "Identificando chip..."
    CHIP_RAW=$(esptool.py --port "$PORT" chip_id 2>&1 || true)
    verb "chip_id raw: $CHIP_RAW"

    if   echo "$CHIP_RAW" | grep -qi ESP32;   then CHIP="ESP32"
    elif echo "$CHIP_RAW" | grep -qi ESP8266; then CHIP="ESP8266"
    else CHIP="UNKNOWN"; warn "Chip no reconocido"; fi

    ok "Chip: $CHIP"
fi

# ── FORENSICS ──────────────────────────────────────────────────────────────
if ! $NO_FORENSICS && [[ "$MODE" != "fast" ]]; then
    log "Recolectando datos forenses..."
    uname -a > "$WD/forensics/system.txt"
    lsusb    > "$WD/forensics/usb.txt"    2>/dev/null || true

    if dmesg &>/dev/null 2>&1; then
        dmesg | tail -n 50 > "$WD/forensics/dmesg.txt"; ok "dmesg capturado"
    elif sudo -v 2>/dev/null; then
        sudo dmesg | tail -n 50 > "$WD/forensics/dmesg.txt"; ok "dmesg (sudo)"
    else
        warn "dmesg omitido (sin privilegios)"
    fi
fi

# ── REPORT-ONLY ────────────────────────────────────────────────────────────
if $REPORT_ONLY; then
    warn "Modo report-only: omitiendo dump"
    DUMP_BYTES=0
    CHIP="${CHIP:-UNKNOWN}"
    SCORE=0
    RISK="BAJO"
    # Saltar directamente al reporte
    goto_report=true
else
    goto_report=false
fi

# ── DUMP ───────────────────────────────────────────────────────────────────
if ! $goto_report; then
    # Tamaño de dump
    if [[ -n "$DUMP_SIZE" ]]; then
        DS="$DUMP_SIZE"
    elif [[ "$MODE" == "fast" ]]; then
        DS="0x100000"
    else
        DS="0x400000"
    fi

    # Baud args
    BAUD_ARGS=()
    [[ -n "$BAUD_FORCE" ]] && BAUD_ARGS=("--baud" "$BAUD_FORCE")

    log "Iniciando dump ($DS)..."
    verb "Dump size: $DS | Timeout: ${TIMEOUT}s"

    # ── DUMP ROBUSTO (DevSecurityMX FIX) ───────────────────────────────────────
BAUDS=()

# Si el usuario forzó baud, usar solo ese
if [[ -n "$BAUD_FORCE" ]]; then
    BAUDS=("$BAUD_FORCE")
else
    BAUDS=(115200 230400 460800 921600)
fi

DUMP_OK=false

for B in "${BAUDS[@]}"; do
    log "Intentando dump a baud $B..."

    # Reset suave del puerto (ayuda MUCHO con ESP32)
    stty -F "$PORT" hupcl 2>/dev/null || true
    sleep 1

    if timeout "$TIMEOUT" esptool.py \
        --port "$PORT" \
        --baud "$B" \
        read_flash 0x0 "$DS" "$DUMP" \
        > "$WD/logs/esptool_$B.log" 2>&1; then

        ok "Dump completado con baud $B"
        DUMP_OK=true
        break
    else
        warn "Fallo en baud $B (ver logs/esptool_$B.log)"
    fi
done

if ! $DUMP_OK; then
    die "Dump fallido en todos los baud rates"
fi

    DUMP_BYTES=$(wc -c < "$DUMP")
    ok "Firmware: $DUMP_BYTES bytes"

    # ── VALIDACIÓN ─────────────────────────────────────────────────────────
    FF_LINES=$($HEX "$DUMP" | grep -c "ff ff ff ff" || true)
    TOTAL_LINES=$($HEX "$DUMP" | wc -l)
    (( TOTAL_LINES > 0 && FF_LINES * 100 / TOTAL_LINES > 90 )) && \
        warn "Dump sospechoso (>90% 0xFF) — posible lectura fallida"

    # ── EXTRAER APP ────────────────────────────────────────────────────────
    if (( DUMP_BYTES > 65536 )); then
        dd if="$DUMP" of="$APP" bs=1 skip=65536 status=none
        ok "App partition extraída (offset 0x10000)"
    else
        warn "Dump demasiado pequeño; usando dump completo como app"
        APP="$DUMP"
    fi

    # ── VALIDACIÓN DE DUMP ─────────────────────────────────────────────────
    FILE_TYPE=$(file "$DUMP" 2>/dev/null || echo "unknown")
    ok "Tipo de firmware: $FILE_TYPE"
    verb "file output: $FILE_TYPE"

    # ── CHECKSUM AUTOMÁTICO ────────────────────────────────────────────────
    if ! $NO_HASH; then
        sha256sum "$DUMP" > "$WD/forensics/dump.sha256"
        sha256sum "$APP"  > "$WD/forensics/app.sha256"
        ok "SHA256 generados"
        verb "Dump hash: $(cat $WD/forensics/dump.sha256)"
    fi

    # ── STRINGS ────────────────────────────────────────────────────────────
    if ! $NO_STRINGS; then
        log "Extrayendo strings (min ${STRINGS_MIN} chars)..."
        strings -n "$STRINGS_MIN" "$APP" > "$WD/analysis/strings.txt"
        STR_COUNT=$(wc -l < "$WD/analysis/strings.txt")
        ok "Strings extraídas: $STR_COUNT"
    fi

    # ── ANÁLISIS ───────────────────────────────────────────────────────────
    SCORE=0
    if ! $NO_ANALYZE && ! $NO_STRINGS; then
        log "Analizando riesgo..."
        STR="$WD/analysis/strings.txt"

        # ── DETECCIÓN DE SECRETOS REALES ────────────────────────────────────
        SECRETS_FOUND=$(grep -E "AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}" "$STR" 2>/dev/null || true)
        if [[ -n "$SECRETS_FOUND" ]]; then
            warn "AWS Access Key detectada (AKIA/ASIA)"
            echo "$SECRETS_FOUND" > "$WD/analysis/secrets_aws.txt"
            ((SCORE+=40))
        fi

        GENERIC_SECRETS=$(grep -E "(SECRET|TOKEN|API_KEY|PASSWORD|PASSWD|PRIVATE_KEY)=['\"]?[A-Za-z0-9+/]{8,}" "$STR" 2>/dev/null || true)
        if [[ -n "$GENERIC_SECRETS" ]]; then
            warn "Secretos genéricos detectados (SECRET/TOKEN/API_KEY)"
            echo "$GENERIC_SECRETS" > "$WD/analysis/secrets_generic.txt"
            ((SCORE+=30))
        fi

        {
        grep -q  "BEGIN CERTIFICATE"    "$STR" && { warn "Certificados embebidos";      ((SCORE+=25)); } || true
        grep -iq "key\|token\|secret"   "$STR" && { warn "Keys / tokens detectados";    ((SCORE+=25)); } || true
        grep -E  "https?://"            "$STR" &>/dev/null && { warn "Endpoints HTTP/S";((SCORE+=10)); } || true
        grep -iq "password\|passwd\|pwd" "$STR" && { warn "Strings de contraseña";      ((SCORE+=15)); } || true
        grep -iq "wifi\|ssid"           "$STR" && { log  "Indicadores WiFi";            ((SCORE+=5));  } || true
        grep -iq "mqtt\|amqp"           "$STR" && { warn "Brokers IoT detectados";      ((SCORE+=10)); } || true
        grep -iq "private\|priv_key"    "$STR" && { warn "Clave privada posible";       ((SCORE+=20)); } || true
        } || true

        echo "$SCORE" > "$WD/analysis/score.txt"
        ok "Score de riesgo: $SCORE"
    fi

    # ── RIESGO ─────────────────────────────────────────────────────────────
    if   (( SCORE >= 80 )); then RISK="CRITICO"
    elif (( SCORE >= 50 )); then RISK="ALTO"
    elif (( SCORE >= 25 )); then RISK="MEDIO"
    else                         RISK="BAJO"; fi

    ok "Riesgo final: $RISK"
fi

# ── REPORTE JSON ───────────────────────────────────────────────────────────
if [[ "$FORMAT" == "json" || "$FORMAT" == "both" || "$FORMAT" == "txt" ]]; then

    cat > "$WD/report/report.json" <<EOF
{
  "chip":    "$CHIP",
  "score":   ${SCORE:-0},
  "risk":    "$RISK",
  "mode":    "$MODE",
  "tag":     "$TAG",
  "note":    "$NOTE",
  "port":    "$PORT",
  "date":    "$(date -Iseconds)"
}
EOF

fi

# ── REPORTE TXT ────────────────────────────────────────────────────────────
if [[ "$FORMAT" == "txt" || "$FORMAT" == "both" ]]; then

    cat > "$WD/report/report.txt" <<EOF
=====================================
 DevSecurityMX · MCU Audit Report
=====================================
Fecha:    $(date)
Chip:     $CHIP
Puerto:   $PORT
Modo:     $MODE
Tag:      ${TAG:-—}
Nota:     ${NOTE:-—}

Score:    ${SCORE:-0} / 80
Riesgo:   $RISK

Artefactos:
  Firmware dump  → $WD/dump/
  Strings        → $WD/analysis/strings.txt
  Forensics      → $WD/forensics/
  Logs           → $LOG
=====================================
EOF

fi

ok "Reportes generados (formato: $FORMAT)"

# ── GHIDRA ─────────────────────────────────────────────────────────────────
if [[ "$MODE" == "full" ]] && ! $NO_GHIDRA; then
    if command -v ghidraRun &>/dev/null && [[ -f "$APP" ]]; then
        log "Lanzando Ghidra headless (background)..."
        ghidraRun "$WD/ghidra_proj" \
            -import "$APP" \
            -overwrite \
            -analysisTimeoutPerFile 60 \
            >"$WD/logs/ghidra.log" 2>&1 &
        ok "Ghidra iniciado (PID $!)"
    else
        warn "Ghidra no disponible o app.bin no encontrado"
    fi
fi

# ── FIN ────────────────────────────────────────────────────────────────────
$QUIET || {
echo ""
echo -e " ${G}✔${N} Proceso completado"
echo -e " ${D}Workspace:${N} $WD"
echo ""
}