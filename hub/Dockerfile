ARG JUPYTERHUB_VERSION
FROM jupyterhub/k8s-hub:$JUPYTERHUB_VERSION

USER root

RUN pip3 install --upgrade pip

COPY authenticator /app/authenticator
COPY templates /app/templates
WORKDIR /app/authenticator
RUN pip3 install python-pachyderm
RUN pip3 install .

USER ${NB_USER}
WORKDIR /srv/jupyterhub
