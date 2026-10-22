#!/bin/bash
#
# 生成打好补丁的 PHP 源码包 php-<版本>-cve2026.tar.gz，供 bt_php_cve2026.sh 使用。
#
# 步骤：从 php.net 下载官方源码 → 校验 SHA256（与 php.net 公布值一致）→ 打上 patches/ 里的补丁 → 重新打包
#
# 用法：
#   bash prepare_source.sh 73          # 生成 php-7.3.33-cve2026.tar.gz
#   bash prepare_source.sh all         # 生成全部 7 个版本
#
# 服务器访问不了 php.net 时，可以在任意 Linux / macOS 机器上生成，再上传到服务器脚本所在目录。

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

# 版本号 → 官方源码版本、php.net 公布的 tar.xz SHA256、补丁文件
info() {
    case "$1" in
        70) echo "7.0.33 ab8c5be6e32b1f8d032909dedaaaa4bbb1a209e519abb01a52ce3914f9a13d96 php-7.0.33-CVE-2026-109618-109619.patch" ;;
        71) echo "7.1.33 bd7c0a9bd5433289ee01fd440af3715309faf583f75832b64fe169c100d52968 php-7.1.33-CVE-2026-109618-109619.patch" ;;
        72) echo "7.2.34 409e11bc6a2c18707dfc44bc61c820ddfd81e17481470f3405ee7822d8379903 php-7.2.34-CVE-2026-109618-109619.patch" ;;
        73) echo "7.3.33 166eaccde933381da9516a2b70ad0f447d7cec4b603d07b9a916032b215b90cc php-7.3.33-CVE-2026-109618-109619.patch" ;;
        74) echo "7.4.33 924846abf93bc613815c55dd3f5809377813ac62a9ec4eb3778675b82a27b927 php-7.4.33-CVE-2026-109618-109619-official-712e60f9ed.patch" ;;
        80) echo "8.0.30 216ab305737a5d392107112d618a755dc5df42058226f1670e9db90e77d777d9 php-8.0.30-CVE-2026-109618-109619-official-82f8f31b16.patch" ;;
        81) echo "8.1.34 ffa9e0982e82eeaea848f57687b425ed173aa278fe563001310ae2638db5c251 php-8.1.34-CVE-2026-109618-109619-official-1d7dec178a.patch" ;;
        *)  return 1 ;;
    esac
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

prepare() {
    local ver=$1 full sum patchfile
    info "$ver" >/dev/null || { echo "不支持的版本: ${ver}（可选 70 71 72 73 74 80 81 all）"; exit 1; }
    read -r full sum patchfile <<< "$(info "$ver")"
    local out="$HERE/php-$full-cve2026.tar.gz"
    local work
    work=$(mktemp -d)

    echo "==> PHP ${full}：下载官方源码"
    local tarball="$work/php-$full.tar.xz"
    if [ -f "$HERE/php-$full.tar.xz" ]; then
        echo "    使用本地文件 $HERE/php-$full.tar.xz"
        cp "$HERE/php-$full.tar.xz" "$tarball"
    else
        curl -fsSL -o "$tarball" "https://www.php.net/distributions/php-$full.tar.xz" \
            || curl -fsSL -o "$tarball" "https://museum.php.net/php${full%%.*}/php-$full.tar.xz" \
            || { echo "下载失败：请检查网络，或手动下载 php-$full.tar.xz 后放到 $HERE 再运行"; exit 1; }
    fi

    local got
    got=$(sha256 "$tarball")
    if [ "$got" != "$sum" ]; then
        echo "SHA256 校验失败！期望 ${sum}，实际 $got"; exit 1
    fi
    echo "    SHA256 校验通过（与 php.net 公布值一致）"

    tar xJf "$tarball" -C "$work"
    echo "==> 打补丁 $patchfile"
    (cd "$work/php-$full" && patch -p1 -s < "$HERE/patches/$patchfile" && find . -name "*.orig" -delete) \
        || { echo "补丁应用失败"; exit 1; }
    mkdir -p "$work/php-$full/CVE-2026-PATCH"
    cp "$HERE/patches/$patchfile" "$work/php-$full/CVE-2026-PATCH/"

    echo "==> 打包 $out"
    (cd "$work" && tar czf "$out" "php-$full")
    echo "    完成：$(basename "$out")  sha256=$(sha256 "$out")"
    rm -rf "$work"
}

[ $# -eq 1 ] || { sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
command -v patch >/dev/null || { echo "缺少 patch 命令：apt-get install -y patch 或 yum install -y patch"; exit 1; }
command -v xz >/dev/null || { echo "缺少 xz 命令：apt-get install -y xz-utils 或 yum install -y xz"; exit 1; }

if [ "$1" = all ]; then
    for v in 70 71 72 73 74 80 81; do prepare "$v"; done
else
    prepare "$1"
fi
