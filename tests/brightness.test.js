const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawn } = require("node:child_process")
const { once } = require("node:events")

const helper = path.resolve(__dirname, "../bin/screensaver-brightness.sh")

function fixture(t, initial = 87) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "screensaver-brightness-"))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  fs.writeFileSync(path.join(dir, "brightness"), String(initial))
  fs.writeFileSync(path.join(dir, "omarchy-hw-display"), "#!/bin/bash\necho intel_backlight\n", { mode: 0o755 })
  fs.writeFileSync(path.join(dir, "brightnessctl"), `#!/usr/bin/env node
const fs = require("node:fs")
const path = require("node:path")
const args = process.argv.slice(2)
if (!args.includes("--class=backlight") || !args.includes("--device=intel_backlight")) process.exit(9)
const file = path.join(process.env.TEST_BRIGHTNESS_DIR, "brightness")
if (args.includes("get")) console.log(fs.readFileSync(file, "utf8"))
else if (args.includes("max")) console.log("1000")
else if (args.includes("set")) {
  if (process.env.TEST_DENY_DIM === "1" && args.at(-1) === "1") process.exit(1)
  fs.writeFileSync(file, args.at(-1))
} else process.exit(9)
`, { mode: 0o755 })
  const env = { ...process.env, PATH: `${dir}:${process.env.PATH}`, XDG_RUNTIME_DIR: dir, TEST_BRIGHTNESS_DIR: dir }
  return { dir, env, value: () => Number(fs.readFileSync(path.join(dir, "brightness"), "utf8")) }
}

async function start(t, data, level = 0) {
  const child = spawn("bash", [helper, String(level)], { env: data.env, stdio: ["pipe", "pipe", "pipe"] })
  const exited = once(child, "exit")
  const ready = new Promise((resolve, reject) => {
    let output = ""
    child.stdout.on("data", chunk => { output += chunk; if (output.includes("dimmed")) resolve() })
    child.on("exit", code => { if (!output.includes("dimmed")) reject(new Error(`helper exited before dimming: ${code}`)) })
  })
  t.after(() => { child.stdin.destroy(); if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM") })
  await ready
  return { child, exited }
}

test("dimming restores the exact laptop brightness on dismissal", { timeout: 4000 }, async t => {
  const data = fixture(t)
  const { child, exited } = await start(t, data)
  assert.equal(data.value(), 1)
  child.stdin.end()
  assert.equal((await exited)[0], 0)
  assert.equal(data.value(), 87)
})

test("dimming restores brightness when its tracked launcher terminates", { timeout: 4000 }, async t => {
  const data = fixture(t, 253)
  const { child, exited } = await start(t, data)
  child.kill("SIGTERM")
  await exited
  assert.equal(data.value(), 253)
})

test("restoration survives a killed launcher when the shell's stdin pipe closes", { timeout: 4000 }, async t => {
  const data = fixture(t)
  const { child, exited } = await start(t, data)
  child.kill("SIGKILL")
  await exited
  child.stdin.destroy()
  const deadline = Date.now() + 2000
  while (data.value() !== 87 && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 20))
  assert.equal(data.value(), 87)
})

test("an already dark laptop is never brightened by the screensaver", { timeout: 4000 }, async t => {
  const data = fixture(t, 0)
  const { child, exited } = await start(t, data)
  assert.equal(data.value(), 0)
  child.stdin.end()
  await exited
  assert.equal(data.value(), 0)
})

test("failed dimming leaves the original brightness intact", { timeout: 4000 }, async t => {
  const data = fixture(t)
  data.env.TEST_DENY_DIM = "1"
  const child = spawn("bash", [helper], { env: data.env, stdio: ["pipe", "pipe", "pipe"] })
  const [code] = await once(child, "exit")
  child.stdin.destroy()
  assert.equal(code, 1)
  assert.equal(data.value(), 87)
})

test("an overlapping guard cannot replace the original saved brightness", { timeout: 4000 }, async t => {
  const data = fixture(t)
  const { child, exited } = await start(t, data)
  const overlap = spawn("bash", [helper], { env: data.env, stdio: ["pipe", "pipe", "pipe"] })
  const [code] = await once(overlap, "exit")
  overlap.stdin.destroy()
  assert.equal(code, 1)
  assert.equal(data.value(), 1)
  child.stdin.end()
  await exited
  assert.equal(data.value(), 87)
})

test("configured dim level uses the hardware maximum and still restores the snapshot", { timeout: 4000 }, async t => {
  const data = fixture(t, 800)
  const { child, exited } = await start(t, data, 20)
  assert.equal(data.value(), 200)
  child.stdin.end()
  await exited
  assert.equal(data.value(), 800)
})

test("a dim level above the original brightness never brightens the laptop", { timeout: 4000 }, async t => {
  const data = fixture(t, 87)
  const { child, exited } = await start(t, data, 50)
  assert.equal(data.value(), 87)
  child.stdin.end()
  await exited
  assert.equal(data.value(), 87)
})

test("changing the dim level while visible preserves the original restoration value", { timeout: 4000 }, async t => {
  const data = fixture(t, 800)
  const { child, exited } = await start(t, data, 20)
  child.stdin.write("level:5\n")
  const deadline = Date.now() + 2000
  while (data.value() !== 50 && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 20))
  assert.equal(data.value(), 50)
  child.stdin.end()
  await exited
  assert.equal(data.value(), 800)
})
