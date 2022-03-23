#!/usr/bin/env bash


user_help () {
    echo "Waits until the given CRD is present in the cluster."
    echo "options:"
    echo "-crd, --expect-crd         CRD name to be present in the cluster - it's a sign that the operator is installed."
    echo "-cs,  --catalogsource      CatalogSource name of the operator that is being installed."
    echo "-n,   --namespace          The target namespace the operator is being installed in."
    echo "-s,   --subscription       Subscription name of the operator that is being installed."
    echo "-h,   --help               To show this help text"
    echo ""
    exit 0
}

read_arguments() {
    if [[ $# -lt 2 ]]
    then
        user_help
    fi

    while test $# -gt 0; do
           case "$1" in
                -h|--help)
                    user_help
                    ;;
                -crd|--expect-crd)
                    shift
                    EXPECT_CRD=$1
                    shift
                    ;;
                -cs|--catalogsource)
                    shift
                    CATALOGSOURCE_NAME=$1
                    shift
                    ;;
                -n|--namespace)
                    shift
                    NAMESPACE=$1
                    shift
                    ;;
                -s|--subscription)
                    shift
                    SUBSCRIPTION_NAME=$1
                    shift
                    ;;
                *)
                   echo "$1 is not a recognized flag!" >> /dev/stderr
                   user_help
                   exit -1
                   ;;
          esac
    done
}

captureAllPodLogsInNamespace() {
    echo "Retrieving Pod Logs For Namespace $1 ..."
    oc get po -n $1 --no-headers -o custom-columns=":metadata.name" | \
    while IFS= read -r po; do \
        if [[ -d "${LOG_DIR}" ]]; then
            mkdir -p $LOG_DIR/$1
            LOG_FILE=$LOG_DIR/$1/$po.log
            echo "Processing $LOG_FILE..."
            oc logs $po -n $1 > $LOG_FILE
        else
            oc logs $po -n $1
        fi
    done
    echo "Finished retrieving Pod Logs For Namespace $1 ..."
}

wait_until_is_installed() {
    echo "Waiting for CRD ${EXPECT_CRD} to be available in the cluster..."
    OLM_NS="openshift-operator-lifecycle-manager"

    NEXT_WAIT_TIME=0
    MAX_NUM_ATTEMPTS=100
    SLEEP_TIME=1
    if [[ -n "${CI}${CLONEREFS_OPTIONS}" ]]; then
        MAX_NUM_ATTEMPTS=30
        SLEEP_TIME=1
    fi

    while [[ -z `oc get crd | grep ${EXPECT_CRD} || true` ]]; do
        if [[ ${NEXT_WAIT_TIME} -eq ${MAX_NUM_ATTEMPTS} ]]; then
           echo "reached timeout of waiting for CRD ${EXPECT_CRD} to be available in the cluster - see following info for debugging:"
           echo "================================ CatalogSource =================================="
           oc get catalogsource ${CATALOGSOURCE_NAME} -n ${NAMESPACE} -o yaml
           echo "================================ CatalogSource Pod Logs =================================="
           oc logs `oc get pods -l "olm.catalogSource=${CATALOGSOURCE_NAME#*/}" -n ${NAMESPACE} -o name` -n ${NAMESPACE}
           echo "================================ Subscription =================================="
           oc get subscription ${SUBSCRIPTION_NAME} -n ${NAMESPACE} -o yaml
           echo "================================ InstallPlans =================================="
           oc get installplans -n ${NAMESPACE} -o yaml
           captureAllPodLogsInNamespace $OLM_NS
           captureAllPodLogsInNamespace $NAMESPACE
           exit 1
        fi
        echo "$(( NEXT_WAIT_TIME++ )). attempt (out of ${MAX_NUM_ATTEMPTS}) of waiting for CRD ${EXPECT_CRD} to be available in the cluster"
        sleep ${SLEEP_TIME}
    done
}

set -e

read_arguments $@

if [[ -d "${ARTIFACT_DIR}" ]]; then
   LOG_DIR=$ARTIFACT_DIR/logs
   mkdir -p $LOG_DIR
fi

wait_until_is_installed