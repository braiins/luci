--[[

LuCI bOSminer module

Copyright (C) 2015, OpenWrt.org

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Libor Vasicek <libor.vasicek@braiins.cz>

]]--

module("luci.controller.bosminer", package.seeall)

function index()
	entry({"admin", "miner"}, alias("admin", "miner", "overview"), _("Miner"), 10).index = true
	e = entry({"admin", "miner", "overview"}, template("overview"), _("Overview"), 1)
	e.css = "bosminer_overview/styles.7892c1a1960a25b04d38.css"
	e = entry({"admin", "miner", "config"}, template("config"), _("Configuration"), 2)
	e.css = "bosminer_config/styles.182605929b84ac1c189e.css"

	entry({"admin", "miner", "api_status"}, call("action_status")).leaf = true
	entry({"admin", "miner", "cfg_metadata"}, call("action_cfg_metadata")).leaf = true
	entry({"admin", "miner", "cfg_data"}, call("action_cfg_data")).leaf = true
	entry({"admin", "miner", "cfg_save"}, call("action_cfg_save")).leaf = true
	entry({"admin", "miner", "cfg_apply"}, call("action_cfg_apply")).leaf = true
end

local http = require "luci.http"
local json = require "luci.jsonc"

local socket = require "socket"
local HOST = "127.0.0.1"
local PORT = 4028

local CFG_CODE_SUCCESS = 0
local CFG_CODE_SYSTEM_ERROR = 1

local CFG_HANDLER = "bosminer config"

local CFG_HANDLE_METADATA = CFG_HANDLER .. " --metadata"
local CFG_HANDLE_DATA = CFG_HANDLER .. " --data"
local CFG_HANDLE_SAVE = CFG_HANDLER .. " --save"

local function query_cgminer_api(q)
	local tcp = assert(socket.tcp())
	tcp:settimeout(3)

	-- create socket
	local ok, err = tcp:connect(HOST, PORT)
	if not ok then
		return false, err
	end

	-- send query
	tcp:send('{ "command":"'..q..'" }')

	-- read all data and close
	local result, err = tcp:receive('*a')
	tcp:close()
	if not result then
		return false, err
	end

	-- remove null from string
	result = result:sub(1, -2)
	return true, result
end

local function get_cfg_error(code, message)
	local reply = {}
	reply.status = {}
	reply.status.code = code
	reply.status.message = message
	reply.status.generator = 'LuCI backend'
	reply.status.timestamp = os.time()
	return json.stringify(reply)
end

local function handle_cfg_command(cmd)
	local buffer = nil
	local reply = nil

	local fd = io.popen(cmd)
	if fd then
		buffer = fd:read("*a") or ''
		fd:close()
	end

	if buffer ~= '' then
		reply = json.parse(buffer)
		if not reply then
			reply = get_cfg_error(CFG_CODE_SYSTEM_ERROR, buffer)
		else
			-- return unmodified JSON response because LUA deserializer is not equivalent
			reply = buffer
		end
	else
		reply = get_cfg_error(CFG_CODE_SYSTEM_ERROR, 'Command did not return any data')
	end

	return reply
end

local function dump_to_tmp(data)
	local request_tmp = os.tmpname()

	if request_tmp then
		local fd = io.open(request_tmp, 'w')
		if not fd then
			return nil
		end
		if not fd:write(data) then
			nixio.fs.unlink(request_tmp)
			request_tmp = nil
			fd:close()
		else
			fd:close()
		end
	end

	return request_tmp
end

function action_cfg_metadata()
	local reply = handle_cfg_command(CFG_HANDLE_METADATA .. " 2>&1")

	http.prepare_content("application/json")
	http.write(reply)
end

function action_cfg_data()
	local reply = handle_cfg_command(CFG_HANDLE_DATA .. " 2>&1")

	http.prepare_content("application/json")
	http.write(reply)
end

function action_cfg_save()
	local reply = nil

	-- dump request to a temporary file because 'io.popen' cannot use rw mode
	local request_tmp = dump_to_tmp(http.content())
	if request_tmp then
		reply = handle_cfg_command(CFG_HANDLE_SAVE .. " <%s 2>&1" % request_tmp)
		nixio.fs.unlink(request_tmp)
	else
		reply = get_cfg_error(CFG_CODE_SYSTEM_ERROR, 'Cannot create temporary file')
	end

	http.prepare_content("application/json")
	http.write(reply)
end

function action_cfg_apply()
	local reply = nil

	os.execute("/etc/init.d/bosminer reload &")	-- reload configuration
	reply = get_cfg_error(CFG_CODE_SUCCESS, 'Reloading configuration...')

	http.prepare_content("application/json")
	http.write(reply)
end

function action_status()
	-- query cgminer API and pass the result to application
	local ok, result = query_cgminer_api('devs+devdetails+temps+pools+summary+tempctrl+fans')
	if not ok then
		http.status(500, "Cannot query CGMiner API: "..result)
		return
	end

	local reply = json.parse(result)
	if not reply then
		http.status(500, "Invalid JSON response")
		return
	end

	-- return unmodified JSON response because LUA deserializer is not equivalent
	http.prepare_content("application/json")
	http.write(result)
end
