#!/bin/bash

#######################################################
# RAPIDAPI MEGA SERVICE - AUTOMATED SETUP SCRIPT
# Complete production deployment in minutes
#######################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$HOME/rapidapi-service"
SERVICE_USER="ubuntu"
DOMAIN="your-domain.com"  # Change this!

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   RAPIDAPI MEGA SERVICE - AUTO SETUP      ║${NC}"
echo -e "${BLUE}║   Production-Ready Deployment             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}ERROR: Do not run as root. Run as regular user with sudo access.${NC}"
    exit 1
fi

echo -e "${GREEN}[1/12] Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y

echo -e "${GREEN}[2/12] Installing required packages...${NC}"
sudo apt install -y \
    python3-pip \
    python3-venv \
    nginx \
    certbot \
    python3-certbot-nginx \
    redis-server \
    git \
    ufw \
    fail2ban \
    unattended-upgrades \
    htop \
    curl \
    wget \
    build-essential

echo -e "${GREEN}[3/12] Configuring firewall...${NC}"
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

echo -e "${GREEN}[4/12] Configuring automatic security updates...${NC}"
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}:\${distro_codename}-updates";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
Unattended-Upgrade::Mail "root";
EOF

sudo dpkg-reconfigure -plow unattended-upgrades

echo -e "${GREEN}[5/12] Securing Redis...${NC}"
sudo tee -a /etc/redis/redis.conf > /dev/null <<EOF

# Security settings
bind 127.0.0.1 ::1
protected-mode yes
requirepass $(openssl rand -base64 32)
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF

sudo systemctl restart redis-server

echo -e "${GREEN}[6/12] Creating project directory...${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo -e "${GREEN}[7/12] Setting up Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

echo -e "${GREEN}[8/12] Installing Python dependencies...${NC}"
cat > requirements.txt <<EOF
fastapi==0.109.2
uvicorn[standard]==0.27.1
pydantic==2.6.1
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
EOF

pip install -r requirements.txt

echo -e "${GREEN}[9/12] Creating environment file...${NC}"
cat > .env <<EOF
# AI Provider Keys (ADD YOUR KEYS HERE!)
GEMINI_API_KEYS=
OPENAI_API_KEYS=
ANTHROPIC_API_KEYS=
PERPLEXITY_API_KEYS=
COHERE_API_KEYS=
GROQ_API_KEYS=

# RapidAPI
RAPIDAPI_PROXY_SECRET=

# Telegram
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Redis
REDIS_URL=redis://localhost:6379

# Security
API_SECRET_KEY=$(openssl rand -hex 32)
ADMIN_SECRET=$(openssl rand -hex 16)

# Server
API_URL=https://$DOMAIN
WORKERS=4
PORT=8000
ENVIRONMENT=production

# Monitoring
SENTRY_DSN=
LOG_LEVEL=INFO
EOF

echo -e "${YELLOW}IMPORTANT: Edit $PROJECT_DIR/.env and add your API keys!${NC}"
echo -e "${YELLOW}Press Enter when done...${NC}"
read

echo -e "${GREEN}[10/12] Creating systemd services...${NC}"

# API Service
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
ExecStart=$PROJECT_DIR/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 --workers 4 --log-level info
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$PROJECT_DIR

[Install]
WantedBy=multi-user.target
EOF

# Telegram Bot Service
sudo tee /etc/systemd/system/telegram-bot.service > /dev/null <<EOF
[Unit]
Description=Telegram Monitoring Bot
After=network.target rapidapi.service
Wants=rapidapi.service

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
EnvironmentFile=$PROJECT_DIR/.env
ExecStart=$PROJECT_DIR/venv/bin/python telegram_bot.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}[11/12] Configuring Nginx...${NC}"
sudo tee /etc/nginx/sites-available/rapidapi > /dev/null <<EOF
# Rate limiting zones
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=100r/s;
limit_req_zone \$binary_remote_addr zone=api_burst:10m rate=20r/s;

# Connection limiting
limit_conn_zone \$binary_remote_addr zone=conn_limit:10m;

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Rate limiting
    limit_req zone=api_limit burst=50 nodelay;
    limit_req zone=api_burst burst=10 nodelay;
    limit_conn conn_limit 20;

    # Max body size
    client_max_body_size 10M;

    # Logging
    access_log /var/log/nginx/rapidapi-access.log;
    error_log /var/log/nginx/rapidapi-error.log;

    # Proxy to FastAPI
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }

    # Health check endpoint (no rate limit)
    location = /health {
        limit_req off;
        limit_conn off;
        proxy_pass http://127.0.0.1:8000;
        access_log off;
    }

    # Metrics endpoint (protected)
    location = /metrics {
        allow 127.0.0.1;
        deny all;
        proxy_pass http://127.0.0.1:8000;
    }
}
EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/rapidapi /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

echo -e "${GREEN}[12/12] Starting services...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable rapidapi telegram-bot redis-server nginx
sudo systemctl start rapidapi telegram-bot

echo ""
echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}       NEXT STEPS${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}1. Configure SSL certificate:${NC}"
echo "   sudo certbot --nginx -d $DOMAIN"
echo ""
echo -e "${YELLOW}2. Check service status:${NC}"
echo "   sudo systemctl status rapidapi"
echo "   sudo systemctl status telegram-bot"
echo ""
echo -e "${YELLOW}3. View logs:${NC}"
echo "   sudo journalctl -u rapidapi -f"
echo "   sudo journalctl -u telegram-bot -f"
echo ""
echo -e "${YELLOW}4. Test API:${NC}"
echo "   curl http://localhost:8000/health"
echo ""
echo -e "${YELLOW}5. Access API documentation:${NC}"
echo "   https://$DOMAIN/docs"
echo ""
echo -e "${YELLOW}6. Monitor with Telegram:${NC}"
echo "   Send /start to your Telegram bot"
echo ""
echo -e "${GREEN}Server is running at: ${BLUE}https://$DOMAIN${NC}"
echo ""

# Create helpful management scripts
cat > "$PROJECT_DIR/restart.sh" <<'EOF'
#!/bin/bash
sudo systemctl restart rapidapi telegram-bot
echo "Services restarted!"
EOF

cat > "$PROJECT_DIR/logs.sh" <<'EOF'
#!/bin/bash
sudo journalctl -u rapidapi -f
EOF

cat > "$PROJECT_DIR/status.sh" <<'EOF'
#!/bin/bash
echo "=== Service Status ==="
sudo systemctl status rapidapi --no-pager
echo ""
sudo systemctl status telegram-bot --no-pager
echo ""
echo "=== Resource Usage ==="
free -h
df -h
EOF

chmod +x "$PROJECT_DIR"/*.sh

echo -e "${GREEN}Created helper scripts:${NC}"
echo "  ./restart.sh  - Restart services"
echo "  ./logs.sh     - View logs"
echo "  ./status.sh   - Check status"
echo ""
echo -e "${GREEN}Setup completed successfully! 🚀${NC}"
