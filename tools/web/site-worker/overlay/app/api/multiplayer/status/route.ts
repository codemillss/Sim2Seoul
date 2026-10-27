export const dynamic = "force-dynamic";
export function GET(request: Request) {
  return Response.json({ available: true, apiVersion: 1, mode: "sites", signInRequired: !request.headers.get("oai-authenticated-user-id") }, { headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" } });
}
