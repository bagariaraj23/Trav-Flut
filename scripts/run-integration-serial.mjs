#!/usr/bin/env node
// Run each integration test file serially using vitest to avoid cross-file parallelism
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';

const testsDir = path.resolve(process.cwd(), 'tests', 'integration');
if (!fs.existsSync(testsDir)) {
    console.error('Integration tests directory not found:', testsDir);
    process.exit(1);
}

const files = fs.readdirSync(testsDir).filter((f) => f.endsWith('.test.ts') || f.endsWith('.test.tsx') || f.endsWith('.test.js') &&
    !f.includes('api'));
if (files.length === 0) {
    console.log('No integration test files found.');
    process.exit(0);
}

let failed = false;
for (const file of files) {
    const filePath = path.join('tests', 'integration', file);
    console.log('\n=== Running integration file:', filePath, '===');
    try {
        // Load `.env.test` for each run so the test processes use the test DB envs
        execSync(`npx dotenv -e .env.test -- vitest run ${filePath} --reporter=dot`, { stdio: 'inherit' });
    } catch (err) {
        console.error('\n=== File failed:', filePath, '===');
        failed = true;
        // continue to run remaining files to collect more failures
    }
}

if (failed) {
    console.error('\nSome integration tests failed. See output above.');
    process.exit(2);
}

console.log('\nAll integration test files completed successfully.');
process.exit(0);
