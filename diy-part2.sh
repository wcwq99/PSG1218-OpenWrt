#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 给自定义 init 脚本加执行权限(git 不保留可执行位)
# diy-part2 在 cd openwrt 后执行,files 已移至 openwrt/files
chmod +x files/etc/init.d/sing-box 2>/dev/null || true

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate
