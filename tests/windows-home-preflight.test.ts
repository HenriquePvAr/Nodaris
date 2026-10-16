// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { describe, expect, it } from "vitest";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  inspectWindowsHomeChecks,
  inspectWindowsHome,
  type WindowsHomeSnapshot
} from "../packages/core/src/windows-home-preflight.js";

const readySnapshot: WindowsHomeSnapshot = {
  platform: "windows",
  nodeVersion: "v22.12.0",
  pnpmVersion: "12.8.1",
  repositoryPathAbsolute: true,
  repositoryPathContainsLegacyUserPath: false,
  allowedRootExplicitlySelected: true,
  privateCredentialStoreAvailable: true,
  independentTunnelProvisioned: true,
  conflictingTask: false,
  conflictingPath: false,
  conflictingPorts: [],
  conflictingInstance: false,
  tunnelProfileAvailable: true
};

describe("preflight portátil Windows sem efeitos colaterais", () => {
  it("avalia statuses reais sanitizados sem promover incerteza a PASS", () => {
    expect(
      inspectWindowsHomeChecks([
        { name: "windows", status: "PASS", code: "WINDOWS_SUPPORTED" },
        { name: "task", status: "INCONCLUSIVE", code: "TASK_QUERY_UNAVAILABLE" },
        { name: "profile", status: "NOT_CHECKED", code: "PROFILE_NOT_INSPECTED" }
      ])
    ).toEqual({
      status: "INCONCLUSIVE",
      findings: ["TASK_QUERY_UNAVAILABLE", "PROFILE_NOT_INSPECTED"],
      effectsPerformed: false
    });
    expect(
      inspectWindowsHomeChecks([
        { name: "windows", status: "PASS", code: "WINDOWS_SUPPORTED" },
        { name: "port", status: "BLOCKED", code: "PORT_CONFLICT" }
      ]).status
    ).toBe("BLOCKED");
  });

  it("retorna pronto quando o snapshot demonstra os pré-requisitos", () => {
    expect(inspectWindowsHome(readySnapshot)).toEqual({
      status: "ready",
      findings: [],
      plannedPorts: [3333, 3334, 8080],
      effectsPerformed: false
    });
  });

  it("bloqueia versões, raiz não aprovada, caminho legado e conflitos sem revelar dados", () => {
    const result = inspectWindowsHome({
      ...readySnapshot,
      nodeVersion: "v20.0.0",
      pnpmVersion: "9.0.0",
      repositoryPathContainsLegacyUserPath: true,
      allowedRootExplicitlySelected: false,
      conflictingTask: true,
      conflictingPath: true,
      conflictingPorts: [3333],
      conflictingInstance: true,
      tunnelProfileAvailable: false
    });
    expect(result.status).toBe("blocked");
    expect(result.findings).toEqual(
      expect.arrayContaining([
        "NODE_VERSION_UNSUPPORTED",
        "PNPM_VERSION_UNSUPPORTED",
        "LEGACY_PATH_DETECTED",
        "ROOT_NOT_APPROVED",
        "TASK_CONFLICT",
        "PATH_CONFLICT",
        "PORT_CONFLICT",
        "INSTANCE_CONFLICT",
        "TUNNEL_PROFILE_UNAVAILABLE"
      ])
    );
    expect(JSON.stringify(result)).not.toContain("C:\\Users");
    expect(result.effectsPerformed).toBe(false);
  });

  it("não presume prontidão quando a observação de host é incompleta", () => {
    const result = inspectWindowsHome({
      ...readySnapshot,
      privateCredentialStoreAvailable: null,
      conflictingTask: null
    });
    expect(result.status).toBe("inconclusive");
    expect(result.findings).toContain("HOST_FACTS_INCOMPLETE");
  });

  it.skipIf(process.platform !== "win32")(
    "executa o fixture PowerShell 5.1 do coletor e planejador com facts simulados",
    () => {
      const powershell = join(
        process.env["WINDIR"] ?? "C:\\Windows",
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe"
      );
      const fixture = fileURLToPath(
        new URL("./fixtures/windows/home-preflight-smoke.ps1", import.meta.url)
      );
      const output = execFileSync(
        powershell,
        ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", fixture],
        { encoding: "utf8", timeout: 20_000, windowsHide: true }
      );
      expect(output).toContain("WINDOWS_HOME_PREFLIGHT_FIXTURE=PASS");
      const encodedReport = output
        .split(/\r?\n/)
        .find((line) => line.startsWith("WINDOWS_HOME_PREFLIGHT_REPORT_BASE64="))
        ?.slice("WINDOWS_HOME_PREFLIGHT_REPORT_BASE64=".length);
      expect(encodedReport).toBeDefined();
      const report = JSON.parse(Buffer.from(encodedReport!, "base64").toString("utf8")) as {
        overallStatus: "PASS" | "BLOCKED" | "INCONCLUSIVE";
        checks: {
          name: string;
          status: "PASS" | "BLOCKED" | "INCONCLUSIVE" | "NOT_CHECKED";
          code: string;
        }[];
      };
      expect(inspectWindowsHomeChecks(report.checks).status).toBe(report.overallStatus);
    }
  );
});
