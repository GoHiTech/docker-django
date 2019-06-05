FROM python:2.7
# https://hub.docker.com/_/python/
# https://docs.djangoproject.com/en/1.11/
# http://docs.gunicorn.org/en/stable/settings.html
# https://pypi.python.org/pypi/django-celery

MAINTAINER Dean Taylor <dean@gohitech.net>
EXPOSE 8000
ENTRYPOINT ["/docker-entrypoint.sh"]
WORKDIR /usr/src/app

RUN apt-get update && apt-get -y install \
  gettext-base \
  netcat \
  && apt-get clean

RUN pip install --no-cache-dir \
  celery==3.1.17 \
  Django==1.8.18 \
  django-celery==3.2.2 \
  envparse \
  gevent \
  gunicorn

COPY docker-entrypoint.d/ /docker-entrypoint.d/
COPY docker-entrypoint_celery.d/ /docker-entrypoint_celery.d/
COPY docker-entrypoint.sh /
COPY gunicorn.py /

ENV CELERY_BROKER_URL="amqp://"

# Django Docker default settings
ENV DJANGO_ALLOWED_HOSTS="['localhost','.gohitech.net',]"
ENV DJANGO_DEBUG="False"
ENV DJANGO_LANGUAGE_CODE="en-au"
ENV DJANGO_LOG_LEVEL="INFO"
ENV DJANGO_PROJECT_NAME="gohitech"
ENV DJANGO_SECRET_KEY="+hzj(tw!bod_*_xh4u2ml!ylbtx6)2r9bqq2i!evjo!x&pay%2"
ENV DJANGO_TIME_ZONE="Australia/Perth"
ENV DJANGO_USE_TZ="True"
ENV DJANGO_USE_X_FORWARDED_HOST="True"

# Gunicorn default settings
ENV GUNICORN_USER="user"
ENV GUNICORN_WORKERS="4"
ENV GUNICORN_BIND="0.0.0.0:8000"
ENV GUNICORN_LOG_LEVEL="info"

ENV POSTGRES_DB="postgres"
ENV POSTGRES_USER="postgres"

ENV RABBITMQ_HOSTNAME="rabbitmq"

COPY settings.py_template ./settings.py_template
COPY settings.d/ ./settings.d/

COPY ./celery.py_template ./celery.py_template
COPY ./celeryconfig.py_template ./celeryconfig.py_template

RUN groupadd user \
  && useradd --home-dir "$(pwd)" -g user user
