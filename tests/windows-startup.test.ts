import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

const launcherPath = new URL("../scripts/windows/launcher.vbs", import.meta.url);
const managerPath = new URL("../scripts/windows/nodaris.ps1", import.meta.url);

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
});
