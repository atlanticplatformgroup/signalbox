export function objectValue(value: unknown, name: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${name} must be an object`);
  }
  return value as Record<string, unknown>;
}

export function arrayValue(value: unknown, name: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(`${name} must be an array`);
  return value;
}

export function stringValue(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${name} must be a non-empty string`);
  }
  return value;
}

export function optionalString(value: unknown, name: string): string | undefined {
  return value === undefined || value === null ? undefined : stringValue(value, name);
}

export function booleanValue(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") throw new Error(`${name} must be a boolean`);
  return value;
}

export function integerValue(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new Error(`${name} must be a safe integer`);
  }
  return value;
}

export function jsonValue(text: string, name: string): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch (error) {
    throw new Error(`${name} must be valid JSON`, { cause: error });
  }
}

export function assertKeys(value: Record<string, unknown>, allowed: readonly string[], name: string): void {
  const allowedKeys = new Set(allowed);
  const unexpected = Object.keys(value).filter((key) => !allowedKeys.has(key));
  if (unexpected.length > 0) throw new Error(`${name} has unexpected keys: ${unexpected.join(", ")}`);
}
