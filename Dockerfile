# syntax=docker/dockerfile:1
# Image de production de l'API : PHP-FPM + nginx dans un seul conteneur.
# Écoute sur $PORT (8080 par défaut) pour fonctionner aussi sur Railway / Render.
# Fichier autonome : la config PHP, nginx et le script de démarrage sont inclus ci-dessous.
#
# Lancer l'API      : docker run -p 8000:8080 --env-file .env <image>
# Lancer le worker  : docker run --env-file .env <image> php artisan queue:work
# Migrations auto   : ajouter RUN_MIGRATIONS=true

FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --ignore-platform-reqs

FROM php:8.3-fpm-alpine

RUN apk add --no-cache nginx bash icu-dev libpng-dev libzip-dev oniguruma-dev \
    && docker-php-ext-configure zip \
    && docker-php-ext-install pdo_mysql zip intl gd bcmath pcntl opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY <<'EOF' /usr/local/etc/php/conf.d/zz-app.ini
upload_max_filesize = 50M
post_max_size = 50M
memory_limit = 256M
expose_php = Off
opcache.enable = 1
opcache.validate_timestamps = 0
EOF

COPY <<'EOF' /etc/nginx/http.d/default.conf
server {
  listen __PORT__;
  client_max_body_size 50M;
  root /var/www/html/public;
  index index.php;

  location /storage/ {
    alias /var/www/html/storage/app/public/;
    try_files $uri =404;
    add_header Accept-Ranges bytes;
  }

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_pass 127.0.0.1:9000;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
  }
}
EOF

COPY --chmod=755 <<'EOF' /usr/local/bin/entrypoint
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
EOF

WORKDIR /var/www/html

COPY --from=vendor /app/vendor ./vendor
COPY . .

RUN composer dump-autoload --optimize --no-dev --no-scripts \
    && mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views \
       storage/logs storage/app/public bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["entrypoint"]
CMD ["serve"]
