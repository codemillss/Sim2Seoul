export function GET(request: Request) {
  const destination = new URL(request.url);
  destination.pathname = "/play.html";
  return Response.redirect(destination, 307);
}
