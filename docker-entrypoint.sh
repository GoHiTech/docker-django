#!/usr/bin/env bash
# http://docs.gunicorn.org/en/stable/settings.html

# Sanity checks
[ -d /docker-entrypoint.d ] || mkdir -p /docker-entrypoint.d
python --version &>/dev/null || { echo "ERROR: Python not installed or not in path."; exit 1; }
python -m django --version |grep -q 'No module named django' && \
  { echo "ERROR: No module named django"; exit 1; }

# Create a new project if manage.py does not exist
[ -f manage.py ] || django-admin startproject ${DJANGO_PROJECT_NAME:-'mysite'} .

if ! ping -c1 -w1 db 2>&1 |grep -q 'unknown host'; then
  # Ensure Postgres database is ready to accept a connection
  echo "Trying db connection..."
  while ! nc -z db 5432; do
    echo "BD not ready, will try again shortly"
    sleep 1
  done
  echo "Connected to DB, will continue processing"
  sleep 5
else
  echo "WARNING: Database container link; db unknown host"
fi

# Source files in /docker-entrypoint.d dump directory
IFS=$'\n' eval 'for f in $(find /docker-entrypoint.d/ -type f -print |sort); do source ${f}; done'

# Start Gunicorn process
echo 'Starting Gunicorn.'
exec gunicorn ${DJANGO_PROJECT_NAME:-'mysite'}.wsgi \
  --name         ${GUNICORN_NAME:-'wsgi_app'} \
  --bind         ${GUNICORN_BIND_IP:-'0.0.0.0'}:8000 \
  --worker-class ${GUNICORN_WORKER_CLASS:-'sync'} \
  --workers      ${GUNICORN_WORKERS:-$(( 2 * $(nproc --all) ))} \
  --log-level    ${GUNICORN_LOG_LEVEL:-'info'} \
  --error-logfile - \
  --access-logfile - \
  "$@"
