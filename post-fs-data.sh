#!/system/bin/sh
if getprop ro.product.manufacturer|grep -qiE 'OPPO|OnePlus'; then sleep 5; else sleep 1; fi
[ -f /data/adb/magisk/magiskpolicy ] && /data/adb/magisk/magiskpolicy --live "allow magisk * * *" 2>/dev/null

MODDIR=${0%/*}
MODPATH=/data/adb/modules/sys_optimizer_webui
LOGF=$MODPATH/logs/boot.log
mkdir -p $MODPATH/logs $MODPATH/common

. $MODPATH/common/functions.sh

now=$(date +%s); last=$(cat $MODPATH/.last_boot 2>/dev/null || echo 0)
[ $((now-last)) -lt 30 ] && touch $MODPATH/.loop_detected
echo $now > $MODPATH/.last_boot

[ -d /data/adb/modules/sys_optimizer_webui.disabled ] && [ ! -f /data/adb/modules/sys_optimizer_webui.disabled/disable ] && {
    mv /data/adb/modules/sys_optimizer_webui.disabled /data/adb/modules/sys_optimizer_webui 2>/dev/null
    echo "[恢复] 自动启用" >> $LOGF
}

ROOT_TYPE=$(get_root_type)
case $ROOT_TYPE in kernelsu|apatch) set_selinux_context "$MODPATH" ;; esac

if [ -n "$APATCH" ]; then command -v chcon >/dev/null 2>&1 && chcon -R u:object_r:magisk_file:s0 "$MODPATH" 2>/dev/null; fi

chmod 755 $MODDIR/service.sh 2>/dev/null
. $MODPATH/common/functions.sh
check_device_compatibility >/dev/null 2>&1
exit 0