#!/bin/bash
set -euo pipefail
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
chmod +x files/etc/init.d/frpc 2>/dev/null || true
chmod +x files/usr/bin/frpc 2>/dev/null || true

# Patch frp 包:跳过 17MB Go 二进制编译与安装,改用内存拉取 wrapper
# 保留 init/config/uci-defaults 让 luci-app-frpc 正常工作,二进制走 /tmp
# 注意:Makefile 第28行是单美元 $(...) 而非双美元,因为在 define Package/frp/install 内直接展开
FRP_MK=feeds/packages/net/frp/Makefile
if [ ! -f "$FRP_MK" ]; then
    echo "[diy-part2] ERROR: missing $FRP_MK" >&2
    exit 1
fi

# 1) 注释掉二进制安装行,保留其余(init/config/uci-defaults)
# 真实行: \t$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/$(2) $(1)/usr/bin/
sed -i 's|^\t$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/$(2) $(1)/usr/bin/|\t# disabled: 17MB Go binary, use /tmp wrapper instead|' "$FRP_MK"
if grep -q '^\t$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/$(2) $(1)/usr/bin/' "$FRP_MK" || \
   ! grep -q 'disabled: 17MB Go binary, use /tmp wrapper instead' "$FRP_MK"; then
    echo "[diy-part2] ERROR: failed to remove frp binary install rule" >&2
    exit 1
fi

# 2) 在 BuildPackage eval 之前覆盖 Build/Compile,跳过 Go 编译。
if ! grep -q 'Build/Compile = true' "$FRP_MK"; then
    sed -i '/^include \.\.\/\.\.\/lang\/golang\/golang-package\.mk/a Build/Compile = true  # skip Go build, binary via /tmp wrapper at runtime' "$FRP_MK"
fi
compile_line=$(grep -n -m1 'Build/Compile = true' "$FRP_MK" | cut -d: -f1 || true)
eval_line=$(grep -n -m1 '\$(eval \$(call BuildPackage' "$FRP_MK" | cut -d: -f1 || true)
if [ -z "$compile_line" ] || [ -z "$eval_line" ] || [ "$compile_line" -ge "$eval_line" ]; then
    echo "[diy-part2] ERROR: Build/Compile override missing or placed after BuildPackage eval" >&2
    exit 1
fi
echo "[diy-part2] patched frp Makefile: skip binary install + Go build, use wrapper"

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate
