#!/system/bin/sh
MODPATH="/data/adb/modules/sys_optimizer_webui"
rm -rf /data/adb/modules/sys_optimizer_webui/common/logs 2>/dev/null

get_root_type() {
    if [ -n "$KSU" ]; then echo "kernelsu"; return; fi
    if [ -n "$APATCH" ]; then echo "apatch"; return; fi
    if [ -d /data/adb/ksu ]; then echo "kernelsu"; return; fi
    if [ -d /data/adb/ap ]; then echo "apatch"; return; fi
    if [ -f /data/adb/magisk/util_functions.sh ]; then
        . /data/adb/magisk/util_functions.sh 2>/dev/null
        case $MAGISK_VER in
            *alpha*)   echo "alpha" ;;
            *delta*)   echo "delta" ;;
            *kitsune*) echo "kitsune" ;;
            *)         echo "magisk" ;;
        esac
        return
    fi
    echo "unknown"
}
set_selinux_context() {
    command -v chcon >/dev/null 2>&1 && chcon -R u:object_r:magisk_file:s0 "$1" 2>/dev/null
}
LOGF=$MODPATH/logs/service.log
CONF=$MODPATH/common/config.conf
mkdir -p $MODPATH/logs 2>/dev/null
chmod 0777 $MODPATH/logs 2>/dev/null
safe_cat() {
    local file="$1" default="${2:-}"
    if [ ! -r "$file" ]; then echo "$default"; return 1; fi
    local result=$(read -t 0.3 -r var < "$file" 2>/dev/null && echo "$var" || echo "$default")
    echo "${result:-$default}"
}
get_config(){
    local key="$1" default="${2:-}"
    local value=$(sed -n "s/^${key}=//p" "$CONF" 2>/dev/null | head -1 | tr -d '\r')
    if [ -n "$value" ]; then echo "$value"; else echo "$default"; fi
}
LOG_LEVEL=$(get_config log_level 1)
case "$LOG_LEVEL" in ''|*[!0-9]*) LOG_LEVEL=1 ;; esac
write_log() {
    local level="$1" msg="$2"
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    case "$level" in I|W|E) [ "$LOG_LEVEL" -ge 1 ] || return ;; D) [ "$LOG_LEVEL" -ge 2 ] || return ;; *) return ;; esac
    local logline="$timestamp $level/SysOpt: $msg"
    if echo "$logline" >> "$LOGF" 2>/dev/null; then chmod 666 "$LOGF" 2>/dev/null; return 0; fi
    command -v log >/dev/null 2>&1 && log -p i -t SysOpt "$msg"
}
log_info() { write_log "I" "$1"; }
log_err()  { write_log "E" "$1"; }
log_debug(){ write_log "D" "$1"; }
set_config(){ if grep -q "^$1=" $CONF;then sed -i "s/^$1=.*/$1=$2/" $CONF;else echo "$1=$2">>$CONF;fi }
check_service_status() {
    local pid_file="$MODPATH/.service.pid" pid_bak="$MODPATH/.service.pid.bak" pid
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then echo "running"; return; fi
    fi
    if [ -f "$pid_bak" ]; then
        pid=$(cat "$pid_bak" 2>/dev/null)
        if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then echo "$pid" > "$pid_file" 2>/dev/null; echo "running"; return; fi
    fi
    local found_pid=$(pgrep -f "$MODPATH/service.sh" 2>/dev/null | head -1)
    if [ -n "$found_pid" ]; then
        echo "$found_pid" > "$pid_file" 2>/dev/null
        cp "$pid_file" "$pid_bak" 2>/dev/null
        echo "running"; return
    fi
    echo "stopped"
}
get_system_info(){ echo "model=$(getprop ro.product.model)"; echo "android=$(getprop ro.build.version.release)"; echo "sdk=$(getprop ro.build.version.sdk)"; }
get_storage_info(){ df -h /data | tail -1 | awk '{print "total="$2,"used="$3,"free="$4,"percent="$5}'; }
get_uptime_seconds(){ cat /proc/uptime | awk '{print int($1)}'; }
get_cpu_clusters(){ for p in /sys/devices/system/cpu/cpufreq/policy*; do [ -d $p ] || continue; c=$(safe_cat $p/related_cpus); f=$(safe_cat $p/cpuinfo_max_freq); [ -n "$c" -a -n "$f" ] && echo "$f:$c"; done | sort -n -t: -k1,1 | awk -F: '{if(NR==1)e=$2;else if(NR==NR)h=$2;if(NR>1&&NR<NR)p=p" "$2}END{printf "e_core=\"%s\"\nh_core=\"%s\"\np_core=\"%s\"\n",e,h,p}'; }
detect_xiaomi(){ [ -n "$(getprop ro.miui.ui.version.name)" ] && return 0 || return 1; }
get_ram_info(){ awk '/^MemTotal:/{t=$2}/^MemFree:/{f=$2}/^Buffers:/{b=$2}/^Cached:/{c=$2}/^MemAvailable:/{a=$2} END{if(a==0)a=f+b+c;u=t-a;printf "total=%.1f\nused=%.1f\navail=%.1f\npercent=%.0f\n",t/1048576,u/1048576,a/1048576,u*100/t}' /proc/meminfo; }
get_cpu_all(){
    local stat_line=$(head -1 /proc/stat 2>/dev/null)
    if [ -z "$stat_line" ]; then echo "usage=0"; return; fi
    set -- $stat_line
    local user=$2 nice=$3 system=$4 idle=$5 iowait=$6 irq=$7 softirq=$8
    local total=$((user + nice + system + idle + iowait + irq + softirq))
    local used=$((user + nice + system + irq + softirq))
    local usage=0; [ $total -gt 0 ] && usage=$((used * 100 / total)); [ $usage -gt 100 ] && usage=100
    echo "usage=$usage"
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -d $cpu ] || continue
        core=${cpu##*/}
        cur=$(safe_cat $cpu/cpufreq/scaling_cur_freq 0)
        max=$(safe_cat $cpu/cpufreq/scaling_max_freq 1000)
        cur=$((cur/1000)); max=$((max/1000)); [ $max -eq 0 ] && max=1000
        echo "${core}=${cur},${max}"
    done
}
detect_charging() {
    local mode=$(get_config charge_detect_mode 10); mode=$((mode))
    local usb_online=$(safe_cat /sys/class/power_supply/usb/online 0)
    local usb_type=$(safe_cat /sys/class/power_supply/usb/type "")
    local usb_present=$(safe_cat /sys/class/power_supply/usb/present 0)
    local ac_online=$(safe_cat /sys/class/power_supply/ac/online 0)
    local wireless_online=$(safe_cat /sys/class/power_supply/wireless/online 0)
    local status=$(safe_cat /sys/class/power_supply/battery/status "" | tr '[:upper:]' '[:lower:]')
    case $mode in
        1) [ "$status" = "charging" ] || [ "$status" = "not charging" ] || [ "$status" = "full" ] && return 0 ;;
        2) [ "$status" = "charging" ] || [ "$status" = "not charging" ] && return 0 ;;
        3) [ "$status" = "charging" ] || [ "$status" = "full" ] && return 0 ;;
        4) [ "$status" = "charging" ] && return 0 ;;
        5) [ "$usb_online" = "1" ] && return 0 ;;
        6) [ -n "$usb_type" ] && return 0 ;;
        7) [ "$usb_present" = "1" ] && return 0 ;;
        8) [ "$ac_online" = "1" ] && return 0 ;;
        9) [ "$wireless_online" = "1" ] && return 0 ;;
        10) [ "$usb_online" = "1" ] || [ -n "$usb_type" ] || [ "$usb_present" = "1" ] || [ "$ac_online" = "1" ] || [ "$wireless_online" = "1" ] && return 0 ;;
        *) [ "$status" = "charging" ] || [ "$status" = "not charging" ] && return 0 ;;
    esac
    return 1
}
send_notify() {
    local title="$1" content="$2" event="$3"
    local mode=$(get_config notify_mode 1); [ "$mode" = "0" ] && return
    local events=$(get_config notify_events "shutdown,low_battery,clean_done")
    if [ -n "$event" ] && ! echo ",$events," | grep -q ",$event,"; then return; fi
    if [ "$mode" = "1" ] && command -v cmd >/dev/null 2>&1; then
        timeout 2 cmd notification post -S bigtext -t "$title" 'Tag' "$content" >/dev/null 2>&1
    else log_info "通知: $title - $content"; fi
}
check_low_voltage() {
    [ "$(get_config low_voltage_shutdown 0)" = "0" ] && return 0
    local threshold=$(get_config shutdown_voltage 3300) delay=$(get_config shutdown_delay 30)
    local boot_min=$(get_config boot_minimum_time 120)
    local uptime=$(awk '{print int($1)}' /proc/uptime); [ $uptime -lt $boot_min ] && return 0
    local voltage=$(safe_cat /sys/class/power_supply/battery/voltage_now 0 | awk '{print $1/1000}')
    [ -z "$voltage" ] && return 0
    if [ ${voltage%.*} -lt $threshold ] && ! detect_charging; then
        log_info "电压 $voltage mV 低于阈值 $threshold，将在 $delay 秒后关机"
        send_notify "⚠️ 电池电压过低" "将在 $delay 秒后自动关机" "shutdown"
        sleep $delay; sync; /system/bin/reboot -p; exit 0
    fi
    return 0
}
get_forced_device() {
    local force=$(get_config force_device_type "")
    if [ -n "$force" ]; then echo "$force"; else get_system_type; fi
}
detect_platform(){
    local forced=$(get_forced_device)
    case "$forced" in qcom|mtk|generic) echo "$forced"; return ;; esac
    if [ -d "/sys/class/qcom-battery" ]; then echo "qcom"
    elif [ -d "/sys/class/mtk-battery" ]; then echo "mtk"
    else echo "generic"; fi
}
get_system_type(){
    local forced=$(get_forced_device)
    case "$forced" in coloros|miui|hyperos|oneui|funtouch|realmeui|aosp) echo "$forced"; return ;; esac
    [ -n "$(getprop ro.build.version.oplusrom)" ] && { echo "coloros"; return; }
    [ -n "$(getprop ro.oplus.version)" ] && { echo "coloros"; return; }
    [ -n "$(getprop ro.oppo.version)" ] && { echo "coloros"; return; }
    [ -n "$(getprop ro.realme.version)" ] && { echo "realmeui"; return; }
    [ -n "$(getprop ro.build.version.realme)" ] && { echo "realmeui"; return; }
    [ -n "$(getprop ro.miui.ui.version.name)" -a -z "$(getprop ro.build.version.hyperos)" ] && { echo "miui"; return; }
    [ -n "$(getprop ro.build.version.hyperos)" ] && { echo "hyperos"; return; }
    [ -n "$(getprop ro.samsung.version)" ] && { echo "oneui"; return; }
    [ -n "$(getprop ro.build.version.oneui)" ] && { echo "oneui"; return; }
    [ -n "$(getprop ro.vivo.os.version)" ] && { echo "funtouch"; return; }
    local brand=$(getprop ro.product.brand | tr '[:upper:]' '[:lower:]')
    local manufacturer=$(getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')
    case "$brand" in oppo|oneplus) echo "coloros"; return;; realme) echo "realmeui"; return;; xiaomi|redmi|poco) echo "miui"; return;; samsung) echo "oneui"; return;; vivo) echo "funtouch"; return;; honor) echo "magicos"; return;; lenovo|motorola) echo "zui"; return;; esac
    case "$manufacturer" in oppo|oneplus) echo "coloros"; return;; realme) echo "realmeui"; return;; xiaomi) echo "miui"; return;; samsung) echo "oneui"; return;; vivo) echo "funtouch"; return;; honor) echo "magicos"; return;; lenovo|motorola) echo "zui"; return;; esac
    [ -d "/system/oppo" ] || [ -d "/product/oppo" ] || [ -d "/system_ext/oppo" ] && { echo "coloros"; return; }
    [ -d "/system/miui" ] || [ -d "/data/miui" ] && { echo "miui"; return; }
    [ -d "/system/vivo" ] && { echo "funtouch"; return; }
    [ -d "/system/samsung" ] && { echo "oneui"; return; }
    local fingerprint=$(getprop ro.build.fingerprint | tr '[:upper:]' '[:lower:]')
    case "$fingerprint" in *oppo*|*oneplus*) echo "coloros"; return;; *realme*) echo "realmeui"; return;; *xiaomi*|*redmi*|*poco*) echo "miui"; return;; *samsung*) echo "oneui"; return;; *vivo*) echo "funtouch"; return;; *honor*) echo "magicos"; return;; *lenovo*|*motorola*) echo "zui"; return;; esac
    echo "aosp"
}
record_battery_history() {
    local interval=$(get_config battery_history_interval 600); [ "$interval" = "0" ] && return
    local hist_file="$MODPATH/logs/battery_history.log"
    mkdir -p "$(dirname "$hist_file")"
    local max_lines=$(get_config battery_history_max_lines 1000)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cap=$(safe_cat /sys/class/power_supply/battery/capacity 0)
    local volt=$(safe_cat /sys/class/power_supply/battery/voltage_now 0 | awk '{print $1/1000}')
    local curr=$(safe_cat /sys/class/power_supply/battery/current_now 0 | awk '{print $1/1000}')
    local temp=$(safe_cat /sys/class/power_supply/battery/temp 0 | awk '{print $1/10}')
    echo "$timestamp,$cap,$volt,$curr,$temp" >> "$hist_file"
    if [ -f "$hist_file" ] && [ $(wc -l < "$hist_file") -gt $max_lines ]; then
        tail -n $max_lines "$hist_file" > "$hist_file.tmp" && mv "$hist_file.tmp" "$hist_file"
    fi
}
v2v(){ awk "BEGIN{printf \"%.2f\",$1/1000000}" 2>/dev/null || echo "0.00"; }
c2a(){ awk "BEGIN{printf \"%.2f\",${1#-}/1000000}" 2>/dev/null || echo "0.00"; }
t2c(){ awk "BEGIN{printf \"%.1f\",$1/10}" 2>/dev/null || echo "0.0"; }
battery_info(){
    local tmp_result="/data/local/tmp/battery_info.tmp"
    (
        SRC=$(get_config battery_source "auto")
        cap=$(safe_cat /sys/class/power_supply/battery/capacity 0)
        sta=$(safe_cat /sys/class/power_supply/battery/status "未知")
        vlt=$(safe_cat /sys/class/power_supply/battery/voltage_now 0)
        cur=$(safe_cat /sys/class/power_supply/battery/current_now 0)
        tmp=$(safe_cat /sys/class/power_supply/battery/temp 0)
        usb=$(safe_cat /sys/class/power_supply/usb/online 0)
        des=0; fcc=0; rm=0; soh=0; cc=0; manu=""; sn=""; qmax=0; lock_warn=""; calc_soh=0
        des=$(safe_cat /sys/class/power_supply/battery/charge_full_design 0); [ "$des" -gt 1000000 ] && des=$((des/1000))
        fcc=$(safe_cat /sys/class/power_supply/battery/charge_full 0); [ "$fcc" -gt 1000000 ] && fcc=$((fcc/1000))
        rm=$(safe_cat /sys/class/power_supply/battery/charge_counter 0); [ "$rm" -gt 1000000 ] && rm=$((rm/1000))
        cc=$(safe_cat /sys/class/power_supply/battery/cycle_count 0)
        if [ "$SRC" = "auto" ]; then
            if [ -d "/sys/class/qcom-battery" ]; then
                qmax=$(safe_cat /sys/class/qcom-battery/fg1_qmax 0); [ "$qmax" -gt 1000000 ] && qmax=$((qmax/1000)); [ "$qmax" -gt 0 ] && des=$qmax
                fcc=$(safe_cat /sys/class/qcom-battery/fg1_fcc 0); [ "$fcc" -gt 1000000 ] && fcc=$((fcc/1000))
                rm=$(safe_cat /sys/class/qcom-battery/fg1_rm 0); [ "$rm" -gt 1000000 ] && rm=$((rm/1000))
                soh=$(safe_cat /sys/class/qcom-battery/soh 0)
            elif [ -d "/sys/class/mtk-battery" ]; then
                fcc=$(safe_cat /sys/class/mtk-battery/fg_fullcap 0); [ "$fcc" -gt 1000000 ] && fcc=$((fcc/1000))
                rm=$(safe_cat /sys/class/mtk-battery/fg_remaining 0); [ "$rm" -gt 1000000 ] && rm=$((rm/1000))
                cc=$(safe_cat /sys/class/mtk-battery/cycle_count 0)
            elif [ -f "/sys/class/oplus_chg/battery/design_capacity" ]; then
                des=$(safe_cat /sys/class/oplus_chg/battery/design_capacity 0)
                fcc=$(safe_cat /sys/class/oplus_chg/battery/battery_fcc 0)
                rm=$(safe_cat /sys/class/oplus_chg/battery/battery_rm 0)
                soh=$(safe_cat /sys/class/oplus_chg/battery/battery_soh 0)
                cc=$(safe_cat /sys/class/oplus_chg/battery/battery_cc 0)
                manu=$(safe_cat /sys/class/oplus_chg/battery/battery_manu_date)
                sn=$(safe_cat /sys/class/oplus_chg/battery/battery_sn)
            fi
        fi
        [ "$des" -eq 0 ] && des=1
        calc_soh=$(( fcc * 100 / des )); [ "$soh" -eq 0 ] && soh=$calc_soh
        if [ $soh -ge 95 ]; then grd="极好 ✨"; elif [ $soh -ge 90 ]; then grd="优秀 🌟"; elif [ $soh -ge 85 ]; then grd="良好 👍"; elif [ $soh -ge 80 ]; then grd="一般 ⚠️"; else grd="建议更换 🔴"; fi
        pwr=0
        if [ "$usb" = "1" ] && [ ${cur#-} -gt 0 ]; then pwr=$(awk "BEGIN{printf \"%.2f\",$vlt*${cur#-}/1000000000}" 2>/dev/null || echo 0); fi
        charge_type=$(safe_cat /sys/class/power_supply/usb/type "")
        cat <<EOF
{
  "capacity": "$cap",
  "status": "$sta",
  "voltage": "$(v2v $vlt)",
  "current": "$(c2a $cur)",
  "temperature": "$(t2c $tmp)",
  "usb_online": "$usb",
  "power": "$pwr",
  "design_capacity": "$des",
  "fcc": "$fcc",
  "remaining_capacity": "$rm",
  "soh": "$soh",
  "calculated_soh": "$calc_soh",
  "cycle_count": "$cc",
  "manufacture_date": "$manu",
  "serial": "$sn",
  "health_grade": "$grd",
  "lock_warning": "$lock_warn",
  "charge_type": "$charge_type"
}
EOF
    ) > "$tmp_result" 2>/dev/null &
    local pid=$!
    sleep 2
    if kill -0 $pid 2>/dev/null; then
        kill $pid 2>/dev/null; wait $pid 2>/dev/null
        echo '{"capacity":"0","status":"未知","voltage":"0.00","current":"0.00","temperature":"0.0","usb_online":"0","power":"0","design_capacity":"0","fcc":"0","remaining_capacity":"0","soh":"0","calculated_soh":"0","cycle_count":"0","manufacture_date":"","serial":"","health_grade":"--","lock_warning":"","charge_type":""}'
    else
        wait $pid 2>/dev/null
        cat "$tmp_result" 2>/dev/null || echo '{"capacity":"0","status":"未知","voltage":"0.00","current":"0.00","temperature":"0.0","usb_online":"0","power":"0","design_capacity":"0","fcc":"0","remaining_capacity":"0","soh":"0","calculated_soh":"0","cycle_count":"0","manufacture_date":"","serial":"","health_grade":"--","lock_warning":"","charge_type":""}'
    fi
    rm -f "$tmp_result"
}
optimize_io_scheduler() {
    [ "$(get_config enable_io_opt 1)" = "0" ] && return
    log_debug "starting I/O scheduler optimization"
    for disk in /sys/block/*; do
        [ -e "$disk/queue/scheduler" ] || continue
        local rotational=$(safe_cat "$disk/queue/rotational" 1)
        local disk_name=$(basename "$disk"); local scheduler="none"
        if [ "$rotational" = "0" ]; then
            if grep -q "none" "$disk/queue/scheduler" 2>/dev/null; then scheduler="none"
            elif grep -q "mq-deadline" "$disk/queue/scheduler" 2>/dev/null; then scheduler="mq-deadline"; fi
        else
            if grep -q "bfq" "$disk/queue/scheduler" 2>/dev/null; then scheduler="bfq"
            elif grep -q "cfq" "$disk/queue/scheduler" 2>/dev/null; then scheduler="cfq"; fi
        fi
        echo "$scheduler" > "$disk/queue/scheduler" 2>/dev/null && log_debug "  set $disk_name scheduler to $scheduler"
    done
}
optimize_read_ahead() {
    [ "$(get_config enable_read_ahead 1)" = "0" ] && return
    log_debug "starting read-ahead optimization"
    local mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    local read_ahead=1024; [ "$mem_total" -gt 4000000 ] && read_ahead=2048
    for disk in /sys/block/*; do
        [ -e "$disk/queue/read_ahead_kb" ] && { echo "$read_ahead" > "$disk/queue/read_ahead_kb" 2>/dev/null; log_debug "  set $(basename $disk) read_ahead_kb to $read_ahead"; }
    done
}
optimize_cpu_governor() {
    [ "$(get_config enable_cpu_gov 1)" = "0" ] && return
    log_debug "starting CPU governor optimization"
    local governor="schedutil"
    if ! grep -q "$governor" /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null; then governor="interactive"; fi
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -f "$cpu" ] && echo "$governor" > "$cpu" 2>/dev/null; done
    log_debug "  set CPU governor to $governor"
    if [ "$governor" = "interactive" ] && echo "$(getprop ro.board.platform)" | grep -qi "exynos"; then
        for timer in /sys/devices/system/cpu/cpufreq/interactive/timer_rate; do [ -f "$timer" ] && echo "20000" > "$timer" 2>/dev/null; done
        log_debug "  applied Exynos specific tweaks"
    fi
}
optimize_gpu() {
    [ "$(get_config enable_gpu_opt 1)" = "0" ] && return
    log_debug "starting GPU frequency optimization"
    local gpu_devfreq="/sys/class/kgsl/kgsl-3d0/devfreq"; local gpu_governor_path=""
    if [ -d "$gpu_devfreq" ]; then gpu_governor_path="$gpu_devfreq/governor"
    elif [ -f "/sys/class/kgsl/kgsl-3d0/governor" ]; then gpu_governor_path="/sys/class/kgsl/kgsl-3d0/governor"; fi
    if [ -f "$gpu_governor_path" ]; then
        local current=$(safe_cat "$gpu_governor_path")
        if grep -q "msm-adreno-tz" "$gpu_governor_path" 2>/dev/null; then
            echo "msm-adreno-tz" > "$gpu_governor_path" 2>/dev/null; log_debug "  set GPU governor to msm-adreno-tz (was $current)"
        else
            for gov in "schedutil" "simple_ondemand" "performance"; do
                if grep -q "$gov" "$gpu_governor_path" 2>/dev/null; then
                    echo "$gov" > "$gpu_governor_path" 2>/dev/null; log_debug "  set GPU governor to $gov (was $current)"; break
                fi
            done
        fi
    else log_debug "  GPU governor node not found, skipping"; fi
}
optimize_power_save() {
    [ "$(get_config enable_power_save 1)" = "0" ] && return
    log_debug "starting power save tweaks"
    echo 20 > /proc/sys/vm/dirty_ratio 2>/dev/null
    echo 10 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
    echo 50 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
    [ -f /proc/sys/vm/swappiness ] && echo 60 > /proc/sys/vm/swappiness 2>/dev/null
    log_debug "  vm parameters updated"
}
oiface_ctl() {
    case "$1" in
        status)
            local mode=$(getprop persist.sys.oiface.enable 2>/dev/null); [ -z "$mode" ] && mode=0
            local service=$(getprop init.svc.oiface 2>/dev/null); [ -z "$service" ] && service="stopped"
            echo "mode=$mode"; echo "service=$service"
            ;;
        enable) setprop persist.sys.oiface.enable 1; start oiface 2>/dev/null || setprop ctl.restart oiface 2>/dev/null; echo "oiface 已启用" ;;
        disable) setprop persist.sys.oiface.enable 0; stop oiface 2>/dev/null || setprop ctl.stop oiface 2>/dev/null; echo "oiface 已禁用" ;;
        mode2) setprop persist.sys.oiface.enable 2; stop oiface 2>/dev/null; sleep 1; start oiface 2>/dev/null; echo "特殊模式 2 已设置" ;;
        restart) stop oiface 2>/dev/null; sleep 1; start oiface 2>/dev/null; echo "oiface 服务已重启" ;;
        *) echo "用法: oiface_ctl {status|enable|disable|mode2|restart}"; return 1 ;;
    esac
}
battery_health_diagnosis() {
    [ "$(get_config enable_battery_health_diagnosis 1)" = "0" ] && return
    log_debug "running battery health diagnosis"
    local design=$(safe_cat /sys/class/power_supply/battery/charge_full_design 0 | awk '{print $1/1000}')
    local sys_full=$(safe_cat /sys/class/power_supply/battery/charge_full 0 | awk '{print $1/1000}')
    local real_full=$(safe_cat /sys/class/qcom-battery/fg1_qmax 0 | awk '{print $1/1000}'); [ -z "$real_full" ] && real_full=$sys_full
    local cycle=$(safe_cat /sys/class/power_supply/battery/cycle_count 0)
    if [ "$real_full" -gt 0 ] && [ "$sys_full" -gt 0 ]; then
        local lock_diff=$(( (real_full - sys_full) * 100 / real_full ))
        if [ $lock_diff -ge 10 ]; then
            log_info "⚠️ 可能锁容 ${lock_diff}% (真实${real_full}mAh, 系统${sys_full}mAh)"
            echo "$lock_diff" > $MODPATH/.lock_status
        else rm -f $MODPATH/.lock_status; fi
    fi
    if [ "$(get_config enable_deep_cycle_counter 1)" = "1" ]; then
        local cap=$(safe_cat /sys/class/power_supply/battery/capacity 0)
        local flag_file="/data/charge_cycle_flag.txt"; local count_file="/data/charge_cycle_count.txt"
        if [ "$cap" = "0" ]; then echo "drained" > $flag_file
        elif [ "$cap" = "100" ] && [ -f $flag_file ] && [ "$(cat $flag_file)" = "drained" ]; then
            local cnt=$(safe_cat $count_file 0); cnt=$((cnt + 1)); echo $cnt > $count_file; rm -f $flag_file
            log_info "深度循环计数 +1，当前总数 $cnt"
        fi
    fi
    if [ "$(get_config enable_mod_battery_detection 1)" = "1" ] && [ "$design" -gt 0 ] && [ "$sys_full" -gt 0 ]; then
        local cap_diff=$(( (sys_full - design) * 100 / design ))
        if [ $cap_diff -gt 20 ] && [ $cycle -lt 50 ]; then
            log_info "🔋 检测到魔改电池，容量超出设计 ${cap_diff}%"
            echo "$cap_diff" > $MODPATH/.mod_battery
        else rm -f $MODPATH/.mod_battery; fi
    fi
    if [ "$(get_config enable_fast_charge_repair 1)" = "1" ] && [ -f /sys/class/qcom-battery/fast_charge_health ]; then
        local fh=$(safe_cat /sys/class/qcom-battery/fast_charge_health 0)
        if [ -n "$fh" ] && [ $fh -lt 70 ]; then
            chmod 666 /sys/class/qcom-battery/fast_charge_health 2>/dev/null
            echo 100 > /sys/class/qcom-battery/fast_charge_health 2>/dev/null
            log_info "快充健康修复: 已重置为100"
        fi
    fi
}
suppress_processes() {
    local mode=$(get_config process_suppress_mode 0); [ "$mode" = "0" ] && return
    local adj_threshold=$(get_config process_suppress_adj 800)
    local smart_pkgs=$(get_config smart_avoid_packages "com.tencent.mm,com.tencent.mobileqq"); local is_smart=0
    if [ -n "$smart_pkgs" ]; then
        local front_app=$(dumpsys window windows 2>/dev/null | grep -E 'mCurrentFocus' | sed -E 's/.* ([a-zA-Z0-9.]+)\/.*/\1/')
        if echo ",$smart_pkgs," | grep -q ",$front_app,"; then is_smart=1; log_debug "smart avoid: $front_app"; fi
    fi
    if [ "$mode" = "1" ] && { [ "$(safe_cat /sys/class/backlight/*/bl_power 0)" != "0" ] || [ "$(dumpsys power 2>/dev/null | grep mScreenOn=true)" = "" ]; }; then is_smart=1; fi
    [ $is_smart -eq 1 ] && return
    (
        for pid in /proc/[0-9]*; do
            [ ! -d "$pid" ] && continue
            oom=$(safe_cat $pid/oom_score_adj 9999)
            [ "$oom" -ge $adj_threshold ] 2>/dev/null || continue
            cmdline=$(safe_cat $pid/cmdline)
            case "$cmdline" in *com.android*|*system*|*kernel*) continue;; esac
            kill -9 ${pid##*/} 2>/dev/null
        done
    ) &
    log_debug "suppress_processes started in background"
}
lock_directories() {
    local dirs=$(get_config memory_lock_dirs ""); [ -z "$dirs" ] && return
    echo "$dirs" | tr ';' '\n' | while read d; do
        [ -d "$d" ] || continue; chmod 000 "$d" 2>/dev/null; chattr +i "$d" 2>/dev/null; log_debug "locked $d"
    done
}
LOCKDIR=/dev/shm/sysopt_locks; mkdir -p $LOCKDIR 2>/dev/null
acquire_lock() {
    local name="$1" lockfile="$LOCKDIR/$name.lock"
    if [ -f "$lockfile" ]; then
        local oldpid=$(safe_cat "$lockfile")
        if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then log_debug "任务 $name 已在运行 (PID $oldpid)，跳过"; return 1
        else rm -f "$lockfile"; fi
    fi
    echo $$ > "$lockfile"; return 0
}
release_lock() { local name="$1"; rm -f "$LOCKDIR/$name.lock"; }
adblock_update() {
    local enable=$(get_config adblock_enable 0); [ "$enable" != "1" ] && return
    acquire_lock "adblock" || return
    log_debug "adblock_update started"
    local url="https://example.com/adblock.txt"; local tmp=/data/local/tmp/adblock.txt; local success=0
    if command -v curl >/dev/null 2>&1; then curl -s -o $tmp $url 2>/dev/null && success=1
    elif command -v wget >/dev/null 2>&1; then wget -q -O $tmp $url 2>/dev/null && success=1
    else log_debug "adblock_update: 未找到 curl 或 wget"; release_lock "adblock"; return; fi
    if [ -s $tmp ]; then
        cp $tmp /data/adb/modules/sys_optimizer_webui/adblock_rules.txt
        iptables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:5353 2>/dev/null
        iptables -t nat -I OUTPUT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:5353
        log_info "adblock rules updated"
    else log_err "adblock_update failed, no data"; fi
    rm -f $tmp; release_lock "adblock"; log_debug "adblock_update finished"
}
clean_by_rules() {
    local rules_file=$(get_config file_clean_rules ""); [ ! -f "$rules_file" ] && return
    while IFS='|' read -r path pattern; do [ -z "$path" ] && continue; find "$path" -type f -name "$pattern" -delete 2>/dev/null; done < "$rules_file"
}
f2fs_dirty_check() {
    local threshold=$(get_config f2fs_dirty_threshold_mb 5000)
    local userdata=$(getprop dev.mnt.blk.data)
    if [ ! -d "/sys/fs/f2fs/$userdata" ]; then local temp=$(find /sys/fs/f2fs -type d -name 'dm-*' | head -1); [ -n "$temp" ] && userdata=$(basename "$temp"); fi
    [ -z "$userdata" ] && return
    local dirty=$(safe_cat "/sys/fs/f2fs/$userdata/dirty_segments" 0 | awk '{s+=$1}END{print s*4}')
    [ -z "$dirty" ] && return
    if [ "$dirty" -gt "$threshold" ]; then log_info "f2fs dirty $dirty MB > threshold $threshold, triggering GC"; echo 1 > "/sys/fs/f2fs/$userdata/gc_urgent" 2>/dev/null; fi
}
selinux_status(){
    local mode=$(getenforce 2>/dev/null); case "$mode" in Enforcing|Permissive|Disabled) ;; *) mode="未知" ;; esac
    local enforce; if [ -f /sys/fs/selinux/enforce ]; then enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null); [ -z "$enforce" ] && enforce="不可读"; else enforce='节点不存在'; fi
    echo "mode=$mode"; echo "enforce=$enforce"
}
selinux_set_enforcing(){ if setenforce 1 2>/dev/null; then echo "已切换至强制模式"; [ -w /sys/fs/selinux/enforce ] && echo 1 > /sys/fs/selinux/enforce 2>/dev/null; else echo "切换失败，请检查权限"; fi }
selinux_set_permissive(){
    echo "⚠️ 警告：宽容模式降低安全性，仅用于调试！"
    if setenforce 0 2>/dev/null; then echo "已切换至宽容模式"; [ -w /sys/fs/selinux/enforce ] && echo 0 > /sys/fs/selinux/enforce 2>/dev/null; else echo "切换失败，请检查权限"; fi
}
battery_whitelist_list(){ dumpsys deviceidle whitelist 2>/dev/null | grep -E '^user,' | cut -d, -f2 | sort -u; }
battery_whitelist_add(){
    local pkg="$1"
    [ -z "$pkg" ] && { echo "包名不能为空"; return 1; }
    if dumpsys deviceidle whitelist +"$pkg" 2>/dev/null; then
        # 如果添加成功，从移除列表中删除（如果存在）
        REMOVED_FILE="$MODPATH/common/removed_whitelist.conf"
        if [ -f "$REMOVED_FILE" ]; then
            sed -i "/^$pkg$/d" "$REMOVED_FILE" 2>/dev/null
        fi
        echo "添加成功: $pkg"
    else
        echo "添加失败"
    fi
}
battery_whitelist_remove(){
    local pkg="$1"
    [ -z "$pkg" ] && { echo "包名不能为空"; return 1; }
    if dumpsys deviceidle whitelist -"$pkg" 2>/dev/null; then
        # 将移除的包名追加到移除列表（去重）
        REMOVED_FILE="$MODPATH/common/removed_whitelist.conf"
        mkdir -p "$(dirname "$REMOVED_FILE")"
        touch "$REMOVED_FILE"
        # 先删除已有行再追加，避免重复
        sed -i "/^$pkg$/d" "$REMOVED_FILE" 2>/dev/null
        echo "$pkg" >> "$REMOVED_FILE"
        echo "移除成功: $pkg"
    else
        echo "移除失败"
    fi
}
battery_whitelist_installed_apps(){ pm list packages 2>/dev/null | cut -d: -f2 | sort; }

# ========== 白名单持久化 ==========
WHITELIST_FILE="$MODPATH/common/whitelist.conf"
REMOVED_FILE="$MODPATH/common/removed_whitelist.conf"

persist_whitelist() {
    battery_whitelist_list > "$WHITELIST_FILE"
    log_debug "白名单已保存到 $WHITELIST_FILE"
}

restore_whitelist() {
    [ -f "$WHITELIST_FILE" ] || return 0
    log_info "正在恢复白名单..."
    local current_whitelist=$(battery_whitelist_list)
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        if ! echo "$current_whitelist" | grep -q "^$pkg$"; then
            battery_whitelist_add "$pkg" >/dev/null 2>&1
            log_debug "  添加 $pkg"
        fi
    done < "$WHITELIST_FILE"
    log_info "白名单恢复完成"
}

# 新增：强制移除用户曾经移除的应用
restore_removed_whitelist() {
    [ -f "$REMOVED_FILE" ] || return 0
    log_info "正在强制移除用户已移除的白名单应用..."
    local removed_count=0
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        # 直接调用移除命令，即使不在白名单也没关系
        if dumpsys deviceidle whitelist -"$pkg" >/dev/null 2>&1; then
            log_debug "  已强制移除 $pkg"
            removed_count=$((removed_count + 1))
        else
            log_debug "  移除 $pkg 失败（可能已不在白名单）"
        fi
    done < "$REMOVED_FILE"
    log_info "强制移除完成，共处理 $removed_count 个应用"
}

# ========== 电芯类型配置 ==========
CELL_TYPE_FILE="$MODPATH/common/cell_type.conf"

get_cell_type() {
    if [ -f "$CELL_TYPE_FILE" ]; then
        cat "$CELL_TYPE_FILE" 2>/dev/null || echo "dual"
    else
        echo "dual"
    fi
}

set_cell_type() {
    echo "$1" > "$CELL_TYPE_FILE"
    log_info "电芯类型已设置为: $1"
}

# ========== 阿灵子类型配置 ==========
ALING_TYPE_FILE="$MODPATH/common/aling_type.conf"

get_aling_type() {
    if [ -f "$ALING_TYPE_FILE" ]; then
        cat "$ALING_TYPE_FILE" 2>/dev/null || echo "single"
    else
        echo "single"
    fi
}

set_aling_type() {
    echo "$1" > "$ALING_TYPE_FILE"
    log_info "阿灵子类型已设置为: $1"
}

# ========== 酷安@shell终端舵主-电池检测-4.5 详细电池信息（支持电芯类型参数） ==========
battery_info_detailed() {
    local cell_type=$(get_cell_type)
    local usb_online=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)
    local charge_type=$(cat /sys/class/power_supply/battery/charge_type 2>/dev/null)
    local v_now=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0)
    local v_usb=$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null || echo 0)
    local i_now=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
    local temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)
    local capacity=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
    local design=$(cat /sys/class/oplus_chg/battery/design_capacity 2>/dev/null || echo 0)
    local fcc=$(cat /sys/class/oplus_chg/battery/battery_fcc 2>/dev/null || echo 0)
    local rm=$(cat /sys/class/oplus_chg/battery/battery_rm 2>/dev/null || echo 0)
    local soh=$(cat /sys/class/oplus_chg/battery/battery_soh 2>/dev/null || echo 0)
    local cc=$(cat /sys/class/oplus_chg/battery/battery_cc 2>/dev/null || echo 0)
    local manu_date=$(cat /sys/class/oplus_chg/battery/battery_manu_date 2>/dev/null)
    local sn=$(cat /sys/class/oplus_chg/battery/battery_sn 2>/dev/null)
    local pps_power=$(cat /sys/devices/virtual/oplus_chg/battery/ppschg_power 2>/dev/null || echo 0)
    local usb_temp=$(cat /sys/devices/virtual/thermal/thermal_zone94/temp 2>/dev/null || echo 0)
    local vooc_temp=$(cat /sys/devices/virtual/thermal/thermal_zone85/temp 2>/dev/null || echo 0)
    local batt_qmax=$(cat /sys/class/oplus_chg/battery/batt_qmax 2>/dev/null || echo 0)
    local chip_soc=$(cat /sys/class/oplus_chg/battery/chip_soc 2>/dev/null || echo 0)

    local v=$(awk "BEGIN{printf \"%.2f\", $v_now/1000000}" 2>/dev/null || echo "0.00")
    local v_usb_fmt=$(awk "BEGIN{printf \"%.2f\", $v_usb/1000000}" 2>/dev/null || echo "0.00")
    local i_abs=$(echo "sqrt($i_now^2)" | bc 2>/dev/null || echo 0)
    if [ "$cell_type" = "dual" ]; then i_total=$(awk "BEGIN{printf \"%.2f\", $i_abs*2/1000}" 2>/dev/null || echo "0.00")
    else i_total=$(awk "BEGIN{printf \"%.2f\", $i_abs/1000}" 2>/dev/null || echo "0.00"); fi
    local p_total=$(awk "BEGIN{printf \"%.2f\", $v * $i_total}" 2>/dev/null || echo "0.00")
    local temp_c=$(awk "BEGIN{printf \"%.1f\", $temp/10}" 2>/dev/null || echo "0.0")
    local usb_temp_c=$(awk "BEGIN{printf \"%.1f\", $usb_temp/100}" 2>/dev/null || echo "0.0")
    local vooc_temp_c=$(awk "BEGIN{printf \"%.1f\", $vooc_temp/1000}" 2>/dev/null || echo "0.0")

    local health=0; [ "$design" -gt 0 ] && health=$(awk "BEGIN{printf \"%.0f\", $fcc*100/$design}" 2>/dev/null || echo 0)
    local locked=$((fcc - rm)); [ "$locked" -lt 0 ] && locked=0
    local locked_percent=0; [ "$fcc" -gt 0 ] && locked_percent=$(awk "BEGIN{printf \"%.2f\", $locked*100/$fcc}" 2>/dev/null || echo 0)

    local charge_status="未充电"; [ "$usb_online" = "1" ] && charge_status="正在充电"
    local full_flag=$(cat /sys/class/oplus_chg/battery/battery_notify_code 2>/dev/null); [ "$full_flag" != "0" ] && charge_status="已充满"

    local protocol="未知"
    case "${charge_type}" in 2) protocol="普通充电(5V/9V)" ;; 8) protocol="有线快充(VOOC基础)" ;; 14) protocol="超级快充(SVOOC)" ;; 16) protocol="PD快充" ;; esac

    cat <<EOF
{
  "usb_online": "$usb_online",
  "charge_status": "$charge_status",
  "protocol": "$protocol",
  "voltage_battery": "$v",
  "voltage_usb": "$v_usb_fmt",
  "current": "$i_total",
  "power": "$p_total",
  "temperature_battery": "$temp_c",
  "temperature_usb": "$usb_temp_c",
  "temperature_vooc": "$vooc_temp_c",
  "capacity_ui": "$capacity",
  "capacity_hardware": "$chip_soc",
  "design_capacity": "$design",
  "fcc": "$fcc",
  "remaining_capacity": "$rm",
  "soh": "$soh",
  "calculated_soh": "$health",
  "cycle_count": "$cc",
  "manufacture_date": "$manu_date",
  "serial": "$sn",
  "qmax": "$batt_qmax",
  "pps_power": "$pps_power",
  "locked_capacity": "$locked",
  "locked_percent": "$locked_percent"
}
EOF
}

battery_info_aling() {
    local subtype=$(get_aling_type); local divisor=1000; [ "$subtype" = "dual" ] && divisor=500
    local des_raw=$(cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null || echo 0)
    local fcc_raw=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null || echo 0)
    local rm_raw=$(cat /sys/class/power_supply/battery/charge_counter 2>/dev/null || echo 0)
    local cc_raw=$(cat /sys/class/power_supply/battery/cycle_count 2>/dev/null || echo 0)
    local cap=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
    local sta=$(cat /sys/class/power_supply/battery/status 2>/dev/null | tr -d '\n' || echo "未知")
    local vlt_raw=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0)
    local cur_raw=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
    local tmp_raw=$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0)
    local usb=$(cat /sys/class/power_supply/usb/online 2>/dev/null || echo 0)

    local design=$((des_raw / divisor)); local fcc=$((fcc_raw / divisor)); local rm=$((rm_raw / divisor)); local cc=$cc_raw
    local vlt=$(awk "BEGIN{printf \"%.2f\", $vlt_raw/1000000}" 2>/dev/null || echo "0.00")
    local cur_abs=${cur_raw#-}; local cur=$(awk "BEGIN{printf \"%.2f\", $cur_abs/1000000}" 2>/dev/null || echo "0.00")
    local tmp=$(awk "BEGIN{printf \"%.1f\", $tmp_raw/10}" 2>/dev/null || echo "0.0")
    local soh=0; [ "$design" -gt 0 ] && soh=$((fcc * 100 / design))
    local pwr=0; if [ "$usb" = "1" ] && [ $cur_abs -gt 0 ]; then pwr=$(awk "BEGIN{printf \"%.2f\", $vlt_raw*$cur_abs/1000000000000}" 2>/dev/null || echo "0"); fi
    local grd=""; if [ $soh -ge 95 ]; then grd="极好 ✨"; elif [ $soh -ge 90 ]; then grd="优秀 🌟"; elif [ $soh -ge 85 ]; then grd="良好 👍"; elif [ $soh -ge 80 ]; then grd="一般 ⚠️"; else grd="建议更换 🔴"; fi
    cat <<EOF
{
  "capacity": "$cap",
  "status": "$sta",
  "voltage": "$vlt",
  "current": "$cur",
  "temperature": "$tmp",
  "usb_online": "$usb",
  "power": "$pwr",
  "design_capacity": "$design",
  "fcc": "$fcc",
  "remaining_capacity": "$rm",
  "soh": "$soh",
  "cycle_count": "$cc",
  "health_grade": "$grd"
}
EOF
}

xuantian_v2_info() {
    local cap=$(safe_cat /sys/class/power_supply/battery/capacity 0)
    local volt_raw=$(safe_cat /sys/class/power_supply/battery/voltage_now 0)
    local temp_raw=$(safe_cat /sys/class/power_supply/battery/temp 0)
    local design_raw=$(safe_cat /sys/class/power_supply/battery/charge_full_design 0)
    local fcc_raw=$(safe_cat /sys/class/power_supply/battery/charge_full 0)
    local rm_raw=$(safe_cat /sys/class/power_supply/battery/charge_counter 0)
    local cycle=$(safe_cat /sys/class/power_supply/battery/cycle_count 0)

    local voltage=$(awk "BEGIN{printf \"%.2f\", $volt_raw/1000000}" 2>/dev/null || echo "0.00")
    local temperature=$(awk "BEGIN{printf \"%.1f\", $temp_raw/10}" 2>/dev/null || echo "0.0")
    local design_capacity=$((design_raw / 1000)); local fcc=$((fcc_raw / 1000)); local remaining=$((rm_raw / 1000))
    local health=0; [ "$design_raw" -gt 0 ] && health=$((fcc_raw * 100 / design_raw))

    local qcom_qmax=0; local qcom_ir=0; local fast_charge_health=0
    if [ -d "/sys/class/qcom-battery" ]; then
        qcom_qmax=$(safe_cat /sys/class/qcom-battery/fg1_qmax 0)
        qcom_ir=$(safe_cat /sys/class/qcom-battery/fg1_ir 0)
        fast_charge_health=$(safe_cat /sys/class/qcom-battery/fast_charge_health 0)
    fi

    local mtk_fullcap=0; local mtk_remaining=0; local mtk_cycle=0; local batt_health=""
    if [ -d "/sys/class/mtk-battery" ]; then
        mtk_fullcap=$(safe_cat /sys/class/mtk-battery/fg_fullcap 0)
        mtk_remaining=$(safe_cat /sys/class/mtk-battery/fg_remaining 0)
        mtk_cycle=$(safe_cat /sys/class/mtk-battery/cycle_count 0)
        batt_health=$(safe_cat /sys/class/mtk-battery/batt_health)
    fi

    cat <<EOF
{
  "capacity": $cap,
  "voltage": $voltage,
  "temperature": $temperature,
  "design_capacity": $design_capacity,
  "fcc": $fcc,
  "remaining_capacity": $remaining,
  "cycle_count": $cycle,
  "health": $health,
  "qcom_qmax": $qcom_qmax,
  "qcom_ir": $qcom_ir,
  "fast_charge_health": $fast_charge_health,
  "mtk_fullcap": $mtk_fullcap,
  "mtk_remaining": $mtk_remaining,
  "mtk_cycle": $mtk_cycle,
  "batt_health": "$batt_health"
}
EOF
}

xuantian_auto_info() {
    local cap=$(safe_cat /sys/class/power_supply/battery/capacity 0)
    local volt_raw=$(safe_cat /sys/class/power_supply/battery/voltage_now 0)
    local temp_raw=$(safe_cat /sys/class/power_supply/battery/temp 0)
    local design_raw=$(safe_cat /sys/class/power_supply/battery/charge_full_design 0)
    local fcc_raw=$(safe_cat /sys/class/power_supply/battery/charge_full 0)
    local cycle=$(safe_cat /sys/class/power_supply/battery/cycle_count 0)

    local real_qmax=0; local real_fcc_raw=0; local ir=0; local fast_health=0
    if [ -d "/sys/class/qcom-battery" ]; then
        real_qmax=$(safe_cat /sys/class/qcom-battery/fg1_qmax 0)
        real_fcc_raw=$(safe_cat /sys/class/qcom-battery/fg1_fcc 0)
        ir=$(safe_cat /sys/class/qcom-battery/fg1_ir 0)
        fast_health=$(safe_cat /sys/class/qcom-battery/fast_charge_health 0)
    fi

    local voltage=$(awk "BEGIN{printf \"%.2f\", $volt_raw/1000000}" 2>/dev/null || echo "0.00")
    local temperature=$(awk "BEGIN{printf \"%.1f\", $temp_raw/10}" 2>/dev/null || echo "0.0")
    local design_capacity=$((design_raw / 1000)); local fcc=$((fcc_raw / 1000))
    local health=0; [ "$design_raw" -gt 0 ] && health=$((fcc_raw * 100 / design_raw))

    local real_qmax_mah=$((real_qmax / 1000)); local real_fcc_mah=$((real_fcc_raw / 1000))
    local real_health=0; [ "$design_raw" -gt 0 ] && real_health=$((real_qmax_mah * 100 / design_capacity))
    local lock_diff=0; [ "$real_qmax_mah" -gt 0 ] && [ "$real_fcc_mah" -gt 0 ] && lock_diff=$(( (real_qmax_mah - real_fcc_mah) * 100 / real_qmax_mah ))
    local lock_cap_diff=0; [ "$real_qmax_mah" -gt 0 ] && [ "$fcc" -gt 0 ] && lock_cap_diff=$(( (real_qmax_mah - fcc) * 100 / real_qmax_mah ))

    cat <<EOF
{
  "capacity": $cap,
  "voltage": $voltage,
  "temperature": $temperature,
  "design_capacity": $design_capacity,
  "fcc": $fcc,
  "cycle_count": $cycle,
  "health": $health,
  "real_qmax": $real_qmax_mah,
  "real_fcc": $real_fcc_mah,
  "real_health": $real_health,
  "ir": $ir,
  "fast_charge_health": $fast_health,
  "lock_diff": $lock_diff,
  "lock_cap_diff": $lock_cap_diff
}
EOF
}

battery_detail15_info() {
    local cap=$(safe_cat /sys/class/power_supply/battery/capacity 0)
    local volt_raw=$(safe_cat /sys/class/power_supply/battery/voltage_now 0)
    local temp_raw=$(safe_cat /sys/class/power_supply/battery/temp 0)
    local design_raw=$(safe_cat /sys/class/oplus_chg/battery/design_capacity 0)
    local fcc_raw=$(safe_cat /sys/class/oplus_chg/battery/battery_fcc 0)
    local cc=$(safe_cat /sys/class/oplus_chg/battery/battery_cc 0)
    local soh=$(safe_cat /sys/class/oplus_chg/battery/battery_soh 0)
    local manu=$(safe_cat /sys/class/oplus_chg/battery/battery_manu_date)
    local sn=$(safe_cat /sys/class/oplus_chg/battery/battery_sn)

    local voltage=$(awk "BEGIN{printf \"%.2f\", $volt_raw/1000000}" 2>/dev/null || echo "0.00")
    local temperature=$(awk "BEGIN{printf \"%.1f\", $temp_raw/10}" 2>/dev/null || echo "0.0")
    local design_capacity=$((design_raw)); local fcc=$((fcc_raw / 1000))
    local health=0; [ "$design_raw" -gt 0 ] && health=$((fcc_raw * 100 / design_raw))

    local model=$(getprop ro.product.model); local android=$(getprop ro.build.version.release); local brand=$(getprop ro.product.brand)

    cat <<EOF
{
  "capacity": $cap,
  "voltage": $voltage,
  "temperature": $temperature,
  "design_capacity": $design_capacity,
  "fcc": $fcc,
  "cycle_count": $cc,
  "soh": $soh,
  "health": $health,
  "manufacture_date": "$manu",
  "serial": "$sn",
  "model": "$model",
  "android": "$android",
  "brand": "$brand"
}
EOF
}

perform_clean() {
    log_info "执行缓存清理"
    rm -rf /data/data/*/cache/* 2>/dev/null
    rm -rf /data/data/*/code_cache/* 2>/dev/null
    rm -rf /data/user/0/*/cache/* 2>/dev/null
    rm -rf /data/user_de/0/*/cache/* 2>/dev/null
    log_info "缓存清理完成"
}

perform_fstrim_with_frequency() {
    local freq=$(get_config fstrim_frequency 1)
    local now=$(date +%s); local last_fstrim=$(safe_cat $MODPATH/.last_fstrim 0); local interval=14400
    [ "$freq" = "0" ] && interval=3600; [ "$freq" = "2" ] && interval=43200
    [ $((now-last_fstrim)) -ge $interval ] && { log_info "执行 fstrim"; fstrim -v /data 2>&1 | log_info; echo $now > $MODPATH/.last_fstrim; }
}

perform_android_data_clean() {
    local enable=$(get_config android_data_clean 1); [ "$enable" != "1" ] && return
    log_info "执行 Android/data 清理"
    local threshold=$(get_config data_cache_threshold_mb 100); local skip=$(get_config skip_apps "com.tencent.mm,com.taobao.taobao")
    for d in /data/media/0/Android/data/*; do
        [ -d "$d" ] || continue
        local pkg=$(basename "$d")
        if echo ",$skip," | grep -q ",$pkg,"; then log_debug "跳过 $pkg"; continue; fi
        local size=$(du -sm "$d" 2>/dev/null | cut -f1)
        [ "$size" -gt "$threshold" ] && { rm -rf "$d/cache" "$d/files/.cache" "$d/no_backup" 2>/dev/null; log_info "清理 $pkg"; }
    done
    date +%s > $MODPATH/.last_data_clean
}

perform_background_control() {
    local mode=$(get_config background_control_mode 1); [ "$mode" = "0" ] && return
    log_debug "后台管控模式 $mode"; [ "$mode" -ge 2 ] && echo 32 > /proc/sys/kernel/pid_max 2>/dev/null
}

perform_dex2oat_optimization() {
    [ "$(get_config dex2oat_optimization 1)" = "0" ] && return
    log_debug "执行 dex2oat 优化"; setprop pm.dexopt.boot verify 2>/dev/null; setprop pm.dexopt.install quicken 2>/dev/null
}

calculate_smoothness_score() {
    local cpu_usage=$(get_cpu_all | grep usage | cut -d= -f2); local mem_avail=$(get_ram_info | grep avail | cut -d= -f2)
    local score=100; local cpu_int=0 mem_int=0
    [ -n "$cpu_usage" ] && cpu_int=${cpu_usage%.*} && [ -z "$cpu_int" ] && cpu_int=0
    [ -n "$mem_avail" ] && mem_int=${mem_avail%.*} && [ -z "$mem_int" ] && mem_int=0
    [ "$cpu_int" -gt 80 ] 2>/dev/null && score=$((score - (cpu_int - 80) / 2))
    [ "$mem_int" -lt 2 ] 2>/dev/null && score=$((score - (2 - mem_int) * 10))
    [ $score -lt 0 ] && score=0
    echo "score=$score" > $MODPATH/.smoothness_score
    echo "improvement=$((100 - score))" >> $MODPATH/.smoothness_score
}

check_custom_clean_times() {
    local times=$(get_config custom_clean_times "03:00,15:30"); local now=$(date +%H:%M)
    echo "$times" | grep -q "$now" && return 0 || return 1
}

check_device_compatibility() { return 0; }

perform_optimize() {
    log_info "执行手动性能优化"; optimize_io_scheduler; optimize_read_ahead; optimize_cpu_governor; optimize_gpu; optimize_power_save; log_info "性能优化完成"
}

get_gpu_info() {
    local platform="$1"; local freq="0" load="0"
    case $platform in
        adreno)
            base="/sys/class/kgsl/kgsl-3d0"
            freq=$(safe_cat $base/gpuclk 0); [ "$freq" -gt 0 ] && freq=$((freq/1000000))
            load_raw=$(safe_cat $base/gpu_busy_percentage 0); load=$(echo "$load_raw" | sed 's/%//g' | tr -d ' ')
            ;;
        mali_9300)
            freq_node="/sys/kernel/thermal/gpu_freq"; load_node="/sys/kernel/ged/hal/gpu_utilization"
            freq_raw=$(safe_cat $freq_node 0); freq_val=$(echo "$freq_raw" | grep -o '[0-9]\+' | head -1)
            [ -n "$freq_val" ] && freq=$((freq_val/1000000)) && [ $freq -eq 0 ] && [ $freq_val -gt 1000 ] && freq=$((freq_val/1000))
            load_raw=$(safe_cat $load_node 0); load_val=$(echo "$load_raw" | grep -o '[0-9]\+' | head -1)
            [ -n "$load_val" ] && [ $load_val -gt 100 ] && load_val=$((load_val/10)) && load="$load_val"
            ;;
        mali_8100)
            freq_node="/sys/kernel/gpu/gpu_cur_freq"; load_node="/sys/kernel/gpu/gpu_busy"
            freq_raw=$(safe_cat $freq_node 0); freq_val=$(echo "$freq_raw" | grep -o '[0-9]\+' | head -1)
            [ -n "$freq_val" ] && freq=$((freq_val/1000000)) && [ $freq -eq 0 ] && [ $freq_val -gt 1000 ] && freq=$((freq_val/1000))
            load_raw=$(safe_cat $load_node 0); load_val=$(echo "$load_raw" | grep -o '[0-9]\+' | head -1)
            [ -n "$load_val" ] && [ $load_val -gt 100 ] && load_val=$((load_val/10)) && load="$load_val"
            ;;
    esac
    [ -z "$freq" ] && freq=0; [ -z "$load" ] && load=0
    echo "freq=$freq"; echo "load=$load"
}