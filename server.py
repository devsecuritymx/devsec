from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
import os, json, re

app = FastAPI(title="DevSecurityMX", version="1.0")

BASE_DIR = "devsec-out"
WEB_DIR  = "web"

app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")

# ── HELPERS ────────────────────────────────────────────────────────────────

def scan_path(scan_id: str) -> str:
    # Previene path traversal
    safe = re.sub(r"[^a-zA-Z0-9_\-]", "", scan_id)
    if safe != scan_id:
        raise HTTPException(400, "ID de scan inválido")
    return os.path.join(BASE_DIR, safe)


def parse_partitions(strings_path: str) -> list:
    if not os.path.exists(strings_path):
        return []
    with open(strings_path, errors="ignore") as f:
        data = f.read()
    matches = re.findall(
        r"(factory|ota_\d|nvs|phy_init)\s+0x([0-9a-fA-F]+)\s+0x([0-9a-fA-F]+)",
        data
    )
    return [{"name": m[0], "offset": m[1], "size": m[2]} for m in matches]


def read_json(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


# ── RUTAS ──────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return FileResponse(os.path.join(WEB_DIR, "index.html"))

@app.get("/help")
def help_docs():
    return FileResponse(os.path.join(WEB_DIR, "help.html"))


@app.get("/scans")
def list_scans():
    if not os.path.exists(BASE_DIR):
        return []
    entries = [
        e for e in os.listdir(BASE_DIR)
        if os.path.isdir(os.path.join(BASE_DIR, e))
    ]
    return sorted(entries, reverse=True)


@app.get("/scan/{scan_id}")
def get_scan(scan_id: str):
    path = scan_path(scan_id)
    if not os.path.isdir(path):
        raise HTTPException(404, "Scan no encontrado")

    report     = read_json(os.path.join(path, "report", "report.json"))
    str_path   = os.path.join(path, "analysis", "strings.txt")
    strings    = ""
    findings   = []
    partitions = []

    if os.path.exists(str_path):
        with open(str_path, errors="ignore") as f:
            content = f.read()

        strings = content[:8000]

        if "BEGIN CERTIFICATE" in content:
            findings.append("Certificados detectados")
        if "key" in content.lower():
            findings.append("Keys / tokens detectados")
        if re.search(r"https?://", content):
            findings.append("Endpoints HTTP/S encontrados")
        if "wifi" in content.lower():
            findings.append("Credenciales WiFi posibles")

        partitions = parse_partitions(str_path)

    return {
        "report":     report,
        "strings":    strings,
        "findings":   findings,
        "partitions": partitions,
    }


@app.get("/search/{scan_id}")
def search_strings(scan_id: str, q: str = ""):
    path = os.path.join(scan_path(scan_id), "analysis", "strings.txt")
    if not os.path.exists(path):
        raise HTTPException(404, "Strings no encontradas")
    if not q:
        return []

    results = []
    q_lower = q.lower()
    with open(path, errors="ignore") as f:
        for line in f:
            if q_lower in line.lower():
                results.append(line.strip())
                if len(results) >= 100:
                    break
    return results