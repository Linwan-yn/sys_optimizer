# 智能系统优化模块 1.3-正式版

## 📋 模块信息
- **模块名称**：智能系统优化模块 (深度保养版)
- **版本**：1.3-正式版
- **作者**：林挽
- **支持 Root 方案**：Magisk (官方/Alpha/Delta/Kitsune)、KernelSU、APatch
- **Android 版本要求**：Android 10+ (API 29+)

## 📁 模块目录结构
```

/data/adb/modules/sys_optimizer_webui/
├── module.prop                 # 模块属性
├── action.sh                   # 一键维护脚本
├── service.sh                  # 主服务脚本
├── post-fs-data.sh             # 启动后脚本
├── uninstall.sh                # 卸载脚本
├── common/
│   ├── config.conf             # 配置文件
│   ├── functions.sh            # 核心函数库
│   ├── oiface_ctl.sh           # oiface 控制脚本
│   ├── f2fs_gc_daemon.sh       # F2FS 垃圾回收守护
│   ├── clean_rules.conf        # 文件清理规则文件
│   ├── cell_type.conf          # 电芯类型配置
│   ├── aling_type.conf         # 阿灵子类型配置
│   ├── whitelist.conf          # 白名单持久化文件
│   └── removed_whitelist.conf  # 已移除白名单记忆文件
├── webroot/                    # WebUI 文件
│   ├── index.html
│   ├── style.css
│   ├── app.js
│   ├── kernelsu.js
│   ├── config.json
│   └── KsuWebUI_1.0.apk
├── logs/                        # 日志目录
│   ├── service.log              # 主服务日志
│   ├── f2fs_gc_daemon.log       # F2FS 回收日志
│   └── battery_history.log      # 电池历史记录
└── OS/                          # 文档目录
├── README.md
└── 简介.txt

```

## ⚙️ 配置说明
编辑 `/data/adb/modules/sys_optimizer_webui/common/config.conf` 后重启生效。以下列出所有可用配置项、默认值及详细说明。

### 📊 基础清理
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `clean_interval` | 14400 | 自动缓存清理间隔（秒），4小时一次 | 保持默认 |
| `enable_fstrim` | 1 | 启用 FSTRIM 磁盘整理（0=禁用，1=启用） | 保持启用 |
| `fstrim_frequency` | 1 | FSTRIM 频率：0=1小时，1=4小时，2=12小时 | 一般保持1 |
| `android_data_clean` | 1 | 启用 Android/data 目录清理（0=禁用，1=启用） | 保持启用 |
| `data_cache_threshold_mb` | 100 | 触发清理的缓存大小阈值（MB） | 可适当降低至50 |
| `skip_apps` | com.tencent.mm,com.taobao.taobao | 跳过清理的包名（逗号分隔） | 按需添加 |
| `custom_clean_times` | 03:00,15:30 | 自定义清理时间（HH:MM,HH:MM） | 按需修改 |

### 🚀 性能调优
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `background_control_mode` | 1 | 后台管控模式：0=关，1=轻度，2=中度，3=严格 | 轻度平衡续航与性能 |
| `enable_io_opt` | 1 | I/O 调度优化开关 | 保持启用 |
| `enable_read_ahead` | 1 | 动态预读优化开关 | 保持启用 |
| `enable_cpu_gov` | 1 | CPU 调频优化开关 | 保持启用 |
| `enable_gpu_opt` | 1 | GPU 调频优化开关 | 保持启用 |
| `enable_power_save` | 1 | 节能参数优化开关 | 日常建议启用 |

### 🔋 电池相关
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `battery_source` | auto | 电池数据源：auto/qcom/mtk/oplus/xiaomi/meizu/aling/shell_detailed/xuantian_v2/xuantian_auto/detail15 | 自动检测即可 |
| `enable_battery_health_diagnosis` | 1 | 电池健康诊断开关（锁容检测等） | 保持启用 |
| `enable_battery_unlock` | 0 | 解容功能（高风险） | **强烈建议禁用** |
| `enable_deep_cycle_counter` | 1 | 深度循环计数开关 | 保持启用 |
| `enable_mod_battery_detection` | 1 | 魔改电池检测开关 | 保持启用 |
| `enable_fast_charge_repair` | 1 | 快充健康修复开关 | 保持启用 |

### 🎮 GPU 监控
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `gpu_source` | auto | GPU 数据源：auto/adreno/mali | 自动检测 |

### 🛡️ 高级功能
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `process_suppress_mode` | 0 | 进程压制模式：0=关，1=轻度(息屏)，2=激进(始终) | 日常保持0 |
| `process_suppress_adj` | 800 | oom_score_adj 压制阈值 | 保持默认 |
| `smart_avoid_packages` | com.tencent.mm,com.tencent.mobileqq | 智能避让包名 | 按需添加 |
| `memory_lock_dirs` | (空) | 内存压制目录（分号分隔） | 高级用户使用 |
| `adblock_enable` | 0 | 广告拦截开关 | 启用可能影响部分应用 |
| `adblock_update_interval` | 86400 | 广告规则更新间隔（秒） | 保持默认 |
| `file_clean_rules` | /data/adb/modules/sys_optimizer_webui/common/clean_rules.conf | 文件清理规则路径 | 保持默认 |
| `whitelist_restore_delay` | 60 | 白名单恢复延迟（秒），开机后等待指定秒数再恢复白名单，避免被系统覆盖 | 默认60，可根据需要调整 |

### 🗑️ F2FS 相关
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `f2fs_dirty_threshold_mb` | 5000 | F2FS 脏块触发阈值（MB） | 保持默认 |
| `enable_f2fs_daemon` | 0 | F2FS 垃圾回收守护开关 | data分区为F2FS时可启用 |
| `f2fs_gc_sleep` | 60 | 每次回收最大持续时间（秒） | 保持默认 |
| `f2fs_check_interval` | 180 | 屏幕检测间隔（秒） | 保持默认 |

### 📝 日志设置
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `log_level` | 1 | 日志级别：0=无，1=普通，2=调试 | 普通用户保持1 |
| `log_retention_days` | 7 | 日志保留天数 | 保持默认 |

### 📊 存储警告
| 配置项 | 默认值 | 说明 | 建议 |
|--------|--------|------|------|
| `storage_warning` | 85 | 存储警告阈值（%） | 保持默认 |
| `storage_critical` | 95 | 存储严重阈值（%） | 保持默认 |

---

## 🌐 WebUI 访问
### KernelSU
- 在模块列表中找到本模块，点击卡片上的「WebUI」按钮即可打开控制台。

### Magisk
1. 安装 [KsuWebUI](https://github.com/5ec1cff/KsuWebUI) 应用（模块安装时会自动尝试安装，如果失败请手动安装）。
2. 打开 KsuWebUI，点击「本地页面」。
3. 选择「智能系统优化模块」即可打开控制台。

### APatch
- 与 KernelSU 类似，需要安装支持 WebUI 的管理器应用。

## ✨ 主要功能

### 🏠 首页
- 服务状态、运行时间、清理统计
- 流畅度评分
- 设备信息、存储状态概览

### ⚙️ 系统
- **SELinux 管理**：查看/切换强制/宽容模式
- **F2FS 垃圾回收**：启动强制回收、查看回收日志
- **配置管理**：详细配置选项（可折叠）
- **快速操作**：缓存清理、Android/data清理、性能优化、重启服务
- **实时日志**：查看主服务日志

### ⚡ 性能
- **oiface 性能模式**：禁用/普通/特殊模式切换
- **运行内存监控**：总内存、已用、可用、使用率
- **CPU 监控**：实时负载、各核心频率
- **GPU 监控**：实时负载、频率（支持Adreno/Mali选择）
- **流畅度评分**：系统流畅度评估

### 🔋 电池
- **实时状态**：电量、电压、电流、温度、功率、充电协议
- **电池健康**：设计容量、当前满容、剩余容量、SOH、循环次数
- **锁容检测**：自动检测并提示容量锁定
- **数据源选择**：支持酷安详细版、阿灵、玄天宝镜(v2/自动版)、电池使用详情1.5
- **电芯配置**：单/双电芯切换（针对不同数据源）
- **电池优化白名单**：查看/添加/移除应用（支持持久化记忆，被移除的应用会自动记录，重启后强制移除）
- **高级配置**：充电检测模式、低电压自动关机、通知设置、历史记录等
- **电池历史曲线**：查看电量、电压、电流、温度历史变化

### 👤 我的
- 模块信息、版本、作者
- 更新地址
- 反馈方式、日志路径

## 📱 ColorOS 专属功能
如果检测到系统已安装 `com.coloros.phonemanager`，将在系统页自动显示 ColorOS 功能卡片，提供以下快捷入口：
- **性能平台**：快速进入 ColorOS 性能设置
- **久用保养**：电池保养相关设置
- **网络检测**：网络诊断工具

## 🗑️ 文件清理规则
编辑 `common/clean_rules.conf` 可自定义文件清理规则，每行格式：
```

路径|文件名模式

```
示例：
```

/storage/emulated/0/Download|.tmp
/data/local/tmp|.log

```

## 📋 白名单记忆机制
- 通过 WebUI 手动添加的应用，会被保存到 `whitelist.conf`，开机后自动恢复。
- 通过 WebUI 手动移除的应用，会被记录到 `removed_whitelist.conf`，每次开机后会强制移除（即使系统或其他应用再次添加）。
- 这解决了某些毒瘤应用（如拼多多）重启后被系统重新加入白名单的问题。

## 🚨 重要提示
- **本模块涉及系统底层修改**，使用前请充分了解各项功能的作用，建议提前备份重要数据。
- 如遇到任何问题，可先尝试在 WebUI 中关闭相应优化开关，或卸载模块后重启手机。
- 模块为开源分享，作者不对因使用本模块造成的任何损失承担责任。
- 部分功能（如解容、进程压制等）可能影响系统稳定性，请谨慎使用。

## 📥 下载更新
最新版本及更新日志请访问：
[https://www.123684.com/s/2dUzTd-nypUv](https://www.123684.com/s/2dUzTd-nypUv)

## 🗑️ 卸载
在 Magisk/KernelSU 管理器中移除模块即可。卸载时配置会自动备份至：
```

/sdcard/SysOptimizer_Backup_YYYYMMDD_HHMMSS/

```
如需恢复配置，将备份的 `config.conf` 复制回模块目录并重启即可。

## 📞 反馈
- 酷安：@林挽2009
- 反馈时请附上以下日志文件：
  - `/data/adb/modules/sys_optimizer_webui/logs/service.log`
  - `/data/adb/modules/sys_optimizer_webui/logs/f2fs_gc_daemon.log`

---

**感谢使用智能系统优化模块！** 🎉
