#!/usr/bin/env perl

#NOTE: 
#Current (AMPS) is stored in tenths in tables (divide by 10)

##################
# Purpose:  Checked with:  Vertiv RDU101 & IS-UNITY-DP, Tripplite WEBCARDLX, UHSA
# Changelog:
#	* 6/15/2021 - Initial Release
#	* 1/10/2022 - Removed 'switch' dependency
#	* 3/04/2022 - New Dependency Perl Module Time::Piece
#	* 3/04/2022 - Retrieves Battery Last Replaced Date (Vertiv RDU101 Cards)
##############################
my $prog_author  = "Brandon McCorkle";
my $prog_date    = "January 10th, 2022";
my $prog_name    = "check_ups_status.pl";
my $prog_version = "1.0.4";

#
# Copyright (c) 2021, Brandon McCorkle <brandon.mccorkle@gmail.com>
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#	* Redistributions of source code must retain the above copyright
#	  notice, this list of conditions and the following disclaimer.
#	* Redistributions in binary form must reproduce the above copyright
#	  notice, this list of conditions and the following disclaimer in the
#	  documentation and/or other materials provided with the distribution.
#	* Neither the name of the <organization> nor the
#	  names of its contributors may be used to endorse or promote products
#	  derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL BRANDON MCCORKLE BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use warnings;
use strict;
use Net::SNMP;
use Math::BigFloat;
Math::BigFloat->precision(-3);
use Getopt::Long;
Getopt::Long::config('auto_abbrev');
use Time::Piece;



#####
# VARIABLES
#####
## SNMP Connection Variables
my $snmp_community		= "";
my $snmp_host;
my $snmp_port                   = 161;
my $snmp_timeout                = 5;	#Seconds
my $snmp_version                = 1;
my $snmp_username		= "";
my $snmp_seclevel		= "noauthnopriv";
my $snmp_authprotocol		= "sha";
my $snmp_authpassword		= "";
my $snmp_privprotocol		= "aes";
my $snmp_privpassword		= "";
my $session;
my $error;

## Threshold Variables
my $warn_charge_remain		= 10;	#Percent
my $crit_charge_remain		= 5;	#Percent
my $warn_load			= 80;	#Percent
my $crit_load			= 90;   #Percent
my $warn_load_va;			#VA (Calculated off of %Load)
my $crit_load_va;			#VA (Calculated off of %Load)
my $warn_time_remain		= 2;	#Minutes
my $crit_time_remain		= 1;	#Minutes
my $warn_batt_status		= 3;	#1=Normal, 2=Unknown, 3=Low, 4=Depleted
my $crit_batt_status		= 4;	#1=Normal, 2=Unknown, 3=Low, 4=Depleted

## Arrays to return oid values (Global so they return both)
my $result_identity;
my $result_agent;
my $result_input_table;
my $result_output;
my $result_output_table;
my $result_battery;
my $result_config;
my $result_alarm;
my $result_tripplite;
my $result_vertiv;
my %hash_identity;
my %hash_input;
my %hash_output;
my %hash_battery;
my %hash_config;
my %hash_tripplite;
my %hash_vertiv;
my %hash_vertiv_agent_model;

## Reference Only (We use the whole OID below instead)
my $mib2 = '1.3.6.1.2.1';
my $enterprises = '1.3.6.1.4.1';
my $upsmib = "$mib2.33";
my $vertiv = "$enterprises.476";

## UPS Generic Identification OIDs
my $oid_upsIdentManufacturer		= "1.3.6.1.2.1.33.1.1.1.0";
my $oid_upsIdentModel          		= "1.3.6.1.2.1.33.1.1.2.0";
my $oid_upsIdentUPSSoftwareVersion 	= "1.3.6.1.2.1.33.1.1.3.0";
my $oid_upsIdentAgentSoftwareVersion	= "1.3.6.1.2.1.33.1.1.4.0";
my $oid_upsIdentName			= "1.3.6.1.2.1.33.1.1.5.0";

## UPS Generic Battery OIDs
my $oid_battery_status		= "1.3.6.1.2.1.33.1.2.1.0";     # Battery Status (1=Unknown, 2=Normal, 3=Low, 4=Depleted)
my $oid_battery_seconds        	= "1.3.6.1.2.1.33.1.2.2.0";     # Seconds on Battery
my $oid_battery_min_remain     	= "1.3.6.1.2.1.33.1.2.3.0";     # Battery Remaining (Min)
my $oid_battery_charge_remain	= "1.3.6.1.2.1.33.1.2.4.0";     # Charge Remaining (Min)
my $oid_battery_alarm_count  	= "1.3.6.1.2.1.33.1.6.1.0";     # Number of Alarms

## UPS Generic Input OIDs
my $oid_input_numlines          = "1.3.6.1.2.1.33.1.3.2.0";     # Input Number of Lines
my $oid_input_table		= "1.3.6.1.2.1.33.1.3.3.1";	# Input Table (Frequency, Voltage, Current, True Power)

## UPS Generic Output OIDs
my $oid_output_source           = "1.3.6.1.2.1.33.1.4.1.0";     # Output Source (1=Other, 2=None, 3=Normal, 4=Bypass, 5=Battery, 6=Booster, 7=Reducer)
my $oid_output_freq             = "1.3.6.1.2.1.33.1.4.2.0";     # Output Frequency
my $oid_output_numlines         = "1.3.6.1.2.1.33.1.4.3.0";     # Output Number of Lines
my $oid_output_table		= "1.3.6.1.2.1.33.1.4.4.1";	# Output Table (Voltage, Current, Power, Percent Load)

## UPS Generic Config OIDs
my $oid_config_max_va           = "1.3.6.1.2.1.33.1.9.5.0";     # Maximum Output VA

## UPS Alarm OIDs
my $oid_alarm_tripplite_table	= "1.3.6.1.4.1.850.1.3.2.1";			# Alarm Table (Tripplite Defined Alarms)
my $oid_alarm_vertiv_table   	= "1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100";   # Alarm Table (Vertiv Defined Alarms)
my $oid_alarm_table		= "1.3.6.1.2.1.33.1.6.2";			# Alarm Table (Generic Defined Alarms)

## Vertiv GXT3-GXT5 OIDs
my $oid_vertiv_brownouts		= "1.3.6.1.4.1.476.1.42.3.5.8.1.0";			# Brownout Count
my $oid_vertiv_blackouts       		= "1.3.6.1.4.1.476.1.42.3.5.8.2.0";   			# Blackout Count
my $oid_vertiv_batt_lastreplaced 	= "1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.1.4160";  	# Date of Last Battery Replacement
my $oid_vertiv_input_volts_L1_L2 	= "1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.1.4097";	# System Input Voltage (L1-L2)
my $oid_vertiv_output_appar_pwr 	= "1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.1.4209";	# System Output Apparent Power (VA)
my $oid_vertiv_system_status   		= "1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.1.4123";  	# System Status (1=Normal Operation, 2=Startup, 8=Normal with Warning, 16=Normal with Alarm, 32=Abnornal Operation)
my $oid_vertiv_agent_model     		= "1.3.6.1.4.1.476.1.42.2.1.2.0";                 	# Agent Model (Card Model)
my $oid_battery_test_result    		= "1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.1.6181";	# Battery Test Result
my $oid_battery_charge_percent 		= "1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.1.4153";	# Battery Percent Charge

## Tripplite OIDs (WEBCARDLX)
my $oid_tripplite_load			= "1.3.6.1.4.1.850.1.1.3.1.3.3.2.1.5.1.1";		# Output Load (%)
my $oid_tripplite_usedVA		= "1.3.6.1.4.1.850.1.1.3.2.3.2.1.1.12.1.1";		# Power Usage in VA

## SNMP Input Table Arrays
my @i_index = ("Index");							# Label for i_index Array
my @i_freq = ("Freq");								# Label for i_freq Array
my @i_volt = ("Volts");								# Label for i_volt Array
my @i_curr = ("Amps");								# Label for i_curr Array
my @i_truepower = ("True Power");						# Label for i_truepower Array
my @input_table = ( \@i_index, \@i_freq, \@i_volt, \@i_curr, \@i_truepower );	# UPS SNMP Input Table Array

## SNMP Output Table Arrays
my @o_index = ("Index");                                                        # Label for o_index Array
my @o_volt = ("Volts");                                                      	# Label for o_volt Array
my @o_curr = ("Amps");                                                        	# Label for o_curr Array
my @o_truepower = ("True Power");                                               # Label for o_truepower Array
my @o_load = ("Load");                                                          # Label for o_load Array (Load in %)
my @output_table = ( \@o_index, \@o_volt, \@o_curr, \@o_truepower, \@o_load );  # UPS SNMP Input Table Array

## Program Variables
my $debug		= 0;	# Set to 1 to Debug
my $alarm_cnt		= 0;
my $alarm_info		= "";
my $PERF_DATA		= "";
my $alarm_display	= 3;
my $custom_display	= "lstb";
my $hide_exit_status	= 0;
my $flag_warn		= 0;
my $flag_crit		= 0;
my $print_help 		= 0;
my $print_version	= 0;
my $EXIT_STATE		= "";

## UPS Shortened Variables
my $batt_date;                  # Battery Last Replaced Date (RDU101 Cards Only)
my $batt_status;		# Battery Status
my $blackouts;			# Number of Blackouts
my $brownouts;			# Number of Brownouts
my $charge_remain;		# Battery Charge Remaining in Minutes
my $input_voltage;		# Input Voltage
my $load;			# Load in VA
my $load_percent;		# Load in Percent
my $model;			# UPS Model
my $output_current;		# Output Current
my $output_source;		# Output Source
my $output_voltage;		# Output Voltage
my $time_remain;		# Battery Time Remaining
my $va_capacity;		# VA Capacity of UPS

## Icinga2 Status Codes:
my $STATE_OK		= 0;
my $STATE_WARNING	= 1;
my $STATE_CRITICAL	= 2;
my $STATE_UNKNOWN	= 3;



#####
# HELP MESSAGE
#####
sub display_help(){
	system("clear");
        printf "scriptname [options]\n";
        printf "        -h\tHelp\n";
        printf "        -V\tVersion\n";
        printf "        -C\tSNMP Community\n";
        printf "        -H\tHostname\n";
        printf "        -p\tSNMP Port (Default: 161)\n";
        printf "        -t\tSNMP Timeout (Default 5 sec)\n";
	printf "	-v\tSNMP Version [2|3]  (Default: 2)\n";
	printf "	-a\tAlarm Output Format [1=count|2=short|3=long]  (Default: Long)\n";
	printf "	\t1 = Alarm Count / Load Information\n";
	printf "	\t2 = Alarm Count / Load Information (Details on Multiline)\n";
	printf "	\t3 = Alarm Count & Details (May overrun line)\n";
        printf "        -d\tDisplay Output Format [l|s|t|b] (Order Changes Displayed Order)*\n";
        printf "        \tl = Show Load Information\n";
        printf "        \ts = Show Status of Battery and Output\n";
        printf "        \tt = Show Time Remaining and Charge %%\n";
        printf "        \tb = Show Brownouts & Blackouts (Vertiv Only)\n";
        printf "        \t* First Option is Line 1 output (Alarms Override, See -a)\n";
	printf "	-z\tDON'T Print exit status on Line 1 (Hate duplication)\n";
	printf "	--un\tSNMPv3 Username\n";
	printf "	--sl\tSNMPv3 Security Level [noauthnopriv|authnopriv|authpriv] (Default: noauthnopriv)\n";
	printf "	--ap\tSNMPv3 Auth Protocol [md5|sha] (Default: sha)\n";
	printf "	--ak\tSNMPv3 Auth Password\n";
	printf "	--pp\tSNMPv3 Privacy Protocol [des|aes] (Default: aes)\n";
        printf "        --pk\tSNMPv3 Privacy Password\n";
	printf "        --wc\tWARN: On Remaining %% of Battery Charge (Default: 10%%)\n";
	printf "	--cc\tCRIT: On Remaining %% of Battery Charge (Default:  5%%)\n";
        printf "        --wl\tWARN: On Percent of Battery Load (Integer) (Default: 80%%)\n";
        printf "        --cl\tCRIT: On Percent of Battery Load (Integer) (Default: 90%%)\n";
	printf "	--wt\tWARN: On Minutes of Battery Remaining (Default: 2 min)\n";
	printf "	--ct\tCRIT: On Minutes of Battery Remaining (Default: 1 min)\n";
	printf "	--ws\tWARN: On Battery Status: (1=Normal, 2=Unknown, 3=Low, 4=Depleted)\n";
	printf "	--cs\tCRIT: On Battery Status: (1=Normal, 2=Unknown, 3=Low, 4=Depleted)\n";
	printf "\n";
        printf "     Example: ./check_ups_status.pl -C public -H 193.168.3.30 -ws 3 -cs 4 \n";
	printf "\n\n";
}



#####
# Retrieve Options
#####
Getopt::Long::Configure('bundling');
my $status = GetOptions
        ("h+"           =>      \$print_help,
         "V+"           =>      \$print_version,
	 "C=s"          =>      \$snmp_community,
         "H=s"          =>      \$snmp_host,
         "p=i"          =>      \$snmp_port,
         "t=i"          =>      \$snmp_timeout,
	 "v=i"		=>	\$snmp_version,
	 "a=i"		=>	\$alarm_display,
	 "d=s"		=>	\$custom_display,
	 "z!"		=>	\$hide_exit_status,
	 "un=s"		=>	\$snmp_username,
	 "sl=s"		=>	\$snmp_seclevel,
	 "ap=s"		=>	\$snmp_authprotocol,
	 "ak=s"		=>	\$snmp_authpassword,
	 "pp=s"		=>	\$snmp_privprotocol,
	 "pk=s"		=>	\$snmp_privpassword,
         "wc=i"         =>      \$warn_charge_remain,
         "cc=i"         =>      \$crit_charge_remain,
         "wl=i"         =>      \$warn_load,
         "cl=i"         =>      \$crit_load,
         "wt=i"         =>      \$warn_time_remain,
         "ct=i"         =>      \$crit_time_remain,
         "ws=i"         =>      \$warn_batt_status,
         "cs=i"         =>      \$crit_batt_status)
	or exit 1;

if ($print_help != 0) {
	display_help;
	exit;
}
elsif ($print_version !=0) {
	print "$prog_name by $prog_author | Released: $prog_date | Version: $prog_version\n\n";
	exit;
}



#####
# SANITIZE OPTIONS
#####
sub sub_sanitize() {

	my ($char, $len, $temp, $warn_msg, $crit_msg);

	#Check Custom Alarms Option
	if ($alarm_display >= 1 && $alarm_display <= 3) {
		# We're Okay
	}
	else {
		print "Option -a: Invalid Number\n\n";
		exit 1;
	}

	#Check Custom Display Output Option
	if ( length($custom_display) > 4 ) {
		print "Option -d: To many Characters\n\n";
		exit 1;
	}
	else {
	        $temp = $custom_display;
		$len = length($temp);
		for (1..$len) {
			$char = chop($temp);
			if ($char ne "l" && $char ne "s" && $char ne "t" && $char ne "b") {
				print "Option -d: Invalid Character \'$char\'\n\n";
				exit 1;
			}
		}
	}

	#Check Threshold Option (Load)
        if ( (defined $warn_load && $warn_load < 0) || (defined $warn_load && $warn_load > 100) ) {
                print "Option --wl: Invalid Percent (0 to 100)\n\n";
                exit 1;
        }
        if ( (defined $crit_load && $crit_load < 0 || defined $crit_load && $crit_load > 100) ) {
                print "Option --cl: Invalid Percent (0 to 100)\n\n";
                exit 1;
	}

        #Check Threshold Option (Battery Charge Remaining)
        if ( (defined $warn_charge_remain && $warn_charge_remain < 0) || (defined $warn_charge_remain && $warn_charge_remain > 100) ) {
                print "Option --wc: Invalid Percent (0 to 100)\n\n";
                exit 1;
        }
        if ( (defined $crit_charge_remain && $crit_charge_remain < 0 || defined $crit_charge_remain && $crit_charge_remain > 100) ) {
                print "Option --cc: Invalid Percent (0 to 100)\n\n";
                exit 1;
        }

	#Check Threshold Option (Battery Minutes Remaining)
        if ( defined $warn_time_remain && $warn_time_remain < 0 ) {
                print "Option --wt: Invalid Number (Negative)\n\n";
                exit 1;
        }
        elsif ( defined $crit_time_remain && $crit_time_remain < 0 ) {
                print "Option --ct: Invalid Number (Negative)\n\n";
                exit 1;

        }

	#Check Threshold Option (Battery Status)
	if ( (defined $warn_batt_status && $warn_batt_status > 4) || (defined $warn_batt_status && $warn_batt_status < 1) ) {
                print "Option --ws: Invalid Number (1 to 4)\n\n";
                exit 1;
	}
        elsif ( (defined $crit_batt_status && $crit_batt_status > 4) || (defined $crit_batt_status && $crit_batt_status < 1) ) {
                print "Option --cs: Invalid Number (1 to 4)\n\n";
                exit 1;
        }

	#Debug
	if ($debug == 1) {
                printf "\n\n";
                printf "DEBUG: Warning & Critical Thresholds...\n";
                printf "DEBUG: Battery Load Thresholds:  Warning: %s%%  Critical: %s%%\n", $warn_load, $crit_load;	
		printf "DEBUG: Battery Time Thresholds:  Warning: %s min  Critical: %s min\n", $warn_time_remain, $crit_time_remain;
		if ($warn_batt_status == 1) {
			$warn_msg = "Normal";
		}
		elsif ($warn_batt_status == 2) {
			$warn_msg = "Unknown";
		}
		elsif ($warn_batt_status == 3) {
			$warn_msg = "Low";
		}
		elsif ($warn_batt_status == 4) {
			$warn_msg = "Depleted";
		}

		if ($crit_batt_status == 1) {
			$crit_msg = "Normal";
		}
		elsif ($crit_batt_status == 2) {
			$crit_msg = "Unknown";
		}
		elsif ($crit_batt_status == 3) {
			$crit_msg = "Low";
		}
		elsif ($crit_batt_status == 4) {
			$crit_msg = "Depleted";
		}

		printf "DEBUG: Battery Stat Thresholds:  Warning: %s(%s)  Critical: %s(%s)\n", $warn_batt_status, $warn_msg, $crit_batt_status, $crit_msg;
	}
}



#####
# HASH DEFINITIONS
#####
sub sub_HASH_IDENTITY() {
        %hash_identity = (
                "snmp_upsIdentManufacturer"     	=> "$oid_upsIdentManufacturer",
                "snmp_upsIdentModel"            	=> "$oid_upsIdentModel",
		"snmp_upsIdentUPSSoftwareVersion"	=> "$oid_upsIdentUPSSoftwareVersion",
		"snmp_upsIdentAgentSoftwareVersion"	=> "$oid_upsIdentAgentSoftwareVersion",
		"snmp_upsIdentName"			=> "$oid_upsIdentName",
                "snmp_input_numlines"			=> "$oid_input_numlines",
        );
}

sub sub_HASH_CONFIG() {
        %hash_config = (
                "snmp_config_max_va"    => "$oid_config_max_va",
        );
}

sub sub_HASH_OUTPUT() {
  	%hash_output = (
        	"snmp_output_source"    => "$oid_output_source",
                "snmp_output_freq"      => "$oid_output_freq",
      	);
}

sub sub_HASH_BATTERY() {
	%hash_battery = (
        	"snmp_battery_status"           => "$oid_battery_status",
                "snmp_battery_seconds"          => "$oid_battery_seconds",
                "snmp_battery_min_remain"       => "$oid_battery_min_remain",
                "snmp_battery_charge_remain"    => "$oid_battery_charge_remain",
                "snmp_battery_alarm_count"      => "$oid_battery_alarm_count",
	);
}

sub sub_HASH_TRIPPLITE() {
	%hash_tripplite = (
		"oid_tripplite_load"		=> "$oid_tripplite_load",
		"oid_tripplite_usedVA"		=> "$oid_tripplite_usedVA",
	);
}

sub sub_HASH_VERTIV_AGENT_MODEL() {
	%hash_vertiv_agent_model = (
                "snmp_vertiv_agent_model"       => "$oid_vertiv_agent_model",
	);
}

sub sub_HASH_VERTIV_UNITY() {
	%hash_vertiv = (
        	"snmp_vertiv_brownouts"         	=> "$oid_vertiv_brownouts",
                "snmp_vertiv_blackouts"         	=> "$oid_vertiv_blackouts",
                "snmp_vertiv_output_appar_pwr"  	=> "$oid_vertiv_output_appar_pwr",
                "snmp_vertiv_system_status"     	=> "$oid_vertiv_system_status",
                "snmp_battery_test_result"      	=> "$oid_battery_test_result",
                "snmp_battery_charge_percent"   	=> "$oid_battery_charge_percent",
	);
}

sub sub_HASH_VERTIV_UNITY_2Phase() {
        %hash_vertiv = (
                "snmp_vertiv_brownouts"         	=> "$oid_vertiv_brownouts",
                "snmp_vertiv_blackouts"         	=> "$oid_vertiv_blackouts",
                "snmp_vertiv_input_volts_L1_L2"         => "$oid_vertiv_input_volts_L1_L2",
                "snmp_vertiv_output_appar_pwr"  	=> "$oid_vertiv_output_appar_pwr",
                "snmp_vertiv_system_status"     	=> "$oid_vertiv_system_status",
                "snmp_battery_test_result"      	=> "$oid_battery_test_result",
                "snmp_battery_charge_percent"   	=> "$oid_battery_charge_percent",
        );
}

sub sub_HASH_VERTIV_RDU1xx() {
	%hash_vertiv = (
        	"snmp_vertiv_brownouts"         	=> "$oid_vertiv_brownouts",
                "snmp_vertiv_blackouts"         	=> "$oid_vertiv_blackouts",
                "snmp_vertiv_batt_lastreplaced" 	=> "$oid_vertiv_batt_lastreplaced",
                "snmp_vertiv_output_appar_pwr"  	=> "$oid_vertiv_output_appar_pwr",
                "snmp_vertiv_system_status"     	=> "$oid_vertiv_system_status",
                "snmp_battery_test_result"      	=> "$oid_battery_test_result",
                "snmp_battery_charge_percent"   	=> "$oid_battery_charge_percent",
	);
}

sub sub_HASH_VERTIV_RDU1xx_2Phase() {
        %hash_vertiv = (
                "snmp_vertiv_brownouts"                 => "$oid_vertiv_brownouts",
                "snmp_vertiv_blackouts"                 => "$oid_vertiv_blackouts",
                "snmp_vertiv_batt_lastreplaced"         => "$oid_vertiv_batt_lastreplaced",
                "snmp_vertiv_input_volts_L1_L2"         => "$oid_vertiv_input_volts_L1_L2",
                "snmp_vertiv_output_appar_pwr"          => "$oid_vertiv_output_appar_pwr",
                "snmp_vertiv_system_status"             => "$oid_vertiv_system_status",
                "snmp_battery_test_result"              => "$oid_battery_test_result",
                "snmp_battery_charge_percent"           => "$oid_battery_charge_percent",
        );
}



#####
# GET SNMP UPS INPUT TABLE
#####
sub sub_get_snmp_ups_input_table() {
       	my ($x, $y, $oid, $oid_cut, $val, @split_result);
	$result_input_table = $session->get_table( $oid_input_table );

        #Debug
        if ($debug == 1) {
                printf "\n\n";
                printf "DEBUG: Storing UPS SNMP Input Table in \@input_table[X][Y]...\n";
                printf "DEBUG: X=[UPS Input Line] Y=[0=index, 1=frequency, 2=voltage, 3=current, 4=truepower]\n";
        }

        #Store SNMP values from Input Table
        foreach $oid(sort keys %$result_input_table) {

                $val = $result_input_table->{ $oid };

                #split_result[0] = (0=index, 1=frequency, 2=voltage, 3=current, 4=truepower) | split_result[1] = UPS Input Line
                $oid_cut = $oid;
                $oid_cut =~ s/$oid_input_table\.//;
                @split_result = split (/\./, $oid_cut);

                #Don't Store Value if index number (Don't overwrite text Label)
                if ($split_result[0]-1 != 0) {
                        $input_table[$split_result[1]][$split_result[0]-1] = $val;

                        #Debug
                        if ($debug == 1) {
                                printf "DEBUG: Stored %s in \@input_table at:\t[%s][%s]\n", $input_table[$split_result[1]][$split_result[0]-1], $split_result[1], $split_result[0]-1;
                        }
                }
        }

	return;
}



#####
# GET SNMP UPS OUTPUT TABLE
#####
sub sub_get_snmp_ups_output_table() {
	my ($x, $y, $oid, $oid_cut, $val, @split_result);
        $result_output_table = $session->get_table( $oid_output_table );

        #Debug
        if ($debug == 1) {
                printf "\n\n";
                printf "DEBUG: Storing UPS SNMP Output Table in \@output_table[X][Y]...\n";
                printf "DEBUG: X=[UPS Output Line] Y=[0=index, 1=voltage, 2=current, 3=truepower, 4=load]\n";
        }

        #Store SNMP values from Output Table
        foreach $oid(sort keys %$result_output_table) {

                $val = $result_output_table->{ $oid };

                #split_result[0] = (0=index, 1=voltage, 2=current, 3=truepower, 4=load) | split_result[1] = UPS Output Line
                $oid_cut = $oid;
                $oid_cut =~ s/$oid_output_table\.//;
                @split_result = split (/\./, $oid_cut);

                #Don't Store Value if index number (Don't overwrite text Label)
                if ($split_result[0]-1 != 0) {
                        $output_table[$split_result[1]][$split_result[0]-1] = $val;

                        #Debug
                        if ($debug == 1) {
                                printf "DEBUG: Stored %s in \@output_table at:\t[%s][%s]\n", $output_table[$split_result[1]][$split_result[0]-1], $split_result[1], $split_result[0]-1;
                        }
                }
        }

        return;
}



#####
# GET SNMP VALUES FROM UPS
#####
sub sub_get_snmp_ups() {
	my ( @oids, @oids_agent, @oids_config, @oids_output, @oids_battery, @oids_alarm, @oids_tripplite, @oids_vertiv);

	# Establish Connection Depending on Version Used
	if ($snmp_version == 1 || $snmp_version ==2) {
	        ($session,$error) = Net::SNMP->session(
        	        Hostname        =>      $snmp_host,
                	Port            =>      $snmp_port,
	                Version         =>      $snmp_version,
        	        Timeout         =>      $snmp_timeout,
                	Community       =>      $snmp_community,
                );
	}
	elsif ($snmp_version == 3 && $snmp_community eq "") {
        	($session,$error) = Net::SNMP->session(
                	-hostname       =>      $snmp_host,
	                -port           =>      $snmp_port,
        	        -version        =>      $snmp_version,
                	-timeout        =>      $snmp_timeout,
	                -username       =>      $snmp_username,
			-authprotocol	=>	$snmp_authprotocol,
			-authpassword	=>	$snmp_authpassword,
			-privprotocol	=>	$snmp_privprotocol,
			-privpassword	=>	$snmp_privpassword
                );
	}
	else {
		if ($snmp_version == 3 && $snmp_community ne "") {
			printf "Error:  SNMPv3 given but SNMPv2 Community defined";
		}
		exit;
	}

        # Close Connection if Error
        if (!defined($session)){
		printf "ERROR: %s.\n", $error;
#		printf STDERR $session->error();
#		$session->close();
                exit 1;
        }

	#Get Identity Hash
	sub_HASH_IDENTITY;

	@oids = sort values %hash_identity;
	$result_identity = $session->get_request( -varbindlist => \@oids );

	#Debug
	if ($debug == 1) {
		printf "\n\n";
		printf "DEBUG: Retrieved UPS SNMP Identification...\n";
		printf "DEBUG: UPS Manufacturer: $result_identity->{ $hash_identity{ 'snmp_upsIdentManufacturer'}}\n";
		printf "DEBUG: UPS Model:        $result_identity->{ $hash_identity{ 'snmp_upsIdentModel'}}\n";
		printf "DEBUG: UPS Software:     $result_identity->{ $hash_identity{ 'snmp_upsIdentUPSSoftwareVersion'}}\n";
		printf "DEBUG: UPS Agent:      	 $result_identity->{ $hash_identity{ 'snmp_upsIdentAgentSoftwareVersion'}}\n";
		printf "DEBUG: UPS Name:         $result_identity->{ $hash_identity{ 'snmp_upsIdentName'}}\n";
	}

	#Vertiv Manufacturer
	if ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv' ) {
		
		#Get Agent Model
                sub_HASH_VERTIV_AGENT_MODEL;
                @oids_agent = sort values %hash_vertiv_agent_model;
                $result_agent = $session->get_request( -varbindlist => \@oids_agent );

		#Debug
		if ($debug == 1) {
                        printf "\n\n";
	                printf "DEBUG: Retrieved Vertiv Agent...\n";
	                printf "DEBUG: Vertiv Agent:  $result_agent->{$hash_vertiv_agent_model{'snmp_vertiv_agent_model'}}\n";
		}

		#GXT Model
		if ( $result_identity->{$hash_identity{'snmp_upsIdentModel'}} =~ /\QGXT\E/) {

			#Unity Card
			if ( $result_agent->{$hash_vertiv_agent_model{'snmp_vertiv_agent_model'}} eq "IS-UNITY-DP" ) {
				sub_HASH_CONFIG;
				sub_HASH_OUTPUT;
				sub_HASH_BATTERY;
				sub_HASH_VERTIV_UNITY;

                                #Determine if more than 1 input phase to get correct input voltage
                                if ( $result_identity->{$hash_identity{'snmp_input_numlines'}} >= 2 ) {
                                        sub_HASH_VERTIV_UNITY_2Phase;
                                }
                                else {
                                        sub_HASH_VERTIV_UNITY;
                                }
			}

			#RDU1xx Card
			if ( $result_agent->{$hash_vertiv_agent_model{'snmp_vertiv_agent_model'}} eq "RDU1xx Platform" ) {
				sub_HASH_CONFIG;
                                sub_HASH_OUTPUT;
                                sub_HASH_BATTERY;

				#Determine if more than 1 input phase to get correct input voltage
				if ( $result_identity->{$hash_identity{'snmp_input_numlines'}} >= 2 ) {
					sub_HASH_VERTIV_RDU1xx_2Phase;
				}
				else {
	                                sub_HASH_VERTIV_RDU1xx;
				}
			}
		}
	}
	#Tripplite Manufacturer
	elsif ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'TRIPPLITE' ) {
		sub_HASH_CONFIG;
                sub_HASH_OUTPUT;
                sub_HASH_BATTERY;
		sub_HASH_TRIPPLITE;
	}
	#Generic UPS
	else {
		sub_HASH_CONFIG;
                sub_HASH_OUTPUT;
                sub_HASH_BATTERY;
	}

	#Get UPS SNMP Input Table
	sub_get_snmp_ups_input_table;

        #Get UPS SNMP Output Table
        sub_get_snmp_ups_output_table;

        @oids_config = sort values %hash_config;
        $result_config = $session->get_request( -varbindlist => \@oids_config );

        @oids_output = sort values %hash_output;
        $result_output = $session->get_request( -varbindlist => \@oids_output );

        @oids_battery = sort values %hash_battery;
        $result_battery = $session->get_request( -varbindlist => \@oids_battery );

	#Get SNMP Values for Vertiv Information and check for Alarms
	if ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv' ) {
		@oids_vertiv = sort values %hash_vertiv;
		$result_vertiv = $session->get_request( -varbindlist => \@oids_vertiv );	
        	#Check Alarm Count and Get Alarms if not zero
           	if ( $result_battery->{$hash_battery{'snmp_battery_alarm_count'}} != 0 ) {
                	#Use Vertiv Alarm Definitions, else use Generic UPS Alarm Definitions
                        if ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv' ) {
                        	$result_alarm = $session->get_table( $oid_alarm_vertiv_table );
                        }
                        else {
                        	$result_alarm = $session->get_table( $oid_alarm_table );
                        }
                }
	}
	#Get SNMP Values for TRIPPLITE Information and check for Alarms
        elsif ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'TRIPPLITE' ) {
                @oids_tripplite = sort values %hash_tripplite;
                $result_tripplite = $session->get_request( -varbindlist => \@oids_tripplite );
                #Check Alarm Count and Get Alarms if not zero
                if ( $result_battery->{$hash_battery{'snmp_battery_alarm_count'}} != 0 ) {
			$result_alarm = $session->get_table( $oid_alarm_tripplite_table );
                }
	}
	#If not Vertiv or Tripplite, check for Generic UPS Alarms
        else {
                #Check Alarm Count and Get Alarms if not zero
                if ( $result_battery->{$hash_battery{'snmp_battery_alarm_count'}} != 0 ) {
                        $result_alarm = $session->get_table( $oid_alarm_table );
                }
        }

	$session->close();

	return;
}



#####
# Format Variables & Do Calculations
#####
sub sub_convert () {

	#UPS Model Number
	$model = $result_identity->{ $hash_identity{ 'snmp_upsIdentModel' } };

	#Input Voltage
	if ( ($result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv') && ($result_identity->{$hash_identity{'snmp_input_numlines'}} >= 2 ) ) {
		$input_voltage = $result_vertiv->{ $hash_vertiv{ 'snmp_vertiv_input_volts_L1_L2' } };
	}

	else {
		$input_voltage = $input_table[1][2];
	}

        #Output Voltage
	$output_voltage = $output_table[1][1];

	#####
	#Various Statistics Based on Vendor
	#####
	#Vertiv
	if ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv' ) {
                #VA Capacity
                $va_capacity = $result_config->{ $hash_config{ 'snmp_config_max_va' } };

		#Load VA (Use Apparent Power to get VA Directly)
		$load = (int($result_vertiv->{ $hash_vertiv{ 'snmp_vertiv_output_appar_pwr' }}));

        	#Load Percent
	        $load_percent =  $load * 100.0 / $va_capacity;

                #Load Thresholds (Convert from % to VA)
                $warn_load_va = int($va_capacity * ($warn_load/100));
                $crit_load_va = int($va_capacity * ($crit_load/100));

	        #Time Remaining
        	$time_remain = $result_battery->{ $hash_battery{ 'snmp_battery_min_remain' } };

	        #Brownouts / Blackouts
        	$brownouts = $result_vertiv->{ $hash_vertiv{ 'snmp_vertiv_blackouts' } };
        	$blackouts = $result_vertiv->{ $hash_vertiv{ 'snmp_vertiv_brownouts' } };
		
                #Battery Last Replaced (RDU101 Cards Only)
                if ( $result_agent->{$hash_vertiv_agent_model{'snmp_vertiv_agent_model'}} eq "RDU1xx Platform" ) {
                        $batt_date = $result_vertiv->{ $hash_vertiv{ 'snmp_vertiv_batt_lastreplaced' } };
                        $batt_date =~ m/(\d{4}\-(0[1-9]|1[0-2])\-\d{1,2})/;
                        $batt_date = $1;
                        $batt_date = Time::Piece->strptime($batt_date, '%F')->strftime('%D');
                }
	}
	#Tripplite
	elsif ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'TRIPPLITE' ) {
                #VA Capacity
                $va_capacity = $result_config->{ $hash_config{ 'snmp_config_max_va' } };

                #Load Percent
		$load_percent = $output_table[1][4];
		
		#Load VA (Not Provided by SNMP - Reverse Calc)
		$load = $va_capacity * ($load_percent / 100);

		#Load Thresholds (Convert from % to VA)
		$warn_load_va = int($va_capacity * ($warn_load/100));
        	$crit_load_va = int($va_capacity * ($crit_load/100));

		#Time Remaining
		#N/A

		#Brownouts / Blackouts
		#N/A
	}
	#Generic
	else {
                #Load Percent
                $load_percent = $output_table[1][4];
	};

	#Battery Status
	if ($result_battery->{ $hash_battery{ 'snmp_battery_status' } } == 1) {
		$batt_status = "Unknown";
		$flag_warn = ++$flag_warn;
	}
	elsif ($result_battery->{ $hash_battery{ 'snmp_battery_status' } } == 2) {
		$batt_status = "Normal";
	}
	elsif ($result_battery->{ $hash_battery{ 'snmp_battery_status' } } == 3) {
		$batt_status = "Low";
		$flag_warn = ++$flag_warn;
	}
	elsif ($result_battery->{ $hash_battery{ 'snmp_battery_status' } } == 4) {
		$batt_status = "Depleted";
		$flag_crit = ++$flag_crit;
	}

	#Output Source
	if ($result_output->{ $hash_output{ 'snmp_output_source' } } == 1) {
		$output_source = "Other";
		$flag_warn = ++$flag_warn;
	}
	elsif ($result_output->{ $hash_output{ 'snmp_output_source' } } == 2) {
		$output_source = "None";
		$flag_crit = ++$flag_crit;
	}
	elsif ($result_output->{ $hash_output{ 'snmp_output_source' } } == 3) {
		$output_source = "Normal";
	}
	elsif ($result_output->{ $hash_output{ 'snmp_output_source' } } == 4) {
		$output_source = "Bypass";
		$flag_warn = ++$flag_warn;
	}
	elsif ($result_output->{ $hash_output{ 'snmp_output_source' } } == 5) {
		$output_source = "Battery";
		$flag_crit = ++$flag_crit;
	}
	elsif ($result_output->{ $hash_output{ 'snmp_output_source' } } == 6) {
		$output_source = "Booster";
		$flag_warn = ++$flag_warn;
	}
	elsif ($result_output->{ $hash_output{ 'snmp_output_source' } } == 7) {
		$output_source = "Reducer";
		$flag_warn = ++$flag_warn;
	}

	#Charge Remaining
	$charge_remain = $result_battery->{ $hash_battery{ 'snmp_battery_charge_remain' } };

	return;
}



#####
# Threshold Checks
#####
sub sub_check_thresholds () {

	#Load Threshold Check
        if ( $load_percent >= $crit_load ) {
                $flag_crit = ++$flag_crit;
		#Debug
	        if ($debug == 1) {
        	        printf "\n\n";
			printf "DEBUG: CRITICAL ALERT:  Load: %s%% (Threshold: %s%%)\n", $load_percent, $crit_load;
		}
        }
        elsif ( $load_percent >= $warn_load ) {
                $flag_warn = ++$flag_warn;
                #Debug
                if ($debug == 1) {
                        printf "\n\n";
                        printf "DEBUG: WARNING ALERT:  Load: %s%% (Threshold: %s%%)\n", $load_percent, $warn_load;
                }
        }

	#Time Remaining Threshold Check (if available from SNMP)
	if (defined($time_remain)) {
	        if ( $time_remain <= $crit_time_remain ) {
                	$flag_crit = ++$flag_crit;
	                if ($debug == 1) {
        	                printf "\n\n";
                	        printf "DEBUG: CRITIAL ALERT:  Time Remaining: %s min (Threshold: %s min)\n", $time_remain, $crit_time_remain;
	                }
	        }
	        elsif ( $time_remain <= $warn_time_remain ) {
                	$flag_warn = ++$flag_warn;
                        if ($debug == 1) {
                                printf "\n\n";
                                printf "DEBUG: WARNING ALERT:  Time Remaining: %s min (Threshold: %s min)\n", $time_remain, $warn_time_remain;
                        }
		}
	}

	#Charge Remaining Threshold Check
        if ( $charge_remain <= $crit_charge_remain ) {
                $flag_crit = ++$flag_crit;
		if ($debug == 1) {
                	printf "\n\n";
                        printf "DEBUG: CRITIAL ALERT:  Charge Remaining: %s%% (Threshold: %s%%)\n", $charge_remain, $crit_charge_remain;
                }
        }
        elsif ( $charge_remain <= $warn_charge_remain ) {
                $flag_warn = ++$flag_warn;
                if ($debug == 1) {
                        printf "\n\n";
                        printf "DEBUG: WARNING ALERT:  Charge Remaining: %s%% (Threshold: %s%%)\n", $charge_remain, $warn_charge_remain;
                }
        }

        return;
}



#####
# Alarm Description Check
#####
sub sub_check_alarms () {
        my (@array_alarm_def, @found_alarms, $oid, $val);
	my $i = 0;

	$alarm_cnt = $result_battery->{$hash_battery{'snmp_battery_alarm_count'}};

	#Alarm Definitions - Choose Correct Array
	if ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv' ) {
		#Vertiv UPS Alarm Definitions
		@array_alarm_def = (
			#Alarm OIDs                     			#Definition                             #State
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4122',	'System Input Power Problem',		'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4135',	'Bypass Not Available',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4162',	'Battery Low',				'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4168',	'Battery Discharging',			'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4215',	'System Output Off',			'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4229',	'Emergency Power Off - Latched',	'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4233',	'Inverter Failure',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4295',	'Rectifier Failure',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4298',	'UPS Output on Bypass',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4310',	'Equipment Over Temperature',		'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4311',	'System Fan Failure',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4323',	'Battery Test Failed',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4741',	'Battery Self Test',			'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4823',	'Parallel Comm Warning',		'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.4825',	'Loss of Redundancy',			'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5178',	'Output Overvoltage',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5179',	'Output Undervoltage',			'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5568',	'Input Undervoltage',			'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5569',	'Input Overvoltage',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5588',	'Unspecified General Event',		'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5806',	'Output Overload',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5874',	'Battery Over Voltage',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.5976',	'Maintenance Bypass Breaker Closed',	'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.6180',	'Battery Under Voltage',		'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.6182',	'Replace Battery',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.6186',	'Input Frequency Deviation',		'Warning',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.6187',	'Shutdown Pending',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.6254',	'Charger Failure',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.6453',	'Input Wiring Fault',			'Critical',
			'1.3.6.1.4.1.476.1.42.3.9.20.1.20.1.2.100.6454',	'DC to DC Converter Fault',		'Critical',
		);
	}
	elsif ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'TRIPPLITE' ) {

        	#Tripplite UPS Alarm Definitions
                @array_alarm_def = (
                       	#Alarm OIDs			#Definition				#State
			'1.3.6.1.4.1.850.1.3.3.1.1.1',	'Ping Watchdog Ping Probe Failed',	'Warning',
                        '1.3.6.1.4.1.850.1.3.3.1.1.2',	'NTP Watchdog NTP Probe Failed',	'Warning',
                        '1.3.6.1.4.1.850.1.3.3.2.1',	'Communications Lost',			'Warning',
			'1.3.6.1.4.1.850.1.3.3.3.1',	'Load Level Above Threshold',		'Critical',
                        '1.3.6.1.4.1.850.1.3.3.3.2',	'On Battery',				'Critical',
                        '1.3.6.1.4.1.850.1.3.3.3.3',	'Battery Capacity Below Warning Level',	'Critical',
                        '1.3.6.1.4.1.850.1.3.3.3.4',	'Battery Low',				'Critical',
                        '1.3.6.1.4.1.850.1.3.3.3.5', 	'Temperature High',			'Warning',
                        '1.3.6.1.4.1.850.1.3.3.3.8',	'Overload',				'Critical',
			'1.3.6.1.4.1.850.1.3.3.3.14',	'Output Off',				'Warning',
			'1.3.6.1.4.1.850.1.3.3.3.19',	'Self Test Failed',			'Critical',
			'1.3.6.1.4.1.850.1.3.3.3.23.1', 'Load Level Above Threshold',		'Critical',
                        '1.3.6.1.4.1.850.1.3.3.3.25',	'Battery Age Above Threshold',		'Warning',      
			'1.3.6.1.4.1.850.1.3.3.3.26.1',	'Load 01 Off',				'Warning',
			'1.3.6.1.4.1.850.1.3.3.3.26.2',	'Load 02 Off',				'Warning',
			'1.3.6.1.4.1.850.1.3.3.3.47',	'Loads Not All On',			'Warning',
		);
	}
	else {
		#Generic UPS Alarm Definitions
		@array_alarm_def = (
                        #Alarm OIDs			#Definition                             #State
			'1.3.6.1.2.1.33.1.6.3.1',	'Battery Bad',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.2',	'On Battery',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.3',	'Low Battery',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.4',	'Depleted Battery',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.5',	'Temperature Bad',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.6',	'Input Bad',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.7',	'Output Bad',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.8',	'Output Overload',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.9',	'On Bypass',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.10',	'Bypass Bad',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.11',	'Output Off (Requested)',		'Warning',
			'1.3.6.1.2.1.33.1.6.3.12',	'UPS Off (Requested)',			'Warning',
			'1.3.6.1.2.1.33.1.6.3.13',	'Charger Failed',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.14',	'UPS Output Off',			'Warning',
			'1.3.6.1.2.1.33.1.6.3.15',	'UPS System Off',			'Warning',
			'1.3.6.1.2.1.33.1.6.3.16',	'Fan Failure',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.17',	'Fuse Failure',				'Critical',
			'1.3.6.1.2.1.33.1.6.3.18',	'General Fault',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.19',	'Diag Test Failed',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.20',	'Communications Lost',			'Warning',
			'1.3.6.1.2.1.33.1.6.3.21',	'Awaiting Power',			'Warning',
			'1.3.6.1.2.1.33.1.6.3.22',	'Shutdown Pending',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.23',	'Shutdown Imminment',			'Critical',
			'1.3.6.1.2.1.33.1.6.3.24',	'Test in Progress',			'Warning',
		);
	}

   	foreach $oid(sort keys %$result_alarm) {
        	$val = $result_alarm->{ $oid };

		#Vertiv UPS Alarms
		if ( $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv') {
                	#Next Value if not an Active Alarm
	                next if ( $val !~ m/Active Alarm/ );

        	        if ($val eq "Active Alarm") {
                                for ($i = 0; $i <= $#array_alarm_def; $i += 3) {
                                        if ($oid eq $array_alarm_def[$i]) {
						#Found Alarm
                                                push (@found_alarms, $array_alarm_def[$i+1]);
                                                if ($array_alarm_def[$i+2] eq "Critical") {
                                                        $flag_crit++;
                                                }
                                                elsif ($array_alarm_def[$i+2] eq "Warning") {
                                                        $flag_warn++;
                                                }
		                  	}
        		    	}
 			}
		}
		#Generic UPS Alarms
		else {
			#Next Value if not an Active Alarm
 			next if ( $oid !~ m/\.(\d+)\.(\d+)$/ );

			if ($1 == 2) {
				#Loop through Alarm Def Array and see if Match
				for ($i = 0; $i <= $#array_alarm_def; $i += 3) {
					if ($val eq $array_alarm_def[$i]) {
                        	                # Found Alarm
						push (@found_alarms, $array_alarm_def[$i+1]);
						if ($array_alarm_def[$i+2] eq "Critical") {
							$flag_crit++;
						}
						elsif ($array_alarm_def[$i+2] eq "Warning") {
							$flag_warn++;
						}
	                                }
        	                }
			}
		}
	}

	#Format Alarm Output
        for $i (0..$#found_alarms) {
                $alarm_info = $alarm_info . "$found_alarms[$i]";
                if ($i != $#found_alarms) {
                        $alarm_info = $alarm_info . ", ";
                }
        }

	return;
}



#####
# Check Icinga State to Exit with
#####
sub sub_check_state () {

        if ( $flag_crit > 0 ) {
		$EXIT_STATE = $STATE_CRITICAL;
	}
	elsif ( $flag_warn > 0 ) {
		$EXIT_STATE = $STATE_WARNING;
	}
	elsif ( $alarm_cnt == 0 && $flag_crit == 0 && $flag_warn == 0 ) {
		$EXIT_STATE = $STATE_OK;
	}
	else {
		$EXIT_STATE = $STATE_UNKNOWN;
	}
}



#####
# Performance Data
#####
sub sub_perf_data () {
	my $flag = 0;

# SNMP Input/Output Line Dependent:  $load, $load_percent
	$PERF_DATA = "|";
	if (defined($load)) {
		$PERF_DATA = $PERF_DATA . "'Load (VA)'=$load;$warn_load_va;$crit_load_va;0;$va_capacity";
		$flag = 1;
	}
	if (defined($load_percent)) {
		if ($flag == 1) {$PERF_DATA = $PERF_DATA . " ";}	# Add Space
		$PERF_DATA = $PERF_DATA . "'Load (%)'=$load_percent;$warn_load;$crit_load;0;100";
		$flag = 1;
	}
	if (defined($time_remain)) {
		if ($flag == 1) {$PERF_DATA = $PERF_DATA . " ";}	# Add Space
	        $PERF_DATA = $PERF_DATA . "'Time Remain'=$time_remain;$warn_time_remain;$crit_time_remain";
		$flag = 1;
	}
	if (defined($charge_remain)) {
		if ($flag == 1) {$PERF_DATA = $PERF_DATA . " ";}        # Add Space
		$PERF_DATA = $PERF_DATA . "'Charge Remain'=$charge_remain;$warn_charge_remain;$crit_charge_remain;0;100";
		$flag = 1;
	}
	if (defined($input_voltage)) {
		if ($flag == 1) {$PERF_DATA = $PERF_DATA . " ";}        # Add Space
	        $PERF_DATA = $PERF_DATA . "'Input Voltage'=$input_voltage";
		$flag = 1;
	}
	if (defined($blackouts)) {
		if ($flag == 1) {$PERF_DATA = $PERF_DATA . " ";}        # Add Space
		$PERF_DATA = $PERF_DATA . "'Blackouts'=$blackouts";
		$flag = 1;
	}
	if (defined($blackouts)) {
                if ($flag == 1) {$PERF_DATA = $PERF_DATA . " ";}        # Add Space
                $PERF_DATA = $PERF_DATA . "'Brownouts'=$brownouts";
                $flag = 1;
        }		
	
	return;
}



#####
# Return Message
#####
sub sub_return_msg () {

	my (@display_order, $order_l, $order_s, $order_t, $order_b, $i);
	my $RETURN_MSG = "";
	my $status_info = "";
	my $STATUS_MSG = "";
	my $x = 0;

	#Get Order of Argument Options
		$order_l = index($custom_display, "l");
		$order_s = index($custom_display, "s");
		$order_t = index($custom_display, "t");
		$order_b = index($custom_display, "b");

	#Load % & Load VA
	if ($order_l != -1) {
		if (defined $load_percent && defined $load && defined $va_capacity) {
			$display_order[$order_l] = sprintf("Load: %.1f%% or %d/%d VA", $load_percent, $load, $va_capacity);
		}
		elsif (defined $load_percent) {
			$display_order[$order_l] = sprintf("Load: %.1f%%", $load_percent);
		}
		elsif (defined $load && defined $va_capacity) {
			$display_order[$order_l] = sprintf("%d/%d VA", $load, $va_capacity);
		}
	} 
	#Battery & Output Source
	if ($order_s != -1) {
		if (defined $batt_status && defined $output_source) {
	                $display_order[$order_s] = sprintf("Battery: %s, Output Source: %s", $batt_status, $output_source);
		}
		elsif (defined $batt_status) {
			$display_order[$order_s] = sprintf("Battery: %s", $batt_status);
		}
		elsif (defined $output_source) {
			$display_order[$order_s] = sprintf("Output Source: %s", $output_source);
		}

                #Battery Last Replaced (Vertiv Only with RDU101 Card)
                if (defined $batt_date) {
                        $display_order[$order_s] = $display_order[$order_s] . sprintf(", Date: %s", $batt_date);
                }
}
	#Time & Charge Remaining
        if ($order_t != -1) {
		if (defined $time_remain && defined $charge_remain) {
                        $display_order[$order_t] = sprintf("Remaining: %s min, Charge: %s%%", $time_remain, $charge_remain);
		}
                elsif (defined $time_remain) {
                        $display_order[$order_t] = sprintf("Remaining: %s min", $time_remain);
                }
                elsif (defined $charge_remain) {
                        $display_order[$order_t] = sprintf("Charge: %s%%", $charge_remain);
                }
        }
	#Blackouts & Brownouts (Vertiv Only)
        if ($order_b != -1 && $result_identity->{$hash_identity{'snmp_upsIdentManufacturer'}} eq 'Vertiv') {
                $display_order[$order_b] = sprintf("Brownouts: %s, Blackouts: %s", $brownouts, $blackouts);
	}

	#Sort Customized Display
	if ( $#display_order > 0 && $alarm_display == 2 ) {
		$x = 1;
	}
	for $i ($x..$#display_order) {
		#Verify Line is Defined
		if ($display_order[$i]) {
			$status_info = $status_info . "$display_order[$i]";
			#Add Carridge Return if not End
			if ($i != $#display_order) {
				$status_info = $status_info . "\n";
			}
		}
	}

	#
	#Setup Return Message
	#

	#Check whether to print Icinga State in Output
	if ( $hide_exit_status != 1 ) {
		if    ($EXIT_STATE == 0) {$STATUS_MSG = "OK - ";}
		elsif ($EXIT_STATE == 1) {$STATUS_MSG = "WARNING - ";}
		elsif ($EXIT_STATE == 2) {$STATUS_MSG = "CRITICAL - ";}
		else                     {$STATUS_MSG = "UNKNOWN - ";}
	}

	#Alarms / Display Only Count
        if ( $alarm_display == 1 && $alarm_cnt != 0 ) {
                $RETURN_MSG = "$alarm_cnt Alarms | $status_info";
        }
	#Alarms / Display Count on Line 1 / Details on Multiline
        elsif ( $alarm_display == 2 && $alarm_cnt != 0 ) {
		if ( $#display_order == 0 ) {
	                $RETURN_MSG = "$alarm_cnt Alarms | $display_order[0]\n$alarm_info";
		}
		else {
			$RETURN_MSG = "$alarm_cnt Alarms | $display_order[0]\n$alarm_info\n\n$status_info";
		}
        }
	#Alarms / Display Count and Details on Line 1
        elsif ( $alarm_display == 3 && $alarm_cnt !=0 ) {
                $RETURN_MSG = "$alarm_cnt Alarms: $alarm_info\n$status_info";
	}
	#No Alarms
	else {
		$RETURN_MSG = $status_info;
	}

	#PRINT STATUS, RETURN MESSAGE, AND PEFORMANCE DATA
	printf("\n\n");
	print "$STATUS_MSG" . "$RETURN_MSG" . "$PERF_DATA";
	printf("\n\n");

	return;
}



#####
# Main
#####
sub_sanitize;
sub_get_snmp_ups;
sub_convert;
sub_check_thresholds;

if ( $result_battery->{$hash_battery{'snmp_battery_alarm_count'}} != 0 ) {
	sub_check_alarms;
}

sub_perf_data;
sub_check_state;
sub_return_msg;

exit $EXIT_STATE;
