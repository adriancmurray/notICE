#!/bin/bash

# notICE Server Setup Script
# Run this script to configure your notICE server

set -e

echo ""
echo "🧊 notICE Server Setup"
echo "======================"
echo ""

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed."
    echo "   Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed."
    echo "   Please install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✅ Docker is installed"
echo ""

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    echo "📝 Created .env configuration file"
fi

# Prompt for region information
echo "📍 Region Configuration"
echo "-----------------------"
read -p "Region name (e.g., 'Idaho Falls, ID'): " REGION_NAME
read -p "Latitude (e.g., 43.4926): " REGION_LAT
read -p "Longitude (e.g., -112.0401): " REGION_LONG

# Update .env file
sed -i.bak "s/REGION_NAME=.*/REGION_NAME=\"$REGION_NAME\"/" .env
sed -i.bak "s/REGION_LAT=.*/REGION_LAT=$REGION_LAT/" .env
sed -i.bak "s/REGION_LONG=.*/REGION_LONG=$REGION_LONG/" .env
rm -f .env.bak

echo ""
echo "📱 Telegram Configuration (Optional)"
echo "------------------------------------"
echo "To enable push notifications, you need:"
echo "1. A Telegram bot token (get from @BotFather)"
echo "2. A chat/channel ID (group where alerts will be posted)"
echo ""
read -p "Do you want to configure Telegram? (y/n): " SETUP_TELEGRAM

if [ "$SETUP_TELEGRAM" = "y" ] || [ "$SETUP_TELEGRAM" = "Y" ]; then
    read -p "Bot token: " TELEGRAM_BOT_TOKEN
    read -p "Chat ID: " TELEGRAM_CHAT_ID
    
    sed -i.bak "s/TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN/" .env
    sed -i.bak "s/TELEGRAM_CHAT_ID=.*/TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID/" .env
    rm -f .env.bak
    
    echo "✅ Telegram configured"
fi

echo ""
echo "🌐 Public Access"
echo "----------------"
echo "How should the server be accessible?"
echo ""
echo "  1) Local only (http://localhost:8090)"
echo "     - Good for testing"
echo ""
echo "  2) Public via Cloudflare Tunnel (free HTTPS URL)"
echo "     - No port forwarding needed"
echo "     - Free public URL with HTTPS"
echo "     - Share with anyone instantly"
echo ""
read -p "Choose access mode [1/2]: " ACCESS_MODE

echo ""
echo "🚀 Starting notICE server..."
echo ""

if [ "$ACCESS_MODE" = "2" ]; then
    # Start with Cloudflare tunnel
    docker compose --profile public up -d
    
    echo ""
    echo "⏳ Waiting for Cloudflare tunnel..."
    sleep 5
    
    # Get the tunnel URL from logs
    TUNNEL_URL=$(docker compose logs tunnel 2>&1 | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | head -1)
    
    echo ""
    echo "✅ notICE server is running!"
    echo ""
    if [ -n "$TUNNEL_URL" ]; then
        echo "🌍 PUBLIC URL: $TUNNEL_URL"
        echo ""
        echo "Share this link with your community!"
        echo "They can open it in a browser and 'Add to Home Screen' for the full app."
    else
        echo "📊 Tunnel starting... check logs with: docker compose logs tunnel"
    fi
else
    # Start local only
    docker compose up -d
    
    echo ""
    echo "✅ notICE server is running!"
    echo ""
    echo "📊 Admin Dashboard: http://localhost:8090/_/"
    echo "🌐 App: http://localhost:8090/"
fi

echo ""
echo "📊 Admin Dashboard: http://localhost:8090/_/"
echo ""
echo "Commands:"
echo "  docker compose logs -f        # View logs"
echo "  docker compose down           # Stop server"
echo "  docker compose --profile public up -d  # Add public access"
echo ""
