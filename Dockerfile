FROM phusion/baseimage:jammy-1.0.1
MAINTAINER markusressel

RUN apt-get update \
&& apt-get -y install bc \
&& apt-get clean && rm -rf /var/lib/apt/lists/*

COPY zfs-inplace-rebalancing.sh ./

ENTRYPOINT ["./zfs-inplace-rebalancing.sh"]
