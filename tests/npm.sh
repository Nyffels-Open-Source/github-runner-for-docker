#!/bin/bash
set -euo pipefail
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT
mkdir -p "$work_directory/package" "$work_directory/consumer"
printf '%s\n' '{"name":"runner-npm-smoke","version":"1.0.0","main":"index.js"}' > "$work_directory/package/package.json"
printf '%s\n' 'module.exports = 42;' > "$work_directory/package/index.js"
cd "$work_directory/package"
archive="$(npm pack --ignore-scripts --json | node -p 'Object.values(JSON.parse(require("fs").readFileSync(0, "utf8")))[0].filename')"
cd "$work_directory/consumer"
npm init -y >/dev/null
npm install "../package/$archive" --ignore-scripts --no-audit --no-fund
node -e 'require("assert").strictEqual(require("runner-npm-smoke"), 42)'
npm query '#runner-npm-smoke' > query.json
node -e 'require("assert").strictEqual(Object.values(require("./query.json"))[0].name, "runner-npm-smoke")'
npm ci --ignore-scripts --no-audit --no-fund
node -e 'require("assert").strictEqual(require("runner-npm-smoke"), 42)'
echo 'npm pack, install, query, and ci smoke tests passed.'
