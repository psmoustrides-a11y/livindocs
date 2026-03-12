export function validateInput(data: unknown): boolean {
  if (data === null || data === undefined) return false;
  if (typeof data !== 'object') return false;
  return true;
}

export function formatResponse<T>(data: T): { data: T; timestamp: string } {
  return {
    data,
    timestamp: new Date().toISOString(),
  };
}

export interface ApiResponse<T> {
  data: T;
  timestamp: string;
}

export type UserId = string;
