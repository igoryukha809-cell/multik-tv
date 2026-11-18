FROM alpine:3.20
RUN apk add --no-cache ffmpeg bash coreutils font-dejavu
WORKDIR /app
COPY loop.sh /app/loop.sh
RUN chmod +x /app/loop.sh
ENTRYPOINT ["/app/loop.sh"]
