import { exec, execSync } from "child_process";
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

interface NotificationHookInput {
  session_id: string;
  hook_event_name: "Notification";
  message: string;
  title?: string;
  notification_type: string;
  cwd: string;
}

function sanitize(str: string): string {
  return str.replace(/[^a-zA-Z0-9 _\-.,!?:()]/g, "");
}

function main() {
  const input: NotificationHookInput = JSON.parse(readFileSync(0, "utf-8"));
  const title = sanitize(input.title ?? "Claude Code");
  const message = sanitize(input.message ?? "Notification");
  const sound = join(homedir(), ".claude", "sounds", "notification.wav");
  execSync(
    `osascript -e 'display notification "${message}" with title "${title}"'`
  );
  exec(`afplay "${sound}"`);
}

main();
