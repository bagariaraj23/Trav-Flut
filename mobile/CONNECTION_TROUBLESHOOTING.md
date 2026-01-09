# Mobile App Backend Connection Troubleshooting

## Common Issues

### 1. Connection Timeout

**Problem**: App can't connect to backend (connection timeout after 30 seconds)

**Solutions**:

#### For Physical Device:
1. Ensure your device and computer are on the **same Wi-Fi network**
2. Check your computer's current IP address:
   ```bash
   ifconfig | grep "inet " | grep -v 127.0.0.1
   ```
3. Update `mobile/.env` with the correct IP:
   ```
   API_BASE_URL=http://YOUR_IP_ADDRESS:3000/api
   ```
4. Restart the Flutter app

#### For Android Emulator:
Use the special emulator IP instead:
```
API_BASE_URL=http://10.0.2.2:3000/api
```

#### For iOS Simulator:
Use localhost:
```
API_BASE_URL=http://localhost:3000/api
```

### 2. IP Address Changed

If your computer's IP address changes (common with DHCP), update both:
- `mobile/.env` - `API_BASE_URL`
- `.env` (backend) - `API_BASE_URL` and `NEXT_PUBLIC_API_BASE_URL`

### 3. Backend Not Running

Ensure the backend server is running:
```bash
npm run dev
# Should show: "Ready on http://localhost:3000"
```

### 4. Firewall Blocking

Check if your firewall is blocking port 3000:
- macOS: System Settings > Network > Firewall
- Allow incoming connections for Node.js/Next.js

### 5. Quick Fix Script

Use the provided script to auto-detect and update IP:
```bash
cd mobile/scripts
./switch_env.sh network
# Enter your IP when prompted
```

## Current Configuration

- **Backend URL**: `http://192.168.0.163:3000/api`
- **Mobile Config**: `mobile/.env`
- **Backend Config**: `.env`

## Testing Connection

Test if backend is reachable:
```bash
# From your device/emulator network
curl http://YOUR_IP:3000/api/health
```

