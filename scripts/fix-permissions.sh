#!/usr/bin/env bash

set -e

echo "Fixing permissions for Nextcloud and Paperless..."

# Stop services first
echo "Stopping services..."
sudo systemctl stop nextcloud-setup.service || true
sudo systemctl stop phpfpm-nextcloud.service || true
sudo systemctl stop nginx.service || true
sudo systemctl stop paperless-consumer.service || true
sudo systemctl stop paperless-scheduler.service || true
sudo systemctl stop paperless-web.service || true
sudo systemctl stop paperless-task-queue.service || true

# Fix Nextcloud permissions
echo "Fixing Nextcloud permissions..."
if [ -d /var/lib/nextcloud ]; then
    sudo chown -R nextcloud:nextcloud /var/lib/nextcloud
    sudo chmod -R 0750 /var/lib/nextcloud
    echo "  ✓ /var/lib/nextcloud"
fi

if [ -d /persist/var/lib/nextcloud ]; then
    sudo chown -R nextcloud:nextcloud /persist/var/lib/nextcloud
    sudo chmod -R 0750 /persist/var/lib/nextcloud
    echo "  ✓ /persist/var/lib/nextcloud"
fi

if [ -d /var/lib/redis-nextcloud ]; then
    sudo chown -R redis-nextcloud:redis-nextcloud /var/lib/redis-nextcloud
    sudo chmod -R 0750 /var/lib/redis-nextcloud
    echo "  ✓ /var/lib/redis-nextcloud"
fi

if [ -d /persist/var/lib/redis-nextcloud ]; then
    sudo chown -R redis-nextcloud:redis-nextcloud /persist/var/lib/redis-nextcloud
    sudo chmod -R 0750 /persist/var/lib/redis-nextcloud
    echo "  ✓ /persist/var/lib/redis-nextcloud"
fi

# Fix Paperless permissions
echo "Fixing Paperless permissions..."
if [ -d /var/lib/paperless ]; then
    sudo chown -R paperless:paperless /var/lib/paperless
    sudo chmod -R 0750 /var/lib/paperless
    echo "  ✓ /var/lib/paperless"
fi

if [ -d /persist/var/lib/paperless ]; then
    sudo chown -R paperless:paperless /persist/var/lib/paperless
    sudo chmod -R 0750 /persist/var/lib/paperless
    echo "  ✓ /persist/var/lib/paperless"
fi

# Start services
echo "Starting services..."
sudo systemctl start nginx.service
sudo systemctl start phpfpm-nextcloud.service
sudo systemctl start nextcloud-setup.service
sudo systemctl start paperless-web.service
sudo systemctl start paperless-consumer.service
sudo systemctl start paperless-scheduler.service
sudo systemctl start paperless-task-queue.service

echo ""
echo "Done! Checking service status..."
echo ""
echo "=== Nextcloud ==="
sudo systemctl status nextcloud-setup.service --no-pager -l || true
echo ""
echo "=== Paperless ==="
sudo systemctl status paperless-scheduler.service --no-pager -l || true

echo ""
echo "If services are still failing, check logs with:"
echo "  sudo journalctl -u nextcloud-setup.service -n 50"
echo "  sudo journalctl -u paperless-scheduler.service -n 50"
