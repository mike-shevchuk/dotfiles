import { exec } from "child_process";
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

export function sanitize(str: string): string {
  return str.replace(/[^a-zA-Z0-9 _\-.,!?:()]/g, "");
}

export function readInput<T>(): T {
  return JSON.parse(readFileSync(0, "utf-8"));
}

export function notify(title: string, message: string, soundFile: string): void {
  const sound = join(homedir(), ".claude", "sounds", `${soundFile}.wav`);
  exec(
    `osascript -e 'display notification "${sanitize(message)}" with title "${sanitize(title)}"'`
  );
  exec(`afplay "${sound}"`);
}
