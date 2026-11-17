FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package.json server.js ./
RUN addgroup -S app && adduser -S app -G app \
 && mkdir -p /app/hls && chown -R app:app /app
USER app
EXPOSE 8080
CMD ["node", "server.js"]
