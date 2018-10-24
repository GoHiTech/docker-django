#!/usr/bin/env bash
# http://docs.gunicorn.org/en/stable/settings.html
# https://pypi.python.org/pypi/django-celery

# Sanity checks
[ -d /docker-entrypoint.d ] || mkdir -p /docker-entrypoint.d
[ -d /docker-entrypoint_celery.d ] || mkdir -p /docker-entrypoint_celery.d
[ -z $DJANGO_PROJECT_NAME ] && export DJANGO_PROJECT_NAME='mysite'
[ -z $RUNAS_USER ] && export RUNAS_USER='user'

# Create a new project if manage.py does not exist
if [ ! -f manage.py ]; then
  django-admin startproject ${DJANGO_PROJECT_NAME} .
  mv ${DJANGO_PROJECT_NAME}/settings.py ${DJANGO_PROJECT_NAME}/settings_startproject.py
fi
[ -z $DJANGO_SETTINGS_MODULE ] && export DJANGO_SETTINGS_MODULE="${DJANGO_PROJECT_NAME}.settings"

# Ensure base setting files are in location
[ -d settings.d ]                         || mkdir settings.d
[ -d ${DJANGO_PROJECT_NAME}/settings.d ]  || ln -sr settings.d ${DJANGO_PROJECT_NAME}/settings.d
if [ ! -h ${DJANGO_PROJECT_NAME}/settings.py ]; then
  [ -f ${DJANGO_PROJECT_NAME}/settings.py ] && mv ${DJANGO_PROJECT_NAME}/settings.py ${DJANGO_PROJECT_NAME}/settings.py_$(date '+%Y%m%d')
  ln -sr settings.py ${DJANGO_PROJECT_NAME}/settings.py
fi
if [ -f settings_pre.py ]; then
  [ -h ${DJANGO_PROJECT_NAME}/settings_pre.py ] || ln -sr settings_pre.py ${DJANGO_PROJECT_NAME}/settings_pre.py
fi

# Services?
is_memcached=false; is_db=false
# https://github.com/memcached/memcached/wiki/ConfiguringServer
#ping -c1 -w1 memcached &>/dev/null && is_memcached=true
#if [ ! \( -z $MEMCACHED_ENABLE -a -z $MEMCACHED_HOSTNAME -a -z $MEMCACHED_PORT \) ]; then
#  [ -z $MEMCACHED_HOSTNAME ] && export MEMCACHED_HOSTNAME='memcached'
#  [ -z $MEMCACHED_PORT ]     && export MEMCACHED_PORT='11211'
#  timeout=5
#  until nc -z ${MEMCACHED_HOSTNAME} ${MEMCACHED_PORT} || [ $timeout -eq 0 ]; do
#    echo "Memcached not ready, will try again shortly"
#    sleep 1
#    (( --timeout ))
#  done
#  is_memcached=true
#  [[ $timeout -eq 0 ]] && { echo "Memcached not ready, DISABLED"; is_memcached=false; }
#fi
#ping -c1 -w1 db        &>/dev/null && is_db=true
#if [ ! ( -z $POSTGRES_HOSTNAME -a -z $POSTGRES_PORT -a -z $POSTGRES_PASSWORD ) ]; then
if [ ! -z $POSTGRES_PASSWORD ]; then
  [ -z $DJANGO_DATABASES_default_HOST ] && export DJANGO_DATABASES_default_HOST='db'
  [ -z $DJANGO_DATABASES_default_PORT ] && export DJANGO_DATABASES_default_PORT='5432'
  [ -z $POSTGRES_PASSWORD ]             && export POSTGRES_PASSWORD='postgres'
  timeout=60
  until nc -z ${DJANGO_DATABASES_default_HOST} ${DJANGO_DATABASES_default_PORT} || [ $timeout -eq 0 ]; do
    echo "BD not ready, will try again shortly"
    sleep 1
    (( --timeout ))
  done
  is_db=true
  [[ $timeout -eq 0 ]] && { echo "DB not ready, DISABLED"; is_db=false; }
fi
export is_memcached is_db

# Run?
if [[ $GUNICORN_ENABLE == True ]]; then
  export CELERY_ENABLE='False'
elif [[ $CELERY_ENABLE == True ]] || [[ $CELERY_ENABLE == worker ]] || [[ $CELERY_ENABLE == beat ]]; then
  export GUNICORN_ENABLE='False'
elif [[ $GUNICORN_ENABLE != False ]]; then
  export GUNICORN_ENABLE='True'
  export CELERY_ENABLE='False'
fi

# Configure and setup memcached if present
if $is_memcached; then
  pip install --no-cache-dir python-memcached
else
  echo "WARNING: Caches container link; memcached: Name or service not known"
fi

# Configure and setup postgres database if present
if $is_db; then
  pip install --no-cache-dir psycopg2-binary

  if [[ $GUNICORN_ENABLE == True ]]; then
    echo 'python manage.py migrate --fake-initial'
    python manage.py migrate --fake-initial

    if ! $is_memcached; then
      echo 'python manage.py createcachetable'
      python manage.py createcachetable
    fi
  fi
else
  echo "WARNING: Database container link; ${DJANGO_DATABASES_default_HOST}: Name or service not known"
fi

if [[ $GUNICORN_ENABLE == True ]]; then
  # Source files in docker-entrypoint.d/ dump directory
  IFS=$'\n' eval 'for f in $(find /docker-entrypoint.d/ -type f ! \( -iname '*.DISABLE' \) -print |sort); do source ${f}; done'

  [[ -z $RUNAS_USER ]] || export GUNICORN_USER="${RUNAS_USER}"
  # https://docs.djangoproject.com/en/1.8/howto/static-files/
  echo 'python manage.py collectstatic --noinput'
  python manage.py collectstatic --noinput

  # Start Gunicorn process
  echo 'Starting Gunicorn.'
  exec gunicorn ${DJANGO_PROJECT_NAME}.wsgi \
    --name         ${GUNICORN_NAME:-'wsgi_app'} \
    --workers      ${GUNICORN_WORKERS:-$(( 2 * $(nproc --all) ))} \
    --access-logfile - \
    --error-logfile - \
    --config       file:///gunicorn.py \
    "$@"
  exit
elif [[ $CELERY_ENABLE == True ]] || [[ $CELERY_ENABLE == worker ]] || [[ $CELERY_ENABLE == beat ]]; then
  # Source files in docker-entrypoint_celery.d/ dump directory
  IFS=$'\n' eval 'for f in $(find /docker-entrypoint_celery.d/ -type f ! \( -iname '*.DISABLE' \) -print |sort); do source ${f}; done'

  [ -f /tmp/celerybeat.pid ] && rm -f /tmp/celerybeat.pid

  export CELERY_USER="${RUNAS_USER}"

  export GUNICORN_ENABLE='False'

  if [ ! -f celeryconfig.py ]; then
    cat >celeryconfig.py <<EOT
import os
BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'amqp://')
EOT
  fi

  celery_cmd='worker'
  [[ -z $CELERY_CONCURRENCY ]] || celery_cmd="${celery_cmd} --concurrency=${CELERY_CONCURRENCY}"

  if [[ $CELERY_ENABLE == beat ]]; then
    celery_cmd='beat --pidfile=/tmp/celerybeat.pid --schedule=/tmp/celerybeat-schedule'
    if $is_db; then
      celery_cmd="${celery_cmd} --scheduler=djcelery.schedulers.DatabaseScheduler"
      sleep 3	# Workaround; wait for djcelery migration
    fi
  fi

  su_cmd="python manage.py celery $celery_cmd $@"

  echo 'Starting Celery...'; echo "${su_cmd}"
  exec su -c "exec ${su_cmd}" -p - $CELERY_USER
  exit
else
  su_cmd="${@}"
  exec su -c "exec ${su_cmd}" -p $RUNAS_USER
  exit
fi
