#!/system/bin/sh
exec >> /data/adb/modules/sys_optimizer_webui/logs/service.log 2>&1
echo "$(date) service.sh started, APATCH=$APATCH"
MODDIR=${0%/*}
. $MODDIR/common/functions.sh
MODPATH=$MODDIR

restore_from_backup() {
    local BACKUP_DIR="/data/local/tmp/sysopt_backup"
    [ ! -d "$BACKUP_DIR" ] && return
    log_info "检测到备份目录，正在恢复配置..."
    [ -f "$BACKUP_DIR/common/config.conf" ] && {
        cp "$BACKUP_DIR/common/config.conf" "$MODDIR/common/config.conf"
        log_info "  ✓ 已恢复 config.conf"
    }
    for f in .clean_count .last_clean .last_fstrim .last_data_clean .last_custom_clean .service.uptime .service.start_time; do
        [ -f "$BACKUP_DIR/$f" ] && {
            cp "$BACKUP_DIR/$f" "$MODDIR/"
            log_info "  ✓ 已恢复 $f"
        }
    done
    rm -rf "$BACKUP_DIR"
    log_info "备份恢复完成，已清理临时目录 (日志未恢复)"
}
restore_from_backup

ROOT_TYPE=$(get_root_type)
log_info "service.sh started, root=$ROOT_TYPE"
[ "$ROOT_TYPE" = "kernelsu" ] || [ "$ROOT_TYPE" = "apatch" ] && set_selinux_context "$MODDIR"

case $ROOT_TYPE in
    magisk|alpha|delta|kitsune)
        command -v resetprop >/dev/null 2>&1 && resetprop sys.sysopt.initialized 1 || setprop sys.sysopt.initialized 1
        ;;
    *)
        setprop sys.sysopt.initialized 1
        ;;
esac

# ========== F2FS 守护启动（增强版） ==========
f2fs_daemon_enabled=$(get_config enable_f2fs_daemon 0)
log_info "F2FS 守护配置值: enable_f2fs_daemon=$f2fs_daemon_enabled"
if [ "$f2fs_daemon_enabled" = "1" ]; then
    GC_SLEEP=$(get_config f2fs_gc_sleep 60)
    CHECK_INTERVAL=$(get_config f2fs_check_interval 180)
    export GC_SLEEP CHECK_INTERVAL

    if [ -f $MODDIR/.f2fs_daemon.pid ]; then
        oldpid=$(cat $MODDIR/.f2fs_daemon.pid 2>/dev/null)
        if [ -n "$oldpid" ] && ! kill -0 $oldpid 2>/dev/null; then
            log_info "发现残留 PID 文件 (PID $oldpid 已不存在)，清理"
            rm -f $MODDIR/.f2fs_daemon.pid
        fi
    fi

    if [ ! -f $MODDIR/.f2fs_daemon.pid ]; then
        log_info "正在启动 F2FS 垃圾回收守护..."
        if command -v setsid >/dev/null 2>&1; then
            setsid sh $MODDIR/common/f2fs_gc_daemon.sh >/dev/null 2>&1 &
            pid=$!
            log_info "使用 setsid 启动，PID $pid"
        elif command -v nohup >/dev/null 2>&1; then
            nohup sh $MODDIR/common/f2fs_gc_daemon.sh >/dev/null 2>&1 &
            pid=$!
            log_info "使用 nohup 启动，PID $pid"
        else
            log_err "未找到 setsid 或 nohup，无法启动 F2FS 守护"
            sh $MODDIR/common/f2fs_gc_daemon.sh >/dev/null 2>&1 &
            pid=$!
            log_info "直接后台启动，PID $pid"
        fi
        echo $pid > $MODDIR/.f2fs_daemon.pid
        log_info "F2FS 垃圾回收守护已启动，PID $pid"
    else
        log_info "F2FS 垃圾回收守护已在运行 (PID $(cat $MODDIR/.f2fs_daemon.pid))"
    fi
else
    log_info "F2FS 守护未启用 (配置值为 $f2fs_daemon_enabled)"
fi

# ========== 通用函数 ==========
check_storage_usage() {
    local warn=$(get_config storage_warning 85)
    local crit=$(get_config storage_critical 95)
    local usage=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$usage" -ge "$crit" ]; then
        send_notify "⚠️ 存储严重不足" "已使用 ${usage}%，请立即清理" "storage"
    elif [ "$usage" -ge "$warn" ]; then
        send_notify "⚠️ 存储空间警告" "已使用 ${usage}%，建议清理" "storage"
    fi
}
clean_old_logs() {
    local days=$(get_config log_retention_days 7)
    find $MODDIR/logs -name "*.log" -type f -mtime +$days -delete 2>/dev/null
    log_debug "已清理超过 ${days} 天的日志"
}

echo $$ > $MODDIR/.service.parent.pid

while true; do
    if [ -f $MODDIR/.service.pid ]; then
        oldpid=$(cat $MODDIR/.service.pid 2>/dev/null)
        if [ -n "$oldpid" ] && kill -0 $oldpid 2>/dev/null; then
            kill -9 $oldpid 2>/dev/null
            wait $oldpid 2>/dev/null
        fi
    fi
    rm -f $MODDIR/.service.pid $MODDIR/.service.pid.bak $MODDIR/.heartbeat

    (
        echo $$ > $MODDIR/.service.pid
        cp $MODDIR/.service.pid $MODDIR/.service.pid.bak 2>/dev/null
        echo $(date +%s) > $MODDIR/.service.start_time
        echo $(date +%s) > $MODDIR/.heartbeat
        log_info "主循环子进程启动 pid $$"
        trap 'rm -f $MODDIR/.service.pid $MODDIR/.service.pid.bak' EXIT

        until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
        log_info "boot completed, 等待系统服务稳定..."
        sleep 30  # 额外等待系统服务完全初始化

        # 在系统完全启动后恢复白名单
        delay=$(get_config whitelist_restore_delay 60)
        log_info "等待 ${delay} 秒后恢复白名单..."
        sleep $delay
        restore_whitelist
        # 强制移除用户曾经移除的应用
        restore_removed_whitelist

        # 启动一个循环，持续一段时间强制移除removed列表中的应用（防止系统后续添加）
        (
            for i in 1 2 3 4 5; do
                sleep 60
                restore_removed_whitelist
            done
        ) &

        [ -f $MODDIR/.loop_detected ] && {
            log_info "loop detected, delay 120s"
            sleep 120
            rm $MODDIR/.loop_detected
        }

        [ ! -f $MODDIR/.clean_count ] && echo 0 > $MODDIR/.clean_count
        [ ! -f $MODDIR/.last_fstrim ] && echo 0 > $MODDIR/.last_fstrim
        [ ! -f $MODDIR/.last_data_clean ] && echo "1970-01-01 00:00:00" > $MODDIR/.last_data_clean
        touch $MODDIR/.last_clean

        ( sleep 300; perform_dex2oat_optimization; touch $MODDIR/.dex2oat_first_done ) &

        last_history=0
        history_interval=$(get_config battery_history_interval 600)
        last_storage_check=0
        last_log_clean=0
        heartbeat_file="$MODDIR/.heartbeat"

        while true; do
            now=$(date +%s)
            echo $now > $MODDIR/.service.uptime
            echo $now > "$heartbeat_file"

            if [ ! -f "$MODDIR/.service.pid" ] || [ "$(cat $MODDIR/.service.pid 2>/dev/null)" != "$$" ]; then
                echo $$ > $MODDIR/.service.pid
                cp $MODDIR/.service.pid $MODDIR/.service.pid.bak 2>/dev/null
                log_debug "PID 文件已修复"
            fi

            [ -f $MODDIR/.trigger_clean ] && {
                rm $MODDIR/.trigger_clean
                perform_clean
                perform_fstrim_with_frequency
                c=$(($(cat $MODDIR/.clean_count)+1))
                echo $c > $MODDIR/.clean_count
                date +%Y-%m-%d\ %H:%M:%S > $MODDIR/.last_clean
                log_info "manual clean $c"
                touch $MODDIR/.clean_finished
            }
            [ -f $MODDIR/.trigger_optimize ] && {
                rm $MODDIR/.trigger_optimize
                perform_optimize
                perform_dex2oat_optimization
                log_info "manual optimize"
                touch $MODDIR/.optimize_finished
            }
            [ -f $MODDIR/.trigger_data_clean ] && {
                rm $MODDIR/.trigger_data_clean
                perform_android_data_clean
                log_info "manual data clean"
                touch $MODDIR/.data_clean_finished
            }

            interval=$(get_config clean_interval 14400)
            last_clean=$(stat -c %Y $MODDIR/.last_clean 2>/dev/null || echo 0)
            [ $((now - last_clean)) -ge $interval ] && {
                perform_clean
                perform_fstrim_with_frequency
                c=$(($(cat $MODDIR/.clean_count)+1))
                echo $c > $MODDIR/.clean_count
                date +%Y-%m-%d\ %H:%M:%S > $MODDIR/.last_clean
                log_info "timed clean $c"
            }

            perform_fstrim_with_frequency

            [ "$(get_config android_data_clean 1)" = "1" ] && {
                [ $((now % 3600)) -lt 60 ] && check_custom_clean_times && perform_android_data_clean
                last_data=$(stat -c %Y $MODDIR/.last_data_clean 2>/dev/null || echo 0)
                [ $((now - last_data)) -ge 86400 ] && perform_android_data_clean
            }

            [ $((now % 1800)) -lt 60 ] && perform_background_control

            [ $((now % 3600)) -lt 60 ] && {
                optimize_io_scheduler
                optimize_read_ahead
                optimize_cpu_governor
                optimize_gpu
                optimize_power_save
            }

            [ $((now % 3600)) -lt 60 ] && [ -f $MODDIR/.dex2oat_first_done ] && perform_dex2oat_optimization

            [ $((now % 120)) -lt 10 ] && calculate_smoothness_score

            [ $((now % 300)) -lt 60 ] && {
                ( suppress_processes ) &
                lock_directories
                clean_by_rules
                f2fs_dirty_check
            }

            [ $((now % 300)) -lt 60 ] && {
                if detect_charging; then
                    log_debug "充电检测模式 $(get_config charge_detect_mode 10) 判定为：充电中"
                else
                    log_debug "充电检测模式 $(get_config charge_detect_mode 10) 判定为：未充电"
                fi
            }

            check_low_voltage

            if [ -n "$history_interval" ] && [ "$history_interval" -gt 0 ] 2>/dev/null; then
                if [ $((now - last_history)) -ge $history_interval ]; then
                    mkdir -p "$MODDIR/logs"
                    record_battery_history
                    last_history=$now
                fi
            else
                history_interval=600
                log_info "battery_history_interval 无效，已重置为 600"
            fi

            [ $((now - last_storage_check)) -ge 21600 ] && {
                check_storage_usage
                last_storage_check=$now
            }

            [ $((now - last_log_clean)) -ge 86400 ] && {
                clean_old_logs
                last_log_clean=$now
            }

            last_adblock=$(cat $MODDIR/.last_adblock 2>/dev/null || echo 0)
            interval_adblock=$(get_config adblock_update_interval 86400)
            [ $((now - last_adblock)) -ge $interval_adblock ] && {
                ( adblock_update ) &
                echo $now > $MODDIR/.last_adblock
            }

            sleep 60
        done
    ) &
    CHILD_PID=$!
    echo $CHILD_PID > $MODDIR/.service.last_child
    sleep 5

    while true; do
        real_child_pid=$(pgrep -f "$MODDIR/service.sh" 2>/dev/null | grep -v $$ | head -1)
        if [ -z "$real_child_pid" ]; then
            log_info "子进程已不存在，退出监控"
            break
        fi

        last_heartbeat=$(cat $MODDIR/.heartbeat 2>/dev/null || echo 0)
        now=$(date +%s)
        if [ $((now - last_heartbeat)) -gt 300 ]; then
            log_err "心跳超时 (大于5分钟)，但已配置为不自动杀死，继续监控"
        fi

        sleep 60
    done

    log_info "service child exited, restart in 10s"
    sleep 10
done