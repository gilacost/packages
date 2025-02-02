# -*- mode: dockerfile -*-
# syntax = docker/dockerfile:1.2
ARG image
FROM ${image} as builder
ARG os
ARG os_version
ADD yumdnf /usr/local/bin/

# Setup ESL repo
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
    yumdnf install -y \
    git \
    wget && \
    wget https://packages.erlang-solutions.com/erlang-solutions-2.0-1.noarch.rpm && \
    rpm -Uvh erlang-solutions-2.0-1.noarch.rpm

# Setup EPEL
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
    if [ "${os}" = "centos" -o "${os}" = "almalinux" ]; then \
    yumdnf install -y epel-release; \
    fi

# Install Erlang/OTP
ARG erlang_version
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
    yumdnf install -y \
    esl-erlang-${erlang_version}

# Install FPM dependences
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
    yumdnf install -y \
    ruby-devel \
    gcc \
    make \
    rpm-build \
    libffi-devel

# Install FPM
RUN if [ "${os}:${os_version}" = "centos:7" -o "${os}:${os_version}" = "amazonlinux:2" ]; then \
    gem install git --no-document --version 1.7.0; \
    gem install fpm --no-document --version 1.12.0; \
    else \
    gem install fpm --no-document --version 1.13.0; \
    fi

# Ensure UTF-8 locale
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
    if [ "${os}:${os_version}" = "centos:8" ]; then \
    yumdnf install -y glibc-locale-source && \
    localedef -i en_US -f UTF-8 en_US.UTF-8; \
    fi
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Build it
WORKDIR /tmp/build
ARG elixir_version
RUN wget --quiet https://github.com/elixir-lang/elixir/archive/v${elixir_version}.tar.gz
RUN tar xf v${elixir_version}.tar.gz
RUN ls -lhR
WORKDIR /tmp/build/elixir-${elixir_version}
RUN make
RUN make test
RUN make install PREFIX=/usr DESTDIR=/tmp/install

# Package it
WORKDIR /tmp/output
ARG elixir_iteration
RUN fpm -s dir -t rpm \
    --chdir /tmp/install \
    --name elixir \
    --version ${elixir_version} \
    --package-name-suffix ${os_version} \
    --epoch 1 \
    --iteration ${elixir_iteration} \
    --package elixir_VERSION_ITERATION_ARCH.rpm \
    --maintainer "Erlang Solutions Ltd <support@erlang-solutions.com>" \
    --description "Elixir functional meta-programming language" \
    --url "https://erlang-solutions.com" \
    --architecture "all" \
    --depends "esl-erlang >= ${erlang_version}" \
    .

# Test install
FROM ${image} as install

WORKDIR /tmp/output
COPY --from=builder /tmp/output .
ADD yumdnf /usr/local/bin/

RUN yumdnf install -y ./*.rpm
RUN elixir -v

# Export it
FROM scratch
COPY --from=install /tmp/output /
