FROM ghcr.io/muchobien/pocketbase:latest

# Copy PocketBase hooks (Telegram notifications, etc.)
COPY pb_hooks /pb_hooks

# Copy PWA static files (served at /)
COPY pb_public /pb_public

# Expose port
EXPOSE 8090

# Start PocketBase
CMD ["serve", "--http=0.0.0.0:8090"]
