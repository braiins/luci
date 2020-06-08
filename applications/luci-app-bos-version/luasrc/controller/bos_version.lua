--[[

LuCI BraiinsOS version reporting module

Copyright (C) 2020  Braiins Systems s.r.o.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Braiins <braiins@braiins.com>

example: `curl http://hostname/cgi-bin/luci/bos/info`

]]--

module("luci.controller.bos_version", package.seeall)

local http = require "luci.http"

function index()
	local bos = node("bos")

	-- endpoint with everything in JSON format
	node("bos", "info").target = call("bos_info")

	-- endpoints with version strings and mode as text
	node("bos", "version").target = call("bos_version")
	node("bos", "major").target = call("bos_major")
	node("bos", "mode").target = call("bos_mode")
end


local function read_line(path)
	local f = io.open(path, "r")
	return (f and f:read("*l")) or ""
end

local function read_bos_version()
	return read_line("/etc/bos_version")
end

local function read_bos_major()
	return read_line("/etc/bos_major")
end

local function read_bos_mode()
	return read_line("/etc/bos_mode")
end


function bos_info()
	local info = {
		version = read_bos_version(),
		major = read_bos_major(),
		mode = read_bos_mode(),
	}

	http.prepare_content("application_json")
	http.write_json(info)
end

function bos_version()
	local version = read_bos_version()

	http.prepare_content("text/plain")
	http.write(version)
end

function bos_major()
	local major = read_bos_major()

	http.prepare_content("text/plain")
	http.write(major)
end

function bos_mode()
	local mode = read_bos_mode()

	http.prepare_content("text/plain")
	http.write(mode)
end
