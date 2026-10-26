#!/bin/sh
set -e

cd /var/www/html

# Les volumes montés arrivent vides : on recrée l'arborescence de storage.
mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views \
  storage/logs storage/app/public
chown -R www-data:www-data storage bootstrap/cache

php artisan storage:link --force >/dev/null 2>&1 || true
php artisan config:cache
php artisan view:cache

if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  php artisan migrate --force
fi

# Signal utilisé par le healthcheck (le worker attend que l'API soit prête).
touch /tmp/ready

if [ "$1" = "serve" ]; then
  sed "s/__PORT__/${PORT:-8080}/" /etc/nginx/http.d/default.conf > /tmp/default.conf
  mv /tmp/default.conf /etc/nginx/http.d/default.conf
  php-fpm -D
  exec nginx -g 'daemon off;'
fi

# Autre commande (ex. worker) : php artisan queue:work ...
exec "$@"
