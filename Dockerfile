FROM python:2.7
# https://hub.docker.com/_/python/
# https://docs.djangoproject.com/en/1.11/
# http://docs.gunicorn.org/en/stable/settings.html

MAINTAINER Dean Taylor <dean@gohitech.net>
EXPOSE 8000
ENTRYPOINT ["/docker-entrypoint.sh"]
WORKDIR /usr/src/app

RUN pip install --no-cache-dir \
  Django==1.8.18 \
  envparse \
  gevent \
  gunicorn

COPY docker-entrypoint.d/ /docker-entrypoint.d/
COPY docker-entrypoint.sh /

# Django Docker defaults settings
ENV DJANGO_ALLOWED_HOSTS="['.gohitech.net']"
ENV DJANGO_DEBUG="False"
ENV DJANGO_LANGUAGE_CODE="en-au"
ENV DJANGO_TIME_ZONE="Australia/Perth"

ENV DJANGO_PROJECT_NAME="gohitech"

COPY settings_docker.py settings_template.py ./
