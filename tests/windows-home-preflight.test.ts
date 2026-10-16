// SPDX-FileCopyrightText: 2026 Henrique Paiva Araujo
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

import { describe, expect, it } from "vitest";
import {
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
});
