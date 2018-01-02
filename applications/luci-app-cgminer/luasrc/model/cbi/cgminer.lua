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
local sys = require "luci.sys"
require "ubus"

m = Map("cgminer", translate("CGMiner"), translate("Miner general configuration"))
m.on_after_commit = function() luci.sys.call("/etc/init.d/cgminer reload") end

s = m:section(TypedSection, "pool", translate("Pools"))
s.anonymous = true
s.addremove = true

o = s:option(Value, "server", translate("Server"))
o.datatype = "string"
o.placeholder = "stratum+tcp://stratum.slushpool.com"

o = s:option(Value, "port", translate("Port"))
o.datatype = "portrange"
o.placeholder = "3333"

o = s:option(Value, "user", translate("User"))
o.datatype = "string"

o = s:option(Value, "password", translate("Password"))
o.datatype = "string"

s = m:section(TypedSection, "miner", translate("Miner"),
	translate("Warning: overclock is at your own risk and vary in performance from miner to miner. It may damage miner in overheating condition."))
s.anonymous = true
s.addremove = false

o = s:option(Value, "frequency", translate("Frequency (MHz)"),
	translate("If you want to try overclock frequency, you usually need to adjust VID to be lower."))
o.datatype = "range(120,1332)"
o.placeholder = "1332"
o.default = 1332

o = s:option(Value, "voltage", translate("Voltage (Level)"),
	translate("The lower VID value means the higher voltage and higher power consumption."))
o.datatype = "range(10,15)"
o.placeholder = "13"
o.default = 13

o = s:option(StaticList, "chains", translate("Enabled Chains"))
o.widget = "checkbox"
o.rmempty = true
for i=0,5 do
	o:value(i)
end

return m
