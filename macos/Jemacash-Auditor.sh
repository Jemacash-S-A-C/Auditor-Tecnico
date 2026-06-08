#!/usr/bin/env bash
# Jemacash Auditor — macOS
# Recolecta información de hardware y la envía a la plataforma Jemacash.
# Solo usa herramientas nativas de macOS: bash, awk, sed, curl, osascript.
# Se autoeliminará tras la ejecución.

SENTINEL="###JEMACASH_CONFIG###"
SELF="${BASH_SOURCE[0]:-$0}"
DOWNLOADS_DIR="$HOME/Downloads"

# ── Notificaciones (osascript nativo, sin dependencias) ───────────────────────

notify_success() {
  osascript << 'AS'
display dialog "Auditoría completada exitosamente." & return & return & \
  "Su dispositivo ha sido verificado y los datos enviados a Jemacash. Puede continuar con el registro de su garantía en la plataforma." \
  with title "Jemacash Auditor" buttons {"OK"} default button "OK" with icon note
AS
  true
}

notify_error() {
  osascript - "$1" << 'AS'
on run argv
  display dialog "Error al completar la auditoría: " & (item 1 of argv) & return & return & \
    "Intente ejecutar el auditor nuevamente. Si el problema persiste, contacte a soporte de Jemacash." \
    with title "Jemacash Auditor - Error" buttons {"OK"} default button "OK" with icon stop
end run
AS
  true
}

# ── Autoeliminación ───────────────────────────────────────────────────────────

remove_self() {
  (sleep 1 && rm -f "$SELF") &
}

# ── Parseo de JSON con sed (sin Python ni jq) ─────────────────────────────────
# Funciona con JSON plano de una línea (como el que genera JSON.stringify)

json_get() {
  # Extrae el valor de un campo string: json_get '{"Key":"Val"}' Key  →  Val
  printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# ── Escape de valores para JSON (sin Python) ──────────────────────────────────

json_esc() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ── Carga de configuración ────────────────────────────────────────────────────

API_URL=""
GUARANTEE_ID=""
ACCESS_TOKEN=""

load_from_json() {
  local j="$1"
  [ -z "$j" ] && return
  [ -z "$API_URL" ]      && API_URL=$(json_get "$j" "ApiUrl")
  [ -z "$GUARANTEE_ID" ] && GUARANTEE_ID=$(json_get "$j" "GuaranteeId")
  [ -z "$ACCESS_TOKEN" ] && ACCESS_TOKEN=$(json_get "$j" "AccessToken")
}

load_from_file() {
  [ -f "$1" ] || return 0
  load_from_json "$(cat "$1")"
}

load_from_dir() {
  [ -d "$1" ] || return 0
  while IFS= read -r -d '' f; do
    { [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; } || return 0
    load_from_file "$f"
  done < <(find "$1" -maxdepth 1 -name "Jemacash-Auditor.config*.json" -print0 2>/dev/null)
}

# Prioridad 1 — config embebida al final de este archivo (línea sentinel)
EMBEDDED=$(grep "^${SENTINEL}" "$SELF" 2>/dev/null | tail -1 || true)
[ -n "$EMBEDDED" ] && load_from_json "${EMBEDDED#"${SENTINEL}"}"

# Prioridad 2 — config junto al script
{ [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; } && \
  load_from_file "$(dirname "$SELF")/Jemacash-Auditor.config.json"

# Prioridad 3 — config en Descargas
{ [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; } && \
  load_from_file "${DOWNLOADS_DIR}/Jemacash-Auditor.config.json"

# Prioridad 4 — cualquier config*.json en directorio o Descargas
{ [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; } && \
  load_from_dir "$(dirname "$SELF")"
{ [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; } && \
  load_from_dir "${DOWNLOADS_DIR}"

if [ -z "$API_URL" ] || [ -z "$GUARANTEE_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
  notify_error "No se encontró la configuración. Descargue el auditor nuevamente desde Jemacash."
  remove_self
  exit 1
fi

# ── Recolección de hardware (solo herramientas nativas de macOS) ──────────────

HWINFO=$(system_profiler SPHardwareDataType 2>/dev/null || true)
DISPINFO=$(system_profiler SPDisplaysDataType 2>/dev/null || true)

# Número de serie
SERIAL=$(printf '%s' "$HWINFO" | awk -F': ' \
  '/Serial Number/{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}')

# Modelo
MODEL_NAME=$(printf '%s' "$HWINFO" | awk -F': ' \
  '/Model Name/{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}')
[ -z "$MODEL_NAME" ] && MODEL_NAME="Mac"

MODEL_ID=$(printf '%s' "$HWINFO" | awk -F': ' \
  '/Model Identifier/{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}')

BRAND="Apple"

# CPU — Apple Silicon usa "Chip:", Intel usa sysctl o "Processor Name:"
CPU=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
if [ -z "$CPU" ]; then
  CPU=$(printf '%s' "$HWINFO" | awk -F': ' \
    '/Chip:/{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}')
fi
if [ -z "$CPU" ]; then
  CPU=$(printf '%s' "$HWINFO" | awk -F': ' \
    '/Processor Name/{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2; exit}')
fi
[ -z "$CPU" ] && CPU="Apple Silicon"

# RAM — sysctl hw.memsize en bytes → GB con awk
RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
RAM_GB=$(awk "BEGIN{x=${RAM_BYTES}+0; print (x>0) ? int(x/1073741824) : 0}")
[ "$RAM_GB" = "0" ] && RAM_GB="unknown"

# Almacenamiento — diskutil info del disco de arranque, fallback df
DISK_GB=$(diskutil info / 2>/dev/null \
  | grep -i "Disk Size" \
  | grep -oE '[0-9]+\.[0-9]+[[:space:]]*GB|[0-9]+[[:space:]]*GB' \
  | head -1 \
  | awk '{print int($1)}')

if [ -z "$DISK_GB" ] || [ "$DISK_GB" = "0" ]; then
  DISK_GB=$(diskutil info disk0 2>/dev/null \
    | grep -i "Disk Size" \
    | grep -oE '[0-9]+\.[0-9]+[[:space:]]*GB|[0-9]+[[:space:]]*GB' \
    | head -1 \
    | awk '{print int($1)}')
fi

if [ -z "$DISK_GB" ] || [ "$DISK_GB" = "0" ]; then
  DISK_GB=$(df -k / 2>/dev/null | awk 'NR==2{print int($2/1024/1024)}')
fi
[ -z "$DISK_GB" ] && DISK_GB="unknown"

# GPU
GPU=$(printf '%s' "$DISPINFO" | grep "Chipset Model:" | head -1 \
  | awk -F': ' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}')
[ -z "$GPU" ] && GPU="Integrated"

# Sistema operativo
OS_NAME=$(sw_vers -productName 2>/dev/null || echo "macOS")
OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "")
OS_FULL="${OS_NAME} ${OS_VERSION}"

# Año de fabricación (del Model Identifier o año actual)
MANUFACTURE_YEAR=$(printf '%s' "$HWINFO" \
  | grep "Model Identifier" \
  | grep -oE '[0-9]{4}' \
  | tail -1)
[ -z "$MANUFACTURE_YEAR" ] && MANUFACTURE_YEAR=$(date +%Y)

# ── Construcción del payload JSON (puro bash + awk, sin Python ni jq) ─────────

PAYLOAD="{\"serial_number\":\"$(json_esc "$SERIAL")\",\
\"brand\":\"$(json_esc "$BRAND")\",\
\"model\":\"$(json_esc "$MODEL_NAME")\",\
\"manufacture_year\":\"$(json_esc "$MANUFACTURE_YEAR")\",\
\"specs\":{\
\"processor\":\"$(json_esc "$CPU")\",\
\"cpu_name\":\"$(json_esc "$CPU")\",\
\"ram\":\"$(json_esc "$RAM_GB") GB\",\
\"total_ram_gb\":\"$(json_esc "$RAM_GB")\",\
\"storage\":\"$(json_esc "$DISK_GB") GB\",\
\"primary_disk_size_gb\":\"$(json_esc "$DISK_GB")\",\
\"primary_disk\":\"$(json_esc "$MODEL_ID")\",\
\"gpu_name\":\"$(json_esc "$GPU")\",\
\"motherboard\":\"$(json_esc "$MODEL_ID")\",\
\"os_name\":\"$(json_esc "$OS_FULL")\",\
\"os_version\":\"$(json_esc "$OS_VERSION")\"}\
}"

# ── Envío al backend ──────────────────────────────────────────────────────────

BASE="${API_URL%/}"
URI1="${BASE}/guarantees/${GUARANTEE_ID}/audit-report"
URI2="${BASE}/api/guarantees/${GUARANTEE_ID}/audit-report"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$URI1" 2>/dev/null || echo "0")

if [ "$STATUS" = "404" ] || [ "$STATUS" = "405" ] || [ "$STATUS" = "000" ] || [ "$STATUS" = "0" ]; then
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$URI2" 2>/dev/null || echo "0")
fi

# ── Resultado ─────────────────────────────────────────────────────────────────

if [ "$STATUS" -ge 200 ] && [ "$STATUS" -lt 300 ] 2>/dev/null; then
  notify_success
else
  notify_error "Error HTTP ${STATUS} al enviar los datos del dispositivo."
fi

remove_self
