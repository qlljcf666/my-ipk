-- LuCI controller for luci-app-nxdb
-- IPK 插件扫描 / 逆向打包 (经典 Lua LuCI, 兼容 OpenWrt 15~21, 新版需 luci-compat)

module("luci.controller.nxdb", package.seeall)

local util = require "luci.util"
local http = require "luci.http"

-- 后端脚本路径。统一通过 /bin/sh 解释执行, 不依赖文件自身的可执行位
-- (源码经 Windows/非 POSIX 介质拷贝打包后 +x 可能丢失)。
local SH = "/usr/libexec/nxdb/nxdb.sh"

function index()
	local page

	page = entry({"admin", "system", "nxdb"}, alias("admin", "system", "nxdb", "main"),
		_("IPK 逆向打包"), 79)
	page.dependent = false
	page.sysauth = "root"

	entry({"admin", "system", "nxdb", "main"}, template("nxdb/main"),
		_("扫描与打包"), 10).leaf = true
	entry({"admin", "system", "nxdb", "data"}, call("action_data"))
	entry({"admin", "system", "nxdb", "files"}, call("action_files"))
	entry({"admin", "system", "nxdb", "pack"}, call("action_pack"))
	entry({"admin", "system", "nxdb", "cancel"}, call("action_cancel"))
	entry({"admin", "system", "nxdb", "status"}, call("action_status"))
	entry({"admin", "system", "nxdb", "download"}, call("action_download"))
end

-- ----------------------------------------------------------- 安全校验

local function valid_pkg(name)
	return name and #name > 0 and #name <= 128 and
		not name:match("[^%w%.%+%-%_]") and true or false
end

local function valid_out(d)
	if not d or #d > 128 or d:match("%.%.") then
		return false
	end
	-- 允许的可写位置前缀 (避免任意路径写入)
	local prefixes = {
		"^/tmp/", "^/root/", "^/mnt/", "^/media/",
		"^/sda", "^/sdb", "^/mmcblk", "^/opt/"
	}
	for _, p in ipairs(prefixes) do
		if d:match(p) then
			return true
		end
	end
	return false
end

-- ----------------------------------------------------------- 极简 JSON

local function jesc(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\")
	s = s:gsub('"', '\\"')
	s = s:gsub("\r", "\\r")
	s = s:gsub("\n", "\\n")
	s = s:gsub("\t", "\\t")
	return s
end

local function json_out(t)
	http.prepare_content("application/json")
	http.write(t)
end

-- ----------------------------------------------------------- 动作

function action_data()
	local out = util.exec(("/bin/sh %s scan 2>/dev/null"):format(SH)) or ""
	local rows, total_miss = {}, 0
	for line in out:gmatch("[^\r\n]+") do
		local pkg, ver, arch, sec, files, links, missing, desc =
			line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
		if pkg and #pkg > 0 then
			local m = tonumber(missing) or 0
			total_miss = total_miss + m
			rows[#rows+1] = '{"pkg":"%s","ver":"%s","arch":"%s","sec":"%s","files":%d,"links":%d,"missing":%d,"desc":"%s"}' % {
				jesc(pkg), jesc(ver), jesc(arch), jesc(sec),
				tonumber(files) or 0, tonumber(links) or 0, m, jesc(desc)
			}
		end
	end
	json_out('{"ok":true,"total":%d,"missing":%d,"rows":[%s]}' % {
		#rows, total_miss, table.concat(rows, ",") })
end

function action_files()
	local pkg = http.formvalue("pkg") or ""
	if not valid_pkg(pkg) then
		json_out('{"ok":false,"error":"bad pkg"}')
		return
	end
	local out = util.exec(("/bin/sh %s filelist %q 2>/dev/null"):format(SH, pkg)) or ""
	local rows = {}
	for line in out:gmatch("[^\r\n]+") do
		local path, st, target = line:match("^([^\t]*)\t(%a)\t?(.*)$")
		if path then
			local label = ({ F = "文件", D = "目录", L = "符号链接", M = "缺失" })[st] or st
			rows[#rows+1] = '{"path":"%s","st":"%s","label":"%s","target":"%s"}' % {
				jesc(path), st, jesc(label), jesc(target) }
		end
	end
	json_out('{"ok":true,"rows":[%s]}' % table.concat(rows, ","))
end

local function get_out()
	local d = http.formvalue("out") or "/tmp/nxdb_ipk"
	if not valid_out(d) then
		return nil
	end
	if d:sub(-1) == "/" then
		d = d:sub(1, -2)
	end
	return d
end

function action_pack()
	local out = get_out()
	if not out then
		json_out('{"ok":false,"error":"输出目录不允许, 请使用 /tmp、/root、/mnt 等可写路径"}')
		return
	end
	local pkgs = http.formvalue("pkgs") or ""
	local args = {}
	for p in pkgs:gmatch("[^,]+") do
		p = p:match("^%s*(.-)%s*$")
		if valid_pkg(p) then
			args[#args+1] = p
		end
	end
	if #args == 0 then
		json_out('{"ok":false,"error":"未选择有效插件"}')
		return
	end
	util.exec("mkdir -p %q/ipk" % out)
	local quoted = {}
	for _, p in ipairs(args) do
		quoted[#quoted+1] = "'" .. p .. "'"
	end
	local res = util.exec(("/bin/sh %s start %q %s 2>&1"):format(SH, out, table.concat(quoted, " ")))
	res = (res or ""):gsub("%s+", "")
	if res == "BUSY" then
		json_out('{"ok":false,"error":"已有打包任务在运行"}')
	else
		json_out('{"ok":true,"n":%d}' % #args)
	end
end

function action_cancel()
	util.exec(("/bin/sh %s cancel >/dev/null 2>&1"):format(SH))
	json_out('{"ok":true}')
end

function action_status()
	local out = get_out()
	if not out then
		json_out('{"ok":false}')
		return
	end
	local raw = util.exec(("/bin/sh %s status %q 2>/dev/null"):format(SH, out)) or ""

	local state = { running = 0, i = 0, n = 0, done = 0, pkg = "" }
	local files, report = {}, {}
	local section
	for line in raw:gmatch("[^\r\n]+") do
		if line == "==STATE==" then section = "state"
		elseif line == "==FILES==" then section = "files"
		elseif line == "==REPORT==" then section = "report"
		elseif section == "state" then
			local k, v = line:match("^(%w+)=(.*)$")
			if k then state[k] = v end
		elseif section == "files" then
			local name, size = line:match("^([^|]+)|(%d+)$")
			if name then
				files[#files+1] = '{"name":"%s","size":%d}' % { jesc(name), tonumber(size) or 0 }
			end
		elseif section == "report" then
			report[#report+1] = jesc(line)
		end
	end

	json_out('{"ok":true,"running":%d,"i":%d,"n":%d,"done":%d,"pkg":"%s","files":[%s],"report":"%s"}' % {
		tonumber(state.running) or 0,
		tonumber(state.i) or 0,
		tonumber(state.n) or 0,
		tonumber(state.done) or 0,
		jesc(state.pkg),
		table.concat(files, ","),
		table.concat(report, "\\n")
	})
end

function action_download()
	local out = get_out()
	local name = http.formvalue("name") or ""
	-- 仅允许纯文件名, 防止路径穿越
	if not out or not name:match("^[%w%.%+%-%_]+%.ipk$") then
		http.status(400, "Bad Request")
		http.prepare_content("text/plain")
		http.write("bad request")
		return
	end
	local path = out .. "/ipk/" .. name
	local nixio = require "nixio"
	local st = nixio.fs.stat(path)
	if not st then
		http.status(404, "Not Found")
		http.prepare_content("text/plain")
		http.write("not found")
		return
	end
	http.header("Content-Disposition", 'attachment; filename="%s"' % name)
	http.prepare_content("application/octet-stream")
	local f = io.open(path, "rb")
	if f then
		http.write(f:read("*a"))
		f:close()
	end
end
