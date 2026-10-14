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
const lifecyclePath = new URL("../scripts/windows/lifecycle.ps1", import.meta.url);
const localRootsPath = new URL("../scripts/windows/local-roots.ps1", import.meta.url);

describe("inicialização invisível do Windows", () => {
  it("usa WScript com janela oculta e sem credenciais em argumentos", async () => {
    const launcher = await readFile(launcherPath, "utf8");

    expect(launcher).toContain("shell.Run commandLine, 0, False");
    expect(launcher).toContain("-WindowStyle Hidden");
    expect(launcher).toContain("supervisor.ps1");
    expect(launcher.indexOf("NODARIS_LAUNCHER_ENTERED_UTC")).toBeLessThan(
      launcher.indexOf("shell.Run commandLine")
    );
    expect(launcher.indexOf("NODARIS_LAUNCH_CALL_STARTED_UTC")).toBeLessThan(
      launcher.indexOf("shell.Run commandLine")
    );
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

  it("aguarda parada confirmada antes de solicitar um reinício", async () => {
    const manager = await readFile(managerPath, "utf8");
    const restartStart = manager.indexOf("  'restart' {");
    const restartEnd = manager.indexOf("  'enable' {", restartStart);
    const restart = manager.slice(restartStart, restartEnd);

    expect(manager).toContain("function Request-NodarisStop");
    expect(manager).toContain("AddSeconds($TimeoutSeconds)");
    expect(restart).toContain("if (-not (Request-NodarisStop))");
    expect(restart).not.toContain("Start-Sleep");
  });

  it("distingue health local do polling recente no plano de controle", async () => {
    const launcher = await readFile(launcherPath, "utf8");
    const manager = await readFile(managerPath, "utf8");
    const supervisor = await readFile(supervisorPath, "utf8");
    const diagnostics = await readFile(diagnosticsPath, "utf8");
    const lifecycle = await readFile(lifecyclePath, "utf8");

    expect(manager).toContain("Test-NodarisTunnelReadiness");
    expect(supervisor).toContain("Test-NodarisTunnelReadiness");
    expect(supervisor).toContain("health?details=true");
    expect(supervisor).toContain("startup-events.jsonl");
    expect(supervisor).toContain("project_path_resolve_started");
    expect(supervisor).toContain("diagnostics_load_started");
    expect(supervisor).toContain("lifecycle_load_started");
    expect(supervisor).toContain("mutex_wait_started");
    expect(supervisor).toContain("directory_acl_started");
    expect(supervisor).toContain("first_write_succeeded");
    expect(supervisor).toContain("process_creation_observed");
    expect(supervisor).not.toContain("launch_call_returned");
    expect(supervisor.indexOf("script_entry")).toBeLessThan(
      supervisor.indexOf("project_path_resolve_started")
    );
    expect(supervisor.indexOf("diagnostics_load_started")).toBeLessThan(
      supervisor.indexOf("mutex_wait_started")
    );
    expect(supervisor.indexOf("mutex_wait_started")).toBeLessThan(
      supervisor.indexOf("state_directory_create_started")
    );
    expect(supervisor.indexOf("directory_acl_started")).toBeLessThan(
      supervisor.indexOf("Flush-StartupTrace | Out-Null")
    );
    expect(supervisor).toContain("Invoke-NodarisRecoveryPolicy");
    expect(supervisor).toContain("Stop-NodarisChildrenInOrder");
    expect(supervisor).toContain("@('--import', 'tsx'");
    expect(supervisor).not.toContain("$tsxCli");
    expect(lifecycle).toContain("circuit_open");
    expect(manager).toContain("tunnel_chatgpt_readiness=");
    expect(supervisor).toContain("healthz");
    expect(diagnostics).toContain("[ValidateSet(");
    expect(diagnostics).toContain("timestampUtc =");
    expect(diagnostics).toContain("durationMs =");
    expect(diagnostics).toContain("timeoutSeconds =");
    expect(diagnostics).toContain("backoffSeconds =");
    expect(diagnostics).toContain("Test-NodarisPrivateDirectoryAcl");
    expect(diagnostics).toContain("Test-NodarisPrivateFileAcl");
    expect(diagnostics).toContain("function Write-Diagnostic");
    expect(diagnostics).toContain("| Out-Null");
    expect(diagnostics).toContain("TimestampUtc");
    expect(diagnostics).not.toMatch(/CommandLine|NODARIS_TOKEN|Authorization|Exception\.Message/i);
    expect(launcher).toContain("NODARIS_LAUNCHER_ENTERED_UTC");
    expect(launcher).toContain("NODARIS_LAUNCH_CALL_STARTED_UTC");
    expect(launcher).not.toMatch(/NODARIS_TOKEN|Bearer|Authorization|api.?key/i);
  });

  it("mantém o leitor de raízes isolado até a ativação aprovada", async () => {
    const supervisor = await readFile(supervisorPath, "utf8");
    const reader = await readFile(localRootsPath, "utf8");

    expect(supervisor).toContain("$approvedRoot = 'C:\\Users\\Dell\\Downloads\\Nodaris'");
    expect(supervisor).not.toContain("local-roots.ps1");
    expect(supervisor).not.toContain("Read-NodarisLocalRoots");
    expect(reader).toContain("NODARIS_ROOT_CONFIG_REJECTED");
    expect(reader).toContain("AreAccessRulesProtected");
    expect(reader).toContain("ReparsePoint");
    expect(reader).toContain("candidate.Contains(';')");
    expect(reader).toContain("Test-NodarisJsonKeysUnique");
    expect(reader).toContain("schemaVersion = 1");
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
        expect(output).toContain("lifecycle-diagnostics-fixtures=PASS");
      } finally {
        await rm(outputDirectory, { recursive: true, force: true });
      }
    },
    70_000
  );

  it.skipIf(process.platform !== "win32")(
    "valida configuração local de raízes com ACLs e fixtures temporárias",
    async () => {
      const windowsDirectory = process.env["WINDIR"] ?? "C:\\Windows";
      const powershell = join(
        windowsDirectory,
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe"
      );
      const harness = new URL("./fixtures/windows/local-roots-smoke.ps1", import.meta.url);
      const outputDirectory = await mkdtemp(join(tmpdir(), "nodaris-roots-test-"));
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
          { encoding: "utf8", timeout: 30_000 }
        );
        expect(output).toContain("local-roots-fixtures=PASS");
      } finally {
        await rm(outputDirectory, { recursive: true, force: true });
      }
    },
    40_000
  );
});
