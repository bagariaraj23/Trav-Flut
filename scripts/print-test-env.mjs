#!/usr/bin/env node
import dotenv from 'dotenv';
import path from 'path';

const envPath = path.resolve(process.cwd(), '.env.test');
if (process.env.DEBUG) console.log('Loading', envPath);
dotenv.config({ path: envPath });

function maskDb(u) {
    if (!u) return '(unset)';
    return u.replace(/:(?:[^@]+)@/, ':****@');
}

console.log('TEST_DATABASE_URL=' + maskDb(process.env.TEST_DATABASE_URL));
console.log('DATABASE_URL=' + maskDb(process.env.DATABASE_URL));
console.log('NODE_ENV=' + (process.env.NODE_ENV || '(unset)'));
console.log('JWT_SECRET=' + (process.env.JWT_SECRET ? '****' : '(unset)'));
console.log('MAPBOX_ACCESS_TOKEN=' + (process.env.MAPBOX_ACCESS_TOKEN ? '****' : '(unset)'));
