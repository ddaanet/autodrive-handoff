#!/usr/bin/env bash
# Validate one ref of ddaanet/autodrive-handoff in the portal tab named
# `directory` and print its summary, blocking titles and the codes.
# Only ever clicks the Validate / Re-validate button.
# Usage: portal-validate.sh <ref> [<7-char sha the report must show>]
set -euo pipefail
ref=$1
sha=${2:-}
cd /Users/david/code/general/tools

node tab.js eval directory "(()=>{
  const i=[...document.querySelectorAll('main input')].find(x=>/^https:\/\/github/.test(x.placeholder||''));
  const s=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
  s.call(i,'ddaanet/autodrive-handoff@$ref');
  i.dispatchEvent(new Event('input',{bubbles:true}));
  i.dispatchEvent(new Event('change',{bubbles:true}));
  return i.value})()" >/dev/null
sleep 1
node tab.js eval directory "(()=>{
  const b=[...document.querySelectorAll('main button')].find(x=>x.innerText.trim()==='Valider');
  if(!b||b.disabled)throw new Error('validate button unavailable');
  b.click();return 'clicked'})()" >/dev/null

for _ in $(seq 1 40); do
  sleep 3
  line=$(node tab.js eval directory "(document.querySelector('main').innerText.match(/\\S+ @ [0-9a-f]{7} · \\d+ checks/)||[''])[0]" 2>/dev/null || true)
  case "$line" in *"$ref @ $sha"*) break ;; esac
  line=
done
[[ -n "$line" ]] || { echo "$ref: no report in time"; exit 1; }
sleep 1

node tab.js eval directory "(()=>{
  [...document.querySelectorAll('main [aria-expanded=false]')]
    .filter(b=>/^(Blocking|Policy hold)/.test(b.innerText.trim())).forEach(b=>b.click());
  return 1})()" >/dev/null
sleep 1
node tab.js eval directory "document.querySelector('main').innerText" |
  node -e '
const t=JSON.parse(require("fs").readFileSync(0,"utf8"));
const head=(t.match(/Validation: .*/)||["no summary"])[0];
const prov=(t.match(/\S+ @ [0-9a-f]{7} · \d+ checks/)||[""])[0];
const blocking=[...t.matchAll(/Blocking:\n(.*)\n(.*)/g)].map(m=>m[1]+" @ "+m[2]);
const held=[...t.matchAll(/Policy hold:\n(.*)/g)].map(m=>m[1]);
const notFollowed=(t.match(/The plugin.s commands run files the validator could not check[^\n]*/)||[""])[0];
const lines=[prov+" :: "+head];
for(const b of blocking)lines.push("  BLOCK "+b);
lines.push("  holds: "+held.length+" :: "+held.join(" | "));
if(notFollowed)lines.push("  "+notFollowed.slice(0,520));
console.log(lines.join("\n"));'
