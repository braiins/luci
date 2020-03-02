#!/bin/bash

set -e

miner="root@miner.7.mr.ii.zone"
remote="$miner:/www/luci-static/resources/bosminer_config"

scp index.*.js "$remote/index.848f0c09460fb7b7c8db.js"
scp styles.*.js "$remote/styles.2907026f2b0537701527.js"
scp styles.*.css "$remote/styles.fac2d09b06ca0dcef0d3.css"

ssh "$miner" 'rm -rf /tmp/luci-*'
