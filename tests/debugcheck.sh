#!/bin/bash
# Debug (assertion-enabled) build of patched source; look for assertion failures / crashes
V=$1
cd /root && rm -rf dbg && mkdir dbg && tar xzf /host/deliver/php-$V-cve2026.tar.gz -C dbg && cd dbg/php-$V
./configure --disable-all --enable-debug --enable-cli --disable-cgi --enable-session --enable-json --without-pear > /root/dbg-configure.log 2>&1 || { tail /root/dbg-configure.log; exit 1; }
make -j2 > /root/dbg-make.log 2>&1 || { tail -20 /root/dbg-make.log; exit 1; }
echo "debug build ok: $(sapi/cli/php -n -v | head -1)"
sapi/cli/php -n -d max_input_vars=100000 /host/e2e/stress.php
TEST_PHP_EXECUTABLE=$PWD/sapi/cli/php NO_INTERACTION=1 sapi/cli/php run-tests.php -q -p $PWD/sapi/cli/php tests/basic tests/lang Zend/tests ext/standard/tests/array ext/standard/tests/strings ext/session/tests > /root/dbg-tests.log 2>&1
grep -E "^Tests (failed|passed)" /root/dbg-tests.log
echo "assertion/crash hits in outputs:"
grep -lE "Assertion .* failed|Segmentation fault|Termsig=|core dumped" $(find . -name "*.out" -o -name "*.log" | grep -v "^./rt.log") 2>/dev/null | head
grep -E "Termsig|Assertion" /root/dbg-tests.log | head
echo "debugcheck done"
