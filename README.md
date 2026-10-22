# php2shell-fixed

> 联系方式：有事情可以联系 <https://x.com/0xTYZ>

宝塔面板（BT Panel）上已停止维护的 PHP 版本（7.0 – 8.1）的 **PHP2Shell（CVE-2026-109618 / CVE-2026-109619）修复包**。仓库里有打好补丁的源码包，以及一键完成编译、替换、回滚的脚本。

> Patched PHP source tarballs and a one-command upgrade script that fix PHP2Shell (CVE-2026-109618 / CVE-2026-109619) for end-of-life PHP 7.0 – 8.1 builds installed by BT Panel (宝塔).

---

## 漏洞简介

2026-10-21，PHP 官方披露了两个漏洞，CVSS v4.0 评分都是 9.2，**无需登录即可远程执行代码**：

| CVE | 说明 |
|---|---|
| [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) | 内存耗尽时，请求数据只初始化了一半，清理阶段被当作有效数据使用，导致远程代码执行 |
| [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp) | 上一个请求留下的内部状态在内存释放后仍被保留，被同一 worker 的下一个请求使用，导致远程代码执行 |

PHP-FPM、Apache mod_php、php-cgi 等处理 Web 请求的方式都受影响。PHP 官方只为 8.2 – 8.5 发布了修复版本（8.2.35 / 8.3.36 / 8.4.27 / 8.5.12）。8.1 及更早的版本没有正式修复版：官方只给 7.4、8.0、8.1 发了源码补丁，7.3 及以下什么都没有。

官方公告：<https://www.php.net/archive/2026.php#2026-10-21-5>

## 支持的版本

| 宝塔 PHP 版本 | 升级后 | 补丁来源 | 源码包 |
|---|---|---|---|
| 7.0.x | 7.0.33 | 基于官方 7.4 补丁移植（**非官方**） | `php-7.0.33-cve2026.tar.gz` |
| 7.1.x | 7.1.33 | 基于官方 7.4 补丁移植（**非官方**） | `php-7.1.33-cve2026.tar.gz` |
| 7.2.x | 7.2.34 | 基于官方 7.4 补丁移植（**非官方**） | `php-7.2.34-cve2026.tar.gz` |
| 7.3.x | 7.3.33 | 基于官方 7.4 补丁移植（**非官方**） | `php-7.3.33-cve2026.tar.gz` |
| 7.4.x | 7.4.33 | PHP 官方补丁 [`712e60f9ed`](https://github.com/php/php-src/commit/712e60f9ed) | `php-7.4.33-cve2026.tar.gz` |
| 8.0.x | 8.0.30 | PHP 官方补丁 [`82f8f31b16`](https://github.com/php/php-src/commit/82f8f31b16) | `php-8.0.30-cve2026.tar.gz` |
| 8.1.x | 8.1.34 | PHP 官方补丁 [`1d7dec178a`](https://github.com/php/php-src/commit/1d7dec178a) | `php-8.1.34-cve2026.tar.gz` |

- 每个源码包都是 **php.net 官方发布的源码**（SHA256 与 php.net 公布值一致），加上 `patches/` 目录里对应的补丁。包内的 `CVE-2026-PATCH/` 目录也附了补丁原文
- 升级目标是各分支的最后一个版本，所以同时也会带上这些年已发布的其他安全修复
- 同一大版本内升级，扩展 ABI 不变，redis、swoole_loader 等已安装的扩展**不需要重新编译**
- **PHP 8.2 及以上**：直接在宝塔面板里更新到官方修复版即可，不需要本仓库

> ⚠️ 7.0 – 7.3 的补丁是从官方 7.4 补丁移植的，**没有经过 PHP 官方审核**。移植细节见下文的[补丁说明](#补丁说明)。介意的话请优先升级到 PHP 8.2+。

## 支持的系统

脚本只依赖 bash、coreutils、gcc/make 这些基础工具，用服务器上**原来编译 PHP 的环境和编译参数**重新编译，不绑定具体发行版。

| 系统 | 编译器 | 实测情况 |
|---|---|---|
| Ubuntu 16.04 | gcc 5.4 | ✅ 7 个版本全流程；全部回归测试 |
| CentOS 7 | gcc 4.8.5 | ✅ 7 个版本全流程；7.2 / 8.1 回归测试 |
| Debian、Ubuntu 18.04+、CentOS 8 / Rocky / AlmaLinux 等 | — | 未实测，理论上可用 |

"理论上可用"的前提是：宝塔当初能在这台服务器上把这个 PHP 编译出来。如果之后系统升级过（比如 openssl 被换掉了），`build` 这一步可能会失败。失败时线上 PHP 不受任何影响，把 `/www/server/php-cve2026/logs/` 里的日志拿去排查即可。

## 快速开始

以 PHP 7.4 为例，其他版本把 `74` 换成 `70` / `71` / `72` / `73` / `80` / `81`。所有命令都用 root 执行。

### 1. 下载脚本和源码包

只需要下载**脚本**和**你要升级的版本对应的源码包**，放在同一个目录里：

```bash
mkdir -p /root/phpfix && cd /root/phpfix
wget https://github.com/qsnh/php2shell-fixed/raw/main/bt_php_cve2026.sh
wget https://github.com/qsnh/php2shell-fixed/raw/main/php-7.4.33-cve2026.tar.gz
wget https://github.com/qsnh/php2shell-fixed/raw/main/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing      # 已下载的文件都应显示 OK
```

CentOS 7 的 `sha256sum`（coreutils 8.22）不支持 `--ignore-missing`，改用下面这条，只校验已下载的文件：

```bash
grep -E "bt_php_cve2026.sh|php-7.4.33" SHA256SUMS | sha256sum -c
```

服务器访问 GitHub 很慢的话，可以在本地电脑下载好，再用宝塔面板的"文件"功能上传到 `/root/phpfix`。

### 2. 确认哪些站点在用哪个 PHP

```bash
grep -ho "enable-php-[0-9]*" /www/server/panel/vhost/nginx/*.conf | sort | uniq -c
bash bt_php_cve2026.sh status 74
```

### 3. 编译（不影响线上）

```bash
screen -S phpfix                 # 防止 SSH 断开导致编译中断（没有就 apt-get install screen / yum install screen）
bash bt_php_cve2026.sh build 74
```

大约需要 10 – 40 分钟，看到"编译完成，补丁自检通过"就成功了。这一步失败的话线上不受任何影响，日志在 `/www/server/php-cve2026/logs/`。

可用内存不足 1G 时，建议先加一块临时 swap：

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
```

### 4. 安装（建议在业务低峰期）

```bash
bash bt_php_cve2026.sh install 74
```

脚本会依次：
1. 完整备份到 `/www/server/php/74.bak-<时间戳>`
2. 停止 php-fpm，安装新版本
3. 检查 FPM 配置并重新启动
4. 自检：补丁是否生效、扩展有没有少、启动有没有报错

**任何一步失败都会自动回滚。** 使用该 PHP 版本的站点只会中断几秒钟。

### 5. 验证

```bash
bash bt_php_cve2026.sh status 74     # 应显示"已打 CVE-2026-109618/109619 补丁"
```

然后打开网站，把登录、上传、支付这些关键功能点一遍。

### 回滚

```bash
bash bt_php_cve2026.sh rollback 74
```

### 收尾

确认网站正常运行几天后，可以删除编译目录和备份：

```bash
rm -rf /www/server/php-cve2026/build-*
rm -rf /www/server/php/*.bak-*
```

## 脚本做了什么

`bt_php_cve2026.sh <build|install|rollback|status> <版本>`

- **原样复用编译参数**：从当前 PHP 的 `php -i` 里读取 `Configure Command`，原样复用宝塔当初的编译参数，只额外加了 `--without-pear`，避免 `make install` 时联网下载 PEAR
- **找到宝塔自带的库**：宝塔会把 openssl、curl 等库编译到 `/usr/local/*`。脚本会根据旧 php-fpm 实际链接的库，自动设置 `PKG_CONFIG_PATH`
- **检查链接库一致**：编译完会对比新旧 php-fpm 链接的系统库，不一致就停止，防止误用系统自带的 openssl
- **配置和扩展不动**：`php.ini`、`php-fpm.conf`、第三方扩展都保持原样
- **自检补丁是否生效**：通过内存超限时的行为判断，打补丁后会直接 `_exit(1)`，未打补丁的 PHP 是普通 Fatal error，退出码 255。所有版本都用这个方法
- **重复执行安全**：如果当前已经是打过补丁的版本，`install` 会直接退出，不会覆盖备份

适用条件：宝塔从源码编译安装的 PHP，安装在 `/www/server/php/<版本>`，服务名 `php-fpm-<版本>`。不是宝塔安装的 PHP，可以直接使用 `patches/` 里的补丁自行编译。

## 补丁带来的行为变化

官方补丁对已停止维护的版本采取的是**最小化缓解**措施，会带来以下可感知的变化，所有版本都一样：

- 内存超限，或内存分配大小溢出时，不再走普通的 Fatal error 流程，而是把错误写到 stderr 后**直接结束 worker 进程**，FPM 会自动拉起新进程。因此：
  - `register_shutdown_function`、输出缓冲回调等**不会再执行**
  - 错误信息要在 php-fpm 日志里查看（需要 `catch_workers_output = yes`）
- **session 上传进度**（`session.upload_progress`）功能被关闭
- 新增 `max_multipart_body_parts`（8.0 / 8.1 原本就有），默认等于 `max_input_vars + max_file_uploads`，超出的 multipart 段会被丢弃并报 Warning
- multipart 请求头只保留 `Content-Disposition` 和 `Content-Type`，重复的头会被忽略

## 补丁说明

`patches/` 目录：

| 文件 | 说明 |
|---|---|
| `php-7.4.33-…-official-712e60f9ed.patch` | PHP 官方 7.4 补丁原文 |
| `php-8.0.30-…-official-82f8f31b16.patch` | PHP 官方 8.0 补丁原文 |
| `php-8.1.34-…-official-1d7dec178a.patch` | PHP 官方 8.1 补丁原文 |
| `php-7.3.33-…patch` | 7.4 补丁移植到 7.3 |
| `php-7.2.34-…patch` | 7.4 补丁移植到 7.2 |
| `php-7.1.33-…patch` | 7.4 补丁移植到 7.1 |
| `php-7.0.33-…patch` | 7.4 补丁移植到 7.0 |

7.0 – 7.3 移植时，相对官方 7.4 补丁的主要调整：

- **7.3 – 7.0**：补上 7.4 才有的 `ZSTR_MAX_LEN` 定义。字符串拼接（`ZEND_CONCAT` / `ZEND_FAST_CONCAT`）的溢出检查按各版本的代码结构加上（7.0 用的是 `zend_string_realloc`）。`zend_vm_execute.h` 用对应年代的 PHP 重新生成，并验证过对原始源码重新生成的结果与官方源码包逐字一致
- **7.2 – 7.0**：数组结构和 7.3+ 不同。`array_init_singleton` 按旧的数组 API 实现；`HT_HASH_RESET` 本来就是 `memset` 实现，不需要改。补丁里的 `|| true` 改为 `|| 1`，因为这些版本没有定义 `true`
- **7.1 – 7.0**：没有 fast shutdown 这条代码路径，请求结束时清理残留状态（错误/异常处理器、对象存储、`EG(exception)` 等）的逻辑，按这两个版本 `shutdown_executor` 的结构重新放置
- **7.1 – 7.0**：顺带给 `zend_mm_alloc_huge` 补上了大小溢出检查

## 测试情况

每个版本都分别在 **Ubuntu 16.04** 和 **CentOS 7** 上，按宝塔的编译参数先装好未打补丁的版本，再用脚本完整走一遍升级流程。测试脚本在 `tests/` 目录。

**Ubuntu 16.04**（gcc 5.4，glibc 2.23，openssl 1.0.2g）：

| 版本 | 扩展保留 | FPM 行为 | 回滚 / 再升级 | 回归测试：多出的失败数 / 测试总数 |
|---|---|---|---|---|
| 7.0 | ✅ 46 / 46 | ✅ | ✅ | 9 / ~4700 |
| 7.1 | ✅ 46 / 46 | ✅ | ✅ | 9 / ~4950 |
| 7.2 | ✅ 46 / 46 | ✅ | ✅ | 9 / ~5000 |
| 7.3 | ✅ 47 / 47 | ✅ | ✅ | 0 / ~4400 |
| 7.4 | ✅ 46 / 46 | ✅ | ✅ | 未单独跑（官方补丁原件） |
| 8.0 | ✅ 45 / 45 | ✅ | ✅ | 9 / ~5500 |
| 8.1 | ✅ 45 / 45 | ✅ | ✅ | 11 / ~6000 |

**CentOS 7**（gcc 4.8.5，glibc 2.17，openssl 1.0.2k）：

| 版本 | 扩展保留 | FPM 行为 | 回滚 / 再升级 | 回归测试：多出的失败数 / 测试总数 |
|---|---|---|---|---|
| 7.0 | ✅ 46 / 46 | ✅ | ✅ | — |
| 7.1 | ✅ 46 / 46 | ✅ | ✅ | — |
| 7.2 | ✅ 46 / 46 | ✅ | ✅ | 9 / ~5060（与 Ubuntu 结果相同） |
| 7.3 | ✅ 46 / 46 | ✅ | ✅ | — |
| 7.4 | ✅ 46 / 46 | ✅ | ✅ | — |
| 8.0 | ✅ 45 / 45 | ✅ | ✅ | — |
| 8.1 | ✅ 45 / 45 | ✅ | ✅ | 11 / ~5980（与 Ubuntu 结果相同） |

- **回归测试**：在同一环境下，与未打补丁的同版本对比，测试范围是 Zend 引擎、语言、session、字符串、数组等测试集。多出的失败只有两类，都是补丁**有意改变**的行为，官方补丁同样如此：
  - session 上传进度相关的测试（功能被关闭）
  - 内存超限相关的测试（进程直接退出，不再执行后续回调）
- **FPM 行为**：
  - 内存超限后 worker 退出并自动拉起新进程，后续请求正常
  - 上一个请求设置的错误处理器不会残留到下一个请求
  - 嵌套数组参数（`a[]=`、`b[x][y][z]=`）解析正常
  - 升级过程中有 PHP CLI 进程在运行，不影响升级
- **7.0 – 7.2 的额外检查**：
  - 用大量嵌套、稀疏、混合键的请求参数做压力测试，打补丁前后结果逐字节一致
  - 用开启断言的调试版本跑 4300 – 4700 个测试，没有任何断言失败或崩溃

测试环境是 ARM64 架构的容器，编译器版本和编译流程与 x86_64 服务器相同，但不是在相同硬件上测试的。在 ARM64 的 CentOS 7 上，gcc 4.8.5 不支持 PHP 7.4+ 里一段 ARM 专用的内联汇编，**未打补丁的官方源码同样编译不过**；因此测试 7.4 / 8.0 / 8.1 时设置了 `ac_cv__asm_goto=no` 关闭这段汇编。x86_64 服务器不受影响，这个设置只用在测试环境，源码包和脚本都没有改动。宝塔的 swoole_loader 扩展无法在测试环境中模拟；如果升级后加载失败，脚本的扩展自检会自动回滚。

## 自行生成源码包

不想直接使用仓库里的源码包，可以用 `prepare_source.sh` 从 php.net 下载官方源码，校验 SHA256 后打上 `patches/` 里的补丁，重新生成：

```bash
bash prepare_source.sh 74      # 或 all
```

生成的包和仓库里的包源码内容一致。

## 仓库结构

```
├── bt_php_cve2026.sh            一键升级脚本
├── prepare_source.sh            从 php.net 官方源码 + 补丁重新生成源码包
├── php-<版本>-cve2026.tar.gz    打好补丁的源码包（7 个版本）
├── SHA256SUMS                   校验值
├── patches/                     补丁原文
└── tests/                       测试脚本（Ubuntu 16.04 / CentOS 7 宝塔模拟环境、压力测试、调试版本检查）
```

## 注意事项

- 升级后**不要**在宝塔面板里对该 PHP 版本点"更新"或"重装"，否则会被换回未打补丁的版本
- 7.0 – 8.1 都已停止维护，本仓库只是应急方案。**长期请迁移到 PHP 8.2 或更高版本**
- 使用前请先在测试环境验证你自己的业务。本仓库按"原样"提供，不对使用后果承担责任

## 许可

`patches/` 里的补丁和源码包里的 PHP 源码遵循 [PHP License v3.01](https://www.php.net/license/3_01.txt)。
