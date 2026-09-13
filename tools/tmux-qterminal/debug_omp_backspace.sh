#!/usr/bin/env bash
set -euo pipefail


# Evita crash do Bun em CPUs sem AVX (mantém valor já definido pelo usuário).
: "${BUN_JSC_useJIT:=0}"
export BUN_JSC_useJIT
bun -e '
import { parseKey, matchesKey, setKittyProtocolActive } from "@oh-my-pi/pi-tui";

function toHex(str) {
  return Array.from(Buffer.from(str, "utf8"))
    .map(b => b.toString(16).padStart(2, "0"))
    .join(" ");
}

function inspect(label, data) {
  setKittyProtocolActive(true);
  const parse = parseKey(data);
  const isBackspace = matchesKey(data, "backspace");
  const isCtrlQuestion = matchesKey(data, "ctrl+?");
  const isCtrlBackspace = matchesKey(data, "ctrl+backspace");
  const isDelete = matchesKey(data, "delete");

  console.log(`\n[${label}]`);
  console.log(`raw-json: ${JSON.stringify(data)}`);
  console.log(`hex: ${toHex(data)}`);
  console.log(`parseKey: ${String(parse)}`);
  console.log(`matches backspace: ${isBackspace}`);
  console.log(`matches ctrl+?: ${isCtrlQuestion}`);
  console.log(`matches ctrl+backspace: ${isCtrlBackspace}`);
  console.log(`matches delete: ${isDelete}`);
}

async function captureOnce(label) {
  process.stdout.write(`Pressione ${label} agora... `);
  return await new Promise(resolve => {
    process.stdin.once("data", chunk => {
      process.stdout.write("ok\\n");
      const data = typeof chunk === "string" ? chunk : chunk.toString("utf8");
      resolve(data);
    });
  });
}

if (!process.stdin.isTTY || !process.stdin.setRawMode) {
  console.error("stdin nao eh TTY raw, rode isso direto no terminal/tmux.");
  process.exit(1);
}

process.stdin.setRawMode(true);
process.stdin.setEncoding("utf8");
process.stdin.resume();

try {
  const backspace = await captureOnce("BACKSPACE");
  inspect("BACKSPACE", backspace);

  const del = await captureOnce("DELETE");
  inspect("DELETE", del);
} finally {
  process.stdin.setRawMode(false);
  process.stdin.pause();
}
'