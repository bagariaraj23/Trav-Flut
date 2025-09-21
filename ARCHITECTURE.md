# TripThread Architecture

## Overview
TripThread uses a microservices architecture with the following components:

1. **Main Application (Next.js)**
   - Handles HTTP requests
   - Serves the API endpoints
   - Manages user sessions and authentication

2. **Background Job Scheduler (Independent Service)**
   - Runs as a separate service
   - Handles all background tasks
   - Uses Redis for job queuing and persistence
   - Manages trip status updates and other scheduled tasks

3. **Database (PostgreSQL)**
   - Shared between main app and scheduler
   - Managed through Prisma ORM

## Services

### Main Application
- Next.js application serving API endpoints and handling user requests
- Located in the root directory
- No background processing responsibilities

### Scheduler Service
- Independent Node.js service for background jobs
- Located in `/scheduler` directory
- Uses BullMQ for reliable job processing
- Handles:
  - Trip status updates
  - Scheduled tasks
  - Background processing

## Development Setup

1. Start the main application:
```bash
npm run dev
```

2. Start the scheduler service:
```bash
cd scheduler
npm install
npm run dev
```

3. Make sure Redis is running:
```bash
docker run -d -p 6379:6379 redis:alpine
```

## Production Deployment

Both services should be deployed independently:

1. **Main Application**
   - Deploy as a standard Next.js application
   - Configure environment variables

2. **Scheduler Service**
   - Deploy using the provided Dockerfile
   - Scale independently based on job load
   - Monitor using the built-in logging

3. **Requirements**
   - Redis instance
   - PostgreSQL database
   - Environment variables properly configured

## Environment Variables

Main application (.env):
```
DATABASE_URL=postgresql://...
# Other app-specific variables
```

Scheduler (.env):
```
DATABASE_URL=postgresql://...
REDIS_URL=redis://redis:6379
```