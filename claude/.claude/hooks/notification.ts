import { readInput, notify } from "./shared";

interface NotificationHookInput {
  session_id: string;
  hook_event_name: "Notification";
  message: string;
  title?: string;
  notification_type: string;
  cwd: string;
}

const input = readInput<NotificationHookInput>();
notify(input.title ?? "Claude Code", input.message ?? "Notification", "notification");
