FROM php:5.6-apache

# install the PHP extensions we need
RUN apt-get update && apt-get install -y bzr libpng12-dev libjpeg-dev mysql-client ghostscript libphp-adodb tesseract-ocr apache2-utils && rm -rf /var/lib/apt/lists/* \
	&& docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
	&& docker-php-ext-install gd mysqli mysql opcache

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN a2enmod rewrite expires authz_groupfile

#Add directories for images and config and forms
RUN mkdir /images && chown www-data:www-data /images
RUN mkdir /opt/quexf && chown www-data:www-data /opt/quexf
RUN mkdir /forms && chown www-data:www-data /forms

VOLUME ["/var/www/html", "/images", "/opt/quexf"]

RUN set -x \
	&& bzr branch lp:quexf /usr/src/quexf \
	&& chown -R www-data:www-data /usr/src/quexf

#Set PHP defaults for queXS (allow bigger uploads for sample files)
RUN { \
		echo 'memory_limit=256M'; \
		echo 'upload_max_filesize=128M'; \
		echo 'post_max_size=128M'; \
		echo 'max_execution_time=120'; \
        echo 'date.timezone=UTC'; \
	} > /usr/local/etc/php/conf.d/uploads.ini

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat

# ENTRYPOINT resets CMD
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
