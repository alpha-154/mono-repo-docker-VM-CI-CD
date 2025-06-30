Guide: Docker & CI/CD for a Monorepo Project
This document provides a complete, step-by-step guide for containerizing a monorepo application using Docker and Docker Compose for local development, and then setting up a CI/CD pipeline with GitHub Actions to automatically deploy it to an AWS EC2 instance.

Part 1: Local Development with Docker
The goal here is to create a consistent, isolated, and easy-to-run development environment for all services in your monorepo.

Step 1: Writing the Dockerfiles
A Dockerfile is a blueprint for building a container image. In a monorepo, the Dockerfiles for each service will look very similar. We'll create one for each service (backend, frontend, ws) inside a dedicated docker/ directory.

Key Concepts of the Dockerfile:

FROM oven/bun:1: We start with an official base image that already has Bun pre-installed.

WORKDIR /usr/src/app: Sets the working directory inside the container. All subsequent commands run from this path.

COPY ./packages ./packages: Copies the shared packages directory into the container.

COPY ./bun.lockb ./package.json ./turbo.json ./: Copies the essential dependency management files to the container's root.

COPY ./apps/backend ./apps/backend: Copies the source code for a specific application. This line is what you'll change for each service's Dockerfile.

RUN bun install: Installs all dependencies for the entire monorepo based on the copied files.

RUN bun run db:generate: Generates the Prisma client. It's good practice to do this at build time.

EXPOSE 8080: Informs Docker that the container listens on this port at runtime. It's for documentation purposes.

CMD ["bun", "run", "start:backend"]: The default command to run when the container starts. This executes a script from your package.json.

Template: docker/Dockerfile.backend
(You would create similar files for frontend and ws, changing the COPY and CMD lines accordingly)

# Filename: docker/Dockerfile.backend

# Use the official Bun image as a base
FROM oven/bun:1

# Set the working directory inside the container
WORKDIR /usr/src/app

# Copy shared packages and dependency files first to leverage Docker's layer caching
COPY ./packages ./packages
COPY ./bun.lockb ./bun.lockb
COPY ./package.json ./package.json
COPY ./turbo.json ./turbo.json

# Copy the specific application code
COPY ./apps/backend ./apps/backend

# Install all monorepo dependencies
RUN bun install

# Generate the Prisma client
RUN bun run db:generate

# Expose the port the backend server will run on
EXPOSE 8080

# The command to start the backend service
CMD ["bun", "run", "start:backend"]

Step 2: Writing the Local docker-compose.yaml
Docker Compose is a tool for defining and running multi-container Docker applications. This file orchestrates all your services, including the database.

Key Concepts of the docker-compose.yaml:

services: The main section where each container is defined.

db service: Sets up a PostgreSQL database container. The healthcheck is crucial as it ensures other services don't start until the database is truly ready to accept connections.

prisma-migrate service: A special, short-lived container whose only job is to run prisma db push (or migrate dev). It depends on the db being healthy and other services depend on it finishing, which prevents your apps from crashing because the database tables don't exist.

Application services (backend, frontend, ws):

build: Tells Compose to build the image from a Dockerfile instead of pulling it from a registry.

ports: Maps your local machine's ports to the container's ports (e.g., 3000:3000).

depends_on: Controls startup order.

develop.watch: Enables hot-reloading. When you save a file locally, this syncs it into the container, and if you're running your app with a watch flag (e.g., bun --watch), the process will restart automatically.

Complete docker-compose.yaml for Local Development:

# Filename: docker-compose.yaml
version: "3.8"

services:
  db:
    image: postgres:15
    container_name: postgres_db
    restart: always
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: mydb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5

  prisma-migrate:
    build:
      context: .
      dockerfile: docker/Dockerfile.backend
    command: sh -c "bun run db:push"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/mydb
    depends_on:
      db:
        condition: service_healthy

  backend:
    build:
      context: .
      dockerfile: docker/Dockerfile.backend
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/mydb
    depends_on:
      - prisma-migrate
    develop:
      watch:
        - action: sync
          path: ./apps/backend
          target: /usr/src/app/apps/backend

  frontend:
    build:
      context: .
      dockerfile: docker/Dockerfile.frontend
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/mydb
    depends_on:
      - prisma-migrate
    develop:
      watch:
        - action: sync
          path: ./apps/web
          target: /usr/src/app/apps/web

  ws:
    build:
      context: .
      dockerfile: docker/Dockerfile.ws
    ports:
      - "8081:8081"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/mydb
    depends_on:
      - prisma-migrate
    develop:
      watch:
        - action: sync
          path: ./apps/ws
          target: /usr/src/app/apps/ws

volumes:
  postgres_data:

With these files in place, you can run docker-compose up --build from your project root to start your entire development environment.

Part 2: Deploying to EC2 with a CI/CD Pipeline
This section covers automating the deployment process. When you push code to GitHub, it will automatically build new images and update the running application on your EC2 server.

Step 1: One-Time Environment Setup
You must prepare your server and external services before creating the pipeline.

Configure EC2 Instance:

Connect to your EC2 instance via SSH.

Install Docker and Docker Compose:

# Update package lists
sudo apt-get update

# Install Docker
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# IMPORTANT: Add your user to the docker group to run docker without sudo
sudo usermod -aG docker $USER
newgrp docker # Apply new group membership for the current session

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

Clone your repository onto the server. This is only needed once.

git clone https://github.com/your-username/your-repo.git

Configure EC2 Security Group: In your AWS console, ensure the Security Group for your EC2 instance allows inbound traffic on these ports:

22 (SSH): For the CI/CD pipeline to connect.

80 (HTTP) & 443 (HTTPS): For web traffic.

3000, 8080, 8081: The ports your applications are exposed on.

Set Up a Container Registry (Docker Hub):

Go to Docker Hub and create an account.

Create a new public repository for each of your services (e.g., your-username/mono-repo-backend).

Configure GitHub Secrets: In your GitHub repository, go to Settings > Secrets and variables > Actions and add the following secrets. Never hardcode these values.

DOCKERHUB_USERNAME: Your Docker Hub username.

DOCKERHUB_TOKEN: A Docker Hub Access Token (create this in Docker Hub > Account Settings > Security).

EC2_HOST: The public IP address of your EC2 instance.

EC2_USERNAME: The username for connecting to your EC2 instance (e.g., ubuntu).

EC2_SSH_PRIVATE_KEY: The private SSH key (.pem file content) used to connect to your EC2 instance.

Step 2: Create a Production Docker Compose File
This file is similar to the local one but uses pre-built images from your registry instead of building them on the server.

Create docker-compose.prod.yml in your repository root:

# Filename: docker-compose.prod.yml
version: "3.8"

services:
  db:
    image: postgres:15
    container_name: postgres_db
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data

  backend:
    image: ${DOCKER_IMAGE_BACKEND} # This is a variable we will set in the pipeline
    restart: always
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
    depends_on:
      - db

  frontend:
    image: ${DOCKER_IMAGE_FRONTEND}
    restart: always
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
      - NEXT_PUBLIC_API_URL=http://${EC2_HOST}:8080 
      - NEXT_PUBLIC_WS_URL=ws://${EC2_HOST}:8081
    depends_on:
      - db

  ws:
    image: ${DOCKER_IMAGE_WS}
    restart: always
    ports:
      - "8081:8081"
    environment:
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}
    depends_on:
      - db

volumes:
  postgres_data:

On your EC2 server, create a .env file inside the cloned repository directory to hold your database credentials. This keeps them out of version control.

# On EC2, inside /home/ubuntu/your-repo/.env
POSTGRES_USER=postgres
POSTGRES_PASSWORD=a-very-secure-password
POSTGRES_DB=mydb
EC2_HOST=your-ec2-public-ip

Step 3: Write the GitHub Actions CI/CD Workflow
This is the heart of your automation. Create the file .github/workflows/deploy.yml.

Key Concepts of the Workflow:

on: push: branches: [main]: The workflow triggers on every push to the main branch.

jobs: The workflow is split into two jobs: build-and-push and deploy.

needs: build-and-push: The deploy job will only start if the build-and-push job succeeds.

docker/build-push-action: This action logs into Docker Hub, builds your images, and pushes them to the registry. We tag images with both latest and the unique Git commit hash (github.sha) for precise versioning.

appleboy/ssh-action: This action securely connects to your EC2 instance and runs a deployment script.

Deployment Script: The script run on the EC2 server pulls the latest code, sets environment variables with the new image tags, runs the database migration, and finally restarts the services using docker-compose up. The --no-build flag is critical here, as it tells Compose to pull the images we just pushed to Docker Hub.

Complete .github/workflows/deploy.yml:

# Filename: .github/workflows/deploy.yml
name: Build and Deploy to EC2

on:
  push:
    branches:
      - main

env:
  DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
  BACKEND_IMAGE_NAME: mono-repo-backend
  FRONTEND_IMAGE_NAME: mono-repo-frontend
  WS_IMAGE_NAME: mono-repo-ws
  EC2_REPO_PATH: /home/${{ secrets.EC2_USERNAME }}/mono-repo-docker-VM-CI-CD # CHANGE THIS to your repo name

jobs:
  build-and-push:
    name: Build and Push Docker Images
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push backend image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./docker/Dockerfile.backend
          push: true
          tags: ${{ env.DOCKERHUB_USERNAME }}/${{ env.BACKEND_IMAGE_NAME }}:latest,${{ env.DOCKERHUB_USERNAME }}/${{ env.BACKEND_IMAGE_NAME }}:${{ github.sha }}

      # Repeat the build-push-action for frontend and ws services...
      - name: Build and push frontend image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./docker/Dockerfile.frontend
          push: true
          tags: ${{ env.DOCKERHUB_USERNAME }}/${{ env.FRONTEND_IMAGE_NAME }}:latest,${{ env.DOCKERHUB_USERNAME }}/${{ env.FRONTEND_IMAGE_NAME }}:${{ github.sha }}

      - name: Build and push ws image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./docker/Dockerfile.ws
          push: true
          tags: ${{ env.DOCKERHUB_USERNAME }}/${{ env.WS_IMAGE_NAME }}:latest,${{ env.DOCKERHUB_USERNAME }}/${{ env.WS_IMAGE_NAME }}:${{ github.sha }}
  
  deploy:
    name: Deploy to EC2
    runs-on: ubuntu-latest
    needs: build-and-push
    steps:
      - name: Deploy to EC2 instance
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USERNAME }}
          key: ${{ secrets.EC2_SSH_PRIVATE_KEY }}
          script: |
            cd ${{ env.EC2_REPO_PATH }}
            git pull origin main
            
            export DOCKER_IMAGE_BACKEND=${{ env.DOCKERHUB_USERNAME }}/${{ env.BACKEND_IMAGE_NAME }}:${{ github.sha }}
            export DOCKER_IMAGE_FRONTEND=${{ env.DOCKERHUB_USERNAME }}/${{ env.FRONTEND_IMAGE_NAME }}:${{ github.sha }}
            export DOCKER_IMAGE_WS=${{ env.DOCKERHUB_USERNAME }}/${{ env.WS_IMAGE_NAME }}:${{ github.sha }}
            
            docker-compose -f docker-compose.prod.yml run --rm backend bun run db:push
            
            docker-compose -f docker-compose.prod.yml up -d --no-build

Once you commit these files, any new push to your main branch will trigger this pipeline, resulting in a fully automated deployment to your server.