#!/system/bin/sh
GC_SLEEP=60
INTERVAL=3
CHECK_INTERVAL=180
LOG_FILE="/data/adb/modules/sys_optimizer_webui/logs/f2fs_gc_daemon.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
exec >> "$LOG_FILE" 2>&1
echo "========================================"
echo "F2FS 垃圾回收守护启动于 $(date)"
echo "配置: GC_SLEEP=$GC_SLEEP, INTERVAL=$INTERVAL, CHECK_INTERVAL=$CHECK_INTERVAL"
echo "========================================"
trap_exit() {
    echo ""
    echo "脚本被中断，尝试恢复系统状态..."
    if [ -n "$userdata" ] && [ -d "/sys/fs/f2fs/$userdata" ]; then
        [ -n "$gc_booster" ] && echo "$gc_booster" > "/sys/fs/f2fs/$userdata/gc_booster" 2>/dev/null
        [ -n "$cp_interval" ] && echo "$cp_interval" > "/sys/fs/f2fs/$userdata/cp_interval" 2>/dev/null
        [ -n "$dirty_nats_ratio" ] && echo "$dirty_nats_ratio" > "/sys/fs/f2fs/$userdata/dirty_nats_ratio" 2>/dev/null
        [ -n "$discard_idle_interval" ] && echo "$discard_idle_interval" > "/sys/fs/f2fs/$userdata/discard_idle_interval" 2>/dev/null
        [ -n "$gc_idle" ] && echo "$gc_idle" > "/sys/fs/f2fs/$userdata/gc_idle" 2>/dev/null
        [ -n "$gc_idle_interval" ] && echo "$gc_idle_interval" > "/sys/fs/f2fs/$userdata/gc_idle_interval" 2>/dev/null
        [ -n "$gc_max_sleep_time" ] && echo "$gc_max_sleep_time" > "/sys/fs/f2fs/$userdata/gc_max_sleep_time" 2>/dev/null
        [ -n "$gc_min_sleep_time" ] && echo "$gc_min_sleep_time" > "/sys/fs/f2fs/$userdata/gc_min_sleep_time" 2>/dev/null
        [ -n "$gc_no_gc_sleep_time" ] && echo "$gc_no_gc_sleep_time" > "/sys/fs/f2fs/$userdata/gc_no_gc_sleep_time" 2>/dev/null
        [ -n "$gc_urgent" ] && echo "$gc_urgent" > "/sys/fs/f2fs/$userdata/gc_urgent" 2>/dev/null
        [ -n "$gc_urgent_sleep_time" ] && echo "$gc_urgent_sleep_time" > "/sys/fs/f2fs/$userdata/gc_urgent_sleep_time" 2>/dev/null
        [ -n "$idle_interval" ] && echo "$idle_interval" > "/sys/fs/f2fs/$userdata/idle_interval" 2>/dev/null
        [ -n "$ram_thresh" ] && echo "$ram_thresh" > "/sys/fs/f2fs/$userdata/ram_thresh" 2>/dev/null
        echo "GC 参数已尝试恢复"
    fi
    [ "$res_iostats" = "true" ] && restore_iostats
    [ -n "$restore_se" ] && $restore_se
    [ "$io_max" = "on" ] && io_perf_res
    echo "守护退出，请检查系统状态。如异常请重启手机。"
    exit 1
}
trap trap_exit INT TERM
check_root() {
    PATH="/system/bin:/system/xbin:/vendor/bin:/vendor/xbin:$PATH"
    export PATH
    if [ "$(id -u)" != "0" ]; then
        echo "错误: 需要 root 权限"
        exit 1
    fi
    echo "ROOT 权限正常"
}
enforce_se() {
    echo 1 > /sys/fs/selinux/enforce 2>/dev/null
    setenforce 1 2>/dev/null
}
permissive_se() {
    setenforce 0 2>/dev/null
    echo 0 > /sys/fs/selinux/enforce 2>/dev/null
}
check_selinux() {
    restore_se=""
    if [ "$(getenforce 2>/dev/null)" != "Permissive" ]; then
        restore_se="enforce_se"
        permissive_se
        echo "SELinux 已临时切换到 Permissive"
    fi
}
check_busybox() {
    box='/data/adb/magisk/busybox'
    if [ ! -f "$box" ]; then
        if busybox --help 2>&1 | grep -qi 'inaccessible or not found'; then
            box=''
            local temp
            temp=$("$(magisk --path 2>/dev/null)/.magisk/busybox/busybox" --help 2>&1 | grep -i 'inaccessible or not found')
            if [ -z "$temp" ]; then
                box="$(magisk --path)/.magisk/busybox/busybox"
            fi
        else
            box='busybox'
        fi
    fi
    if [ -z "$box" ]; then
        if command -v mount >/dev/null 2>&1; then
            box=""
            echo "未找到 BusyBox，将使用系统命令"
        else
            echo "错误: 未找到 BusyBox 且系统命令不可用"
            $restore_se
            exit 1
        fi
    else
        echo "BusyBox: $box"
    fi
}
check_filesystem() {
    if ! mount | grep ' /data ' | grep -q ' f2fs '; then
        echo "错误: data 分区不是 F2FS 格式，不支持"
        $restore_se
        exit 1
    fi
    echo "文件系统: F2FS"
}
check_userdata() {
    userdata=$(getprop dev.mnt.blk.data)
    if [ ! -f "/sys/fs/f2fs/$userdata/cp_interval" ]; then
        temp_usd=$(find /sys/fs/f2fs/ -type d -name 'dm*' | head -1)
        userdata="${temp_usd##*/}"
    fi
    if [ ! -f "/sys/fs/f2fs/$userdata/cp_interval" ]; then
        if mount | grep -q ' /cache ' | grep -q 'f2fs'; then
            temp_usd=$(find -L /dev/block/ -iname 'userdata' | head -1)
            temp_ud=$(ls -l "$temp_usd")
            userdata="${temp_ud##*/}"
        else
            temp_usd=$(find /sys/fs/f2fs/ -type d -name 'sda*' | head -1)
            if [ -f "$temp_usd/cp_interval" ]; then
                userdata="${temp_usd##*/}"
            else
                temp_usd=$(find /sys/fs/f2fs/ -type d -name 'mmcblk*' | head -1)
                [ -f "$temp_usd/cp_interval" ] && userdata="${temp_usd##*/}"
            fi
        fi
    fi
    if [ -z "$userdata" ] || [ ! -f "/sys/fs/f2fs/$userdata/cp_interval" ]; then
        echo "错误: 无法定位 data 分区设备号"
        $restore_se
        exit 1
    fi
    echo "data 分区: $userdata"
}
check_iopath() {
    if [ -d "/sys/block/$userdata/queue" ]; then
        iopath="/sys/block/$userdata/queue"
    elif [ -d "/sys/block/$(getprop dev.mnt.blk.data)/queue" ]; then
        iopath="/sys/block/$(getprop dev.mnt.blk.data)/queue"
    elif echo "$userdata" | grep -q 'sda' && [ -d /sys/block/sda/queue ]; then
        iopath="/sys/block/sda/queue"
    elif echo "$userdata" | grep -q 'mmcblk' && [ -d /sys/block/mmcblk0/queue ]; then
        iopath="/sys/block/mmcblk0/queue"
    else
        iopath='null'
    fi
    if [ ! -d "$iopath" ]; then
        iostats=0
        echo "警告: 未找到 IO 路径，部分功能受限"
    else
        iostats=$(cat "$iopath/iostats" 2>/dev/null)
        echo "IO 路径: $iopath, iostats=$iostats"
    fi
}
restore_iostats() {
    local flag="$1"
    if [ "$flag" = "true" ] && [ -d "$iopath" ]; then
        echo 0 > "$iopath/iostats" 2>/dev/null
        echo "已恢复 IO 统计"
    fi
}
backup() {
    if mount | grep ' /data ' | grep -q 'background_gc=off'; then
        bak='res'
        echo "GC 当前禁用，已备份"
    else
        bak=""
        echo "GC 已启用，无需备份"
    fi
}
res() {
    mount -o remount,background_gc=off /data 2>/dev/null
}
enable_gc() {
    sync -j 8
    mount -o remount,discard /data 2>/dev/null
    mount -o remount,background_gc=on /data 2>/dev/null
    sleep 1
    echo "GC 功能已启用"
}
load1() {
    gc_booster=$(cat "/sys/fs/f2fs/$userdata/gc_booster" 2>/dev/null)
    cp_interval=$(cat "/sys/fs/f2fs/$userdata/cp_interval" 2>/dev/null)
    dirty_nats_ratio=$(cat "/sys/fs/f2fs/$userdata/dirty_nats_ratio" 2>/dev/null)
    discard_idle_interval=$(cat "/sys/fs/f2fs/$userdata/discard_idle_interval" 2>/dev/null)
    gc_idle=$(cat "/sys/fs/f2fs/$userdata/gc_idle" 2>/dev/null)
    gc_idle_interval=$(cat "/sys/fs/f2fs/$userdata/gc_idle_interval" 2>/dev/null)
    gc_max_sleep_time=$(cat "/sys/fs/f2fs/$userdata/gc_max_sleep_time" 2>/dev/null)
    gc_min_sleep_time=$(cat "/sys/fs/f2fs/$userdata/gc_min_sleep_time" 2>/dev/null)
    gc_no_gc_sleep_time=$(cat "/sys/fs/f2fs/$userdata/gc_no_gc_sleep_time" 2>/dev/null)
    gc_urgent=$(cat "/sys/fs/f2fs/$userdata/gc_urgent" 2>/dev/null)
    gc_urgent_sleep_time=$(cat "/sys/fs/f2fs/$userdata/gc_urgent_sleep_time" 2>/dev/null)
    idle_interval=$(cat "/sys/fs/f2fs/$userdata/idle_interval" 2>/dev/null)
    ram_thresh=$(cat "/sys/fs/f2fs/$userdata/ram_thresh" 2>/dev/null)
    echo "已读取 GC 参数"
}
err() {
    echo "F2FS 参数 $1 未找到"
    $restore_se
    $bak
    exit 1
}
load2() {
    [ -z "$cp_interval" ] && err cp_interval
    [ -z "$gc_idle" ] && err gc_idle
    [ -z "$gc_min_sleep_time" ] && err gc_min_sleep_time
    [ -z "$gc_max_sleep_time" ] && err gc_max_sleep_time
    [ -z "$idle_interval" ] && err idle_interval
    [ -z "$gc_urgent_sleep_time" ] && err gc_urgent_sleep_time
    [ -z "$gc_urgent" ] && err gc_urgent
    [ -z "$gc_no_gc_sleep_time" ] && err gc_no_gc_sleep_time
    echo "GC 参数验证通过"
}
check_time() {
    if ! echo "$GC_SLEEP" | grep -qE '^[0-9]+$'; then
        GC_SLEEP=60
    fi
    if ! echo "$INTERVAL" | grep -qE '^[0-9]+$'; then
        INTERVAL=3
    fi
}
begin() {
    [ -w "/sys/fs/f2fs/$userdata/gc_booster" ] && echo 1 > "/sys/fs/f2fs/$userdata/gc_booster" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/cp_interval" ] && echo 3 > "/sys/fs/f2fs/$userdata/cp_interval" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/dirty_nats_ratio" ] && echo 1 > "/sys/fs/f2fs/$userdata/dirty_nats_ratio" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/discard_idle_interval" ] && echo 1 > "/sys/fs/f2fs/$userdata/discard_idle_interval" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_idle" ] && echo 2 > "/sys/fs/f2fs/$userdata/gc_idle" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_idle_interval" ] && echo 1 > "/sys/fs/f2fs/$userdata/gc_idle_interval" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_max_sleep_time" ] && echo 2000 > "/sys/fs/f2fs/$userdata/gc_max_sleep_time" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_min_sleep_time" ] && echo 500 > "/sys/fs/f2fs/$userdata/gc_min_sleep_time" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_no_gc_sleep_time" ] && echo 1000 > "/sys/fs/f2fs/$userdata/gc_no_gc_sleep_time" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_urgent" ] && echo 1 > "/sys/fs/f2fs/$userdata/gc_urgent" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_urgent_sleep_time" ] && echo 10 > "/sys/fs/f2fs/$userdata/gc_urgent_sleep_time" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/gc_urgent_high_remaining" ] && echo 1 > "/sys/fs/f2fs/$userdata/gc_urgent_high_remaining" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/idle_interval" ] && echo 1 > "/sys/fs/f2fs/$userdata/idle_interval" 2>/dev/null
    [ -w "/sys/fs/f2fs/$userdata/ram_thresh" ] && echo 1 > "/sys/fs/f2fs/$userdata/ram_thresh" 2>/dev/null
    echo "GC 参数已优化"
}
check_write_life() {
    begin_life=""
    res_iostats="false"
    if [ "$iostats" = "1" ]; then
        begin_life=$(cat "/sys/fs/f2fs/$userdata/lifetime_write_kbytes" 2>/dev/null)
        [ "$begin_life" = "0" ] && begin_life=""
    else
        if [ "$iostats" = "0" ] && [ -d "$iopath" ]; then
            echo 1 > "$iopath/iostats" 2>/dev/null
            begin_life=$(cat "/sys/fs/f2fs/$userdata/lifetime_write_kbytes" 2>/dev/null)
            timeout 4s dd if=/dev/zero of=/data/zz.txt bs=4096 count=1024 >/dev/null 2>&1
            sync -j 8
            sleep 1
            e_l=$(cat "/sys/fs/f2fs/$userdata/lifetime_write_kbytes" 2>/dev/null)
            rm -f /data/zz.txt 2>/dev/null
            if [ "$((e_l - begin_life))" -gt 0 ]; then
                res_iostats="true"
            else
                begin_life=""
                res_iostats="true"
            fi
        fi
    fi
    [ -n "$begin_life" ] && echo "写入统计可用" || echo "写入统计不可用"
}
check_bootdevice() {
    disk=$(getprop ro.boot.bootdevice)
    [ -z "$disk" ] && disk='null'
    echo "启动设备: $disk"
}
hv_disk() {
    io_max='off'
    [ "$disk" = "null" ] && return 0
    if ls /dev/block/ | grep -q 'mmcblk'; then
        flash_type=EMMC
    else
        flash_type=UFS
    fi
    for base in "/sys/devices/platform/soc/$disk" "/sys/devices/soc/$disk" "/sys/devices/soc.0/$disk" "/sys/devices/$disk"; do
        if [ -d "$base" ]; then
            disk_path="$base"
            break
        fi
    done
    if [ -z "$disk_path" ]; then
        return 0
    fi
    io_max='on'
    echo "闪存类型: $flash_type"
}
io_perf_bak() {
    [ "$io_max" != "on" ] && return 0
    case "$flash_type" in
        UFS)
            auto_hibern8=$(cat "$disk_path/auto_hibern8" 2>/dev/null)
            clkgate_delay_ms_perf=$(cat "$disk_path/clkgate_delay_ms_perf" 2>/dev/null)
            clkgate_delay_ms_pwr_save=$(cat "$disk_path/clkgate_delay_ms_pwr_save" 2>/dev/null)
            control=$(cat "$disk_path/power/control" 2>/dev/null)
            governor=$(cat "$disk_path/devfreq/$disk/governor" 2>/dev/null)
            ;;
        EMMC)
            down_threshold=$(cat "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" 2>/dev/null)
            up_threshold=$(cat "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" 2>/dev/null)
            clkgate_enable=$(cat "$disk_path/mmc_host/mmc0/clkgate_delay" 2>/dev/null)
            control=$(cat "$disk_path/mmc_host/mmc0/power/control" 2>/dev/null)
            governor=$(cat "$disk_path/mmc_host/mmc0/mmc0/governor" 2>/dev/null)
            ;;
        OLD_EMMC)
            down_threshold=$(cat "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" 2>/dev/null)
            up_threshold=$(cat "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" 2>/dev/null)
            clkgate_enable=$(cat "$disk_path/mmc_host/mmc0/clkgate_delay" 2>/dev/null)
            control=$(cat "$disk_path/mmc_host/mmc0/power/control" 2>/dev/null)
            ;;
    esac
    echo "闪存设置备份完成"
}
io_perf_set() {
    [ "$io_max" != "on" ] && return 0
    case "$flash_type" in
        UFS)
            [ -w "$disk_path/auto_hibern8" ] && echo 0 > "$disk_path/auto_hibern8" 2>/dev/null
            [ -w "$disk_path/clkscale_enable" ] && echo 0 > "$disk_path/clkscale_enable" 2>/dev/null
            [ -w "$disk_path/clkgate_enable" ] && echo 0 > "$disk_path/clkgate_enable" 2>/dev/null
            [ -w "$disk_path/clkgate_delay_ms_perf" ] && echo 2147483647 > "$disk_path/clkgate_delay_ms_perf" 2>/dev/null
            [ -w "$disk_path/clkgate_delay_ms_pwr_save" ] && echo 2147483647 > "$disk_path/clkgate_delay_ms_pwr_save" 2>/dev/null
            [ -w "$disk_path/rpm_lvl" ] && echo 0 > "$disk_path/rpm_lvl" 2>/dev/null
            [ -w "$disk_path/spm_lvl" ] && echo 0 > "$disk_path/spm_lvl" 2>/dev/null
            [ -w "$disk_path/power/control" ] && echo 'on' > "$disk_path/power/control" 2>/dev/null
            [ -w "$disk_path/devfreq/$disk/governor" ] && echo 'performance' > "$disk_path/devfreq/$disk/governor" 2>/dev/null
            ;;
        EMMC)
            [ -w "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" ] && echo 1 > "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" ] && echo 2 > "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/clk_scaling/polling_interval" ] && echo 20 > "$disk_path/mmc_host/mmc0/clk_scaling/polling_interval" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/clkgate_delay" ] && echo 2147483647 > "$disk_path/mmc_host/mmc0/clkgate_delay" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/power/control" ] && echo 'on' > "$disk_path/mmc_host/mmc0/power/control" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/mmc0/governor" ] && echo 'performance' > "$disk_path/mmc_host/mmc0/mmc0/governor" 2>/dev/null
            ;;
        OLD_EMMC)
            [ -w "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" ] && echo 1 > "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" ] && echo 2 > "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/clk_scaling/polling_interval" ] && echo 20 > "$disk_path/mmc_host/mmc0/clk_scaling/polling_interval" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/clkgate_delay" ] && echo 2147483647 > "$disk_path/mmc_host/mmc0/clkgate_delay" 2>/dev/null
            [ -w "$disk_path/mmc_host/mmc0/power/control" ] && echo 'on' > "$disk_path/mmc_host/mmc0/power/control" 2>/dev/null
            ;;
    esac
    echo "闪存性能优化完成"
}
io_perf_res() {
    [ "$io_max" != "on" ] && return 0
    case "$flash_type" in
        UFS)
            echo "$auto_hibern8" > "$disk_path/auto_hibern8" 2>/dev/null
            echo "$clkgate_delay_ms_perf" > "$disk_path/clkgate_delay_ms_perf" 2>/dev/null
            echo "$clkgate_delay_ms_pwr_save" > "$disk_path/clkgate_delay_ms_pwr_save" 2>/dev/null
            echo 1 > "$disk_path/clkscale_enable" 2>/dev/null
            echo 1 > "$disk_path/clkgate_enable" 2>/dev/null
            echo 3 > "$disk_path/rpm_lvl" 2>/dev/null
            echo 3 > "$disk_path/spm_lvl" 2>/dev/null
            echo "$control" > "$disk_path/power/control" 2>/dev/null
            echo "$governor" > "$disk_path/devfreq/$disk/governor" 2>/dev/null
            ;;
        EMMC)
            echo "$down_threshold" > "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" 2>/dev/null
            echo "$up_threshold" > "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" 2>/dev/null
            echo 100 > "$disk_path/mmc_host/mmc0/clk_scaling/polling_interval" 2>/dev/null
            echo "$clkgate_enable" > "$disk_path/mmc_host/mmc0/clkgate_delay" 2>/dev/null
            echo "$control" > "$disk_path/mmc_host/mmc0/power/control" 2>/dev/null
            echo "$governor" > "$disk_path/mmc_host/mmc0/mmc0/governor" 2>/dev/null
            ;;
        OLD_EMMC)
            echo "$down_threshold" > "$disk_path/mmc_host/mmc0/clk_scaling/down_threshold" 2>/dev/null
            echo "$up_threshold" > "$disk_path/mmc_host/mmc0/clk_scaling/up_threshold" 2>/dev/null
            echo 100 > "$disk_path/mmc_host/mmc0/clk_scaling/polling_interval" 2>/dev/null
            echo "$clkgate_enable" > "$disk_path/mmc_host/mmc0/clkgate_delay" 2>/dev/null
            echo "$control" > "$disk_path/mmc_host/mmc0/power/control" 2>/dev/null
            ;;
    esac
    echo "闪存设置恢复完成"
}
check_mv_blocks() {
    read_mv_block="false"
    if [ -f "/sys/fs/f2fs/$userdata/moved_blocks_foreground" ] && [ -f "/sys/fs/f2fs/$userdata/moved_blocks_background" ]; then
        read_mv_block="true"
        temp1=$(cat "/sys/fs/f2fs/$userdata/moved_blocks_foreground" 2>/dev/null)
        temp2=$(cat "/sys/fs/f2fs/$userdata/moved_blocks_background" 2>/dev/null)
        begin_mv_block=$((temp1 + temp2))
        echo "数据迁移统计可用"
    fi
}
early_begin() {
    local unusable=$(cat "/sys/fs/f2fs/$userdata/unusable" 2>/dev/null)
    if [ "$unusable" -ge 2000000 ]; then
        echo "警告: 不可用块较多 ($unusable)，可能需多次回收"
    fi
    echo "开始 F2FS 垃圾回收..."
}
f2fs_gc_wait_safe() {
    local count=0 last_unusable=0 same_count=0
    while [ $count -lt $GC_SLEEP ]; do
        local remaining=$((GC_SLEEP - count))
        local progress=$((count * 100 / GC_SLEEP))
        local filled=$((progress / 2))
        local empty=$((50 - filled))
        if [ -f "/sys/fs/f2fs/$userdata/unusable" ]; then
            local unusable=$(cat "/sys/fs/f2fs/$userdata/unusable" 2>/dev/null)
            if [ "$unusable" = "$last_unusable" ]; then
                same_count=$((same_count + 1))
            else
                same_count=0
                last_unusable=$unusable
            fi
            if [ $same_count -ge 6 ] && [ "$unusable" -gt 0 ]; then
                echo "回收进度停滞 (连续 18 秒无变化)，可能已达最佳状态"
                break
            fi
            printf "\r[%-50s] %d%% | 剩余: %3d秒 | 不可用块: %d   " \
                "$(printf '%*s' $filled '' | tr ' ' '#')$(printf '%*s' $empty '' | tr ' ' '.')" \
                $progress $remaining $unusable
            if [ "$unusable" -eq 0 ]; then
                local end_interval=8
                [ $remaining -le $end_interval ] && end_interval=3
                echo -e "\n不可用块已为0，等待 ${end_interval} 秒后完成"
                sleep $end_interval
                return 0
            fi
        else
            printf "\r[%-50s] %d%% | 剩余: %3d秒   " \
                "$(printf '%*s' $filled '' | tr ' ' '#')$(printf '%*s' $empty '' | tr ' ' '.')" \
                $progress $remaining
        fi
        sleep $INTERVAL
        count=$((count + INTERVAL))
    done
    echo -e "\n回收时间结束。"
}
end() {
    echo "$gc_booster" > "/sys/fs/f2fs/$userdata/gc_booster" 2>/dev/null
    echo "$cp_interval" > "/sys/fs/f2fs/$userdata/cp_interval" 2>/dev/null
    echo "$dirty_nats_ratio" > "/sys/fs/f2fs/$userdata/dirty_nats_ratio" 2>/dev/null
    echo "$discard_idle_interval" > "/sys/fs/f2fs/$userdata/discard_idle_interval" 2>/dev/null
    echo "$gc_idle" > "/sys/fs/f2fs/$userdata/gc_idle" 2>/dev/null
    echo "$gc_idle_interval" > "/sys/fs/f2fs/$userdata/gc_idle_interval" 2>/dev/null
    echo "$gc_max_sleep_time" > "/sys/fs/f2fs/$userdata/gc_max_sleep_time" 2>/dev/null
    echo "$gc_min_sleep_time" > "/sys/fs/f2fs/$userdata/gc_min_sleep_time" 2>/dev/null
    echo "$gc_no_gc_sleep_time" > "/sys/fs/f2fs/$userdata/gc_no_gc_sleep_time" 2>/dev/null
    echo "$gc_urgent" > "/sys/fs/f2fs/$userdata/gc_urgent" 2>/dev/null
    echo "$gc_urgent_sleep_time" > "/sys/fs/f2fs/$userdata/gc_urgent_sleep_time" 2>/dev/null
    echo "$idle_interval" > "/sys/fs/f2fs/$userdata/idle_interval" 2>/dev/null
    echo "$ram_thresh" > "/sys/fs/f2fs/$userdata/ram_thresh" 2>/dev/null
    echo "GC 参数已恢复"
}
p_life() {
    if [ -n "$begin_life" ]; then
        end_life=$(cat "/sys/fs/f2fs/$userdata/lifetime_write_kbytes" 2>/dev/null)
        life=$(( (end_life - begin_life) / 1024 ))
        echo "数据迁移总量: ${life} MB"
        if [ ${#life} -ge 4 ]; then
            lifegb=$(echo "scale=2; $life/1024" | bc)
            printf "折合为: %.2f GB\n" $lifegb
        fi
    fi
}
f2fs_gc_main() {
    check_root
    check_selinux
    check_busybox
    check_filesystem
    check_time
    check_userdata
    check_iopath
    backup
    enable_gc
    load1
    load2
    check_write_life
    check_bootdevice
    hv_disk
    io_perf_bak
    io_perf_set
    check_mv_blocks
    early_begin
    begin
    echo "回收时间: ${GC_SLEEP}秒 | 检查间隔: ${INTERVAL}秒"
    echo "开始时间: $(date '+%H:%M:%S')"
    f2fs_gc_wait_safe
    end
    $bak
    io_perf_res
    p_life
    restore_iostats $res_iostats
    $restore_se
    echo "本次回收结束于 $(date '+%H:%M:%S')"
}
while true; do
    screen_state=$(dumpsys power 2>/dev/null | grep -E 'mScreenOn=true|Display Power: state=ON|DisplayPowerController:.*mScreen(On)?=true' | head -1)
    if [ -n "$screen_state" ]; then
        echo "$(date): 屏幕亮起，跳过回收"
    else
        echo "$(date): 屏幕已关闭，开始执行 F2FS 垃圾回收..."
        f2fs_gc_main
        echo "回收执行完毕，等待 ${CHECK_INTERVAL} 秒后重新检测屏幕状态"
    fi
    sleep $CHECK_INTERVAL
done