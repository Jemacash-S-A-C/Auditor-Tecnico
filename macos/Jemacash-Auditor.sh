#!/usr/bin/env bash
# Jemacash Auditor — macOS
# Recolecta información de hardware y la envía a la plataforma Jemacash.
# Se autoeliminará tras la ejecución.

SENTINEL="###JEMACASH_CONFIG###"
SELF="${BASH_SOURCE[0]:-$0}"
DOWNLOADS_DIR="$HOME/Downloads"

# ── Notificaciones ────────────────────────────────────────────────────────────

notify_success() {
  osascript -e 'display dialog "Auditoría completada exitosamente.\n\nSu dispositivo ha sido verificado y los datos enviados a Jemacash. Puede continuar con el registro de su garantía en la plataforma." with title "Jemacash Auditor" buttons {"OK"} default button "OK" with icon note' 2>/dev/null \
  || echo "[OK] Jemacash Auditor: Auditoría completada exitosamente."
}

notify_error() {
  local msg="$1"
  osascript -e "display dialog \"Error al completar la auditoría: ${msg}\n\nIntente ejecutar el auditor nuevamente. Si el problema persiste, contacte a soporte de Jemacash.\" with title \"Jemacash Auditor - Error\" buttons {\"OK\"} default button \"OK\" with icon stop" 2>/dev/null \
  || echo "[ERROR] Jemacash Auditor: ${msg}"
}

# ── Autoeliminación ───────────────────────────────────────────────────────────

remove_self() {
  local path="$1"
  (sleep 1 && rm -f "$path") &
}

# ── Parseo de JSON ────────────────────────────────────────────────────────────

parse_json_field() {
  local json="$1" field="$2"
  python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('$field',''))" 2>/dev/null <<< "$json" || true
}

# ── Carga de configuración ────────────────────────────────────────────────────

API_URL=""
GUARANTEE_ID=""
ACCESS_TOKEN=""

load_from_json() {
  local json="$1"
  [ -z "$json" ] && return
  [ -z "$API_URL" ]      && API_URL=$(parse_json_field "$json" "ApiUrl")
  [ -z "$GUARANTEE_ID" ] && GUARANTEE_ID=$(parse_json_field "$json" "GuaranteeId")
  [ -z "$ACCESS_TOKEN" ] && ACCESS_TOKEN=$(parse_json_field "$json" "AccessToken")
}

load_from_file() {
  local path="$1"
  [ -f "$path" ] || return 0
  load_from_json "$(cat "$path")"
}

load_from_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  while IFS= read -r -d '' file; do
    { [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; } || return 0
    load_from_file "$file"
  done < <(find "$dir" -maxdepth 1 -name "Jemacash-Auditor.config*.json" -print0 2>/dev/null)
}

# Prioridad 1: config embebida al final de este script (después del sentinel)
EMBEDDED_LINE=$(grep -a "^${SENTINEL}" "$SELF" 2>/dev/null | tail -1 || true)
if [ -n "$EMBEDDED_LINE" ]; then
  load_from_json "${EMBEDDED_LINE#"${SENTINEL}"}"
fi

# Prioridad 2: archivo config junto al script
if [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
  load_from_file "$(dirname "$SELF")/Jemacash-Auditor.config.json"
fi

# Prioridad 3: archivo config en Descargas
if [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
  load_from_file "${DOWNLOADS_DIR}/Jemacash-Auditor.config.json"
fi

# Prioridad 4: cualquier config en el mismo directorio o Descargas
if [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
  load_from_dir "$(dirname "$SELF")"
fi
if [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
  load_from_dir "${DOWNLOADS_DIR}"
fi

if [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
  notify_error "No se encontró la configuración necesaria. Descargue el auditor nuevamente desde la plataforma Jemacash."
  exit 1
fi

# ── Recolección de hardware ───────────────────────────────────────────────────

# Número de serie
SERIAL=$(system_profiler SPHardwareDataType 2>/dev/null \
  | awk -F': ' '/Serial Number/{gsub(/[[:space:]]/, "", $2); print $2}' \
  || true)

# Marca y modelo
BRAND="Apple"
MODEL_NAME=$(system_profiler SPHardwareDataType 2>/dev/null \
  | awk -F': ' '/Model Name/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' \
  | head -1 || true)
[ -z "$MODEL_NAME" ] && MODEL_NAME="Mac"

MODEL_ID=$(system_profiler SPHardwareDataType 2>/dev/null \
  | awk -F': ' '/Model Identifier/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' \
  | head -1 || true)

# CPU: Apple Silicon usa "Chip", Intel usa brand_string o "Processor Name"
CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null \
  || system_profiler SPHardwareDataType 2>/dev/null \
     | awk -F': ' '/Chip/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' \
  || system_profiler SPHardwareDataType 2>/dev/null \
     | awk -F': ' '/Processor Name/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' \
  || true)
[ -z "$CPU" ] && CPU="Apple Silicon"

# RAM
RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
RAM_GB=$(echo "$RAM_BYTES" | awk '{print int($1/1073741824)}')
[ "$RAM_GB" = "0" ] && RAM_GB="unknown"

# Almacenamiento (disco de arranque)
DISK_GB=$(diskutil info / 2>/dev/null \
  | grep "Disk Size" \
  | grep -oE '[0-9]+\.[0-9]+ GB|[0-9]+ GB' \
  | head -1 \
  | awk '{print int($1)}' \
  || df -k / 2>/dev/null | awk 'NR==2{print int($2/1024/1024)}' \
  || true)
[ -z "$DISK_GB" ] || [ "$DISK_GB" = "0" ] && DISK_GB="unknown"

# GPU
GPU=$(system_profiler SPDisplaysDataType 2>/dev/null \
  | grep "Chipset Model:" \
  | head -1 \
  | awk -F': ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' \
  || true)
[ -z "$GPU" ] && GPU="Integrated"

# Sistema operativo
OS_NAME=$(sw_vers -productName 2>/dev/null || echo "macOS")
OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "")
OS_FULL="${OS_NAME} ${OS_VERSION}"

# Año de fabricación (aproximado por año del modelo o año actual)
MANUFACTURE_YEAR=$(system_profiler SPHardwareDataType 2>/dev/null \
  | grep "Model Identifier" \
  | grep -oE '[0-9]{4}' \
  | tail -1 \
  || date +%Y)
[ -z "$MANUFACTURE_YEAR" ] && MANUFACTURE_YEAR=$(date +%Y)

# ── Construcción del payload ──────────────────────────────────────────────────

PAYLOAD=$(python3 -c "
import json, sys
serial, brand, model, year, cpu, ram_gb, disk_gb, model_id, gpu, os_full, os_ver = sys.argv[1:]
data = {
    'serial_number':    serial,
    'brand':            brand,
    'model':            model,
    'manufacture_year': year,
    'specs': {
        'processor':            cpu,
        'cpu_name':             cpu,
        'ram':                  ram_gb + ' GB',
        'total_ram_gb':         ram_gb,
        'storage':              disk_gb + ' GB',
        'primary_disk_size_gb': disk_gb,
        'primary_disk':         model_id,
        'gpu_name':             gpu,
        'motherboard':          model_id,
        'os_name':              os_full,
        'os_version':           os_ver,
    }
}
print(json.dumps(data))
" -- \
  "$SERIAL" "$BRAND" "$MODEL_NAME" "$MANUFACTURE_YEAR" \
  "$CPU" "$RAM_GB" "$DISK_GB" "$MODEL_ID" "$GPU" \
  "$OS_FULL" "$OS_VERSION" \
  2>/dev/null)

if [ -z "$PAYLOAD" ]; then
  notify_error "No se pudo construir el reporte de hardware. Asegúrese de que Python 3 esté disponible."
  remove_self "$SELF"
  exit 1
fi

# ── Envío al backend ──────────────────────────────────────────────────────────

BASE="${API_URL%/}"
URI1="${BASE}/guarantees/${GUARANTEE_ID}/audit-report"
URI2="${BASE}/api/guarantees/${GUARANTEE_ID}/audit-report"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$URI1" 2>/dev/null || echo "0")

if [ "$HTTP_STATUS" = "404" ] || [ "$HTTP_STATUS" = "405" ] || [ "$HTTP_STATUS" = "0" ]; then
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$URI2" 2>/dev/null || echo "0")
fi

# ── Resultado ─────────────────────────────────────────────────────────────────

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ] 2>/dev/null; then
  notify_success
else
  notify_error "Error HTTP ${HTTP_STATUS} al enviar los datos del dispositivo."
fi

remove_self "$SELF"
