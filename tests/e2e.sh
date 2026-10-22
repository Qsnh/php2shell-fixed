#!/bin/bash
# End-to-end test for one PHP branch on a simulated BT server.
# usage: e2e.sh <70|71|72|73|74|80|81> <old-version>   (SKIP_RT=1 skips regression tests)
VER=$1; OLD=$2
set -u
P=/www/server/php/$VER
J=2
log() { echo "##### [$VER] $*"; }

COMMON="--prefix=$P --with-config-file-path=$P/etc --enable-fpm --with-fpm-user=www --with-fpm-group=www --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-iconv-dir --with-zlib --with-libxml-dir=/usr --enable-xml --disable-rpath --enable-bcmath --enable-shmop --enable-sysvsem --enable-inline-optimization --enable-mbregex --enable-mbstring --enable-intl --enable-ftp --with-mhash --enable-pcntl --enable-sockets --enable-soap --with-gettext --disable-fileinfo --enable-opcache"
case $VER in
  70|71) CFG="$COMMON --with-freetype-dir=/usr/local/freetype --with-jpeg-dir --with-png-dir --with-curl=/usr/local/curl --with-gd --with-openssl=/usr/local/openssl --with-mcrypt --with-xmlrpc --with-webp-dir=/usr" ;;
  72|73) CFG="$COMMON --with-freetype-dir=/usr/local/freetype --with-jpeg-dir --with-png-dir --with-curl=/usr/local/curl --with-gd --with-openssl=/usr/local/openssl --with-xmlrpc --with-sodium=/usr/local/libsodium --with-webp-dir=/usr" ;;
  74)    CFG="$COMMON --with-freetype --with-jpeg --with-curl --enable-gd --with-openssl --with-sodium --with-webp --with-xmlrpc" ;;
  80|81) CFG="$COMMON --with-freetype --with-jpeg --with-curl --enable-gd --with-openssl --with-sodium --with-webp" ;;
esac

log "build old $OLD (BT-style)"
cd /root && tar xJf /host/dl/php-$OLD.tar.xz && cd php-$OLD
./configure $CFG > /root/old-configure.log 2>&1 || { tail -30 /root/old-configure.log; exit 1; }
make -j$J > /root/old-make.log 2>&1 || { tail -30 /root/old-make.log; exit 1; }
make install > /root/old-install.log 2>&1 || { tail -30 /root/old-install.log; exit 1; }
EXTDIR=$($P/bin/php-config --extension-dir)
cd /root && rm -rf redis-5.3.7 && tar xzf /host/dl/redis-5.3.7.tgz && cd redis-5.3.7 && $P/bin/phpize >/dev/null 2>&1 && ./configure --with-php-config=$P/bin/php-config >/dev/null && make -j$J >/dev/null 2>&1 && make install >/dev/null
cp /root/php-$OLD/php.ini-production $P/etc/php.ini
printf 'extension = redis.so\n[Zend Opcache]\nzend_extension=%s/opcache.so\nopcache.enable = 1\n' "$EXTDIR" >> $P/etc/php.ini
cat > $P/etc/php-fpm.conf <<CONF
[global]
pid = $P/var/run/php-fpm.pid
error_log = $P/var/log/php-fpm.log
[www]
listen = /tmp/php-cgi-$VER.sock
listen.owner = www
listen.group = www
listen.mode = 0666
user = www
group = www
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
CONF
cp /root/php-$OLD/sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm-$VER && chmod +x /etc/init.d/php-fpm-$VER
mkdir -p /www/wwwroot/t
cat > /www/wwwroot/t/index.php <<'X'
<?php echo "PHP ", PHP_VERSION, " redis=", extension_loaded("redis")?"y":"n", " opcache=", function_exists("opcache_get_status")?"y":"n", "\n";
X
cat > /www/wwwroot/t/oom.php <<'X'
<?php ini_set("memory_limit","16M"); $a=[]; while(1) $a[]=str_repeat("x",1<<20);
X
cat > /www/wwwroot/t/seth.php <<'X'
<?php set_error_handler(function(){ echo "STALE_HANDLER\n"; return true; }); echo "SET\n";
X
cat > /www/wwwroot/t/notice.php <<'X'
<?php echo @$x, "OK ", getmypid(), "\n";
X
cat > /www/wwwroot/t/gpc.php <<'X'
<?php parse_str(str_repeat("a[]=1&", 500) . "b[x][y][z]=2&c[]=3&c[k]=4", $o); echo "GPC ", count($o["a"]), " ", $o["b"]["x"]["y"]["z"], " ", json_encode($o["c"]), " ", count($_GET["q"] ?? []), "\n";
X
/etc/init.d/php-fpm-$VER start >/dev/null
r() { SCRIPT_FILENAME=/www/wwwroot/t/$1 QUERY_STRING="${2:-}" REQUEST_METHOD=GET cgi-fcgi -bind -connect /tmp/php-cgi-$VER.sock 2>&1 | tail -1; }
log "old: $(r index.php)"

log "script: status/build/install"
mkdir -p /root/phpfix && cp /host/deliver/bt_php_cve2026.sh /host/deliver/php-*-cve2026.tar.gz /root/phpfix/ && cd /root/phpfix
bash bt_php_cve2026.sh status $VER
bash bt_php_cve2026.sh build $VER 2>&1 | tail -4
(/www/server/php/$VER/bin/php -r 'sleep(120);' &)
bash bt_php_cve2026.sh install $VER 2>&1 | tail -5
bash bt_php_cve2026.sh status $VER

log "fpm behaviour"
r index.php
r gpc.php "q[]=1&q[]=2&q[a][b]=3"
r oom.php >/dev/null; r notice.php
for i in 1 2 3 4; do r seth.php >/dev/null; done
for i in 1 2 3; do r notice.php; done
grep -E "exited with code" $P/var/log/php-fpm.log | tail -1

log "rollback + reinstall"
bash bt_php_cve2026.sh rollback $VER 2>&1 | tail -2; r index.php
bash bt_php_cve2026.sh install $VER 2>&1 | tail -3; r index.php

if [ "${SKIP_RT:-0}" = 1 ]; then log "DONE (regression tests skipped)"; exit 0; fi
log "regression tests: old tree vs patched tree"
TESTS="Zend/tests tests/basic tests/lang ext/session/tests ext/standard/tests/strings ext/standard/tests/general_functions ext/standard/tests/array"
NEW=$(ls -d /www/server/php-cve2026/build-$VER/php-*)
for tree in /root/php-$OLD $NEW; do
  ( cd $tree && TEST_PHP_EXECUTABLE=$tree/sapi/cli/php NO_INTERACTION=1 $tree/sapi/cli/php run-tests.php -q $( [ $VER -ge 80 ] && echo -j$J ) -p $tree/sapi/cli/php $TESTS > $tree/rt.log 2>&1
    grep -E "^Tests (failed|passed)" $tree/rt.log | sed "s#^#$(basename $tree): #"
    sed -n '/^FAILED TEST SUMMARY/,/^=====/p' $tree/rt.log | grep -oE '\[[^]]+\.phpt\]' | sort > $tree/rt.fail )
done
echo "only-failing-in-patched:"; comm -13 /root/php-$OLD/rt.fail $NEW/rt.fail
echo "only-failing-in-old:"; comm -23 /root/php-$OLD/rt.fail $NEW/rt.fail
log "DONE"
