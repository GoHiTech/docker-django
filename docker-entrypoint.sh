#!/usr/bin/env bash
# http://docs.gunicorn.org/en/stable/settings.html

# Sanity checks
[ -d /docker-entrypoint.d ] || mkdir -p /docker-entrypoint.d
export DJANGO_PROJECT_NAME="${DJANGO_PROJECT_NAME:-mysite}"

# Create a new project if manage.py does not exist
if [ ! -f manage.py ]; then
  django-admin startproject ${DJANGO_PROJECT_NAME} .
  mv ${DJANGO_PROJECT_NAME}/settings.py ${DJANGO_PROJECT_NAME}/settings_startproject.py
fi

# Ensure base setting files are in location
[ -f ${DJANGO_PROJECT_NAME}/settings_docker.py ] || ln -sr settings_docker.py ${DJANGO_PROJECT_NAME}/settings_docker.py
[ -f ${DJANGO_PROJECT_NAME}/settings.py ] || cp settings_template.py ${DJANGO_PROJECT_NAME}/settings.py

if ping -c1 -w1 db &>/dev/null; then
  export DJANGO_DATABASE='postgresql'
  export DJANGO_DATABASECACHE_ENABLE='True'

  pip install --no-cache-dir psycopg2

  # Ensure Postgres database is ready to accept a connection
  echo "Trying db connection..."
  while ! nc -z db 5432; do
    echo "BD not ready, will try again shortly"
    sleep 1
  done
  echo "Connected to DB, will continue processing"
  sleep 5

  python manage.py createcachetable
  python manage.py migrate
else
  echo "WARNING: Database container link; db: Name or service not known"
fi
if ping -c1 -w1 memcached &>/dev/null; then
  export DJANGO_MEMCACHED_ENABLE='True'

  pip install --no-cache-dir python-memcached
else
  echo "WARNING: Caches container link; memcached: Name or service not known"
fi

# Source files in /docker-entrypoint.d dump directory
IFS=$'\n' eval 'for f in $(find /docker-entrypoint.d/ -type f -print |sort); do source ${f}; done'

# Start Gunicorn process
echo 'Starting Gunicorn.'
exec gunicorn ${DJANGO_PROJECT_NAME}.wsgi \
  --name         ${GUNICORN_NAME:-'wsgi_app'} \
  --bind         ${GUNICORN_BIND_IP:-'0.0.0.0'}:8000 \
  --worker-class ${GUNICORN_WORKER_CLASS:-'sync'} \
  --workers      ${GUNICORN_WORKERS:-$(( 2 * $(nproc --all) ))} \
  --log-level    ${GUNICORN_LOG_LEVEL:-'info'} \
  --error-logfile - \
  --access-logfile - \
  "$@"
