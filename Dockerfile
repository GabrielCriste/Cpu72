# Início do Dockerfile base
FROM quay.io/jupyter/base-notebook:2024-12-29

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
        apt-get -y -qq install \
            tigervnc-standalone-server \
        ; \
        rm -rf /var/lib/apt/lists/*; \
    fi
ENV PATH=/opt/TurboVNC/bin:$PATH
RUN if [ "${vncserver}" = "turbovnc" ]; then \
        echo "Installing TurboVNC"; \
        wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | \
        gpg --dearmor >/etc/apt/trusted.gpg.d/TurboVNC.gpg; \
        wget -O /etc/apt/sources.list.d/TurboVNC.list https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list; \
        apt-get -y -qq update; \
        apt-get -y -qq install \
            turbovnc \
        ; \
        rm -rf /var/lib/apt/lists/*; \
    fi

USER $NB_USER

# Instala ambiente Conda e dependências Python
COPY --chown=$NB_UID:$NB_GID environment.yml /tmp
RUN . /opt/conda/bin/activate && \
    mamba env update --quiet --file /tmp/environment.yml

COPY --chown=$NB_UID:$NB_GID . /opt/install
RUN . /opt/conda/bin/activate && \
    mamba install -y -q "nodejs>=22" && \
    pip install /opt/install

# Configuração do Scala e SBT
ARG BASE_IMAGE_TAG
FROM amazoncorretto:${BASE_IMAGE_TAG:-21.0.5-al2023}

# Variáveis de ambiente
ARG SCALA_VERSION
ENV SCALA_VERSION=${SCALA_VERSION:-3.3.4}
ARG SBT_VERSION
ENV SBT_VERSION=${SBT_VERSION:-1.10.5}
ARG USER_ID
ENV USER_ID=${USER_ID:-1001}
ARG GROUP_ID
ENV GROUP_ID=${GROUP_ID:-1001}

# Instala dependências para SBT
RUN \
  dnf -y update && \
  dnf -y install tar gzip procps git rpm && \
  rm -rf /var/cache/dnf/* && \
  dnf clean all

# Instala SBT
RUN \
  curl -fsL --show-error "https://github.com/sbt/sbt/releases/download/v$SBT_VERSION/sbt-$SBT_VERSION.tgz" | tar xfz - -C /usr/share && \
  chown -R root:root /usr/share/sbt && \
  chmod -R 755 /usr/share/sbt && \
  ln -s /usr/share/sbt/bin/sbt /usr/local/bin/sbt

# Instala Scala
RUN \
  case $SCALA_VERSION in \
    2.*) URL=https://downloads.typesafe.com/scala/$SCALA_VERSION/scala-$SCALA_VERSION.tgz SCALA_DIR=/usr/share/scala-$SCALA_VERSION ;; \
    *) URL=https://github.com/scala/scala3/releases/download/$SCALA_VERSION/scala3-$SCALA_VERSION.tar.gz SCALA_DIR=/usr/share/scala3-$SCALA_VERSION ;; \
  esac && \
  curl -fsL --show-error $URL | tar xfz - -C /usr/share/ && \
  mv $SCALA_DIR /usr/share/scala && \
  chown -R root:root /usr/share/scala && \
  chmod -R 755 /usr/share/scala && \
  ln -s /usr/share/scala/bin/* /usr/local/bin && \
  mkdir -p /test && \
  case $SCALA_VERSION in \
    2*) echo "println(util.Properties.versionMsg)" > /test/test.scala ;; \
    *) echo 'import java.io.FileInputStream;import java.util.jar.JarInputStream;val scala3LibJar = classOf[CanEqual[_, _]].getProtectionDomain.getCodeSource.getLocation.toURI.getPath;val manifest = new JarInputStream(new FileInputStream(scala3LibJar)).getManifest;val ver = manifest.getMainAttributes.getValue("Implementation-Version");@main def main = println(s"Scala version ${ver}")' > /test/test.scala ;; \
  esac && \
  scala -nocompdaemon test/test.scala && \
  rm -fr test

# Symlink java
RUN ln -s /opt/java/openjdk/bin/java /usr/local/bin/java

# Criação de usuário sbtuser
RUN groupadd --gid $GROUP_ID sbtuser && useradd -m --gid $GROUP_ID --uid $USER_ID sbtuser --shell /bin/bash
USER sbtuser

# Trabalhar no diretório sbtuser
WORKDIR /home/sbtuser

# Preparação do sbt
RUN \
  sbt --script-version && \
  mkdir -p project && \
  echo "scalaVersion := \"${SCALA_VERSION}\"" > build.sbt && \
  echo "sbt.version=${SBT_VERSION}" > project/build.properties && \
  echo "// force sbt compiler-bridge download" > project/Dependencies.scala && \
  echo "case object Temp" > Temp.scala && \
  sbt compile && \
  rm -r project && rm build.sbt && rm Temp.scala && rm -r target

# Link de diretórios para o root
USER root
RUN \
  rm -rf /tmp/..?* /tmp/.[!.]* * && \
  ln -s /home/sbtuser/.cache /root/.cache && \
  ln -s /home/sbtuser/.sbt /root/.sbt && \
  if [ -d "/home/sbtuser/.ivy2" ]; then ln -s /home/sbtuser/.ivy2 /root/.ivy2; fi

# Trabalhar como root novamente
WORKDIR /root

# Comando final para iniciar o sbt
CMD ["sbt"]
