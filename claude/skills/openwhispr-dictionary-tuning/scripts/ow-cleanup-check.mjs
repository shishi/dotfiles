// 文字起こしの文を、OpenWhispr 本体の整形処理に本番と同じ設定で通し、次の 3 つを数える。
//   - 聞き間違いの表の組が、整形の後に何回残ったか
//   - 入力と出力の両方に表の直しを当てて比べ、句読点以外で文字が変わった件数 (辞書による正しい直しも含む。中身を見て判断する)
//   - 整形が失敗した件数 (本番と同じく、失敗・空の出力は生の文が貼られたものとして数える)
// 使い方: node ow-cleanup-check.mjs <inputs.json> [pairs.tsv] [--save result.json]
//   inputs.json: 文字起こしの文の配列 (python ow-history.py --raw-only の出力)
//   pairs.tsv:   「聞き間違い<TAB>正しい表記」を 1 行に 1 組。省略すると、今の整形の指示の表 (「- 誤 → 正」の行) を使う
//   --save:      結果を JSON で保存する。登録の前と後の結果を並べて比べるのに使う
// OpenWhispr を --remote-debugging-port=9333 付きで起動し、設定画面を開いておく。
import fs from "node:fs";

const { openPanel } = await import(new URL("./ow-eval.mjs", import.meta.url));
const argv = process.argv.slice(2);
const saveAt = argv.indexOf("--save");
const savePath = saveAt >= 0 ? argv.splice(saveAt, 2)[1] : null;
const [inputsPath, pairsPath] = argv;
const inputs = JSON.parse(fs.readFileSync(inputsPath, "utf8")).filter((x) => typeof x === "string" && x.trim());
const panel = await openPanel();
const prompt = await panel.run(`return localStorage.getItem("customPrompt.cleanup") || ""`);
const toPairs = (text, re) => [...text.matchAll(re)].map((m) => [m[1].trim(), m[2].trim()]).filter(([w, r]) => w && r);
const pairs = pairsPath
  ? toPairs(fs.readFileSync(pairsPath, "utf8"), /^([^\t\r\n]+)\t([^\r\n]+)$/gm)
  : toPairs(prompt, /^- (.+?) → (.+)$/gm);
// 正しい表記が聞き間違いを含む組 (例: サーバ → サーバー) は、直った出力でも残りに数えてしまうので数えない
const counted = pairs.filter(([w, r]) => !r.includes(w));
// 本番の音声入力と同じ設定 (OpenWhispr 1.11 の audioManager.js の cleanupConfig) を設定画面のストアから組み立てる
const setup = await panel.run(`const s=(await ow.store()).getState();const m=await ow.mod("settingsStore");
  return {model:(typeof m.getEffectiveCleanupModel==="function"?m.getEffectiveCleanupModel():s.cleanupModel)||"",
    disableThinking:s.cleanupDisableThinking,reasoningEffort:s.cleanupReasoningEffort,agentName:localStorage.getItem("agentName")||"OpenWhispr"}`);
const clean = (text) => panel.run(`const r=await ow.reasoning();
  try{return {ok:true,out:await r.processText(${JSON.stringify(text)},${JSON.stringify(setup.model)},${JSON.stringify(setup.agentName)},
    {inferenceScope:"dictationCleanup",temperature:0,requireCompleteOutput:true,disableThinking:${JSON.stringify(setup.disableThinking)},reasoningEffort:${JSON.stringify(setup.reasoningEffort)}})}}
  catch(e){return {ok:false,error:String(e)}}`);
const strip = (s) => s.replace(/[\s、。,.?？!！「」]/g, "");
// 表の直しを 1 回の走査で当てる。正しい表記も自分自身に対応させ、長い語を先に当てるので、
// 正しい表記が聞き間違いを含む組 (サーバ → サーバー) でも「サーバーー」のような二重の直しにならない
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const fixMap = new Map(pairs.flatMap(([w, r]) => [[r, r], [w, r]]).reverse());
const fixRe = fixMap.size ? new RegExp([...fixMap.keys()].sort((a, b) => b.length - a.length).map(esc).join("|"), "g") : null;
const fix = (s) => (fixRe ? s.replace(fixRe, (m) => fixMap.get(m)) : s);
const count = (s) => counted.reduce((a, [w]) => a + (s.split(w).length - 1), 0);
const rows = [];
for (const t of inputs) {
  const r = await clean(t);
  const out = r.ok ? (r.out || "").trim() : "";
  const pasted = out || t; // 失敗・空の出力のとき、本番は生の文を貼る
  rows.push({ input: t, output: pasted, failed: !r.ok || !out, error: r.ok ? undefined : r.error,
    // 「変わった」は、入力と出力の両方に表の直しを当てたうえでの違い。残った聞き間違いは「残り」だけに数え、
    // 登録の前後で「変わった」の意味がそろうようにする
    left: count(pasted), before: count(t), changed: !(!r.ok || !out) && strip(fix(pasted)) !== strip(fix(t)) });
}
panel.close();
const sum = (k) => rows.reduce((a, x) => a + (typeof x[k] === "boolean" ? Number(x[k]) : x[k]), 0);
const result = { model: setup.model, pairs: pairs.length, inputs: rows.length, before: sum("before"), left: sum("left"), changed: sum("changed"), failed: sum("failed"), rows };
if (savePath) fs.writeFileSync(savePath, JSON.stringify(result, null, 1));
console.log(`モデル: ${result.model} / 表の組: ${result.pairs} / 入力: ${result.inputs} 件`);
console.log(`聞き間違い: ${result.before} 回 → 残り ${result.left} 回`);
console.log(`表の直し・句読点以外で文字が変わった: ${result.changed} 件`);
console.log(`整形の失敗・空の出力: ${result.failed} 件${result.failed ? " (この測定は比較に使わない。アプリが使用中でないことを確かめて測り直す)" : ""}`);
for (const x of rows.filter((x) => x.failed)) console.log(`[失敗] ${x.input}\n     ${x.error || "空の出力"}`);
for (const x of rows.filter((x) => x.left)) console.log(`[残り] ${x.input}\n     → ${x.output}`);
for (const x of rows.filter((x) => x.changed && !x.failed)) console.log(`[変化] ${x.input}\n     → ${x.output}`);
