#!/bin/bash

set -eu -o pipefail

# === Auto setup defaults ===

: "${SKIP_SCHEMA_SETUP:=false}"
: "${SKIP_DB_CREATE:=false}"
: "${SKIP_VISIBILITY_DB_CREATE:=${SKIP_DB_CREATE}}"
: "${SKIP_DEFAULT_NAMESPACE_CREATION:=false}"
: "${DEFAULT_NAMESPACE:=default}"
: "${DEFAULT_NAMESPACE_RETENTION:=24h}"
: "${SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES:=false}"

deprecate() {
	local from=$1 to=$2
	if [[ -n ${!from:=} ]]; then
		echo "The ${from} environment variable is deprecated. Please set ${to} instead." >&2
		printf -v ${to} '%s' "${!from}"
	fi
}

# Cassandra
deprecate KEYSPACE CASSANDRA_KEYSPACE
: "${CASSANDRA_KEYSPACE:=temporal}"
: "${CASSANDRA_SEEDS:=}"
CASSANDRA_HOST=${CASSANDRA_SEEDS}
: "${CASSANDRA_PORT:=9042}"
: "${CASSANDRA_USER:=}"
: "${CASSANDRA_PASSWORD:=}"
deprecate CASSANDRA_TLS_ENABLED CASSANDRA_ENABLE_TLS
: "${CASSANDRA_ENABLE_TLS:=}"
deprecate CASSANDRA_CERT CASSANDRA_TLS_CERT
: "${CASSANDRA_TLS_CERT:=}"
deprecate CASSANDRA_CERT_KEY CASSANDRA_TLS_KEY
: "${CASSANDRA_TLS_KEY:=}"
deprecate CASSANDRA_CA CASSANDRA_TLS_CA
: "${CASSANDRA_TLS_CA:=}"
: "${CASSANDRA_REPLICATION_FACTOR:=1}"

# SQL
: "${DB:=}"
if [[ -n ${DB} ]]; then
    if [[ ${DB} == "cassandra" ]]; then
        echo "The DB environment variable is deprecated. Please unset DB, cassandra is the default." >&2
    else
        deprecate DB SQL_PLUGIN
    fi
fi
: "${SQL_PLUGIN:=}"
deprecate POSTGRES_SEEDS SQL_HOST
deprecate MYSQL_SEEDS SQL_HOST
: "${SQL_HOST:=}"
deprecate DB_PORT SQL_PORT
if [[ ${SQL_PLUGIN} == "postgres12" ]] || [[ ${SQL_PLUGIN} == "postgres12_pgx" ]]; then
    : "${SQL_PORT:=5432}"
elif [[ ${SQL_PLUGIN} == "mysql8" ]]; then
    : "${SQL_PORT:=3306}"
fi
deprecate POSTGRES_USER SQL_USER
deprecate MYSQL_USER SQL_USER
: "${SQL_USER:=}"
deprecate POSTGRES_PWD SQL_PASSWORD
deprecate MYSQL_PWD SQL_PASSWORD
: "${SQL_PASSWORD:=}"
: "${SQL_CONNECT_ATTRIBUTES:=}"
: "${MYSQL_TX_ISOLATION_COMPAT:=false}"
if [[ ${MYSQL_TX_ISOLATION_COMPAT} == true ]]; then
    echo "The MYSQL_TX_ISOLATION_COMPAT environment variable is deprecated. Please set SQL_CONNECT_ATTRIBUTES=\"tx_isolation=READ-COMMITTED\" instead." >&2
    if [[ -z ${SQL_CONNECT_ATTRIBUTES} ]]; then
        SQL_CONNECT_ATTRIBUTES="tx_isolation=READ-COMMITTED"
    else
        SQL_CONNECT_ATTRIBUTES="$SQL_CONNECT_ATTRIBUTES&tx_isolation=READ-COMMITTED"
    fi
fi
deprecate DB_NAME SQL_DATABASE
: "${SQL_DATABASE:=temporal}"
deprecate VISIBILITY_DBNAME SQL_VISIBILITY_DATABASE
: "${SQL_VISIBILITY_DATABASE:=temporal_visibility}"
deprecate POSTGRES_TLS_ENABLED SQL_TLS
: "${SQL_TLS:=false}"
deprecate POSTGRES_TLS_DISABLE_HOST_VERIFICATION SQL_TLS_DISABLE_HOST_VERIFICATION
: "${SQL_TLS_DISABLE_HOST_VERIFICATION:=false}"
deprecate POSTGRES_TLS_CERT_FILE SQL_TLS_CERT_FILE
: "${SQL_TLS_CERT_FILE:=}"
deprecate POSTGRES_TLS_KEY_FILE SQL_TLS_KEY_FILE
: "${SQL_TLS_KEY_FILE:=}"
deprecate POSTGRES_TLS_CA_FILE SQL_TLS_CA_FILE
: "${SQL_TLS_CA_FILE:=}"
deprecate POSTGRES_TLS_SERVER_NAME SQL_TLS_SERVER_NAME
: "${SQL_TLS_SERVER_NAME:=}"

# Elasticsearch
: "${ENABLE_ES:=false}"
: "${ES_SCHEME:=http}"
: "${ES_SEEDS:=}"
: "${ES_PORT:=9200}"
: "${ES_USER:=}"
: "${ES_PWD:=}"
: "${ES_VERSION:=v7}"
: "${ES_VIS_INDEX:=temporal_visibility_v1_dev}"
: "${ES_SEC_VIS_INDEX:=}"
: "${ES_SCHEMA_SETUP_TIMEOUT_IN_SECONDS:=0}"

# Server setup
: "${TEMPORAL_ADDRESS:=}"
# TEMPORAL_CLI_ADDRESS is deprecated and support for it will be removed in the future release.
: "${TEMPORAL_CLI_ADDRESS:=}"

# === Helper functions ===

die() {
    echo "$*" 1>&2
    exit 1
}

sql_env() {
    SQL_PLUGIN=${SQL_PLUGIN} \
    SQL_HOST=${SQL_HOST} SQL_PORT=${SQL_PORT} SQL_USER=${SQL_USER} SQL_PASSWORD=${SQL_PASSWORD} \
    SQL_CONNECT_ATTRIBUTES=${SQL_CONNECT_ATTRIBUTES} \
    SQL_DATABASE=${SQL_DATABASE} \
    SQL_TLS=${SQL_TLS} \
    SQL_TLS_CERT_FILE=${SQL_TLS_CERT_FILE} SQL_TLS_KEY_FILE=${SQL_TLS_KEY_FILE} SQL_TLS_CA_FILE=${SQL_TLS_CA_FILE} \
    SQL_TLS_SERVER_NAME=${SQL_TLS_SERVER_NAME} SQL_TLS_DISABLE_HOST_VERIFICATION=${SQL_TLS_DISABLE_HOST_VERIFICATION} \
    "$@"
}

sql_visibility_env() {
    SQL_PLUGIN=${SQL_PLUGIN} \
    SQL_HOST=${SQL_HOST} SQL_PORT=${SQL_PORT} SQL_USER=${SQL_USER} SQL_PASSWORD=${SQL_PASSWORD} \
    SQL_CONNECT_ATTRIBUTES=${SQL_CONNECT_ATTRIBUTES} \
    SQL_DATABASE=${SQL_VISIBILITY_DATABASE} \
    SQL_TLS=${SQL_TLS} \
    SQL_TLS_CERT_FILE=${SQL_TLS_CERT_FILE} SQL_TLS_KEY_FILE=${SQL_TLS_KEY_FILE} SQL_TLS_CA_FILE=${SQL_TLS_CA_FILE} \
    SQL_TLS_SERVER_NAME=${SQL_TLS_SERVER_NAME} SQL_TLS_DISABLE_HOST_VERIFICATION=${SQL_TLS_DISABLE_HOST_VERIFICATION} \
    "$@"
}

cassandra_env() {
    CASSANDRA_SEEDS=${CASSANDRA_SEEDS} CASSANDRA_HOST=${CASSANDRA_HOST} CASSANDRA_PORT=${CASSANDRA_PORT} \
    CASSANDRA_USER=${CASSANDRA_USER} CASSANDRA_PASSWORD=${CASSANDRA_PASSWORD} \
    CASSANDRA_KEYSPACE=${CASSANDRA_KEYSPACE} \
    CASSANDRA_ENABLE_TLS=${CASSANDRA_ENABLE_TLS} \
    CASSANDRA_TLS_CERT=${CASSANDRA_TLS_CERT} CASSANDRA_TLS_KEY=${CASSANDRA_TLS_KEY} CASSANDRA_TLS_CA=${CASSANDRA_TLS_CA} \
    CASSANDRA_REPLICATION_FACTOR=${CASSANDRA_REPLICATION_FACTOR} \
    "$@"
}

# === Main database functions ===

validate_db_env() {
    case ${SQL_PLUGIN} in
    mysql8 | postgres12 | postgres12_pgx)
        if [[ -z ${SQL_HOST} ]]; then
            die "SQL_HOST env must be set when using SQL."
        fi
        ;;
    "")
        if [[ -z ${CASSANDRA_SEEDS} ]]; then
            die "CASSANDRA_SEEDS env must be set when using Cassandra."
        fi
        ;;
    *)
        die "Unsupported SQL plugin specified: 'SQL_PLUGIN=${SQL_PLUGIN}'. Valid plugins are: mysql8, postgres12, postgres12_pgx"
        ;;
    esac
}

wait_for_cassandra() {
    until cassandra_env temporal-cassandra-tool validate-health; do
        echo 'Waiting for Cassandra to start up.'
        sleep 1
    done
    echo 'Cassandra started.'
}

wait_for_sql() {
    until nc -z "${SQL_HOST}" "${SQL_PORT}"; do
        echo 'Waiting for SQL service to start up.'
        sleep 1
    done

    echo 'SQL service up.'
}

wait_for_db() {
    case ${SQL_PLUGIN} in
      mysql8 | postgres12 | postgres12_pgx)
          wait_for_sql
          ;;
      "")
          wait_for_cassandra
          ;;
      *)
          die "Unsupported SQL plugin: ${SQL_PLUGIN}."
          ;;
    esac
}

setup_cassandra_schema() {
    SCHEMA_DIR=${TEMPORAL_HOME}/schema/cassandra/temporal/versioned
    if [[ ${SKIP_DB_CREATE} != true ]]; then
        cassandra_env temporal-cassandra-tool create -k "${CASSANDRA_KEYSPACE}" --rf "${CASSANDRA_REPLICATION_FACTOR}"
    fi
    cassandra_env temporal-cassandra-tool setup-schema -v 0.0
    cassandra_env temporal-cassandra-tool update-schema -d "${SCHEMA_DIR}"
}

setup_sql_schema() {
    if [[ ${MYSQL_TX_ISOLATION_COMPAT} == true ]]; then
        if [ -z "${SQL_CONNECT_ATTRIBUTES}" ]; then
            export SQL_CONNECT_ATTRIBUTES="tx_isolation=READ-COMMITTED"
        else
            export SQL_CONNECT_ATTRIBUTES="$SQL_CONNECT_ATTRIBUTES&tx_isolation=READ-COMMITTED"
        fi
    fi

    case ${SQL_PLUGIN} in
        mysql8)
            MYSQL_VERSION_DIR=v8
            SCHEMA_DIR=${TEMPORAL_HOME}/schema/mysql/${MYSQL_VERSION_DIR}/temporal/versioned
            VISIBILITY_SCHEMA_DIR=${TEMPORAL_HOME}/schema/mysql/${MYSQL_VERSION_DIR}/visibility/versioned
            ;;
        postgres12 | postgres12_pgx)
            POSTGRES_VERSION_DIR=v12
            SCHEMA_DIR=${TEMPORAL_HOME}/schema/postgresql/${POSTGRES_VERSION_DIR}/temporal/versioned
            VISIBILITY_SCHEMA_DIR=${TEMPORAL_HOME}/schema/postgresql/${POSTGRES_VERSION_DIR}/visibility/versioned
            if [[ ${SQL_DATABASE} == "${SQL_USER}" ]]; then
                SKIP_DB_CREATE=true
            fi
            if [[ ${SQL_VISIBILITY_DATABASE} == "${SQL_USER}" ]]; then
                SKIP_VISIBILITY_DB_CREATE=true
            fi
            ;;
        *)
            die "Unsupported SQL plugin: ${SQL_PLUGIN}."
            ;;
    esac

    if [[ ${SKIP_DB_CREATE} != true ]]; then
        sql_env temporal-sql-tool create
    fi
    sql_env temporal-sql-tool setup-schema -v 0.0
    sql_env temporal-sql-tool update-schema -d "${SCHEMA_DIR}"

    # Only setup visibility schema if ES is not enabled
    if [[ ${ENABLE_ES} == false ]]; then
      if [[ ${SKIP_VISIBILITY_DB_CREATE} != true ]]; then
          sql_visibility_env temporal-sql-tool create
      fi
      sql_visibility_env temporal-sql-tool setup-schema -v 0.0
      sql_visibility_env temporal-sql-tool update-schema -d "${VISIBILITY_SCHEMA_DIR}"
    fi
}

setup_schema() {
    case ${SQL_PLUGIN} in
      mysql8 | postgres12 | postgres12_pgx)
          echo 'Setup SQL schema.'
          setup_sql_schema
          ;;
      "")
          echo 'Setup Cassandra schema.'
          setup_cassandra_schema
          ;;
      *)
          die "Unsupported SQL plugin: ${SQL_PLUGIN}."
          ;;
    esac
}

# === Elasticsearch functions ===

validate_es_env() {
    if [[ ${ENABLE_ES} == true ]]; then
        if [[ -z ${ES_SEEDS} ]]; then
            die "ES_SEEDS env must be set if ENABLE_ES is ${ENABLE_ES}"
        fi
    fi
}

wait_for_es() {
    SECONDS=0

    ES_SERVER="${ES_SCHEME}://${ES_SEEDS%%,*}:${ES_PORT}"

    until curl --silent --fail --user "${ES_USER}":"${ES_PWD}" "${ES_SERVER}" >& /dev/null; do
        DURATION=${SECONDS}

        if [[ ${ES_SCHEMA_SETUP_TIMEOUT_IN_SECONDS} -gt 0 && ${DURATION} -ge "${ES_SCHEMA_SETUP_TIMEOUT_IN_SECONDS}" ]]; then
            echo 'WARNING: timed out waiting for Elasticsearch to start up. Skipping index creation.'
            return;
        fi

        echo 'Waiting for Elasticsearch to start up.'
        sleep 1
    done

    echo 'Elasticsearch started.'
}

setup_es_index() {
    ES_SERVER="${ES_SCHEME}://${ES_SEEDS%%,*}:${ES_PORT}"
# @@@SNIPSTART setup-es-template-commands
    # ES_SERVER is the URL of Elasticsearch server i.e. "http://localhost:9200".
    SETTINGS_URL="${ES_SERVER}/_cluster/settings"
    SETTINGS_FILE=${TEMPORAL_HOME}/schema/elasticsearch/visibility/cluster_settings_${ES_VERSION}.json
    TEMPLATE_URL="${ES_SERVER}/_template/temporal_visibility_v1_template"
    SCHEMA_FILE=${TEMPORAL_HOME}/schema/elasticsearch/visibility/index_template_${ES_VERSION}.json
    INDEX_URL="${ES_SERVER}/${ES_VIS_INDEX}"
    curl --fail --user "${ES_USER}":"${ES_PWD}" -X PUT "${SETTINGS_URL}" -H "Content-Type: application/json" --data-binary "@${SETTINGS_FILE}" --write-out "\n"
    curl --fail --user "${ES_USER}":"${ES_PWD}" -X PUT "${TEMPLATE_URL}" -H 'Content-Type: application/json' --data-binary "@${SCHEMA_FILE}" --write-out "\n"
    curl --user "${ES_USER}":"${ES_PWD}" -X PUT "${INDEX_URL}" --write-out "\n"
    if [[ -n "${ES_SEC_VIS_INDEX}" ]]; then
      SEC_INDEX_URL="${ES_SERVER}/${ES_SEC_VIS_INDEX}"
      curl --user "${ES_USER}":"${ES_PWD}" -X PUT "${SEC_INDEX_URL}" --write-out "\n"
    fi
# @@@SNIPEND
}

# === Server setup ===

register_default_namespace() {
    echo "Registering default namespace: ${DEFAULT_NAMESPACE}."
    if ! temporal operator namespace describe "${DEFAULT_NAMESPACE}"; then
        echo "Default namespace ${DEFAULT_NAMESPACE} not found. Creating..."
        temporal operator namespace create --retention "${DEFAULT_NAMESPACE_RETENTION}" --description "Default namespace for Temporal Server." "${DEFAULT_NAMESPACE}"
        echo "Default namespace ${DEFAULT_NAMESPACE} registration complete."
    else
        echo "Default namespace ${DEFAULT_NAMESPACE} already registered."
    fi
}

add_custom_search_attributes() {
    until temporal operator search-attribute list --namespace "${DEFAULT_NAMESPACE}"; do
      echo "Waiting for namespace cache to refresh..."
      sleep 1
    done
    echo "Namespace cache refreshed."

    echo "Adding Custom*Field search attributes."
    # TODO: Remove CustomStringField
# @@@SNIPSTART add-custom-search-attributes-for-testing-command
    temporal operator search-attribute create --namespace "${DEFAULT_NAMESPACE}" \
        --name CustomKeywordField --type Keyword \
        --name CustomStringField --type Text \
        --name CustomTextField --type Text \
        --name CustomIntField --type Int \
        --name CustomDatetimeField --type Datetime \
        --name CustomDoubleField --type Double \
        --name CustomBoolField --type Bool
# @@@SNIPEND
}

setup_server(){
    echo "Temporal CLI address: ${TEMPORAL_ADDRESS}."

    until temporal operator cluster health | grep -q SERVING; do
        echo "Waiting for Temporal server to start..."
        sleep 1
    done
    echo "Temporal server started."

    if [[ ${SKIP_DEFAULT_NAMESPACE_CREATION} != true ]]; then
        register_default_namespace
    fi

    if [[ ${SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES} != true ]]; then
        add_custom_search_attributes
    fi
}

# === Main ===

if [[ ${SKIP_SCHEMA_SETUP} != true ]]; then
    validate_db_env
    wait_for_db
    setup_schema
fi

if [[ ${ENABLE_ES} == true ]]; then
    validate_es_env
    wait_for_es
    setup_es_index
fi

# Run this func in parallel process. It will wait for server to start and then run required steps.
setup_server &
