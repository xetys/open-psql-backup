#!/usr/bin/env bash
DATE=`date +%d-%m-%Y-%H-%w`
BACKUP_NAME=${DATE}
NAMESPACE=${NAMESPACE:-"default"}
BACKUP_DIR=${BACKUP_DIR:-"./backups"}
ACTION="help"
REST=""
FILTER=""
DROP_SCHEMA=false

helpfunc() {
    echo "usage: ./k8s-psql-tool.sh <ACTION> [OPTIONS...]"
    echo "Actions: "
    echo "  backup: creates a backup of all PostgreSQL databases"
    echo "  restore: restores PostgreSQL databases"
    echo "  exec: executes a query against all PostgreSQL databases"
    echo "Options: "
    echo "  --name,-n:      do not use a timestamp as backup name, but specify it"
    echo "  --filter,-f:    perform action on a filtered set of databases"
    echo "Examples: "
    echo "# just create a backup"
    echo "  ./k8s-psql-tool.sh backup"
    echo "# create a backup in the directory 'my-backup'"
    echo "  ./k8s-psql-tool.sh backup -n my-backup"
    echo "# restore backup 'my-backup'"
    echo "  ./k8s-psql-tool.sh restore -n my-backup"
    echo "# restore backup 'my-backup', but only uaa databases"
    echo "  ./k8s-psql-tool.sh restore -n my-backup -f uaa"
    echo "# run some sql on all dbs"
    echo "  ./k8s-psql-tool.sh exec 'select * from table'"
    echo "# run some sql on uaa database"
    echo "  ./k8s-psql-tool.sh exec -f uaa 'select * from table'"
}

function kctl() {
    kubectl -n ${NAMESPACE} "$@"
}

if [[ $# == 0 ]]; then
    helpfunc
fi

# always get the first param as action
ACTION="$1"
shift

if [[ ${ACTION} = "help" ]] || [[ ${ACTION} = "--help" ]] || [[ ${ACTION} = "-h" ]]; then
    helpfunc
fi

# parse all options
while (( $# > 0 ))
do
    opt="$1"
    shift

    case ${opt} in
    --help|-h)
        helpfunc
        exit 0
        ;;
    --name|-n)
        BACKUP_NAME="$1"
        shift
        ;;
    --namespace)
        NAMESPACE="$1"
        shift
        ;;
    --drop-schema|-d)
        DROP_SCHEMA=true
        ;;
    --backup-dir|-b)
        BACKUP_DIR="$1"
        shift
        ;;
    --filter|-f)
        FILTER=$1
        shift
    ;;
    --*)
        echo "Invalid option: '$opt'" >&2
        exit 1
        ;;
    *)
        # end of long options
        REST="${REST}${opt}"
#        break;
        ;;
   esac

done

if [[ ${FILTER} = "" ]]; then
    SQL_PODS=($(kctl get po -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' | awk '($2 ~ /postgres/ || $2 ~ /postgis/) {print$1}'))
else
    SQL_PODS=($(kctl get po -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' | awk '($2 ~ /postgres/ || $2 ~ /postgis/) {print$1}' | grep ${FILTER}))
fi
case ${ACTION} in
"backup")
    echo "creating backup '${BACKUP_NAME}' in '${BACKUP_DIR}/${BACKUP_NAME}'"
    for service in ${SQL_PODS[@]}; do
        SOURCE_USER=`kctl describe pod ${service} | grep USER | awk -F':' '{print $2}' | xargs`
        echo "found pod ${service} with user ${SOURCE_USER}"
        echo "backing up ${SOURCE_USER}@${service}..."
        mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}/"
        kctl exec -it ${service} -- pg_dump -U ${SOURCE_USER} --format=c ${SOURCE_USER} -f /db.dump
        kctl cp "${NAMESPACE}/${service}:/db.dump" "${BACKUP_DIR}/${BACKUP_NAME}/${SOURCE_USER}.dump"
    done
   ;;
"restore")
    echo "restoring backup '${BACKUP_NAME}' from '${BACKUP_DIR}/${BACKUP_NAME}'"
    DUMPS=($(ls -1 "${BACKUP_DIR}/${BACKUP_NAME}/" | grep ".dump"))
    for service in ${SQL_PODS[@]}; do
        SOURCE_USER=`kctl describe pod ${service} | grep USER | awk -F':' '{print $2}' | xargs`
        for dump in ${DUMPS[@]} ; do
            if [[ "${SOURCE_USER}.dump" = ${dump} ]]; then
                echo "found dump ${dump} for pod ${service}"

                kctl cp "${BACKUP_DIR}/${BACKUP_NAME}/${dump}" "${NAMESPACE}/${service}:/db.dump"
                if ${DROP_SCHEMA}; then
                    kctl exec -it ${service} -- psql -U ${SOURCE_USER} -c 'DROP SCHEMA PUBLIC CASCADE; CREATE SCHEMA PUBLIC;'
                fi
                kctl exec -it ${service} -- pg_restore -U ${SOURCE_USER} -d ${SOURCE_USER} -Fc --clean --no-owner --no-acl --role=${SOURCE_USER} "/db.dump"
            fi
        done
    done
   ;;
"exec")
    echo "executing ''${REST}'' on all postgres instances"
    for service in ${SQL_PODS[@]}; do
        echo "running in ${service}"
        SOURCE_USER=`kctl describe pod ${service} | grep USER | awk -F':' '{print $2}' | xargs`
        kctl exec -it ${service} -- psql -U ${SOURCE_USER} -c "${REST}"
    done
   ;;
esac
