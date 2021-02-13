#!/bin/bash

###    Packages required: jq, bc

###    CONFIG    ##################################################################################################
config="" # config.toml file for node, eg. /home/user/.gaiad/config/config.toml
### optional:          #
nprecommits=20         # check last n precommits, can be 0 for no checking
validatoraddress=""    # if left empty default is from status call (validator)
checkpersistentpeers=1 # if 1 the number of disconnected persistent peers is checked (when persistent peers are configured in config.toml)
logname=""             # a custom log file name can be chosen, if left empty default is nodecheck-<username>.log
logpath="$(pwd)"       # the directory where the log file is stored, for customization insert path like: /my/path
logsize=200            # the max number of lines after that the log will be trimmed to reduce its size
sleep1=30s             # polls every sleep1 sec
colorI='\033[0;32m'    # black 30, red 31, green 32, yellow 33, blue 34, magenta 35, cyan 36, white 37
colorD='\033[0;90m'    # for light color 9 instead of 3
colorE='\033[0;31m'    #
colorW='\033[0;33m'    #
noColor='\033[0m'      # no color
###  END CONFIG  ##################################################################################################

if [ -z $config ]; then
    echo "please configure config.toml in script"
    exit 1
fi
url=$(sed '/^\[rpc\]/,/^\[/!d;//d' $config | grep "^laddr\b" | awk -v FS='("tcp://|")' '{print $2}')
chainid=$(jq -r '.result.node_info.network' <<<$(curl -s "$url"/status))
if [ -z $url ]; then
    echo "please configure config.toml in script correctly"
    exit 1
fi
url="http://${url}"

if [ -z $logname ]; then logname="nodemonitor-${USER}.log"; fi
logfile="${logpath}/${logname}"
touch $logfile

echo "log file: ${logfile}"
echo "rpc url: ${url}"
echo "chain id: ${chainid}"

if [ -z $validatoraddress ]; then validatoraddress=$(jq -r '.result.validator_info.address' <<<$(curl -s "$url"/status)); fi
if [ -z $validatoraddress ]; then
    echo "WARNING: rpc appears to be down, start script again when data can be obtained"
    exit 1
fi
echo "validator address: $validatoraddress"

if [ "$checkpersistentpeers" -eq 1 ]; then
    persistentpeers=$(sed '/^\[p2p\]/,/^\[/!d;//d' $config | grep "^persistent_peers\b" | awk -v FS='("|")' '{print $2}')
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

if [ $nprecommits -eq 0 ]; then echo "precommit checks: off"; else echo "precommit checks: on"; fi
if [ $checkpersistentpeers -eq 0 ]; then echo "persistent peer checks: off"; else echo "persistent peer checks: on"; fi
echo ""

status=$(curl -s "$url"/status)
blockheight=$(jq -r '.result.sync_info.latest_block_height' <<<$status)
blockinfo=$(curl -s "$url"/block?height="$blockheight")
if [ $blockheight -gt $nprecommits ]; then
    if [ "$(grep -c 'precommits' <<<$blockinfo)" != "0" ]; then versionstring="precommits"; elif [ "$(grep -c 'signatures' <<<$blockinfo)" != "0" ]; then versionstring="signatures"; else echo "json parameters of this version not recognised" && exit 1; fi
else
    echo "wait for $nprecommits blocks and start again..." && exit 1
fi

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $logsize ]; then sed -i "1,$(expr $nloglines - $logsize)d" $logfile; fi # the log file is trimmed for logsize

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
        isvalidator=$(grep -c "$validatoraddress" <<<$(curl -s "$url"/block?height="$blockheight"))
        if [ "$isvalidator" != "0" ]; then
            isvalidator="yes"
            precommitcount=0
            for ((i = $(expr $blockheight - $nprecommits + 1); i <= $blockheight; i++)); do
                validatoraddresses=$(curl -s "$url"/block?height="$i")
                validatoraddresses=$(jq ".result.block.last_commit.${versionstring}[].validator_address" <<<$validatoraddresses)
                validatorprecommit=$(grep -c "$validatoraddress" <<<$validatoraddresses)
                precommitcount=$(expr $precommitcount + $validatorprecommit)
            done
            if [ $nprecommits -eq 0 ]; then pctprecommits="1.0"; else pctprecommits=$(echo "scale=2 ; $precommitcount / $nprecommits" | bc); fi
            validatorinfo="isvalidator=$isvalidator pctprecommits=$pctprecommits"
        else
            isvalidator="no"
            validatorinfo="isvalidator=$isvalidator"
        fi
 
        if [ "$checkpersistentpeers" -eq 1 ]; then
            npersistentpeersmatch=0
            netinfo=$(curl -s "$url"/net_info)
            for id in $persistentpeerids; do
                npersistentpeersmatch=$(expr $npersistentpeersmatch + $(grep -c "$id" <<<$netinfo))
            done
            npersistentpeersoff=$(expr $totpersistentpeerids - $npersistentpeersmatch)
        else
            npersistentpeersoff=0
        fi
        status="$catchingup"
        now=$(date --rfc-3339=seconds)
        blockheightfromnow=$(expr $(date +%s -d "$now") - $(date +%s -d $blocktime))
        logentry="[$now] status=$status blockheight=$blockheight tfromnow=$blockheightfromnow npeers=$npeers npersistentpeersoff=$npersistentpeersoff $validatorinfo"
        echo "$logentry" >>$logfile

    else
        status="error"
        now=$(date --rfc-3339=seconds)
        logentry="[$now] status=$status"
        echo "$logentry" >>$logfile
    fi

    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $logsize ]; then sed -i '1d' $logfile; fi

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

    logentry="$(sed 's/[^ ]*[\=]/'\\${color}'&'\\${noColor}'/g' <<<$logentry)"
    echo -e $logentry
    echo -e "${colorD}sleep ${sleep1}${noColor}"

    sleep $sleep1
done
