# The base images, in one place. Each is pinned by the digest of its multi-arch
# index, so the build is the same on amd64 and arm64. The comment above each
# line names the tag the digest belongs to (Dockerfile syntax allows no comment
# after a value). Phase 2 may move the final stage to gcr.io/distroless/cc, and
# this is the only place that changes.

# docker.io/library/rust:1.99.1-alpine
ARG BUILDER_IMAGE=docker.io/library/rust@sha256:b1d5dd5a22a09404d3e798c0cf051b689077360374eb505fa5bb93c479693d87
# gcr.io/distroless/static-debian13:nonroot
ARG RUNTIME_IMAGE=gcr.io/distroless/static-debian13@sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99

FROM ${BUILDER_IMAGE} AS builder

RUN apk add --no-cache musl-dev

# cargo-auditable writes the crate list into the binary, in the .dep-v0
# section, so a scanner can read it from the shipped file. 0.7.7 is the newest
# release that was at least 7 days old on 2026-10-30 (released 2026-10-02,
# MIT OR Apache-2.0).
RUN cargo install --locked cargo-auditable@0.7.7

# The image ships the toolchain that rust-toolchain.toml pins. The file itself
# stays out of the build directory: rustup would read it, find clippy and
# rustfmt missing from this image, and download them. The check fails the build
# if the builder image and the pin ever drift apart.
COPY rust-toolchain.toml /tmp/rust-toolchain.toml
RUN grep -q "channel = \"$(rustc --version | cut -d' ' -f2)\"" /tmp/rust-toolchain.toml

WORKDIR /build

# Build the dependencies first, against an empty crate. This layer changes only
# with Cargo.toml and Cargo.lock, so a change in src/ does not compile them
# again.
COPY Cargo.toml Cargo.lock ./
RUN mkdir src \
    && : > src/lib.rs \
    && echo 'fn main() {}' > src/main.rs \
    && cargo auditable build --release --locked

# The commit goes in at compile time (see BuildInfo::current). It is declared
# only here so that a new commit does not invalidate the layers above. An
# unset or empty argument is unset again, because an empty value would count
# as a commit.
ARG PHYLLON_GIT_COMMIT
COPY src ./src
RUN find src -name '*.rs' -exec touch {} + \
    && if [ -z "$PHYLLON_GIT_COMMIT" ]; then unset PHYLLON_GIT_COMMIT; else export PHYLLON_GIT_COMMIT; fi \
    && cargo auditable build --release --locked

FROM ${RUNTIME_IMAGE}

COPY --from=builder /build/target/release/phyllon /usr/local/bin/phyllon

# The image sets neither PHYLLON_CONFIG nor a HEALTHCHECK. The compose file and
# the Quadlet unit supply both.
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/phyllon"]
CMD ["serve"]
