import { ENV } from '@/env';

export async function diagnoseRedisConnection(): Promise<{
  configured: boolean;
  url?: string;
  tokenLength?: number;
  connectionTest?: { success: boolean; status?: number; error?: string };
}> {
  const result: {
    configured: boolean;
    url?: string;
    tokenLength?: number;
    connectionTest?: { success: boolean; status?: number; error?: string };
  } = {
    configured: !!(ENV.REDIS_REST_URL && ENV.REDIS_REST_TOKEN),
  };

  if (ENV.REDIS_REST_URL) {
    const url = new URL(ENV.REDIS_REST_URL);
    result.url = url.hostname;
  }

  if (ENV.REDIS_REST_TOKEN) {
    result.tokenLength = ENV.REDIS_REST_TOKEN.length;
  }

  if (!ENV.REDIS_REST_URL || !ENV.REDIS_REST_TOKEN) {
    return result;
  }

  try {
    const testResponse = await fetch(`${ENV.REDIS_REST_URL}/ping`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${ENV.REDIS_REST_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify([]),
      cache: 'no-store',
    });

    result.connectionTest = {
      success: testResponse.ok,
      status: testResponse.status,
    };

    if (!testResponse.ok) {
      const text = await testResponse.text();
      result.connectionTest.error = text.substring(0, 200);
    }
  } catch (error) {
    result.connectionTest = {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }

  return result;
}

export async function testRedisCommand(): Promise<{ success: boolean; result?: any; error?: string }> {
  if (!ENV.REDIS_REST_URL || !ENV.REDIS_REST_TOKEN) {
    return { success: false, error: 'Redis credentials not configured' };
  }
  
  try {
    const response = await fetch(`${ENV.REDIS_REST_URL}/pipeline`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${ENV.REDIS_REST_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify([['ping']]),
      cache: 'no-store',
    });
    
    if (!response.ok) {
      const text = await response.text();
      return { 
        success: false, 
        error: `HTTP ${response.status}: ${text.substring(0, 200)}` 
      };
    }
    
    const json = await response.json();
    return { success: true, result: json };
  } catch (error) {
    return { 
      success: false, 
      error: error instanceof Error ? error.message : String(error) 
    };
  }
}
