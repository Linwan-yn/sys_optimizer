#!/system/bin/sh
SKIPUNZIP=1
grep_prop() {
    local REGEX="s/^$1=//p"
    shift
    local FILES=$@
    [ -z "$FILES" ] && FILES='/system/build.prop'
    cat $FILES 2>/dev/null | dos2unix 2>/dev/null | sed -n "$REGEX" | head -n 1
}
extract() {
    local zip=$1
    local file=$2
    local dest=$3
    local dir=$(dirname "$file")
    [ -z "$dest" ] && dest="$MODPATH/$file"
    [ -z "$dir" ] || mkdir -p "$MODPATH/$dir" "$(dirname "$dest")"
    unzip -o -q "$zip" "$file" -d "$MODPATH" >&2
    [ -f "$MODPATH/$file" ] && [ "$MODPATH/$file" != "$dest" ] && mv "$MODPATH/$file" "$dest"
}
set_perm() {
    local PATH=$1
    local UID=$2
    local GID=$3
    local MODE=$4
    chown $UID:$GID "$PATH" 2>/dev/null
    chmod $MODE "$PATH" 2>/dev/null
}
set_perm_recursive() {
    local PATH=$1
    local UID=$2
    local GID=$3
    local DMODE=$4
    local FMODE=$5
    find "$PATH" -type d 2>/dev/null | xargs chown $UID:$GID 2>/dev/null
    find "$PATH" -type d 2>/dev/null | xargs chmod $DMODE 2>/dev/null
    find "$PATH" -type f 2>/dev/null | xargs chown $UID:$GID 2>/dev/null
    find "$PATH" -type f 2>/dev/null | xargs chmod $FMODE 2>/dev/null
}
volume_choice() {
    local prompt="$1"
    local default="$2"
    ui_print "----------------------------------------"
    ui_print "$prompt"
    ui_print "   音量+ 确认，音量- 跳过，等待30秒..."
    ui_print "----------------------------------------"
    timeout 0.1 getevent -c 0 >/dev/null 2>&1
    local end=$(( $(date +%s) + 30 ))
    local key_pressed=""
    while [ $(date +%s) -lt $end ] && [ -z "$key_pressed" ]; do
        local input
        input=$(timeout 0.5 getevent -l -c 1 2>&1 | grep -v "add device")
        if echo "$input" | grep -q "KEY_VOLUMEUP"; then
            key_pressed="UP"
        elif echo "$input" | grep -q "KEY_VOLUMEDOWN"; then
            key_pressed="DOWN"
        fi
    done
    if [ "$key_pressed" = "UP" ]; then
        timeout 0.5 getevent -c 0 >/dev/null 2>&1
        sleep 0.5
        ui_print "  已选择 音量+"
        return 0
    elif [ "$key_pressed" = "DOWN" ]; then
        timeout 0.5 getevent -c 0 >/dev/null 2>&1
        sleep 0.5
        ui_print "  已选择 音量-"
        return 1
    else
        [ "$default" = "+" ] && { ui_print "  超时，默认选择 音量+"; return 0; }
        ui_print "  超时，默认选择 音量-"; return 1
    fi
}
detect_sys() {
    [ -n "$(getprop ro.oplus.version)" -o -n "$(getprop ro.oppo.version)" ] && { echo coloros; return; }
    [ -n "$(getprop ro.miui.ui.version.name)" -a -z "$(getprop ro.build.version.hyperos)" ] && { echo miui; return; }
    [ -n "$(getprop ro.build.version.hyperos)" ] && { echo hyperos; return; }
    [ -n "$(getprop ro.samsung.version)" ] && { echo oneui; return; }
    [ -n "$(getprop ro.vivo.os.version)" ] && { echo funtouch; return; }
    [ -n "$(getprop ro.realme.version)" ] && { echo realmeui; return; }
    echo aosp
}
detect_cpu() {
    data=$(for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        c=$(cat "$p/related_cpus" 2>/dev/null)
        f=$(cat "$p/cpuinfo_max_freq" 2>/dev/null)
        [ -n "$c" ] && [ -n "$f" ] && echo "$f:$c"
    done | sort -n -t: -k1,1)
    [ -z "$data" ] && return
    echo "$data" | awk -F: '
    {cores[NR]=$2;freq[NR]=$1}
    END {
        n=NR;if(n==1){e=cores[1];e_f=freq[1];m="";m_f=0;p="";p_f=0;h=cores[1];h_f=freq[1]}
        else if(n==2){e=cores[1];e_f=freq[1];m="";m_f=0;p="";p_f=0;h=cores[2];h_f=freq[2]}
        else if(n==3){e=cores[1];e_f=freq[1];m=cores[2];m_f=freq[2];p="";p_f=0;h=cores[3];h_f=freq[3]}
        else {
            e=cores[1];e_f=freq[1];m=cores[2];m_f=freq[2];p=cores[3];p_f=freq[3];h=cores[4];h_f=freq[4]
            for(i=5;i<=n;i++){h=h" "cores[i];if(freq[i]>h_f)h_f=freq[i]}
        }
        printf "e_core=\"%s\";e_freq=%d\nm_core=\"%s\";m_freq=%d\np_core=\"%s\";p_freq=%d\nh_core=\"%s\";h_freq=%d\n",e,e_f,m,m_f,p,p_f,h,h_f
    }'
}
format_cpu_ranges() {
    [ -z "${1// /}" ] && { cat /sys/devices/system/cpu/present 2>/dev/null || echo "0"; return; }
    awk -v input="$1" 'BEGIN {
        n=split(input,arr,/[[:space:]]+/);for(i=1;i<=n;i++)if(arr[i]!="")nums[++j]=arr[i]+0
        n=j;if(!n)exit;for(i=1;i<n;i++){min=i;for(j=i+1;j<=n;j++)if(nums[j]<nums[min])min=j
        if(min!=i){t=nums[i];nums[i]=nums[min];nums[min]=t}}
        start=last=nums[1];sep="";for(i=2;i<=n;i++){
            if(nums[i]==last+1){last=nums[i];continue}
            printf "%s%s",sep,(start==last?start:start"-"last);sep=",";start=last=nums[i]
        }
        printf "%s%s",sep,(start==last?start:start"-"last)
    }'
}
get_magisk_type() {
    if [ -n "$KSU" ]; then echo "KernelSU/Next"; return; fi
    if [ -n "$APATCH" ]; then echo "APatch"; return; fi
    if [ -f /data/adb/magisk/util_functions.sh ]; then
        local ver=$(grep_prop version /data/adb/magisk/module.prop 2>/dev/null)
        [ -n "$(echo $0 | grep vvb2060)" ] && echo "Magisk Delta" || echo "Magisk Official($ver)"
        return
    fi
    echo "Unknown"
}
[ -z "$ZIPFILE" ] && ZIPFILE="$3"
[ -z "$MODPATH" ] && MODPATH="/data/adb/modules/$(grep_prop id module.prop 2>/dev/null || echo sys_optimizer_webui)"
[ -z "$TMPDIR" ] && TMPDIR="/dev/tmp"
mkdir -p "$MODPATH" "$TMPDIR"
ui_print "*********************************************"
ui_print "智能系统优化模块 (深度保养版) by 林挽"
ui_print "模块版本: 1.3-正式版"
ui_print "*********************************************"
ui_print "设备型号: $(getprop ro.product.manufacturer) $(getprop ro.product.model)"
ui_print "Android版: $(getprop ro.build.version.release) (API $(getprop ro.build.version.sdk))"
ui_print "Root框架: $(get_magisk_type)"
SYS_TYPE=$(detect_sys)
ui_print "系统类型: $SYS_TYPE"
eval "$(detect_cpu)"
[ -n "$e_core" ] && ui_print "小核(LITTLE): $(format_cpu_ranges "$e_core") (max $((e_freq/1000)) MHz)"
[ -n "$m_core" ] && ui_print "中核(MID)   : $(format_cpu_ranges "$m_core") (max $((m_freq/1000)) MHz)"
[ -n "$p_core" ] && ui_print "大核(BIG)   : $(format_cpu_ranges "$p_core") (max $((p_freq/1000)) MHz)"
[ -n "$h_core" ] && ui_print "超大核(ULTRA): $(format_cpu_ranges "$h_core") (max $((h_freq/1000)) MHz)"
ui_print "*********************************************"
ui_print "- 开始提取模块文件..."
extract "$ZIPFILE" "module.prop"
extract "$ZIPFILE" "post-fs-data.sh"
extract "$ZIPFILE" "service.sh"
extract "$ZIPFILE" "uninstall.sh"
extract "$ZIPFILE" "action.sh" 2>/dev/null
extract "$ZIPFILE" "common/clean_rules.conf"
extract "$ZIPFILE" "common/config.conf"
extract "$ZIPFILE" "common/f2fs_gc_daemon.sh"
extract "$ZIPFILE" "common/functions.sh"
extract "$ZIPFILE" "common/oiface_ctl.sh" 2>/dev/null
extract "$ZIPFILE" "common/玄天宝镜-电池检测-v2.sh"
extract "$ZIPFILE" "common/玄天宝镜-全自动真实容量版.sh"
# 移除 app_browser.js 提取
extract "$ZIPFILE" "webroot/app.js"
extract "$ZIPFILE" "webroot/config.json"
extract "$ZIPFILE" "webroot/index.html"
extract "$ZIPFILE" "webroot/kernelsu.js"
extract "$ZIPFILE" "webroot/style.css"
extract "$ZIPFILE" "webroot/KsuWebUI_1.0.apk" 2>/dev/null
extract "$ZIPFILE" "OS/README.md" 2>/dev/null
extract "$ZIPFILE" "OS/简介.txt" 2>/dev/null
ui_print "- 模块文件提取完成"
OLD_MODULE_ID="sys_optimizer_webui"
OLD_MODPATH="/data/adb/modules/$OLD_MODULE_ID"
CONFIG_SAVED=false
BACKUP_DIR="/data/local/tmp/sysopt_backup_$(date +%Y%m%d_%H%M%S)"
real_old=false
if [ -d "$OLD_MODPATH" ] && [ -f "$OLD_MODPATH/module.prop" ]; then
    old_id=$(grep_prop id "$OLD_MODPATH/module.prop")
    [ "$old_id" = "$OLD_MODULE_ID" ] && real_old=true
fi
if [ "$real_old" = true ]; then
    ui_print "- 检测到旧版本，开始迁移配置数据..."
    mkdir -p "$BACKUP_DIR/common" 2>/dev/null
    if volume_choice "是否还原旧版config.conf配置文件？（新版建议不还原）" "-"; then
        if [ -f "$OLD_MODPATH/common/config.conf" ]; then
            cp -f "$OLD_MODPATH/common/config.conf" "$MODPATH/common/config.conf" 2>/dev/null
            cp -f "$OLD_MODPATH/common/config.conf" "$BACKUP_DIR/common/" 2>/dev/null
            ui_print "✓ 旧版配置已还原并备份"
            CONFIG_SAVED=true
        else
            ui_print "⚠ 旧版配置文件不存在，使用默认配置"
        fi
    else
        ui_print "- 选择不还原旧配置，使用模块默认配置"
    fi
    ui_print "- 还原模块运行状态文件..."
    for f in .clean_count .last_clean .last_fstrim .last_data_clean .last_custom_clean .service.uptime .service.start_time; do
        [ -f "$OLD_MODPATH/$f" ] && cp -f "$OLD_MODPATH/$f" "$MODPATH/$f" 2>/dev/null && cp -f "$OLD_MODPATH/$f" "$BACKUP_DIR/" 2>/dev/null
    done
    ui_print "✓ 状态文件还原完成，备份路径: $BACKUP_DIR"
else
    ui_print "- 未检测到旧版本，执行全新安装"
fi
if [ "$CONFIG_SAVED" != "true" ]; then
    ui_print "- 根据系统类型优化默认配置..."
    CONF_FILE="$MODPATH/common/config.conf"
    [ ! -f "$CONF_FILE" ] && { echo "" > "$CONF_FILE"; set_perm "$CONF_FILE" 0 0 0644; }
    case $SYS_TYPE in
        coloros|realmeui|funtouch) fstrim_freq=0; bg_mode=2 ;;
        hyperos|miui) fstrim_freq=1; bg_mode=2 ;;
        oneui) fstrim_freq=2; bg_mode=1 ;;
        *) fstrim_freq=1; bg_mode=1 ;;
    esac
    grep -q '^fstrim_frequency=' "$CONF_FILE" && sed -i "s/^fstrim_frequency=.*/fstrim_frequency=$fstrim_freq/" "$CONF_FILE" || echo "fstrim_frequency=$fstrim_freq" >> "$CONF_FILE"
    grep -q '^background_control_mode=' "$CONF_FILE" && sed -i "s/^background_control_mode=.*/background_control_mode=$bg_mode/" "$CONF_FILE" || echo "background_control_mode=$bg_mode" >> "$CONF_FILE"
    sed -i '/^install_date=/d' "$CONF_FILE" && echo "install_date=$(date +%Y-%m-%d_%H:%M:%S)" >> "$CONF_FILE"
    ui_print "✓ 系统适配完成: fstrim_freq=$fstrim_freq | bg_mode=$bg_mode"
fi
if [ -f "$MODPATH/webroot/KsuWebUI_1.0.apk" ]; then
    if volume_choice "是否安装KsuWebUI可视化管理应用？" "+"; then
        ui_print "- 开始安装KsuWebUI..."
        pm install -r -q "$MODPATH/webroot/KsuWebUI_1.0.apk" 2>/dev/null
        if [ $? -eq 0 ]; then
            ui_print "✓ KsuWebUI安装成功"
            rm -f "$MODPATH/webroot/KsuWebUI_1.0.apk"
        else
            ui_print "⚠ KsuWebUI安装失败，请手动安装APK文件"
        fi
    else
        ui_print "- 选择不安装KsuWebUI，保留APK文件"
    fi
fi
ui_print "- 开始设置模块文件权限..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
find "$MODPATH" -name "*.sh" -type f 2>/dev/null | xargs chmod 0755 2>/dev/null
set_perm "$MODPATH/common/config.conf" 0 0 0644
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
ui_print "- 权限设置完成"
ui_print "*********************************************"
ui_print "✅ 智能系统优化模块安装成功！"
ui_print "📌 模块生效路径: $MODPATH"
ui_print "💡 请重启手机，模块即可正式生效"
ui_print "*********************************************"
rm -rf "$TMPDIR/sysopt_tmp" 2>/dev/null
exit 0