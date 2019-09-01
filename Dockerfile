FROM ubuntu:18.04

# RUN echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale
# RUN locale-gen en_US.UTF-8

# Install Some PPAs
RUN apt-get update \
    && apt-get upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        software-properties-common curl wget

RUN apt-add-repository ppa:nginx/development -y
RUN apt-add-repository ppa:ondrej/php -y

# Install Some Basic Packages
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential dos2unix gcc git libmcrypt4 libpcre3-dev \
        libpng-dev ntp unzip make python2.7-dev \
        python-pip re2c supervisor unattended-upgrades whois vim \
        libnotify-bin pv cifs-utils mcrypt bash-completion zsh \
        graphviz avahi-daemon tshark imagemagick

# Install PHP Stuffs
# PHP 7.2
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --allow-change-held-packages \
            php7.2-cli php7.2-bcmath php7.2-curl php7.2-dev php7.2-gd \
            php7.2-imap php7.2-intl  php7.2-json  php7.2-ldap \
            php7.2-mbstring php7.2-mysql php7.2-odbc php7.2-pgsql \
            php7.2-phpdbg php7.2-pspell php7.2-soap php7.2-sqlite3 \
            php7.2-xml php7.2-zip php7.2-readline

# Install Composer
RUN wget https://raw.githubusercontent.com/composer/getcomposer.org/master/web/installer -O - -q | php -- --quiet
RUN chmod +x composer.phar
RUN mv composer.phar /usr/local/bin/composer

RUN set -e \
    && composer global require hirak/prestissimo \
    && composer clear-cache

# Set Some PHP CLI Settings
RUN sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.2/cli/php.ini \
    && sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.2/cli/php.ini \
    && sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.2/cli/php.ini \
    && sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.2/cli/php.ini

# Install Nginx & PHP-FPM
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
      --allow-downgrades --allow-remove-essential --allow-change-held-packages \
        nginx php7.2-fpm systemd

# Adjust default nginx port & disable default background services
RUN sed -i "s/80 default_server/8080 default_server/" /etc/nginx/sites-available/default
RUN systemctl disable nginx
RUN systemctl disable php7.2-fpm

# Setup Some PHP-FPM Options
RUN echo "xdebug.remote_enable = 1" >> /etc/php/7.2/mods-available/xdebug.ini \
    && echo "xdebug.remote_connect_back = 1" >> /etc/php/7.2/mods-available/xdebug.ini \
    && echo "xdebug.remote_port = 9000" >> /etc/php/7.2/mods-available/xdebug.ini \
    && echo "xdebug.max_nesting_level = 512" >> /etc/php/7.2/mods-available/xdebug.ini \
    && echo "opcache.revalidate_freq = 0" >> /etc/php/7.2/mods-available/opcache.ini

RUN sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.2/fpm/php.ini \
    && sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.2/fpm/php.ini \
    && sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.2/fpm/php.ini \
    && sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.2/fpm/php.ini \ 
    && sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" /etc/php/7.2/fpm/php.ini \
    && sed -i "s/post_max_size = .*/post_max_size = 100M/" /etc/php/7.2/fpm/php.ini \
    && sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.2/fpm/php.ini

RUN printf "[openssl]\n" | tee -a /etc/php/7.2/fpm/php.ini \
    && printf "openssl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | tee -a /etc/php/7.2/fpm/php.ini \
    && printf "[curl]\n" | tee -a /etc/php/7.2/fpm/php.ini \
    && printf "curl.cainfo = /etc/ssl/certs/ca-certificates.crt\n" | tee -a /etc/php/7.2/fpm/php.ini

# Disable XDebug On The CLI
RUN phpdismod -s cli xdebug

# Copy fastcgi_params to Nginx because they broke it on the PPA
RUN echo 'fastcgi_param	QUERY_STRING		$query_string;\n\
fastcgi_param	REQUEST_METHOD		$request_method;\n\
fastcgi_param	CONTENT_TYPE		$content_type;\n\
fastcgi_param	CONTENT_LENGTH		$content_length;\n\
fastcgi_param	SCRIPT_FILENAME		$request_filename;\n\
fastcgi_param	SCRIPT_NAME		$fastcgi_script_name;\n\
fastcgi_param	REQUEST_URI		$request_uri;\n\
fastcgi_param	DOCUMENT_URI		$document_uri;\n\
fastcgi_param	DOCUMENT_ROOT		$document_root;\n\
fastcgi_param	SERVER_PROTOCOL		$server_protocol;\n\
fastcgi_param	GATEWAY_INTERFACE	CGI/1.1;\n\
fastcgi_param	SERVER_SOFTWARE		nginx/$nginx_version;\n\
fastcgi_param	REMOTE_ADDR		$remote_addr;\n\
fastcgi_param	REMOTE_PORT		$remote_port;\n\
fastcgi_param	SERVER_ADDR		$server_addr;\n\
fastcgi_param	SERVER_PORT		$server_port;\n\
fastcgi_param	SERVER_NAME		$server_name;\n\
fastcgi_param	HTTPS			$https if_not_empty;\n\
fastcgi_param	REDIRECT_STATUS		200;\n' \
>> /etc/nginx/fastcgi_params

# Set The Nginx & PHP-FPM User
RUN sed -i "s/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/" /etc/nginx/nginx.conf

# Install SQLite
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        sqlite3 libsqlite3-dev

# Set workspace & extended INI for flexible config (eg. file upload limit)
COPY . /var/www/html
WORKDIR /var/www/html

RUN mkdir -p /run/php

# COPY .docker/extended.php.ini /usr/local/etc/php/conf.d/extended.php.ini
EXPOSE 8080

# RUN composer install
# RUN chmod -R 777 ./storage

# Supervisor config
ADD ./supervisord.conf /etc/supervisord.conf
EXPOSE 80
CMD ["/usr/bin/supervisord"]
