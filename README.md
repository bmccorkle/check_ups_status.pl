This might have issues with any generic ups as I was unable to fully test but it has been tested on Vertiv RDU101xx and Unity-DP cards along with Tripplite WEBCARDLX. 

# check_ups_vertiv.pl
Icinga2 Vertiv UPS Check

        -h      Help
        -V      Version
        -C      SNMP Community
        -H      Hostname
        -p      SNMP Port (Default: 161)
        -t      SNMP Timeout (Default 5 sec)
        -v      SNMP Version [2|3]  (Default: 2)
        -a      Alarm Output Format [1=count|2=short|3=long]  (Default: Long)
                1 = Alarm Count / Load Information
                2 = Alarm Count / Load Information (Details on Multiline)
                3 = Alarm Count & Details (May overrun line)
        -d      Display Output Format [l|s|t|b] (Order Changes Displayed Order)*
                l = Show Load Information
                s = Show Status of Battery and Output
                t = Show Time Remaining and Charge %
                b = Show Brownouts & Blackouts
                * First Option is Line 1 output (Alarms Override, See -a)
        -z      DON'T Print exit status on Line 1 (Hate duplication)
        --un    SNMPv3 Username
        --sl    SNMPv3 Security Level [noauthnopriv|authnopriv|authpriv] (Default: noauthnopriv)
        --ap    SNMPv3 Auth Protocol [md5|sha] (Default: sha)
        --ak    SNMPv3 Auth Password
        --pp    SNMPv3 Privacy Protocol [des|aes] (Default: aes)
        --pk    SNMPv3 Privacy Password
        --wc    WARN: On Remaining % of Battery Charge (Default: 10%)
        --cc    CRIT: On Remaining % of Battery Charge (Default:  5%)
        --wl    WARN: On Percent of Battery Load (Integer) (Default: 80%)
        --cl    CRIT: On Percent of Battery Load (Integer) (Default: 90%)
        --wt    WARN: On Minutes of Battery Remaining (Default: 2 min)
        --ct    CRIT: On Minutes of Battery Remaining (Default: 1 min)
        --ws    WARN: On Battery Status: (1=Normal, 2=Unknown, 3=Low, 4=Depleted)
        --cs    CRIT: On Battery Status: (1=Normal, 2=Unknown, 3=Low, 4=Depleted)

     Example: ./check_ups_status.pl -C public -H 193.168.3.30 -X batteryStatus -wb 3 -cb 4
