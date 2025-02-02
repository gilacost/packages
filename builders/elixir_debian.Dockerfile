# -*- mode: dockerfile -*-
# syntax = docker/dockerfile:1.2
ARG image
FROM ${image} as builder
ARG os
ARG os_version

ENV DEBIAN_FRONTEND=noninteractive

# Setup ESL repo
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/lib/apt,sharing=private \
    apt-get --quiet update && \
    apt-get --quiet --yes --no-install-recommends install \
    build-essential \
    ca-certificates \
    git \
    gnupg \
    wget && \
    wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && \
    dpkg -i erlang-solutions_2.0_all.deb

# Install Erlang/OTP
ARG erlang_version
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/lib/apt,sharing=private \
    apt-get --quiet update && \
    apt-get --quiet --yes --no-install-recommends install \
    esl-erlang=1:${erlang_version}

# Install FPM dependencies
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/apt,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/lib/apt,sharing=private \
    apt-get --quiet update && apt-get --quiet --yes --no-install-recommends install \
    ruby \
    ruby-dev

# Install FPM
RUN if [ "${os}:${os_version}" = "ubuntu:trusty" ]; then \
    gem install json --no-rdoc --no-ri --version 2.2.0; \
    gem install ffi --no-rdoc --no-ri --version 1.9.25; \
    gem install fpm --no-rdoc --no-ri --version 1.11.0; \
    else \
    gem install fpm --no-document --version 1.13.0; \
    fi

ENV LANG=C.UTF-8

# Build and test it
WORKDIR /tmp/build
ARG elixir_version
RUN wget --quiet https://github.com/elixir-lang/elixir/archive/v${elixir_version}.tar.gz
RUN tar xf v${elixir_version}.tar.gz
WORKDIR /tmp/build/elixir-${elixir_version}
RUN make
RUN make test
RUN make install PREFIX=/usr DESTDIR=/tmp/install

# Package it
WORKDIR /tmp/output
ARG elixir_iteration
RUN fpm -s dir -t deb \
    --chdir /tmp/install \
    --name elixir \
    --version ${elixir_version} \
    --package-name-suffix ${os_version} \
    --epoch 1 \
    --iteration ${elixir_iteration} \
    --package elixir_VERSION-ITERATION_ARCH.deb \
    --maintainer "Erlang Solutions Ltd <support@erlang-solutions.com>" \
    --description "Elixir functional meta-programming language" \
    --url "https://erlang-solutions.com" \
    --architecture "all" \
    --depends "esl-erlang >= ${erlang_version}" \
    $(if [ "${os}:${os_version}" != "ubuntu:trusty" ]; then echo '--deb-compression xz'; fi) \
    .

# Export it
FROM scratch
COPY --from=builder /tmp/output /
