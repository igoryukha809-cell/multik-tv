FROM ossrs/srs:5
COPY srs.conf /usr/local/srs/conf/multik-tv.conf
EXPOSE 1935 8080
CMD ["./objs/srs", "-c", "conf/multik-tv.conf"]