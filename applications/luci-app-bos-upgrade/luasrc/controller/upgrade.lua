--[[

LuCI Cgminer module

Copyright (C) 2020  Braiins Systems s.r.o.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Braiins <braiins@braiins.com>

]]--

module("luci.controller.upgrade", package.seeall)

function index()
	entry({"admin", "system", "upgrade"}, cbi("upgrade"), _("Upgrade"), 65)
end
