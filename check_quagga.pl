#!/usr/bin/perl -w

# ============================== Summary =======================================
# Program : check_quagga.pl
# Version : 1.01
# Date : August 15 2012
# Author : Pierre Cheynier <pierre.cheynier@sfr.com>
# Summary : This is a Nagios plugin that allows to check some Quagga metrics
#
# ================================ Description =================================
# The plugin is capable of check key/numeric value pairs given by "sh(ow)" commands. 
# It connects to the Quagga shell (named VTYSH) via telnet, run a command and extract 
# the desired value. It can be used to monitor Memory, BGP Peers, and many other things. 
# Check usage for how to use them.
# ================================ Change log ==================================
# Legend:
# [*] Informational, [!] Bugix, [+] Added, [-] Removed
#
# Ver 1.1:
# [!] Some checks requires privileges, add "en" switch.
#
# Ver 1.0:
# [*] Initial implementation.
# ========================== START OF PROGRAM CODE =============================

use strict;
use warnings;

use Nagios::Plugin;
use Net::Telnet;
use Data::Dumper;

=pod

=head1 NAME 

check_quagga.pl - Quagga telnet check

=head1 DESCRIPTION

This plugin is capable to check Quagga key/numeric value pairs given by "sh(ow)" commands. 
It connects to the Quagga shell (named VTYSH) via telnet, run a command and extract 
the desired value. It can be used to monitor Memory, BGP Peers, and many other things. 

=head1 AUTHOR

Pierre Cheynier <pierre.cheynier@sfr.com>

=head1 LICENSE

This script is free software; you may redistribute it and/or modify it under the same terms 
as Perl itself.

=head1 USAGE

=head2 Quagga Configuration

You should include this in your main configuration file
C<vtysh_enable=yes>

And for every enabled daemon, include these options at runtime
C<--daemon --vty_addr=ip_address --vty_port=port>

Please keep in mind that you should secure this part via iptables or listen/bind only on a private administrative interface,
and securing this shell by a password

=head2 Arguments

=over 4

=item Port

Default ports are specified in F</etc/services>

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

=item Command

This is the VTYSH command output-ing the result you want

=item Filter

This is a filter to grep the key/value pair you want (separator ":")

=item Warning and critical values

This part implements Nagios Plugin Development Guidelines L<https://nagios-plugins.org/doc/guidelines.html>
by using the perl API

=back

=head2 Examples

Check if there is more than 100 BGP IPv6 prefixes announced, produce a perfdata-compliant output

  perl check_quagga.pl -H vty_addr -p vty_port(bgpd) -P quaggapwd  -C "sh bgp ipv6 unicast statistics" -F "Total Prefixes" -f -n "bgp_prefixes" -c 100:

Check heap memory usage

  perl check_quagga.pl -H vty_addr -p vty_port(bgpd) -P quaggapwd  -C "sh mem" -F "Total heap allocated" -n heap_memory -f

=cut


# Variables
# -------------------------------------------------------------------------- #
my $_VERSION        = '1.0';
my $_NAME           = $0;
my $_TIMEOUT        = 15;         # Default 15s Timeout

# Functions
# -------------------------------------------------------------------------- #
sub get_versioninfo { return "$_NAME version : $_VERSION"; }

sub get_usage {
    return "Usage: $_NAME [-H=<host>] [-p=<port>] [-P=<password>] [-e] [-C=<vtysh command>] [-F=<filter>] [-n=<metric-name>] [-w=<warn_level>] [-c=<crit_level>] [-f] [-V]";
}

# Entry point of the script
# -------------------------------------------------------------------------- #

# Instantiate new Nagios Plugin
my $np = Nagios::Plugin->new(
    shortname => 'Check Quagga',
    usage     => get_usage(),
    version   => get_versioninfo()
);

# Give program specific arguments (help, version and timeout are managed by NP) and retrieve it
$np->add_arg(   spec => 'host|H=s',         required => 1,  help => "Hostname" );
$np->add_arg(   spec => 'port|p=s',         required => 1,  help => "Port to connect to" );
$np->add_arg(   spec => 'password|P=s',     required => 1,  help => "VTYSH Password" );
$np->add_arg(   spec => 'en|e',  		    required => 0,  help => "Requires to gain privileges (via 'en')" );
$np->add_arg(   spec => 'command|C=s',      required => 1,  help => "Command to execute" );
$np->add_arg(   spec => 'filter|F=s',       required => 0,  help => "grep Filter" );
$np->add_arg(   spec => 'name|n=s',         required => 1,  help => "metric name used to print perfdata" );
$np->add_arg(   spec => 'warning|w=i',      required => 0,  help => "warning limit"   );
$np->add_arg(   spec => 'critical|c=i',     required => 0,  help => "critical limit"  );
$np->add_arg(   spec => 'f',                required => 0,  help => "print performance data"    );
$np->getopts;

# Telnet to quagga vtysh
# Connect to host
my $telnet = new Net::Telnet (
    Telnetmode => 0,
    Timeout => 5
);
$telnet->open(Host => $np->opts->host, Port => $np->opts->port) or
  $np->nagios_exit( UNKNOWN, "Can't connect to $np->opts->host:$np->opts->port!" );
# Authenticate
$telnet->waitfor('/Password:.*$/');
$telnet->cmd($np->opts->password);
# Verify that we are logged in (TODO matching a prompt is not sufficient)
$telnet->prompt('/.*>/'); # match a traditionnal vtysh prompt
# > en to get privileges
if (defined($np->opts->en)) {
	$telnet->cmd("en"); 
	$telnet->prompt('/.*#/');
}
# >/# [cmd]
my @result = $telnet->cmd(
    String => $np->opts->command,
    Cmd_remove_mode => 1
);
# Close telnet connection
$telnet->close;

my $filter = $np->opts->filter;
my @matches = grep(/$filter/, @result);
$np->nagios_exit( UNKNOWN, "No output match with the filter given" ) if (scalar(@matches) == 0); 

# Extract only numbers from this result 
# (TODO consider a more complex expression to grep in the middle of unformated outputs)
$matches[0] =~ s/[^0-9]//g;
my $ret_value = $matches[0];

# Add perfdata
if ( defined($np->opts->f) ) {
    $np->add_perfdata(
        label => "'".$np->opts->name."'",
        value => $ret_value
    );
}

# Compute the realserver thresholds & compare to w&c
my $return_const = OK;
if ( defined($np->opts->warning) || defined($np->opts->critical) ) {
    # Numeric comparison
    $return_const = $np->check_threshold( check => $ret_value, warning => $np->opts->warning, critical => $np->opts->critical );
}

my $message = ( defined($np->opts->name) ? $np->opts->name : $np->opts->filter ) . ":" . $ret_value;

# Return
$np->nagios_exit(
    return_code => $return_const,
    message     => $message
);

