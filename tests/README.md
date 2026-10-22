# tests

在 Docker 里模拟"Ubuntu 16.04 + 宝塔编译安装的 PHP"环境，对修复包做端到端测试时用到的脚本。路径约定：仓库内容和官方源码挂载在容器的 `/host` 下（`/host/dl` 放 php.net 官方源码与 redis 扩展源码，`/host/deliver` 放脚本和源码包）。

| 文件 | 用途 |
|---|---|
| `base.sh` | 构建基础镜像：安装编译依赖，模拟宝塔的 `/usr/local/{openssl,curl,freetype,libsodium}` 目录，创建 www 用户 |
| `e2e.sh <70\|71\|72\|80\|81> <旧版本>` | 按宝塔编译参数装好未打补丁的 PHP（含 redis、opcache、php-fpm 服务），然后用 `bt_php_cve2026.sh` 执行 status / build / install / rollback；跑 FPM 行为测试；与未打补丁的同版本对比回归测试 |
| `stress.php` | 构造大量嵌套、稀疏、混合键的请求参数，对比打补丁前后的数组行为（7.0 – 7.2 的 `array_init_singleton` 是按旧数组结构适配的） |
| `debugcheck.sh <完整版本号>` | 用开启断言的调试版本编译打补丁后的源码，跑测试，检查有没有断言失败或崩溃 |

示例：

```bash
docker run -d --name base -v $PWD:/host ubuntu:16.04 sleep infinity
docker exec base bash /host/tests/base.sh && docker commit base btxenial-base
docker run -d --name e2e72 -v $PWD:/host:ro btxenial-base sleep infinity
docker exec e2e72 bash /host/tests/e2e.sh 72 7.2.34
```
