# syntax=docker/dockerfile:1.3
FROM --platform=$BUILDPLATFORM alpine:3.20 AS TransmissionUIs
ARG TWCV="1.6.33"
ARG TICV="1.8.0"

#hadolint ignore=DL3018,DL3008,DL4006,DL4001
RUN apk update && apk --no-cache add curl jq && mkdir -p /opt/transmission-ui \
    && export \
    && env \
    && echo "Install Shift (master)" \
    && wget --no-cache -qO- https://github.com/killemov/Shift/archive/master.tar.gz | tar xz -C /opt/transmission-ui \
    && mv /opt/transmission-ui/Shift-master /opt/transmission-ui/shift \
    && echo "Install Flood for Transmission (latest)" \
    && wget --no-cache -qO- https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.tar.gz | tar xz -C /opt/transmission-ui \
    && echo "Install Combustion (archived release)" \
    && wget --no-cache -qO- https://github.com/Secretmapper/combustion/archive/release.tar.gz | tar xz -C /opt/transmission-ui \
    && echo "Install kettu (archive master)" \
    && wget --no-cache -qO- https://github.com/endor/kettu/archive/master.tar.gz | tar xz -C /opt/transmission-ui \
    && mv /opt/transmission-ui/kettu-master /opt/transmission-ui/kettu \
    && echo "Install Transmission-Web-Control v${TWCV}" \
    && mkdir /opt/transmission-ui/transmission-web-control \
    #&& curl -sL $(curl -s https://api.github.com/repos/ronggang/transmission-web-control/releases/latest | jq --raw-output '.tarball_url') | tar -C /opt/transmission-ui/transmission-web-control/ --strip-components=2 -xz \
    #&& wget --no-cache -qO- "https://github.com/transmission-web-control/transmission-web-control/releases/download/v${TWCV}/dist.tar.gz" | tar -C /opt/transmission-ui/transmission-web-control/ --strip-components=2 -xz \
    #&& ver=$(curl -s "https://api.github.com/repos/6c65726f79/Transmissionic/releases/latest" | jq -r .tag_name) \
    && echo "Install Transmissionic v${TICV}" \
    && wget -qO- "https://github.com/6c65726f79/Transmissionic/releases/download/v${TICV}/Transmissionic-webui-v${TICV}.zip" | unzip -d /opt/transmission-ui/ - \
    && mv /opt/transmission-ui/web /opt/transmission-ui/transmissionic

#copied transmission web control from local archive
ADD transmission_web_control_1.6.33.tar.xz /opt/transmission-ui/

#FROM debian:bullseye-slim AS debian-base
FROM debian:bookworm-slim AS debian-base

ARG aptcacher=''
ARG VERSION=3.20.2
ARG TZ=UTC/Etc
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
ENV NORDVPN_VERSION=${VERSION}
ENV DEBIAN_FRONTEND=noninteractive
ENV IPTABLES_LEGACY=N

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#add apt-cacher setting if present:
WORKDIR /app
#hadolint ignore=DL3018,DL3008
RUN if [[ -n ${aptcacher} ]]; then echo "Acquire::http::Proxy \"http://${aptcacher}:3142\";" >/etc/apt/apt.conf.d/01proxy; \
    echo "Acquire::https::Proxy \"http://${aptcacher}:3142\";" >>/etc/apt/apt.conf.d/01proxy ; fi; \
    # allow to install resolvconf
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections \
    && apt-get update && export DEBIAN_FRONTEND=non-interactive \
    && apt-get -o Dpkg::Options::="--force-confold" install --no-install-recommends -qqy supervisor wget curl jq \
    ca-certificates tzdata dante-server net-tools unzip unrar-free bc tar bash dnsutils \
    tinyproxy ufw iputils-ping vim libdeflate0 libevent-2.1-7 libnatpmp1 libminiupnpc17 \
    # wireguard \
    wireguard-tools \
    #ui start \
    && if [[ ${NORDVPNCLIENT_INSTALLED} -eq 1 ]]; then \
    apt-get -o Dpkg::Options::="--force-confold" install --no-install-recommends -qqy \
    # nordvpn requirements \
    iproute2 iptables readline-common dirmngr gnupg gnupg-l10n gnupg-utils gpg gpg-agent gpg-wks-client \
    gpg-wks-server gpgconf gpgsm libassuan0 libksba8 libnpth0 libreadline8 libsqlite3-0 lsb-base pinentry-curses; fi \
    && wget -nv -t10 -O /tmp/nordrepo.deb  "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn-release/nordvpn-release_1.0.0_all.deb" \
    && apt-get install -qqy --no-install-recommends /tmp/nordrepo.deb && apt-get update \
    && apt-get install -qqy --no-install-recommends -y nordvpn="${VERSION}" \
    #&& apt-get remove -y wget nordvpn-release \
    && mkdir -p /run/nordvpn \
    #chmod a+x /app/*.sh  \
    && addgroup --system vpn && useradd -lNms /bin/bash -u "${NUID:-1000}" -G nordvpn,vpn nordclient \
    && apt-get clean all && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    #transmission user
    && groupmod -g 1000 users && useradd -u 911 -U -d /config -s /bin/false abc && usermod -G users abc \
    && if [[ -n ${aptcacher} ]]; then rm /etc/apt/apt.conf.d/01proxy; fi \
    # patch wg-quick script to remove the need for running in privilegied mode
    && sed -i "s:sysctl -q net.ipv4.conf.all.src_valid_mark=1:echo skipping setting net.ipv4.conf.all.src_valid_mark:" /usr/bin/wg-quick

FROM debian-base AS new

ARG aptcacher=''
ARG DEBIAN_FRONTEND=noninteractive
ARG TBT_VERSION=4.0.6
ARG TARGETPLATFORM

ENV TZ=${TZ:-Etc/UTC}
ENV NORDVPNCLIENT_INSTALLED=${NORDVPNCLIENT_INSTALLED}

VOLUME /data
VOLUME /config

COPY --from=TransmissionUIs /opt/transmission-ui /opt/transmission-ui
COPY out/transmission_${TBT_VERSION}*.deb /tmp/

SHELL ["/bin/bash", "-o", "pipefail", "-xcu"]

#hadolint ignore=DL3008,SC2046,SC2086
RUN echo "cpu: ${TARGETPLATFORM}" \
    ; if [[ "${TBT_VERSION}" =~ ^3 ]]; then echo "Installing transmission from repository" \
    && apt-get update && apt-get install -y --no-install-recommends transmission-daemon transmission-cli \
    && ln -s /usr/share/transmission/web/style /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/images /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/javascript /opt/transmission-ui/transmission-web-control \
    && ln -s /usr/share/transmission/web/index.html /opt/transmission-ui/transmission-web-control/index.original.html \
    ; fi \
    ; if [[ "dev" == "${TBT_VERSION}" ]]; then export TBT_VERSION=4.1; fi \
    ; if [[ "${TBT_VERSION}" =~ ^4 ]]; then echo "Installing transmission ${TBT_VERSION}" \
    && ARCH="$(dpkg --print-architecture)" \
    && ls -alh /tmp/transmission_${TBT_VERSION}* \
    #&& debfile=(/tmp/transmission_${TBT_VERSION}*_${ARCH}.deb) \
    && debfile=("$(ls /tmp/transmission_${TBT_VERSION}*_${ARCH}.deb)") \
    #&& mapfile -t debfile <<< "${debfiles}" \
    ; if [[ -z ${debfile[*]} ]]; then echo "deb package not found: transmission_${TBT_VERSION}*_${ARCH}.deb, error" ; else \
    dpkg -c "${debfile[@]}" \
    && dpkg -i "${debfile[@]}" \
    && mv /usr/local/share/transmission/public_html /usr/local/share/transmission/public_html_original \
    && mkdir -p /usr/local/share/transmission/public_html \
    && ln -s /usr/local/share/transmission/public_html/images /opt/transmission-ui/transmission-web-control/ \
    && ln -s /usr/local/share/transmission/public_html/transmission-app.js /opt/transmission-ui/transmission-web-control/transmission-app.js \
    && ln -s /usr/local/share/transmission/public_html/index.html /opt/transmission-ui/transmission-web-control/index.original.html \
    ; fi ;fi ; \
    echo "alias checkip='curl -sm 10 \"https://zx2c4.com/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checkhttp='TCF=/run/secrets/TINY_CREDS; [[ -f \${TCF} ]] && TCREDS=\"\$(head -1 \${TCF}):\$(tail -1 \${TCF})@\" || TCREDS=\"\";curl -4 -sm 10 -x http://\${TCREDS}\${HOSTNAME}:\${WEBPROXY_PORT:-8888} \"https://ifconfig.me/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checksocks='TCF=/run/secrets/TINY_CREDS; [[ -f \${TCF} ]] && TCREDS=\"\$(head -1 \${TCF}):\$(tail -1 \${TCF})@\" || TCREDS=\"\";curl -4 -sm 10 -x socks5h://\${TCREDS}\${HOSTNAME}:1080 \"https://ifconfig.me/ip\";echo'" | tee -a ~/.bashrc \
    && echo "alias checkvpn='nordvpn status | grep -oP \"(?<=Status: ).*\"'" | tee -a ~/.bashrc \
    && echo "alias gettiny='grep -vP \"(^$|^#)\" /etc/tinyproxy/tinyproxy.conf'" | tee -a ~/.bashrc \
    && echo "alias getdante='grep -vP \"(^$|^#)\" /etc/dante.conf'" | tee -a ~/.bashrc \
    && echo "alias dltest='curl http://appliwave.testdebit.info/100M.iso -o /dev/null'" | tee -a ~/.bashrc \
    && echo "function getversion(){ apt-get update && apt-get install -y --allow-downgrades nordvpn=\${1:-3.16.9} && supervisorctl start start_vpn; }" | tee -a ~/.bashrc \
    && echo "function showversion(){ apt-cache show nordvpn |grep -oP '(?<=Version: ).+' | sort | awk 'NR==1 {first = \$0} END {print first\" - \"\$0; }'; }" | tee -a ~/.bashrc \
    ; rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/* /tmp/*

COPY --chmod=755 etc/ /etc/
COPY --chmod=755 app/ /app/

HEALTHCHECK --interval=5m --timeout=20s --start-period=1m CMD /app/healthcheck.sh

ENV DEBUG=false
ENV DANTE_DEBUG=0
ENV TRANSMISSION_DEBUG=false
ENV NORDVPN_DEBUG=false
ENV DANTE_DEBUG=0
ENV DANTE_LOGLEVEL=error
ENV TINY_LOGLEVEL=error
ENV GENERATE_WIREGUARD_CONF=false
ENV ANALYTICS=1
ENV KILLERSWITCH=on
ENV CYBER_SEC=off
ENV TECHNOLOGY=nordlynx
ENV OBFUSCATE=off
ENV PROTOCOL=udp
ENV GLOBAL_APPLY_PERMISSIONS=true \
    TRANSMISSION_WEB_UI=transmission-web-control \
    TRANSMISSION_HOME=/config/transmission-home \
    TRANSMISSION_RPC_PORT=9091 \
    TRANSMISSION_RPC_USERNAME="" \
    TRANSMISSION_RPC_PASSWORD="" \
    TRANSMISSION_DOWNLOAD_DIR=/data/completed \
    TRANSMISSION_INCOMPLETE_DIR=/data/incomplete \
    TRANSMISSION_WATCH_DIR=/data/watch \
    TRANSMISSION_LOG_LEVEL="" \
    TRANSMISSION_RPC_WHITELIST_ENABLED=false \
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
    POST_DOWN='' \
    TINYUSER='' \
    TINYPASS='' \
    DANTE_LOGOUTPUT='stdout' \
    TINYLOGOUTPUT='stdout'

# Start supervisord as init system
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
