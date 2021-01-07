# Set global vars
ARG REL=bionic
ARG ARCH=amd64

#Use alpine as base-build image to pull the ubuntu cloud image from: https://partner-images.canonical.com and create rootfs.
FROM alpine:3.12 as rootfs-stage

#Set Ubuntu REL and ARCH
ARG REL
ENV REL=${REL}
ARG ARCH
ENV ARCH=${ARCH}

# install packages for downloading Ubuntu cloud image
RUN \
 apk add --no-cache \
        bash \
        curl \
        tzdata \
        xz
# Grab base tarball (Ubuntu cloud image compressed) and extract.
RUN \
 mkdir /root-out && \
 curl -o \
	/rootfs.tar.gz -L \
	https://partner-images.canonical.com/core/${REL}/current/ubuntu-${REL}-core-cloudimg-${ARCH}-root.tar.gz && \
 tar xf \
        /rootfs.tar.gz -C \
        /root-out

# Runtime stage (create actual Ubuntu base image).
FROM scratch
COPY --from=rootfs-stage /root-out/ /
ARG BUILD_DATE
ARG VERSION
LABEL build_version="version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="THEcontainers"

# set version for s6 overlay: check "https://github.com/just-containers/s6-overlay/releases" for most recent version
ARG OVERLAY_VERSION="v2.1.0.2"
ARG OVERLAY_ARCH="amd64"

# set ubuntu base image environment variables
ARG REL
ENV REL=${REL}
ARG ARCH
ENV ARCH=${ARCH}
ARG TZ=Europe/Amsterdam
ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/root" \
LANGUAGE="en_US.UTF-8" \
LANG="en_US.UTF-8" \
TERM="xterm"

# Disable main restricted
RUN \
sed -i 's/^#\s*\(*main restricted\)$/\1/g' /etc/apt/sources.list && \
#sed -i 's/^#\s*\(*universe\)$/\1/g' /etc/apt/sources.list && \
#sed -i 's/^#\s*\(*multiverse\)$/\1/g' /etc/apt/sources.list && \
#disable backports repo
sed -i '/-backports/s/^/#/' /etc/apt/sources.list

# Apply docker mods and install some basic packages and set timezone (removes unused timezones)
RUN \
 echo "**** Ripped from Ubuntu Docker Logic ****" && \
 set -xe && \
 echo '#!/bin/sh' \
	> /usr/sbin/policy-rc.d && \
 echo 'exit 101' \
	>> /usr/sbin/policy-rc.d && \
 chmod +x \
	/usr/sbin/policy-rc.d && \
 dpkg-divert --local --rename --add /sbin/initctl && \
 cp -a \
	/usr/sbin/policy-rc.d \
	/sbin/initctl && \
 sed -i \
	's/^exit.*/exit 0/' \
	/sbin/initctl && \
 echo 'force-unsafe-io' \
	> /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
 echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
	> /etc/apt/apt.conf.d/docker-clean && \
 echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
	>> /etc/apt/apt.conf.d/docker-clean && \
 echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' \
	>> /etc/apt/apt.conf.d/docker-clean && \
 echo 'Acquire::Languages "none";' \
	> /etc/apt/apt.conf.d/docker-no-languages && \
 echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' \
	> /etc/apt/apt.conf.d/docker-gzip-indexes && \
 echo 'Apt::AutoRemove::SuggestsImportant "false";' \
	> /etc/apt/apt.conf.d/docker-autoremove-suggests && \
 mkdir -p /run/systemd && \
 echo 'docker' \
	> /run/systemd/container && \
 echo "**** install apt-utils and locales ****" && \
 apt-get update && \
 apt-get -y -u upgrade && \
 apt-get install -y --no-install-recommends \
	gnupg \
	locales && \
 echo "**** install packages ****" && \
 apt-get install -y \
	curl \
	ncdu \
	tzdata && \
 echo "**** generate locale ****" && \
 locale-gen ${LANG} && \
 echo "****Fixing timezone based on timezone set in docker argument****" && \
 rm -rf /etc/localtime && \
 ln -s /usr/share/zoneinfo/${TZ} /etc/localtime && \
 SUBSTR=$(echo ${TZ}| cut -d'/' -f 1) && \
 SUBSTR2=$(echo ${TZ}| cut -d'/' -f 2) && \
 cd /usr/share/zoneinfo && \
 ls | grep -v $SUBSTR | xargs rm -rf && \
 cd /usr/share/zoneinfo/$SUBSTR && \
 ls | grep -v $SUBSTR2 | xargs rm -rf && \
 dpkg-reconfigure -f noninteractive tzdata && \
 cd / && \
 echo "**** add s6 overlay ****" && \
 if [ "${REL}" = "focal" ] ; then \
 curl -o \
 /tmp/s6-overlay.tar.gz -L \
	"https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}.tar.gz" && \
 tar ixfz \
        /tmp/s6-overlay.tar.gz -C / --exclude="./bin" && \
 tar ixzf \
        /tmp/s6-overlay.tar.gz -C /usr ./bin ; \
 else \
 curl -o \
 /tmp/s6-overlay.tar.gz -L \
	"https://github.com/just-containers/s6-overlay/releases/download/${OVERLAY_VERSION}/s6-overlay-${OVERLAY_ARCH}.tar.gz" && \
 tar ixfz \
        /tmp/s6-overlay.tar.gz -C / ; \
 fi && \
 echo "**** create abc user and make our folders ****" && \
 useradd -u 911 -U -d /config -s /sbin/nologin abc && \
 usermod -G users abc && \
 mkdir -p \
	/app \
	/config \
	/defaults && \
 echo "**** cleanup ****" && \
 apt-get clean && \
 echo "**** cleanup locales ****" && \
 cp /usr/share/i18n/locales/en_US /tmp && \
 rm -rf /usr/share/i18n/locales/??_?? && rm -rf /usr/share/i18n/locales/???_?? && \
 cp /tmp/en_US /usr/share/i18n/locales/ && \
 rm -rf \
	/tmp/* \
	/var/lib/apt/lists/* \
	/var/cache/apt/* \
	/var/tmp/* \
	/var/log/* \
	/usr/share/doc/* \
	/usr/share/info/* \
	/usr/share/man/*
		
# add local files
COPY root/ /

# Fix some permissions for copied files
RUN \
 chmod +x /etc/s6/init/init-stage2 && \
 chmod -R 500 /etc/cont-init.d/ && \
 chmod -R 500 /docker-mods

ENTRYPOINT ["/init"]