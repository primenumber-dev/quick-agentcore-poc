const BASE_URL = process.env.QUICK_API_BASE ??
  "https://qr1.devmarket.myquick.net/home/member/wam_mxlgn/common/docs/api/";

const USER = process.env.QUICK_API_USER;
const PASS = process.env.QUICK_API_PASS;

// QUICK API は POST + application/x-www-form-urlencoded で
// ボディに `P=<URLエンコードしたJSON>` を載せる形式。
// GET でも基本動作するが、銘柄数・要素数が多いと URL 長 (2048+) で詰まるため
// 公式ガイドは POST を推奨している。
export async function callQuickApi<T>(
  endpoint: string,
  payload: unknown
): Promise<T> {
  if (!USER || !PASS) {
    throw new Error("QUICK_API_USER / QUICK_API_PASS are not set");
  }
  const url = new URL(endpoint, BASE_URL);

  const body = "P=" + encodeURIComponent(JSON.stringify(payload));
  const auth = Buffer.from(`${USER}:${PASS}`).toString("base64");
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  if (!res.ok) {
    throw new Error(`Quick API ${endpoint} failed: ${res.status} ${res.statusText}`);
  }
  return (await res.json()) as T;
}
