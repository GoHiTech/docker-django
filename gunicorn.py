import os

#accesslog = 
#disable_redirect_access_to_syslog = True
#logconfig_dict = {
#    "version": 1,
#    "formatters": {
#        "json": {
#            "class": jsonlogging.JSONFormatter
#        },
#    },
#    "root": {
#        "level": "INFO",
#        "handlers": "console",
#    },
#}

for k,v in os.environ.items():
    if k.startswith("GUNICORN_"):
        if k in ('GUNICORN_ENABLE','GUNICORN_CMD_ARGS'):
            continue
        key = k.split('_',1)[1].lower()
        locals()[key] = v
