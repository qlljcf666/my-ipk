-- LuCI controller for luci-app-panel
-- 设备面板: 在路由器页面内通过 iframe 访问局域网设备的 Web 界面
-- 设备清单存储于 UCI /etc/config/panel
-- 经典 Lua LuCI (OpenWrt 21~23 原生; 24.10+ 需 luci-compat)

module("luci.controller.panel", package.seeall)

local http = require "luci.http"

-- 仅允许操作本插件自己的 UCI 配置, 不接受客户端传入的 config 名
local UCI_CONFIG = "panel"

-- 各节允许写入的字段白名单
local DEVICE_KEYS  = { label = true, address = true, port = true,
	username = true, password = true }
local GENERAL_KEYS = { sidebar_collapsed = true }

-- ----------------------------------------------------------- 输入校验

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- UCI 匿名节名(cfg1234abcd)/命名节(general): 字母数字下划线, <=32
local function valid_section(s)
	return type(s) == "string" and #s > 0 and #s <= 32 and
		s:match("^[%w_]+$") ~= nil
end

-- 标签: 1~64 字符, 允许 UTF-8 (如 "5G壳-80端口"), 拒绝控制字符; 返回 trim 后的值
local function check_label(v)
	if type(v) ~= "string" then return nil end
	v = trim(v)
	if #v < 1 or #v > 64 or v:find("[%c]") then return nil end
	return v
end

-- 地址: 允许空(尚未配置); 否则要求 IPv4(各段 0-255) 或主机名(字母数字 . -)
local function check_address(v)
	if type(v) ~= "string" then return false end
	if v == "" then return true end
	if #v > 253 then return false end
	if v:match("^%d") then
		local a, b, c, d = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
		if not a then return false end
		for _, x in ipairs({ a, b, c, d }) do
			local n = tonumber(x)
			if not n or n < 0 or n > 255 then return false end
		end
		return true
	end
	return v:match("^[%w%.%-]+$") ~= nil
end

-- 端口: 1~65535 整数, 返回归一化后的字符串
local function check_port(v)
	local n = tonumber(v)
	if not n or n ~= math.floor(n) or n < 1 or n > 65535 then return nil end
	return tostring(n)
end

local function check_flag(v)
	return v == "0" or v == "1"
end

-- 账号: 允许空; <=64 字符, 去首尾空白, 拒绝控制字符
local function check_username(v)
	if type(v) ~= "string" then return nil end
	v = trim(v)
	if #v > 64 or v:find("[%c]") then return nil end
	return v
end

-- 密码: 允许空; <=128 字符, 拒绝控制字符 (不去空白, 密码可能含空格)
local function check_password(v)
	if type(v) ~= "string" then return nil end
	if #v > 128 or v:find("[%c]") then return nil end
	return v
end

-- 校验设备节字段, 返回 clean 表; 失败返回 nil, 错误信息
local function check_device_values(values)
	local clean = {}
	for k, v in pairs(values or {}) do
		if not DEVICE_KEYS[k] then
			return nil, "非法字段: " .. tostring(k)
		elseif k == "label" then
			local l = check_label(v)
			if not l then return nil, "标签无效 (1-64 个字符)" end
			clean.label = l
		elseif k == "address" then
			if not check_address(v) then return nil, "地址无效 (需 IPv4 或主机名)" end
			clean.address = v
		elseif k == "port" then
			local p = check_port(v)
			if not p then return nil, "端口无效 (1-65535)" end
			clean.port = p
		elseif k == "username" then
			local u = check_username(v)
			if not u then return nil, "账号无效 (<=64 字符)" end
			clean.username = u
		elseif k == "password" then
			local pw = check_password(v)
			if not pw then return nil, "密码无效 (<=128 字符)" end
			clean.password = pw
		end
	end
	return clean
end

-- ----------------------------------------------------------- 路由

function index()
	entry({"admin", "panel"}, template("panel/remote_admin"), _("Device Panel"), 60)
	entry({"admin", "panel", "save"},       call("action_save")).leaf = true
	entry({"admin", "panel", "delete"},     call("action_delete")).leaf = true
	entry({"admin", "panel", "get_config"}, call("action_get_config")).leaf = true
end

-- ----------------------------------------------------------- 保存 (add/update/set)

function action_save()
	local uci = require "luci.model.uci".cursor()
	http.prepare_content("application/json")

	local ok, result = pcall(function()
		local data
		local raw = http.content()
		if type(raw) == "string" and raw ~= "" then
			data = require "luci.jsonc".parse(raw)
		end
		if not data then
			-- 兼容表单提交
			data = {
				action = http.formvalue("action"),
				values = {
					label   = http.formvalue("label") or "",
					address = http.formvalue("address") or "",
					port    = http.formvalue("port") or "80"
				}
			}
		end
		if type(data) ~= "table" or type(data.action) ~= "string" then
			return { success = false, error = "no action" }
		end

		local action = data.action

		if action == "add" then
			local clean, e = check_device_values(data.values)
			if e then return { success = false, error = e } end
			if not clean.label then
				return { success = false, error = "标签必填" }
			end
			local sec = uci:add(UCI_CONFIG, "device")
			for k, v in pairs(clean) do
				if v ~= "" then uci:set(UCI_CONFIG, sec, k, v) end
			end
			uci:commit(UCI_CONFIG)
			return { success = true, id = sec }
		end

		if action == "update" then
			if not valid_section(data.section) then
				return { success = false, error = "非法 section" }
			end
			local clean, e = check_device_values(data.values)
			if e then return { success = false, error = e } end
			for k, v in pairs(clean) do
				if v ~= "" then
					uci:set(UCI_CONFIG, data.section, k, v)
				else
					uci:delete(UCI_CONFIG, data.section, k)
				end
			end
			uci:commit(UCI_CONFIG)
			return { success = true }
		end

		if action == "set" then
			-- 仅允许 general 节的 sidebar_collapsed 开关
			if data.section ~= "general" then
				return { success = false, error = "非法 section" }
			end
			for k, v in pairs(data.values or {}) do
				if not GENERAL_KEYS[k] or not check_flag(v) then
					return { success = false, error = "非法字段或取值" }
				end
				uci:set(UCI_CONFIG, "general", k, v)
			end
			uci:commit(UCI_CONFIG)
			return { success = true }
		end

		return { success = false, error = "unknown action: " .. action }
	end)

	if not ok then
		http.write_json({ success = false, error = "pcall error: " .. tostring(result) })
	else
		http.write_json(result)
	end
end

-- ----------------------------------------------------------- 读取配置

function action_get_config()
	http.prepare_content("application/json")
	local uci = require "luci.model.uci".cursor()
	local result = {}
	uci:foreach(UCI_CONFIG, "device", function(s)
		result[s['.name']] = {
			[".type"] = "device",
			label    = s.label or "",
			address  = s.address or "",
			port     = s.port or "80",
			username = s.username or "",
			password = s.password or ""
		}
	end)
	local gen = uci:get_all(UCI_CONFIG, "general") or {}
	result.general = gen
	result.general[".type"] = "general"
	http.write_json({ values = result })
end

-- ----------------------------------------------------------- 删除设备

function action_delete()
	http.prepare_content("application/json")
	local section = http.formvalue("section") or ""
	if not valid_section(section) or section == "general" then
		http.write_json({ success = false, error = "非法 section" })
		return
	end
	local uci = require "luci.model.uci".cursor()
	if uci:get(UCI_CONFIG, section) ~= "device" then
		http.write_json({ success = false, error = "目标节不存在或不是 device" })
		return
	end
	uci:delete(UCI_CONFIG, section)
	uci:commit(UCI_CONFIG)
	http.write_json({ success = true })
end
