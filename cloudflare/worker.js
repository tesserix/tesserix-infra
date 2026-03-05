// =============================================================================
// Cloudflare Worker — Path-based routing for tesserix.app
// =============================================================================
// Replaces: GCP Load Balancer ($18.50/month) + Istio Gateway + EnvoyFilter
// Cost: $0 (free tier: 100,000 requests/day)
//
// Routes:
//   tesserix.app/auth/*           → auth-bff Cloud Run
//   tesserix.app/*                → tesserix-home Cloud Run
//   internal-idp.tesserix.app/*   → (future: identity provider)
//   *.tesserix.app/*              → marketplace storefront (tenant subdomains)
// =============================================================================

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const host = url.hostname;

    // Platform app: tesserix.app
    if (host === "tesserix.app" || host === "www.tesserix.app") {
      // Auth routes → auth-bff
      if (
        url.pathname.startsWith("/auth") &&
        !url.pathname.startsWith("/auth/error")
      ) {
        return proxy(request, url, env.AUTH_BFF_URL);
      }

      // Everything else → tesserix-home (Next.js)
      return proxy(request, url, env.TESSERIX_HOME_URL);
    }

    // Tenant subdomains: {tenant}.tesserix.app → marketplace storefront
    if (host.endsWith(".tesserix.app") && env.STOREFRONT_URL) {
      const tenant = host.replace(".tesserix.app", "");

      // Skip known subdomains
      if (["www", "internal-idp", "api", "status"].includes(tenant)) {
        return new Response("Not Found", { status: 404 });
      }

      const targetUrl = new URL(
        url.pathname + url.search,
        env.STOREFRONT_URL
      );
      const newRequest = new Request(targetUrl, request);
      newRequest.headers.set("X-Tenant-ID", tenant);
      newRequest.headers.set("X-Original-Host", host);
      return fetch(newRequest);
    }

    return new Response("Not Found", { status: 404 });
  },
};

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
