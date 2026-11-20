FROM ossrs/srs:5
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg bash ca-certificates fonts-dejavu-core librsvg2-bin curl jq && rm -rf /var/lib/apt/lists/*
WORKDIR /usr/local/srs
COPY srs.conf /usr/local/srs/conf/multik-tv.conf
COPY render-start.sh /usr/local/srs/render-start.sh
COPY generate-original-programs.sh /usr/local/srs/generate-original-programs.sh
COPY brand.svg /usr/local/srs/brand.svg
COPY maintenance.svg /usr/local/srs/maintenance.svg
RUN rsvg-convert -w 512 -h 512 /usr/local/srs/brand.svg -o /usr/local/srs/brand.png && rsvg-convert -w 1280 -h 720 /usr/local/srs/maintenance.svg -o /usr/local/srs/maintenance.png && chmod +x /usr/local/srs/render-start.sh /usr/local/srs/generate-original-programs.sh && bash -n /usr/local/srs/render-start.sh
EXPOSE 10000
CMD ["/usr/local/srs/render-start.sh"]
