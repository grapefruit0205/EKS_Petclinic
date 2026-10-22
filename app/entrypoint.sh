#!/bin/bash
# Petclinic App 엔트리포인트
#
#  - DB 접속 설정은 외부 파일(/etc/petclinic/data-access.properties)에서만 읽는다.
#    (datasource-config.xml 의 property-placeholder 에 file: 위치를 추가했다)
#  - Secret 이 주입되지 않으면 classpath 기본값(localhost)으로 조용히 뜨지 않고 fail-fast 한다.
#  - 셸 특수문자가 포함된 비밀번호가 catalina.sh 의 eval 을 깨뜨리지 않도록
#    비밀번호는 셸 옵션이 아니라 파일로만 전달한다.
set -euo pipefail

CONFIG_FILE=/etc/petclinic/data-access.properties

if [ ! -r "$CONFIG_FILE" ]; then
  echo "FATAL: $CONFIG_FILE is missing. Refusing to start with default datasource config." >&2
  exit 1
fi

export CATALINA_OPTS="${JVM_OPTS:--XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError}"

exec catalina.sh run
