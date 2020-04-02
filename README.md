# nodemonitorgaiad
A complete log file based Cosmos gaiad monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files on the host and the template zbx__template_nodemonitorgaiad.xml for the Zabbix server.

### Concept

nodemonitor.sh produces logs that look like:

```sh
2020-04-02 01:15:24+00:00 status=synced blockheight=1557201 tfromnow=10 pctprecommits=.95 npeers=13 npersistentpeersoff=0
2020-04-02 01:15:54+00:00 status=synced blockheight=1557207 tfromnow=7 pctprecommits=1.00 npeers=12 npersistentpeersoff=1
2020-04-02 01:16:25+00:00 status=synced blockheight=1557212 tfromnow=9 pctprecommits=1.00 npeers=13 npersistentpeersoff=0
```
For the Zabbix server there is a log module for analyzing log data.

The log line entries are:

* **status** can be {scriptstarted | error | catchingup | synced} 'error' can have various causes, typically the gaiad process is down
* **blockheight** blockheight from lcd call 
* **tfromnow** time in seconds since blockheight
* **pctprecommits** percentage of last n precommits from blockheight as configured in nodemonitor.sh
* **npeers** number of connected peers
* **npersistentpeersoff** number of disconnected persistent peers

### Installation

The script for the host has a configuration section where parameters can be set on top.

A Zabbix server is required that connects to the host running gaiad. On the host side the Zabbix agent needs to be installed and configured for active mode (is not default). There is various information on the Zabbix site and from other sources that outline how to connect a host to the server and utilize the standard Linux OS templates for general monitoring. Once these steps are completed the gaiad template file can be imported. Under `All templates/Template App Cosmos Gaiad` there is a `Macros` section with several parameters that can be configured, in particular the path to the log file must be set. Do not change those values there, instead go to `Hosts` and select the particular host, then go to `Macros`, then to `Inherited and host macros`. There the macros from the generic template are mirrored for the specific host and can be set without affecting other hosts using the same template.

### Note

For monitoring multiple gaiad instances on the same host the Cosmos Gaiad template needs to be cloned in the template section of the server making use of the clone function.

### Issues

The gaiad triggers are not optimized and interconnected yet, some redundant alerts might occur.

The Zabbix server is low on resources and a small size VPS is sufficient. However, lags can occur with the log file module. Performance problems with the server are mostly caused by the underlying database slowing down the processing. Database tuning might improve on the issues (increase cache size etc.).
