#!/usr/bin/env tsx
/**
 * HTTP-based Cache Testing Script
 * 
 * Tests cache behavior via HTTP API (doesn't require env vars)
 * 
 * Usage:
 *   npx tsx scripts/test-cache-http.ts <query> [api-url]
 * 
 * Example:
 *   npx tsx scripts/test-cache-http.ts "Ranchi" "http://localhost:3000"
 */

const QUERY = process.argv[2] || 'Ranchi';
const API_URL = process.argv[3] || 'http://localhost:3000';
const ITERATIONS = 3;

interface CacheMetrics {
  redisHits: number;
  redisMisses: number;
  memoryHits: number;
  memoryMisses: number;
  totalGets: number;
  totalSets: number;
  batchOperations: number;
  errors: number;
  redisHitRate: string | number;
  memoryHitRate: string | number;
  overallHitRate: string | number;
}

async function fetchMetrics(): Promise<CacheMetrics | null> {
  try {
    const response = await fetch(`${API_URL}/api/admin/cache/metrics`);
    if (!response.ok) {
      console.error(`  Metrics API error: ${response.status} ${response.statusText}`);
      return null;
    }
    const data = await response.json();
    return data.metrics;
  } catch (error) {
    console.error(`  Error fetching metrics: ${error instanceof Error ? error.message : String(error)}`);
    return null;
  }
}

async function searchPlace(query: string, lat: number, lng: number) {
  const url = new URL(`${API_URL}/api/places/search`);
  url.searchParams.set('q', query);
  url.searchParams.set('lat', lat.toString());
  url.searchParams.set('lng', lng.toString());
  url.searchParams.set('limit', '10');

  const response = await fetch(url.toString());
  if (!response.ok) {
    throw new Error(`Search failed: ${response.status} ${response.statusText}`);
  }
  return response.json();
}

async function testCache() {
  console.log('='.repeat(60));
  console.log('HTTP CACHE TESTING SCRIPT');
  console.log('='.repeat(60));
  console.log(`API URL: ${API_URL}`);
  console.log(`Query: "${QUERY}"`);
  console.log(`Iterations: ${ITERATIONS}`);
  console.log('');

  // Check if server is running
  try {
    const healthCheck = await fetch(`${API_URL}/api/health`);
    if (!healthCheck.ok) {
      console.error(`Server is not responding correctly (${healthCheck.status})`);
      console.log(`   Make sure the server is running at ${API_URL}`);
      return;
    }
  } catch (error) {
    console.error(`Cannot connect to server at ${API_URL}`);
    console.log(`   Error: ${error instanceof Error ? error.message : String(error)}`);
    console.log(`   Make sure the server is running: npm run dev`);
    return;
  }

  const metricsBefore = await fetchMetrics();
  if (!metricsBefore) {
    console.log('Could not fetch initial metrics, continuing anyway...');
    console.log('');
  } else {
    console.log('Initial Metrics:');
    console.log(`  Redis Hits: ${metricsBefore.redisHits}`);
    console.log(`  Redis Misses: ${metricsBefore.redisMisses}`);
    console.log(`  Memory Hits: ${metricsBefore.memoryHits}`);
    console.log(`  Memory Misses: ${metricsBefore.memoryMisses}`);
    console.log(`  Overall Hit Rate: ${((metricsBefore.overallHitRate as number) * 100).toFixed(2)}%`);
    console.log('');
  }

  for (let i = 1; i <= ITERATIONS; i++) {
    console.log(`--- Iteration ${i} ---`);
    const startTime = Date.now();
    
    try {
      const response = await searchPlace(QUERY, 12.9576994, 77.7096814);
      const duration = Date.now() - startTime;
      const results = response.data || [];
      
      console.log(`  Results: ${results.length} places`);
      console.log(`  Duration: ${duration}ms`);
      
      // Fetch metrics after each iteration
      const metrics = await fetchMetrics();
      if (metrics) {
        const redisRate = typeof metrics.redisHitRate === 'string' 
          ? parseFloat(metrics.redisHitRate.replace('%', '')) 
          : metrics.redisHitRate * 100;
        const memoryRate = typeof metrics.memoryHitRate === 'string'
          ? parseFloat(metrics.memoryHitRate.replace('%', ''))
          : metrics.memoryHitRate * 100;
        const overallRate = typeof metrics.overallHitRate === 'string'
          ? parseFloat(metrics.overallHitRate.replace('%', ''))
          : metrics.overallHitRate * 100;
        console.log(`  Redis Hit Rate: ${redisRate.toFixed(2)}%`);
        console.log(`  Memory Hit Rate: ${memoryRate.toFixed(2)}%`);
        console.log(`  Overall Hit Rate: ${overallRate.toFixed(2)}%`);
      }
      
      if (i === 1) {
        console.log(`  Expected: Low hit rate (cold start)`);
      } else {
        const expectedHitRate = i === 2 ? '30-50%' : '50-70%';
        console.log(`  Expected: Higher hit rate (${expectedHitRate})`);
      }
      
      console.log('');
    } catch (error) {
      console.error(`  Error: ${error instanceof Error ? error.message : String(error)}`);
      console.log('');
    }
  }

  const metricsAfter = await fetchMetrics();
  if (metricsAfter && metricsBefore) {
    console.log('Final Metrics:');
    console.log(`  Redis Hits: ${metricsAfter.redisHits} (+${metricsAfter.redisHits - metricsBefore.redisHits})`);
    console.log(`  Redis Misses: ${metricsAfter.redisMisses} (+${metricsAfter.redisMisses - metricsBefore.redisMisses})`);
    console.log(`  Memory Hits: ${metricsAfter.memoryHits} (+${metricsAfter.memoryHits - metricsBefore.memoryHits})`);
    console.log(`  Memory Misses: ${metricsAfter.memoryMisses} (+${metricsAfter.memoryMisses - metricsBefore.memoryMisses})`);
    const overallRate = typeof metricsAfter.overallHitRate === 'string'
      ? parseFloat(metricsAfter.overallHitRate.replace('%', ''))
      : metricsAfter.overallHitRate * 100;
    console.log(`  Overall Hit Rate: ${overallRate.toFixed(2)}%`);
    console.log('');

    const redisOps = metricsAfter.redisHits + metricsAfter.redisMisses;
    const memoryOps = metricsAfter.memoryHits + metricsAfter.memoryMisses;
    const totalOps = metricsAfter.totalGets;
    
    console.log('Analysis:');
    console.log(`  Total Operations: ${totalOps}`);
    if (totalOps > 0) {
      console.log(`  Redis Operations: ${redisOps} (${((redisOps / totalOps) * 100).toFixed(1)}%)`);
      console.log(`  Memory Operations: ${memoryOps} (${((memoryOps / totalOps) * 100).toFixed(1)}%)`);
      console.log(`  Cache Efficiency: ${((metricsAfter.memoryHits + metricsAfter.redisHits) / totalOps * 100).toFixed(2)}%`);
    }
    console.log('');

    const finalOverallRate = typeof metricsAfter.overallHitRate === 'string'
      ? parseFloat(metricsAfter.overallHitRate.replace('%', '')) / 100
      : metricsAfter.overallHitRate;
    
    if (finalOverallRate > 0.3) {
      console.log('Cache is working well! Hit rate is above 30%');
    } else if (finalOverallRate > 0.1) {
      console.log('Cache is working but hit rate is low. Consider cache warming.');
    } else {
      console.log('Cache hit rate is very low. Check cache implementation.');
    }
  }
  
  console.log('='.repeat(60));
}

// Run the test
testCache().catch(console.error);

