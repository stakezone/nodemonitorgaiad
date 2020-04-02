# nodemonitorgaiad
A complete log file based Cosmos gaiad monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files of the node to be monitored and the template zbx_export_templates_nodemonitorgaiad.xml for the Zabbix server.

### Concept

nodemonitor.sh produces log files that look like

```sh
2020-04-02 01:15:24+00:00 status=synced blockheight=1557201 tfromnow=10 pctprecommits=.95 npeers=13 npersistentpeersoff=0
2020-04-02 01:15:54+00:00 status=synced blockheight=1557207 tfromnow=7 pctprecommits=1.00 npeers=12 npersistentpeersoff=0
2020-04-02 01:16:25+00:00 status=synced blockheight=1557212 tfromnow=9 pctprecommits=1.00 npeers=13 npersistentpeersoff=1
```

the log entries are

**status** can be {scriptstarted | error | catchingup | synced} 'error' can have various causes, typically the gaiad process is down
**blockheight** blockheight from lcd call 
**tfromnow** time in seconds since blockheight
**pctprecommits** percentage of last n precommits from blockheight as configured in nodemonitor.sh
**npeers** number of connected peers
**npersistentpeersoff** number of disconnected persistent peers
