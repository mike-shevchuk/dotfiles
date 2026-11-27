import { execFile } from "child_process";
import { readFileSync } from "fs";
import { platform } from "os";
import { homedir } from "os";
import { join } from "path";

// text goes as argv (no shell), so only control chars need dropping: Cyrillic, quotes and emoji stay
export function sanitize(str: string): string {
  return str.replace(/[\u0000-\u001f\u007f]+/g, " ").trim();
}

export function readInput<T>(): T {
  return JSON.parse(readFileSync(0, "utf-8"));
}

export function notify(title: string, message: string, soundFile: string): void {
  const safe_title = sanitize(title);
  const safe_message = sanitize(message);
  const sound = join(homedir(), ".claude", "sounds", `${soundFile}.wav`);

  if (platform() === "darwin") {
    execFile("osascript", ["-e", "on run argv", "-e", "display notification (item 1 of argv) with title (item 2 of argv)",
      "-e", "end run", safe_message, safe_title]);
    execFile("afplay", [sound]);
  } else {
    execFile("notify-send", [safe_title, safe_message]);
    execFile("paplay", [sound], (err) => { if (err) execFile("aplay", [sound], () => {}); });
  }
}
