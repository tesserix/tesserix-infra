// =============================================================================
// Cloudflare Worker — Unified routing for tesserix.app + tenant subdomains
// =============================================================================
// Replaces: GCP Load Balancer ($18.50/month) + Istio Gateway + EnvoyFilter
// Cost: $0 (free tier: 100,000 requests/day)
//
// Routes:
//   tesserix.app/auth/*                → auth-bff Cloud Run
//   tesserix.app/*                     → tesserix-home Cloud Run
//   {slug}.mark8ly.com/*               → marketplace storefront
//   {slug}-admin.mark8ly.com/*         → tesserix-home (admin panel)
//   {slug}-admin.mark8ly.com/auth/*    → auth-bff
//   {slug}-api.mark8ly.com/*           → API gateway
//   custom-domain.com/*                → KV lookup → storefront
//   custom-domain.com/auth/*           → KV lookup → auth-bff
// =============================================================================

const RESERVED_SUBDOMAINS = ["www", "internal-idp", "api", "status", "mail", "smtp"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const host = url.hostname;

    // --- Platform app: tesserix.app ---
    if (host === "tesserix.app" || host === "www.tesserix.app") {
      if (url.pathname.startsWith("/auth") && !url.pathname.startsWith("/auth/error")) {
        return proxy(request, url, env.AUTH_BFF_URL);
      }
      return proxy(request, url, env.TESSERIX_HOME_URL);
    }

    // --- Tenant subdomains: *.mark8ly.com ---
    const baseDomain = env.BASE_DOMAIN || "mark8ly.com";
    if (host.endsWith(`.${baseDomain}`)) {
      const subdomain = host.replace(`.${baseDomain}`, "");

      if (RESERVED_SUBDOMAINS.includes(subdomain)) {
        return new Response("Not Found", { status: 404 });
      }

      // Admin subdomain: {slug}-admin.mark8ly.com
      if (subdomain.endsWith("-admin")) {
        const slug = subdomain.replace(/-admin$/, "");
        const route = await lookupRoute(env, slug);
        if (!route) {
          return new Response("Tenant not found", { status: 404 });
        }

        // Auth routes on admin subdomain → auth-bff
        if (url.pathname.startsWith("/auth") && !url.pathname.startsWith("/auth/error")) {
          return proxyWithTenant(request, url, env.AUTH_BFF_URL, route.tenant_id, slug, host);
        }

        // Everything else → tesserix-home (admin panel)
        return proxyWithTenant(request, url, env.TESSERIX_HOME_URL, route.tenant_id, slug, host);
      }

      // API subdomain: {slug}-api.mark8ly.com
      if (subdomain.endsWith("-api")) {
        const slug = subdomain.replace(/-api$/, "");
        const route = await lookupRoute(env, slug);
        if (!route) {
          return new Response("Tenant not found", { status: 404 });
        }
        return proxyWithTenant(request, url, env.API_GATEWAY_URL || env.TESSERIX_HOME_URL, route.tenant_id, slug, host);
      }

      // Storefront subdomain: {slug}.mark8ly.com
      const slug = subdomain;
      const route = await lookupRoute(env, slug);
      if (!route) {
        return new Response("Tenant not found", { status: 404 });
      }
      return proxyWithTenant(request, url, env.STOREFRONT_URL, route.tenant_id, slug, host);
    }

    // --- Custom domains: KV lookup by domain ---
    if (env.TENANT_ROUTES) {
      const domainMapping = await env.TENANT_ROUTES.get(`domain:${host}`, "json");
      if (domainMapping) {
        const route = await lookupRoute(env, domainMapping.slug);
        if (route) {
          // Auth routes on custom domain → auth-bff
          if (url.pathname.startsWith("/auth") && !url.pathname.startsWith("/auth/error")) {
            return proxyWithTenant(request, url, env.AUTH_BFF_URL, route.tenant_id, domainMapping.slug, host);
          }

          // Route based on target type
          const targetUrl = domainMapping.target_type === "admin"
            ? env.TESSERIX_HOME_URL
            : env.STOREFRONT_URL;
          return proxyWithTenant(request, url, targetUrl, route.tenant_id, domainMapping.slug, host);
        }
      }
    }

    return new Response("Not Found", { status: 404 });
  },
};

// Look up tenant route from KV by slug
async function lookupRoute(env, slug) {
  if (!env.TENANT_ROUTES) return null;
  return env.TENANT_ROUTES.get(`tenant:${slug}`, "json");
}

// Proxy request to target origin
function proxy(request, url, targetOrigin) {
  const target = new URL(targetOrigin);
  const newUrl = new URL(url.pathname + url.search, target);
  const newRequest = new Request(newUrl, {
    method: request.method,
    headers: request.headers,
    body: request.body,
    redirect: "manual",
  });
  return fetch(newRequest);
}

// Proxy with tenant context headers
function proxyWithTenant(request, url, targetOrigin, tenantId, slug, originalHost) {
  const target = new URL(targetOrigin);
  const newUrl = new URL(url.pathname + url.search, target);
  const newRequest = new Request(newUrl, {
    method: request.method,
    headers: request.headers,
    body: request.body,
    redirect: "manual",
  });
  newRequest.headers.set("X-Tenant-ID", tenantId);
  newRequest.headers.set("X-Tenant-Slug", slug);
  newRequest.headers.set("X-Original-Host", originalHost);
  return fetch(newRequest);
}
