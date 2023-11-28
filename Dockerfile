## Global Args #################################################################
ARG BASE_UBI_IMAGE_TAG=9.3-1361.1699548029
ARG PROTOC_VERSION=25.0
ARG PYTORCH_INDEX="https://download.pytorch.org/whl"
#ARG PYTORCH_INDEX="https://download.pytorch.org/whl/nightly"
ARG PYTORCH_VERSION=2.1.0

## Base Layer ##################################################################
FROM registry.access.redhat.com/ubi9/ubi:${BASE_UBI_IMAGE_TAG} as base
WORKDIR /app

RUN dnf remove -y --disableplugin=subscription-manager \
        subscription-manager \
        # we install newer version of requests via pip
        python3.11-requests \
    && dnf install -y make \
        # to help with debugging
        procps \
    && dnf clean all

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8


## Rust builder ################################################################
# Specific debian version so that compatible glibc version is used
FROM rust:1.73-bullseye as rust-builder
ARG PROTOC_VERSION

ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse

# Install protoc, no longer included in prost crate
RUN cd /tmp && \
    curl -L -O https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip && \
    unzip protoc-*.zip -d /usr/local && rm protoc-*.zip

WORKDIR /usr/src

COPY rust-toolchain.toml rust-toolchain.toml

RUN rustup component add rustfmt

## Internal router builder #####################################################
FROM rust-builder as router-builder

COPY proto proto
COPY router router

WORKDIR /usr/src/router

#RUN --mount=type=cache,target=/root/.cargo --mount=type=cache,target=/usr/src/router/target cargo install --path .
RUN cargo install --path .

## Launcher builder ############################################################
FROM rust-builder as launcher-builder

COPY launcher launcher

WORKDIR /usr/src/launcher

#RUN --mount=type=cache,target=/root/.cargo --mount=type=cache,target=/usr/src/launcher/target cargo install --path .
RUN cargo install --path .

## Tests base ##################################################################
FROM base as test-base

RUN dnf install -y make unzip python3.11 python3.11-pip gcc openssl-devel gcc-c++ && \
    dnf clean all && \
    ln -fs /usr/bin/python3.11 /usr/bin/python3 && \
    ln -s /usr/bin/python3.11 /usr/local/bin/python && ln -s /usr/bin/pip3.11 /usr/local/bin/pip

RUN pip install --upgrade pip && pip install pytest && pip install pytest-asyncio

# CPU only
ENV CUDA_VISIBLE_DEVICES=""

## Tests #######################################################################
FROM test-base as cpu-tests
ARG PYTORCH_INDEX
ARG PYTORCH_VERSION
ARG SITE_PACKAGES=/usr/local/lib/python3.11/site-packages

WORKDIR /usr/src

# Install specific version of torch
RUN pip install torch=="$PYTORCH_VERSION+cpu" --index-url "${PYTORCH_INDEX}/cpu" --no-cache-dir

COPY server/Makefile server/Makefile

# Install server
COPY proto proto
COPY server server
RUN cd server && \
    make gen-server && \
    pip install ".[accelerate]" --no-cache-dir

# Patch codegen model changes into transformers 4.34
RUN cp server/transformers_patch/modeling_codegen.py ${SITE_PACKAGES}/transformers/models/codegen/modeling_codegen.py

# Install router
COPY --from=router-builder /usr/local/cargo/bin/text-generation-router /usr/local/bin/text-generation-router
# Install launcher
COPY --from=launcher-builder /usr/local/cargo/bin/text-generation-launcher /usr/local/bin/text-generation-launcher

# Install integration tests
COPY integration_tests integration_tests
RUN cd integration_tests && make install

## Python builder #############################################################

FROM test-base as server-release

ARG PYTORCH_INDEX
ARG PYTORCH_VERSION

RUN cd ~ && \
    curl -L -O https://repo.anaconda.com/miniconda/Miniconda3-py311_23.9.0-0-Linux-x86_64.sh && \
    chmod +x Miniconda3-*-Linux-x86_64.sh && \
    bash ./Miniconda3-*-Linux-x86_64.sh -bf -p /opt/miniconda

ENV PATH=/opt/miniconda/bin:$PATH

ARG SITE_PACKAGES=/opt/miniconda/lib/python3.11/site-packages

RUN useradd -u 2000 tgis -m -g 0

SHELL ["/bin/bash", "-c"]

ENV PATH=/opt/miniconda/bin:$PATH

# These could instead come from explicitly cached images

# Install server
COPY proto proto
COPY server server
RUN cd server && make gen-server && pip install ".[accelerate, openvino]" --no-cache-dir && pip uninstall -y openvino && pip install openvino-nightly

# Patch codegen model changes into transformers 4.34.0
RUN cp server/transformers_patch/modeling_codegen.py ${SITE_PACKAGES}/transformers/models/codegen/modeling_codegen.py

# Install router
COPY --from=router-builder /usr/local/cargo/bin/text-generation-router /usr/local/bin/text-generation-router
# Install launcher
COPY --from=launcher-builder /usr/local/cargo/bin/text-generation-launcher /usr/local/bin/text-generation-launcher

ENV PORT=3000 \
    GRPC_PORT=8033 \
    HOME=/home/tgis

# Runs as arbitrary user in OpenShift
RUN chmod -R g+rwx ${HOME}

# Temporary for dev
RUN chmod -R g+w ${SITE_PACKAGES}/text_generation_server /usr/src /usr/local/bin

# Run as non-root user by default
USER tgis

EXPOSE ${PORT}
EXPOSE ${GRPC_PORT}

CMD text-generation-launcher
