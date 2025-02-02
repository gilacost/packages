# -*- mode: dockerfile -*-
# syntax = docker/dockerfile:1.2
ARG image
FROM ${image} as builder
ARG os
ARG os_version
ADD yumdnf /usr/local/bin/

# Setup EPEL
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
    if [ "${os}" = "centos" -o "${os}" = "almalinux" -o "${os}" = "rockylinux" ]; then \
    yumdnf install -y epel-release; \
    fi

# Install Erlang/OTP dependencies
RUN --mount=type=cache,id=${os}_${os_version},target=/var/cache/dnf,sharing=private \
    --mount=type=cache,id=${os}_${os_version},target=/var/cache/yum,sharing=private \
    yumdnf install -y \
    autoconf \
    automake \
    bison \
    flex \
    gcc \
    gcc-c++ \
    git \
    java-11-openjdk-devel \
    libxslt-devel \
    libxslt \
    lksctp-tools-devel \
    make \
    ncurses-devel \
    openssl \
    openssl-devel \
    unixODBC-devel \
    wget \
    wxGTK3-devel \
    zlib-devel

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

# Build it
WORKDIR /tmp/build
ARG erlang_version
RUN wget --quiet https://github.com/erlang/otp/releases/download/OTP-${erlang_version}/otp_src_${erlang_version}.tar.gz
RUN tar xf otp_src_${erlang_version}.tar.gz
ENV ERL_TOP=/tmp/build/otp_src_${erlang_version}
WORKDIR $ERL_TOP
RUN if [ ! -f configure ]; then \
    ./otp_build autoconf; \
    fi
ENV CFLAGS="-g -O2 -fstack-protector-strong"
ENV LDFLAGS="-Wl,-z,relro"
RUN ./configure \
    --prefix=/usr \
    --enable-dirty-schedulers \
    --enable-dynamic-ssl-lib \
    --enable-kernel-poll \
    --enable-sctp \
    --with-java \
    --with-ssl

ARG jobs
RUN make --jobs=${jobs}

# Test it
RUN make --jobs=${jobs} release_tests
WORKDIR $ERL_TOP/release/tests/test_server
RUN $ERL_TOP/bin/erl -noshell -s ts install -s ts smoke_test batch -s init stop
RUN if grep -q '=failed *[1-9]' ct_run.test_server@*/*/run.*/suite.log; then \
    echo "One or more tests failed."; \
    grep -C 10 '=result *failed:' ct_run.test_server@*/*/run.*/suite.log; \
    exit 1; \
    fi

WORKDIR $ERL_TOP
RUN make --jobs=${jobs} docs DOC_TARGETS="chunks man"
RUN mkdir -p /tmp/install
RUN make --jobs=${jobs} DESTDIR=/tmp/install install
RUN make --jobs=${jobs} DESTDIR=/tmp/install install-docs DOC_TARGETS="chunks man"

# Package it
WORKDIR /tmp/output
ARG erlang_iteration
ADD determine-license /usr/local/bin
RUN fpm -s dir -t rpm \
    --chdir /tmp/install \
    --name esl-erlang \
    --version ${erlang_version} \
    --package-name-suffix ${os_version} \
    --epoch 1 \
    --iteration ${erlang_iteration} \
    --package esl-erlang_VERSION_ITERATION~${os}~${os_version}_ARCH.rpm \
    --category interpreters \
    --description "Concurrent, real-time, distributed functional language" \
    --url "https://erlang-solutions.com" \
    --license "$(determine-license ${erlang_version})" \
    --depends 'openssl-libs' \
    --provides "erlang = ${erlang_version}-${erlang_iteration}" \
    --provides "erlang-erts = ${erlang_version}-${erlang_iteration}" \
    --provides "erlang-inets = ${erlang_version}-${erlang_iteration}" \
    .

# Test install
FROM ${image} as install

WORKDIR /tmp/output
COPY --from=builder /tmp/output .
ADD yumdnf /usr/local/bin/

RUN yumdnf install -y ./*.rpm
RUN erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().'  -noshell

# Export it
FROM scratch
COPY --from=install /tmp/output /
