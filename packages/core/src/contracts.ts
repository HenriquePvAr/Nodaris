import { z } from "zod";

export const projectIdSchema = z.string().min(1).max(128);
export const relativePathSchema = z
  .string()
  .max(1024)
  .refine((value) => !value.includes("\0"), "Caminho inválido");
export const projectSchema = z.object({
  id: projectIdSchema,
  machineId: z.string(),
  name: z.string(),
  path: z.string(),
  kind: z.string(),
  languages: z.array(z.string())
});
export type Project = z.infer<typeof projectSchema>;

export const rpcRequestSchema = z.discriminatedUnion("operation", [
  z.object({ operation: z.literal("health") }),
  z.object({ operation: z.literal("machines.list") }),
  z.object({ operation: z.literal("projects.list") }),
  z.object({
    operation: z.literal("project.tree"),
    projectId: projectIdSchema,
    path: relativePathSchema.optional(),
    depth: z.number().int().min(0).max(8).default(4)
  }),
  z.object({
    operation: z.literal("code.search"),
    projectId: projectIdSchema,
    query: z.string().min(1).max(200),
    maxResults: z.number().int().min(1).max(100).default(30)
  }),
  z.object({
    operation: z.literal("file.read"),
    projectId: projectIdSchema,
    path: relativePathSchema
  }),
  z.object({ operation: z.literal("git.status"), projectId: projectIdSchema }),
  z.object({ operation: z.literal("git.diff"), projectId: projectIdSchema }),
  z.object({
    operation: z.literal("git.log"),
    projectId: projectIdSchema,
    limit: z.number().int().min(1).max(50).default(10)
  })
]);
export type RpcRequest = z.infer<typeof rpcRequestSchema>;
