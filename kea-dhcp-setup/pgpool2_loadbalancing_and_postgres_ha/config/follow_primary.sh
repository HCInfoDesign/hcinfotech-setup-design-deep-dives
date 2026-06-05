#!/bin/bash
# This script is run after failover_command to synchronize the Standby with the new Primary.

# Debug Failover
exec 1> >(tee -ia /var/log/pgpool-failover-logs/follow_primary.log)
exec 2> >(tee -ia /var/log/pgpool-failover-logs/follow_primary.log >& 2)

exec {FD}>> /var/log/pgpool-failover-logs/follow_primary.log

export BASH_XTRACEFD="$FD"
set -x

filan -s
# Debug Failover

set -o xtrace

# Special values:
# 1)  %d = node id
# 2)  %h = hostname
# 3)  %p = port number
# 4)  %D = node database cluster path
# 5)  %m = new primary node id
# 6)  %H = new primary node hostname
# 7)  %M = old main node id
# 8)  %P = old primary node id
# 9)  %r = new primary port number
# 10) %R = new primary database cluster path
# 11) %N = old primary node hostname
# 12) %S = old primary node port number
# 13) %% = '%' character

NODE_ID="$1"
NODE_HOST="$2"
NODE_PORT="$3"
NODE_PGDATA="$4"
NEW_PRIMARY_NODE_ID="$5"
NEW_PRIMARY_NODE_HOST="$6"
OLD_MAIN_NODE_ID="$7"
OLD_PRIMARY_NODE_ID="$8"
NEW_PRIMARY_NODE_PORT="$9"
NEW_PRIMARY_NODE_PGDATA="${10}"

POSTGRES_CONF_PATH=/etc/postgresql/18/main
PGHOME=/usr/lib/postgresql/18
REPLUSER=replicationuser
PCP_USER=pgpool
PGPOOL_PATH=/usr/local/bin
PCP_PORT=9898
REPL_SLOT_NAME=$(echo ${NODE_HOST,,} | tr -- -. _)
POSTGRESQL_STARTUP_USER=postgres
SSH_KEY_FILE=id_ed25519
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/${SSH_KEY_FILE}"

echo follow_primary.sh: start: Standby node ${NODE_ID}

# Check the connection status of Standby
${PGHOME}/bin/pg_isready -h ${NODE_HOST} -p ${NODE_PORT} > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo follow_primary.sh: node_id=${NODE_ID} is not running. skipping follow primary command
    exit 0
fi

# Test passwordless SSH
/usr/bin/ssh -T ${SSH_OPTIONS} ${POSTGRESQL_STARTUP_USER}@${NEW_PRIMARY_NODE_HOST} ls /tmp > /dev/null

if [ $? -ne 0 ]; then
    echo follow_main.sh: passwordless SSH to ${POSTGRESQL_STARTUP_USER}@${NEW_PRIMARY_NODE_HOST} failed. Please setup passwordless SSH.
    exit 1
fi

# Get PostgreSQL major version
PGVERSION=`${PGHOME}/bin/psql -V | awk '{print $3}' | sed 's/\..*//' | sed 's/\([0-9]*\)[a-zA-Z].*/\1/'`

if [ $PGVERSION -ge 12 ]; then
    RECOVERYCONF=${POSTGRES_CONF_PATH}/cond.d/recovery.conf
else
    RECOVERYCONF=${NODE_PGDATA}/recovery.conf
fi

# Synchronize Standby with the new Primary.
echo follow_primary.sh: pg_rewind for node ${NODE_ID}

# Run checkpoint command to update control file before running pg_rewind
${PGHOME}/bin/psql -h ${NEW_PRIMARY_NODE_HOST} -p ${NEW_PRIMARY_NODE_PORT} postgres -c "checkpoint;"

# Create replication slot "${REPL_SLOT_NAME}"
${PGHOME}/bin/psql -h ${NEW_PRIMARY_NODE_HOST} -p ${NEW_PRIMARY_NODE_PORT} postgres \
    -c "SELECT pg_create_physical_replication_slot('${REPL_SLOT_NAME}');"  >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo follow_primary.sh: create replication slot \"${REPL_SLOT_NAME}\" failed. You may need to create replication slot manually.
fi

/usr/bin/ssh -T ${SSH_OPTIONS} ${POSTGRESQL_STARTUP_USER}@${NODE_HOST} "

    set -o errexit

    /usr/bin/sudo /usr/bin/systemctl stop postgresql

    ${PGHOME}/bin/pg_rewind -D ${NODE_PGDATA} --source-server=\"user=${REPLUSER} host=${NEW_PRIMARY_NODE_HOST} port=${NEW_PRIMARY_NODE_PORT} dbname=postgres\" -R -c

    [ -d \"${NODE_PGDATA}\" ] && rm -rf ${NODE_PGDATA}/pg_replslot/*

    cat > ${RECOVERYCONF} << EOT
primary_conninfo = 'host=${NEW_PRIMARY_NODE_HOST} port=${NEW_PRIMARY_NODE_PORT} user=${REPLUSER} application_name=${NODE_HOST} sslmode=verify-full passfile=''/var/lib/postgresql/.pgpass'''
recovery_target_timeline = 'latest'
primary_slot_name = '${REPL_SLOT_NAME}'
cluster_name = '${NODE_HOST}'
EOT

    if [ ${PGVERSION} -ge 12 ]; then
        touch ${NODE_PGDATA}/standby.signal
    else
        echo \"standby_mode = 'on'\" >> ${RECOVERYCONF}
    fi

    /usr/bin/sudo /usr/bin/systemctl restart postgresql

"

# If start Standby successfully, attach this node
if [ $? -eq 0 ]; then

    # Run pcp_attact_node to attach Standby node to Pgpool-II.
    ${PGPOOL_PATH}/pcp_attach_node -w -h localhost -U $PCP_USER -p ${PCP_PORT} -n ${NODE_ID}

    if [ $? -ne 0 ]; then
        echo ERROR: follow_primary.sh: end: pcp_attach_node failed
        exit 1
    fi
else

    # If start Standby failed, drop replication slot "${REPL_SLOT_NAME}"
    ${PGHOME}/bin/psql -h ${NEW_PRIMARY_NODE_HOST} -p ${NEW_PRIMARY_NODE_PORT} postgres \
        -c "SELECT pg_drop_replication_slot('${REPL_SLOT_NAME}');"  >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo ERROR: follow_primary.sh: drop replication slot \"${REPL_SLOT_NAME}\" failed. You may need to drop replication slot manually.
    fi

    echo ERROR: follow_primary.sh: end: follow primary command failed
    exit 1
fi

echo follow_primary.sh: end: follow primary command is completed successfully
exit 0
