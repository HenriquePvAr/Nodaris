import { z } from "zod";

const schema = z.object({
  NODARIS_TOKEN: z
    .string()
    .min(32, "Defina NODARIS_TOKEN com pelo menos 32 caracteres aleatórios."),
  NODARIS_ALLOWED_ROOTS: z.string().default(""),
  NODARIS_MACHINE_ID: z.string().min(1).default("local"),
  GATEWAY_HOST: z.string().default("127.0.0.1"),
  GATEWAY_PORT: z.coerce.number().int().min(1).max(65535).default(3333),
  AGENT_HOST: z.string().default("127.0.0.1"),
  AGENT_PORT: z.coerce.number().int().min(1).max(65535).default(3334)
});

export function loadConfig(env: NodeJS.ProcessEnv = process.env) {
  const parsed = schema.parse(env);
  return {
    token: parsed.NODARIS_TOKEN,
    roots: parsed.NODARIS_ALLOWED_ROOTS.split(";")
      .map((root) => root.trim())
      .filter(Boolean),
    machineId: parsed.NODARIS_MACHINE_ID,
    gatewayHost: parsed.GATEWAY_HOST,
    gatewayPort: parsed.GATEWAY_PORT,
    agentHost: parsed.AGENT_HOST,
    agentPort: parsed.AGENT_PORT
  };
}
