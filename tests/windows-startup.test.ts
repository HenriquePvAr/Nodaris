import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const launcherPath = new URL("../scripts/windows/launcher.vbs", import.meta.url);
const managerPath = new URL("../scripts/windows/nodaris.ps1", import.meta.url);
const supervisorPath = new URL("../scripts/windows/supervisor.ps1", import.meta.url);
const diagnosticsPath = new URL("../scripts/windows/diagnostics.ps1", import.meta.url);

describe("inicialização invisível do Windows", () => {
  it("usa WScript com janela oculta e sem credenciais em argumentos", async () => {
    const launcher = await readFile(launcherPath, "utf8");

    expect(launcher).toContain("shell.Run commandLine, 0, False");
    expect(launcher).toContain("-WindowStyle Hidden");
    expect(launcher).toContain("supervisor.ps1");
    expect(launcher).not.toMatch(/NODARIS_TOKEN|Bearer|runtime.?key|api.?key/i);
  });

  it("registra wscript.exe e preserva uma cópia de recuperação antes do reparo", async () => {
    const manager = await readFile(managerPath, "utf8");
    const repairStart = manager.indexOf("  'repair' {");
    const repairEnd = manager.indexOf("  'uninstall' {", repairStart);
    const repair = manager.slice(repairStart, repairEnd);

    expect(manager).toContain("New-ScheduledTaskAction -Execute $wscript");
    expect(repair).toContain("Export-ScheduledTask");
    expect(repair).toContain("task-before-invisible-launcher.xml");
    expect(repair.indexOf("Export-ScheduledTask")).toBeLessThan(
      repair.indexOf("Set-ScheduledTask")
    );
    expect(repair).toContain("Set-ScheduledTask -TaskName $taskName -Action $action");
    expect(repair).not.toMatch(/NODARIS_TOKEN|Bearer|runtime.?key|api.?key/i);
  });

  it("distingue health local do polling recente no plano de controle", async () => {
    const manager = await readFile(managerPath, "utf8");
    const supervisor = await readFile(supervisorPath, "utf8");
    const diagnostics = await readFile(diagnosticsPath, "utf8");

    expect(manager).toContain("Test-NodarisTunnelReadiness");
    expect(supervisor).toContain("Test-NodarisTunnelReadiness");
    expect(supervisor).toContain("health?details=true");
    expect(supervisor).toContain("startup-events.jsonl");
    expect(manager).toContain("tunnel_chatgpt_readiness=");
    expect(supervisor).toContain("healthz");
    expect(diagnostics).toContain("[ValidateSet(");
    expect(diagnostics).toContain("timestampUtc =");
    expect(diagnostics).toContain("durationMs =");
    expect(diagnostics).toContain("timeoutSeconds =");
    expect(diagnostics).toContain("backoffSeconds =");
    expect(diagnostics).not.toMatch(/CommandLine|NODARIS_TOKEN|Authorization|Exception\.Message/i);
  });

  it.skipIf(process.platform !== "win32")(
    "testa backoff, health fixtures, falha sanitizada, ACL e rotação no PowerShell",
    async () => {
      const windowsDirectory = process.env["WINDIR"] ?? "C:\\Windows";
      const powershell = join(
        windowsDirectory,
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe"
      );
      const harness = new URL("./fixtures/windows/diagnostics-smoke.ps1", import.meta.url);
      const outputDirectory = await mkdtemp(join(tmpdir(), "nodaris-diag-test-"));
      try {
        const output = execFileSync(
          powershell,
          [
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            fileURLToPath(harness),
            outputDirectory
          ],
          { encoding: "utf8", timeout: 60_000 }
        );
        expect(output).toContain("diagnostics-fixtures=PASS");
      } finally {
        await rm(outputDirectory, { recursive: true, force: true });
      }
    },
    70_000
  );
});
