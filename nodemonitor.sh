#!/bin/bash

#####    Packages required: jq, bc

#####    CONFIG    ##################################################################################################
config=""              # config.toml file for node, eg. /home/user/.gaiad/config/config.toml
nprecommits=20         # check last n precommits, can be 0 for no checking
validatoraddress=""    # if left empty default is from status call (validator)
checkpersistentpeers=1 # if 1 the number of disconnected persistent peers is checked (when persistent peers are configured in config.toml)
logname=""             # a custom log file name can be chosen, if left empty default is nodecheck-<username>.log
logpath="$(pwd)"       # the directory where the log file is stored, for customization insert path like: /my/path
logsize=200            # the max number of lines after that the log will be trimmed to reduce its size
sleep1=30              # polls every sleep1 sec
#####  END CONFIG  ##################################################################################################


if [ -z $config ]; then echo "please configure config.toml in script"; exit 1;fi
url=$(sed '/^\[rpc\]/,/^\[/!d;//d' $config | grep "^laddr\b" | awk -v FS='("tcp://|")' '{print $2}')
chainid=$(jq -r '.result.node_info.network' <<<$(curl -s "$url"/status))
if [ -z $url ]; then echo "please configure config.toml in script correctly"; exit 1;fi
url="http://${url}"

if [ -z $logname ]; then logname="nodemonitor-${USER}.log"; fi
logfile="${logpath}/${logname}"
touch $logfile

echo "log file: ${logfile}"
echo "lcd url: ${url}"
echo "chain id: ${chainid}"

if [ -z $validatoraddress ]; then validatoraddress=$(jq -r '.result.validator_info.address' <<<$(curl -s "$url"/status)); fi
if [ -z $validatoraddress ]; then
    echo "WARNING: lcd appears to be down, start script again when data can be obtained"
    exit 1
fi
echo "validator address: $validatoraddress"

if [ "$checkpersistentpeers" -eq 1 ]; then
    persistentpeers=$(sed '/^\[p2p\]/,/^\[/!d;//d' $config | grep "^persistent_peers\b" | awk -v FS='("|")' '{print $2}')
    persistentpeerids=$(sed 's/@[0-9.:,]\+/ /g' <<<$persistentpeers)
    totpersistentpeerids=$(wc -w <<<$persistentpeerids)
    echo "$totpersistentpeerids persistent peers: $persistentpeerids"
fi

if [ $nprecommits -eq 0 ]; then echo "precommit checks: off"; else echo "precommit checks: on"; fi
if [ $checkpersistentpeers -eq 0 ]; then echo "persistent peer checks: off"; else echo "persistent peer checks: on"; fi
echo ""

date=$(date --rfc-3339=seconds)

nloglines=$(wc -l <$logfile)
if [ $nloglines -gt $logsize ]; then sed -i "1,$(expr $nloglines - $logsize)d" $logfile; fi # the log file is trimmed for logsize
echo "$date status=scriptstarted chainid=$chainid" >>$logfile

while true; do
    status=$(curl -s "$url"/status)
    result=$(grep -c "result" <<<$status)

    if [ "$result" != 0 ]; then
        npeers=$(curl -s "$url"/net_info | jq -r '.result.n_peers')
        if [ -z $npeers ]; then npeers="na"; fi
        blockheight=$(jq -r '.result.sync_info.latest_block_height' <<<$status)
        blocktime=$(jq -r '.result.sync_info.latest_block_time' <<<$status)
        catchingup=$(jq -r '.result.sync_info.catching_up' <<<$status)
        if [ $catchingup == "false" ]; then catchingup="synced"; elif [ $catchingup == "true" ]; then catchingup="catchingup"; fi
        validatoraddresses=$(curl -s "$url"/block?height="$blockheight" | jq '.result.block.last_commit.precommits[].validator_address')
        validatorprecommit=$(grep -c "$validatoraddress" <<<$validatoraddresses)
        precommitcount=0
        for ((i = $(expr $blockheight - $nprecommits + 1); i <= $blockheight; i++)); do
            validatoraddresses=$(curl -s "$url"/block?height="$i" | jq '.result.block.last_commit.precommits[].validator_address')
            validatorprecommit=$(grep -c "$validatoraddress" <<<$validatoraddresses)
            precommitcount=$(expr $precommitcount + $validatorprecommit)
        done
        if [ $nprecommits -eq 0 ]; then pctprecommits="1.0"; else pctprecommits=$(echo "scale=2 ; $precommitcount / $nprecommits" | bc); fi

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

        now=$(date --rfc-3339=seconds)
        blockheightfromnow=$(expr $(date +%s -d "$now") - $(date +%s -d $blocktime))
        logentry="$now status=$catchingup blockheight=$blockheight tfromnow=$blockheightfromnow pctprecommits=$pctprecommits npeers=$npeers npersistentpeersoff=$npersistentpeersoff"
        echo "$logentry" >>$logfile

    else
        now=$(date --rfc-3339=seconds)
        logentry="$now status=error"
        echo "$logentry" >>$logfile
    fi

    nloglines=$(wc -l <$logfile)
    if [ $nloglines -gt $logsize ]; then sed -i '1d' $logfile; fi

    echo "$logentry"
    echo "sleep $sleep1"
    sleep $sleep1
done
