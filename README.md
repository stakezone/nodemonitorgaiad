This project is intended pre-Stargate, a new Stargate version with many enhancements will be released under the repository 'nmoncosmos'.

# nodemonitorgaiad
A complete log file based Cosmos gaiad monitoring solution for Zabbix. It consists of the shell script nodemonitor.sh for generating log files on the host and the template zbx_<n>_template_nodemonitorgaiad.xml for the Zabbix server, either version 4.x or 5.x.

### Concept

nodemonitor.sh generates logs that look like:

```sh
2020-04-02 01:15:24+00:00 status=synced blockheight=1557201 tfromnow=10 npeers=13 npersistentpeersoff=0 isvalidator=yes pctprecommits=.95 pcttotcommits=.99
2020-04-02 01:15:54+00:00 status=synced blockheight=1557207 tfromnow=7 npeers=12 npersistentpeersoff=1 isvalidator=yes pctprecommits=1.00 pcttotcommits=1.0
2020-04-02 01:16:25+00:00 status=synced blockheight=1557212 tfromnow=9 npeers=13 npersistentpeersoff=0 isvalidator=yes pctprecommits=1.00 pcttotcommits=1.0
```
For the Zabbix server there is a log module for analyzing log data.

The log line entries are:

* **status** can be {scriptstarted | error | catchingup | synced} 'error' can have various causes, typically the gaiad process is down
* **blockheight** blockheight from lcd call 
* **tfromnow** time in seconds since blockheight
* **npeers** number of connected peers
* **npersistentpeersoff** number of disconnected persistent peers
* **isvalidator** if validator metrics are enabled, can be {yes | no}
* **pctprecommits** if validator metrics are enabled, percentage of last n precommits from blockheight as configured in nodemonitor.sh
* **pcttotcommits** if validator metrics are enabled, percentage of total commits of the validator set at blockheight
  
### Installation

The script for the host has a configuration section on top where parameters can be set.

A Zabbix server is required that connects to the host running gaiad. On the host side the Zabbix agent needs to be installed and configured for active mode (is not default). There is various information on the Zabbix site and from other sources that explains how to connect a host to the server and utilize the standard Linux OS templates for general monitoring. Once these steps are completed the gaiad template file can be imported. Under `All templates/Template App Cosmos Gaiad` there is a `Macros` section with several parameters that can be configured, in particular the path to the log file must be set. Do not change those values there, instead go to `Hosts` and select the particular host, then go to `Macros`, then to `Inherited and host macros`. There the macros from the generic template are mirrored for the specific host and can be set without affecting other hosts using the same template.

### Note

For monitoring multiple gaiad instances on the same host the Cosmos Gaiad template needs to be cloned in the template section of the server by making use of the clone function.

### Issues

The Zabbix server is low on resources and a small size VPS is sufficient. However, lags can occur with the log file module. Performance problems with the server are mostly caused by the underlying database slowing down the processing. Database tuning might improve on the issues as well as changing the default Zabbix server parameters for caching etc.

### Update

The 5.x version of Zabbix is now supported with a new template file that utilizes some of the new features (update recommended). For npeers there is a new 'below 15% of 1d avg' trigger. This trigger is not enabled by default as it is more resources intensive for the Zabbix server, it can be set to active in the Template section if desired, or has its default trigger values changed. 
