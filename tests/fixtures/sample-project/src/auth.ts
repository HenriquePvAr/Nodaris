export function isAuthenticated(token: string): boolean {
  return token.length > 0;
}
