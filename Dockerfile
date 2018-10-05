FROM ubuntu:16.04
MAINTAINER masbenx <me@masbenx.net>

ENV REFRESHED_AT 2017-05-20
ENV HTTPD_PREFIX /etc/apache2

# Suppress warnings from apt about lack of Dialog
ENV DEBIAN_FRONTEND noninteractive

LABEL maintainer="masbenx <me@masbenx.net>" \
      org.label-schema.docker.dockerfile="/Dockerfile" \
      org.label-schema.name="Ubuntu 18.04 with Apache2.4 and PHP 7.2, optimised using PHP-FPM" \
      org.label-schema.url="https://masbenx.net" \
      org.label-schema.vcs-url="https://github.com/masbenx/apache-php72fpm"

# Initial apt update
RUN apt-get update && apt-get install -y apt-utils

# Install common / shared packages
RUN apt-get install -y \
    curl \
    git \
    zip \
    unzip \
    vim \
    locales \
    software-properties-common

# Set up locales
RUN locale-gen en_US.UTF-8
ENV LANG C.UTF-8
ENV LANGUAGE C.UTF-8
ENV LC_ALL C.UTF-8
RUN /usr/sbin/update-locale

# Add repository for latest built PHP packages, e.g. 7.2 which isn't otherwise available in Xenial repositories
RUN add-apt-repository ppa:ondrej/php
RUN apt-get update

# Install PHP 7.2 with FPM and other various commonly used modules, including MySQL client
RUN apt-get install -y \
		php7.2 \
                php7.2-bcmath php7.2-bz2 php7.2-cli php7.2-common php7.2-curl \
                php7.2-dev php7.2-fpm php7.2-gd php7.2-gmp php7.2-imap php7.2-intl \
                php7.2-json php7.2-ldap php7.2-mbstring php7.2-mcrypt php7.2-mysql \
                php7.2-odbc php7.2-opcache php7.2-pgsql php7.2-phpdbg php7.2-pspell \
                php7.2-readline php7.2-recode php7.2-soap php7.2-sqlite3 \
                php7.2-tidy php7.2-xml php7.2-xmlrpc php7.2-xsl php7.2-zip

# Install Apache2 with FastCGI module and MySQL client for convenience
RUN apt-get install -y --allow-downgrades --allow-remove-essential --allow-change-held-packages \
                apache2 libapache2-mod-fastcgi apache2-utils \
                libmysqlclient-dev mariadb-client

# Modify PHP-FPM configuration files to set common properties and listen on socket
RUN sed -i "s/;date.timezone =.*/date.timezone = UTC/" /etc/php/7.2/cli/php.ini
RUN sed -i "s/;date.timezone =.*/date.timezone = UTC/" /etc/php/7.2/fpm/php.ini
RUN sed -i "s/display_errors = Off/display_errors = On/" /etc/php/7.2/fpm/php.ini
RUN sed -i "s/upload_max_filesize = .*/upload_max_filesize = 10M/" /etc/php/7.2/fpm/php.ini
RUN sed -i "s/post_max_size = .*/post_max_size = 12M/" /etc/php/7.2/fpm/php.ini
RUN sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.2/fpm/php.ini

RUN sed -i -e "s/pid =.*/pid = \/var\/run\/php7.2-fpm.pid/" /etc/php/7.2/fpm/php-fpm.conf
RUN sed -i -e "s/error_log =.*/error_log = \/proc\/self\/fd\/2/" /etc/php/7.2/fpm/php-fpm.conf
# RUN sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php/7.2/fpm/php-fpm.conf
RUN sed -i "s/listen = .*/listen = \/var\/run\/php\/php7.2-fpm.sock/" /etc/php/7.2/fpm/pool.d/www.conf
RUN sed -i "s/;catch_workers_output = .*/catch_workers_output = yes/" /etc/php/7.2/fpm/pool.d/www.conf

# Install Composer globally
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer \
    && chmod a+x /usr/local/bin/composer

# Remove default Apache VirtualHost, configs, and mods not needed
WORKDIR $HTTPD_PREFIX
RUN rm -f \
    	sites-enabled/000-default.conf \
    	conf-enabled/serve-cgi-bin.conf \
    	mods-enabled/autoindex.conf \
    	mods-enabled/autoindex.load

# Enable additional configs and mods
RUN ln -s $HTTPD_PREFIX/mods-available/expires.load $HTTPD_PREFIX/mods-enabled/expires.load \
    && ln -s $HTTPD_PREFIX/mods-available/headers.load $HTTPD_PREFIX/mods-enabled/headers.load \
	&& ln -s $HTTPD_PREFIX/mods-available/rewrite.load $HTTPD_PREFIX/mods-enabled/rewrite.load

# Configure Apache to use our PHP-FPM socket for all PHP files
COPY php7.2-fpm.conf /etc/apache2/conf-available/php7.2-fpm.conf
RUN a2enconf php7.2-fpm

# Enable Apache modules and configuration
RUN a2dismod mpm_event
RUN a2enmod alias actions fastcgi proxy_fcgi setenvif mpm_worker

# Clean up apt cache and temp files to save disk space
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Symlink apache access and error logs to stdout/stderr so Docker logs shows them
RUN ln -sf /dev/stdout /var/log/apache2/access.log
RUN ln -sf /dev/stdout /var/log/apache2/other_vhosts_access.log
RUN ln -sf /dev/stderr /var/log/apache2/error.log

EXPOSE 80

# Start PHP-FPM worker service and run Apache in foreground so any error output is sent to stdout for Docker logs
CMD service php7.2-fpm start && /usr/sbin/apache2ctl -D FOREGROUND

