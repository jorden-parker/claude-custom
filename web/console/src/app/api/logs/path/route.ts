import { connection } from "next/server";
import { requestedLogPath } from "../log-request";

export async function GET(request: Request) {
  await connection();
  const logPath = await requestedLogPath(request);
  if (logPath instanceof Response) {
    return logPath;
  }
  return Response.json({ path: logPath });
}
