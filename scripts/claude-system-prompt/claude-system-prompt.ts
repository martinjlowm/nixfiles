// Prints the system prompt that a Claude Code binary sends in an interactive
// session, as Markdown on stdout. The binary talks to a local stand-in for the
// Messages API, which records the first request that carries tools and answers
// every request with a non-retryable error. A capture therefore needs no
// network and no account.
import { spawn } from "node:child_process";
import http from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

interface TextBlock {
  type: "text";
  text: string;
}

interface Tool {
  name: string;
  description?: string;
}

interface MessagesRequest {
  model: string;
  system?: string | TextBlock[];
  tools?: Tool[];
}

interface ApiError {
  type: "error";
  error: { type: "invalid_request_error"; message: string };
}

// The subset of ~/.claude.json that lets a fresh home start an interactive
// session without the onboarding, folder trust and API key dialogs.
interface ClaudeState {
  hasCompletedOnboarding: true;
  customApiKeyResponses: { approved: string[]; rejected: string[] };
  projects: Record<string, { hasTrustDialogAccepted: true }>;
}

const claudeBinary = process.argv[2] ?? "claude";
const captureTimeoutMs = 60_000;
const placeholderApiKey = "sk-ant-api03-claude-system-prompt-placeholder-key";

// The first block names the client build for billing. It is not prompt text.
const billingHeaderPrefix = "x-anthropic-billing-header:";

function systemBlocks(request: MessagesRequest): string[] {
  const system = request.system ?? [];
  const blocks = typeof system === "string" ? [system] : system.map((block) => block.text);
  return blocks.filter((text) => !text.startsWith(billingHeaderPrefix));
}

function renderMarkdown(request: MessagesRequest): string {
  const sections = systemBlocks(request).map((text, index) => `# System block ${index}\n\n${text.trim()}\n`);
  const tools = [...(request.tools ?? [])]
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((tool) => `# Tool: ${tool.name}\n\n${(tool.description ?? "").trim()}\n`);
  return [...sections, ...tools].join("\n");
}

function withoutTemporaryHome(markdown: string, home: string): string {
  return markdown.replaceAll(home, "$HOME").replaceAll(home.replaceAll("/", "-"), "-$HOME");
}

function readBody(request: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

const refusal: ApiError = {
  type: "error",
  error: { type: "invalid_request_error", message: "claude-system-prompt records requests and answers none" },
};

async function startStandIn(): Promise<{ request: Promise<MessagesRequest>; port: number; close: () => void }> {
  let resolveRequest: (request: MessagesRequest) => void = () => {};
  const request = new Promise<MessagesRequest>((resolve) => (resolveRequest = resolve));
  const server = http.createServer(async (incoming, response) => {
    const body = await readBody(incoming);
    if (process.env.CLAUDE_SYSTEM_PROMPT_DEBUG) process.stderr.write(`${incoming.method} ${incoming.url} ${body.length}\n`);
    if (incoming.method === "POST" && incoming.url?.startsWith("/v1/messages")) {
      const parsed = JSON.parse(body) as MessagesRequest;
      if ((parsed.tools?.length ?? 0) > 0) resolveRequest(parsed);
    }
    response.writeHead(400, { "content-type": "application/json" }).end(JSON.stringify(refusal));
  });
  const port = await new Promise<number>((resolve) =>
    server.listen(0, "127.0.0.1", () => resolve((server.address() as AddressInfo).port)),
  );
  return { request, port, close: () => server.close() };
}

function prepareHome(home: string, workingDirectory: string): void {
  const state: ClaudeState = {
    hasCompletedOnboarding: true,
    customApiKeyResponses: { approved: [placeholderApiKey.slice(-20)], rejected: [] },
    projects: { [workingDirectory]: { hasTrustDialogAccepted: true } },
  };
  writeFileSync(path.join(home, ".claude.json"), JSON.stringify(state));
}

// An empty home and working directory keep the user's CLAUDE.md, settings,
// plugins and MCP servers out of the captured prompt. The binary keys folder
// trust by real path, and the macOS temporary directory sits behind a link.
function createEmptyHome(): string {
  const home = realpathSync(mkdtempSync(path.join(tmpdir(), "claude-system-prompt-")));
  prepareHome(home, home);
  return home;
}

// `script` gives the binary a pseudo-terminal, so it starts an interactive
// session. --print sends the Agent SDK prompt instead. `script` waits for end
// of input before it starts the binary, so stdin must be closed.
function startInteractiveSession(home: string, standInPort: number): { stop: () => Promise<void> } {
  const claudeCommand = [claudeBinary, "--exclude-dynamic-system-prompt-sections", "hi"];
  const scriptArguments =
    process.platform === "darwin"
      ? ["-q", "/dev/null", ...claudeCommand]
      : ["-q", "-e", "-c", claudeCommand.map((word) => `'${word.replaceAll("'", `'\\''`)}'`).join(" "), "/dev/null"];
  const child = spawn("script", scriptArguments, {
    cwd: home,
    detached: true,
    stdio: ["ignore", "ignore", "ignore"],
    env: {
      PATH: process.env.PATH ?? "",
      TERM: "xterm-256color",
      HOME: home,
      ANTHROPIC_BASE_URL: `http://127.0.0.1:${standInPort}`,
      ANTHROPIC_API_KEY: placeholderApiKey,
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
    },
  });
  const exited = new Promise<void>((resolve) => child.on("exit", () => resolve()));
  return {
    // The binary runs in the process group that `script` leads, and it keeps
    // writing to its home until it exits.
    stop: async () => {
      process.kill(-child.pid!, "SIGKILL");
      await exited;
    },
  };
}

function rejectAfterTimeout(): Promise<never> {
  return new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error(`no request with tools within ${captureTimeoutMs} ms`)), captureTimeoutMs).unref(),
  );
}

async function main(): Promise<void> {
  const standIn = await startStandIn();
  const home = createEmptyHome();
  const session = startInteractiveSession(home, standIn.port);
  try {
    const request = await Promise.race([standIn.request, rejectAfterTimeout()]);
    process.stdout.write(withoutTemporaryHome(renderMarkdown(request), home));
  } finally {
    await session.stop();
    standIn.close();
    rmSync(home, { recursive: true, force: true, maxRetries: 5 });
  }
}

main().then(
  () => process.exit(0),
  (error: Error) => {
    process.stderr.write(`claude-system-prompt: ${error.message}\n`);
    process.exit(1);
  },
);
