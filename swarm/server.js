// server.js
const express = require('express');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Initialize Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Middleware for logging
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${req.method} ${req.url} from ${req.ip}`);
  next();
});

// Get container ID - Try different methods as fallbacks
function getContainerId() {
  try {
    // First try to read from cgroup (most reliable in Docker)
    const cgroupContent = fs.readFileSync('/proc/self/cgroup', 'utf8');
    const containerIdMatch = cgroupContent.match(/[0-9a-f]{64}/);
    if (containerIdMatch) {
      return containerIdMatch[0].substring(0, 12); // Short form of container ID
    }
  } catch (err) {
    // Silently fail and try next method
  }

  try {
    // Try to get hostname which is often the container ID in Docker
    return os.hostname();
  } catch (err) {
    // Final fallback
    return 'unknown-container';
  }
}

// Read package.json for version
function getAppVersion() {
  try {
    const packageJson = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8'));
    return packageJson.version;
  } catch (err) {
    console.error('Error reading package.json:', err);
    return 'unknown';
  }
}

const APP_START_TIME = Date.now();
const STARTUP_GRACE_PERIOD_MS = 60000; // 60 seconds

// Status endpoint
app.get('/status', (req, res) => {
  const statusInfo = {
    version: getAppVersion(),
    container: getContainerId(),
    uptime: `${Math.round((Date.now() - APP_START_TIME) / 1000)}s`,
    timestamp: new Date().toISOString()
  };

  res.json(statusInfo);
});



// Health check endpoint
app.get('/health', (req, res) => {
  // Fail health checks for the first 60 seconds after boot
  const uptime = Date.now() - APP_START_TIME;
  if (uptime < STARTUP_GRACE_PERIOD_MS) {
    console.log(`Health check failed: ${Math.round(uptime / 1000)}s uptime, waiting for ${Math.round(STARTUP_GRACE_PERIOD_MS / 1000)}s`);
    return res.status(503).json({
      status: 'initializing',
      uptime: `${Math.round(uptime / 1000)}s`,
      ready_in: `${Math.round((STARTUP_GRACE_PERIOD_MS - uptime) / 1000)}s`
    });
  }

  // After grace period, return healthy status
  res.status(200).json({ status: 'ok', uptime: `${Math.round(uptime / 1000)}s` });

});

// Readiness probe endpoint - for when the app is ready to receive traffic
app.get('/ready', (req, res) => {
  // You could add startup checks here if needed
  res.status(200).json({ status: 'ready' });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Server is running',
    endpoints: {
      status: '/status - Returns version, container ID, and timestamp',
      health: '/health - Basic health check',
      ready: '/ready - Readiness probe'
    }
  });
});

// wait for 60 seconds before starting the server
setTimeout(() => {
  console.log('Server is starting...');

  // Start the server
  const server = app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Version: ${getAppVersion()}`);
    console.log(`Container ID: ${getContainerId()}`);
  });

  // Graceful shutdown handling
  function gracefulShutdown(signal) {
    console.log(`Received ${signal}. Shutting down gracefully...`);

    server.close(() => {
      console.log('HTTP server closed.');
      process.exit(0);
    });

    // Force shutdown after timeout
    setTimeout(() => {
      console.error('Could not close connections in time, forcefully shutting down');
      process.exit(1);
    }, 10000);
  }

  // Listen for signals
  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
  process.on('SIGINT', () => gracefulShutdown('SIGINT'));
}, STARTUP_GRACE_PERIOD_MS);

