# docker build -t tsutomu/test-samba-ad-container .
FROM bats/bats:latest
LABEL maintainer "Tsutomu Nakamura<tsuna.0x00@gmail.com>"

RUN apk update && \
        apk add --update coreutils && \
        apk add git make

ENTRYPOINT ["/usr/bin/env"]

