FROM eclipse-temurin:21

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates bash unzip && \
    rm -rf /var/lib/apt/lists/*

# JBang to /opt/jbang (the zip extracts to that path)
RUN curl -L https://github.com/jbangdev/jbang/releases/latest/download/jbang.zip -o /tmp/jbang.zip && \
    unzip -q /tmp/jbang.zip -d /opt && \
    rm /tmp/jbang.zip && \
    ln -s /opt/jbang/bin/jbang /usr/local/bin/jbang

# Numeric UID so k8s runAsNonRoot can verify it
RUN useradd -m -u 1001 -s /bin/bash app
USER 1001
WORKDIR /home/app

# Preload jbang + maven caches from the build context so 'camel run'
# does not need to download anything. scripts/build-image.sh populates
# jbang-cache/ and m2-cache/ from $HOME/.jbang and $HOME/.m2.
COPY --chown=1001:1001 jbang-cache /home/app/.jbang
COPY --chown=1001:1001 m2-cache    /home/app/.m2

ENV PATH="/home/app/.jbang/bin:$PATH"
ENV JBANG_NO_VERSION_CHECK=1

COPY --chown=1001:1001 process.camel.yaml application.properties openapi.json /home/app/

# Mock-DB storage. K8s deployment can mount an emptyDir / PVC over /home/app/data
# to give the file pod-lifetime (or longer) persistence.
RUN mkdir -p /home/app/data && touch /home/app/data/users.jsonl

EXPOSE 8080
CMD ["camel", "run", "process.camel.yaml"]
