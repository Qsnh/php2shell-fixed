set -e
ARCH=$(uname -m)
# CentOS 7 is EOL: point yum at vault / EPEL archive
if [ "$ARCH" = x86_64 ]; then BASE=http://vault.centos.org/7.9.2009; else BASE=http://vault.centos.org/altarch/7.9.2009; fi
rm -f /etc/yum.repos.d/*.repo
cat > /etc/yum.repos.d/vault.repo <<R
[base]
name=base
baseurl=$BASE/os/$ARCH/
gpgcheck=0
[updates]
name=updates
baseurl=$BASE/updates/$ARCH/
gpgcheck=0
[extras]
name=extras
baseurl=$BASE/extras/$ARCH/
gpgcheck=0
[epel]
name=epel
baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$ARCH/
gpgcheck=0
R
yum -q -y install gcc gcc-c++ make autoconf patch which file libxml2-devel openssl-devel libcurl-devel libjpeg-turbo-devel \
  libpng-devel libwebp-devel freetype-devel libicu-devel gettext-devel sqlite-devel libxslt-devel xz bzip2 curl \
  libmcrypt-devel oniguruma-devel libsodium-devel fcgi >/dev/null
gcc --version | head -1
L=/usr/lib64
mkdir -p /usr/local/openssl/include /usr/local/openssl/lib /usr/local/curl/include /usr/local/curl/lib /usr/local/curl/bin /usr/local/freetype/include /usr/local/freetype/lib /usr/local/libsodium/include /usr/local/libsodium/lib
ln -sfn /usr/include/openssl /usr/local/openssl/include/openssl
for l in $L/libssl* $L/libcrypto*; do ln -sf $l /usr/local/openssl/lib/; done
ln -sfn /usr/include/curl /usr/local/curl/include/curl
for l in $L/libcurl*; do ln -sf $l /usr/local/curl/lib/; done; ln -sf /usr/bin/curl-config /usr/local/curl/bin/curl-config
ln -sfn /usr/include/freetype2 /usr/local/freetype/include/freetype2
for l in $L/libfreetype*; do ln -sf $l /usr/local/freetype/lib/; done
ln -sf /usr/include/sodium.h /usr/local/libsodium/include/; ln -sfn /usr/include/sodium /usr/local/libsodium/include/sodium
for l in $L/libsodium*; do ln -sf $l /usr/local/libsodium/lib/; done
groupadd www; useradd -g www -s /sbin/nologin www
rpm -q diffutils || echo "NOTE: diffutils not installed"
echo base-ok
