FROM ossrs/srs:5
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg bash ca-certificates fonts-dejavu-core curl && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/local/srs
COPY srs.conf /usr/local/srs/conf/multik-tv.conf
COPY railway-start.sh /usr/local/srs/railway-start.sh
RUN chmod +x /usr/local/srs/railway-start.sh
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD curl -fsS http://127.0.0.1:8080/live/multiktv.m3u8 >/dev/null || exit 1
CMD ["/usr/local/srs/railway-start.sh"]
