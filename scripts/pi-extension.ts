import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

export default function (pi: ExtensionAPI) {
  const hook = join(homedir(), ".frieren-monitor", "hook.sh");
  let active = false;

  function report(event: "start" | "stop") {
    spawnSync(hook, ["pi", event], {
      cwd: process.cwd(),
      timeout: 5000,
      stdio: "ignore",
    });
  }

  pi.on("agent_start", async () => {
    active = true;
    report("start");
  });
  pi.on("agent_settled", async () => {
    if (!active) return;
    active = false;
    report("stop");
  });
  pi.on("session_shutdown", async () => {
    if (!active) return;
    active = false;
    report("stop");
  });
}
