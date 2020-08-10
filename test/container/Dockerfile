# docker build -t tsutomu/test-samba-ad-container .
FROM bats/bats:latest
LABEL maintainer "Tsutomu Nakamura<tsuna.0x00@gmail.com>"

RUN apk update && \
        apk add git

COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod u+x /opt/entrypoint.sh

#ENTRYPOINT ["/opt/entrypoint.sh"]

