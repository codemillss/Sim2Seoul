import { env } from "cloudflare:workers";
import { createRoomApi } from "@/lib/room-api.mjs";

export const dynamic = "force-dynamic";
const roomApi = createRoomApi();
async function dispatch(request: Request) {
  return (await roomApi(request, { DB: env.DB })) ?? Response.json({ error: "route_not_found" }, { status: 404 });
}
export const GET = dispatch;
export const POST = dispatch;
