#!/bin/bash
set -e

# Rimuovi server.pid stale
rm -f /rails/tmp/pids/server.pid

# Migra DB se necessario (solo in produzione)
if [ "$RAILS_ENV" = "production" ]; then
  bundle exec rails db:prepare
fi

exec "$@"
