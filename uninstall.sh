#!/system/bin/sh
OUTFD=$2
MODPATH=/data/adb/modules/sys_optimizer_webui
BACKUP=/sdcard/SysOptimizer_Backup_$(date +%Y%m%d_%H%M%S)
ui_print(){ echo -e "ui_print $1\nui_print" >>/proc/self/fd/$OUTFD; }
. $MODPATH/common/functions.sh 2>/dev/null
[ -f $MODPATH/.f2fs_daemon.pid ] && kill -9 $(cat $MODPATH/.f2fs_daemon.pid) 2>/dev/null && rm $MODPATH/.f2fs_daemon.pid
[ -f $MODPATH/.service.pid ] && kill -9 $(cat $MODPATH/.service.pid) 2>/dev/null
mkdir -p $BACKUP
[ -f $MODPATH/common/config.conf ] && cp $MODPATH/common/config.conf $BACKUP/
[ -f $MODPATH/logs/service.log ] && cp $MODPATH/logs/service.log $BACKUP/
[ -f $MODPATH/.clean_count ] && cp $MODPATH/.clean_count $BACKUP/
ui_print "✓ 配置备份 $BACKUP"
rm -rf $MODPATH
ui_print "✓ 已卸载"
exit 0