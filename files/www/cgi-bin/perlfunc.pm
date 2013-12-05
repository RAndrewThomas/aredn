#############################
# html functions

# emit the http server response
sub http_header
{
    # THIS MUST BE ONE LINE!
    # otherwise an intermittent busybox bug will incorrectly "fix" the generated output
#    print "HTTP/1.0 200 OK\r\n";  # Not needed under Uhttpd
    print "Content-type: text/html\r\n";

    print "Cache-Control: no-store\r\n";
    print "\r\n";
}

# begin html page
sub html_header
{
    my($title, $close) = @_;
    print "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">\n";
    print "<html>\n";
    print "<head>\n";
    print "<title>$title</title>\n";
    print "<meta http-equiv='expires' content='0'>\n";
    print "<meta http-equiv='cache-control' content='no-cache'>\n";
    print "<meta http-equiv='pragma' content='no-cache'>\n";
    print "<link rel=StyleSheet href='/", (-f "/tmp/.night") ? "night" : "day", ".css' type='text/css'>\n";
    print "</head>\n" if $close;
}

# print the navigation bar
sub navbar
{
    my($current) = @_;
    $current = "" unless $current;

    my @pages = qw(status setup ports admin);
    my %titles = (status => "Node Status",
		  setup  => "Basic Setup",
		  ports  => "Port Forwarding,<br>DHCP, and Services",
		  admin  => "Administration");
    
    my($active_bg, $active_fg);
    if(-f "/tmp/.night") { $active_bg = "red";   $active_fg = "black" }
    else                 { $active_bg = "black"; $active_fg = "white" }

    print "<hr><table cellpadding=5 border=0 width=100%><tr>\n";

    foreach $page (@pages)
    {
	print "<td align=center width=25%";
	print " class=navbar_select" if $page eq $current;
	print "><a href='$page'>", $titles{$page}, "</a></td>\n";
    }
    
    print "</tr></table><hr>\n";
}


# put the submitted parameters into a hash
# (from $ENV{QUERY_STRING} in a method=get form)
sub read_query_string
{
    return unless $ENV{QUERY_STRING};
    foreach(split "&", $ENV{QUERY_STRING})
    {
	my ($parm, $val) = /(\w+)=(.*)/;
	$val =~ s/\+/ /g;
	if($val =~ /^([^%]*)%(\w\w)(.*)/) # convert hex values
	{
	    my $val2 = "";
	    while($val =~ /^([^%]*)%(\w\w)(.*)/)
	    {
		$val2 .= $1 . chr hex $2;
		$val = $3; 
	    }
	    $val2 .= $val;
	    $val = $val2;
	}
	$parms{$parm} = $val;
    }
}


# c-style fgets for read_postdata
$stdinbuffer = "";

sub fgets
{
    my($size) = @_;
    my $line = "";

    while(1)
    {
	unless(length $stdinbuffer)
	{
	    return "" unless read STDIN, $stdinbuffer, $size;
	}
	my ($first, $cr) = $stdinbuffer =~ /^([^\n]*)(\n)?/;
	$cr = "" unless $cr;
	$line .= $first . $cr;
	$stdinbuffer = substr $stdinbuffer, length "$first$cr";
        if($cr or length $line >= $size)
	{
	    if(0)
	    {
		$line2 = $line;
		$line2 =~ s/\r/\\r/;
		$line2 =~ s/\n/\\n/;
		push @parse_errors, "[$line2]";
	    }
	    return $line;
	}
    }
}

# read postdata
# (from STDIN in method=post form)
sub read_postdata
{
    my ($line, $parm, $file, $handle, $tmp);
    my $state = "boundary";
    my ($boundary) = $ENV{CONTENT_TYPE} =~ /boundary=(\S+)/ if $ENV{CONTENT_TYPE};
    my $parsedebug = 0;
    push(@parse_errors, "[$boundary]") if $parsedebug;

    while(length ($line = fgets(1000)))
    {
	$line =~ s/[\r\n]+$//; # chomp doesn't strip \r!
	#print "[$state] $line<br>\n";

	if($state eq "boundary" and $line =~ /^--$boundary(--)?$/)
	{
	    last if $line eq "--$boundary--";
	    $state = "cdisp";
	}
	elsif($state eq "cdisp")
	{
	    my $prefix = "Content-Disposition: form-data;";
	    if(($parm, $file) = $line =~ /^$prefix name="(\w+)"; filename="(.*)"$/)
	    { # file upload
		$parms{$parm} = $file;
		if($file) { $state = "ctype" }
		else      { $state = "boundary" }
	    }
	    elsif(($parm) = $line =~ /^$prefix name="(\w+)"$/)
	    { # form parameter
		$line = fgets(10);
		push(@parse_errors, "not blank: '$line'") unless $line eq "\r\n";
		$line = fgets(1000);
		$line =~ s/[\r\n]+$//;
		$parms{$parm} = $line;
		$state = "boundary";
	    }
	    else
	    { # oops, don't know what this is
		push @parse_errors, "unknown line: '$line'";
	    }
	}
	elsif($state eq "ctype") # file upload happens here
	{
	    push(@parse_errors, "unexpected: '$line'") unless $line =~ /^Content-Type: /;
	    $line = fgets(10);
	    push(@parse_errors, "not blank: '$line'") unless $line eq "\r\n";
	    $tmp = "";
	    system "mkdir -p /tmp/web/upload";
	    open($handle, ">/tmp/web/upload/file");
	    while(1)
	    {
		# get the next line from the form
		$line = fgets(1000);
		last unless length $line;
		last if $line =~ /^--$boundary(--)?\r\n$/;

		# make sure the trailing \r\n doesn't get into the file
		print $handle $tmp;
		$tmp = "";
		if($line =~ /\r\n$/)
		{
		    $line =~ s/\r\n$//;
		    $tmp = "\r\n";
		}
		print $handle $line;
	    }
	    close($handle);
	    last if $line eq "--$boundary--\r\n";
	    $state = "cdisp";
	}
    }
    
    push(@parse_errors, `md5sum /tmp/web/upload/file`) if $parsedebug and $handle;
}

# generate a selector box option
sub selopt
{
    my($label, $value, $select, $opt) = @_;
    print "<option value=$value";
    print " selected" if $value eq $select;
    print " $opt" if $opt;
    print ">$label</option>\n";
}

# generate a selector box option with preformatted spacing
sub selopt_pre
{
    my($label, $value, $select, $opt) = @_;
    print "<option value=$value";
    print " selected" if $value eq $select;
    print " $opt" if $opt;
    print " style='font-family:monospace;white-space:pre'>$label</option>\n";
}

# display internal data for debugging
sub show_debug_info
{
    return unless $debug;

    print "<b>env</b><br>\n";
    foreach(sort keys %ENV) { print "$_ = $ENV{$_}<br>\n" }

    print "<br><br><b>parms</b><br>\n";
    foreach(sort keys %parms)
    {
	$tmp = $parms{$_};
	$tmp =~ s/ /\(space\)/g;
	if($parms{$_} eq "") { print "$_ = (null)<br>\n" }
	else                 { print "$_ = $tmp<br>\n" }
    }
}

# report any form parsing errors
sub show_parse_errors
{
    return unless @parse_errors;
    print "<h3>Internal Error.  Send the following information to ad5oo\@arrl.net</h3>\n";
    print "<pre>\n";
    foreach(@parse_errors) { print "$_\n" }
    print "</pre>";
}


# show the reboot page, redirect to $link, and reboot
sub reboot_page
{
    my ($link) = @_;
    my($lanip, $lanmask, $junk, $lannet);
    my $node = nvram_get("node");
    $link = "/cgi-bin/status" unless $link;

    # is the browser coming from the lan?
    if(system "ifconfig br-lan >/dev/null 2>&1")
    {
	($lanip, $lanmask, $junk, $lannet) = &get_ip4_network("eth0");
    }
    else
    {
	($lanip, $lanmask, $junk, $lannet) = &get_ip4_network("br-lan");
    }
    my($browser) = $ENV{REMOTE_ADDR} =~ /::ffff:([\d\.]+)/;
    my $fromlan = validate_same_subnet($browser, $lanip, $lanmask);
    $junk = ""; # dummy to avoid warning

    # detect a LAN subnet change
    my $subnet_change = 0;
    if($fromlan)
    {
	&load_openwrt_config("/etc/config/network");
	$lannet = ip2decimal($lannet);
	$lanmask = ip2decimal($lanmask);
	my $cfgip = ip2decimal($openwrt{network}{interface}{lan}{ipaddr});
	my $cfgmask = ip2decimal($openwrt{network}{interface}{lan}{netmask});
	$subnet_change = 1 if $lanmask != $cfgmask or $lannet != ($cfgip & $cfgmask);
    }

    # print the page
    http_header();

    if($fromlan and $subnet_change)
    {
	html_header("$node rebooting", 1);
	print "<body><center>\n";
	print "<h1>$node is rebooting</h1><br>\n";
	print "<h3>The LAN subnet has changed. You will need to acquire a new DHCP lease<br>";
	print "and reset any name service caches you may be using.</h3><br>\n";
	print "<h3>Wait for the Power LED to start blinking, then stop blinking.<br>\n";
	print "When the DMZ LED turns off you can get your new DHCP lease and reconnect with<br>\n";
	print "<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>or<br>\n";
	print "<a href='http://$node.local.mesh:8080/'>http://$node.local.mesh:8080/</a></h3>\n";
    }
    else
    {
	html_header("$node rebooting", 0);
	print "<meta http-equiv='refresh' content='60;url=$link'>\n";
	print "</head><body><center>\n";
	print "<h1>$node is rebooting</h1><br>\n";
	print "<h3>Your browser should return to this node in 60 seconds.</br><br>\n";
	print "If something goes astray you can try to connect with<br><br>";
	print "<a href='http://localnode.local.mesh:8080/'>http://localnode.local.mesh:8080/</a><br>or<br>\n";
	print "<a href='http://$node.local.mesh:8080/'>http://$node.local.mesh:8080/</a></h3>\n";
    }

    print "</center></body></html>";
    system "/sbin/reboot" unless $debug;
    exit;
}


# word wrap a list of text strings
sub word_wrap
{
    my $len = shift;
    my @output = ();

    foreach(@_)
    {
	my $str = $_;
	while(length $str > $len)
	{
	    my $str1 = substr $str, 0, $len;
	    my $str2 = substr $str, $len;
	    if($str1 =~ /^(.*)\s(\S+)$/)
	    {
		push @output, "$1\n";
		$str = $2 . $str2;
	    }
	    else
	    {
		push @output, "$str1\n";
		$str = $str2;
	    }	    
	}

	push @output, $str;
    }

    return @output;
}


#############################
# system interaction

# read an nvram variable
sub nvram_get_old
{
    my ($var) = @_;
    return "ERROR" if not defined $var;
    chomp($var = `nvram get $var`);
    return $var;
}

# set an nvram variable
sub nvram_set_old
{
    my ($var, $val) = @_;
    return "ERROR" if not defined $val;
    return system "nvram set $var='$val'";
}

# Replace the /etc/nvram file used by 1.0.0 Linksys
# with the backfire uci command due to an observed race condition
# 
# read an nvram variable
sub nvram_get
{
    my ($var) = @_;
    return "ERROR" if not defined $var;
    chomp($var = `uci -c /etc/local/uci/ -q get hsmmmesh.settings.$var`);
    return $var;
}

# set an nvram variable
sub nvram_set
{
    my ($var, $val) = @_;
    return "ERROR" if not defined $val;
    system "uci -c /etc/local/uci/ set hsmmmesh.settings.$var='$val'";
    system "uci -c /etc/local/uci/ commit";
}


# return the ipv4 network parameters of the given interface or "none"
sub get_ip4_network
{
    my($ip, $mask, $bcast, $net, $cidr);
    foreach(`ifconfig $_[0]`)
    {
	next unless /inet addr:([\d\.]+)  Bcast:([\d\.]+)  Mask:([\d\.]+)/;
	($ip, $bcast, $mask) = ($1, $2, $3);
	last;
    }
    return ("none") unless defined $ip;
    my $dmask = ip2decimal($mask);
    $net = decimal2ip(ip2decimal($ip) & $dmask);
    $cidr = 0;
    for(my $i = 31; $i >= 0 and ($dmask & (1 << $i)); $i--) { $cidr++ }
    return ($ip, $mask, $bcast, $net, $cidr);
}

# return the ipv6 address and scope of the given interface or "none"
sub get_ip6_addr
{
    my $ip = "none";
    my $scope = "";
    foreach(`ifconfig $_[0]`)
    {
	next unless /inet6 addr: ([\w:]+)\/\d+ Scope:(\w+)/;
	($ip, $scope) = ($1, $2);
	last;
    }
    return "$ip $scope";
}

# return the address of the default gateway or "none"
# currently assumes ipv4
sub get_default_gw
{
    my $gw = "none";
    foreach(`route -n`)
    {
	next unless /^0\.0\.0\.0\s+([\d\.]+)/;
	$gw = $1;
	last;
    }
    return $gw;
}

# return the hostname for the given ip address or ""
sub ip2hostname
{
    my ($ip) = @_;
    my $host;
    return "" unless $ip;
    return "" if $ip eq "none";
    foreach(`nslookup $ip`)
    {
	next unless ($host) = /Address: $ip (\S+)/;
	return $host;
    }
    return "";
}

# return the hostname and tactical name for a mesh node
sub mesh_ip2hostname
{
    my ($ip) = @_;
    my @list;
    my $host;
    return "" unless $ip;
    return "" if $ip eq "none";
    foreach(`grep $ip /etc/hosts 2>/dev/null`)
    {
	next unless ($host) = /^$ip\s+(.*)/;
	return (join " / ", (split /\s+/, $host));
    }
    foreach(`grep $ip /var/run/hosts_olsr 2>/dev/null`)
    {
	next unless ($host) = /^$ip\s+([\w\-]+)/;
	push @list, $host;
    }
    return join " / ", @list;
}

# return the hostname and tactical name for this node
#sub get_nodenames
#{
#    my $host = `grep "option 'hostname' /etc/config/system | awk '{print \$3}'`;
#    my $tac  = `grep "option 'tactical' /etc/config/system | awk '{print \$3}'`;
#    $host =~ s/[\"\'\n]//g;
#    $tac  =~ s/[\"\'\n]//g;
#    return ($host, $tac);
#}

# return the mac address for the given interface
sub get_mac
{
    my ($intf) = @_;
    my $mac = "";
    return "" unless $intf;
    foreach(`ifconfig $intf 2>/dev/null`)
    {
	next unless /^\S+ .*HWaddr (\S+)/;
	$mac = $1;
    }
    return $mac;
}

# load the setup file
sub load_cfg
{
    #my $mac2 = nvram_get("mac2");
    my $node = nvram_get("node");
    my $mac2 = mac2ip(get_mac("wlan0"), 0);
    open(FILE, $_[0]) or return 0;
    while(defined ($line = <FILE>))
    {
	next if $line =~ /^\s*#/;
	next if $line =~ /^\s*$/;
	$line =~ s/<NODE>/$node/;
	$line =~ s/<MAC2>/$mac2/;
	$line =~ /^(\w+)\s*=\s*(.*)$/;
	$cfg{$1} = $2;
    }
    close(FILE);
    return 1;
}

# save the setup file and generate the full configuration
sub save_setup
{
    # save the parms to the setup file

    open(FILE, ">$_[0]") or return 0;
    foreach(sort keys %parms)
    {
	next unless /^(aprs|dhcp|dmz|lan|olsrd|wan|wifi)_/;
	print FILE "$_ = $parms{$_}\n";
    }
    close(FILE);

    # set the nvram parameters

    nvram_set("node",     $parms{node});
    nvram_set("tactical", $parms{tactical});
    nvram_set("config",   $parms{config});

    # generate the system config files

    system "mkdir -p /tmp/web/save";
    $rc =  system "/usr/local/bin/node-setup -a $parms{config} >/tmp/web/save/node-setup.out 2>&1";
    return 0 if $rc or -s "/tmp/web/save/node-setup.out";
    system "rm -rf /tmp/web/save";

    # change system and web passwords

    $passwd2 = $passwd1;
    $passwd2 =~ s/'/'\\''/g;
    system "/usr/local/bin/setpasswd '$passwd2' >/dev/null 2>&1" if $passwd1;

    system "touch /tmp/reboot-required";
    return 1;
}

sub get_wifi_signal
{
    # CMLARA:
    # this would be easy if /proc/net/wireless updated automatically, but it doesn't.
    # the hack is to re-scan
    # also iwlist doesnt correctly limit to single ssid
    # and we have to call from 2 programs now instead of 1
    my ($ssid) = (`uci -q get wireless.\@wifi-iface[0].ssid`);
    chomp $ssid;
    my ($SignalLevel) = "N/A";
    my ($NoiseFloor) = "N/A";
    foreach(`iwlist $_[0] scanning essid "$ssid" |grep -A 5 -B 5 "$ssid"`)
    {
        next unless /Signal level=([\d\-]+) dBm/;
        $SignalLevel=$1;
    }

    foreach(`iw dev $_[0] survey dump|grep -A 1 \"\\[in use\\]\"`)
    {
        next unless /([\d\-]+) dBm/;
        $NoiseFloor=$1;
    }

    if ( $SignalLevel == "N/A" || $NoiseFloor == "N/A" )
    {
        return ("N/A","N/A");
    }
    else {
    return ($SignalLevel, $NoiseFloor);
    }
}

sub get_free_space
{
    my $dir = $_[0];
    foreach(`df -k $dir`)
    {
	next unless /$dir$/;
	my @tmp = split /\s+/, $_;
	return $tmp[3];
    }
    return "N/A";
}

sub get_free_mem
{
    foreach(`free`)
    {
	next unless /^\s+Mem[:]/;
	my @tmp = split /\s+/, $_;
	return $tmp[4] + $tmp[6];
    }
    return "N/A";
}

# this works for the "/etc/config/network" file
# other files can use other schemas so this function is not universal
sub load_openwrt_config
{
    my ($file) = @_;
    my $base = $file;
    $base =~ s/^.*\///;

    my($section, $name) = ();
    foreach(`cat $file 2>/dev/null`)
    {
	next if /^\s*$/;
	next if /^\s*\#/;
	if(/^config\s+(\w+)\s+(\w+)/)
	{
	    ($section, $name) = ($1, $2);
	    next;
	}
	next unless $section and $name;
	if(my($opt, $val) = /^\s+option\s+(\w+)\s+(\S+.*)/)
	{
	    $val =~ s/^"//;
	    $val =~ s/\s+$//;
	    $val =~ s/"$//;
	    $openwrt{$base}{$section}{$name}{$opt} = $val;
	}
    }
}


#############################
# ip address functions

# add the given value to the last octet
sub add_ip_address
{
    my($address, $add) = @_;
    my($prefix, $last) = $address =~ /^(.*)\.(\d+)$/;
    return "error" unless defined $last;
    $last += $add;
    return "error" if $last < 0 or $last > 255;
    return "$prefix.$last";
}

# substitute the given value for the last octet
sub change_ip_address
{
    my($address, $value) = @_;
    my($prefix) = $address =~ /^(.*)\.\d+$/;
    return "error" unless defined $prefix;
    return "$prefix.$value";
}

# convert dotted quad to 32 bit value
sub ip2decimal
{
    my($address) = @_;
    my $sum = 0;
    foreach(split /[.]/, $address)
    {
	$sum *= 256;
	$sum += $_;
    }
    return $sum;
}

# convert 32 bit value to dotted quad
sub decimal2ip
{
    my($sum) = @_;
    my @parts;
    for(my $i = 0; $i < 4; $i++)
    {
	push @parts, $sum & 255;
	$sum >>= 8;
    }
    return join ".", reverse @parts;
}

# convert a left shifted mac address into 3 IP address octets
sub mac2ip
{
    my ($mac, $shiftbits) = @_;
    my $val = 0;
    my $str;
    foreach($mac =~ /\w\w:\w\w:\w\w:(\w\w):(\w\w):(\w\w)/)
    {
	$val <<= 8;
	$val += hex $_;
    }
    $val <<= $shiftbits;
    return sprintf "%d.%d.%d",
      ($val & 0xff0000) >> 16,
      ($val & 0xff00) >> 8,
       $val & 0xff;
}


#############################
# input validation

sub validate_node
{
    my ($node) = @_;
    return 0 unless $node =~ /^\w\-$/;
    return 0 if $node =~ /_/;
    return 1;
}

sub validate_ip
{
    my($ip) = @_;
    $ip =~ s/\s//g;
    return 0 if $ip eq "0.0.0.0";
    return 0 if $ip eq "255.255.255.255";
    my $count = 0;
    foreach($ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
    {
	++$count if $_ < 256;
    }
    return 0 unless $count == 4;
    return 1;
}

sub validate_netmask
{
    my($mask) = @_;
    $mask =~ s/\s//g;
    return 0 if $mask eq "0.0.0.0";
    my $count = 0;
    my $bitmask = "";
    foreach my $val ($mask =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/)
    {
	++$count if $val < 256;
	for(my $i = 0; $i < 8; ++$i)
	{
	    my $bit = 128 >> $i;
	    if($val & $bit) { $bitmask .= "1" }
	    else            { $bitmask .= "0" }
	}
    }
    return 0 unless $bitmask =~ /^1+0*$/;
    return 0 unless $count == 4;
    return 1;
}

# verify that the address is neither the network
# nor broadcast address for this subnet
sub validate_ip_netmask
{
    my($ip, $mask) = @_;
    return 0 unless validate_ip($ip);
    return 0 unless validate_netmask($mask);
    $ip = ip2decimal($ip);
    $mask = ip2decimal($mask);
    my $notmask = 0xffffffff - $mask;
    return 0 if ($ip & $notmask) == 0;
    return 0 if ($ip & $notmask) == $notmask;
    return 1;
}

# verify that two addresses are in the same subnet
sub validate_same_subnet
{
    my($addr1, $addr2, $mask) = @_;
    $addr1 = ip2decimal($addr1);
    $addr2 = ip2decimal($addr2);
    $mask  = ip2decimal($mask);
    return 1 if ($addr1 & $mask) == ($addr2 & $mask);
    return 0;
}

sub validate_mac
{
    my($mac) = @_;
    $mac = lc $mac;
    $mac =~ s/^\s+//;
    $mac =~ s/\s+$//;
    return 0 unless length $mac == 17;
    for(my $i = 0; $i < 17; $i++)
    {
	my $ch = chop $mac;
	if(($i + 1) % 3) { return 0 unless $ch =~ /[0-9a-f]/ }
	else             { return 0 unless $ch eq ":" }
    }
    return 1;
}

sub validate_hostname
{
    my($host) = @_;
    $host =~ s/^\s+//;
    $host =~ s/\s+$//;
    return 0 if $host =~ /_/;
    return 1 if $host =~ /^[\w\-]+$/;
    return 0;
}

sub validate_port
{
    my($port) = @_;
    $port =~ s/^\s+//;
    $port =~ s/\s+$//;
    return 0 if $port eq "";
    return 0 if $port =~ /\D/;
    return 0 if $port < 1 or $port > 65535;
    return 1;
}

sub validate_port_range
{
    my($port) = @_;
    my($port1, $port2);
    return 0 unless ($port1, $port2) = $port =~ /^\s*(\d+)\s*-\s*(\d+)\s*$/;
    return 0 unless validate_port($port1);
    return 0 unless validate_port($port2);
    return 0 unless $port2 > $port1;
    return 1;
}

sub validate_service_name
{
    my($name) = @_;
    #return 0 if $name eq "";
    return 0 if $name =~ /[:'|]/;
    return 1;
}

sub validate_service_protocol
{
    my($proto) = @_;
    return 0 if $proto eq "";
    return 0 unless $proto =~ /^\w+$/;
    return 1;
}

sub validate_service_suffix
{
    my($suffix) = @_;
    # currently only protects against parsing errors in the config files and html
    return 0 if $suffix =~ /[:']/;
    return 1;
}

sub validate_latitude
{
    my($lat) = @_;
    return 0 unless defined $lat;
    $lat =~ s/^\s+//;
    $lat =~ s/\s+$//;
    return 0 if $lat =~ /[^\d\.\-]/;
    return 0 if $lat < -90 or $lat > 90;
    return 1;
}

sub validate_longitude
{
    my($lon) = @_;
    return 0 unless defined $lon;
    $lon =~ s/^\s+//;
    $lon =~ s/\s+$//;
    return 0 if $lon =~ /[^\d\.\-]/;
    return 0 if $lon < -180 or $lat > 180;
    return 1;
}


# Return maximum dbm value for tx power 
sub wifi_maxpower
{
    $boardtype = `/usr/local/bin/get_hardwaretype`;
    chomp($boardtype);
    if ($boardtype eq "bullet-m"){
        return 27;
    }
    elsif ($boardtype eq "rocket-m") {
        #Rocket-m is 28dbm but has a 10db offchip amp.
        return 18;
    }
    else
    {
        #When in doubt lets return 27 for safety.
        return 27;
    }

}


sub wifi_validant
{
    #CMLARA -- Basic mapping of antennas to models,  we really don't know all the models yet
    # so we will just put the ones we know here first
    $boardtype = `/usr/local/bin/get_hardwaretype`;
    chomp($boardtype);
    if ($boardtype eq "bullet-m"){
        %antennas = ( 1  => "N-Connector" );
    } 
    elsif ($boardtype eq "rocket-m") {
        %antennas = ( 1  => "Chain0", 2  => "Chain1", 3 => "Diversity" );
    }
    else 
    {
        %antennas = ( 0  => "Left", 1  => "Right", 2 => "Diversity" );
    }

    return %antennas;
}

sub wifi_defaultant
{
    $boardtype = `/usr/local/bin/get_hardwaretype`;
    chomp($boardtype);
    if ($boardtype eq "bullet-m"){
        return 1;
    } 
    elsif ($boardtype eq "rocket-m"){
        return 3;
    }
    else
    {
        #Most likely to catch all models.  Some have 3 and start at 1, some start at 0, others have 1 at 1, etc
        return 1;
    }
}

sub wifi_useschains
{
    $boardtype = `/usr/local/bin/get_hardwaretype`;
    chomp($boardtype);
    if ($boardtype eq "rocket-m"){
        return 1;
    }
    else
    {
        return 0;
    }
}

#Some systems have power offsets in them because of a secondary amplifier
#Because of this the chipset may report one power level but the amplifier
#has increased it to a higher level.
sub wifi_txpoweroffset
{
    $boardtype = `/usr/local/bin/get_hardwaretype`;
    chomp($boardtype);
    if ($boardtype eq "rocket-m"){
        return 10;
    }
    else
    {
        return 0;
    }

}
#weird uhttpd/busybox error requires a 1 at the end of this file
1