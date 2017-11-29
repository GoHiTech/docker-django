# docker-django

[Docker](https://www.docker.com/) image containing a [Django](https://www.djangoproject.com/) based Python framework.

The image uses [Gunicorn](http://gunicorn.org/) a Python WSGI HTTP Server.

# Directory purposes

docker-entrypoint.d/
Dump directory containing any implementation specific Bash shell commands required for the Django image instantiation. All file content will be executed and files will be processed in lexical order. A ".DISABLE" extension will ensure that the content of the file will not be included.

settings.d/
Dump directory containing any implementation specific Django default settings. All files with a ".py" extension will be processed in lexical order.


* Currently supports PostgreSQL Docker image only.
* Postgres application name must be set to "db".
* Default cache
1. Memcached docker image will be used if application name set to "memcached"
2. Database will be used if memcached not present
3. DummyCache will be used if neither memcached or database is present

## Postgres environment variables honoured in Django image

* POSTGRES_PASSWORD
* POSTGRES_DB
* POSTGRES_USER

These must match values passed to the Postgres image. A common environment file could be used.
