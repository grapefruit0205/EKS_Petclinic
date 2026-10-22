# Petclinic App (Tier 2) — Spring MVC / JSP WAR on Tomcat 11
#
# 빌드 전제: mvnw -B -P MySQL package -DskipTests  → target/petclinic.war
# 이미지 태그: ECR petclinic-app
FROM tomcat:11.0.18-jdk21-temurin

# 기본 예제 웹앱 제거 — 외부 경로 / 와 내부 context / 를 일치시킨다(ROOT.war)
RUN rm -rf "${CATALINA_HOME}/webapps/"*

COPY target/petclinic.war "${CATALINA_HOME}/webapps/ROOT.war"
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# 비-root 실행 사용자 (공식 이미지에는 tomcat 유저가 없다)
RUN groupadd --system --gid 10001 petclinic \
    && useradd --system --uid 10001 --gid petclinic \
       --home-dir "${CATALINA_HOME}" --shell /usr/sbin/nologin petclinic \
    && mkdir -p "${CATALINA_HOME}/work" "${CATALINA_HOME}/temp" "${CATALINA_HOME}/logs" \
       "${CATALINA_HOME}/conf/Catalina/localhost" \
    && chmod 0755 /usr/local/bin/entrypoint.sh \
    && chown -R petclinic:petclinic \
       "${CATALINA_HOME}/work" "${CATALINA_HOME}/temp" \
       "${CATALINA_HOME}/logs" "${CATALINA_HOME}/conf" "${CATALINA_HOME}/webapps"

USER 10001

ENV CATALINA_TMPDIR=/usr/local/tomcat/temp

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
