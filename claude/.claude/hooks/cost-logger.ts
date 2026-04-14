import { appendFileSync, existsSync, mkdirSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { readInput } from "./shared";

interface StopHookInput {
  session_id: string;
  hook_event_name: "Stop";
  stop_hook_active: boolean;
  last_assistant_message: string;
  cwd: string;
}

const input = readInput<StopHookInput>();

// Avoid double-firing when stop hook re-triggers itself
if (input.stop_hook_active) process.exit(0);

// ── Locate JSONL file for this session ───────────────────────────────────────
// Claude stores session files at: ~/.claude/projects/<cwd-as-path>/session_id.jsonl
// where slashes in cwd become hyphens (e.g. /home/user/code → -home-user-code)
const projectDir = input.cwd.replace(/\//g, "-");
const jsonlPath = join(
  homedir(),
  ".claude",
  "projects",
  projectDir,
  `${input.session_id}.jsonl`
);

let inputTokens = 0;
let outputTokens = 0;
const seenIds = new Set<string>();

if (existsSync(jsonlPath)) {
  const lines = readFileSync(jsonlPath, "utf-8").split("\n").filter(Boolean);
  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      // Deduplicate by UUID so cached/repeated entries don't inflate counts
      const msgId: string | undefined = entry?.uuid ?? entry?.message?.id;
      if (msgId) {
        if (seenIds.has(msgId)) continue;
        seenIds.add(msgId);
      }
      const usage = entry?.message?.usage;
      if (usage) {
        inputTokens += usage.input_tokens ?? 0;
        outputTokens += usage.output_tokens ?? 0;
      }
    } catch {
      // skip malformed lines
    }
  }
}

// ── Estimate cost (claude-sonnet-4.x pricing) ─────────────────────────────
// Input: $3/MTok   Output: $15/MTok
const costUsd = (inputTokens * 3 + outputTokens * 15) / 1_000_000;

const now = new Date();
const dateStr = now.toISOString().replace("T", " ").slice(0, 19);
// Group sessions by hour: YYYY-MM-DD-HH
const dateTag = now.toISOString().slice(0, 13).replace("T", "-");

// ── Append to rolling cost log ────────────────────────────────────────────
const claudeDir = join(homedir(), ".claude");
const logPath = join(claudeDir, "session-costs.log");
const logLine =
  `${dateStr}  cwd=${input.cwd}` +
  `  in=${inputTokens.toLocaleString()}  out=${outputTokens.toLocaleString()}` +
  `  cost=$${costUsd.toFixed(4)}\n`;
appendFileSync(logPath, logLine);

// ── Write / append session summary markdown ──────────────────────────────
const sessionsDir = join(claudeDir, "sessions");
mkdirSync(sessionsDir, { recursive: true });
const summaryPath = join(sessionsDir, `${dateTag}.md`);
const preview = (input.last_assistant_message ?? "").slice(0, 300);
const summary = [
  `# Session ${dateStr}`,
  ``,
  `**CWD:** \`${input.cwd}\``,
  `**Session ID:** \`${input.session_id}\``,
  `**Tokens:** ${inputTokens.toLocaleString()} in / ${outputTokens.toLocaleString()} out`,
  `**Estimated cost:** $${costUsd.toFixed(4)}`,
  ``,
  `## Last message`,
  preview,
  ``,
  `---`,
  ``,
].join("\n");
appendFileSync(summaryPath, summary);
