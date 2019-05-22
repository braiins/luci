--[[

LuCI Cgminer module

Copyright (C) 2015, OpenWrt.org

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: JAKUB HORAK <jakub.horak@braiins.cz>
Author: Libor Vasicek <libor.vasicek@braiins.cz>

]]--

module("luci.controller.cgminer", package.seeall)

nixio = require 'nixio'

function index()
	entry({"admin", "services", "cgminer"}, cbi("cgminer"), _("CGMiner"))
	entry({"admin", "status", "miner"}, template("hashrate"), _("Miner"), 90)
	entry({"admin", "status", "miner", "api_status"}, call("action_devs")).leaf = true
	entry({"admin", "status", "miner", "clear_error"}, call("action_clear_error")).leaf = true
end

local socket = require "socket"
local HOST = "127.0.0.1"
local PORT = 4028
local util = require "luci.util"
local SAVE_LAST_QUIT_FILE = "/tmp/cgminer_quit_reason"


local function go_in(t, ...)
	for _, k in ipairs({...}) do
		if type(t) == 'table' then
			t = t[k]
		else
			return nil
		end
	end
	return t
end

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

local function look_for_cgminer()
	-- cgminer API isn't accessible, look for process
	local result = util.ubus("service", "list", {})
	if not result then
		return {
			code='error',
		}
	end
	local inst = go_in(result, 'cgminer', 'instances', 'instance1')
	if inst and inst.running then
		return {
			code='started',
			pid=inst.pid,
		}
	else
		return {
			code='stopped',
		}
	end
end

function get_last_quit()
	local stat = nixio.fs.stat(SAVE_LAST_QUIT_FILE)
	if not stat then
		return nil
	end
	local f = io.open(SAVE_LAST_QUIT_FILE, 'r')
	if not f then
		return nil
	end
	local msg = f:read('*l')
	f:close()

	return {
		msg = msg,
		mtime = stat.mtime,
	}
end

function action_devs()
	luci.http.prepare_content("application/json")

	local reply = nil

	-- query cgminer API and pass the result to application
	local ok, result = query_cgminer_api('stats+pools+summary+devs+fanctrl')
	if ok then
		reply = luci.jsonc.parse(result)
		assert(reply)
	else
		reply = look_for_cgminer()
	end
	reply.last_quit = get_last_quit()
	-- look for cgminer process
	luci.http.write(luci.jsonc.stringify(reply))
end

function action_clear_error()
	nixio.fs.unlink(SAVE_LAST_QUIT_FILE)
	luci.http.prepare_content("application/json")
	luci.http.write(luci.jsonc.stringify({}))
end
