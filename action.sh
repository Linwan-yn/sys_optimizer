#!/system/bin/sh
MODPATH=${0%/*}
. $MODPATH/common/functions.sh

echo "================================"
echo "智能系统优化模块 - 一键维护"
echo "================================"

echo "[1/5] 当前状态: $(check_service_status)"
echo "清理次数: $(cat $MODPATH/.clean_count 2>/dev/null || echo 0)"
echo "上次清理: $(cat $MODPATH/.last_clean 2>/dev/null || echo '从未')"

echo "[2/5] 触发缓存清理..."
touch $MODPATH/.trigger_clean
echo "任务已提交"

echo "[3/5] 触发 Android/data 清理..."
touch $MODPATH/.trigger_data_clean
echo "任务已提交"

echo "[4/5] 触发性能优化..."
touch $MODPATH/.trigger_optimize
echo "任务已提交"

echo "[5/5] 等待5秒查看最新日志..."
sleep 5
echo "最近10条日志:"
tail -10 $MODPATH/logs/service.log

echo "================================"
echo "一键维护完成，请查看日志确认效果"
exit 0