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
const supervisorRootsFixturePath = new URL(
  "./fixtures/windows/supervisor-roots-smoke.ps1",
  import.meta.url
);
const processIdentityFixturePath = new URL(
  "./fixtures/windows/process-identity-smoke.ps1",
  import.meta.url
);
const finalizationFixturePath = new URL(
  "./fixtures/windows/finalization-smoke.ps1",
  import.meta.url
);

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

  it("confirma identidade de processos e impede encerramento por PID reutilizado", async () => {
    const lifecycle = await readFile(lifecyclePath, "utf8");
    const manager = await readFile(managerPath, "utf8");
    const supervisor = await readFile(supervisorPath, "utf8");

    expect(lifecycle).toContain("function Get-NodarisProcessIdentity");
    expect(lifecycle).toContain("startTimeUtcTicks");
    expect(lifecycle).toContain("executablePathHash");
    expect(lifecycle).toContain("commandLineHash");
    expect(lifecycle).toContain("userSidHash");
    expect(lifecycle).toContain("sessionId");
    expect(lifecycle).toContain("function Get-NodarisSupervisorDisposition");
    expect(lifecycle).toContain("function Stop-NodarisVerifiedProcess");
    expect(lifecycle).toContain("NODARIS_CHILD_IDENTITY_UNCONFIRMED");
    expect(manager).toContain("Get-NodarisSupervisorAssessment");
    expect(manager).not.toMatch(/Get-Process\s+-Id\s+\(\[int\]\$state\.supervisorPid/);
    expect(supervisor).toContain("supervisorIdentity = $script:supervisorIdentity");
    expect(supervisor).toContain("identity = $identity");
    expect(supervisor).toContain("identity_unconfirmed_manual_intervention");
    expect(supervisor).toContain("Stop-NodarisVerifiedProcess");
    expect(supervisor).toContain("if ($circuitOpen) { break }");
    expect(supervisor).not.toContain("taskkill.exe");
    expect(supervisor).not.toMatch(/['"]\/T['"]|['"]\/F['"]/);
    expect(supervisor).not.toMatch(/Write-Diagnostic.*(commandLine|userSid|executablePath)/i);
    expect(supervisor.indexOf("Get-NodarisProcessIdentity -ProcessId $PID")).toBeLessThan(
      supervisor.indexOf("\n  Start-Stack")
    );
  });

  it.skipIf(process.platform !== "win32")(
    "exercita identidade, PID reutilizado, estado legado e parada com PIDs sintéticos",
    async () => {
      const windowsDirectory = process.env["WINDIR"] ?? "C:\\Windows";
      const powershell = join(
        windowsDirectory,
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe"
      );
      const outputDirectory = await mkdtemp(join(tmpdir(), "nodaris-process-identity-"));
      try {
        const output = execFileSync(
          powershell,
          [
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            fileURLToPath(processIdentityFixturePath),
            outputDirectory
          ],
          { encoding: "utf8", timeout: 30_000 }
        );
        expect(output).toContain("process-identity-fixtures=PASS");
        expect(output).toContain("provider-cases=success,access-denied,missing-process");
        expect(output).toContain("safe-stop=mismatch-blocked,match-allowed,query-failure-blocked");
        expect(output).toContain("post-spawn=single-launch,no-retry,no-unverified-stop");
        expect(output).toContain("metadata=sanitized");
      } finally {
        await rm(outputDirectory, { recursive: true, force: true });
      }
    },
    40_000
  );

  it("usa finalização testável que persiste estado parcial e libera o mutex", async () => {
    const lifecycle = await readFile(lifecyclePath, "utf8");
    const supervisor = await readFile(supervisorPath, "utf8");
    const diagnostics = await readFile(diagnosticsPath, "utf8");
    const fixture = await readFile(finalizationFixturePath, "utf8");

    expect(lifecycle).toContain("function Invoke-NodarisFinalization");
    expect(lifecycle).toContain("function Get-NodarisServiceSnapshot");
    expect(lifecycle).toContain("function Test-NodarisComponentStopped");
    expect(lifecycle).toContain("cleanup_failed_manual_intervention");
    expect(lifecycle).toContain("return 'identity_inconclusive'");
    expect(supervisor).toContain("Invoke-NodarisFinalization -Names $finalizationNames");
    expect(supervisor).toContain(
      "$finalizationRequestedStatus = if ($circuitOpen) { 'degraded' } else { 'stopped' }"
    );
    expect(supervisor).toContain(
      "$finalizationRequestedStatus = if ($circuitOpen) { 'degraded' } else { 'error' }"
    );
    expect(supervisor).toContain("$finalizationEvidence[$Name]");
    expect(supervisor).toContain("cleanup_failed_manual_intervention");
    expect(lifecycle).toContain("state_write_failed");
    expect(supervisor).toContain("Get-FinalizationPortStatus");
    expect(supervisor).toContain("if (-not (Test-NodarisPrivateDirectoryAcl $stateRoot))");
    expect(diagnostics).toContain("'state_write_failed'");
    expect(diagnostics).toContain("'mutex_release_failed'");
    expect(fixture).toContain("Invoke-NodarisFinalization -Names");

    if (process.platform !== "win32") return;

    const windowsDirectory = process.env["WINDIR"] ?? "C:\\Windows";
    const powershell = join(
      windowsDirectory,
      "System32",
      "WindowsPowerShell",
      "v1.0",
      "powershell.exe"
    );
    const outputDirectory = await mkdtemp(join(tmpdir(), "nodaris-finalization-"));
    try {
      const output = execFileSync(
        powershell,
        [
          "-NoProfile",
          "-NonInteractive",
          "-ExecutionPolicy",
          "Bypass",
          "-File",
          fileURLToPath(finalizationFixturePath),
          outputDirectory
        ],
        { encoding: "utf8", timeout: 30_000 }
      );
      expect(output).toContain("finalization-fixtures=PASS");
      expect(output).toContain(
        "cleanup-cases=normal,first-child,second-child,multiple,identity-unconfirmed,pid-reuse"
      );
      expect(output).toContain(
        "persistence-cases=after-cleanup,diagnostic-failure,state-write-failure,combined-failure"
      );
      expect(output).toContain(
        "terminal-state-cases=breaker-complete:degraded,breaker-partial:degraded,normal-complete:stopped,startup-error-complete:error,startup-error-breaker:degraded"
      );
      expect(output).toContain(
        "invariants=manual-state-preserved,no-false-stopped,identity-snapshot-retained,manager-blocked,mutex-released,sanitized"
      );
    } finally {
      await rm(outputDirectory, { recursive: true, force: true });
    }
  }, 40_000);

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
    expect(supervisor).toContain("Invoke-NodarisFinalization");
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

  it("carrega e valida as raízes autorizadas antes de iniciar qualquer serviço", async () => {
    const supervisor = await readFile(supervisorPath, "utf8");
    const reader = await readFile(localRootsPath, "utf8");
    const rootsFixture = await readFile(supervisorRootsFixturePath, "utf8");
    const helperStart = supervisor.indexOf("function Get-NodarisAllowedRootsValue");
    const helperEnd = supervisor.indexOf("function Start-Stack", helperStart);
    const integration = supervisor.slice(helperStart, helperEnd);
    const loadCall = supervisor.indexOf("Initialize-NodarisAllowedRoots -ReaderScriptPath");
    const startCall = supervisor.indexOf("\n  Start-Stack\n", loadCall);

    expect(supervisor).toContain("Join-Path $PSScriptRoot 'local-roots.ps1'");
    expect(supervisor).toContain(
      "Join-Path $env:LOCALAPPDATA 'Nodaris\\config\\allowed-roots.json'"
    );
    expect(supervisor).toContain("Read-NodarisLocalRoots -Path $ConfigPath");
    expect(supervisor).toContain("$env:NODARIS_ALLOWED_ROOTS = $allowedRootsValue");
    expect(supervisor).toContain("$validatedRoots -join ';'");
    expect(supervisor).not.toContain("$approvedRoot");
    expect(supervisor).not.toMatch(/C:\\Users\\Dell\\Downloads\\Nodaris/i);
    expect(integration).not.toMatch(/\$repoRoot|USERPROFILE|Downloads/i);
    expect(integration).toContain("Remove-Item Env:NODARIS_ALLOWED_ROOTS");
    expect(integration).toContain("throw 'NODARIS_ROOT_CONFIG_REJECTED'");
    expect(integration).toContain("'configuration_invalid'");
    expect(loadCall).toBeGreaterThan(supervisor.indexOf("'mutex_acquired'"));
    expect(startCall).toBeGreaterThan(loadCall);
    expect(reader).toContain("NODARIS_ROOT_CONFIG_REJECTED");
    expect(reader).toContain("AreAccessRulesProtected");
    expect(reader).toContain("ReparsePoint");
    expect(reader).toContain("candidate.Contains(';')");
    expect(reader).toContain("Test-NodarisJsonKeysUnique");
    expect(reader).toContain("schemaVersion = 1");
    expect(rootsFixture).toContain("Invoke-FixtureStartup $configPath $unexpectedReaderPath");
    expect(rootsFixture).toContain("Invoke-FixtureStartup $configPath $script:ReaderPath");
    expect(rootsFixture).toContain("if ($global:NodarisTestFakeReaderCalls -ne 1)");
    expect(rootsFixture).toContain(
      'Write-FixtureConfig $configPath (\'{"schemaVersion":1,"allowedRoots":["\' + $escapedOne + \'"]}\')'
    );
  });

  it.skipIf(process.platform !== "win32")(
    "simula a integração de raízes no PowerShell sem executar o supervisor real",
    async () => {
      const windowsDirectory = process.env["WINDIR"] ?? "C:\\Windows";
      const powershell = join(
        windowsDirectory,
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe"
      );
      const outputDirectory = await mkdtemp(join(tmpdir(), "nodaris-supervisor-roots-"));
      try {
        const output = execFileSync(
          powershell,
          [
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            fileURLToPath(supervisorRootsFixturePath),
            outputDirectory,
            fileURLToPath(supervisorPath),
            fileURLToPath(localRootsPath)
          ],
          { encoding: "utf8", timeout: 45_000 }
        );
        expect(output).toContain("supervisor-roots-fixtures=PASS");
        expect(output).toContain("valid-roots=single,multiple");
        expect(output).toContain("fail-closed=missing,invalid,unexpected-output,acl");
        expect(output).toContain("start-stack-calls=2");
        expect(output).toContain("telemetry-sanitized=PASS");
      } finally {
        await rm(outputDirectory, { recursive: true, force: true });
      }
    },
    55_000
  );

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
