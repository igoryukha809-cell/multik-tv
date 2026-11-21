/**
 * HLS edge proxy for the channel.
 *
 * Deploy as a Cloudflare Worker and set ORIGIN to the existing Render service
 * URL (for example, https://your-service.onrender.com). Keep the value
 * restricted to the channel's own origin; this worker intentionally does not
 * accept a client-supplied upstream URL.
 */
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "Range, If-None-Match, If-Modified-Since",
  "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges",
};

function responseHeaders(source, cacheControl) {
  const headers = new Headers(source);
  for (const [key, value] of Object.entries(corsHeaders)) headers.set(key, value);
  headers.set("Cache-Control", cacheControl);
  headers.delete("Set-Cookie");
  headers.delete("Server");
  return headers;
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: corsHeaders });
    }
    if (!env.ORIGIN) {
      return new Response("Worker is missing its ORIGIN setting", {
        status: 503,
        headers: { ...corsHeaders, "Cache-Control": "no-store" },
      });
    }

    const incoming = new URL(request.url);
    const origin = new URL(env.ORIGIN);
    if (origin.protocol !== "https:" || origin.username || origin.password) {
      return new Response("ORIGIN must be an HTTPS origin without credentials", {
        status: 500,
        headers: corsHeaders,
      });
    }

    // Only proxy the public HLS path. Never expose arbitrary upstream paths.
    if (!incoming.pathname.startsWith("/live/") ||
        !/\.(m3u8|ts|m4s|mp4)$/.test(incoming.pathname)) {
      return new Response("Not found", { status: 404, headers: corsHeaders });
    }

    const upstream = new URL(incoming.pathname + incoming.search, origin);
    const isPlaylist = incoming.pathname.endsWith(".m3u8");
    const isSegment = /\.(ts|m4s|mp4)$/.test(incoming.pathname);
    const cacheable = request.method === "GET" && isSegment && !request.headers.has("Range");
    const cacheKey = new Request(upstream.toString(), { method: "GET" });
    const cache = caches.default;

    if (cacheable) {
      const cached = await cache.match(cacheKey);
      if (cached) {
        const headers = responseHeaders(cached.headers, "public, max-age=20, s-maxage=20");
        return new Response(cached.body, { status: cached.status, headers });
      }
    }

    const upstreamRequest = new Request(upstream, {
      method: request.method,
      headers: request.headers,
      redirect: "follow",
    });
    const upstreamResponse = await fetch(upstreamRequest);
    const cacheControl = isPlaylist
      ? "no-store, no-cache, must-revalidate"
      : isSegment
        ? "public, max-age=20, s-maxage=20"
        : "no-store";
    const headers = responseHeaders(upstreamResponse.headers, cacheControl);
    const response = new Response(upstreamResponse.body, {
      status: upstreamResponse.status,
      statusText: upstreamResponse.statusText,
      headers,
    });

    if (cacheable && upstreamResponse.ok) {
      ctx.waitUntil(cache.put(
        cacheKey,
        new Response(response.clone().body, {
          status: response.status,
          headers: response.headers,
        }),
      ));
    }
    return response;
  },
};
