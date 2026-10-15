# luci-app-nxdb

OpenWrt LuCI 插件：扫描设备上已安装的 ipk 包，并依据 `/usr/lib/opkg/info`
元数据从**正在运行的 rootfs 逆向重建标准 `.ipk` 安装包**。

菜单位置：**系统 → IPK 逆向打包**（`admin/system/nxdb`）

## 功能

- 扫描 `/usr/lib/opkg/info/*.control`，列出全部已安装包：包名、版本、架构、分类、
  文件数 / 符号链接数 / **缺失项数**（缺失多为未编入 rootfs 的 `.ko`）。
- 点击包名查看该包 `.list` 中每个条目的实时状态（文件 / 目录 / 符号链接 / 缺失）。
- 勾选任意多个包后一键**后台守护打包**，实时显示进度、日志与产物大小；可随时停止任务。
- 生成的 ipk 可在页面上直接下载，`opkg install <pkg>.ipk` 即可在其他设备安装。
- 输出目录限制在 `/tmp`、`/root`、`/mnt`、`/media`、`/opt` 等可写白名单路径，
  包名与文件名均做严格校验，防止路径穿越。
- 后端 `/usr/libexec/nxdb/nxdb.sh` 为**纯 busybox ash** 实现，仅使用 busybox 自带的
  `tar/gzip/sed/awk/start-stop-daemon`，不依赖 python/ar/opkg，架构无关（`all`）。
- 产物为 OpenWrt 官方格式：外层 gzip tar，成员顺序 `./debian-binary ./data.tar.gz
  ./control.tar.gz`（ar 归档会被多数 opkg 判为 Malformed package）。

## 源码结构

```
luci-app-nxdb/
├── Makefile                     # OpenWrt 包定义 (PKG_NAME / LUCI_DEPENDS, 走 luci.mk)
├── .gitattributes               # 强制 LF 换行 (ucode LuCI 模板解析必需)
├── luasrc/                      # luci.mk 映射 -> /usr/lib/lua/luci/
│   ├── controller/
│   │   └── nxdb.lua             # 菜单路由 + data/files/pack/cancel/status/download
│   └── view/
│       └── nxdb/
│           └── main.htm         # 扫描 / 打包 / 进度 / 下载页面 (原生 XHR, 零 JS 依赖)
└── root/                        # luci.mk 映射 -> /
    ├── etc/uci-defaults/
    │   └── 99-luci-app-nxdb     # 安装后 chmod 后端脚本 + 清 LuCI 缓存 (执行后自删)
    ├── usr/libexec/nxdb/
    │   └── nxdb.sh              # busybox ash 后端: scan/filelist/start/run/status/cancel
    └── usr/share/rpcd/acl.d/
        └── luci-app-nxdb.json   # rpcd ACL (新版 LuCI 菜单鉴权必需)
```

路径映射遵循 `luci.mk` 约定：`luasrc/` → `/usr/lib/lua/luci/`，`root/` → `/`。

## 编译

本目录是**标准 OpenWrt 编译源码树**，在 OpenWrt buildroot 或对应架构 SDK 中编译。

方式一：放入 buildroot 源码树编译

```sh
# 1. 放入 package 目录 (或独立 feed)
cp -a luci-app-nxdb openwrt/package/

# 2. 配置中选中 (Target 已具备 luci feed)
make menuconfig
#   LuCI  ->  Applications  ->  <*> luci-app-nxdb

# 3. 编译
make package/luci-app-nxdb/compile V=s
```

方式二：使用对应固件的 SDK（不下载完整源码树）

```sh
tar xf OpenWrt-SDK-*.tar.xz && cd OpenWrt-SDK-*
cp -a /path/to/luci-app-nxdb package/
make package/luci-app-nxdb/compile V=s
# 产物: bin/packages/<arch>/base/luci-app-nxdb_1.0.0-1_all.ipk
```

> 依赖 `luci-compat`（经典 Lua LuCI 控制器在 21.02+ 上的兼容层；
> 19.07 等自带 Lua LuCI 的版本可直接运行）。编译前请确保 luci feed 已安装：
> `./scripts/feeds update luci && ./scripts/feeds install luci-compat`。

## 安装

```sh
opkg update
opkg install ./luci-app-nxdb_1.0.0-1_all.ipk
```

安装后 uci-defaults 会自动设置后端脚本可执行位并清理 LuCI 缓存，刷新页面即可见菜单。
若菜单未出现，手动执行：

```sh
rm -rf /tmp/luci-indexcache /tmp/luci-indexcache.gz /tmp/luci-modulecache
```

## 使用说明

1. 进入 **系统 → IPK 逆向打包**，页面自动扫描已安装包。
2. 可用关键字过滤、勾选“仅有缺失”、全选/反选。
3. 设置输出目录（默认 `/tmp/nxdb_ipk`，掉电丢失；需保留请改 `/root` 或挂载盘）。
4. 点 **打包选中插件**，任务后台运行，可随时 **停止任务**；完成后在页面底部单击
   ipk 文件名下载。
5. 重新打包出的 ipk 保留原 control / conffiles / 维护脚本，且符号链接按原样重建。

## 兼容性说明

- 兼容 Lua LuCI（luci-compat）与 ucode LuCI（24.10+，经 ucodebridge 运行 Lua controller）。
- **模板/脚本必须 LF 换行**：ucode LuCI 模板解析器遇到 CRLF 的 `.htm` 会报
  `Syntax error ... unfinished string`，仓库已通过 `.gitattributes` 强制 `eol=lf`。
- 后端脚本同时支持直接执行与 `/bin/sh nxdb.sh ...` 调起，不依赖文件自身可执行位；
  守护进程（start-stop-daemon 或 shell fallback）同样以 `/bin/sh` 自举。

## License

MIT
