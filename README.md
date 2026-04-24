# DevSecurityMX 🔐

> Herramienta de Red Team para adquisición y análisis de firmware en dispositivos ESP32/ESP8266.

---

## 🚀 Características

- **Firmware dump automático** — multi-baud con fallback automático (115200 → 921600)
- **Análisis de strings y secretos** — detección de AWS keys (`AKIA`), tokens, contraseñas y certificados embebidos
- **Dashboard web interactivo** — visualización de riesgo, findings y particiones en tiempo real
- **Detección de riesgo** — scoring automático con niveles BAJO / MEDIO / ALTO / CRÍTICO
- **Forense del sistema** — captura de `dmesg`, `lsusb` e información del host
- **Integración con Ghidra** — análisis de reversing headless en modo `--full`
- **Pipeline automatizado** — un solo comando de scan a dashboard
- **Multi-distro** — soporta Debian/Ubuntu, Fedora, Arch y macOS

---

## 🔧 Instalación

```bash
git clone https://github.com/DevSecurityMX/devsec
cd devsec
./install.sh
```

### Dependencias

- Python 3.6+
- esptool, fastapi, uvicorn (instaladas automáticamente)
- binutils (strings, sha256sum), file, xxd
- Git (para clonar ghidra-xtensa)
- Ghidra (opcional, para reversing avanzado)

### Archivos incluidos

- `devsec.sh` — Script principal
- `esp.sh` — Core de adquisición y análisis
- `devsec_esptool.py` — Wrapper de esptool con reintentos
- `server.py` — API web para dashboard
- `install.sh` — Instalador multi-distro
- `requirements.txt` — Dependencias Python
- `.gitignore` — Exclusiones para Git
- `web/` — Archivos estáticos del dashboard

---

## 📋 Preparación para Git

Antes de subir a Git, asegúrate de:

1. **Eliminar archivos no deseados:**
   - `__pycache__/` (borrado)
   - `ghidra-xtensa/` (borrado, se clona automáticamente)
   - `devsec-out/` (salida de scans, excluida en .gitignore)

2. **Archivos a subir:**
   - Tu core: `devsec.sh`, `esp.sh`, `devsec_esptool.py`, `server.py`, `install.sh`, `README.md`
   - `web/`, `requirements.txt`, `.gitignore`

3. **.gitignore incluye:**
   - `__pycache__/`, `*.pyc`
   - `*.log`
   - `devsec-out/`, `*.bin`, `*.dump`
   - `ghidra-xtensa/`
   - `.env`, `Thumbs.db`, `DS_Store`

El script `esp.sh` clona automáticamente `ghidra-xtensa` si no existe.

---

## ⚡ Uso rápido

```bash
# Scan completo con etiqueta
./devsec.sh scan --port /dev/ttyUSB0 --full --tag produccion

# Scan rápido sin Ghidra, reporte JSON
./devsec.sh scan --fast --no-ghidra --format json

# Scan + abrir dashboard automáticamente al terminar
./devsec.sh scan --port /dev/ttyUSB0 --auto-web

# Solo forensics
./devsec.sh scan --forensic

# Ver último reporte
./devsec.sh analyze

# Dashboard web en puerto personalizado
./devsec.sh web --port-web 9090 --open

# Listar scans y limpiar los de más de 7 días
./devsec.sh list
./devsec.sh clean --days 7
```

---

## 🧩 Pipeline

```
[1] Acquisition   → Dump de flash via esptool (multi-baud)
[2] Validation    → file(1) + sanity check 0xFF
[3] Processing    → Extracción de app partition, hashes SHA256
[4] Forensics     → dmesg, lsusb, info del sistema
[5] Analysis      → Strings, secretos reales (AKIA/TOKEN), score de riesgo
[6] Reporting     → JSON + TXT estructurado con tags y notas
[7] Visualization → Dashboard web interactivo
[8] Reversing     → Ghidra headless (modo --full)
```

---

## 📊 Detección de secretos

El pipeline detecta automáticamente:

| Patrón | Descripción | Peso |
|--------|-------------|------|
| `AKIA[0-9A-Z]{16}` | AWS Access Key ID | +40 |
| `SECRET=`, `TOKEN=`, `API_KEY=` | Secretos genéricos | +30 |
| `BEGIN CERTIFICATE` | Certificados embebidos | +25 |
| `key\|token\|secret` | Keys genéricas | +25 |
| `password\|passwd` | Strings de contraseña | +15 |
| `private\|priv_key` | Claves privadas | +20 |
| `mqtt\|amqp` | Brokers IoT | +10 |
| `https?://` | Endpoints HTTP/S | +10 |
| `wifi\|ssid` | Credenciales WiFi | +5 |

---

## 🗂️ Estructura de salida

```
devsec-out/
└── 2026-04-23_12-00-00/
    ├── dump/
    │   ├── firmware.bin      # Dump completo
    │   └── app.bin           # Partición app (offset 0x10000)
    ├── analysis/
    │   ├── strings.txt       # Strings extraídas
    │   ├── secrets_aws.txt   # AWS keys detectadas
    │   └── secrets_generic.txt
    ├── forensics/
    │   ├── system.txt
    │   ├── usb.txt
    │   ├── dmesg.txt
    │   ├── dump.sha256
    │   └── app.sha256
    ├── report/
    │   ├── report.json
    │   └── report.txt
    └── logs/
        └── run.log
```

---

## 🧠 Filosofía

Automatizar completamente el proceso de adquisición y análisis de firmware embebido —  
desde el dump hasta el dashboard — para que el operador pueda enfocarse en los hallazgos,  
no en la infraestructura.

---

## ⚖️ Licencia

Para uso autorizado en auditorías de seguridad y entornos propios.  
No usar en dispositivos sin autorización explícita del propietario.
