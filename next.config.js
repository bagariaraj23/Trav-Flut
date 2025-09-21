/** @type {import('next').NextConfig} */
require('dotenv').config();

const nextConfig = {
  env: {
    ENABLE_SCHEDULER: process.env.ENABLE_SCHEDULER
  },
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'storage.googleapis.com',
        port: '',
        pathname: '/u/**'
      }
    ]
  }
}

module.exports = nextConfig
