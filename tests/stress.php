<?php
// Exercise arrays created by php_register_variable_ex (singleton-sized in patched builds)
mt_srand(42);
$q = [];
for ($i = 0; $i < 300; $i++) {
    $q[] = "a[]=" . $i;
    $q[] = "h[k$i]=" . $i;
    $q[] = "n[x][y$i][]=" . $i;
    $q[] = "m[" . ($i % 7) . "][" . ($i % 5) . "]=" . $i;
    $q[] = "s[" . ($i * 3) . "]=" . $i;   // sparse int keys
}
$q[] = "one[only]=1"; $q[] = "single[]=x"; $q[] = "e[]=";
usort($q, function ($x, $y) { return strcmp(md5($x), md5($y)); });  // deterministic shuffle (7.0 shuffle ignores mt_srand)
parse_str(implode("&", $q), $r);
$out = [];
foreach ($r as $k => $v) {
    $c = $v;                         // copy (array dup on write)
    if (is_array($c)) {
        $c["new_" . $k] = 1;           // packed->hash / growth
        unset($c[array_keys($c)[0]]);  // delete
        ksort($c);
        $c = array_merge($c, ["z" => 1], [5, 6]);
        $c2 = array_flip(array_map("json_encode", array_values($c)));
        $iter = 0; foreach ($c as $kk => &$vv) { if (++$iter % 3 == 0) { $c["add$iter"] = $iter; } } unset($vv);
        $out[$k] = [count($c), count($c2), md5(serialize($c)), md5(json_encode($v))];
    }
}
ksort($out);
echo md5(serialize($out)), " ", count($r["a"]), " ", count($r["h"]), " ", count($r["n"]["x"]), " ", count($r["s"]), " ", json_encode($r["one"]), json_encode($r["single"]), json_encode($r["e"]), "\n";
// Deeply nested + many keys in one sub-array
parse_str(str_repeat("d", 1) . str_repeat("[a]", 60) . "=1&w[" . implode("]=1&w[", range(1, 2000)) . "]=1", $r2);
$d = $r2["d"]; $depth = 0; while (is_array($d)) { $d = reset($d); $depth++; }
echo "depth=$depth wcount=", count($r2["w"]), " sum=", array_sum(array_keys($r2["w"])), "\n";
