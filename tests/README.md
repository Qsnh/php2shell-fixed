# tests

在 Docker 里模拟"Ubuntu 16.04 / CentOS 7 + 宝塔编译安装的 PHP"环境，对修复包做端到端测试时用到的脚本。路径约定：仓库内容和官方源码挂载在容器的 `/host` 下（`/host/dl` 放 php.net 官方源码与 redis 扩展源码，`/host/deliver` 放脚本和源码包）。

| 文件 | 用途 |
|---|---|
| `base.sh` | 构建 Ubuntu 16.04 基础镜像：安装编译依赖，模拟宝塔的 `/usr/local/{openssl,curl,freetype,libsodium}` 目录，创建 www 用户 |
| `base-centos7.sh` | 构建 CentOS 7 基础镜像，内容同上（yum 源指向 vault.centos.org 和 EPEL 归档） |
| `e2e.sh <54\|55\|56\|70\|71\|72\|73\|74\|80\|81> <旧版本>` | 按宝塔编译参数装好未打补丁的 PHP（含 redis、opcache、php-fpm 服务），然后用 `bt_php_cve2026.sh` 执行 status / build / install / rollback；跑 FPM 行为测试；与未打补丁的同版本对比回归测试 |
| `stress.php` | 构造大量嵌套、稀疏、混合键的请求参数，对比打补丁前后的数组行为（7.0 – 7.2 的 `array_init_singleton` 是按旧数组结构适配的） |
| `debugcheck.sh <完整版本号>` | 用开启断言的调试版本编译打补丁后的源码，跑测试，检查有没有断言失败或崩溃 |

示例：

```bash
docker run -d --name base -v $PWD:/host ubuntu:16.04 sleep infinity
docker exec base bash /host/tests/base.sh && docker commit base btxenial-base
docker run -d --name e2e72 -v $PWD:/host:ro btxenial-base sleep infinity
docker exec e2e72 bash /host/tests/e2e.sh 72 7.2.34
```

- 设置环境变量 `SKIP_RT=1` 可以跳过回归测试
- 在 ARM64 的 CentOS 7 上测 7.4 / 8.0 / 8.1 时，需要加 `-e ac_cv__asm_goto=no`（gcc 4.8.5 不支持其中一段 ARM 内联汇编；x86_64 不需要）
- **5.4 / 5.5 / 5.6**：`/host/dl` 里的 redis 扩展源码要用 PHP5 兼容的 **phpredis 4.3.0**（`redis-4.3.0.tgz`，5.3.7 只支持 PHP7+）；5.4 没有内置 opcache，脚本会自动跳过 opcache。在 **ARM64** 上测 5.4 时，官方 2015 年的 `config.guess` 不认识 `aarch64`，需要 `-e BT_BUILD="--build=aarch64-unknown-linux-gnu --host=aarch64-unknown-linux-gnu"`；x86_64 不需要
