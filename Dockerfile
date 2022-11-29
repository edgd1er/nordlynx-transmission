# syntax=docker/dockerfile:1.3
FROM alpine:3.15 AS TransmissionUIs

#hadolint ignore=DL3018,DL3008,DL4006
RUN apk --no-cache add curl jq && mkdir -p /opt/transmission-ui \
    && echo "Install Shift" \
    && wget --no-cache -qO- https://github.com/killemov/Shift/archive/master.tar.gz | tar xz -C /opt/transmission-ui \
    && mv /opt/transmission-ui/Shift-master /opt/transmission-ui/shift \
    && echo "Install Flood for Transmission" \
    && wget --no-cache -qO- https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.tar.gz | tar xz -C /opt/transmission-ui \
    && echo "Install Combustion" \
    && wget --no-cache -qO- https://github.com/Secretmapper/combustion/archive/release.tar.gz | tar xz -C /opt/transmission-ui \
    && echo "Install kettu" \
    && wget --no-cache -qO- https://github.com/endor/kettu/archive/master.tar.gz | tar xz -C /opt/transmission-ui \
    && mv /opt/transmission-ui/kettu-master /opt/transmission-ui/kettu \
    && echo "Install Transmission-Web-Control" \
    && mkdir /opt/transmission-ui/transmission-web-control \
    && wget --no-cache -qO- "$(wget --no-cache -qO- https://api.github.com/repos/ronggang/transmission-web-control/releases/latest | jq --raw-output '.tarball_url')" | tar -C /opt/transmission-ui/transmission-web-control/ --strip-components=2 -xz

FROM debian:bullseye-slim AS debian-base

ARG aptcacher=''
ARG VERSION=3.15.1
ARG TZ=America/Chicago
ARG NORDVPNCLIENT_INSTALLED=1

LABEL maintainer="edgd1er <edgd1er@htomail.com>" \
      org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="nordlynx-transmission" \
      org.label-schema.description="Provides VPN through NordVpn application or plain wireguard." \
      org.label-schema.url="https://hub.docker.com/r/edgd1er/nordlynx-transmission" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/edgd1er/nordlynx-transmission" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

ENV TZ=${TZ}
ENV NORDVPNCLIENT_INSTALLED=${NORDVPNCLIENT_INSTALLED}
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#add apt-cacher setting if present:
WORKDIR /app
#hadolint ignore=DL3018,DL3008
RUN if [[ -n ${aptcacher} ]]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy; \
    echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy ; fi; \
    echo "alias checkip='curl -sm 10 \"https://zx2c4.com/ip\"'" | tee -a ~/.bashrc \
    && echo "alias checkhttp='curl -sm 10 -x http://\${HOSTNAME}:\${WEBPROXY_PORT:-8888} \"https://ifconfig.me/ip\"'" | tee -a ~/.bashrc \
    && echo "alias checksocks='curl -sm10 -x socks5://\${HOSTNAME}:1080 \"https://ifconfig.me/ip\"'" | tee -a ~/.bashrc \
    && echo "alias checkvpn='curl -sm 10 \"https://api.nordvpn.com/vpn/check/full\" | jq -r .status'" | tee -a ~/.bashrc \
    && echo "alias getcheck='curl -sm 10 \"https://api.nordvpn.com/vpn/check/full\" | jq . '" | tee -a ~/.bashrc \
    && echo "alias gettiny='grep -vP \"(^$|^#)\" /etc/tinyproxy/tinyproxy.conf'" | tee -a ~/.bashrc \
    && echo "alias getdante='grep -vP \"(^$|^#)\" /etc/dante.conf'" | tee -a ~/.bashrc \
    # allow to install resolvconf
    && echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections \
    && apt-get update && export DEBIAN_FRONTEND=non-interactive \
    && apt-get -o Dpkg::Options::="--force-confold" install --no-install-recommends -qqy supervisor wget curl jq \
    ca-certificates tzdata dante-server net-tools unzip unrar-free bc tar \
    transmission transmission-common transmission-daemon transmission-cli tinyproxy ufw iputils-ping vim \
    # wireguard \
    wireguard-tools \
    #ui start \
    && if [[ ${NORDVPNCLIENT_INSTALLED} -eq 1 ]]; then \
    apt-get -o Dpkg::Options::="--force-confold" install --no-install-recommends -qqy \
    # nordvpn requirements \
    iproute2 iptables readline-common dirmngr gnupg gnupg-l10n gnupg-utils gpg gpg-agent gpg-wks-client \
    gpg-wks-server gpgconf gpgsm libassuan0 libksba8 libnpth0 libreadline8 libsqlite3-0 lsb-base pinentry-curses; fi \
    && wget -nv -t10 -O /tmp/nordrepo.deb https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb \
    && apt-get install -qqy --no-install-recommends /tmp/nordrepo.deb && apt-get update \
    && apt-get install -qqy --no-install-recommends -y nordvpn="${VERSION}" \
    && apt-get remove -y wget nordvpn-release \
    && mkdir -p /run/nordvpn \
    #chmod a+x /app/*.sh  \
    && addgroup --system vpn && useradd -lNms /usr/bash -u "${NUID:-1000}" -G nordvpn,vpn nordclient \
    && apt-get clean all && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    #transmission user
    && groupmod -g 1000 users && useradd -u 911 -U -d /config -s /bin/false abc && usermod -G users abc \
    && if [[ -n ${aptcacher} ]]; then rm /etc/apt/apt.conf.d/01proxy; fi \
    # patch wg-quick script to remove the need for running in privilegied mode
    && sed -i "s:sysctl -q net.ipv4.conf.all.src_valid_mark=1:echo skipping setting net.ipv4.conf.all.src_valid_mark:" /usr/bin/wg-quick


FROM debian-base AS debian-dev

ARG aptcacher=''
ARG VERSION=3.15.1
ARG TZ=America/Chicago
ARG NORDVPNCLIENT_INSTALLED=1
ARG TBT_VERSION

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

#hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcurl4-openssl-dev libssl-dev \
    pkg-config build-essential checkinstall wget tar zlib1g-dev intltool jq bash cmake g++ make python3 \
    gettext libdeflate-dev libevent-dev libfmt-dev libminiupnpc-dev \
    libnatpmp-dev libpsl-dev ninja-build xz-utils clang-format clang clang-tidy git

WORKDIR /var/tmp
#hadolint ignore=DL3003,DL3008,SC3010
RUN if [[ "dev" == "${TBT_VERSION}" ]]; then \
    echo "Fetching and building ${TBT_VERSION} of transmission" \
    && git clone --depth 1 --branch main https://github.com/transmission/transmission \
    && cd transmission  \
    && git submodule update --init && mkdir build \
    && cd build && cmake \
        -S src \
        -B obj \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_CXX_COMPILER='/usr/bin/clang++' \
        -DCMAKE_CXX_FLAGS='-gdwarf-4 -fno-omit-frame-pointer -fsanitize=address,leak,undefined' \
        -DCMAKE_C_COMPILER='/usr/bin/clang' \
        -DCMAKE_C_FLAGS='-gdwarf-4 -fno-omit-frame-pointer -fsanitize=address,leak,undefined' \
        -DCMAKE_INSTALL_PREFIX=pfx \
        -DENABLE_CLI=ON \
        -DENABLE_DAEMON=ON \
        -DENABLE_GTK=OFF \
        -DENABLE_MAC=OFF \
        -DENABLE_QT=OFF \
        -DENABLE_TESTS=ON \
        -DENABLE_UTILS=ON \
        -DENABLE_WEB=ON \
        -DRUN_CLANG_TIDY=ON .. \
        && cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo .. \
        # && cp /var/tmp/transmission-${TBT_VERSION}/*.deb /var/tmp/ ;fi \
        && make \
        && make install \
        ; fi

#build from tagged version
#hadolint ignore=DL3003,DL3008,DL3047,SC2053
RUN if [[ ${TBT_VERSION} =~ [34] ]]; then \
    if [[ ${TBT_VERSION} =~ 3 ]]; then \
      URL=https://github.com/transmission/transmission-releases/raw/master/transmission-3.00.tar.xz \
      && apt-get install -y --no-install-recommends libgtkmm-3.0-dev gettext qttools5-dev build-essential cmake libcurl4-openssl-dev libssl-dev; \
    else URL=https://github.com/transmission/transmission-releases/raw/master/transmission-4.0.0-beta.1+r98cf7d9b3c.tar.xz; fi \
    && echo "Fetching and building ${URL##*/} of transmission" \
    && mkdir -p /var/tmp/transmission \
    && wget --no-cache -O- ${URL} | tar -Jx -C /var/tmp/transmission --strip-components=1 \
    && cd transmission && mkdir build && cd build \
    && ls -al .. \
    && pwd \
    && cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo .. \
    && make \
    && make install \
    && cd /var/tmp/transmission/build \
    && echo "version: ${TBT_VERSION} / ${TBT_VERSION##*v}" \
    && if [[ dev == ${TBT_VERSION}  ]]; then TBT_VERSION=v4; fi \
    && checkinstall -y -D --pkgname transmission  --pakdir /var/tmp --pkgversion="${TBT_VERSION##*v}.0.0" ; fi

FROM debian-base AS new

ARG aptcacher=''
ARG DEBIAN_FRONTEND=noninteractive
ARG TBT_VERSION=3.00
ARG TARGETPLATFORM

ENV TZ=${TZ}
ENV NORDVPNCLIENT_INSTALLED=${NORDVPNCLIENT_INSTALLED}

VOLUME /data
VOLUME /config

COPY --from=TransmissionUIs /opt/transmission-ui /opt/transmission-ui
COPY --from=debian-dev /var/tmp/*.deb /var/tmp/
#COPY --from=debian-dev /usr/local/bin/ /usr/local/bin/
#COPY --from=debian-dev /usr/local/share/ /usr/local/share/

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

#hadolint ignore=DL3008,SC2046
RUN echo "cpu: ${TARGETPLATFORM}" \
    && if [ -f /var/tmp/transmission_*_$(dpkg --print-architecture).deb ]; then \
    ls -alh /var/tmp/*.deb \
    && echo "Installing transmission ${TBT_VERSION}" \
    && dpkg -i /var/tmp/transmission_*_$(dpkg --print-architecture).deb  ;\
    else echo "Installing transmission from repository" \
    && apt-get update && apt-cache search transmission \
    && apt-get install -y --no-install-recommends transmission-daemon transmission-cli; fi \
    && ln -s /usr/share/transmission/web/style /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/images /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/javascript /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/index.html /opt/transmission-ui/transmission-web-control/index.original.html \
    && rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

COPY --chmod=755 etc/ /etc/
COPY --chmod=755 app/ /app/

HEALTHCHECK --interval=5m --timeout=20s --start-period=1m CMD /app/healthcheck.sh

ENV GLOBAL_APPLY_PERMISSIONS=true \
    TRANSMISSION_WEB_UI=transmission-web-control \
    TRANSMISSION_HOME=/config/transmission-home \
    TRANSMISSION_RPC_PORT=9091 \
    TRANSMISSION_RPC_USERNAME="" \
    TRANSMISSION_RPC_PASSWORD="" \
    TRANSMISSION_DOWNLOAD_DIR=/data/completed \
    TRANSMISSION_INCOMPLETE_DIR=/data/incomplete \
    TRANSMISSION_WATCH_DIR=/data/watch \
    CREATE_TUN_DEVICE=true \
    ENABLE_UFW=false \
    UFW_ALLOW_GW_NET=false \
    UFW_EXTRA_PORTS='' \
    UFW_DISABLE_IPTABLES_REJECT=false \
    PUID=''\
    PGID='' \
    PEER_DNS=true \
    PEER_DNS_PIN_ROUTES=true \
    DROP_DEFAULT_ROUTE='' \
    WEBPROXY_ENABLED=false \
    WEBPROXY_PORT=8888 \
    WEBPROXY_USERNAME='' \
    WEBPROXY_PASSWORD='' \
    LOG_TO_STDOUT=false \
    HEALTH_CHECK_HOST=google.com \
    SELFHEAL=false  \
    EP_IP='' \
    EP_PORT='' \
    LISTEN_PORT='51820' \
    PRIVATE_KEY='' \
    PUBLIC_KEY='' \
    ALLOWED_IPS='' \
    TABLE=auto \
    FWMARK=0x1fe1 \
    PERSISTENT_KEEP_ALIVE=25 \
    DNS="103.86.96.100, 103.86.99.100" \
    PRE_UP='' \
    POST_UP='' \
    PRE_DOWN='' \
    POST_DOWN=''

# Start supervisord as init system
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
