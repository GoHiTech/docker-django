"""
Django settings for Docker image.

Derived from settings generated by 'django-admin startproject' using Django 1.8.18.

For more information on this file, see
https://docs.djangoproject.com/en/1.8/topics/settings/

For the full list of settings and their values, see
https://docs.djangoproject.com/en/1.8/ref/settings/
"""
# Quick-start development settings - unsuitable for production
# See https://docs.djangoproject.com/en/1.8/howto/deployment/checklist/

import sys
import socket
from ast import literal_eval
import glob

# Build paths inside the project like this: os.path.join(BASE_DIR, ...)
import os

# https://pypi.python.org/pypi/django-celery
# http://docs.celeryproject.org/en/3.1/
# http://docs.celeryproject.org/en/3.1/configuration.html
import djcelery

def _gethostbyname(hostname):
    try:
        socket.gethostbyname(hostname)
        return True
    except socket.error:
        return False

this_module = sys.modules[__name__]

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ROOT_URLCONF = os.getenv('DJANGO_PROJECT_NAME', 'gohitech') + '.urls'

WSGI_APPLICATION = os.getenv('DJANGO_PROJECT_NAME', 'gohitech') + '.wsgi.application'

# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = os.getenv('DJANGO_SECRET_KEY', '+hzj(tw!bod_*_xh4u2ml!ylbtx6)2r9bqq2i!evjo!x&pay%2')

# https://docs.djangoproject.com/en/1.8/howto/static-files/
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, "static")

# http://docs.celeryproject.org/en/3.1/configuration.html
BROKER_URL = 'amqp://guest:guest@rabbitmq:5672//'
CELERY_ACCEPT_CONTENT = ['pickle', 'json', 'msgpack', 'yaml',]


# Get all Environment variables with a DJANGO_ prefix; remove prefix
#print { k: v for k, v in os.environ.iteritems() if k.startswith('DJANGO_') }
_django_environ = { k[7:]: v for k, v in os.environ.iteritems() if k.startswith('DJANGO_') }
for key in _django_environ:
    try:
        if (key in {'PROJECT_NAME','SETTINGS_MODULE',}) or (key.startswith('DATABASE_')):
            pass
        elif key in {'ADMINS','MANAGERS',}:
            setattr(this_module, key, tuple(literal_eval(_django_environ[key])))
        else:
            setattr(this_module, key, literal_eval(_django_environ[key]))
    except ValueError,e:
        setattr(this_module, key, _django_environ[key])
        #print "ValueError for %s: %s (%s)" % (key,_django_environ[key],str(e))

# Logging

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {
        'console': {
            'class':  'logging.StreamHandler',
            'stream': sys.stdout,
        },
    },
    'loggers': {
        'django': {
            'handlers': ['console',],
            'level':    os.getenv('DJANGO_LOG_LEVEL','INFO'),
        },
    },
}

# Application definition

INSTALLED_APPS = (
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
)
INSTALLED_APPS += ("djcelery", )

MIDDLEWARE_CLASSES = (
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.auth.middleware.SessionAuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'django.middleware.security.SecurityMiddleware',
)

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

# CACHES and Database
# https://docs.djangoproject.com/en/1.8/topics/cache/
# https://docs.djangoproject.com/en/1.8/ref/settings/#databases
# https://hub.docker.com/_/postgres/
if _gethostbyname('memcached'):
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
            'LOCATION': socket.gethostbyname('memcached') + ':11211',
        },
    }
elif _gethostbyname('db'):
    if not _gethostbyname('memcached'):
        CACHES = {
            'default': {
                'BACKEND': 'django.core.cache.backends.db.DatabaseCache',
                'LOCATION': 'cache_table_default',
            },
        }

    if os.getenv('POSTGRES_PASSWORD') is not None:
        DATABASES = {
            'default': {
                'ENGINE':  'django.db.backends.postgresql_psycopg2',
                'NAME':     os.getenv('POSTGRES_DB', os.getenv('POSTGRES_USER','postgres')),
                'USER':     os.getenv('POSTGRES_USER','postgres'),
                'PASSWORD': os.getenv('POSTGRES_PASSWORD'),
                'HOST':     'db',
                'PORT':     '5432',
            },
        }
else:
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.dummy.DummyCache',
        },
    }


# Provide overrides in settings.d/*.py
config_files = glob.glob(os.path.join(os.getenv('DJANGO_PROJECT_NAME', 'gohitech'),'settings.d','*.py'))
#config_files = glob.glob(os.path.join(BASE_DIR,'settings.d','*.py'))
try:
    for config_f in sorted(config_files):
        print "INFO: Execute config file %s" % os.path.abspath(config_f)
        execfile(os.path.abspath(config_f))
except TypeError,e:
    pass

print "djcelery.setup_loader()"
djcelery.setup_loader()
