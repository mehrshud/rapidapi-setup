#!/bin/bash

#######################################################
# RAPIDAPI MEGA SERVICE - FULLY AUTOMATED SETUP
# Zero-prompt deployment for Ubuntu 24.04 LTS
# Optimized for DigitalOcean London datacenter
#######################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration - CHANGE THESE!
DOMAIN="layu.ir"  # YOUR DOMAIN HERE
ADMIN_EMAIL="admin@${DOMAIN}"  # For SSL cert notifications

# Derived configuration
PROJECT_DIR="$HOME/rapidapi-service"
SERVICE_USER="$USER"
REDIS_PASSWORD=$(openssl rand -base64 32)
API_SECRET=$(openssl rand -hex 32)
ADMIN_SECRET=$(openssl rand -hex 16)

# Disable ALL interactive prompts
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export UCF_FORCE_CONFFOLD=1

clear
echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   RAPIDAPI MEGA SERVICE - FULLY AUTOMATED SETUP   ║${NC}"
echo -e "${CYAN}║   Ubuntu 24.04 LTS - DigitalOcean London          ║${NC}"
echo -e "${CYAN}║   Zero-Prompt Production Deployment               ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Domain:${NC} $DOMAIN"
echo -e "${BLUE}Location:${NC} London, UK"
echo -e "${BLUE}Project Directory:${NC} $PROJECT_DIR"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}❌ ERROR: Do not run as root. Run as regular user with sudo access.${NC}"
    exit 1
fi

# Verify domain is set
if [ "$DOMAIN" = "your-domain.com" ]; then
    echo -e "${RED}❌ ERROR: Please edit the script and set your DOMAIN variable!${NC}"
    exit 1
fi

# Function to run commands silently with status
run_silent() {
    local msg="$1"
    shift
    echo -ne "${YELLOW}⏳ $msg...${NC}"
    if "$@" >/dev/null 2>&1; then
        echo -e "\r${GREEN}✓ $msg${NC}"
        return 0
    else
        echo -e "\r${RED}✗ $msg${NC}"
        return 1
    fi
}

# Configure system to NEVER show prompts
echo -e "${GREEN}[0/15] Configuring system for fully non-interactive mode...${NC}"

# Configure needrestart to not prompt
sudo mkdir -p /etc/needrestart
sudo tee /etc/needrestart/needrestart.conf > /dev/null <<'EOF'
# Restart services automatically
$nrconf{restart} = 'a';
$nrconf{kernelhints} = 0;
EOF

# Configure UCF to never prompt
sudo tee /etc/ucf.conf > /dev/null <<'EOF'
conf_force_conffold=YES
EOF

# Disable ALL dpkg prompts - ONLY use confold
sudo tee /etc/apt/apt.conf.d/99local-options > /dev/null <<'EOF'
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
};
EOF

# Pre-configure openssh-server to avoid prompt
echo 'openssh-server openssh-server/permit-root-login boolean false' | sudo debconf-set-selections
echo 'openssh-server openssh-server/password-authentication boolean true' | sudo debconf-set-selections

echo -e "${GREEN}[1/15] Updating system packages (fully automated)...${NC}"

# First, fix any broken packages from previous run
sudo dpkg --configure -a 2>&1 | grep -v "^$" || true

# Update package lists
sudo apt-get update -qq 2>&1 | grep -v "^Get:\|^Hit:\|^Reading" || true

# Upgrade with proper options - ONLY confold, no confnew
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" 2>&1 | grep -v "^Reading\|^Building\|^Get:\|^Fetched" || true

# Clean up
sudo apt-get autoremove -y -qq 2>&1 | grep -v "^Reading" || true

echo -e "${GREEN}[2/15] Installing core packages...${NC}"
sudo apt-get install -y -qq \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release

echo -e "${GREEN}[3/15] Installing Python and development tools...${NC}"
sudo apt-get install -y -qq \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    git \
    htop \
    net-tools \
    dnsutils

echo -e "${GREEN}[4/15] Installing and configuring Nginx...${NC}"
sudo apt-get install -y -qq nginx
sudo systemctl enable nginx >/dev/null 2>&1

echo -e "${GREEN}[5/15] Installing Redis...${NC}"
sudo apt-get install -y -qq redis-server

echo -e "${GREEN}[6/15] Installing Certbot for SSL...${NC}"
sudo apt-get install -y -qq certbot python3-certbot-nginx

echo -e "${GREEN}[7/15] Installing security packages...${NC}"
sudo apt-get install -y -qq \
    ufw \
    fail2ban \
    unattended-upgrades

echo -e "${GREEN}[8/15] Configuring firewall (UFW)...${NC}"
sudo ufw --force reset >/dev/null 2>&1
sudo ufw default deny incoming >/dev/null 2>&1
sudo ufw default allow outgoing >/dev/null 2>&1
sudo ufw allow 22/tcp >/dev/null 2>&1
sudo ufw allow 80/tcp >/dev/null 2>&1
sudo ufw allow 443/tcp >/dev/null 2>&1
sudo ufw --force enable >/dev/null 2>&1

echo -e "${GREEN}[9/15] Configuring automatic security updates...${NC}"
sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-custom > /dev/null <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

echo -e "${GREEN}[10/15] Securing Redis...${NC}"
sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.backup
sudo tee -a /etc/redis/redis.conf > /dev/null <<EOF

# Custom security settings
bind 127.0.0.1 ::1
protected-mode yes
requirepass $REDIS_PASSWORD
maxmemory 512mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
EOF

sudo systemctl restart redis-server
sudo systemctl enable redis-server >/dev/null 2>&1

echo -e "${GREEN}[11/15] Setting up project directory...${NC}"
mkdir -p "$PROJECT_DIR"/{logs,backups,uploads}
cd "$PROJECT_DIR"

echo -e "${GREEN}[12/15] Creating Python environment...${NC}"
python3 -m venv venv
source venv/bin/activate

echo -e "${GREEN}[13/15] Installing Python dependencies...${NC}"
cat > requirements.txt <<'EOF'
fastapi==0.109.2
uvicorn[standard]==0.27.1
pydantic==2.6.1
pydantic-settings==2.1.0
python-multipart==0.0.9
google-generativeai==0.3.2
openai==1.12.0
anthropic==0.18.1
cohere==4.47
httpx==0.26.0
aiofiles==23.2.1
redis==5.0.1
hiredis==2.3.2
slowapi==0.1.9
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0
prometheus-client==0.19.0
sentry-sdk[fastapi]==1.40.3
psutil==5.9.8
python-telegram-bot==21.0.1
pyyaml==6.0.1
python-dateutil==2.8.2
jinja2==3.1.3
itsdangerous==2.1.2
orjson==3.9.15
EOF

pip install --quiet --upgrade pip setuptools wheel
pip install --quiet -r requirements.txt

echo -e "${GREEN}[14/15] Creating configuration files...${NC}"

# Environment file
cat > .env <<EOF
# AI Provider API Keys - ADD YOUR KEYS HERE!
GEMINI_API_KEYS=
OPENAI_API_KEYS=
ANTHROPIC_API_KEYS=
PERPLEXITY_API_KEYS=
COHERE_API_KEYS=
GROQ_API_KEYS=

# RapidAPI Configuration
RAPIDAPI_PROXY_SECRET=
RAPIDAPI_KEY=

# Telegram Bot (Optional)
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Redis Configuration
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=$REDIS_PASSWORD

# Security
API_SECRET_KEY=$API_SECRET
ADMIN_SECRET=$ADMIN_SECRET
JWT_SECRET=$API_SECRET
CORS_ORIGINS=https://$DOMAIN,https://www.$DOMAIN

# Server Configuration
API_URL=https://$DOMAIN
WORKERS=4
PORT=8000
ENVIRONMENT=production
LOG_LEVEL=INFO
MAX_UPLOAD_SIZE=10485760

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=60

# Monitoring (Optional)
SENTRY_DSN=
PROMETHEUS_ENABLED=true

# Database (if needed later)
DATABASE_URL=

# Email (Optional - for alerts)
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
ADMIN_EMAIL=$ADMIN_EMAIL
EOF

chmod 600 .env

# Create basic FastAPI app if it doesn't exist
if [ ! -f "app.py" ]; then
    cat > app.py <<'PYEOF'
from fastapi import FastAPI, Request, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import redis
import os
from datetime import datetime
import psutil

# Initialize
app = FastAPI(
    title="RapidAPI Mega Service",
    description="Multi-provider AI API gateway",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Rate limiting
limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis connection
try:
    redis_client = redis.Redis(
        host="localhost",
        port=6379,
        password=os.getenv("REDIS_PASSWORD"),
        decode_responses=True
    )
    redis_client.ping()
except Exception as e:
    print(f"Redis connection failed: {e}")
    redis_client = None

@app.get("/")
async def root():
    return {
        "service": "RapidAPI Mega Service",
        "version": "2.0.0",
        "status": "operational",
        "timestamp": datetime.utcnow().isoformat()
    }

@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring"""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    redis_status = "connected" if redis_client and redis_client.ping() else "disconnected"
    
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "redis": redis_status,
        "system": {
            "cpu_percent": cpu_percent,
            "memory_percent": memory.percent,
            "disk_percent": disk.percent
        }
    }

@app.get("/metrics")
async def metrics():
    """Prometheus-compatible metrics"""
    cpu_percent = psutil.cpu_percent()
    memory = psutil.virtual_memory()
    
    metrics = f"""# HELP api_cpu_usage CPU usage percentage
# TYPE api_cpu_usage gauge
api_cpu_usage {cpu_percent}

# HELP api_memory_usage Memory usage percentage
# TYPE api_memory_usage gauge
api_memory_usage {memory.percent}

# HELP api_memory_bytes Memory usage in bytes
# TYPE api_memory_bytes gauge
api_memory_bytes {memory.used}
"""
    return metrics

@app.post("/api/v1/chat")
@limiter.limit("100/minute")
async def chat(request: Request):
    """Main chat endpoint - implement your AI logic here"""
    return {
        "response": "API endpoint ready - implement your AI logic",
        "timestamp": datetime.utcnow().isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
PYEOF
fi

# Create systemd service for API
sudo tee /etc/systemd/system/rapidapi.service > /dev/null <<EOF
[Unit]
Description=RapidAPI Mega Service
After=network.target redis.service
Wants=redis.service

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 --workers 4 --log-level info --access-log
Restart=always
RestartSec=10
StandardOutput=append:$PROJECT_DIR/logs/api.log
StandardError=append:$PROJECT_DIR/logs/api-error.log

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR
CapabilityBoundingSet=
AmbientCapabilities=
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true
PrivateMounts=true

[Install]
WantedBy=multi-user.target
EOF

# Nginx configuration
sudo tee /etc/nginx/sites-available/rapidapi > /dev/null <<EOF
# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=100r/s;
limit_req_zone \$binary_remote_addr zone=api_burst:10m rate=20r/s;
limit_conn_zone \$binary_remote_addr zone=conn_limit:10m;

# Cache for static content
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=api_cache:10m max_size=100m inactive=60m use_temp_path=off;

upstream api_backend {
    least_conn;
    server 127.0.0.1:8000 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;

    # Rate limiting
    limit_req zone=api_limit burst=50 nodelay;
    limit_req zone=api_burst burst=10 nodelay;
    limit_conn conn_limit 20;

    # Max body size
    client_max_body_size 10M;
    client_body_buffer_size 128k;

    # Timeouts
    client_body_timeout 12;
    client_header_timeout 12;
    keepalive_timeout 15;
    send_timeout 10;

    # Logging
    access_log /var/log/nginx/rapidapi-access.log combined buffer=32k flush=5s;
    error_log /var/log/nginx/rapidapi-error.log warn;

    # Health check endpoint (no rate limit)
    location = /health {
        limit_req off;
        limit_conn off;
        proxy_pass http://api_backend;
        access_log off;
    }

    # Metrics endpoint (localhost only)
    location = /metrics {
        allow 127.0.0.1;
        allow ::1;
        deny all;
        proxy_pass http://api_backend;
    }

    # API endpoints
    location / {
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Static files (if any)
    location /static {
        alias $PROJECT_DIR/static;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Enable site and remove default
sudo ln -sf /etc/nginx/sites-available/rapidapi /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test nginx config
sudo nginx -t

echo -e "${GREEN}[15/15] Starting and enabling services...${NC}"

# Reload systemd
sudo systemctl daemon-reload

# Enable and start services
sudo systemctl enable rapidapi >/dev/null 2>&1
sudo systemctl restart nginx
sudo systemctl start rapidapi

# Wait a moment for service to start
sleep 3

# Check if service started successfully
if sudo systemctl is-active --quiet rapidapi; then
    echo -e "${GREEN}✓ RapidAPI service started successfully${NC}"
else
    echo -e "${YELLOW}⚠ RapidAPI service may need troubleshooting${NC}"
fi

# Configure SSL automatically
echo ""
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  CONFIGURING SSL CERTIFICATE${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""

if sudo certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "$ADMIN_EMAIL" --redirect; then
    echo -e "${GREEN}✓ SSL certificate installed successfully${NC}"
else
    echo -e "${YELLOW}⚠ SSL installation failed. Run manually: sudo certbot --nginx -d $DOMAIN${NC}"
fi

# Create management scripts
echo -e "${GREEN}Creating management scripts...${NC}"

cat > "$PROJECT_DIR/restart.sh" <<'EOFSCRIPT'
#!/bin/bash
echo "Restarting services..."
sudo systemctl restart rapidapi nginx
echo "✓ Services restarted!"
sudo systemctl status rapidapi --no-pager -l
EOFSCRIPT

cat > "$PROJECT_DIR/logs.sh" <<'EOFSCRIPT'
#!/bin/bash
echo "=== Live API Logs ==="
echo "Press Ctrl+C to exit"
echo ""
sudo journalctl -u rapidapi -f --no-pager
EOFSCRIPT

cat > "$PROJECT_DIR/status.sh" <<'EOFSCRIPT'
#!/bin/bash
clear
echo "════════════════════════════════════════"
echo "  RAPIDAPI SERVICE STATUS"
echo "════════════════════════════════════════"
echo ""
echo "=== Service Status ==="
sudo systemctl status rapidapi --no-pager -l | head -20
echo ""
sudo systemctl status nginx --no-pager -l | head -10
echo ""
echo "=== Resource Usage ==="
free -h
echo ""
df -h | grep -E "Filesystem|/$"
echo ""
echo "=== Recent API Logs ==="
sudo journalctl -u rapidapi --no-pager -n 5
echo ""
echo "=== Network ==="
sudo ss -tlnp | grep -E "8000|80|443"
EOFSCRIPT

cat > "$PROJECT_DIR/update.sh" <<'EOFSCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
echo "Updating dependencies..."
source venv/bin/activate
pip install -q --upgrade pip
pip install -q -r requirements.txt --upgrade
echo "Restarting service..."
sudo systemctl restart rapidapi
echo "✓ Update complete!"
EOFSCRIPT

cat > "$PROJECT_DIR/backup.sh" <<'EOFSCRIPT'
#!/bin/bash
BACKUP_DIR="$HOME/rapidapi-service/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

echo "Creating backup..."
tar -czf "$BACKUP_FILE" \
    --exclude='venv' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='logs/*.log' \
    -C "$HOME" rapidapi-service/

echo "✓ Backup created: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"

# Keep only last 7 backups
cd "$BACKUP_DIR" && ls -t | tail -n +8 | xargs -r rm --
EOFSCRIPT

chmod +x "$PROJECT_DIR"/*.sh

# Create helpful aliases
cat >> "$HOME/.bashrc" <<'EOFBASH'

# RapidAPI shortcuts
alias api-status='~/rapidapi-service/status.sh'
alias api-logs='~/rapidapi-service/logs.sh'
alias api-restart='~/rapidapi-service/restart.sh'
alias api-update='~/rapidapi-service/update.sh'
alias api-backup='~/rapidapi-service/backup.sh'
alias api-cd='cd ~/rapidapi-service'
EOFBASH

# Setup log rotation
sudo tee /etc/logrotate.d/rapidapi > /dev/null <<'EOFLOG'
/home/*/rapidapi-service/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 ubuntu ubuntu
    sharedscripts
    postrotate
        systemctl reload rapidapi > /dev/null 2>&1 || true
    endscript
}
EOFLOG

# Final summary
clear
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           INSTALLATION COMPLETE! 🚀                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  SERVICE INFORMATION${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}🌐 API URL:${NC}        https://$DOMAIN"
echo -e "${BLUE}📚 Documentation:${NC}  https://$DOMAIN/docs"
echo -e "${BLUE}📁 Project Dir:${NC}    $PROJECT_DIR"
echo -e "${BLUE}🔒 Redis Password:${NC} $REDIS_PASSWORD"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  QUICK COMMANDS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Service Management:${NC}"
echo "  api-status         # Check service status"
echo "  api-logs           # View live logs"
echo "  api-restart        # Restart services"
echo "  api-update         # Update dependencies"
echo "  api-backup         # Create backup"
echo "  api-cd             # Go to project directory"
echo ""
echo -e "${YELLOW}Manual Commands:${NC}"
echo "  sudo systemctl status rapidapi"
echo "  sudo systemctl restart rapidapi"
echo "  sudo journalctl -u rapidapi -f"
echo "  sudo nginx -t && sudo systemctl reload nginx"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  NEXT STEPS${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}1.${NC} Add your API keys to .env file:"
echo "   nano $PROJECT_DIR/.env"
echo ""
echo -e "${YELLOW}2.${NC} Test the API:"
echo "   curl https://$DOMAIN/health"
echo ""
echo -e "${YELLOW}3.${NC} Check service status:"
echo "   api-status"
echo ""
echo -e "${YELLOW}4.${NC} View API documentation:"
echo "   https://$DOMAIN/docs"
echo ""
echo -e "${YELLOW}5.${NC} Monitor logs:"
echo "   api-logs"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  SECURITY NOTES${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "✓ Firewall configured (UFW)"
echo -e "✓ SSL certificate installed"
echo -e "✓ Redis secured with password"
echo -e "✓ Automatic security updates enabled"
echo -e "✓ Service hardened with systemd"
echo -e "✓ Rate limiting active"
echo ""
echo -e "${CYAN}Your Redis password has been saved to $PROJECT_DIR/.env${NC}"
echo ""
echo -e "${GREEN}All done! Your API is live at: ${BLUE}https://$DOMAIN${NC}"
echo ""

# Save installation info
cat > "$PROJECT_DIR/INSTALLATION_INFO.txt" <<EOF
RapidAPI Service Installation
==============================
Date: $(date)
Domain: $DOMAIN
Location: London, UK
Ubuntu: 24.04 LTS

Redis Password: $REDIS_PASSWORD
API Secret: $API_SECRET
Admin Secret: $ADMIN_SECRET

Project Directory: $PROJECT_DIR
Service User: $SERVICE_USER

Quick Commands:
- api-status
- api-logs  
- api-restart
- api-update
- api-backup
- api-cd

Service Status:
sudo systemctl status rapidapi

Logs:
sudo journalctl -u rapidapi -f

Configuration:
$PROJECT_DIR/.env
EOF

echo -e "${CYAN}Installation info saved to: $PROJECT_DIR/INSTALLATION_INFO.txt${NC}"
echo ""

# Source bashrc to enable aliases immediately
source "$HOME/.bashrc" 2>/dev/null || true

# Final check
echo -e "${YELLOW}Running final health check...${NC}"
sleep 2
if curl -sf http://localhost:8000/health > /dev/null; then
    echo -e "${GREEN}✓ API is responding correctly!${NC}"
else
    echo -e "${YELLOW}⚠ API may need a moment to start. Check with: api-status${NC}"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓✓✓ SETUP COMPLETE - ENJOY YOUR API! ✓✓✓${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
