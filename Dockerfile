# Início do Dockerfile base
FROM quay.io/jupyter/base-notebook:2024-12-02

USER root

# Atualiza e instala pacotes necessários para ambiente gráfico e servidor VNC
RUN apt-get -y -qq update \
 && apt-get -y -qq install \
        dbus-x11 \
        xclip \
        xfce4 \
        xfce4-panel \
        xfce4-session \
        xfce4-settings \
        xorg \
        xubuntu-icon-theme \
        fonts-dejavu \
 && apt-get -y -qq remove xfce4-screensaver \
 && mkdir -p /opt/install \
 && chown -R $NB_UID:$NB_GID $HOME /opt/install \
 && rm -rf /var/lib/apt/lists/*

# Instala o servidor VNC
ARG vncserver=tigervnc
RUN if [ "${vncserver}" = "tigervnc" ]; then \
        echo "Installing TigerVNC"; \
        apt-get -y -qq update; \
        apt-get -y -qq install tigervnc-standalone-server; \
        rm -rf /var/lib/apt/lists/*; \
    fi

USER $NB_USER

# Garante permissões corretas para o cache do Conda
RUN mkdir -p /home/jovyan/.cache/conda && \
    chown -R $NB_UID:$NB_GID /home/jovyan/.cache/conda

# Instala ambiente Conda e dependências Python
COPY --chown=$NB_UID:$NB_GID environment.yml /tmp
RUN . /opt/conda/bin/activate && \
    mamba env update --quiet --file /tmp/environment.yml

COPY --chown=$NB_UID:$NB_GID . /opt/install
RUN . /opt/conda/bin/activate && \
    mamba install -y -q "nodejs>=22" && \
    pip install /opt/install
    

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
