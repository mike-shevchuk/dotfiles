import { exec, execSync } from "child_process";
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

interface SubagentStopHookInput {
  session_id: string;
  hook_event_name: "SubagentStop";
  stop_hook_active: boolean;
  agent_id: string;
  agent_type: string;
  last_assistant_message: string;
  cwd: string;
}

function sanitize(str: string): string {
  return str.replace(/[^a-zA-Z0-9 _\-.,!?:()]/g, "");
}

function main() {
  const input: SubagentStopHookInput = JSON.parse(readFileSync(0, "utf-8"));

  if (input.stop_hook_active) return;

  const agentType = sanitize(input.agent_type ?? "Subagent");
  const sound = join(homedir(), ".claude", "sounds", "subagent_stop.wav");
  execSync(
    `osascript -e 'display notification "${agentType} agent completed" with title "Claude Code - Subagent"'`
  );
  exec(`afplay "${sound}"`);
}

main();
