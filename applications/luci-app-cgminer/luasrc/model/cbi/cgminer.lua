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
local util = require("luci.util")
local class = util.class
require "ubus"

local DEFAULT_FREQUENCY = 1332
local DEFAULT_VOLTAGE = 10
local CGMINER_CONFIG = '/etc/cgminer.conf'

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
		keys = { 'frequency', 'voltage', 'chains' }
	}
}

local function get_handler(s)
	local name, id = parse_sect_name(s)
	if not name then return nil end
	return obj_handlers[name], id, name
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
	return true
end

function JsonUCICursor.save(self, config)
	nixio.fs.writefile(CGMINER_CONFIG, luci.jsonc.stringify(self.json))
end

function JsonUCICursor.foreach(self, config, sectiontype, fn)
	if sectiontype == 'pool' then
		fill_ids(self.json.pools)
		for i, pool in ipairs(self.json.pools) do
			fn{ ['.name'] = make_sect_name('pool', pool._id) }
		end
	elseif sectiontype == 'miner' then
		fn{ ['.name'] = 'miner' }
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

s = m:section(TypedSection, "miner", translate("Miner"),
	translate("Warning: overclock is at your own risk and vary in performance from miner to miner. It may damage miner in overheating condition."))
s.anonymous = true
s.addremove = false

o = s:option(Value, "frequency", translate("Frequency (MHz)"),
	translate("If you want to try overclock frequency, you usually need to adjust VID to be lower."))
o.datatype = "range(120,1332)"
o.placeholder = DEFAULT_FREQUENCY
o.default = DEFAULT_FREQUENCY

o = s:option(Value, "voltage", translate("Voltage (Level)"),
	translate("The lower VID value means the higher voltage and higher power consumption."))
o.datatype = "range(10,15)"
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

return m
