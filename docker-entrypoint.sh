#!/usr/bin/env bash
# http://docs.gunicorn.org/en/stable/settings.html
# https://pypi.python.org/pypi/django-celery

# Sanity checks
[ -d /docker-entrypoint.d ] || mkdir -p /docker-entrypoint.d
[ -d /docker-entrypoint_celery.d ] || mkdir -p /docker-entrypoint_celery.d
[ -z $DJANGO_PROJECT_NAME ] && export DJANGO_PROJECT_NAME='mysite'
[ -z $RUNAS_USER ] && export RUNAS_USER='user'

# Create a new project if manage.py does not exist
# NB: settings.py file is created after all environment variables have been processed
#     later in this entrypoint script
if [ ! -f manage.py ]; then
  django-admin startproject ${DJANGO_PROJECT_NAME} .
  cat <<EOF >${DJANGO_PROJECT_NAME}/__init__.py
from __future__ import absolute_import

EOF
  mv ${DJANGO_PROJECT_NAME}/settings.py ${DJANGO_PROJECT_NAME}/settings_startproject.py
fi
[ -z $DJANGO_SETTINGS_MODULE ] && export DJANGO_SETTINGS_MODULE="${DJANGO_PROJECT_NAME}.settings"

# Services?
is_memcached='False'; is_db='False'
# https://github.com/memcached/memcached/wiki/ConfiguringServer
#ping -c1 -w1 memcached &>/dev/null && is_memcached='True'
#if [ ! \( -z $MEMCACHED_ENABLE -a -z $MEMCACHED_HOSTNAME -a -z $MEMCACHED_PORT \) ]; then
#  [ -z $MEMCACHED_HOSTNAME ] && export MEMCACHED_HOSTNAME='memcached'
#  [ -z $MEMCACHED_PORT ]     && export MEMCACHED_PORT='11211'
#  timeout=5
#  until nc -z ${MEMCACHED_HOSTNAME} ${MEMCACHED_PORT} || [ $timeout -eq 0 ]; do
#    echo "Memcached not ready, will try again shortly"
#    sleep 1
#    (( --timeout ))
#  done
#  is_memcached='True'
#  [[ $timeout -eq 0 ]] && { echo "Memcached not ready, DISABLED"; is_memcached='False'; }
#fi
#ping -c1 -w1 db        &>/dev/null && is_db='True'
#if [ ! ( -z $POSTGRES_HOSTNAME -a -z $POSTGRES_PORT -a -z $POSTGRES_PASSWORD ) ]; then
if [ ! -z $POSTGRES_PASSWORD ]; then
  [ -z $DJANGO_DATABASES_default_HOST ] && export DJANGO_DATABASES_default_HOST='db'
  [ -z $DJANGO_DATABASES_default_PORT ] && export DJANGO_DATABASES_default_PORT='5432'
  [ -z $POSTGRES_PASSWORD ]             && export POSTGRES_PASSWORD='postgres'
  [ -z $POSTGRES_USER ]                 && export POSTGRES_USER='postgres'
  timeout=60
  until nc -z ${DJANGO_DATABASES_default_HOST} ${DJANGO_DATABASES_default_PORT} || [ $timeout -eq 0 ]; do
    echo "BD not ready, will try again shortly"
    sleep 1
    (( --timeout ))
  done
  is_db='True'
  [[ $timeout -eq 0 ]] && { echo "DB not ready, DISABLED"; is_db='False'; }
fi
export is_memcached is_db

# Run?
if [[ $GUNICORN_ENABLE == True ]]; then
  CELERY_ENABLE='False'
elif [[ $CELERY_ENABLE == True ]] || [[ $CELERY_ENABLE == worker ]] || [[ $CELERY_ENABLE == beat ]]; then
  GUNICORN_ENABLE='False'
elif [[ $GUNICORN_ENABLE != False ]]; then
  GUNICORN_ENABLE='True'
  CELERY_ENABLE='False'
fi
export CELERY_ENABLE GUNICORN_ENABLE

# Configure and setup memcached if present
if [[ $is_memcached == True ]]; then
  pip install --no-cache-dir python-memcached
else
  echo "WARNING: Caches container link; memcached: Name or service not known"
fi

# Generate the settings.py file
/usr/bin/envsubst <settings.py_template >settings.py

# Ensure base setting files are in location
[ -d settings.d ]                         || mkdir settings.d
[ -d ${DJANGO_PROJECT_NAME}/settings.d ]  || ln -sr settings.d ${DJANGO_PROJECT_NAME}/settings.d
[[ -f settings.d/__init__.py ]] && rm -f settings.d/__init__.py
cat <<EOF >settings.d/__init__.py
__all__ = [ $(ls -m settings.d/*.py 2>/dev/null) ]
EOF
if [ ! -h ${DJANGO_PROJECT_NAME}/settings.py ]; then
  [ -f ${DJANGO_PROJECT_NAME}/settings.py ] && mv ${DJANGO_PROJECT_NAME}/settings.py ${DJANGO_PROJECT_NAME}/settings.py_$(date '+%Y%m%d')
  ln -sr settings.py ${DJANGO_PROJECT_NAME}/settings.py
fi
if [ -f settings_pre.py ]; then
  [ -h ${DJANGO_PROJECT_NAME}/settings_pre.py ] || ln -sr settings_pre.py ${DJANGO_PROJECT_NAME}/settings_pre.py
fi

# Configure and setup postgres database if present
if [[ $is_db == True ]]; then
  pip install --no-cache-dir psycopg2-binary

  if [[ $GUNICORN_ENABLE == True ]]; then
    echo 'python manage.py migrate --fake-initial'
    python manage.py migrate --fake-initial

    if [[ $is_memcached == False ]]; then
      echo 'python manage.py createcachetable'
      python manage.py createcachetable
    fi
  fi
else
  echo "WARNING: Database container link; ${DJANGO_DATABASES_default_HOST}: Name or service not known"
fi

# Configure Celery
grep -q 'from .celery ' ${DJANGO_PROJECT_NAME}/__init__.py 2>/dev/null || cat <<EOF >>${DJANGO_PROJECT_NAME}/__init__.py
# This will make sure the app is always imported when
# Django starts so that shared_task will use this app.
from .celery import app as celery_app  # noqa
__all__ = ('celery_app',)
EOF
grep -q 'import djcelery' ${DJANGO_PROJECT_NAME}/wsgi.py 2>/dev/null || cat <<EOF >>${DJANGO_PROJECT_NAME}/wsgi.py
import djcelery
djcelery.setup_loader()
EOF
/usr/bin/envsubst <celery.py_template >${DJANGO_PROJECT_NAME}/celery.py
/usr/bin/envsubst <celeryconfig.py_template >celeryconfig.py

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

  CELERY_USER="${RUNAS_USER}"
  GUNICORN_ENABLE='False'
  export CELERY_USER GUNICORN_ENABLE

  celery_cmd='worker'
  [[ -z $CELERY_CONCURRENCY ]] || celery_cmd="${celery_cmd} --concurrency=${CELERY_CONCURRENCY}"

  if [[ $CELERY_ENABLE == beat ]]; then
    celery_cmd='beat --pidfile=/tmp/celerybeat.pid --schedule=/tmp/celerybeat-schedule'
    if [[ $is_db == True ]]; then
      celery_cmd="${celery_cmd} --scheduler=djcelery.schedulers.DatabaseScheduler"
    fi
  fi

  su_cmd="python manage.py celery $celery_cmd $@"

  sleep 3	# Workaround; wait for djcelery migration

  echo 'Starting Celery...'; echo "${su_cmd}"
  exec su -c "${su_cmd}" -p - $CELERY_USER
  exit
else
  su_cmd="${@}"
  exec su -c "${su_cmd}" -p - $RUNAS_USER
  exit
fi
