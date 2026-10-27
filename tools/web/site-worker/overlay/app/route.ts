export function GET(request: Request) {
  const destination = new URL(request.url);
  destination.pathname = "/index.html";
  return Response.redirect(destination, 307);
}
