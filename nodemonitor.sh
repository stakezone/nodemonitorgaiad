#!/bin/bash

#set -x # for debugging

###    packages required: jq, bc

###    if suppressing error messages is preferred, run as './nodemonitor.sh 2> /dev/null'

###    CONFIG    ##################################################################################################
CONFIG=""                # config.toml file for node, eg. $HOME/.gaia/config/config.toml
### optional:            #
NPRECOMMITS="20"         # check last n precommits, can be 0 for no checking
VALIDATORADDRESS=""      # if left empty default is from status call (validator)
CHECKPERSISTENTPEERS="1" # if 1 the number of disconnected persistent peers is checked (when persistent peers are configured in config.toml)
VALIDATORMETRICS="on"    # metrics for validator node
LOGNAME=""               # a custom log file name can be chosen, if left empty default is nodecheck-<username>.log
LOGPATH="$(pwd)"         # the directory where the log file is stored, for customization insert path like: /my/path
LOGSIZE=200              # the max number of lines after that the log will be trimmed to reduce its size
LOGROTATION="1"          # options for log rotation: (1) rotate to $LOGNAME.1 every $LOGSIZE lines;  (2) append to $LOGNAME.1 every $LOGSIZE lines; (3) truncate $logfile to $LOGSIZE every iteration
SLEEP1="30s"             # polls every SLEEP1 sec
###  internal:           #
colorI='\033[0;32m'      # black 30, red 31, green 32, yellow 33, blue 34, magenta 35, cyan 36, white 37
colorD='\033[0;90m'      # for light color 9 instead of 3
colorE='\033[0;31m'      #
colorW='\033[0;33m'      #
noColor='\033[0m'        # no color
###  END CONFIG  ##################################################################################################

if [ -z $CONFIG ]; then
    echo "please configure config.toml in script"
    exit 1
fi
url=$(sed '/^\[rpc\]/,/^\[/!d;//d' $CONFIG | grep "^laddr\b" | awk -v FS='("tcp://|")' '{print $2}')
chainid=$(jq -r '.result.node_info.network' <<<$(curl -s "$url"/status))
if [ -z $url ]; then
    echo "please configure config.toml in script correctly"
    exit 1
fi
url="http://${url}"

if [ -z $LOGNAME ]; then LOGNAME="nodemonitor-${USER}.log"; fi
logfile="${LOGPATH}/${LOGNAME}"
touch $logfile

echo "log file: ${logfile}"
echo "rpc url: ${url}"
echo "chain id: ${chainid}"

if [ -z $VALIDATORADDRESS ]; then VALIDATORADDRESS=$(jq -r '.result.validator_info.address' <<<$(curl -s "$url"/status)); fi
if [ -z $VALIDATORADDRESS ]; then
    echo "rpc appears to be down, start script again when data can be obtained"
    exit 1
fi
echo "validator address: $VALIDATORADDRESS"

if [ "$CHECKPERSISTENTPEERS" -eq 1 ]; then
    persistentpeers=$(sed '/^\[p2p\]/,/^\[/!d;//d' $CONFIG | grep "^persistent_peers\b" | awk -v FS='("|")' '{print $2}')
    persistentpeerids=$(sed 's/,//g' <<<$(sed 's/@[^ ^,]\+/ /g' <<<$persistentpeers))
    totpersistentpeerids=$(wc -w <<<$persistentpeerids)
    npersistentpeersmatchcount=0
    netinfo=$(curl -s "$url"/net_info)
    if [ -z "$netinfo" ]; then
        echo "lcd appears to be down, start script again when data can be obtained"
        exit 1
    fi
    for id in $persistentpeerids; do
        npersistentpeersmatch=$(grep -c "$id" <<<$netinfo)
        if [ $npersistentpeersmatch -eq 0 ]; then
            persistentpeersmatch="$id $persistentpeersmatch"
            npersistentpeersmatchcount=$(expr $npersistentpeersmatchcount + 1)
        fi
    done
    npersistentpeersoff=$(expr $totpersistentpeerids - $npersistentpeersmatchcount)
    echo "$totpersistentpeerids persistent peer(s): $persistentpeerids"
    echo "$npersistentpeersmatchcount persistent peer(s) off: $persistentpeersmatch"
fi

if [ $NPRECOMMITS -eq 0 ]; then echo "precommit checks: off"; else echo "precommit checks: on"; fi
if [ $CHECKPERSISTENTPEERS -eq 0 ]; then echo "persistent peer checks: off"; else echo "persistent peer checks: on"; fi
echo ""

status=$(curl -s "$url"/status)
blockheight=$(jq -r '.result.sync_info.latest_block_height' <<<$status)
blockinfo=$(curl -s "$url"/block?height="$blockheight")
if [ $blockheight -gt $NPRECOMMITS ]; then
    if [ "$(grep -c 'precommits' <<<$blockinfo)" != "0" ]; then versionstring="precommits"; elif [ "$(grep -c 'signatures' <<<$blockinfo)" != "0" ]; then versionstring="signatures"; else
        echo "json parameters of this version not recognised"
        exit 1
    fi
else
    echo "wait for $NPRECOMMITS blocks and start again..."
    exit 1
fi

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $LOGSIZE ]; then sed -i "1,$(expr $nloglines - $LOGSIZE)d" $logfile; fi # the log file is trimmed for logsize

date=$(date --rfc-3339=seconds)
echo "$date status=scriptstarted chainid=$chainid" >>$logfile

while true; do
    status=$(curl -s "$url"/status)
    result=$(grep -c "result" <<<$status)
    if [ "$result" != "0" ]; then
        npeers=$(curl -s "$url"/net_info | jq -r '.result.n_peers')
        if [ -z $npeers ]; then npeers="na"; fi
        blockheight=$(jq -r '.result.sync_info.latest_block_height' <<<$status)
        blocktime=$(jq -r '.result.sync_info.latest_block_time' <<<$status)
        catchingup=$(jq -r '.result.sync_info.catching_up' <<<$status)
        if [ $catchingup == "false" ]; then catchingup="synced"; elif [ $catchingup == "true" ]; then catchingup="catchingup"; fi
        if [ "$CHECKPERSISTENTPEERS" -eq 1 ]; then
            npersistentpeersmatch=0
            netinfo=$(curl -s "$url"/net_info)
            for id in $persistentpeerids; do
                npersistentpeersmatch=$(expr $npersistentpeersmatch + $(grep -c "$id" <<<$netinfo))
            done
            npersistentpeersoff=$(expr $totpersistentpeerids - $npersistentpeersmatch)
        else
            npersistentpeersoff=0
        fi
        if [ "$VALIDATORMETRICS" == "on" ]; then
            #isvalidator=$(grep -c "$VALIDATORADDRESS" <<<$(curl -s "$url"/block?height="$blockheight"))
            validators=$(jq -r '.result.round_state.validators[]' <<<$(curl -s "$url"/dump_consensus_state))
            isvalidator=$(grep -c "$VALIDATORADDRESS" <<<$validators)
            if [ "$isvalidator" != "0" ]; then
                isvalidator="yes"
                precommitcount=0
                for ((i = $(expr $blockheight - $NPRECOMMITS + 1); i <= $blockheight; i++)); do
                    validatoraddresses=$(curl -s "$url"/block?height="$i")
                    validatoraddresses=$(jq ".result.block.last_commit.${versionstring}[].validator_address" <<<$validatoraddresses)
                    validatorprecommit=$(grep -c "$VALIDATORADDRESS" <<<$validatoraddresses)
                    precommitcount=$(expr $precommitcount + $validatorprecommit)
                done
                if [ $NPRECOMMITS -eq 0 ]; then pctprecommits="1.0"; else pctprecommits=$(echo "scale=2 ; $precommitcount / $NPRECOMMITS" | bc); fi
                validatorinfo="isvalidator=$isvalidator pctprecommits=$pctprecommits"
            else
                isvalidator="no"
                validatorinfo="isvalidator=$isvalidator"
            fi
        fi
        status="$catchingup"
        now=$(date --rfc-3339=seconds)
        blockheightfromnow=$(expr $(date +%s -d "$now") - $(date +%s -d $blocktime))
        variables="status=$status blockheight=$blockheight tfromnow=$blockheightfromnow npeers=$npeers npersistentpeersoff=$npersistentpeersoff $validatorinfo"
    else
        status="error"
        now=$(date --rfc-3339=seconds)
        variables="status=$status"
    fi

    logentry="[$now] $variables"
    echo "$logentry" >>$logfile

    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $LOGSIZE ]; then
        case $LOGROTATION in
        1)
            mv $logfile "${logfile}.1"
            touch $logfile
            ;;
        2)
            echo "$(cat $logfile)" >>${logfile}.1
            >$logfile
            ;;
        3)
            sed -i '1d' $logfile
            if [ -f ${logfile}.1 ]; then rm ${logfile}.1; fi # no log rotation with option (3)
            ;;
        *) ;;

        esac
    fi

    case $status in
    synced)
        color=$colorI
        ;;
    error)
        color=$colorE
        ;;
    catchingup)
        color=$colorW
        ;;
    *)
        color=$noColor
        ;;
    esac

    pctprecommits=$(awk '{printf "%f", $0}' <<<"$pctprecommits")
    if [[ "$isvalidator" == "yes" ]] && [[ "$pctprecommits" < "1.0" ]]; then color=$colorW; fi
    if [[ "$isvalidator" == "no" ]] && [[ "$VALIDATORMETRICS" == "on" ]]; then color=$colorW; fi

    logentry="$(sed 's/[^ ]*[\=]/'\\${color}'&'\\${noColor}'/g' <<<$logentry)"
    echo -e $logentry
    echo -e "${colorD}sleep ${SLEEP1}${noColor}"

    variables_=""
    for var in $variables; do
        var_=$(grep -Po '^[0-9a-zA-Z_-]*' <<<$var)
        var_="$var_=\"\""
        variables_="$var_; $variables_"
    done
    #echo $variables_
    eval $variables_

    sleep $SLEEP1
done
