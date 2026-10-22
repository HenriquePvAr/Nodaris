/* global process, URL */
async function main() {
  const token = String(process.env.NODARIS_PORTABLE_MCP_TOKEN || "");
  const port = Number(process.env.NODARIS_PORTABLE_MCP_PORT || "");
  if (token.length < 32 || !Number.isInteger(port) || port < 1 || port > 65535) {
    process.stderr.write("PORTABLE_MCP_CHECK=INVALID_CONFIGURATION\n");
    process.exitCode = 2;
    return;
  }

  const { Client, StreamableHTTPClientTransport } = await import("@modelcontextprotocol/client");
  const client = new Client({ name: "nodaris-portable-readiness", version: "1.0.0" });
  try {
    await client.connect(
      new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${port}/mcp`), {
        requestInit: { headers: { authorization: `Bearer ${token}` } }
      })
    );
    const result = await client.listTools();
    const expected = [
      "nodaris_code_search",
      "nodaris_file_read",
      "nodaris_git_diff",
      "nodaris_git_log",
      "nodaris_git_status",
      "nodaris_health",
      "nodaris_machines_list",
      "nodaris_project_tree",
      "nodaris_projects_list"
    ];
    const actual = Array.isArray(result.tools) ? result.tools.map((tool) => tool.name).sort() : [];
    if (
      actual.length !== expected.length ||
      actual.some((name, index) => name !== expected[index])
    ) {
      throw new Error("read_only_tool_inventory_mismatch");
    }
    process.stdout.write(`PORTABLE_MCP_CHECK=PASS TOOLS=${actual.length} READ_ONLY=VERIFIED\n`);
  } catch (error) {
    const code =
      typeof error?.code === "string" && /^[A-Z0-9_]{1,48}$/.test(error.code)
        ? error.code
        : "MCP_HANDSHAKE_FAILED";
    process.stderr.write(`PORTABLE_MCP_CHECK=FAIL CODE=${code}\n`);
    process.exitCode = 1;
  } finally {
    await client.close().catch(() => undefined);
  }
}

main().catch(() => {
  process.stderr.write("PORTABLE_MCP_CHECK=FAIL CODE=MCP_CHECK_RUNTIME_ERROR\n");
  process.exitCode = 1;
});
