FROM node:22-alpine
ENV NODE_ENV=production
RUN apk add --no-cache ffmpeg
WORKDIR /app
COPY package.json server.js learning.js director.js ./
RUN addgroup -S app && adduser -S app -G app && mkdir -p /app/hls /media /data && chown -R app:app /app /media /data
USER app
EXPOSE 8080
CMD ["node","server.js"]
