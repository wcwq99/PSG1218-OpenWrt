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
chmod +x files/etc/init.d/frpc 2>/dev/null || true
chmod +x files/usr/bin/frpc 2>/dev/null || true

# Patch frp 包:跳过 17MB Go 二进制编译与安装,改用内存拉取 wrapper
# 保留 init/config/uci-defaults 让 luci-app-frpc 正常工作,二进制走 /tmp
# 注意:Makefile 第28行是单美元 $(...) 而非双美元,因为在 define Package/frp/install 内直接展开
FRP_MK=feeds/packages/net/frp/Makefile
if [ -f "$FRP_MK" ]; then
    # 1) 注释掉二进制安装行(第28行),保留其余(init/config/uci-defaults)
    # 真实行: \t$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/$(2) $(1)/usr/bin/
    sed -i 's|^\t$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/$(2) $(1)/usr/bin/|\t# disabled: 17MB Go binary, use /tmp wrapper instead|' "$FRP_MK"
    # 2) 覆盖 Build/Compile,跳过 Go 编译
    #    golang-package.mk 把 Build/Compile 设为调用 golang-build.sh build,
    #    Namespace runner 上 Go module 下载不完整会导致编译失败。
    #    frp 二进制走 /tmp wrapper,编译时不需要构建 Go 产物。
    #    用变量式覆盖(=),在 include golang-package.mk 之后生效,使其变空。
    if ! grep -q 'Build/Compile =' "$FRP_MK"; then
        printf '\n# skip Go build, binary provided via /tmp wrapper at runtime\nBuild/Compile = true\n' >> "$FRP_MK"
    fi
    grep -q "use /tmp wrapper instead" "$FRP_MK" \
        && echo "[diy-part2] patched frp Makefile: skip binary install + Go build, use wrapper" \
        || echo "[diy-part2] WARNING: frp Makefile patch NOT applied, check pattern!"
fi

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate
