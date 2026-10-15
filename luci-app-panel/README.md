# luci-app-panel

OpenWrt LuCI 插件：**设备面板（Device Panel）**。在 LuCI 页面中以内嵌 `iframe`
的方式集中管理并访问局域网内的设备 Web 界面，无需逐台输入地址端口。

菜单位置：顶级菜单 **Device Panel**（`admin/panel`，菜单排序 60）。

## 功能

- 左侧设备列表（可折叠，折叠状态持久化到 UCI），单击设备即在右侧 `iframe` 中
  按 `地址:端口` 打开其 Web 管理页。
- 页面内直接 **新增 / 编辑 / 删除** 设备：名称、IP 地址（或主机名）、端口、
  **后台登录账号 / 密码**；全部配置实时存入 UCI `panel`，刷新与重启后不丢失。
- 连接已配置凭据的设备时，顶部出现凭据栏并**自动尝试填充登录表单**
  （仅当 iframe 页面与 LuCI 同源时浏览器才允许注入；跨域时凭据栏提供
  账号 / 密码一键复制）。
- 内置暗色模式，页面自包含、零第三方 JS 依赖（原生 `fetch`）。
- 首次安装时通过 `uci-defaults` 幂等播种 3 台示例设备（`192.168.66.1`
  的 80 / 6677 / 9527 端口）；用户已存在任何设备时不再覆盖。

## 源码结构

```
luci-app-panel/
├── Makefile                     # OpenWrt 包定义 (PKG_NAME / LUCI_DEPENDS, 走 luci.mk)
├── .gitattributes               # 强制 LF 换行 (ucode LuCI 模板解析必需)
├── luasrc/                      # luci.mk 映射 -> /usr/lib/lua/luci/
│   ├── controller/
│   │   └── panel.lua            # 菜单路由 + save/delete/get_config (读写 UCI panel)
│   └── view/
│       └── panel/
│           └── remote_admin.htm # 设备面板页面 (侧边栏 + iframe + 增删改弹窗)
└── root/                        # luci.mk 映射 -> /
    └── etc/
        ├── config/
        │   └── panel            # UCI 配置骨架 (仅 general 节, 设备由 uci-defaults 播种)
        └── uci-defaults/
            └── luci-app-panel   # 幂等播种示例设备 + 清 LuCI 缓存 (执行后自删)
```

路径映射遵循 `luci.mk` 约定：`luasrc/` → `/usr/lib/lua/luci/`，`root/` → `/`。

## UCI 配置

`/etc/config/panel`：

```
config panel 'general'
    option sidebar_collapsed '0'      # 侧边栏是否折叠: 0/1

config device
    option label    '5G壳-80端口'      # 显示名称 (1-64 字符)
    option address  '192.168.66.1'     # IPv4 / 主机名
    option port     '80'               # 1-65535
    option username 'admin'            # 后台登录账号 (可选, <=64 字符)
    option password 'admin'            # 后台登录密码 (可选, <=128 字符)
```

控制器只接受白名单键（`label` / `address` / `port` / `username` / `password`、
`general` 节的 `sidebar_collapsed`），并对节名、名称、地址、端口、账号、
密码做服务端校验，UCI 配置名固定为 `panel`，不可由请求参数指定。

> **安全提示**：凭据以明文保存在 `/etc/config/panel`（仅 root 可读，
> 0644），与 LuCI 自身保存 PPPoE 密码的方式一致。请勿在多人可登录
> LuCI 的环境中存放高价值密码。

## 编译

本目录是**标准 OpenWrt 编译源码树**，在 OpenWrt buildroot 或对应架构 SDK 中编译。

方式一：放入 buildroot 源码树编译

```sh
# 1. 放入 package 目录 (或独立 feed)
cp -a luci-app-panel openwrt/package/

# 2. 配置中选中 (Target 已具备 luci feed)
make menuconfig
#   LuCI  ->  Applications  ->  <*> luci-app-panel

# 3. 编译
make package/luci-app-panel/compile V=s
```

方式二：使用对应固件的 SDK（不下载完整源码树）

```sh
tar xf OpenWrt-SDK-*.tar.xz && cd OpenWrt-SDK-*
cp -a /path/to/luci-app-panel package/
make package/luci-app-panel/compile V=s
# 产物: bin/packages/<arch>/base/luci-app-panel_2.0-1_all.ipk
```

> 依赖 `luci-compat`（经典 Lua LuCI 控制器在 21.02+ 上的兼容层；
> 19.07 等自带 Lua LuCI 的版本可直接运行）。`luci.mk` 还会自动追加
> `luci-lua-runtime` 依赖并生成清理 `/tmp/luci-*cache`、`killall -HUP rpcd`
> 的 postinst。编译前请确保 luci feed 已安装：
> `./scripts/feeds update luci && ./scripts/feeds install luci-compat`。

## 安装

```sh
opkg update
opkg install ./luci-app-panel_2.0-1_all.ipk
```

安装后 uci-defaults 会幂等写入示例设备、提交 UCI 并清理 LuCI 缓存，
刷新页面即可见顶级菜单 **Device Panel**。若菜单未出现，手动执行：

```sh
rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
killall -HUP rpcd 2>/dev/null
```

## 使用说明

1. 进入顶级菜单 **Device Panel**，左侧列出全部已配置设备。
2. 单击设备卡片，右侧即通过 `http://地址:端口` 内嵌打开该设备页面
   （被访问设备若限制跨域嵌入（`X-Frame-Options`），则需在对端放开）。
3. 使用侧边栏的添加 / 编辑 / 删除按钮维护设备列表，改动即时写入 UCI；
   弹窗中的 **账号 / 密码** 为可选项，保存该设备后台的登录凭据。
4. 连接已存凭据的设备时：
   - 若 iframe 页面与 LuCI **同源**（同协议 + 同主机 + 同端口，例如经反代
     挂载在同域名下），页面加载后自动填充账号密码并触发 `input/change`
     事件（兼容 React/Vue 等框架的受控输入框）；
   - 若**跨域**（浏览器同源策略禁止访问 iframe DOM，属安全机制，无法绕过），
     顶部凭据栏显示账号与掩码密码，点击 **Copy** 一键复制后粘贴登录。
5. 侧边栏折叠按钮可收起列表，折叠状态在下次进入时保持。

## 相对旧解包目录的修复点

本源码树由真实 buildroot 解出的打包目录逆向整理，除补齐标准 `Makefile` /
`luasrc` / `root` 布局外还修复了以下问题：

- **uci-defaults 非幂等**：旧脚本每次执行都无条件 `uci add` 三台设备，
  重装 / sysupgrade 恢复后会产生重复条目；新脚本仅在不存在任何 `device`
  节时播种，且保留用户既有的 `general.sidebar_collapsed`。
- **配置冗余**：出厂 `/etc/config/panel` 与 uci-defaults 重复写示例设备；
  现配置文件仅保留 `general` 骨架，设备统一由 uci-defaults 播种。
- **控制器入参未校验**：旧版允许请求指定任意 UCI 配置名、写入任意键；
  现固定配置名为 `panel`，键白名单化，节名 / 名称 / 地址 / 端口全部校验，
  API 路径与 JSON 响应结构保持不变。
- 视图原样迁移，仅规范化了原文件中一处混乱的缩进。

## 兼容性说明

- 兼容 Lua LuCI（luci-compat）与 ucode LuCI（24.10+，经 ucodebridge 运行 Lua controller）。
- **模板/脚本必须 LF 换行**：ucode LuCI 模板解析器遇到 CRLF 的 `.htm` 会报
  `Syntax error ... unfinished string`，仓库已通过 `.gitattributes` 强制 `eol=lf`。

## License

MIT
