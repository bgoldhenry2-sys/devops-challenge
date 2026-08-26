FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package.json .
RUN npm install --omit=dev

COPY src ./src

# Do not run as root
USER node

CMD ["node", "src/index.js"]
