check_quagga
===============================================================================

Nagios check for Quagga software routing suite

## Description : 

This plugin is capable to check Quagga key/numeric value pairs given by "sh(ow)" commands.  
It connects to the Quagga shell (named VTYSH) via telnet, run a command and extract the desired value.  
It can be used to monitor Memory, BGP Peers, and many other things.

## Usage :

### Prerequisites :

```perl
Nagios::Plugin
Net::Telnet
```

In Debian from 5.0 you can apt-get install these packages

```bash
libnet-telnet-perl
libnagios-plugin-perl 
```

### Run :

```bash
    git clone https://github.com/sfr-network-service-platforms/check_quagga.git
    perl check_quagga.pl <...>
```

### Quagga Configuration :
 
You should include this in your main configuration file 
```bash
    vtysh_enable=yes
```

And for every enabled daemon, include these options at runtime 
```bash
    --daemon --vty_addr=ip_address --vty_port=port
```

Please keep in mind that you should secure this part via iptables or listen/bind only on a private administrative interface, and securing this shell by a password

### Arguments :

- Port : Default ports are specified in /etc/services

Here are my own for Quagga :

    zebrasrv    2600/tcp            # zebra service
    zebra       2601/tcp            # zebra vty
    ripd        2602/tcp            # ripd vty (zebra)
    ripngd      2603/tcp            # ripngd vty (zebra)
    ospfd       2604/tcp            # ospfd vty (zebra)
    bgpd        2605/tcp            # bgpd vty (zebra)
    ospf6d      2606/tcp            # ospf6d vty (zebra)
    ospfapi     2607/tcp            # OSPF-API
    isisd       2608/tcp            # ISISd vty (zebra)

- Command : This is the VTYSH command output-ing the result you want

- Filter : This is a filter to grep the key/value pair you want (separator ":")

- Warning and critical values : This part implements [Nagios Plugin Development Guidelines] (https://nagios-plugins.org/doc/guidelines.html) by using the perl API

### Examples : 


* Check if there is more than 100 BGP IPv6 prefixes announced, produce a perfdata-compliant output

```bash
    perl check_quagga.pl -H vty_addr -p vty_port(bgpd) -P quaggapwd  -C "sh bgp ipv6 unicast statistics" -F "Total Prefixes" -f -n "bgp_prefixes" -c 100:
```

* Check heap memory usage

```bash
    perl check_quagga.pl -H vty_addr -p vty_port(bgpd) -P quaggapwd  -C "sh mem" -F "Total heap allocated" -n heap_memory -f
```
