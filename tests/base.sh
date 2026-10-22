set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential pkg-config autoconf libxml2-dev libssl-dev libcurl4-openssl-dev \
  libjpeg-dev libpng12-dev libwebp-dev libfreetype6-dev libicu-dev libsodium-dev gettext libxslt1-dev \
  libsqlite3-dev libonig-dev libmcrypt-dev xz-utils curl libfcgi0ldbl >/dev/null
ML=$(gcc -print-multiarch)
mkdir -p /usr/local/openssl/include /usr/local/openssl/lib /usr/local/curl/include /usr/local/curl/lib /usr/local/curl/bin /usr/local/freetype/include /usr/local/freetype/lib /usr/local/libsodium/include /usr/local/libsodium/lib
ln -sfn /usr/include/openssl /usr/local/openssl/include/openssl
for l in /usr/lib/$ML/libssl* /usr/lib/$ML/libcrypto*; do ln -sf $l /usr/local/openssl/lib/; done
ln -sfn /usr/include/$ML/curl /usr/local/curl/include/curl
for l in /usr/lib/$ML/libcurl*; do ln -sf $l /usr/local/curl/lib/; done; ln -sf /usr/bin/curl-config /usr/local/curl/bin/curl-config
ln -sfn /usr/include/freetype2 /usr/local/freetype/include/freetype2
for l in /usr/lib/$ML/libfreetype*; do ln -sf $l /usr/local/freetype/lib/; done
ln -sf /usr/include/sodium.h /usr/local/libsodium/include/; ln -sfn /usr/include/sodium /usr/local/libsodium/include/sodium
for l in /usr/lib/$ML/libsodium*; do ln -sf $l /usr/local/libsodium/lib/; done
groupadd www; useradd -g www -s /sbin/nologin www
echo base-ok
