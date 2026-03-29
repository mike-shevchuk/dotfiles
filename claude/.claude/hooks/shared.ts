import { exec } from "child_process";
import { readFileSync } from "fs";
import { platform } from "os";
import { homedir } from "os";
import { join } from "path";

export function sanitize(str: string): string {
  return str.replace(/[^a-zA-Z0-9 _\-.,!?:()]/g, "");
}

export function readInput<T>(): T {
  return JSON.parse(readFileSync(0, "utf-8"));
}

export function notify(title: string, message: string, soundFile: string): void {
  const safe_title = sanitize(title);
  const safe_message = sanitize(message);
  const sound = join(homedir(), ".claude", "sounds", `${soundFile}.wav`);

  if (platform() === "darwin") {
    exec(`osascript -e 'display notification "${safe_message}" with title "${safe_title}"'`);
    exec(`afplay "${sound}"`);
  } else {
    exec(`notify-send "${safe_title}" "${safe_message}"`);
    exec(`paplay "${sound}" 2>/dev/null || aplay "${sound}" 2>/dev/null`);
  }
}
