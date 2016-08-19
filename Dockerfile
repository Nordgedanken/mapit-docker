FROM debian:jessie
MAINTAINER Matthew Landauer <matthew@oaf.org.au>

RUN echo \
   'deb ftp://ftp.us.debian.org/debian/ jessie main\n \
    deb ftp://ftp.us.debian.org/debian/ jessie-updates main\n \
    deb http://security.debian.org jessie/updates main\n' \
    > /etc/apt/sources.list


RUN apt-get update
RUN apt-get upgrade -y

# Set the locale so that postgres is setup with the correct locale
#RUN apt-get install -y language-pack-en
RUN apt-get update -qq && apt-get install -y locales -qq && locale-gen en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Here we're installing things that are actually installed by the install script
# but we're installing them first here so that we can take advantage of docker
# caching while debugging this Dockerfile. So, it should be able to comment
# out this section when everything is working
#RUN apt-get install -y git-core lockfile-progs ruby curl dnsutils lsb-release
# We install postgres now so that it can be running when the install script is used
RUN apt-get install -y postgresql-9.4  postgresql-9.4-postgis-2.1 postgresql-server-dev-9.4 python-psycopg2 python-pip
#RUN pip install django-mapit
#RUN apt-get install -y memcached python-virtualenv python-django python-django-south python-psycopg2 python-yaml python-memcache python-gdal python-beautifulsoup ruby-sass



ADD https://github.com/mysociety/commonlib/raw/master/bin/install-site.sh /install-site.sh
COPY ./create_template_postgis-debian.sh /create_template_postgis-debian.sh
RUN chmod +x /create_template_postgis-debian.sh && service postgresql start; su -l -c "bash /create_template_postgis-debian.sh" postgres
RUN service postgresql restart; /bin/bash /install-site.sh --default mapit mapit localhost
#RUN /bin/bash /install-site.sh --default mapit mapit localhost
RUN rm /install-site.sh

# Install Supervisor to manage multiple processes running in the docker container
RUN apt-get install -y supervisor
RUN mkdir -p /var/run/postgresql /var/run/nginx /var/run/mapit /var/log/supervisor
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN echo "daemon off;" >> /etc/nginx/nginx.conf
# Permissions seem to be wrong on postgres server.key after building on docker hub
# This is also possibly related to https://github.com/dotcloud/docker/issues/783
# TODO Investigate this further rather than working around
RUN rm /var/lib/postgresql/9.1/main/server.key
RUN cp /etc/ssl/private/ssl-cert-snakeoil.key /var/lib/postgresql/9.1/main/server.key
RUN chown postgres:postgres /var/lib/postgresql/9.1/main/server.key

# See this: https://code.djangoproject.com/ticket/16778
RUN echo "standard_conforming_strings = off" >> /etc/postgresql/9.1/main/postgresql.conf
# Curious. Expected Shapely to be installed earlier
RUN pip install Shapely
# Turn debug off so we don't run out of memory during imports
RUN sed 's/DEBUG: True/DEBUG: False/' /var/www/mapit/mapit/conf/general.yml > /var/www/mapit/mapit/conf/general2.yml; mv /var/www/mapit/mapit/conf/general2.yml /var/www/mapit/mapit/conf/general.yml

# unzip and ogr2ogr are handy for dealing with boundary data. So, installing now.
RUN apt-get install -y unzip gdal-bin

# Cleanup. This is only really truly going to be useful if we flatten this image so that we
# remove intermediate images
RUN apt-get clean
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 80
CMD ["/usr/bin/supervisord"]
