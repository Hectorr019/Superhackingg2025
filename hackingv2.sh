#!/data/data/com.termux/files/usr/bin/bash
# KLK
PORT=9876
ROOT=/sdcard
cd $ROOT
busybox httpd -p $PORT -h $ROOT &
echo "🚀 Servidor HTTP corriendo en puerto $PORT" > /dev/null
