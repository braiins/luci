--[[

LuCI Cgminer module

Copyright (C) 2018  Braiins Systems s.r.o.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Author: Jakub Horak <jakub.horak@braiins.com>

]]--
module("luci.controller.admin.nandinstall", package.seeall)

local UPGRADE_LOG = '/tmp/nand_install_progress.lock'

function index()
	local fs = require "nixio.fs"

	entry({"admin", "system", "nandinstall"}, call("action_nandinstall"), _("Install Current System to Device (NAND)"), 70)
	entry({"admin", "system", "nandinstall", "install"}, post("action_nandinstall_install"))
	entry({"admin", "system", "nandinstall", "progresspage"}, call("action_nandinstall_progresspage"))
	entry({"admin", "system", "nandinstall", "progress"}, call("action_nandinstall_progress"))

end

function action_nandinstall()
	luci.template.render("admin_system/nandinstall", {
	})
end

function action_nandinstall_progress()
	luci.http.prepare_content("application/json")
	local status = 'error'
	local operation = 'n/a'
	local lines = {}
	local f = io.open(UPGRADE_LOG, 'r')
	if f then
		status = 'ok'
		operation = 'in progress'
		local contents = f:read('*a')
		-- grab only completed lines
		for line in contents:gmatch('(.-)\n') do
			prefix, data = line:match('^(%w+) (.*)$')
			if prefix == 'stdout' or prefix == 'stderr' then
				lines[#lines + 1] = data
			elseif prefix == 'exit' then
				if tonumber(data) == 0 then
					operation = 'succeeded'
				else
					operation = 'failed'
					lines[#lines + 1] = 'Process return code was '..data
				end
			end
		end
		f:close()
	end
	local resp = {
		lines = lines,
		operation = operation,
		status = status,
		date = os.date('%c'),
	}
	luci.http.write_json(resp)
	os.exit(0)
end

function action_nandinstall_progresspage()
	luci.template.render("admin_system/nandinstall_progress", {
	})
end

function action_nandinstall_install()
	local f = io.popen("run-background-process "..UPGRADE_LOG.." 'miner nand_install'", "r")
	for line in f:lines() do end
	luci.http.redirect(luci.dispatcher.build_url("admin/system/nandinstall/progresspage"))
end
