FROM alpine
MAINTAINER David Steiman (adinatbust@gmail.com)
RUN apk add --update ca-certificates \
 && apk add --update -t deps curl \
 && curl -L https://storage.googleapis.com/kubernetes-release/release/v1.13.4/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl \
 && apk del --purge deps \
 && rm /var/cache/apk/* \
 && apk add --update bash && rm -rf /var/cache/apk/*

ENV DAEMON_MODE=0 \
    BACKUP_DIR=/backups \
    NAMESPACE=default

ADD ./back-up.sh /back-up.sh
ADD ./k8s-psql-tool.sh /k8s-psql-tool.sh

CMD /back-up.sh
