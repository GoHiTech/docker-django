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
  netcat \
  && apt-get clean

RUN pip install --no-cache-dir \
  celery==3.1.17 \
  Django==1.8.18 \
  django-celery \
  envparse \
  gevent \
  gunicorn

COPY docker-entrypoint.d/ /docker-entrypoint.d/
COPY docker-entrypoint.sh /

# Django Docker default settings
ENV DJANGO_ALLOWED_HOSTS="['localhost','.gohitech.net',]"
ENV DJANGO_DEBUG="False"
ENV DJANGO_LANGUAGE_CODE="en-au"
ENV DJANGO_TIME_ZONE="Australia/Perth"
ENV DJANGO_USE_TZ="True"
ENV DJANGO_USE_X_FORWARDED_HOST="True"

ENV DJANGO_PROJECT_NAME="gohitech"

COPY settings.py ./settings.py
COPY settings.d/ ./settings.d/

RUN groupadd user \
  && useradd --home-dir "$(pwd)" -g user user
