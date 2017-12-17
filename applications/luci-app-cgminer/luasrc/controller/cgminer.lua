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

function index()
	entry({"admin", "services", "cgminer"}, cbi("cgminer"), _("CGMiner"))
end
