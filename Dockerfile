FROM node:24-alpine

WORKDIR /workspace

# Install root dependencies (PM2)
COPY package.json ./
RUN npm install

# Copy package.json files for each project
COPY drive-osx-ui/package.json ./drive-osx-ui/
COPY drive-osx-api/package.json ./drive-osx-api/
COPY drive-osx-mail/package.json ./drive-osx-mail/

# Install project dependencies
WORKDIR /workspace/drive-osx-ui
RUN npm install

WORKDIR /workspace/drive-osx-api
RUN npm install

WORKDIR /workspace/drive-osx-mail
RUN npm install

# Copy the application source
WORKDIR /workspace

COPY drive-osx-ui ./drive-osx-ui
COPY drive-osx-api ./drive-osx-api
COPY drive-osx-mail ./drive-osx-mail

COPY ecosystem.config.js .

EXPOSE 3000 3001 1025

CMD ["npm", "start"]