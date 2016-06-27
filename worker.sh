#!/bin/bash

# @author Michal Karm Babacek

# Debug logging
echo "STAT: `networkctl status`" | tee /opt/worker/ip.log
echo "STAT ${WORKER_NIC:-eth0}: `networkctl status ${WORKER_NIC:-eth0}`" | tee /opt/worker/ip.log

# Wait for the interface to wake up
TIMEOUT=20
MYIP=""
while [[ "${MYIP}X" == "X" ]] && (( "${TIMEOUT}" > 0 )); do
    echo "Loop ${TIMEOUT}" | tee /opt/worker/ip.log
    MYIP="`networkctl status ${WORKER_NIC:-eth0} | awk '{if($1~/Address:/){printf($2);}}' | tr -d '[[:space:]]'`"
    export MYIP
    echo "MYIP is $MYIP" | tee /opt/worker/ip.log
    let TIMEOUT=$TIMEOUT-1
    if [[ "${MYIP}X" != "X" ]]; then break; else sleep 1; fi
done
echo -e "MYIP: ${MYIP}\nMYNIC: ${WORKER_NIC:-eth0}" | tee /opt/worker/ip.log
if [[ "${MYIP}X" == "X" ]]; then 
    echo "${WORKER_NIC:-eth0} Interface error. " | tee /opt/worker/ip.log
    exit 1
fi


# Tomcat runtime setup
CONTAINER_NAME=`echo ${DOCKERCLOUD_CONTAINER_FQDN}|sed 's/\([^\.]*\.[^\.]*\).*/\1/g'`
if [ "`echo \"${CONTAINER_NAME}\" | wc -c`" -gt 24 ]; then
    echo "ERROR: CONTAINER_NAME ${CONTAINER_NAME} must be up to 24 characters long."
    exit 1
fi

export JAVA_OPTS="-server \
                  -Xms${WORKER_MS_RAM:-512m} \
                  -Xmx${WORKER_MX_RAM:-512m} \
                  -XX:MetaspaceSize=96M \
                  -XX:MaxMetaspaceSize=256m \
                  -Djava.net.preferIPv4Stack=true \
                  -Djava.awt.headless=true \
                  -XX:+HeapDumpOnOutOfMemoryError \
                  -XX:HeapDumpPath=/opt/worker \
                  -Djava.security.egd=${WORKER_RNG:-file:///dev/random}"

# Configure

sed -i "s/@WORKER_LOAD_METRIC@/${WORKER_LOAD_METRIC:-BusyConnectorsLoadMetric}/g" ${CATALINA_HOME}/conf/server.xml
sed -i "s/@WORKER_LOAD_CAPACITY@/${WORKER_LOAD_CAPACITY:-1}/g" ${CATALINA_HOME}/conf/server.xml
sed -i "s/@WORKER_MOD_CLUSTER_ADVERTISE_ADDRESS@/${WORKER_MOD_CLUSTER_ADVERTISE_ADDRESS:-224.0.1.106}/g" ${CATALINA_HOME}/conf/server.xml
sed -i "s/@WORKER_MOD_CLUSTER_ADVERTISE_PORT@/${WORKER_MOD_CLUSTER_ADVERTISE_PORT:-23399}/g" ${CATALINA_HOME}/conf/server.xml
sed -i "s/@WORKER_MOD_CLUSTER_ADVERTISE_INTERFACE@/${MYIP}/g" ${CATALINA_HOME}/conf/server.xml
sed -i "s/@WORKER_JVM_ROUTE@/${CONTAINER_NAME}/g" ${CATALINA_HOME}/conf/server.xml
sed -i "s/@WORKER_HOST@/${DOCKERCLOUD_CONTAINER_FQDN}/g" ${CATALINA_HOME}/conf/server.xml
sed -i "s/@WORKER_IP@/${MYIP}/g" ${CATALINA_HOME}/conf/server.xml

${CATALINA_HOME}/bin/catalina.sh run

