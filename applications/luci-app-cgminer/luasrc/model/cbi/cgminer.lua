--[[

LuCI CGMiner module

Copyright (C) 2015, OpenWrt.org

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Braiins <braiins@braiins.com>

]]--

local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require("luci.util")
local class = util.class
require "ubus"

local DEFAULT_FREQUENCY = 1332
local DEFAULT_VOLTAGE = 10
local CGMINER_CONFIG = '/etc/cgminer.conf'

local DEFAULT_FREQUENCY_S9 = 650
local DEFAULT_VOLTAGE_S9 = 8.8


local MINER_MODEL
do
	local f = io.open('/tmp/sysinfo/board_name', 'r')
	assert(f)
	MINER_MODEL = f:read('*l')
	f:close()
end
local IS_AM1_MINER = MINER_MODEL == 'am1-s9'
-- TODO: lookup what string does T1 miner USE
local IS_T1_MINER = not IS_AM1_MINER

local DEFAULT_TEMPERATURE = IS_AM1_MINER and 75 or 89
local MAX_TEMPERATURE = IS_AM1_MINER and 90 or 95
local DEFAULT_FAN_SPEED = 100

local function copy_table_into_table(dest, source)
	for k, v in pairs(source) do
		dest[k] = v
	end
end

--[[

We fake UCI config store with our JSON-based implementation. However UCI
clients expect all array-like entries to have unique "id" that is
somewhat consistent in-between page reloads.

The first attempt was to use the array index as ID, but that produced
invalid references, because when an entry was deleted from middle of a
table, the elements after it shifted.

The second attempt stores id in the JSON, provided we can safely change
te schema (and cgminer doesn't mind the extra keys in dictionary). The
ids are either used from the JSON itself or generated on JSON load.

]]

local function fill_ids(t)
	local used = {}
	local max = 0
	-- find maximum id in use
	for i, v in ipairs(t) do
		assert(type(v) == 'table')
		if v._id then
			local id = tonumber(v._id)
			if id then
				used[id] = true
				max = math.max(max, id)
			end
		end
	end
	-- assign ids to elements that do not have one
	-- start assigning from max+1
	for i, v in ipairs(t) do
		assert(type(v) == 'table')
		if not v._id then
			repeat
				max = max + 1
			until not used[max]
			v._id = tostring(max)
		end
	end
end

--[[

Lookup JSON table element by id

]]

local function get_by_id(t, id)
	for i, v in ipairs(t) do
		assert(type(t) == 'table')
		if v._id == id then
			return v, i
		end
	end
	return nil
end

--[[

Make element unique id as a composite of "array name" and "unique id".
This name is generated when foreach is called on a cursor.

]]

local function make_sect_name(name, id)
	return ('%s_%s'):format(name, id)
end

--[[

Parse section name

]]

local function parse_sect_name(s)
	local name, id = s:match('(%w+)%_(%w+)')
	if name then
		return name, id
	else
		return s
	end
end

--[[

These handlers are for converting from JSON to LuCI representation (get) and
back (set). The "id" argument is ignored for objects that are not of
array-of-dictionaries type. The "keys" table is a list of keys for purpose of
returning the whole dictionary and not just an element of it.

]]

function is_num(x)
	return type(tonumber(x)) == 'number'
end

local obj_handlers = {
	pool = {
		get = function (json, id, key)
			local pool = get_by_id(json.pools, id)
			if not pool then return {} end
			return pool[key]
		end,
		set = function (json, id, key, val)
			local pool = get_by_id(json.pools, id)
			if not pool then return end
			pool[key] = val
		end,
		del = function (json, id)
			local pool, i = get_by_id(json.pools, id)
			assert(pool)
			table.remove(json.pools, i)
		end,
		add = function (json)
			local pos = #json.pools + 1
			local t = {
				url = '',
				user = '',
				pass = '',
			}
			json.pools[pos] = t
			fill_ids(json.pools)
			return json.pools[pos]._id
		end,
		keys = { 'url', 'user', 'pass' }
	},
	fancontrol = {
		get = function (json, id, key)
			return json[key]
		end,
		set = function (json, id, key, val)
			json[key] = val
		end,
		load_fixup = function (json)
			local ctrl = json['fan-ctrl']
			json['fan-ctrl-enabled'] = (ctrl == 'temp' or ctrl == 'speed') and '1' or '0'
		end,
		save_fixup = function (json)
			local ok = false
			if json['fan-ctrl-enabled'] == '1' then
				if json['fan-ctrl'] == 'temp' then
					if is_num(json['fan-temp']) then
						ok = true
						json['fan-speed'] = nil
					end
				elseif json['fan-ctrl'] == 'speed' then
					if is_num(json['fan-speed']) then
						ok = true
						json['fan-temp'] = nil
					end
				end
			end
			if not ok then
				json['fan-ctrl'] = nil
				json['fan-temp'] = nil
				json['fan-speed'] = nil
			end
			json['fan-ctrl-enabled'] = nil
		end,
	},
}
local am1_handlers = {
	miners9 = {
		get = function (json, id, key)
			if key == 'asicboost' then
				return (tonumber(json['multi-version']) or 1) > 1 and '1' or '0'
			else
				return json[key]
			end
		end,
		set = function (json, id, key, val)
			if key == 'asicboost' then
				json['multi-version'] = val == '1' and '4' or '1'
			else
				json[key] = val
			end
		end,
		load_fixup = function (json)
			json['overclock-enable'] = is_num(json['overclock']) and '1' or '0'
		end,
		save_fixup = function (json)
			local ok = false
			if json['overclock-enable'] == '1' and is_num(json['overclock']) then
				ok = true
			end
			if not ok then
				json['overclock'] = nil
			end
			json['overclock-enable'] = nil
		end,
	},
	chainconfigs9 = {
		get = function (json, id, key)
			local m = assert(json.chainconfigs9[tonumber(id)])
			return m[key]
		end,
		set = function (json, id, key, val)
			local m = assert(json.chainconfigs9[tonumber(id)])
			m[key] = val
		end,
		keys = { 'frequency', 'voltage', 'frequency-override', 'voltage-override' },
		load_fixup = function (json)
			local volt_list = luci.util.split(json['bitmain-voltage'] or '', ',')
			local freq_list = luci.util.split(json['bitmain-freq'] or '', ',')
			local t = {}

			for i = 1, 6 do
				local f = freq_list[#freq_list == 1 and 1 or i]
				local v = volt_list[#volt_list == 1 and 1 or i]
				t[i] = {
					frequency = f,
					frequency_override = f and f ~= '' and '1' or '0',
					voltage = v,
					voltage_override =  v and v ~= '' and '1' or '0',
				}
			end
			json.chainconfigs9 = t
		end,
		save_fixup = function (json)
			local volt_list = {}
			local freq_list = {}
			for i = 1, 6 do
				local chain = json.chainconfigs9[i]
				volt_list[i] = chain.voltage_override == '1' and chain.voltage or ''
				freq_list[i] = chain.frequency_override == '1' and chain.frequency or ''
			end
			json.chainconfigs9 = nil
			json['bitmain-voltage'] = table.concat(volt_list, ',')
			json['bitmain-freq'] = table.concat(freq_list, ',')
		end,
	},
}
local t1_handlers = {
	miner = {
		get = function (json, id, key)
			if key == 'frequency' then
				return json.A1Pll1
			elseif key == 'voltage' then
				return json.A1Vol
			elseif key == 'chains' then
				return luci.util.split(json['enabled-chains'] or '', ',')
			end
		end,
		set = function (json, id, key, val)
			if key == 'frequency' then
				for i = 1, 6 do
					json[('A1Pll%d'):format(i)] = val
				end
			elseif key == 'voltage' then
				json.A1Vol = val
			elseif key == 'chains' then
				if val == '' then val = {} end
				json['enabled-chains'] = table.concat(val, ',')
			end
		end,
		keys = { 'frequency', 'voltage', 'chains', }
	},
}

if IS_AM1_MINER then
	copy_table_into_table(obj_handlers, am1_handlers)
elseif IS_T1_MINER then
	copy_table_into_table(obj_handlers, t1_handlers)
end


local function get_handler(s)
	local name, id = parse_sect_name(s)
	if not name then return nil end
	return obj_handlers[name], id, name
end
local function load_fixup(json)
	for _, s in pairs(obj_handlers) do
		if s.load_fixup then
			s.load_fixup(json)
		end
	end
end
local function save_fixup(json)
	for _, s in pairs(obj_handlers) do
		if s.save_fixup then
			s.save_fixup(json)
		end
	end
end

JsonUCICursor = class()

function JsonUCICursor.__init__(self)
end

function JsonUCICursor.commit(self, config)
end

function JsonUCICursor.unload(self, config)
end

function JsonUCICursor.load(self, config)
	local str = nixio.fs.readfile(CGMINER_CONFIG) or ""
	self.json = luci.jsonc.parse(str)
	if not self.json or type(self.json) ~= 'table' or not self.json.pools or type(self.json.pools) ~= 'table' then
		error("default configuration not available, create "..CGMINER_CONFIG)
	end
	load_fixup(self.json)
	return true
end

function JsonUCICursor.save(self, config)
	save_fixup(self.json)
	nixio.fs.writefile(CGMINER_CONFIG, luci.jsonc.stringify(self.json))
	load_fixup(self.json)
end

function JsonUCICursor.foreach(self, config, sectiontype, fn)
	if sectiontype == 'pool' then
		fill_ids(self.json.pools)
		for i, pool in ipairs(self.json.pools) do
			fn{ ['.name'] = make_sect_name('pool', pool._id) }
		end
	elseif sectiontype == 'chainconfigs9' then
		for i = 1, 6 do
			fn{ ['.name'] = make_sect_name('chainconfigs9', i) }
		end
	else
		fn{ ['.name'] = sectiontype }
	end
end

function JsonUCICursor.add(self, config, sectiontype)
	local handler, id, name = get_handler(sectiontype)
	assert(handler)
	assert(handler.add)
	local new_id = handler.add(self.json)
	return make_sect_name(name, new_id)
end

function JsonUCICursor.delete(self, config, section, option)
	if option then return self:set(config, section, option, '') end
	local handler, id = get_handler(section)
	assert(handler)
	assert(handler.del)
	handler.del(self.json, id)
end

function JsonUCICursor.set(self, config, section, option, value)
	local handler, id = get_handler(section)
	assert(handler)
	handler.set(self.json, id, option, value)
end

function JsonUCICursor.get(self, config, section, option)
	local handler, id = get_handler(section)
	assert(handler)
	return handler.get(self.json, id, option)
end

function JsonUCICursor.get_all(self, config, section)
	local handler, id = get_handler(section)
	assert(handler)
	local t = {}
	for _, key in ipairs(handler.keys) do
		t[key] = handler.get(self.json, id, key)
	end
	return t
end

function getFixedFreqVoltageValue(freq)
	local vol_value = 0
	freq = tonumber(freq)
	if freq>=675 then   -- hashrate 14500
		vol_value=870;
	elseif freq>=650 then  -- hashrate 14000
		vol_value=880;
	elseif freq>=631 then  -- hashrate 13500
		vol_value=900;
	elseif freq>=606 then  -- hashrate 13000
		vol_value=910;
	elseif freq>=581 then  -- hashrate 12500
		vol_value=930;
	else
		vol_value=940;
	end
	return vol_value/100
end


local config = {
	name = "cgminer",
	uci = JsonUCICursor(),
}

m = Map(config, translate("CGMiner"), translate("Miner general configuration"))
m.on_after_commit = function() luci.sys.call("/etc/init.d/cgminer reload") end

s = m:section(TypedSection, "pool", translate("Pools"))
s.anonymous = true
s.addremove = true

o = s:option(Value, "url", translate("Pool URL"))
o.datatype = "string"
o.optional = false
o.rmempty = false
o.style = "width: 40em"
o.default = "stratum+tcp://stratum.slushpool.com:3333"

o = s:option(Value, "user", translate("User"))
o.datatype = "string"
o.optional = false
o.rmempty = false
o.placeholder = "eg. user.worker1"

o = s:option(Value, "pass", translate("Password"))
o.datatype = "string"
o.placeholder = "usually not required"



s = m:section(TypedSection, "fancontrol", translate("Fan Control"),
	translate("Temperature and fan speed control mode"))
s.anonymous = true
s.addremove = false


o = s:option(DummyValue, "_warning", "")
o.default = translatef('<div class="alert-message warning"><h4>Warning!</h4>Mis-configuring temperature control (ie. setting fan speed too low, setting target temperature too high, ...) may irreversibly damage your miner!<br></div>')
o.rawhtml = true

o = s:option(Flag, "fan-ctrl-enabled", translate("I understand"))

o = s:option(ListValue, "fan-ctrl", translate("Mode of fan control"))
o.oneline = false
o.widget = "radio"
o.optional = false
o.rmempty = true
o.default = "temp"
o.size = 1
o:depends("fan-ctrl-enabled", "1")
o:value("temp", translate("Automatic Fan Control"))
o:value("speed", translate("Fixed Fan Speed"))


o = s:option(DummyValue, "_note1", " ")
o:depends("fan-ctrl", "temp")
o.default = 'Target temperature is in degree celsius. '
if IS_AM1_MINER then
	o.default = o.default .. 'The fan controller is trying to keep maximum of "Temp2" over all chains close to this value (+- two degrees).'
else
	o.default = o.default .. 'The fan controller is trying to keep maximum of all temperatures close to this value (+- two degrees).'
end

o = s:option(Value, "fan-temp", translate("Target temperature &deg;C"))
o:depends("fan-ctrl", "temp")
o.datatype = ("and(uinteger,min(1),max(%d))"):format(MAX_TEMPERATURE)
o.default = DEFAULT_TEMPERATURE

o = s:option(DummyValue, "_note2", " ")
o:depends("fan-ctrl", "speed")
o.default = [[
	Target fan speed is in percent - "0" means fan off, "100" means fan
	full on. If you turn fan off (set it to 0%) and you will not provide
	additional way to cool the miner, it may overheat and die.

	However, cgminer will try to TURN ON the fans ANYWAY if the temperature
	reaches "dangerous" level, no matter what mode of control is selected,
	but the miner might be already damaged at this point.
]]

o = s:option(Value, "fan-speed", translate("Target fan speed %"))
o:depends("fan-ctrl", "speed")
o.datatype = "and(uinteger,min(0),max(100))"
o.default = DEFAULT_FAN_SPEED


if IS_AM1_MINER then
	s = m:section(TypedSection, "miners9", translate("Features"),
		translate("Additional miner feature configuration"))
	s.anonymous = true
	s.addremove = false

	o = s:option(Flag, "asicboost", translate("ASIC Boost Enable"))

	o = s:option(Flag, "overclock-enable", translate("Enable frequency scaling"))

	o = s:option(DummyValue, "_note3", " ")
	o:depends("overclock-enable", "1")
	o.default = [[
		Frequency scaling enables you to overclock or underclock by a constant
		factor. If your frequency is 650 MHz then multiplier of 1 keeps frequency as it is (650 MHz),
		1.05 overclocks frequency by 5% (682.5 MHz) and multiplier 0.93 underclocks frequency by 7% (604.5 MHz).

		If you override frequencies in chain configuration bellow,
		these frequencies will get scaled by the overclocking
		multiplier.
	]]

	o = s:option(DummyValue, "_note4", " ")
	o:depends("overclock-enable", "1")
	o.default = [[
		Overclocking is at your own risk and may damage
		your miner.
	]]


	o = s:option(Value, "overclock", translate("Frequency scaling multiplier"))
	o:depends("overclock-enable", "1")
	o.datatype = "range(0.01,2)"
	o.default = '1.00'

	s = m:section(TypedSection, "chainconfigs9", translate("Chain Configuration"),
		translate("Warning: overclocking is at your own risk and vary in performance from miner to miner. It may damage miner in overheating condition."))
	s.anonymous = false
	s.addremove = false
	s.template = "cbi/tblsection"
	function s:sectiontitle(section)
		local handler, id = get_handler(section)
		return ('Chain %d'):format(id)
	end

	o = s:option(Flag, "frequency_override", translate(""))

	o = s:option(Value, "frequency", translate("Frequency (MHz)"))
	o:depends("frequency_override", "1")
	o.datatype = "and(uinteger,min(100),max(1175))"
	o.placeholder = DEFAULT_FREQUENCY_S9
	o.default = DEFAULT_FREQUENCY_S9

	o = s:option(Flag, "voltage_override", translate(""))

	o = s:option(Value, "voltage", translate("Voltage (Volts)"))
	o:depends("voltage_override", "1")
	o.datatype = "range(7.9,9.4)"
	o.placeholder = DEFAULT_VOLTAGE_S9
	o.default = DEFAULT_VOLTAGE_S9

	local factor = 1
	if m:get("miners9", "overclock-enable") == '1' then
		local overclock = m:get("miners9", "overclock")
		if is_num(overclock) then
			factor = tonumber(overclock)
		end
	end
	o = s:option(DummyValue, "recommended_voltage", translate("Recommended voltage"))
	function o.cfgvalue(self, section)
		local freq = m:get(section, "frequency")
		if not freq or freq == '' then freq = DEFAULT_FREQUENCY_S9 end
		freq = freq * factor
		return ("%.2fV (for %.1f MHz)"):format(getFixedFreqVoltageValue(freq), freq)
	end
elseif IS_T1_MINER then
	s = m:section(TypedSection, "miner", translate("Miner"),
		translate("Warning: overclock is at your own risk and vary in performance from miner to miner. It may damage miner in overheating condition."))
	s.anonymous = true
	s.addremove = false

	o = s:option(Value, "frequency", translate("Frequency (MHz)"),
		translate("If you want to try overclock frequency, you usually need to adjust VID to be lower."))
	o.datatype = "and(uinteger,min(120),max(1596))"
	o.placeholder = DEFAULT_FREQUENCY
	o.default = DEFAULT_FREQUENCY

	o = s:option(Value, "voltage", translate("Voltage (Level)"),
		translate("The lower VID value means the higher voltage and higher power consumption."))
	o.datatype = "and(uinteger,min(1),max(31))"
	o.placeholder = DEFAULT_VOLTAGE
	o.default = DEFAULT_VOLTAGE

	o = s:option(StaticList, "chains", translate("Enabled Chains"))
	o.widget = "checkbox"
	o.rmempty = false
	o.optional = false
	for i=0,5 do
		o:value(i)
	end

	o = s:option(DummyValue, "hashrate", translate("Theoretical Hashrate"))
	function o.cfgvalue(self,section)
	  local CHIPS_PER_CHAIN = 63
	  local CORES_PER_CHIP = 32
	  local frequency = m:get(section, "frequency") or DEFAULT_FREQUENCY
	  local chains = m:get(section, "chains")
	  -- get number of enabled chains
	  chains = (chains and table.getn(chains)) or 0
	  return (frequency * 10^6 * 2 * CHIPS_PER_CHAIN * CORES_PER_CHIP * chains) / 10^12 .. " Th/s"
	end
end

return m
