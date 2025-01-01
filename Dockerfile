

# Configuração para Scala e SBT
FROM amazoncorretto:21.0.5-al2023

# Variáveis de ambiente
ARG SCALA_VERSION=3.3.4
ENV SCALA_VERSION=${SCALA_VERSION}
ARG SBT_VERSION=1.10.5
ENV SBT_VERSION=${SBT_VERSION}
ARG USER_ID=1001
ARG GROUP_ID=1001

# Instalação de dependências
RUN dnf -y update && \
    dnf -y install tar gzip procps git rpm && \
    rm -rf /var/cache/dnf/* && \
    dnf clean all

# Instalação do SBT
RUN curl -fsL "https://github.com/sbt/sbt/releases/download/v$SBT_VERSION/sbt-$SBT_VERSION.tgz" | \
    tar xfz - -C /usr/share && \
    chmod -R 755 /usr/share/sbt && \
    ln -s /usr/share/sbt/bin/sbt /usr/local/bin/sbt

# Instalação do Scala
RUN curl -fsL "https://github.com/scala/scala3/releases/download/$SCALA_VERSION/scala3-$SCALA_VERSION.tar.gz" | \
    tar xfz - -C /usr/share && \
    mv /usr/share/scala3-$SCALA_VERSION /usr/share/scala && \
    chmod -R 755 /usr/share/scala && \
    ln -s /usr/share/scala/bin/* /usr/local/bin

# Criação de usuário para o SBT
RUN groupadd --gid $GROUP_ID sbtuser && useradd -m --gid $GROUP_ID --uid $USER_ID sbtuser --shell /bin/bash
USER sbtuser
WORKDIR /home/sbtuser

# Preparação do ambiente SBT
RUN sbt sbtVersion && \
    mkdir -p project && \
    echo "scalaVersion := \"${SCALA_VERSION}\"" > build.sbt && \
    echo "sbt.version=${SBT_VERSION}" > project/build.properties && \
    sbt compile && \
    rm -r project build.sbt target

# Limpeza final
USER root
RUN rm -rf /tmp/..?* /tmp/.[!.]* && \
    ln -s /home/sbtuser/.cache /root/.cache && \
    ln -s /home/sbtuser/.sbt /root/.sbt && \
    if [ -d "/home/sbtuser/.ivy2" ]; then ln -s /home/sbtuser/.ivy2 /root/.ivy2; fi

CMD ["sbt"]
