# Use an official Node.js runtime as a parent image
FROM node:lts-slim

ARG BUILD_DIR="/usr/app"
ARG CONTAINER_USER="node"
ARG CONTAINER_EXPOSE_PORT="8000"

# Set the working directory
# WORKDIR /usr/src/app
WORKDIR $BUILD_DIR

# Optionally update npm to the latest version
RUN npm install -g npm

# Install npm-check-updates globally
RUN npm install -g npm-check-updates

# Remove package-lock.json and node_modules to clean the environment
RUN rm -rf package-lock.json node_modules

# Use ncu to update the package.json versions
RUN ncu -u

# Install the updated packages
RUN npm install -d

# Copy the rest of your application code
COPY . .

# Build your application if necessary
RUN npm run build

# Expose any ports your application uses
ARG APP_PORT
EXPOSE 3000 ${APP_PORT}

# Define the command to run your application
# CMD ["npm", "start"]
# Instead of starting the app, just start a shell to keep the container running
CMD ["sh", "-c", "tail -f /dev/null"]
