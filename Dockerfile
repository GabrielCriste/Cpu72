# Base Jupyter Notebook com suporte a ambiente gráfico e VNC
FROM quay.io/jupyter/base-notebook:2024-12-02

USER root

# Atualização e instalação de pacotes necessários
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
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Configuração do servidor VNC
ARG vncserver=tigervnc
RUN if [ "${vncserver}" = "tigervnc" ]; then \
        apt-get -y -qq update && \
        apt-get -y -qq install tigervnc-standalone-server && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    elif [ "${vncserver}" = "turbovnc" ]; then \
        wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg && \
        wget -O /etc/apt/sources.list.d/TurboVNC.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list && \
        apt-get -y -qq update && \
        apt-get -y -qq install turbovnc && \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

USER $NB_USER

# Instalação de dependências Python
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
