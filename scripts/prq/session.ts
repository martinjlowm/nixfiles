// Starts an agent session on the agents console from a brief, so the work on a
// pull request begins without a `Botler` comment on it. The console's
// `POST /new` takes a repository, a ref and a prompt, and the session answers in
// the console. Its only credential is the `__Host-mj_session` cookie that SAML
// login issues, valid for 12 hours, read here from MJ_AGENTS_SESSION.
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline/promises';

const CONSOLE_URL = process.env.PRQ_AGENTS_URL ?? 'https://agents.mj.factbird.com';
const CREATE_TIMEOUT_MS = 30_000;

async function ask(question: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    return (await rl.question(question)).trim().toLowerCase();
  } finally {
    rl.close();
  }
}

function edit(text: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'prq-brief-'));
  const file = join(dir, 'brief.md');
  try {
    writeFileSync(file, text);
    spawnSync(process.env.VISUAL ?? process.env.EDITOR ?? 'vi', [file], { stdio: 'inherit' });
    return readFileSync(file, 'utf8');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Returns the new session's path, or null when the console turned the request
// away, which an expired cookie does by redirecting to the login.
async function createSession(repository: string, ref: string, prompt: string, cookie: string): Promise<string | null> {
  const response = await fetch(`${CONSOLE_URL}/new`, {
    method: 'POST',
    redirect: 'manual',
    signal: AbortSignal.timeout(CREATE_TIMEOUT_MS),
    headers: {
      'content-type': 'application/x-www-form-urlencoded',
      cookie: `__Host-mj_session=${cookie}`,
    },
    body: new URLSearchParams({ repository, ref, prompt }),
  });
  const location = response.headers.get('location') ?? '';
  return location.startsWith('/session/') ? location : null;
}

export async function startSession(repository: string, ref: string, brief: string): Promise<void> {
  let prompt = brief;
  process.stdout.write(`\x1b[2J\x1b[H${prompt}\n\n`);
  for (;;) {
    const answer = await ask(`Start a session on ${repository} at ${ref}? [y]es, [e]dit, [N]o `);
    if (answer === 'e') {
      prompt = edit(prompt);
      process.stdout.write(`\x1b[2J\x1b[H${prompt}\n\n`);
    } else if (answer === 'y') {
      break;
    } else {
      return;
    }
  }

  const cookie = process.env.MJ_AGENTS_SESSION;
  let path: string | null = null;
  let failure = 'MJ_AGENTS_SESSION is not set.';
  if (cookie) {
    process.stdout.write(`Creating the session on ${CONSOLE_URL}…\n`);
    try {
      path = await createSession(repository, ref, prompt, cookie);
      failure = 'The console refused MJ_AGENTS_SESSION, which lasts 12 hours.';
    } catch (error) {
      failure = `The console did not answer: ${(error as Error).message}.`;
    }
  }
  if (path) {
    execFileSync('open', [`${CONSOLE_URL}${path}`]);
    return;
  }
  // The console's /new fills its form from these, so the browser shows the
  // session ready to start. The clipboard keeps the brief for a URL too long
  // for something between the browser and the console.
  execFileSync('pbcopy', { input: prompt });
  const form = new URLSearchParams({ repository, ref, prompt });
  execFileSync('open', [`${CONSOLE_URL}/new?${form}`]);
  process.stdout.write(`${failure} The form is open in the browser and the brief is on the clipboard.\n`);
  await ask('Press enter to return to the list. ');
}
