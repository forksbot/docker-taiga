FROM python:3.6-slim
MAINTAINER Benjamin Hutchins <ben@hutchins.co>
MAINTAINER Riotkit <riotkit_org@riseup.net>

# build-time arguments, use them in docker build with --build-arg switch to build different version
ARG TAIGA_BACK_VERSION=4.2.7
ARG TAIGA_FRONT_VERSION=4.2.7-stable
ARG TAIGA_UID=1000
ARG TAIGA_GID=1000

# runtime arguments
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=c \
    LC_TYPE=en_US.UTF-8 \
    TAIGA_ENABLE_EMAIL=False \
    TAIGA_EMAIL_USE_TLS=true\
    TAIGA_EMAIL_HOST=smtp \
    TAIGA_EMAIL_PORT=25 \
    TAIGA_EMAIL_USER=taiga@riotkit.org \
    TAIGA_EMAIL_PASS=some-password \
    TAIGA_EMAIL_FROM=taiga@localhost \
    TAIGA_BROKER_URL=amqp://guest:guest@rabbit:5672 \
    TAIGA_REDIS_URL="redis://redis:6379/0" \
    TAIGA_DEFAULT_LOCALE=en \
    TAIGA_SECRET_KEY=REPLACE-ME-j1598u1J^U*(y251u98u51u5981urf98u2o5uvoiiuzhlit3) \
    TAIGA_DB_NAME=taiga \
    TAIGA_DB_HOST=postgres \
    TAIGA_DB_USER=taiga \
    TAIGA_DB_PASSWORD= \
    TAIGA_SCHEME=http \
    TAIGA_ENABLE_EVENTS=false \
    TAIGA_EVENTS_HOST=events \
    TAIGA_REDIRECT_TO_SSL=false \
    TAIGA_HOSTNAME=localhost \
    TAIGA_ENABLE_SSL=false \
    # Set to `true` to enable the LDAP authentication.
    TAIGA_LDAP=false \
    # The LDAP server URL.
    LDAP_SERVER="" \
    # The port to connect to the LDAP server on.
    LDAP_PORT=0 \
    # Set to `true` to enable StartTLS when connecting to the server.
    LDAP_START_TLS="false" \
    # The DN to bind to the LDAP server with. If left blank the client will attempt to bind anonymously.
    LDAP_BIND_DN="" \
    # The password for the bind DN.
    LDAP_BIND_PASSWORD="" \
    # The root of the LDAP structure in which to search for user accounts.
    LDAP_SEARCH_BASE="" \
    # Additional filter added to the user account query.
    LDAP_SEARCH_FILTER_ADDITIONAL="" \
    # The LDAP attribute that will be used for the account's Taiga username.
    LDAP_USERNAME_ATTRIBUTE="uid" \
    # The LDAP attribute that will be used for the account's Email address.
    LDAP_EMAIL_ATTRIBUTE="mail" \
    # The LDAP attribute that will be used for the account's full name.
    LDAP_FULL_NAME_ATTRIBUTE="cn" \
    # The fallback authentication method to use if LDAP fails. This will allows users to login with either an LDAP account or a local account. Set to a blank string to prevent logging in with anything other than LDAP.
    LDAP_FALLBACK="normal" \
    #  Whether or not to save the LDAP password in the local database. If `LDAP_FALLBACK` is set to `normal` this will allow users that have logged in with LDAP before to login even if the LDAP server is unavailable.
    LDAP_SAVE_LOGIN_PASSWORD="true" \
    DEBUG=false

# install dependencies
# download and unpack applications in selected versions
# set a locale
# clean up
RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends locales gettext ca-certificates nginx libcap2-bin supervisor wget curl \
    && apt-get clean \
    \
    && addgroup --gid $TAIGA_GID taiga \
    && adduser taiga --uid $TAIGA_UID --home /usr/src --disabled-password --shell /bin/bash --gid $TAIGA_GID \
    && setcap cap_net_bind_service=ep /usr/sbin/nginx \
    \
    && wget https://github.com/taigaio/taiga-back/archive/$TAIGA_BACK_VERSION.tar.gz -O /usr/src/taiga-back.tar.gz \
    && wget https://github.com/taigaio/taiga-front-dist/archive/$TAIGA_FRONT_VERSION.tar.gz -O /usr/src/taiga-front-dist.tar.gz \
    && cd /usr/src/ \
    && tar -xvf taiga-back.tar.gz \
    && mkdir -p /usr/src/taiga-back \
    && mv taiga-back-*/* taiga-back/ \
    \
    && tar -xvf taiga-front-dist.tar.gz \
    && mkdir -p /usr/src/taiga-front-dist \
    && mv taiga-front-*/* taiga-front-dist/ \
    \
    && rm /usr/src/*.tar.gz \
    \
    && mkdir -p /taiga /usr/src/taiga-front-dist/dist/js/ \
    && pip install --no-cache-dir -r /usr/src/taiga-back/requirements.txt \
    && pip install --no-cache-dir j2cli \
    && pip install --no-cache-dir taiga-contrib-ldap-auth-ext \
    && echo "LANG=en_US.UTF-8" > /etc/default/locale \
    && echo "LC_TYPE=en_US.UTF-8" > /etc/default/locale \
    && echo "LC_MESSAGES=POSIX" >> /etc/default/locale \
    && echo "LANGUAGE=en" >> /etc/default/locale \
    && locale-gen en_US.UTF-8 && dpkg-reconfigure locales \
    && locale -a

# Configure SSL ( Required for the LDAP plugin )
RUN echo "CipherString=DEFAULT@SECLEVEL=1" >> /etc/ssl/openssl.cnf

# copy configs and scripts
COPY conf /opt/taiga-conf
COPY checkdb.py /checkdb.py
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY supervisor.conf /etc/supervisord.conf

# configure
RUN cp /opt/taiga-conf/taiga/local.py /usr/src/taiga-back/settings/local.py \
    && cp /opt/taiga-conf/taiga/docker-settings.py /usr/src/taiga-back/settings/docker.py \
    && j2 /opt/taiga-conf/locale.gen.j2 > /etc/locale.gen \
    \
    && cd /usr/src/taiga-back/ && python manage.py collectstatic --noinput \
    && mkdir -p /var/log/nginx /var/lib/nginx \
    && touch /var/run/nginx.pid \
    && chown taiga:taiga /usr/src /var/log/nginx/ /var/run/nginx.pid /var/lib/nginx -R

EXPOSE 80 443
VOLUME /usr/src/taiga-back/media
WORKDIR /usr/src/taiga-back

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]

HEALTHCHECK --interval=1m --timeout=5s \
  CMD curl -s -f http://localhost/ || exit 1
