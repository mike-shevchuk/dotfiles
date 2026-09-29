import { readInput, notify } from "./shared";

interface PreToolUseInput {
  session_id: string;
  hook_event_name: "PreToolUse";
  tool_name: string;
  tool_input: {
    command?: string;
    [key: string]: unknown;
  };
  cwd: string;
}

const DANGEROUS_PATTERNS: { pattern: RegExp; label: string }[] = [
  { pattern: /rm\s+-[rf]{1,2}\b/i,          label: "rm -rf" },
  { pattern: /git\s+reset\s+--hard/i,        label: "git reset --hard" },
  { pattern: /git\s+push\s+(-f|--force)/i,   label: "git push --force" },
  { pattern: /git\s+clean\s+-[a-z]*f/i,      label: "git clean -f" },
  { pattern: /git\s+checkout\s+--\s/i,       label: "git checkout --" },
  { pattern: /git\s+branch\s+-D\s/i,         label: "git branch -D" },
  { pattern: /DROP\s+TABLE/i,                label: "DROP TABLE" },
  { pattern: /DROP\s+DATABASE/i,             label: "DROP DATABASE" },
  { pattern: /TRUNCATE\s+TABLE/i,            label: "TRUNCATE TABLE" },
  { pattern: /chmod\s+-R\s+777/i,            label: "chmod -R 777" },
  { pattern: /:\s*>\s*\S/,                   label: "> file truncate" },
];

const input = readInput<PreToolUseInput>();
const command = input.tool_input?.command ?? "";

const matches = DANGEROUS_PATTERNS.filter((p) => p.pattern.test(command));
if (matches.length > 0) {
  const labels = matches.map((m) => m.label).join(", ");
  const preview = command.slice(0, 80).replace(/\n/g, " ");
  notify("!! Danger Guard !!", `${labels}: ${preview}`, "notification");
}
// Always exit 0 — notify only, never block
