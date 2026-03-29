import { exec, execSync } from "child_process";
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

interface StopHookInput {
  session_id: string;
  hook_event_name: "Stop";
  stop_hook_active: boolean;
  last_assistant_message: string;
  cwd: string;
}

function sanitize(str: string): string {
  return str.replace(/[^a-zA-Z0-9 _\-.,!?:()]/g, "");
}

function main() {
  const input: StopHookInput = JSON.parse(readFileSync(0, "utf-8"));

  // Avoid infinite loops: don't notify if stop hook is already re-firing
  if (input.stop_hook_active) return;

  const preview = sanitize(
    (input.last_assistant_message ?? "Done").slice(0, 100)
  );
  const sound = join(homedir(), ".claude", "sounds", "stop.wav");
  execSync(
    `osascript -e 'display notification "${preview}" with title "Claude Code - Stopped"'`
  );
  exec(`afplay "${sound}"`);
}

main();
