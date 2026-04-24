#!/usr/bin/env python3
"""devsec_esptool.py — Wrapper de esptool con reintentos por baud rate."""

import subprocess
import sys

BAUDS = [921600, 460800, 230400, 115200]

def log(msg: str) -> None:
    print(f"[esptool] {msg}", flush=True)

def dump(port: str, size: str, output: str) -> int:
    for baud in BAUDS:
        log(f"Intentando baud {baud}...")
        result = subprocess.run(
            ["esptool.py", "--port", port, "--baud", str(baud),
             "read_flash", "0x00000", size, output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode == 0:
            log(f"Dump exitoso a {baud} baud")
            return 0
        log(f"Fallo ({baud}): {result.stderr.decode(errors='ignore').strip()}")

    log("Error: dump fallido en todos los baud rates")
    return 1

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Uso: devsec_esptool.py <port> <size> <output>")
        sys.exit(1)
    sys.exit(dump(sys.argv[1], sys.argv[2], sys.argv[3]))