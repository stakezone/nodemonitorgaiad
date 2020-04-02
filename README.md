# nodemonitorgaiad
A complete log file based Cosmos gaiad monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files of the node to be monitored and the template zbx_export_templates_nodemonitorgaiad.xml for the Zabbix server.

### Concept

nodemonitor.sh produces log files that look like:

```sh
2020-04-02 01:15:24+00:00 status=synced blockheight=1557201 tfromnow=10 pctprecommits=.95 npeers=13 npersistentpeersoff=0
2020-04-02 01:15:54+00:00 status=synced blockheight=1557207 tfromnow=7 pctprecommits=1.00 npeers=12 npersistentpeersoff=0
2020-04-02 01:16:25+00:00 status=synced blockheight=1557212 tfromnow=9 pctprecommits=1.00 npeers=13 npersistentpeersoff=1
```

The log entries are:

* **status** can be {scriptstarted | error | catchingup | synced} 'error' can have various causes, typically the gaiad process is down
* **blockheight** blockheight from lcd call 
* **tfromnow** time in seconds since blockheight
* **pctprecommits** percentage of last n precommits from blockheight as configured in nodemonitor.sh
* **npeers** number of connected peers
* **npersistentpeersoff** number of disconnected persistent peers

### Installation

A Zabbix server is required that connects to the host running gaiad. On the host side the Zabbix agent needs to be installed and configured as active. There is various information on the Zabbix site and from other sources that outline how to connect a host to the server and utilize the standard Linux OS template for general monitoring. Once these steps are completed the gaiad template zbx_export_templates_nodemonitorgaiad.xml can be imported. Under `All templates/Template App Cosmos Gaiad` there is a `Macros` section where several parameters that need to be set, in particular the path to the log file on the host must be configured.

### Note

For monitoring multiple gaiad on the same host the Cosmos Gaiad template needs to be cloned in the template section of the server with the clone function.

###Issues

The Zabbix server is low on resources and a small size VPS is sufficient. However, delays can occur with the log file module. Performance problems with the server are mostly an issue of the underlying database slowing down the processing. Database tuning might improve the slowness (ie. more cache size etc.).

The gaiad triggers are not optimized, some redundant alerts might occur.
