const http = require('http');

const APP_VERSION = process.env.APP_VERSION || "unknown";
const STARTUP_DELAY_SECONDS = parseInt(process.env.STARTUP_DELAY_SECONDS || "45", 10);
const PORT = 8080;

console.log(`[App v${APP_VERSION}] Initializing...`);
console.log(`[App v${APP_VERSION}] Configured startup delay: ${STARTUP_DELAY_SECONDS} seconds.`);

if (STARTUP_DELAY_SECONDS > 0) {
    console.log(`[App v${APP_VERSION}] Simulating boot-up time. Will start server in ${STARTUP_DELAY_SECONDS} seconds.`);
}

setTimeout(() => {
    const server = http.createServer((req, res) => {
        if (req.url === '/health' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                status: "OK",
                version: APP_VERSION,
                message: `App version ${APP_VERSION} is healthy.`
            }));
        } else if (req.url === '/' && req.method === 'GET') {
            res.writeHead(200, { 'Content-Type': 'text/plain' });
            res.end(`Hello from App Version: ${APP_VERSION}\n`);
        } else {
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('Not Found\n');
        }
    });

    server.listen(PORT, () => {
        console.log(`[App v${APP_VERSION}] Server listening on port ${PORT}`);
        console.log(`[App v${APP_VERSION}] Health check available at /health`);
        console.log(`[App v${APP_VERSION}] Main endpoint available at /`);
    });

    server.on('error', (err) => {
        console.error(`[App v${APP_VERSION}] Server error:`, err);
        process.exit(1); // Exit if server can't start
    });

}, STARTUP_DELAY_SECONDS * 1000);

// Graceful shutdown (optional but good practice)
process.on('SIGTERM', () => {
    console.log(`[App v${APP_VERSION}] SIGTERM signal received. Shutting down gracefully.`);
    // Perform any cleanup here before exiting
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log(`[App v${APP_VERSION}] SIGINT signal received. Shutting down gracefully.`);
    process.exit(0);
});