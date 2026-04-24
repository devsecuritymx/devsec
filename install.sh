#!/bin/bash
# install.sh — DevSecurityMX · Instalador multi-distro v2.0
# Uso: ./install.sh

set -euo pipefail

G='\033[0;32m' R='\033[0;31m' Y='\033[1;33m' C='\033[0;36m' D='\033[2m' N='\033[0m'
ok()   { echo -e "${G}[✔]${N} $1"; }
warn() { echo -e "${Y}[!]${N} $1"; }
info() { echo -e "${C}[*]${N} $1"; }
die()  { echo -e "${R}[✘]${N} $1"; exit 1; }

echo -e "${C}"
cat <<'EOF'
 ██████╗ ███████╗██╗   ██╗███████╗███████╗ ██████╗
 ██╔══██╗██╔════╝██║   ██║██╔════╝██╔════╝██╔════╝
 ██║  ██║█████╗  ██║   ██║███████╗█████╗  ██║
 ██║  ██║██╔══╝  ╚██╗ ██╔╝╚════██║██╔══╝  ██║  ███╗
 ██████╔╝███████╗ ╚████╔╝ ███████║███████╗╚██████╔╝
 ╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚══════╝ ╚═════╝
EOF
echo -e "${N}"
echo -e " ${D}MCU Firmware Audit Framework — Instalador v2.0${N}\n"

# ── DETECCIÓN DE DISTRO ────────────────────────────────────────────────────
info "Detectando distribución..."
DISTRO=""
if   command -v apt-get &>/dev/null; then DISTRO="debian"
elif command -v dnf     &>/dev/null; then DISTRO="fedora"
elif command -v pacman  &>/dev/null; then DISTRO="arch"
elif command -v brew    &>/dev/null; then DISTRO="macos"
else die "Distribución no soportada. Instala las dependencias manualmente."; fi
ok "Distro detectada: $DISTRO"

# ── DEPENDENCIAS DEL SISTEMA ───────────────────────────────────────────────
info "Instalando dependencias del sistema..."
case "$DISTRO" in
    debian)
        sudo apt-get update -qq
        sudo apt-get install -y python3 python3-pip binutils file lsusb xxd git ;;
    fedora)
        sudo dnf install -y python3 python3-pip binutils file usbutils util-linux git ;;
    arch)
        sudo pacman -Sy --noconfirm python python-pip binutils file usbutils xxd git ;;
    macos)
        brew install python binutils xxd git || true ;;
esac
ok "Dependencias del sistema instaladas"

# ── DEPENDENCIAS PYTHON ────────────────────────────────────────────────────
info "Instalando dependencias Python..."
pip3 install --user -r requirements.txt
ok "Dependencias Python instaladas desde requirements.txt"

# ── GRUPO SERIAL (DETECCIÓN REAL) ─────────────────────────────────────────
info "Configurando acceso al puerto serie..."
SERIAL_GROUP="dialout"

if   getent group dialout &>/dev/null; then SERIAL_GROUP="dialout"
elif getent group uucp    &>/dev/null; then SERIAL_GROUP="uucp"
elif getent group tty     &>/dev/null; then SERIAL_GROUP="tty"
fi

if groups "$USER" | grep -qw "$SERIAL_GROUP"; then
    ok "Usuario ya pertenece al grupo $SERIAL_GROUP"
else
    warn "Agregando $USER al grupo $SERIAL_GROUP..."
    sudo usermod -aG "$SERIAL_GROUP" "$USER"
    warn "Reinicia sesión para que el grupo tome efecto"
fi

# ── PERMISOS EJECUTABLES ───────────────────────────────────────────────────
info "Configurando permisos..."
chmod +x devsec.sh esp.sh
ok "Permisos configurados (devsec.sh, esp.sh)"

# ── SYMLINK GLOBAL (OPCIONAL) ──────────────────────────────────────────────
if [[ "$DISTRO" != "macos" ]]; then
    if [[ -d "$HOME/.local/bin" ]]; then
        ln -sf "$(pwd)/devsec.sh" "$HOME/.local/bin/devsec" 2>/dev/null && \
            ok "Symlink creado: ~/.local/bin/devsec" || \
            warn "No se pudo crear symlink (continúa con ./devsec.sh)"
    fi
fi

# ── VERIFICACIÓN FINAL ─────────────────────────────────────────────────────
echo ""
info "Verificando instalación..."
python3 -c "import esptool; print('esptool OK')"   && ok "esptool importable"
python3 -c "import fastapi; print('fastapi OK')"   && ok "fastapi importable"
python3 -c "import uvicorn; print('uvicorn OK')"   && ok "uvicorn importable"
command -v strings  &>/dev/null && ok "strings (binutils) disponible" || warn "strings no encontrado"
command -v xxd      &>/dev/null && ok "xxd disponible"                || warn "xxd no encontrado"
command -v sha256sum &>/dev/null && ok "sha256sum disponible"         || warn "sha256sum no encontrado"
command -v file     &>/dev/null && ok "file disponible"               || warn "file no encontrado"

echo ""
echo -e " ${G}✔ Instalación completa${N}"
echo -e " ${D}Uso:${N}  ./devsec.sh help"
echo -e " ${D}Scan:${N} ./devsec.sh scan --port /dev/ttyUSB0"
echo ""
