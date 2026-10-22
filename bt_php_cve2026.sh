#!/bin/bash
#
# 宝塔面板 PHP 7.0 / 7.1 / 7.2 / 7.3 / 7.4 / 8.0 / 8.1 修复 PHP2Shell (CVE-2026-109618 / CVE-2026-109619)
#
# 原理：用打好补丁的 PHP 源码（各分支最后一个版本），按当前 PHP 完全相同的编译参数
#       重新编译并覆盖安装到 /www/server/php/<版本>。php.ini、FPM 配置、
#       已安装的第三方扩展（redis、swoole_loader 等）都保留不动。
#
# 用法（把本脚本和对应的 php-x.y.z-cve2026.tar.gz 放在同一目录）：
#   bash bt_php_cve2026.sh build    73   # 第 1 步：编译（耗时较长，不影响线上）
#   bash bt_php_cve2026.sh install  73   # 第 2 步：备份 → 替换 → 重启 → 自检（失败自动回滚）
#   bash bt_php_cve2026.sh rollback 73   # 需要时：回滚到升级前的备份
#   bash bt_php_cve2026.sh status   73   # 查看当前版本 / 是否已打补丁
#
# 其他版本把 73 换成 70 / 71 / 72 / 74 / 80 / 81 即可。

set -uo pipefail

ACTION=${1:-}
VER=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
STATE_DIR=/www/server/php-cve2026
LOG_DIR=$STATE_DIR/logs

red()   { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
info()  { echo -e "\033[36m==> $*\033[0m"; }
die()   { red "错误: $*"; exit 1; }

usage() {
    sed -n "9,15p" "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

[ -n "$ACTION" ] && [ -n "$VER" ] || usage
case "$VER" in
    70) PHP_FULL=7.0.33 ;;
    71) PHP_FULL=7.1.33 ;;
    72) PHP_FULL=7.2.34 ;;
    73) PHP_FULL=7.3.33 ;;
    74) PHP_FULL=7.4.33 ;;
    80) PHP_FULL=8.0.30 ;;
    81) PHP_FULL=8.1.34 ;;
    *)  die "版本只支持 70 71 72 73 74 80 81" ;;
esac
[ "$(id -u)" = 0 ] || die "请用 root 运行"

PREFIX=/www/server/php/$VER
INIT=/etc/init.d/php-fpm-$VER
SRC_TGZ=$HERE/php-$PHP_FULL-cve2026.tar.gz
BUILD_ROOT=$STATE_DIR/build-$VER
SRC_DIR=$BUILD_ROOT/php-$PHP_FULL
BACKUP_PTR=$STATE_DIR/last-backup-$VER
PID_FILE=$PREFIX/var/run/php-fpm.pid

mkdir -p "$LOG_DIR"

# 补丁后内存超限会直接 _exit(1) 且不输出到 stdout；未打补丁的 PHP 走普通 Fatal error，退出码 255
is_patched() {
    local out rc
    out=$("$1" -n -d memory_limit=8M -d display_errors=1 -r '$a = str_repeat("x", 32 * 1024 * 1024);' 2>/dev/null)
    rc=$?
    [ "$rc" = 1 ] && [ -z "$out" ]
}

linked_libs() {
    ldd "$1" 2>/dev/null | awk '/=> \//{print $3}' | sed 's#/lib/[^/]*-linux-gnu/#/lib/ARCH/#' | sort -u
}

fpm_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
}

fpm_stop() {
    if [ -x "$INIT" ]; then "$INIT" stop >/dev/null 2>&1 || true; fi
    for _ in $(seq 1 20); do fpm_running || return 0; sleep 0.5; done
    # init 脚本没停掉时兜底
    fpm_running && kill -QUIT "$(cat "$PID_FILE")" 2>/dev/null
    for _ in $(seq 1 20); do fpm_running || return 0; sleep 0.5; done
    return 1
}

fpm_start() {
    "$INIT" start >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do fpm_running && return 0; sleep 0.5; done
    return 1
}

do_status() {
    [ -x "$PREFIX/bin/php" ] || die "$PREFIX/bin/php 不存在"
    "$PREFIX/bin/php" -v | head -1
    if is_patched "$PREFIX/bin/php"; then
        green "已打 CVE-2026-109618/109619 补丁"
    else
        red "未打补丁（仍受 CVE-2026-109618/109619 影响）"
    fi
    if fpm_running; then echo "php-fpm-$VER: 运行中 (pid $(cat "$PID_FILE"))"; else echo "php-fpm-$VER: 未运行"; fi
}

do_build() {
    [ -x "$PREFIX/bin/php" ] || die "$PREFIX/bin/php 不存在，确认这是宝塔安装的 PHP $VER"
    [ -f "$SRC_TGZ" ] || die "找不到源码包 ${SRC_TGZ}（请和脚本放在同一目录）"

    # 1. 取出当前 PHP 的原始编译参数
    local raw
    raw=$("$PREFIX/bin/php" -n -i | sed -n 's/^Configure Command =>  *//p')
    [ -n "$raw" ] || die "读取不到原编译参数"
    local -a ARGS
    eval "ARGS=($raw)" || die "解析编译参数失败"
    [ "${ARGS[0]}" = "./configure" ] || die "编译参数格式不认识: $raw"
    printf '%s\n' "${ARGS[@]:1}" | grep -qx -- "--prefix=$PREFIX" || die "原编译 prefix 不是 ${PREFIX}，脚本不适用"
    # 宝塔原参数 + 不重装 PEAR（make install 时会联网下载，容易卡住；已装的 PEAR 不受影响）
    printf '%s\n' "${ARGS[@]:1}" | grep -q -- "pear" || ARGS+=("--without-pear")

    # 宝塔自己编译的库（/usr/local/openssl 等）通过 pkg-config 查找时需要 PKG_CONFIG_PATH，
    # 原编译参数里不会记录这个环境变量，这里按旧程序实际链接的库自动补上
    local d pcp=""
    for d in $(ldd "$PREFIX/sbin/php-fpm" 2>/dev/null | awk '/=> \/usr\/local\//{print $3}' | xargs -r -n1 dirname | sort -u); do
        [ -d "$d/pkgconfig" ] && pcp="$pcp${pcp:+:}$d/pkgconfig"
    done
    if [ -n "$pcp" ]; then
        export PKG_CONFIG_PATH="$pcp${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
    fi

    # 2. 空间 / 内存检查
    local avail_kb mem_kb jobs
    avail_kb=$(df -Pk "$STATE_DIR" | awk 'NR==2{print $4}')
    [ "$avail_kb" -gt 1572864 ] || die "$STATE_DIR 所在磁盘可用空间不足 1.5G"
    mem_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    [ -n "$mem_kb" ] || mem_kb=$(awk '/MemFree/{print $2}' /proc/meminfo)
    jobs=$(( mem_kb / 1048576 ))
    [ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
    [ "$jobs" -lt 1 ] && jobs=1
    if [ "$mem_kb" -lt 786432 ]; then
        red "提示：可用内存不足 768M，编译可能被系统 OOM 杀掉。建议先加 swap 或在业务低峰执行。"
    fi

    # 3. 解压并编译（全程不碰线上目录）
    info "解压源码到 $BUILD_ROOT"
    rm -rf "$BUILD_ROOT" && mkdir -p "$BUILD_ROOT"
    tar xzf "$SRC_TGZ" -C "$BUILD_ROOT" || die "解压失败"
    cd "$SRC_DIR" || die "源码目录不存在"

    info "configure（使用原编译参数，日志 $LOG_DIR/configure-$VER.log）"
    echo "${ARGS[*]}" > "$LOG_DIR/configure-cmd-$VER.txt"
    if ! "${ARGS[@]}" > "$LOG_DIR/configure-$VER.log" 2>&1; then
        tail -20 "$LOG_DIR/configure-$VER.log"
        die "configure 失败，线上 PHP 未受任何影响。把 $LOG_DIR/configure-$VER.log 发给我排查"
    fi

    info "make -j${jobs}（大约 10~40 分钟，日志 $LOG_DIR/make-$VER.log）"
    if ! make -j"$jobs" > "$LOG_DIR/make-$VER.log" 2>&1; then
        tail -30 "$LOG_DIR/make-$VER.log"
        die "编译失败，线上 PHP 未受任何影响。把 $LOG_DIR/make-$VER.log 发给我排查"
    fi

    # 4. 新程序自检
    local newphp=$SRC_DIR/sapi/cli/php
    "$newphp" -n -v | head -1
    is_patched "$newphp" || die "新编译的 PHP 自检失败（未检测到补丁）"
    "$newphp" -n -r 'echo "ok\n";' >/dev/null || die "新编译的 PHP 无法运行"

    # 5. 新旧 php-fpm 链接的系统库必须一致（防止误用系统自带的 openssl/curl 等）
    local libdiff
    libdiff=$(diff <(linked_libs "$PREFIX/sbin/php-fpm") <(linked_libs "$SRC_DIR/sapi/fpm/php-fpm"))
    if [ -n "$libdiff" ]; then
        echo "$libdiff" | tee "$LOG_DIR/libdiff-$VER.txt"
        if [ "${FORCE:-0}" != 1 ]; then
            die "新旧 php-fpm 链接的系统库不一致（< 旧  > 新），已停止。把上面的输出发给我；确认无影响可用 FORCE=1 跳过此检查"
        fi
        red "FORCE=1，忽略链接库差异"
    else
        echo "链接库检查：与原 php-fpm 一致"
    fi
    green "编译完成，补丁自检通过。下一步：bash $0 install $VER"
}

do_install() {
    [ -x "$SRC_DIR/sapi/cli/php" ] && [ -x "$SRC_DIR/sapi/fpm/php-fpm" ] \
        || die "还没编译，请先执行: bash $0 build $VER"
    is_patched "$SRC_DIR/sapi/cli/php" || die "编译产物自检失败，请重新 build"
    if is_patched "$PREFIX/bin/php"; then
        green "PHP $VER 已经是打过补丁的版本，无需重复安装"; exit 0
    fi
    [ -x "$INIT" ] || die "找不到 $INIT"

    local stamp backup was_running=0
    stamp=$(date +%Y%m%d-%H%M%S)
    backup=/www/server/php/$VER.bak-$stamp
    fpm_running && was_running=1

    # 升级前状态（扩展列表用于升级后对比）
    "$PREFIX/bin/php" -m 2>/dev/null | grep -v '^\[' | grep -v '^$' | sort > "$LOG_DIR/modules-before-$VER.txt"
    "$PREFIX/bin/php" -v | head -1 > "$LOG_DIR/version-before-$VER.txt"

    info "备份 $PREFIX → $backup"
    cp -a "$PREFIX" "$backup" || die "备份失败，未做任何改动"
    echo "$backup" > "$BACKUP_PTR"

    info "停止 php-fpm-${VER}（使用 PHP $VER 的站点会中断几秒）"
    fpm_stop || { red "php-fpm 停不下来，放弃升级"; fpm_start; exit 1; }

    info "安装新版本"
    if ! (cd "$SRC_DIR" && make install > "$LOG_DIR/install-$VER.log" 2>&1); then
        tail -20 "$LOG_DIR/install-$VER.log"
        red "make install 失败，自动回滚"
        restore "$backup" "$was_running"
        exit 1
    fi

    info "检查 php-fpm 配置"
    if ! "$PREFIX/sbin/php-fpm" -t > "$LOG_DIR/fpm-test-$VER.log" 2>&1; then
        cat "$LOG_DIR/fpm-test-$VER.log"
        red "php-fpm 配置检查失败，自动回滚"
        restore "$backup" "$was_running"
        exit 1
    fi

    if [ "$was_running" = 1 ]; then
        info "启动 php-fpm-$VER"
        if ! fpm_start; then
            red "php-fpm 启动失败，自动回滚"
            restore "$backup" "$was_running"
            exit 1
        fi
    fi

    # 自检
    local fail=0
    "$PREFIX/bin/php" -m 2>/dev/null | grep -v '^\[' | grep -v '^$' | sort > "$LOG_DIR/modules-after-$VER.txt"
    if ! is_patched "$PREFIX/bin/php"; then red "自检失败：未检测到补丁"; fail=1; fi
    local missing
    missing=$(comm -23 "$LOG_DIR/modules-before-$VER.txt" "$LOG_DIR/modules-after-$VER.txt")
    if [ -n "$missing" ]; then red "自检失败：升级后缺少扩展: $missing"; fail=1; fi
    if "$PREFIX/bin/php" -v 2>&1 | grep -qiE "warning|error"; then
        "$PREFIX/bin/php" -v; red "自检失败：php 启动有警告/错误"; fail=1
    fi
    if [ "$fail" = 1 ]; then
        red "自动回滚"
        restore "$backup" "$was_running"
        exit 1
    fi

    echo
    echo "升级前: $(cat "$LOG_DIR/version-before-$VER.txt")"
    echo "升级后: $("$PREFIX/bin/php" -v | head -1)"
    echo "扩展: $(wc -l < "$LOG_DIR/modules-after-$VER.txt") 个，与升级前一致"
    if [ "$was_running" = 1 ]; then echo "php-fpm-$VER: 运行中 (pid $(cat "$PID_FILE"))"; fi
    green "升级完成。备份在 $backup ，确认网站正常后可删除；有问题执行: bash $0 rollback $VER"
}

restore() {
    local backup=$1 start=$2
    fpm_stop || true
    rm -rf "$PREFIX.failed" && mv "$PREFIX" "$PREFIX.failed" && cp -a "$backup" "$PREFIX" \
        || die "回滚失败！请手动执行: rm -rf $PREFIX && cp -a $backup $PREFIX && $INIT start"
    rm -rf "$PREFIX.failed"
    if [ "$start" = 1 ]; then fpm_start || red "回滚后 php-fpm 启动失败，请检查 $INIT start 的输出"; fi
    "$PREFIX/bin/php" -v | head -1
    green "已回滚到 $backup"
}

do_rollback() {
    [ -f "$BACKUP_PTR" ] || die "没有找到备份记录"
    local backup
    backup=$(cat "$BACKUP_PTR")
    [ -x "$backup/bin/php" ] || die "备份目录 $backup 不完整"
    local was_running=0
    fpm_running && was_running=1
    info "回滚 $PREFIX ← $backup"
    restore "$backup" "$was_running"
}

case "$ACTION" in
    build)    do_build ;;
    install)  do_install ;;
    rollback) do_rollback ;;
    status)   do_status ;;
    *)        usage ;;
esac
