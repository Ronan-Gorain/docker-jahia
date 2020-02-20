FROM tomcat:9.0

MAINTAINER Jahia Devops team <paas@jahia.com>

ARG BASE_URL="http://downloads.jahia.com/downloads/jahia/jahia7.3.4/Jahia-EnterpriseDistribution-7.3.4.1-r60321.4663.jar"
ARG PROCESSING_SERVER="true"
ARG OPERATING_MODE="production"
ARG XMX="2G"
ARG MAX_UPLOAD="268435456"
ARG SUPER_USER_PASSWORD="root"
ARG LIBREOFFICE="false"
ARG FFMPEG="false"
ARG DEBUG_TOOLS="false"
ARG DBMS_TYPE="mariadb"
ARG DB_HOST="mariadb"
ARG DB_NAME="jahia"
ARG DB_USER="root"
ARG DB_PASS="hophop"
ARG JMANAGER_USER="manager"
ARG JMANAGER_PASS="password"
ARG MODULES_BASE_URL="https://store.jahia.com/cms/mavenproxy/private-app-store/org/jahia/modules"
ARG HEALTHCHECK_VER="1.0.10"
ARG MAVEN_VER="3.6.3"

ENV FACTORY_DATA="/data/digital-factory-data"
ENV FACTORY_CONFIG="/usr/local/tomcat/conf/digital-factory-config"
ENV PROCESSING_SERVER="$PROCESSING_SERVER"
ENV OPERATING_MODE="$OPERATING_MODE"
ENV XMX="$XMX" MAX_UPLOAD="$MAX_UPLOAD"

ENV CATALINA_BASE="/usr/local/tomcat" CATALINA_HOME="/usr/local/tomcat" CATALINA_TMPDIR="/usr/local/tomcat/temp"

ENV DBMS_TYPE="$DBMS_TYPE" DB_HOST="$DB_HOST" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASS="$DB_PASS"
ENV JMANAGER_USER="$JMANAGER_USER" JMANAGER_PASS="$JMANAGER_PASS" SUPER_USER_PASSWORD="$SUPER_USER_PASSWORD"

ENV KARAF_SHELL_PORT="8101"


ADD config_mariadb.xml /tmp
ADD config_postgresql.xml /tmp
ADD entrypoint.sh /
WORKDIR /tmp



ADD installer.jar /tmp
ADD maven.zip /tmp



ADD reset-jahia-tools-manager-password.py /usr/local/bin


RUN apt update \
    && packages="imagemagick python3 jq ncat" \
    && if $DEBUG_TOOLS; then \
        packages="$packages vim binutils"; \
       fi \
    && if $LIBREOFFICE; then \
        packages="$packages libreoffice"; \
       fi \
    && if $FFMPEG; then \
        packages="$packages ffmpeg"; \
       fi \
    && apt-get install -y --no-install-recommends \
        $packages \
    && rm -rf /var/lib/apt/lists/*

RUN printf 'hop hop hop\n' \
    #&& wget --progress=dot:giga -O installer.jar $BASE_URL \
    #&& wget --progress=dot:giga -O maven.zip https://mirrors.ircam.fr/pub/apache/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.zip \
    && sed -e 's/${MAVEN_VER}/'$MAVEN_VER'/' \
        #-e 's,${LICENSE_PATH},'$FACTORY_CONFIG/jahia/license.xml',' \
        -i /tmp/config_$DBMS_TYPE.xml \
    && java -jar installer.jar config_$DBMS_TYPE.xml \
    && unzip -q maven.zip -d /opt \
    && rm -f installer.jar config_*.xml maven.zip \
    && mv /data/jahia/tomcat/webapps/* /usr/local/tomcat/webapps \
    && mv /data/jahia/tomcat/lib/* /usr/local/tomcat/lib/ \
    && echo 'export JAVA_OPTS="$JAVA_OPTS -DDB_HOST=$DB_HOST -DDB_PASS=$DB_PASS -DDB_NAME=$DB_NAME -DDB_USER=$DB_USER"' \
                >> /usr/local/tomcat/bin/setenv.sh \
    && chmod +x /usr/local/tomcat/bin/setenv.sh \
    && chmod +x /entrypoint.sh \
    && sed -e "s#common.loader=\"\\\$#common.loader=\"/usr/local/tomcat/conf/digital-factory-config\",\"\$#g" \
        -i /usr/local/tomcat/conf/catalina.properties \
    && echo

ADD $MODULES_BASE_URL/healthcheck/$HEALTHCHECK_VER/healthcheck-$HEALTHCHECK_VER.jar \
        $FACTORY_DATA/modules/healthcheck-$HEALTHCHECK_VER.jar


EXPOSE 8080
EXPOSE 7860
EXPOSE 7870

HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=600s \
            --retries=3 \
            CMD jsonhealth=$(curl http://localhost:8080/healthcheck -s -u root:$SUPER_USER_PASSWORD); \
                exitcode=$?; \
                if (test $exitcode -ne 0); then \
                    echo "cURL's exit code: $exitcode"; \
                    exit 1; \
                fi; \
                echo $jsonhealth; \
                if (test "$(echo $jsonhealth | jq -r '.status')" = "RED"); then \
                    exit 1; \
                else \
                    exit 0; \
                fi

CMD /entrypoint.sh