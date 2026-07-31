#!/bin/bash
#
# K2 OpenWrt 本地编译辅助脚本
# 用法: ./build-local.sh [clean|cache|all]
#   all    (默认) 检测环境 + 克隆 + feeds + 编译
#   clean  清理 build_dir/staging_dir 后全量编译
#   cache  保留缓存增量编译
#   env    只检测环境不编译
#
set -e

# ============ 配置 ============
REPO_URL="https://github.com/coolsnowwolf/lede"
REPO_BRANCH="master"
WORKDIR="${WORKDIR:-$HOME/openwrt-k2}"
CONFIG_FILE="k2.config"
DIY_P1="diy-part1.sh"
DIY_P2="diy-part2.sh"
JOBS="${JOBS:-$(($(nproc)-1))}"
[ "$JOBS" -lt 1 ] && JOBS=1

# 颜色
G() { printf '\033[32m%s\033[0m\n' "$1"; }
Y() { printf '\033[33m%s\033[0m\n' "$1"; }
R() { printf '\033[31m%s\033[0m\n' "$1"; }
B() { printf '\033[36m%s\033[0m\n' "$1"; }

MODE="${1:-all}"

# 仓库目录(本脚本所在目录),必须在任何 cd 之前解析成绝对路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============ 环境检测 ============
check_env() {
    B "=== [1/5] 环境检测 ==="

    # OS 检测
    if grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
        G "OS: $(grep '^PRETTY_NAME' /etc/os-release | cut -d'"' -f2)"
    else
        R "⚠ 当前 OS 非 Ubuntu/Debian,本脚本依赖 apt,可能不兼容"
        R "  推荐用 Ubuntu 22.04 (WSL2/虚拟机/物理机均可)"
        read -p "继续吗? [y/N] " c; [ "$c" != "y" ] && exit 1
    fi

    # CPU/内存
    B "  CPU 核心数: $(nproc)"
    B "  内存: $(free -h | awk '/^Mem:/{print $2}')"
    B "  磁盘可用: $(df -h "$HOME" | awk 'NR==2{print $4}')"
    if [ "$(nproc)" -lt 2 ]; then Y "⚠ CPU 少于 2 核,编译会很慢"; fi
    local mem_mb; mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$mem_mb" -lt 4000 ]; then Y "⚠ 内存 < 4GB,建议加 swap 防 OOM"; fi
    local disk_gb; disk_gb=$(df -BG "$HOME" | awk 'NR==2{print $4}' | tr -d 'G')
    if [ "$disk_gb" -lt 20 ]; then R "✗ 磁盘 < 20GB,编译需 ~15GB,空间不足"; exit 1; fi

    # 必备命令
    local missing=()
    for cmd in git make gcc g++ wget curl; do
        command -v $cmd >/dev/null 2>&1 || missing+=($cmd)
    done
    if [ ${#missing[@]} -gt 0 ]; then
        Y "缺少命令: ${missing[*]},自动安装..."
    fi

    # 安装编译依赖(同 build-k2.yml,适配 Ubuntu 24.04 / Python 3.12+)
    B "  安装编译依赖(需 sudo)..."
    sudo -E apt-get -qq update
    sudo -E apt-get -qq install -y build-essential clang flex bison gperf gawk \
        git-lfs libelf-dev libssl-dev libncurses-dev autoconf automake \
        jq rsync unzip wget zip zlib1g-dev python3 python3-setuptools \
        python3-venv file 2>/dev/null || true
    sudo -E apt-get -qq autoremove --purge 2>/dev/null || true

    # Ubuntu 24.04 / Python 3.12+ 移除了 distutils,旧 LEDE 构建脚本仍依赖它
    # 装 setuptools 提供 distutils 兼容层,并设环境变量让旧脚本找到
    if ! python3 -c "import distutils" 2>/dev/null; then
        Y "  Python distutils 缺失,安装 setuptools 兼容层..."
        pip3 install --user setuptools 2>/dev/null || true
    fi
    export SETUPTOOLS_USE_DISTUTILS=local
    G "✓ 依赖安装完成"
}

# ============ 克隆源码 ============
clone_src() {
    B "=== [2/5] 克隆 LEDE 源码 ==="
    if [ -d "$WORKDIR/openwrt/.git" ]; then
        G "✓ 源码已存在,拉取更新..."
        cd "$WORKDIR/openwrt"
        git fetch --depth 1 origin $REPO_BRANCH
        git reset --hard origin/$REPO_BRANCH
    else
        mkdir -p "$WORKDIR"
        cd "$WORKDIR"
        git clone --depth 1 $REPO_URL -b $REPO_BRANCH openwrt
    fi
}

# ============ Feeds + DIY ============
setup_feeds() {
    B "=== [3/5] Feeds + DIY 脚本 ==="
    cd "$WORKDIR/openwrt"

    # 复制本仓库的 diy/files/config 到源码目录
    local repo_dir="$SCRIPT_DIR"
    [ -f "$repo_dir/$DIY_P1" ] && cp "$repo_dir/$DIY_P1" . && chmod +x $DIY_P1
    [ -f "$repo_dir/$DIY_P2" ] && cp "$repo_dir/$DIY_P2" . && chmod +x $DIY_P2
    [ -d "$repo_dir/files" ] && rm -rf files && cp -r "$repo_dir/files" files
    [ -f "$repo_dir/$CONFIG_FILE" ] && cp "$repo_dir/$CONFIG_FILE" .config

    # part1 (feeds update 前)
    ./$DIY_P1
    ./scripts/feeds update -a
    ./scripts/feeds install -a

    # part2 (feeds install 后,load config 前)
    ./$DIY_P2

    G "✓ Feeds 与 DIY 完成"
}

# ============ 编译 ============
compile() {
    B "=== [4/5] 编译 ($JOBS jobs) ==="
    cd "$WORKDIR/openwrt"

    if [ "$MODE" = "clean" ]; then
        Y "清理 build_dir/staging_dir,全量编译..."
        make clean
    fi

    B "  make defconfig..."
    make defconfig

    B "  下载包..."
    make download -j8
    find dl -size -1024c -exec rm -f {} \; 2>/dev/null || true

    B "  编译固件(约 40-90 分钟)..."
    local start; start=$(date +%s)
    if make -j$JOBS; then
        local elapsed; elapsed=$(( ($(date +%s) - start) / 60 ))
        G "✓ 编译成功,耗时 ${elapsed} 分钟"
    else
        R "✗ 并行编译失败,重试 V=s 看错误..."
        make -j$JOBS V=sc 2>&1 | tail -150
        R "✗ 编译失败,见上方日志"
        exit 1
    fi
}

# ============ 输出固件 ============
show_fw() {
    B "=== [5/5] 固件产物 ==="
    cd "$WORKDIR/openwrt/bin/targets/"*/* 2>/dev/null || { R "✗ 产物目录不存在"; exit 1; }
    echo ""
    ls -la *.bin 2>/dev/null || R "✗ 未找到 .bin 固件(可能超 IMAGE_SIZE 被拒)"
    echo ""
    local sysup; sysup=$(ls *sysupgrade.bin 2>/dev/null | head -1)
    if [ -n "$sysup" ]; then
        local sz; sz=$(stat -c%s "$sysup")
        local sz_mb; sz_mb=$(awk "BEGIN{printf \"%.2f\", $sz/1048576}")
        if [ "$sz" -le 8060928 ]; then
            G "✓ $sysup ($sz_mb MB) ≤ 8MB,可刷入 K2"
        else
            R "✗ $sysup ($sz_mb MB) > 8MB,超 K2 Flash 限制"
        fi
    fi
    B "manifest 包数: $(wc -l < *.manifest 2>/dev/null || echo '?')"
    echo ""
    B "产物目录: $PWD"
}

# ============ 主流程 ============
case "$MODE" in
    env)   check_env ;;
    clean|cache|all)
        check_env
        clone_src
        setup_feeds
        compile
        show_fw
        ;;
    *) R "用法: $0 [all|clean|cache|env]"; exit 1 ;;
esac
