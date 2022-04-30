FROM debian:bullseye-slim

ARG aptcacher=''
ARG VERSION=3.12.5
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
    echo -e "alias checkip='curl -sm10 \"https://zx2c4.com/ip\";\n'\nalias checkhttp='curl -sm 10 -x http://0.0.0.0:${WEBPROXY_PORT} \"https://ifconfig.me/ip\";\n'\nalias checksocks='curl -x http://0.0.0.0:1080 \"https://ifconfig.me/ip\";\n'" >> ~/.bash_aliases\
    echo -e "alias checkvpn='curl -m 10 -s https://api.nordvpn.com/vpn/check/full | jq -r \'.[\"status\"]\';\n"  >> ~/.bash_aliases \
    # allow to install resolvconf
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections \
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
    && mkdir -p /opt/transmission-ui \
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
    && wget --no-cache -qO- "$(wget --no-cache -qO- https://api.github.com/repos/ronggang/transmission-web-control/releases/latest | jq --raw-output '.tarball_url')" | tar -C /opt/transmission-ui/transmission-web-control/ --strip-components=2 -xz \
    # ui end \
    && wget -nv -t10 -O /tmp/nordrepo.deb https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb \
    && apt-get install -qqy --no-install-recommends /tmp/nordrepo.deb && apt-get update \
    && apt-get install -qqy --no-install-recommends -y nordvpn="${VERSION}" \
    && apt-get remove -y wget nordvpn-release && find /etc/apt/ -iname "*.list" -exec cat {} \; && echo \
    && mkdir -p /run/nordvpn \
    #chmod a+x /app/*.sh  \
    && addgroup --system vpn && useradd -lNms /usr/bash -u "${NUID:-1000}" -G nordvpn,vpn nordclient \
    && apt-get clean all && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    #transmission user
    && groupmod -g 1000 users && useradd -u 911 -U -d /config -s /bin/false abc && usermod -G users abc \
    && if [[ -n ${aptcacher} ]]; then rm /etc/apt/apt.conf.d/01proxy; fi \
    # patch wg-quick script to remove the need for running in privilegied mode
    && sed -i "s:sysctl -q net.ipv4.conf.all.src_valid_mark=1:echo skipping setting net.ipv4.conf.all.src_valid_mark:" /usr/bin/wg-quick \
    && cat /etc/tinyproxy/tinyproxy.conf

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
    WEBPROXY_PORT=8118 \
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
