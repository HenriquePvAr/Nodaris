# Connect a portable Nodaris installation to ChatGPT

This is the per-user Windows flow. It uses the operator's own OpenAI Platform organization, ChatGPT workspace, tunnel ID, and restricted runtime API key. It does not reuse another installation's identity or expose a public listener. The portable supervisor can optionally run the official `tunnel-client` alongside Agent and Gateway.

## Requirements and account-side setup

1. Configure and verify the local read-only runtime using [new-PC installation](INSTALLATION_NEW_PC.md). Agent and Gateway must pass its authenticated MCP `tools/list` check.
2. In the operator's OpenAI Platform organization, create or select a Secure MCP Tunnel and associate it with the intended ChatGPT workspace. The runtime operator needs Tunnels Read + Use. Tunnel creation/management requires Tunnels Read + Manage. These are separate account permissions; the Nodaris script does not create account resources or keys.
3. Create a runtime API key for the tunnel client. Do not use an admin API key. Keep the key ready for the local hidden prompt. If the account cannot create/use a tunnel or the ChatGPT workspace cannot add a custom MCP server, record that as an account-side blocker; do not expose the Gateway publicly.

OpenAI's current setup uses an OpenAI-hosted tunnel and an outbound `tunnel-client` connection. The private MCP server remains reachable only on the local host. Consult the [Secure MCP Tunnel guide](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [custom MCP server guide](https://developers.openai.com/api/docs/guides/custom-mcp-server), and [official releases](https://github.com/openai/tunnel-client/releases) for account/UI changes.

## Install the official client locally

Use the release link in Platform or the official OpenAI release page. Select the Windows architecture appropriate for this computer. Verify the downloaded archive's SHA-256 against the checksum published for that exact official release before extraction. Do not use a third-party mirror.

In a non-elevated PowerShell at the Nodaris clone:

```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
.\scripts\windows\nodaris-portable.ps1 tunnel-prepare-install
```

The command displays and asks for local confirmation before creating only `%LOCALAPPDATA%\Nodaris\tunnel-client` with a private owner/SYSTEM ACL. Extract the verified archive into that directory. Do not run the client from Downloads or a shared directory. Locate `tunnel-client.exe` under the protected install directory and inspect its built-in help/version:

```powershell
$client = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Nodaris\tunnel-client') -Filter tunnel-client.exe -File -Recurse | Select-Object -First 1
if (-not $client) { throw 'tunnel-client.exe not found in the private install directory' }
& $client.FullName --version
& $client.FullName help quickstart
```

The configuration command also records the executable SHA-256 and rechecks it before use. This pins the local file after setup; it does not replace the operator's initial official-release checksum verification.

## Configure the local tunnel profile

Run the following in the same clone. The command asks for the executable path if needed, the tunnel ID, and then reads the runtime API key through a hidden `SecureString` prompt. It rejects a client outside the protected install directory. It creates a private, fixed-scope profile for `http://127.0.0.1:3333/mcp`, a loopback health listener on `127.0.0.1:3335`, and stores the API key using Windows DPAPI `CurrentUser`. The profile contains environment-variable references, never the key itself. No tunnel is started and the tunnel remains disabled at this point.

```powershell
.\scripts\windows\nodaris-portable.ps1 tunnel-configure -TunnelExecutable $client.FullName -TunnelId (Read-Host 'Tunnel ID from your own Platform organization')
```

The command runs `tunnel-client doctor` using the generated profile and the protected local credentials, without printing its output or starting the poll loop. Then review and approve the separate opt-in:

```powershell
.\scripts\windows\nodaris-portable.ps1 doctor
.\scripts\windows\nodaris-portable.ps1 tunnel-enable
```

`tunnel-enable` requires the exact local confirmation `ENABLE NODARIS TUNNEL`. Agent/Gateway writes remain off. `tunnel-disable` requires its own confirmation and affects the next runtime start. To stop a currently running session, separately approve `stop`; it stops only the processes recorded by the portable supervisor after identity checks.

## Start and verify the combined runtime

```powershell
.\scripts\windows\nodaris-portable.ps1 start
```

The start confirmation states whether the tunnel will run. The supervisor acquires a per-user mutex, refuses occupied ports, starts Agent/Gateway, verifies authenticated Agent health and MCP initialize/`tools/list`, then starts the tunnel client with the profile path and protected credentials in its child environment. It checks that the tunnel process owns port 3335 and that its local `/healthz` and `/readyz` return successfully. It never logs or places API keys in process arguments. If a child exits or readiness fails, the supervisor stops only its identity-verified processes. The optional per-user Task Scheduler task runs the same supervisor and therefore remains the single autostart entry for Agent, Gateway, and the tunnel.

The local health/readiness checks do not prove active control-plane polling or a successful ChatGPT call. While the client is running, check its local status/UI and run `& $client.FullName doctor --config (Join-Path $env:LOCALAPPDATA 'Nodaris\portable\tunnel-client.yaml') --explain`; avoid copying diagnostic exports into chat because they may include private metadata. In ChatGPT, add a custom MCP server and choose the tunnel created for this computer/workspace. Confirm tool discovery, then call `nodaris_health`, `nodaris_projects_list`, and `nodaris_file_read` on a harmless file within a selected root. The installation is externally validated only after those calls succeed in that ChatGPT workspace.

## Rollback and security

- To stop the complete local runtime, run `nodaris-portable.ps1 stop` and type `STOP NODARIS READ RUNTIME`. It signals only the owned supervisor, which stops its verified child processes.
- To disable future tunnel startup, run `tunnel-disable` and type `DISABLE NODARIS TUNNEL`; separately stop the active runtime if one is running. The private profile and DPAPI key remain for review and later reuse.
- To disable autostart, use `task-disable` with its separate local confirmation. The task is per-user, limited, `IgnoreNew`, and starts disabled when first installed.
- To revoke remote access, remove/disconnect the custom MCP server in ChatGPT and revoke the runtime key/tunnel in the operator's Platform account. Local process stop alone does not revoke the account-side tunnel.
- Do not open inbound firewall ports, disable Gateway Bearer authentication, put keys in YAML, arguments, PowerShell history, source control, screenshots, or logs, or reuse another installation's machine or tunnel identifiers.

Memory V1 is not enabled by tunnel setup. Memory Read, Memory Write, and Project Write remain disabled in the portable runtime; each future capability requires a separate per-install implementation and local authorization. A healthy tunnel proves transport readiness only, not Registry access, MCP tool success, or Memory V1 availability.
