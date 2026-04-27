import { exec } from "child_process";
import { readInput } from "./shared";

interface PostToolUseInput {
  session_id: string;
  hook_event_name: "PostToolUse";
  tool_name: string;
  tool_input: {
    file_path?: string;
    [key: string]: unknown;
  };
  cwd: string;
}

const input = readInput<PostToolUseInput>();
const filePath = input.tool_input?.file_path;

if (!filePath) process.exit(0);

// Escape path for safe shell use
const safe = filePath.replace(/'/g, "'\\''");

if (filePath.endsWith(".py")) {
  // ruff check for lint + ruff format for style
  exec(`ruff check --fix '${safe}' 2>/dev/null; ruff format '${safe}' 2>/dev/null`);
} else if (filePath.endsWith(".ts") || filePath.endsWith(".tsx")) {
  exec(`eslint --fix '${safe}' 2>/dev/null`);
} else if (filePath.endsWith(".js") || filePath.endsWith(".mjs")) {
  exec(`eslint --fix '${safe}' 2>/dev/null`);
} else if (filePath.endsWith(".lua")) {
  exec(`stylua '${safe}' 2>/dev/null`);
}
// Silently exit for unsupported extensions
