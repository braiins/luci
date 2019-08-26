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
	entry({"admin", "miner", "overview"}, template("info"), _("Overview"), 1)
end
