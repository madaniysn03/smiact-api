# Image de production de l'API : PHP-FPM + nginx dans un seul conteneur.
# Écoute sur $PORT (8080 par défaut) pour fonctionner aussi sur Railway / Render.

FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --ignore-platform-reqs

FROM php:8.3-fpm-alpine

RUN apk add --no-cache nginx bash icu-dev libpng-dev libzip-dev oniguruma-dev \
    && docker-php-ext-configure zip \
    && docker-php-ext-install pdo_mysql zip intl gd bcmath pcntl opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY docker/php/php.ini /usr/local/etc/php/conf.d/zz-app.ini
COPY docker/nginx/prod.conf /etc/nginx/http.d/default.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint

WORKDIR /var/www/html

COPY --from=vendor /app/vendor ./vendor
COPY . .

RUN composer dump-autoload --optimize --no-dev --no-scripts \
    && mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views \
       storage/logs storage/app/public bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod +x /usr/local/bin/entrypoint

ENV PORT=8080
EXPOSE 8080

ENTRYPOINT ["entrypoint"]
CMD ["serve"]
