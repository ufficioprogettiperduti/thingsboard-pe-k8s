#!/bin/bash
#
# Copyright © 2016-2020 The Thingsboard Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

function installTb() {

    loadDemo=$1

    microk8s kubectl apply -f $DATABASE/tb-node-db-configmap.yml

    microk8s kubectl apply -f tb-node-configmap.yml
    microk8s kubectl apply -f database-setup.yml &&
    microk8s kubectl wait --for=condition=Ready pod/tb-db-setup --timeout=120s &&
    microk8s kubectl exec tb-db-setup -- sh -c 'export INSTALL_TB=true; export LOAD_DEMO='"$loadDemo"'; start-tb-node.sh; touch /tmp/install-finished;'

    microk8s kubectl delete pod tb-db-setup

}

function installPostgres() {
    microk8s kubectl apply -f postgres.yml
    microk8s kubectl rollout status deployment/postgres
}

function installCassandra() {

    if [ $CASSANDRA_REPLICATION_FACTOR -lt 1 ]; then
        echo "CASSANDRA_REPLICATION_FACTOR should be greater or equal to 1. Value $CASSANDRA_REPLICATION_FACTOR is not allowed."
        exit 1
    fi

    microk8s kubectl apply -f cassandra.yml

    microk8s kubectl rollout status statefulset/cassandra

    microk8s kubectl exec -it cassandra-0 -- bash -c "cqlsh -u cassandra -p cassandra -e \
                    \"CREATE KEYSPACE IF NOT EXISTS thingsboard \
                    WITH replication = { \
                        'class' : 'SimpleStrategy', \
                        'replication_factor' : $CASSANDRA_REPLICATION_FACTOR \
                    };\""
}

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --loadDemo)
    LOAD_DEMO=true
    shift # past argument
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

if [ "$LOAD_DEMO" == "true" ]; then
    loadDemo=true
else
    loadDemo=false
fi

source .env

microk8s kubectl apply -f tb-namespace.yml || echo
microk8s kubectl config set-context --current --namespace=thingsboard

case $DATABASE in
        postgres)
            installPostgres
            installTb ${loadDemo}
        ;;
        hybrid)
            installPostgres
            installCassandra
            installTb ${loadDemo}
        ;;
        *)
        echo "Unknown DATABASE value specified: '${DATABASE}'. Should be either postgres or hybrid." >&2
        exit 1
esac

