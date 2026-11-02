// Loads the web export in headless Chrome, prints the console, and saves a screenshot.
// Serve the export first (python tools/serve_web.py), then:
//   node tools/web_smoke.mjs [screenshot.png] [seconds]
// Exits non-zero if the page logs errors or never reports the test world as generated.
// Uses software WebGL (SwiftShader), so frame rates here say nothing about real performance.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const URL = process.env.WEB_URL ?? "http://localhost:8060/index.html";
const CHROME = process.env.CHROME ?? "C:/Program Files/Google/Chrome/Application/chrome.exe";
const screenshotPath = process.argv[2] ?? "web_smoke.png";
const seconds = Number(process.argv[3] ?? 60);
const READY = /(test world|facility) generated/;
const PORT = 9333;

const profile = mkdtempSync(join(tmpdir(), "web-smoke-"));
const chrome = spawn(CHROME, [
	"--headless=new",
	`--remote-debugging-port=${PORT}`,
	`--user-data-dir=${profile}`,
	"--use-angle=swiftshader",
	"--enable-unsafe-swiftshader",
	"--window-size=1280,720",
	"about:blank",
], { stdio: "ignore" });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function pageSocketUrl() {
	for (let i = 0; i < 50; i++) {
		try {
			const targets = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
			const page = targets.find((t) => t.type === "page");
			if (page) return page.webSocketDebuggerUrl;
		} catch {}
		await sleep(200);
	}
	throw new Error("Chrome did not expose a page target");
}

let exitCode = 1;
try {
	const ws = new WebSocket(await pageSocketUrl());
	await new Promise((r) => ws.addEventListener("open", r, { once: true }));
	let nextId = 1;
	const pending = new Map();
	const send = (method, params = {}) => new Promise((resolve) => {
		const id = nextId++;
		pending.set(id, resolve);
		ws.send(JSON.stringify({ id, method, params }));
	});

	let ready = false;
	let errors = 0;
	ws.addEventListener("message", (event) => {
		const msg = JSON.parse(event.data);
		if (msg.id && pending.has(msg.id)) {
			pending.get(msg.id)(msg.result);
			pending.delete(msg.id);
		} else if (msg.method === "Runtime.consoleAPICalled") {
			const text = msg.params.args.map((a) => a.value ?? a.description ?? "").join(" ");
			console.log(`[${msg.params.type}] ${text}`);
			if (msg.params.type === "error") errors++;
			if (READY.test(text)) ready = true;
		} else if (msg.method === "Runtime.exceptionThrown") {
			console.log(`[exception] ${msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text}`);
			errors++;
		}
	});

	await send("Runtime.enable");
	await send("Page.enable");
	await send("Page.navigate", { url: URL });

	const deadline = Date.now() + seconds * 1000;
	while (!ready && Date.now() < deadline) await sleep(500);
	if (ready) await sleep(3000); // Let a few frames render.

	const shot = await send("Page.captureScreenshot", { format: "png" });
	writeFileSync(screenshotPath, Buffer.from(shot.data, "base64"));
	console.log(`screenshot: ${screenshotPath}`);
	console.log(ready ? `READY, ${errors} console error(s)` : `NOT READY after ${seconds}s, ${errors} console error(s)`);
	exitCode = ready && errors === 0 ? 0 : 1;
	ws.close();
} finally {
	chrome.kill();
	await sleep(500);
	try { rmSync(profile, { recursive: true, force: true }); } catch {}
	process.exit(exitCode);
}
