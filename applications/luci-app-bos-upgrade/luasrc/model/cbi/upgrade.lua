--[[

LuCI Cgminer module

Copyright (C) 2020  Braiins Systems s.r.o.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Braiins <braiins@braiins.com>

]]--

local m = Map("bos", translate("System Upgrade"),
translate("Configure the firmware to monitor our feeds server for new releases and automatically install them."))

local s = m:section(NamedSection, "auto_upgrade", "bos")
s.anonymous = true

local o = s:option(Flag, "enable", translate("Enable Auto Upgrade"))
o.rmempty=false

return m
