# Chimera Coffee - Development Environment Setup

This directory contains scripts for setting up and managing the local development environment for the Chimera Coffee project.

## Overview

The Chimera Coffee system consists of three components:

1. **Backend** (`../ChimeraCoffee/`) - Java Spring Boot API server
2. **Management Frontend** (`../chimera-management/`) - Vue 3 admin dashboard
3. **WeChat Miniapp** (`../chimeracoffeeweb-master/`) - WeChat miniapp for customers

These scripts help you run the **Backend + Management Frontend** for local development.

> ⚠️ **Security Notice**: This setup is intended for **local development only**. Default credentials (admin/admin123, chimera/chimera) and configuration are insecure and should never be used in production. See [Security Considerations](#security-considerations) for details.

---

## Prerequisites

### Required Software

All of these should be installed and available in your PATH:

| Software | Version | Purpose | Download/Install |
|----------|---------|---------|------------------|
| **Java** | 17+ | Backend runtime | `apt install openjdk-17-jdk` or [Oracle JDK](https://www.oracle.com/java/technologies/downloads/) |
| **Maven** | 3.8+ | Build backend | `apt install maven` or [Maven](https://maven.apache.org/download.cgi) |
| **MongoDB** | 6.0+ | Database | [MongoDB Community](https://www.mongodb.com/try/download/community) |
| **Node.js** | 18+ | Frontend runtime | [Node.js](https://nodejs.org/) |
| **npm** | 9+ | Package management | Comes with Node.js |

### MongoDB Requirements

You need both `mongod` (server) and `mongosh` (shell) commands available:

```bash
# Verify installation
mongod --version
mongosh --version
```

### Verify Prerequisites

Run the info script to check your environment:

```bash
./dev-info.sh
```

This will display:
- Installed software versions
- Git branch/status for all three repos
- MongoDB connection status
- Backend build status
- Frontend dependencies status

---

## Quick Start

### 1. Clone All Repositories (if not already)

```bash
# Main directory structure:
# /your-workspace/
#   ├── ChimeraCoffee/          # Backend (this repo)
#   ├── chimera-management/     # Frontend (separate repo)
#   └── chimeracoffeeweb-master/ # Miniapp (separate repo)

# Clone backend (contains these scripts)
git clone <backend-repo-url> ChimeraCoffee

# Clone frontend
git clone <frontend-repo-url> chimera-management

# Clone miniapp (optional for backend/frontend dev)
git clone <miniapp-repo-url> chimeracoffeeweb-master

# Copy/link scripts to parent directory (optional)
mkdir -p ../test
cp -r ChimeraCoffee/dev-scripts/* ../test/
```

### 2. Start Everything

```bash
cd test  # or wherever you placed the scripts

# Start backend + frontend
./dev-start.sh
```

### 3. Access the Application

Once started, access the services at:

| Service | URL | Credentials |
|---------|-----|-------------|
| Management Frontend | http://localhost:5173/shop/ | admin / admin123 |
| Backend API | http://localhost:8088 | - |
| API Documentation | http://localhost:8088/swagger-ui.html | - |

### 4. Stop Everything

```bash
./dev-stop.sh
```

---

## Scripts Reference

### `dev-info.sh`
Display development environment information.

```bash
./dev-info.sh
```

Shows:
- Prerequisites status (Java, Maven, MongoDB, Node.js, npm)
- Git branch and status for all three repos
- MongoDB running status
- Backend build status
- Frontend dependencies status

### `dev-start.sh`
Start the development environment.

```bash
# Start backend + frontend (default)
./dev-start.sh

# Start only backend
./dev-start.sh --backend-only

# Start only frontend (assumes backend is already running)
./dev-start.sh --frontend-only

# Skip Maven build (use existing JAR)
./dev-start.sh --skip-build

# Skip database initialization
./dev-start.sh --skip-db-init

# Reset MongoDB data (fresh database)
./dev-start.sh --reset-db

# Combine options
./dev-start.sh --backend-only --reset-db
```

**What it does:**
1. Shows current git branch info for backend/frontend repos
2. Starts MongoDB (if not running) or connects to existing one
3. Builds the backend JAR (unless `--skip-build`)
4. Initializes database with seed data (admin user, sample products)
5. Starts backend server
6. Configures frontend to use local backend API
7. Starts frontend dev server

### `dev-stop.sh`
Stop the development environment.

```bash
# Stop backend and MongoDB (default)
./dev-stop.sh

# Stop only backend, keep MongoDB running
./dev-stop.sh --soft

# Stop everything and remove MongoDB data
./dev-stop.sh --clean
```

### `dev-init-db.sh`
Initialize database with seed data. Usually called automatically by `dev-start.sh`.

```bash
# Run standalone (ensure MongoDB is running first)
./dev-init-db.sh
```

---

## Configuration

### Environment Variables

You can customize the setup using environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_PORT` | 8088 | Backend server port |
| `FRONTEND_PORT` | 5173 | Frontend dev server port |
| `MONGO_HOST` | 127.0.0.1 | MongoDB host |
| `MONGO_PORT` | 27017 | MongoDB port |
| `MONGO_DATABASE` | chimera_local | Database name |
| `MONGO_USERNAME` | chimera | MongoDB username |
| `MONGO_PASSWORD` | chimera | MongoDB password |
| `ADMIN_USERNAME` | admin | Admin login username |
| `ADMIN_PASSWORD` | admin123 | Admin login password |

> ⚠️ **Security Warning**: The default credentials above are for **local development only**. Never use these defaults in production. Always change passwords before deploying.

Example:
```bash
SERVER_PORT=9090 FRONTEND_PORT=3000 ./dev-start.sh
```

### Using External MongoDB

If you have your own MongoDB instance running:

```bash
export MONGO_HOST=your.mongodb.host
export MONGO_PORT=27017
export MONGO_DATABASE=your_db
export MONGO_USERNAME=your_user
export MONGO_PASSWORD=your_pass

./dev-start.sh
```

The script will detect that MongoDB is already running and skip starting a local instance.

---

## Project Structure

```
/workspace/
├── ChimeraCoffee/              # Backend (Spring Boot)
│   ├── src/
│   ├── target/                 # Build output
│   ├── .local-mongo/          # Local MongoDB data (auto-created)
│   ├── .local-static/         # Uploaded files storage
│   ├── .m2/                   # Local Maven repository
│   └── log/                   # Log files
│
├── chimera-management/         # Frontend (Vue 3)
│   ├── src/
│   ├── dist/                  # Build output
│   ├── node_modules/          # Dependencies
│   └── .env.local             # Auto-generated dev config
│
├── chimeracoffeeweb-master/    # WeChat Miniapp (optional)
│   └── miniprogram/
│
└── test/                       # These scripts
    ├── dev-info.sh
    ├── dev-start.sh
    ├── dev-stop.sh
    ├── dev-init-db.sh
    └── README.md
```

---

## Seed Data

The database is initialized with minimal test data:

### Admin User
- **Username**: `admin`
- **Password**: `admin123`
- **Role**: `ADMIN`

### Inventory
| Name | Type | Unit | Initial Stock |
|------|------|------|---------------|
| Coffee Beans | raw | g | 10,000 |
| Milk | raw | ml | 5,000 |
| Sugar | raw | g | 2,000 |

### Products
| Name | Price | Student Price | Description |
|------|-------|---------------|-------------|
| Latte | ¥24.00 | ¥22.00 | Classic espresso with steamed milk |
| Americano | ¥18.00 | ¥16.00 | Espresso with hot water |

### Product Options
- **Size**: Small, Large (+¥2.00)
- **Temperature**: Hot, Iced

---

## Troubleshooting

### Port Already in Use

```bash
# Check what's using port 8088
lsof -i :8088

# Use different ports
SERVER_PORT=9090 FRONTEND_PORT=3000 ./dev-start.sh
```

### MongoDB Connection Failed

```bash
# Check if MongoDB is running
mongosh --eval "db.runCommand({ ping: 1 })"

# Reset MongoDB data
./dev-start.sh --reset-db
```

### Frontend Shows Connection Error

Make sure backend is running:
```bash
curl http://localhost:8088/swagger-ui.html
```

Or restart both:
```bash
./dev-stop.sh
./dev-start.sh
```

### Build Fails

Try clean build:
```bash
cd ../ChimeraCoffee
mvn clean
./test/dev-start.sh
```

---

## Git Branch Information

The scripts will display the current branch for each repository but **will NOT auto-checkout** any branches. You are responsible for being on the correct branch for your work.

To see current branches:
```bash
./dev-info.sh
```

---

## Miniapp Development

The WeChat miniapp (`chimeracoffeeweb-master/`) is **NOT** started by these scripts. To develop the miniapp:

1. Install [WeChat DevTools](https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html)
2. Open the `chimeracoffeeweb-master` directory in DevTools
3. Configure the miniapp to point to your local backend (requires ngrok or similar for WeChat callbacks)

---

## Logs

- Backend logs: `../ChimeraCoffee/log/backend_*.log`
- MongoDB logs: `../ChimeraCoffee/log/mongo.log`
- Frontend logs: Console output (Vite dev server)

---

## Contributing

When adding new features that require configuration:

1. **Backend**: Use environment variables in `application.properties`:
   ```properties
   my.new.config=${MY_NEW_CONFIG:default_value}
   ```

2. **Frontend**: Add to `.env` files and use `import.meta.env`:
   ```typescript
   const config = import.meta.env.VITE_MY_NEW_CONFIG || 'default';
   ```

3. **Scripts**: Update the dev scripts to set appropriate defaults

---

## Security Considerations

### Default Credentials (Development Only)

The development environment uses default credentials that are **insecure by design**:

| Service | Username | Password | Note |
|---------|----------|----------|------|
| Admin User | `admin` | `admin123` | Change immediately if exposed to network |
| MongoDB | `chimera` | `chimera` | Local development only |

**⚠️ Never use these credentials in production or on publicly accessible systems.**

### Local Development Safety

These scripts are designed for **local development only**:
- MongoDB binds to `127.0.0.1` (localhost) by default
- No encryption between services (HTTP only)
- Debug logging enabled
- CORS configured to allow all origins

### Before Production Deployment

1. Change all default passwords
2. Use strong, unique passwords for each service
3. Enable MongoDB authentication
4. Use HTTPS with valid SSL certificates
5. Configure firewall rules
6. Disable unnecessary debug logging
7. Review and harden all configuration

See [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) for production deployment instructions.

---

## Support

For issues or questions:
- Check the troubleshooting section above
- Review the logs in `../ChimeraCoffee/log/`
- Consult the project documentation
- Ask in the team chat

---

## License

[Your License Here]
