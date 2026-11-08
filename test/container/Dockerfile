# Image to run the bats unit tests. "make test" builds it locally, and GitHub Actions
# (.github/workflows/test-image.yml) pushes it to Docker Hub as hobbylabs/test-samba-ad-container.
#   docker build -t hobbylabs/test-samba-ad-container test/container
#
# bats is pinned to v1.1.0. Newer bats (>= 1.3) no longer passes extra arguments
# of "load" to helpers.bash ("load helpers /pdc/entrypoint.sh"), which the tests rely on.
FROM bats/bats:v1.1.0
LABEL maintainer="Tsutomu Nakamura<tsuna.0x00@gmail.com>"

# coreutils: tests require GNU coreutils instead of busybox (e.g. base64)
RUN apk update && \
        apk add --update coreutils && \
        apk add git make

ENTRYPOINT ["/usr/bin/env"]
