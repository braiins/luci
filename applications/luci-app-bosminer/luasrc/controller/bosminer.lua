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
	e.css = "bosminer_overview/styles.dd486bc7fd9fd28b78bc.css"

	entry({"admin", "miner", "api_status"}, call("action_status")).leaf = true
end

local socket = require "socket"
local HOST = "127.0.0.1"
local PORT = 4028

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

function action_status()
	local http = require "luci.http"

	-- query cgminer API and pass the result to application
	local ok, result = query_cgminer_api('devs+devdetails+temps+pools+summary+tempctrl+fans')
	if not ok then
		http.status(500, "Cannot query CGMiner API: "..result)
		return
	end

	local reply = luci.jsonc.parse(result)
	if not reply then
		http.status(500, "Invalid JSON response")
		return
	end

	http.prepare_content("application/json")
	http.write(luci.jsonc.stringify(reply))
end
