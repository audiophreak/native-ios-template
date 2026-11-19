// The real end-to-end scenario: the app's test target runs on the iOS Simulator against this project's web
// application, a real database and Better Auth. Run it from anywhere:
//
//     node ios/scripts/e2e.mjs [--rebuild] [--down]
//
// It uses the project's own commands (db:init, db:up, db:migrate, build), starts `next start` on a free loopback
// port with open sign-up, creates two throwaway accounts, runs phase one of ios/AppTests/EndToEndTests.swift,
// restarts the web server AND the database, then runs phase two. It prints no secret and no token; the passwords
// are random and exist only in this process. `--down` stops the database at the end (the volume is kept).
import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, openSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ios = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const root = resolve(ios, "..");
const flags = new Set(process.argv.slice(2));
const say = (message) => console.log(`[e2e] ${message}`);
const fail = (message) => {
  console.error(`[e2e] FAILED: ${message}`);
  process.exitCode = 1;
};

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, ...options });
  return { ok: result.status === 0, out: `${result.stdout ?? ""}${result.stderr ?? ""}` };
}

function freePort() {
  return new Promise((done, reject) => {
    const server = createServer();
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => done(port));
    });
    server.on("error", reject);
  });
}

const logDirectory = mkdtempSync(join(tmpdir(), "ios-e2e-"));
let server = null;
let serverLog = "";

async function startServer(port) {
  serverLog = join(logDirectory, `server-${Date.now()}.log`);
  const handle = openSync(serverLog, "a");
  const env = {
    ...process.env,
    PORT: String(port),
    BETTER_AUTH_URL: `http://127.0.0.1:${port}`,
    AUTH_ALLOW_SIGN_UP: "true",
    AUTH_TRUSTED_IP_HEADER: "x-real-ip",
    SUPABASE_ALLOW_LAN_EXPOSURE: process.env.SUPABASE_ALLOW_LAN_EXPOSURE ?? "",
  };
  delete env.NODE_ENV;
  // Node runs Next directly (not through npx): one process, so stopping it stops the server.
  server = spawn(process.execPath, [join(root, "node_modules/next/dist/bin/next"), "start", "-p", String(port), "-H", "127.0.0.1"], { cwd: root, env, stdio: ["ignore", handle, handle] });
  for (let attempt = 0; attempt < 180; attempt += 1) {
    if (server.exitCode !== null || server.signalCode !== null) throw new Error(`the web server exited while starting (see ${serverLog})`);
    try {
      // A short timeout and no kept-alive connection: a socket left over from the server this one replaces must not stall the check.
      const answer = await fetch(`http://127.0.0.1:${port}/api/v1/app-info`, { signal: AbortSignal.timeout(3000), headers: { connection: "close" } });
      if (answer.status === 200) return;
    } catch {}
    await new Promise((wait) => setTimeout(wait, 500));
  }
  const tail = readFileSync(serverLog, "utf8").split("\n").slice(-8).join("\n");
  throw new Error(`the web server did not become ready (alive: ${server.exitCode === null && server.signalCode === null}); its log ends:\n${tail}`);
}

async function stopServer() {
  const target = server;  // not the module variable: a timer must never reach a server started later
  if (!target || target.exitCode !== null || target.signalCode !== null) return;
  await new Promise((done) => {
    const force = setTimeout(() => target.kill("SIGKILL"), 15000);
    target.once("exit", () => {
      clearTimeout(force);
      done();
    });
    target.kill("SIGTERM");
  });
}

async function signUp(port, label, password) {
  const email = `${label}-${randomBytes(4).toString("hex")}@example.test`;
  const response = await fetch(`http://127.0.0.1:${port}/api/auth/sign-up/email`, {
    method: "POST",
    // Node's fetch adds browser-style Fetch Metadata headers, so Better Auth treats it as a browser and wants the origin
    // (the server's own). The app under test is URLSession and sends neither, which is the native-client case.
    headers: { "content-type": "application/json", origin: `http://127.0.0.1:${port}`, "x-real-ip": `10.0.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}` },
    body: JSON.stringify({ email, password, name: label }),
  });
  if (response.status !== 200) throw new Error(`sign-up of ${label} answered ${response.status}`);
  return email;
}

function phase(name, simulator, port, accounts) {
  const env = {
    ...process.env,
    TEST_RUNNER_E2E_PHASE: name,
    TEST_RUNNER_E2E_PORT: String(port),
    TEST_RUNNER_E2E_EMAIL_A: accounts.a,
    TEST_RUNNER_E2E_EMAIL_B: accounts.b,
    TEST_RUNNER_E2E_PASSWORD: accounts.password,
  };
  const log = join(logDirectory, `xcodebuild-${name}.log`);
  const result = spawnSync(
    "xcodebuild",
    ["test", "-project", "App.xcodeproj", "-scheme", "App", "-destination", `id=${simulator}`, "-derivedDataPath", ".derived-data/app", "-only-testing:AppTests/EndToEndTests", "-onlyUsePackageVersionsFromResolvedFile"],
    { cwd: ios, env, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 },
  );
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  writeFileSync(log, output);
  const wanted = name === "one" ? "phase one" : "phase two";
  const ran = new RegExp(`Test "${wanted}[^"]*" passed`).test(output);
  if (result.status !== 0 || !ran) {
    const failures = output.split("\n").filter((line) => /✘|error:|Issue recorded|encountered an error/.test(line)).slice(0, 12).join("\n");
    throw new Error(`phase ${name} did not pass${ran ? "" : " (it did not run)"}; full log: ${log}\n${failures}`);
  }
  say(`phase ${name}: passed`);
}

try {
  if (process.platform !== "darwin") throw new Error("the iOS Simulator needs macOS");
  const simulator = run("sh", [join(ios, "scripts/simulator.sh")]);
  if (!simulator.ok) throw new Error(simulator.out.trim());
  const udid = simulator.out.trim();

  if (!existsSync(join(root, ".env.local"))) {
    say("creating .env.local with `npm run db:init`");
    if (!run("npm", ["run", "--silent", "db:init"]).ok) throw new Error("db:init failed");
  }
  for (const step of ["db:up", "db:migrate"]) {
    say(`npm run ${step}`);
    const result = run("npm", ["run", "--silent", step]);
    if (!result.ok) throw new Error(`${step} failed:\n${result.out.slice(-1500)}`);
  }
  if (flags.has("--rebuild") || !existsSync(join(root, ".next/BUILD_ID"))) {
    say("npm run build");
    const result = run("npm", ["run", "--silent", "build"]);
    if (!result.ok) throw new Error(`build failed:\n${result.out.slice(-1500)}`);
  }

  const port = await freePort();
  say(`starting the web application on 127.0.0.1:${port}`);
  await startServer(port);
  const password = `${randomBytes(9).toString("base64url")}-Aa1`;
  const accounts = { password, a: await signUp(port, "ios-a", password), b: await signUp(port, "ios-b", password) };
  say("two throwaway accounts created");

  phase("one", udid, port, accounts);

  say("restarting the web server and the database");
  await stopServer();
  for (const step of ["db:down", "db:up"]) {
    const result = run("npm", ["run", "--silent", step]);
    if (!result.ok) throw new Error(`${step} failed:\n${result.out.slice(-1500)}`);
  }
  await startServer(port);

  phase("two", udid, port, accounts);

  const log = readFileSync(serverLog, "utf8");
  if (/Bearer [A-Za-z0-9_-]{20,}|set-auth-token/i.test(log)) throw new Error("the server log contains an authorization header");
  say("the server log contains no authorization header or token");
  say("END-TO-END SCENARIO PASSED");
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
} finally {
  await stopServer();
  if (flags.has("--down")) run("npm", ["run", "--silent", "db:down"]);
}
