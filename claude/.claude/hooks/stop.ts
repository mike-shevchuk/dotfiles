import { readInput, notify } from "./shared";

interface StopHookInput {
  session_id: string;
  hook_event_name: "Stop";
  stop_hook_active: boolean;
  last_assistant_message: string;
  cwd: string;
}

const input = readInput<StopHookInput>();

// Avoid infinite loops: don't notify if stop hook is already re-firing
if (!input.stop_hook_active) {
  const preview = (input.last_assistant_message ?? "Done").slice(0, 100);
  notify("Claude Code - Stopped", preview, "stop");
}
