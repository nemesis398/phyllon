# The two FROM lines below are the only places that name a base image. They are
# literal, with the tag and the digest of the multi-arch index (so the build is
# the same on amd64 and arm64), because Dependabot reads only literal FROM
# lines: it does not resolve a FROM that uses an ARG, and it needs the tag to
# know which release to track. Phase 2's move to gcr.io/distroless/cc edits the
# second line.
FROM docker.io/library/rust:1.99.1-alpine@sha256:b1d5dd5a22a09404d3e798c0cf051b689077360374eb505fa5bb93c479693d87 AS builder

RUN apk add --no-cache musl-dev

# cargo-auditable writes the crate list into the binary, in the .dep-v0
# section, so a scanner can read it from the shipped file. 0.7.7 is the newest
# release that was at least 7 days old on 2026-10-30 (released 2026-10-02,
# MIT OR Apache-2.0).
RUN cargo install --locked cargo-auditable@0.7.7

# The image ships the toolchain that rust-toolchain.toml pins. The file itself
# stays out of the build directory: rustup would read it, find clippy and
# rustfmt missing from this image, and download them. The check fails the build
# if the builder image and the pin ever drift apart. The match is a fixed
# string on a whole line, so a comment or a pattern character cannot pass it,
# and an empty version finds no line and fails.
COPY rust-toolchain.toml /tmp/rust-toolchain.toml
RUN grep -qxF "channel = \"$(rustc --version | cut -d' ' -f2)\"" /tmp/rust-toolchain.toml

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

FROM gcr.io/distroless/static-debian13:nonroot@sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99

COPY --from=builder /build/target/release/phyllon /usr/local/bin/phyllon

# The image sets neither PHYLLON_CONFIG nor a HEALTHCHECK. The compose file and
# the Quadlet unit supply both.
# 65532 is the nonroot user of distroless. The number lets Kubernetes verify
# runAsNonRoot, which it cannot do with a name.
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/phyllon"]
CMD ["serve"]
