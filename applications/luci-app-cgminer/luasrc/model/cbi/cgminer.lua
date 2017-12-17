--[[

LuCI CGMiner module

Copyright (C) 2015, OpenWrt.org

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Libor Vasicek <libor.vasicek@braiins.cz>

]]--

local fs = require "nixio.fs"
--[[
local sys = require "luci.sys"
require "ubus"
]]--

m = Map("cgminer", translate("CGMiner"), translate("Miner general configuration"))
--[[
m.on_after_commit = function() luci.sys.call("/etc/init.d/cgminer restart") end
]]--

s = m:section(TypedSection, "pool", translate("Pools"))
s.anonymous = true
s.addremove = true

server = s:option(Value, "server", translate("Server"))
server.datatype = "string"
server.placeholder = "stratum+tcp://stratum.slushpool.com"

port = s:option(Value, "port", translate("Port"))
port.datatype = "portrange"
port.placeholder = "3333"

user = s:option(Value, "user", translate("User"))
user.datatype = "string"

password = s:option(Value, "password", translate("Password"))
password.datatype = "string"

s = m:section(TypedSection, "miner", translate("Miner"),
	translate("Warning: overclock is at your own risk and vary in performance from miner to miner. It may damage miner in overheating condition."))
s.anonymous = true
s.addremove = false

frequency = s:option(Value, "frequency", translate("Frequency (MHz)"),
	translate("If you want to try overclock frequency, you usually need to adjust VID to be lower."))
frequency.datatype = "range(120,1332)"
frequency.placeholder = "1332"
frequency.default = 1332

voltage = s:option(Value, "voltage", translate("Voltage (Level)"),
	translate("The lower VID value means the higher voltage and higher power consumption."))
voltage.datatype = "range(10,15)"
voltage.placeholder = "13"
voltage.default = 13

return m
