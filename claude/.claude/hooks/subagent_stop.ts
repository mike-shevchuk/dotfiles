import { readInput, notify } from "./shared";

interface SubagentStopHookInput {
  session_id: string;
  hook_event_name: "SubagentStop";
  stop_hook_active: boolean;
  agent_id: string;
  agent_type: string;
  last_assistant_message: string;
  cwd: string;
}

const input = readInput<SubagentStopHookInput>();

if (!input.stop_hook_active) {
  const agentType = input.agent_type ?? "Subagent";
  notify("Claude Code - Subagent", `${agentType} agent completed`, "subagent_stop");
}
