module("luci.controller.usb_pcie_scan", package.seeall)

local sys  = require "luci.sys"
local http = require "luci.http"

local function exec(cmd)
	return (sys.exec(cmd) or "")
end

local function json(t)
	http.prepare_content("application/json")
	http.write_json(t)
end

local function ishex(s)
	return type(s) == "string" and s:match("^[0-9a-fA-F]+$") ~= nil
end

----------- 路由 -----------
function index()
	entry({"admin", "system", "usb_pcie_scan"},
	      firstchild(), _("USB/PCIe 设备扫描"), 90)

	entry({"admin", "system", "usb_pcie_scan", "main"},
	      template("usb_pcie_scan/main"), _("扫描"), 1).leaf = true

	entry({"admin", "system", "usb_pcie_scan", "scan"},    call("action_scan")).leaf    = true
	entry({"admin", "system", "usb_pcie_scan", "bind"},    call("action_bind")).leaf    = true
	entry({"admin", "system", "usb_pcie_scan", "rclocal"}, call("action_rclocal")).leaf = true
end

----------- 设备扫描 -----------
function action_scan()
	local t = http.formvalue("type") or "usb"
	local d = {}

	if t == "usb" then
		d.lsusb   = exec("lsusb")
		d.lsusb_t = exec("lsusb -t")
		d.lsusb_v = exec("lsusb -v")

		-- 必要时自动挂载 debugfs (sys.call 返回退出码)
		if sys.call("test -f /sys/kernel/debug/usb/devices") ~= 0 then
			exec("mount -t debugfs none /sys/kernel/debug 2>/dev/null")
		end
		d.debug = exec("cat /sys/kernel/debug/usb/devices 2>/dev/null")

	elseif t == "pcie" then
		d.lspci   = exec("lspci")
		d.lspci_v = exec("lspci -v")
		d.lspci_t = exec("lspci -t")
	else
		json({ok = false, msg = "未知 type"})
		return
	end
	json(d)
end

----------- 驱动临时挂载 -----------
-- echo "VID PID" > /sys/bus/usb-serial/drivers/<driver>/new_id
function action_bind()
	local vid    = http.formvalue("vid")
	local pid    = http.formvalue("pid")
	local driver = http.formvalue("driver")

	if not (ishex(vid) and ishex(pid) and driver and driver:match("^[%w%-_]+$")) then
		json({ok = false, msg = "参数错误：VID/PID 必须为十六进制，driver 仅允许字母数字下划线连字符"})
		return
	end

	if sys.call("test -d /sys/bus/usb-serial/drivers/" .. driver) ~= 0 then
		json({ok = false, msg = "驱动目录不存在（该驱动未加载）: " .. driver})
		return
	end

	local cmd = string.format('echo "%s %s" > /sys/bus/usb-serial/drivers/%s/new_id', vid, pid, driver)
	-- sys.call 返回退出码 (sys.exec 返回的是 stdout 字符串, 不能当退出码用)
	local rc  = sys.call(cmd .. " 2>/dev/null")

	json({
		ok  = rc == 0,
		cmd = cmd,
		msg = rc == 0 and "临时挂载成功" or ("挂载失败: exit=" .. tostring(rc))
	})
end

----------- rc.local 开机脚本 -----------
local RC = "/etc/rc.local"

local function rc_read()
	local f = io.open(RC, "r")
	if not f then return nil end
	local s = f:read("*a") or ""
	f:close()
	return s
end

local function rc_write(s)
	local f = io.open(RC, "w")
	if not f then return false end
	f:write(s)
	f:close()
	sys.call("chmod +x " .. RC .. " 2>/dev/null")
	return true
end

function action_rclocal()
	local op = http.formvalue("op") or "list"

	if op == "list" then
		local c = rc_read()
		json({ok = c ~= nil, content = c or "", msg = c and "" or ("未找到 " .. RC)})
		return
	end

	local cmdline = http.formvalue("cmd")
	if not cmdline or cmdline == "" then
		json({ok = false, msg = "命令不能为空"})
		return
	end

	local c = rc_read() or "#!/bin/sh\n# Put your custom commands here\nexit 0\n"

	if op == "add" then
		-- 忽略空白差异的重复检测
		local norm = cmdline:gsub("%s+", "")
		for line in c:gmatch("[^\n]+") do
			if line:gsub("%s+", "") == norm then
				json({ok = false, msg = "命令已存在于 rc.local 中", content = c})
				return
			end
		end
		-- 插入到 exit 0 之前（按行匹配，避免 gsub 替换串转义问题）
		local pre, post = c:match("^(.*\n)[ \t]*exit[ \t]+0[ \t]*\n?(.*)$")
		if pre then
			c = pre .. cmdline .. "\nexit 0\n" .. post
		else
			if c:sub(-1) ~= "\n" then c = c .. "\n" end
			c = c .. cmdline .. "\nexit 0\n"
		end

	elseif op == "remove" then
		local norm = cmdline:gsub("%s+", "")
		local out = {}
		for line in (c .. "\n"):gmatch("([^\n]*)\n") do
			if line:gsub("%s+", "") ~= norm then
				out[#out + 1] = line
			end
		end
		c = table.concat(out, "\n")
	else
		json({ok = false, msg = "未知操作"})
		return
	end

	if not rc_write(c) then
		json({ok = false, msg = "无法写入 " .. RC})
		return
	end
	json({ok = true, msg = "rc.local 已更新", content = c})
end
