# luci-app-usb-pcie-scan

OpenWrt LuCI 插件：USB / PCIe 设备扫描与驱动挂载识别工具。

菜单位置：**系统 → USB/PCIe 设备扫描**

## 功能

### USB 设备

- `lsusb` 硬件识别（VID:PID 列表）
- `lsusb -t` 设备树 / 驱动挂载关系
- `lsusb -v` 设备详细信息
- `cat /sys/kernel/debug/usb/devices` 内核调试视图（debugfs 未挂载时自动挂载）
- **驱动临时挂载**：VID/PID 可手写输入，也可点「从 lsusb 提取」从扫描结果中下拉选择设备，实时生成四条命令预览：

  ```sh
  echo "12d1 1506" > /sys/bus/usb-serial/drivers/option/new_id
  echo "12d1 1506" > /sys/bus/usb-serial/drivers/option1/new_id
  echo "12d1 1506" > /sys/bus/usb-serial/drivers/option_1/new_id
  echo "12d1 1506" > /sys/bus/usb-serial/drivers/generic/new_id
  ```

  每个驱动一个「临时挂载」按钮（挂载成功后出现 `/dev/ttyUSB*` 串口）
- **一键加入 rc.local**：把挂载命令写入 `/etc/rc.local` 的 `exit 0` 之前，实现开机自动挂载（重复命令自动跳过）

### PCIe 设备

- `lspci` 硬件识别
- `lspci -v` 设备详细信息（含 Kernel driver in use）
- `lspci -t` 总线树 / 驱动挂载

## 源码结构

```
luci-app-usb-pcie-scan/
├── Makefile                     # OpenWrt 包定义 (PKG_NAME/LUCI_DEPENDS)
├── .gitattributes               # 强制 LF 换行 (ucode LuCI 模板解析必需)
├── luasrc/
│   ├── controller/
│   │   └── usb_pcie_scan.lua    # 菜单路由 + scan/bind/rclocal 三个 action
│   └── view/
│       └── usb_pcie_scan/
│           └── main.htm         # USB / PCIe 双标签页界面
└── root/
    ├── etc/uci-defaults/
    │   └── 99-luci-usb-pcie-scan            # 安装后清 LuCI 缓存，菜单立即可见
    └── usr/share/rpcd/acl.d/
        └── luci-app-usb-pcie-scan.json     # rpcd ACL (19.07+ 菜单鉴权必需)
```

路径映射遵循 luci.mk 约定：`luasrc/` → `/usr/lib/lua/luci/`，`root/` → `/`。

## 安装

```sh
opkg update
opkg install ./luci-app-usb-pcie-scan_1.0.0-1_all.ipk
```

依赖：`luci-compat`、`usbutils`（lsusb）、`pciutils`（lspci）。

安装后刷新 LuCI 页面即可看到菜单；若未出现，执行：

```sh
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
```

## 使用说明

1. **USB 标签页**自动加载 `lsusb`、`lsusb -t`、`lsusb -v` 与内核调试视图。
2. 在「驱动临时挂载 / 开机自启」区：
   - 手动填写十六进制 VID/PID，或点「从 lsusb 提取」从下拉框选择扫描到的设备；
   - 下方实时预览四条 `new_id` 挂载命令；
   - 点「临时挂载 xxx」立即生效；点「加入 rc.local」写入开机脚本。
3. **PCIe 标签页**点「刷新全部」加载 `lspci` 三种视图。

注意：

- 四个驱动按钮是否可用取决于本机已加载的 usb-serial 驱动（查看 `/sys/bus/usb-serial/drivers/`），目录不存在时按钮会明确提示「该驱动未加载」。
- 挂载命令立即生效但不持久，重启失效；需要开机生效请点「加入 rc.local」。

## 兼容性说明

- 兼容 Lua LuCI（luci-compat）与 ucode LuCI（24.10+，经 ucodebridge 运行 Lua controller）。
- **模板文件必须 LF 换行**：ucode LuCI 的模板解析器遇到 CRLF 的 `.htm` 会报 `Syntax error ... unfinished string`。仓库已用 `.gitattributes` 强制 `eol=lf`。

## License

MIT
