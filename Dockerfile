FROM ghcr.io/muchobien/pocketbase:latest

# Copy hooks
COPY pb_hooks /pb_hooks

# Expose port
EXPOSE 8090

# Start PocketBase
CMD ["serve", "--http=0.0.0.0:8090"]
