# OpenWrt LuCI 插件合集

本仓库包含三个面向 OpenWrt LuCI 的实用插件（经典 Lua 控制器，架构无关 `all`），
均为标准 OpenWrt 编译源码树，既可在 buildroot / SDK 中编译，也提供已构建的 `.ipk`
可直接安装。

仓库地址：<https://gitee.com/qlljcf666/my-ipk>

## 插件一览

| 插件 | 版本 | 菜单位置 | 作用 | 额外依赖 |
|---|---|---|---|---|
| **luci-app-nxdb** | 1.0.0-1 | 系统 → IPK 逆向打包 | 从运行中的 rootfs 逆向重建已装软件的标准 `.ipk` | luci-compat |
| **luci-app-panel** | 2.0-1 | 顶级菜单 Device Panel | iframe 集中访问局域网设备 Web 后台，支持保存账号密码并自动/一键填充登录 | luci-compat |
| **luci-app-usb-pcie-scan** | 1.0.0-1 | 系统 → USB/PCIe 设备扫描 | USB/PCIe 硬件扫描、驱动临时挂载（new_id）、开机自启 | luci-compat, usbutils, pciutils |

> 三者都基于 `feeds/luci/luci.mk` 打包，`luci.mk` 会自动追加 `luci-lua-runtime`
> 依赖并生成清理 LuCI 缓存、`killall -HUP rpcd` 的 postinst。

---

## 一、仓库文件结构

```
my-ipk/
├── README.md                        # 本说明（总项目文档）
│
├── luci-app-nxdb/                   # 插件1：IPK 逆向打包
│   ├── Makefile                     #   OpenWrt 包定义（走 luci.mk）
│   ├── .gitattributes               #   强制 LF 换行
│   ├── README.md                    #   插件详细文档
│   ├── luasrc/                      #   → /usr/lib/lua/luci/
│   │   ├── controller/nxdb.lua      #   菜单路由 + data/files/pack/cancel/status/download
│   │   └── view/nxdb/main.htm       #   扫描/打包/进度/下载页面（原生 XHR）
│   └── root/                        #   → /
│       ├── etc/uci-defaults/99-luci-app-nxdb
│       ├── usr/libexec/nxdb/nxdb.sh #   busybox ash 打包后端（不依赖 ar/python）
│       └── usr/share/rpcd/acl.d/luci-app-nxdb.json
│
├── luci-app-panel/                  # 插件2：设备面板（当前版本 v2.0）
│   ├── Makefile
│   ├── .gitattributes
│   ├── README.md
│   ├── luasrc/
│   │   ├── controller/panel.lua     #   菜单 admin/panel + save/delete/get_config（读写 UCI panel）
│   │   └── view/panel/remote_admin.htm  # 侧边栏 + iframe + 增删改弹窗 + 凭据栏/自动填充
│   └── root/
│       ├── etc/config/panel         #   UCI 配置（general + device 节，含 username/password）
│       └── etc/uci-defaults/luci-app-panel  # 幂等播种示例设备
│
├── luci-app-usb-pcie-scan/          # 插件3：USB/PCIe 设备扫描
│   ├── Makefile
│   ├── .gitattributes
│   ├── README.md
│   ├── luasrc/
│   │   ├── controller/usb_pcie_scan.lua   # 菜单 + scan/bind/rclocal
│   │   └── view/usb_pcie_scan/main.htm    # USB/PCIe 双标签页
│   └── root/
│       ├── etc/uci-defaults/99-luci-usb-pcie-scan
│       └── usr/share/rpcd/acl.d/luci-app-usb-pcie-scan.json
│
├── luci-app-panel - 1.0/            # luci-app-panel 旧版（1.0.1）备份，仅供参考
│
├── luci-app-nxdb_1.0.0-1_all.ipk
├── luci-app-panel_2.0-1_all.ipk
├── luci-app-usb-pcie-scan_1.0.0-1_all.ipk
└── luci-app-panel-all.ipk           # 旧版 panel 1.0.x 产物（历史保留）
```

**统一约定**：

- 所有插件都是 `LUCI_PKGARCH:=all`（纯 Lua/HTML/Shell，架构无关，一个 ipk 全平台通用）。
- `luasrc/` → 安装到 `/usr/lib/lua/luci/`，`root/` → 安装到 `/`。
- 所有文本文件强制 **LF**（`.gitattributes` 兜底），否则 ucode LuCI（24.10+）
  解析 CRLF 的 `.htm` 会报 `unfinished string` 语法错误。
- 许可证均为 **MIT**。

---

## 二、插件作用与使用

### 1. luci-app-nxdb — IPK 逆向打包

设备上已装软件只有解压后的文件、没有原始 ipk 时，本插件扫描
`/usr/lib/opkg/info/*.control` 与 `*.list`，在 LuCI 页面勾选包后由后端
`nxdb.sh`（纯 busybox ash，仅用 tar/gzip/sed/awk）后台重建出标准 OpenWrt
ipk（gzip tar 外壳，成员顺序 `./debian-binary ./data.tar.gz ./control.tar.gz`）。

使用：

1. 进入 **系统 → IPK 逆向打包**，页面自动列出已装包（含缺失文件数提示）。
2. 点包名可查看每个文件条目的实时状态（文件/目录/符号链接/缺失）。
3. 勾选目标包，设置输出目录（默认 `/tmp/nxdb_ipk`，掉电丢失；要保留选 `/root` 或挂载盘）。
4. 点 **打包选中插件**，可随时停止；完成后在页面底部单击文件名直接下载。

### 2. luci-app-panel — 设备面板（v2.0）

在一个 LuCI 页面内通过 iframe 集中打开局域网内其他设备（5G 壳、光猫、AP 等）
的 Web 管理后台，免记地址端口。

- 点左上角 **+** 添加设备：标签、地址、端口，以及 v2.0 新增的
  **后台登录账号 / 密码**（可选）。配置存于 UCI `/etc/config/panel`。
- 单击设备卡片即在右侧 iframe 打开 `http://地址:端口`，支持刷新、新窗口打开、全屏、侧边栏折叠记忆。
- 连接已保存凭据的设备时：
  - **同源**（iframe 页面与 LuCI 同协议/主机/端口，如经反代挂载）：页面加载后
    自动填充账号密码（原生 setter + input/change 事件，兼容 React/Vue 登录框）；
  - **跨域**（浏览器同源策略禁止页面脚本访问 iframe DOM，属硬性安全限制）：
    iframe 上方显示凭据栏，账号明文、密码掩码，点 **Copy** 一键复制粘贴登录。
- 凭据以明文保存在 `/etc/config/panel`（与系统保存 PPPoE 密码方式相同），
  请勿在多人可登录的设备上存放高价值密码。

### 3. luci-app-usb-pcie-scan — USB/PCIe 设备扫描

调试 4G/5G 模组、串口卡等外设时快速识别硬件并处理驱动绑定：

- **USB 标签页**：`lsusb`（VID:PID）、`lsusb -t`（设备树/驱动挂载）、
  `lsusb -v`（详情）、内核 `/sys/kernel/debug/usb/devices` 调试视图。
- **驱动临时挂载**：手写 VID/PID 或点「从 lsusb 提取」下拉选择，实时预览
  `option / option1 / option_1 / generic` 四条 `new_id` 命令，逐驱动一键挂载，
  成功后出现 `/dev/ttyUSB*`；「加入 rc.local」可写入开机自启（重复命令自动跳过）。
- **PCIe 标签页**：`lspci` / `lspci -v`（含 Kernel driver in use）/ `lspci -t`。
- 临时挂载重启失效，需要持久化请使用「加入 rc.local」。

---

## 三、在线安装 ipk（路由器直接装）

### 方式 A：从 Gitee 下载后安装（推荐，免上传）

在路由器 SSH 中执行（以 panel 2.0 为例）：

```sh
opkg update
cd /tmp
wget --no-check-certificate \
  "https://gitee.com/qlljcf666/my-ipk/raw/master/luci-app-panel_2.0-1_all.ipk"
opkg install ./luci-app-panel_2.0-1_all.ipk
```

三个插件的直链（master 分支）：

```sh
# luci-app-nxdb
wget --no-check-certificate -O /tmp/nxdb.ipk \
  "https://gitee.com/qlljcf666/my-ipk/raw/master/luci-app-nxdb_1.0.0-1_all.ipk"

# luci-app-panel v2.0
wget --no-check-certificate -O /tmp/panel.ipk \
  "https://gitee.com/qlljcf666/my-ipk/raw/master/luci-app-panel_2.0-1_all.ipk"

# luci-app-usb-pcie-scan
wget --no-check-certificate -O /tmp/scan.ipk \
  "https://gitee.com/qlljcf666/my-ipk/raw/master/luci-app-usb-pcie-scan_1.0.0-1_all.ipk"
```

> 精简固件没有 `wget` 时可用 `curl -k -L -o /tmp/panel.ipk <URL>`；
> 也可以在电脑上下载 ipk 后用 scp 上传到路由器 `/tmp` 再 `opkg install`。
> 公司网络若拦截 Gitee 证书，先确认固件时间/CA 正常，或临时加
> `--no-check-certificate`（仅用于可信内网下载）。

### 方式 B：LuCI 网页上传安装

进入 **系统 → 软件包（Software）→ 上传软件包（Upload Package）**，
选择本地的 `.ipk` 文件上传安装即可。

### 方式 C：配置为本地 opkg 源（局域网批量装）

把仓库目录用任意 HTTP 服务（如 nginx/uhttpd）暴露后，在路由器上：

```sh
echo "src/gz myipk http://<你的电脑IP>/<目录>" > /etc/opkg/customfeeds.conf
# 目录内需有 opkg 索引（Packages / Packages.gz），可用以下命令生成：
#   usign 不要求时: opkg-make-index . > Packages && gzip -kf Packages
opkg update
opkg install luci-app-panel
```

### 安装后处理

- 安装完成后 postinst 会自动清理 LuCI 缓存并重载 rpcd，刷新浏览器即可见菜单。
- 菜单未出现时手动执行：

```sh
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
killall -HUP rpcd 2>/dev/null
```

- 依赖 `luci-compat`（21.02+ 的经典 Lua 兼容层；19.07 自带 Lua LuCI 可直接运行）。
  若 opkg 报依赖缺失：`./scripts/feeds` 体系固件请先 `opkg update`；
  自编译固件可在固件中编入 luci feed 的 `luci-compat`。
- usb-pcie-scan 还需要 `usbutils`、`pciutils`（opkg 会自动一并安装，需联网的官方源）。

---

## 四、加入 OpenWrt 集成编译

### 前置：准备 luci feed 与 luci-compat

```sh
# 首次拉取源码后
./scripts/feeds update -a
./scripts/feeds install luci
./scripts/feeds install luci-compat
```

### 方式 1：复制到 package 目录（最简单）

```sh
# 单个插件
cp -a luci-app-panel openwrt/package/

# 或三个一起
cp -a luci-app-nxdb luci-app-panel luci-app-usb-pcie-scan openwrt/package/

cd openwrt
make menuconfig
#   LuCI  ->  Applications
#     <*> luci-app-nxdb
#     <*> luci-app-panel
#     <*> luci-app-usb-pcie-scan
make package/luci-app-panel/compile V=s
# 产物: bin/packages/<arch>/base/luci-app-panel_2.0-1_all.ipk
```

要**编入固件出厂镜像**，menuconfig 中选 `*`（内置）而非 `M`（仅生成 ipk）；
三个插件可同时内置，互不冲突。

### 方式 2：作为自定义 feed 接入（推荐多包维护）

本仓库根目录（三个插件目录的上一级）本身就是一个合法的 feed 根目录。
在源码根目录编辑 `feeds.conf.default`（或新建 `feeds.conf`）追加一行：

```sh
src-link myipk /本机/绝对路径/my-ipk
```

然后：

```sh
./scripts/feeds update myipk
./scripts/feeds install -a -p myipk     # 或逐个 install luci-app-panel 等
make menuconfig
#   LuCI -> Applications 中即可看到三个插件
make defconfig
make package/luci-app-nxdb/compile V=s
make package/luci-app-panel/compile V=s
make package/luci-app-usb-pcie-scan/compile V=s
# 整包编译: make -j$(nproc)
```

远程仓库方式（CI/服务器构建）：在 `feeds.conf` 中使用

```sh
src-git myipk https://gitee.com/qlljcf666/my-ipk.git;master
```

再执行同样的 `feeds update/install` 流程。

### 方式 3：使用对应固件的 SDK（不动完整源码树）

```sh
tar xf OpenWrt-SDK-<target>_*.tar.xz
cd OpenWrt-SDK-*
cp -a /path/to/luci-app-panel package/
make package/luci-app-panel/compile V=s
# 产物: bin/packages/<arch>/base/luci-app-panel_2.0-1_all.ipk
```

### 编译注意事项

- **Windows 检出**：请保留仓库内 `.gitattributes` 的 `eol=lf`；在 Linux/WSL
  构建时若文件被改成 CRLF，执行 `sed -i 's/\r$//'` 或重新干净检出。
- 自定义包名/版本：编辑对应插件 `Makefile` 的 `PKG_VERSION` / `PKG_RELEASE`，
  产物文件名随之变化。
- 修改 `.htm` / `.lua` 后无需重编整个工具链，重跑对应
  `make package/<name>/compile V=s` 即可（增量，几秒级）。

---

## 五、兼容性

| OpenWrt 版本 | LuCI 形态 | 支持情况 |
|---|---|---|
| 19.07 | 经典 Lua | 直接可用（luci-compat 为元包） |
| 21.02 / 22.03 / 23.05 | Lua + 部分客户端 JS | 需 `luci-compat`，正常使用 |
| 24.10+（ucode LuCI） | ucode + ucodebridge | 需 `luci-compat`，Lua 控制器经兼容层运行；`.htm` 必须 LF |

## License

MIT
