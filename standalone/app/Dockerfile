# Use an official Node.js runtime as a parent image
FROM node:18-alpine

# Set the working directory in the container
WORKDIR /usr/src/app

# Arguments that can be passed during build time
ARG APP_VERSION="0.0.0"
ARG STARTUP_DELAY_SECONDS="0"

# Set environment variables from build arguments
ENV APP_VERSION=${APP_VERSION}
ENV STARTUP_DELAY_SECONDS=${STARTUP_DELAY_SECONDS}

# Bundle app source
COPY server.js .

# Expose the port the app runs on
EXPOSE 8080

# Define the command to run the app
CMD ["node", "server.js"]