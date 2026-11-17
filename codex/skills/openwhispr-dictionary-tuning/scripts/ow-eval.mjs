// OpenWhispr の設定画面 (panel=true のページ) で JavaScript を評価し、結果を標準出力へ書く。
// 使い方: node ow-eval.mjs <file.js>
//   file.js は async 関数の本体として評価する。値は return で返し、await をそのまま書ける。
//   次の 2 つを使える:
//     await ow.store()     設定画面のストア。getState() で設定値と setter を得る
//     await ow.reasoning() 整形処理 (processText・getSystemPrompt を持つ)
// OpenWhispr を --remote-debugging-port=9333 付きで起動しておく。ポートは環境変数 OW_CDP_PORT で変えられる。
import fs from "node:fs";

// 設定画面が先読みしているモジュールから、ハッシュ付きの名前のバンドルを探して読み込む
export const OW_PRELUDE = `const ow={
  async mod(name){const url=[...document.querySelectorAll("link[rel=modulepreload]")].map(l=>l.href).find(n=>new RegExp("/"+name+"-[^/]+\\\\.js$").test(n));if(!url)throw new Error(name+" のバンドルが見つかりません");return import(url)},
  async store(){const m=await this.mod("settingsStore");const s=Object.values(m).find(v=>{try{return v&&typeof v.getState==="function"&&typeof v.getState().setCustomPrompt==="function"}catch(e){return false}});if(!s)throw new Error("設定のストアが見つかりません");return s},
  async reasoning(){const m=await this.mod("ReasoningService");const r=Object.values(m).find(v=>v&&typeof v.processText==="function"&&typeof v.getSystemPrompt==="function");if(!r)throw new Error("整形処理が見つかりません");return r},
};`;

export async function openPanel() {
  const port = process.env.OW_CDP_PORT || "9333";
  const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const target = list.find((t) => t.url.includes("panel=true"));
  if (!target) throw new Error("設定画面のページが見つかりません。引数なしで OpenWhispr をもう一度起動して設定画面を開いてください。");
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r));
  let id = 0;
  const pending = new Map();
  ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); pending.get(m.id)?.(m); pending.delete(m.id); });
  // アプリが終了・再起動すると接続が切れる。待っている評価が止まったままにならないよう、エラーとして返す
  ws.addEventListener("close", () => { for (const r of pending.values()) r({ error: { message: "設定画面との接続が切れました" } }); pending.clear(); });
  // body を async 関数の本体として評価する。毎回関数に包むので、同じ名前の宣言を繰り返しても衝突しない
  const run = async (body) => {
    const expression = `(async()=>{${OW_PRELUDE}\n${body}\n})()`;
    const m = await new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method: "Runtime.evaluate", params: { expression, awaitPromise: true, returnByValue: true } })); });
    if (m.error) throw new Error(m.error.message);
    if (m.result?.exceptionDetails) throw new Error(m.result.exceptionDetails.exception?.description || JSON.stringify(m.result.exceptionDetails).slice(0, 500));
    return m.result?.result?.value;
  };
  return { run, close: () => ws.close() };
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, "/").split("/").pop())) {
  const panel = await openPanel();
  try {
    const v = await panel.run(fs.readFileSync(process.argv[2], "utf8"));
    console.log(typeof v === "string" ? v : JSON.stringify(v, null, 1));
  } finally {
    panel.close();
  }
}
