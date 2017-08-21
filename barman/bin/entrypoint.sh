#!/usr/bin/env bash
set -e

echo ">>> Checking all configurations"
[[ "$REPLICATION_HOST" != "" ]] || ( echo 'Variable REPLICATION_HOST is not set!' ;exit 1 )
[[ "$POSTGRES_USER" != "" ]] || ( echo 'Variable POSTGRES_USER is not set!' ;exit 2 )
[[ "$POSTGRES_PASSWORD" != "" ]] || ( echo 'Variable POSTGRES_PASSWORD is not set!' ;exit 3 )
[[ "$POSTGRES_DB" != "" ]] || ( echo 'Variable POSTGRES_DB is not set!' ;exit 4 )

echo ">>> Waiting for upstream DB"
dockerize -wait tcp://$REPLICATION_HOST:$REPLICATION_PORT -timeout "$WAIT_UPSTREAM_TIMEOUT"s
sleep $INITIAL_BACKUP_DELAY

echo ">>> Configuring barman for streaming replication"
echo "
[$CLUSTER_NAME]
description =  'Cluster $CLUSTER_NAME replication'
backup_method = postgres
streaming_archiver = on
streaming_archiver_name = barman_receive_wal
streaming_archiver_batch_size = 50
streaming_conninfo = host=$REPLICATION_HOST user=$REPLICATION_USER password=$REPLICATION_PASSWORD port=$REPLICATION_PORT
conninfo = host=$REPLICATION_HOST dbname=$POSTGRES_DB user=$POSTGRES_USER password=$POSTGRES_PASSWORD port=$REPLICATION_PORT connect_timeout=$POSTGRES_CONNECTION_TIMEOUT
slot_name = $REPLICATION_SLOT_NAME
" >> $UPSTREAM_CONFIG_FILE

SLOTS_COUNT=`barman show-server $UPSTREAM_NAME | grep "replication_slot: Record(slot_name='$REPLICATION_SLOT_NAME'" | wc -l`
if [ "$SLOTS_COUNT" -gt "0" ]; then 
    echo ">>>>>> Looks like replication slot already exists"
else 
   barman receive-wal --create-slot $UPSTREAM_NAME  
fi

echo '>>> STARTING SSH (if required)...'
source /home/postgres/.ssh/entrypoint.sh

barman receive-wal $UPSTREAM_NAME