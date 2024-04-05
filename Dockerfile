#FROM alpine:latest
FROM tomcat:jdk15-openjdk-slim-buster

ARG APPLICATION="guacamole"
ARG BUILD_RFC3339="2024-04-05T10:33:00Z"
ARG REVISION="local"
ARG DESCRIPTION="Guacamole 1.5.4 on amd64"
ARG PACKAGE="ghcr.io/ptr33/guacamole"
ARG VERSION="1.5.4"

STOPSIGNAL SIGKILL

LABEL org.opencontainers.image.ref.name="${PACKAGE}" \
      org.opencontainers.image.created=$BUILD_RFC3339 \
      org.opencontainers.image.authors="MaxWaldorf,OZNU,ptr33" \
      org.opencontainers.image.documentation="https://github.com/${PACKAGE}/README.md" \
      org.opencontainers.image.description="${DESCRIPTION}" \
      org.opencontainers.image.licenses="GPLv3" \
      org.opencontainers.image.source="https://github.com/${PACKAGE}" \
      org.opencontainers.image.revision=$REVISION \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.url="https://hub.docker.com/r/${PACKAGE}/"

ENV \
      APPLICATION="${APPLICATION}" \
      BUILD_RFC3339="${BUILD_RFC3339}" \
      REVISION="${REVISION}" \
      DESCRIPTION="${DESCRIPTION}" \
      PACKAGE="${PACKAGE}" \
      VERSION="${VERSION}"


ENV ARCH=amd64 \
GUAC_VER=1.5.4 \
GUACAMOLE_HOME=/app/guacamole \
PG_MAJOR=11 \
PGDATA=/config/postgres \
POSTGRES_USER=guacamole \
POSTGRES_DB=guacamole_db

#Add essential packages
RUN apt-get update && apt-get install -y curl apt-utils cifs-utils postgresql ghostscript

# Apply the s6-overlay

RUN curl -SLO "https://github.com/just-containers/s6-overlay/releases/download/v2.1.0.2/s6-overlay-${ARCH}.tar.gz" \
  && tar -xzf s6-overlay-${ARCH}.tar.gz -C / \
  && tar -xzf s6-overlay-${ARCH}.tar.gz -C /usr ./bin \
  && rm -rf s6-overlay-${ARCH}.tar.gz \
  && mkdir -p ${GUACAMOLE_HOME} \
    ${GUACAMOLE_HOME}/lib \
    ${GUACAMOLE_HOME}/extensions

WORKDIR ${GUACAMOLE_HOME}

# Look for debian testing packets
RUN echo "deb http://deb.debian.org/debian buster-backports main contrib non-free" >> /etc/apt/sources.list

# Install dependencies
RUN apt-get update && apt-get -t buster-backports install -y \
    build-essential \
    libcairo2-dev libjpeg62-turbo-dev libpng-dev libtool-bin libossp-uuid-dev \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libpango1.0-dev freerdp2-dev libfreerdp-client2-2 \
    libssh2-1-dev libtelnet-dev libvncserver-dev libwebsockets-dev \
    libpulse-dev libssl-dev libvorbis-dev libwebp-dev \
  && apt-get autoremove && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/*

# Link FreeRDP to where guac expects it to be
RUN ln -s /usr/local/lib/freerdp /usr/lib/x86_64-linux-gnu/freerdp || exit 0

# Install guacamole-server
RUN curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/source/guacamole-server-${GUAC_VER}.tar.gz" \
  && tar -xzf guacamole-server-${GUAC_VER}.tar.gz \
  && cd guacamole-server-${GUAC_VER} \
  && ./configure \
  && make -j$(getconf _NPROCESSORS_ONLN) \
  && make install \
  && cd .. \
  && rm -rf guacamole-server-${GUAC_VER}.tar.gz guacamole-server-${GUAC_VER} \
  && ldconfig

# Install guacamole-client and postgres auth adapter
RUN set -x \
  && rm -rf ${CATALINA_HOME}/webapps/guacamole \
  && curl -SLo ${CATALINA_HOME}/webapps/guacamole.war "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-${GUAC_VER}.war" \
  && curl -SLo ${GUACAMOLE_HOME}/lib/postgresql-42.1.4.jar "https://jdbc.postgresql.org/download/postgresql-42.1.4.jar" \
  && curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-auth-jdbc-${GUAC_VER}.tar.gz" \
  && tar -xzf guacamole-auth-jdbc-${GUAC_VER}.tar.gz \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/guacamole-auth-jdbc-postgresql-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions/ \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/schema ${GUACAMOLE_HOME}/ \
  && rm -rf guacamole-auth-jdbc-${GUAC_VER} guacamole-auth-jdbc-${GUAC_VER}.tar.gz

# Add optional extensions
RUN set -xe \
  && mkdir ${GUACAMOLE_HOME}/extensions-available \
  && for i in auth-ldap auth-duo auth-header auth-cas auth-openid auth-quickconnect auth-totp; do \
    echo "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz" \
    && curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz" \
    && tar -xzf guacamole-${i}-${GUAC_VER}.tar.gz \
    && cp guacamole-${i}-${GUAC_VER}/guacamole-${i}-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions-available/ \
    && rm -rf guacamole-${i}-${GUAC_VER} guacamole-${i}-${GUAC_VER}.tar.gz \
  ;done

ENV PATH=/usr/lib/postgresql/${PG_MAJOR}/bin:$PATH
ENV GUACAMOLE_HOME=/config/guacamole

WORKDIR /config

COPY root /

ENTRYPOINT [ "/init" ]

