#!/bin/bash
set -e

BACKUP_DIR=${BACKUP_DIR:-"/backups"}
DAEMON_MODE=${DAEMON_MODE:-"0"}

function kctl() {
    kubectl "$@"
}

DATABASES=($(kctl get deploy -l is-psql=true | grep -v NAME | awk '{print$1}'))


function doBackUp() {
    DATE=`date +%d-%m-%Y-%H-%w`
    echo "doing backup in ${DATE}"
    mkdir -p "${BACKUP_DIR}/${DATE}"
    cd "${BACKUP_DIR}/${DATE}"

    #for (( i=1; i<${#DATABASES[@]}+1; i++ ));
    for db in "${DATABASES[@]}"
    do
        echo "loading data of database ${db}"
        # get the source pod
        SOURCE_POD=`kctl get pod | grep Running | grep ${db} | awk '{print$1}'`
        # get pod connection data
        SOURCE_USER=`kctl describe pod ${SOURCE_POD} | grep USER | awk -F':' '{print $2}' | xargs`

        echo "backing up ${SOURCE_USER}@${SOURCE_POD}..."
        kctl exec -it ${SOURCE_POD} -- pg_dump -U ${SOURCE_USER} --format=c ${SOURCE_USER} > "${BACKUP_DIR}/${DATE}/${SOURCE_USER}.sqlc"
        echo "database ${SOURCE_USER} saved..."
    done

    cd ../../
    echo "backups created"
}

function cleanUp() {
    # delete all 9,15 from older than 2 days
    find ${BACKUP_DIR} -type d -mtime +2 ! -path "${BACKUP_DIR}/.*" | awk -F '-' '{ if($4 == "09" || $4 == "15") print $0 }' | xargs rm -rf
    # delete all 6,18 from older than 7 days
    find ${BACKUP_DIR} -type d -mtime +7 ! -path "${BACKUP_DIR}/.*" | awk -F '-' '{ if($4 == "06" || $4 == "18") print $0 }' | xargs rm -rf
    # delete 12 from older than 14 days
    find ${BACKUP_DIR} -type d -mtime +14 ! -path "${BACKUP_DIR}/.*" | awk -F '-' '{ if($4 == "12") print $0 }' | xargs rm -rf
    # delete every non odd from older than 28 days
    find ${BACKUP_DIR} -type d -mtime +28 ! -path "${BACKUP_DIR}/.*" | awk -F '-' '{ if($5 % 2 != 0) print $0 }' | xargs rm -rf
    # delete every day except sunday from older than 42 days
    find ${BACKUP_DIR} -type d -mtime +42 ! -path "${BACKUP_DIR}/.*" | awk -F '-' '{ if($5 != "0") print $0 }' | xargs rm -rf
}

if [ ${DAEMON_MODE} -eq "1" ]; then

    echo "starting backup process..."
    while [ true ]; do
        NOW=`date +%H%M`
        echo ${NOW}
        BACKUP_TIMES=("000" "0600" "0900" "1200" "1500" "1800")
        if [[ " ${BACKUP_TIMES[@]} " =~ " $NOW " ]]; then
            doBackUp
            cleanUp
        fi
        sleep 10
    done
else
    echo "running one backup cycle"
    cleanUp
    doBackUp
fi

