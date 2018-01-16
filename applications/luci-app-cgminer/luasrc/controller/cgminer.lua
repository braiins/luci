--[[

LuCI Cgminer module

Copyright (C) 2015, OpenWrt.org

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Libor Vasicek <libor.vasicek@braiins.cz>

]]--

module("luci.controller.cgminer", package.seeall)

local SOCKET = require "socket"
local HOST = "127.0.0.1"
local PORT = 4029

function index()
	entry({"admin", "services", "cgminer"}, cbi("cgminer"), _("CGMiner"))

    entry({"admin", "status", "miner"}, alias("admin", "status", "miner", "hashrate"), _("Miner"), 90)

    entry({"admin", "status", "miner", "hashrate"}, template("hashrate"), _("Hash Rate"), 1).leaf = true
	entry({"admin", "status", "miner", "temperature"}, template("temperature"), _("Temperature"), 2).leaf = true
	entry({"admin", "status", "miner", "errors"}, template("errors"), _("Errors"), 3).leaf = true

	entry({"admin", "status", "miner", "devs_status"}, call("action_devs")).leaf = true
end

function action_devs()
	luci.http.prepare_content("application/json")

	local tcp = assert(SOCKET.tcp())
	tcp:connect(HOST, PORT)
	-- tcp:send('{ "command":"devs" }')

	-- read all data and close
	local result, error = tcp:receive('*a')
	if result then
		-- remove null from string
		-- result = result:sub(1, -2)
		-- write it to the http output
		luci.http.write(result)
	end
end
