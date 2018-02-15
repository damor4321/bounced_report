#!/usr/bin/perl

#use lib qw(/MTA/appn/lib/PDist /MTA/appn/opt/fblprocess);
use strict;
#use warnings;
use Date::Format;
use Getopt::Std;
use Mail::IMAPClient;
use File::Copy;
use Data::Dumper;

use config;

use constant {
 MULTIPART => "MULTIPART",
 TEXT => "TEXT"
};

#=====
my %opt;
my $imap;

my $start_time;
my $end_time;
my $start_time2;
my $end_time2;
my @msgs;
my $header_to = $imap_user;
my $subject = "Undelivered Mail Returned to Sender";
#my $subject = "Postmaster Copy: Undelivered Mail";


sub connect_server {

     $imap = Mail::IMAPClient->new(
     Server   => $imap_server,
     Port     => 143,
     Ssl      => 0,
     User     => $imap_user,
     Password => $imap_pass,
     )
     or die ("new(): $@");
     
     print  "I'm authenticated in imap server $imap_server\n" if $imap->IsAuthenticated();     
     return;
}



sub disconnect_server {
    $imap->close;
    print "Disconnect from imap server $imap_server\n";
}


sub get_dates {


    #$0 -f 03-Jul-2014 -t 06-Jul-2014


    if ($opt{f} and $opt{t}) {
        $start_time = $opt{f};
        $end_time = $opt{t};
        print "Start date =[$start_time] and End date =[$end_time]\n";
    }



    #03-Jul-2013
    my %month = ('Jan'=>'01','Feb'=>'02','Mar'=>'03','Apr'=>'04','May'=>'05','Jun'=>'06', 'Jul'=>'07','Aug'=>'08','Sep'=>'09','Oct'=>'10','Nov'=>'11','Dec'=>'12');
    
    my @s = split /-/, $start_time; 
    $s[0] = sprintf("%02d", $s[0]);
    $start_time2 = $s[2] . $month{$s[1]} . $s[0];
    
    @s = split /-/, $end_time;  
    $s[0] = sprintf("%02d", $s[0]);
    $end_time2 = $s[2] . $month{$s[1]} . $s[0];
    
    print "Start date 2=[$start_time2] and End date 2=[$end_time2]\n";

    die ("Bad date range: Start date =[$start_time] and End date =[$end_time]") if ($start_time2 ge $end_time2);

    return;
}



sub get_messages {

	$imap->select("INBOX") or die "Could not select: $@\n";
	$imap->Uid(1);
	$imap->Peek(1);


	print "Getting messages sentsince=[$start_time] sentbefore=[$end_time] to=[$header_to] subject=[$subject]\n";
	@msgs = $imap->search("SENTSINCE $start_time SENTBEFORE $end_time TO $header_to SUBJECT \"$subject\"") or die ("No emails found\n");


	#my $i=0; foreach my $seqno (@msgs) { print "$i:\t\t$seqno\n"; $i++; } ; die ("ADIOS"); 
}

sub trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub get_report_data { 


    open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    select((select(RAW), $|=1)[0]);


    my $idx=0;
    foreach my $seqno (@msgs) {

	   
	   #last if($idx > 3);

	   #my @message = split "\r\n" , $imap->message_string($seqno);
	   my @message = split "\r\n" , $imap->body_string($seqno);
	   
	   print "Message $idx:\t\t$seqno FETCHED\n";
	   #print Dumper(@message);

	   my $reg = "";
	   my $diag_code_val = 0; my $undelivered_message_part = 0; my $delivery_status_part = 0; my $undelivered_message_vals = 0;
	   my $rcpt; my $diag; my $date; my $msgid; my $dsn; my $gw;
	   
	  foreach my $l (@message) {

		chomp $l;
		
		if($l =~ m/^Content-Type: message\/delivery-status$/ ) { $delivery_status_part = 1; next;}


		my ($item) = $l =~ /^Reporting-MTA: dns; (.*)$/;
        	if ($item ne "" and $delivery_status_part == 1) { $gw= trim($item); next;}

		($item) = $l =~ /^Final-Recipient: .*;(.*)$/;
        	if ($item ne ""  and $delivery_status_part == 1) { $rcpt= lc(trim($item)); next;}

		($item) = $l =~ /^Diagnostic-Code: (.*)$/;
		if ($item ne ""  and $delivery_status_part == 1) { $diag = trim($item). " ";  $diag_code_val=1; next;}
		if ($diag_code_val == 1) { 
			if($l ne "") { $diag .= trim($l) ." "; }
			else { $diag_code_val = 0; $delivery_status_part = 0;}			
			next;
		}
			


		if($l =~ m/^Content-Description: Undelivered Message/) { $undelivered_message_part = 1; next;}

		($item) = $l =~ /^Date: (.*)$/;
		if ($item ne ""  and $undelivered_message_part == 1) { 
			$date= trim($item);  

			$undelivered_message_vals ++;
			if($undelivered_message_vals > 1) {
				last;
			}
			else {
				next;
			}

		}
		
		($item) = $l =~ /^Message-Id: (.*)$/i;
		if ($item ne "" and $undelivered_message_part == 1) { 
			$msgid = trim($item);

			#$undelivered_message_part = 0;

			$undelivered_message_vals ++;
			if($undelivered_message_vals > 1) {
				last;
			}
			else {
				next;
			}
		}			


	   }
	   my $reg = "$date\t$msgid\t$rcpt\tBOUNCED\t$diag\t$gw\n";
	   print RAW $reg;
	   $idx++;
	   print " Message $idx:\t\t$seqno PARSED\n";

    }

    close RAW;
    copy "raw.csv", "COPIA.csv";

}




sub put_header {
 
  my $text=shift;
  my $fh=shift;

  print $fh "					\n";
  print $fh "					\n";
  print $fh "$text					\n";
  print $fh "					\n";

}



sub get_user_unknowns {


    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "user_unknowns.csv") or die "Cannot open file [$!]";
	put_header ("1. RESULTADO USER NO EXISTE: DESCARTAR", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;

		if ($reg =~ m/The email account that you tried to reach does not exist|554 delivery error:|554 qq Sorry, no valid recipients|554 delivery error:|said: 550 Requested action not taken: mailbox unavailable|No such user|550 No Such User Here|Recipient address rejected: User unknown|Recipient address rejected: User unknown|User unknown \(in reply to RCPT TO command\)|550 5\.1\.1 User unknown|550 5\.1\.1 User Unknown|550 User unknown|550 5\.7\.1 User unknown|550 user not known| was not found in LDAP server|550 5\.1\.1 Error: invalid recipients is found from|550 Invalid recipient|550 Invalid Recipient|550-Invalid recipient|550 Lo sentimos, ya no hay nadie con ese email|Mailbox unavailable for this recipient|Recipient address rejected: Unknown recipient|is not a valid mailbox|550 unknown recipient|Recipient not found|554 delivery error: dd This user doesn\'t have a|550 User suspended|550 Unknown recipient|550 User not found|recipient rejected|550 5\.1\.1 Not our Customer|550 Invalid mailbox:|Utilisateur inconnu|Account Inactive|This account has been disabled or discontinued|said: 550 Blocked. If you feel this to be in error|550 No such recipient|said: 550 Unrouteable address| does not exist|550 Address unknown|550 sorry, no mailbox here by that name|Recipient unknown\.|does not exist here \(in reply to RCPT TO command\)|511 sorry, no mailbox here by that name|550 no mailbox by that name is currently available|said: 550 5\.1\.1 unknown or illegal alias:|does not exist here\.|said: 553 Invalid recipient|Account blocked due to inactivity|callout verification failure/) {

			if ($reg =~ m/dsn=5\.1\.1|dsn=5\.0\.0/) {
				print REP $reg;				
			}
			else {
				print REST $reg;
			}

		}
		else {
			print REST $reg;
		}
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";

}


sub get_host_domain_not_found {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "host_domain_not_found.csv") or die "Cannot open file [$!]";
	put_header ("2. RESULTADO MAQUINA o DOMINIO NO EXISTE: DESCARTAR", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;
		if($reg =~ m/Host or domain name not found/ and $reg =~ m/dsn=5\.4\.4/) {
			print REP $reg;
			next;
		}

		print REST $reg;		
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";

}



sub get_user_disabled {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "user_disabled.csv") or die "Cannot open file [$!]";
	put_header ("3. RESULTADO USUARIO DESHABILITADO (5.2.1) : REINTENTAR ANTES DE DESCARTAR", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;
		if($reg =~ m/The email account that you tried to reach is disabled|\.\.\. user disabled; cannot receive new mail:/) {
			print REP $reg;
			next;
		}

		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";


}


sub get_full_or_over_quota {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "full_or_over_quota.csv") or die "Cannot open file [$!]";
	put_header ("4. RESULTADO BUZON OVER-QUOTA: REINTENTAR", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;

		if($reg =~ m/552-5\.2\.2 The email account that you tried to reach is over quota|Mailbox quota exceeded|would exceed mailbox quota|Recipient address rejected: Mailbox is full|said: 550 Recipient Rejected: Mailbox would exceed maximum allowed storage|Mail quota exceeded/) {
			print REP $reg;
			next;
		}
	
		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";

}

sub get_relay_denied {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "relay_denied.csv") or die "Cannot open file [$!]";
	put_header ("5.1. RESULTADO MALA CONFIGURACION DEL SERVIDOR REMOTO AL PENSAR QUE INTENTAMOS USARLE COMO RELAY: REINTENTAR", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;

		if($reg =~ m/isn\'t allowed to relay|said: 550 Relaying mail to|Relay access denied|No relaying allowed|550 relay not permitted|550 relaying denied for|553-you are trying to use me|is currently not permitted to relay|553 sorry, that domain isn\'t in my list of allowed rcpthosts|550 5\.7\.1 Unable to relay/) {
			print REP $reg;
			next;
		}

		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";
}

sub get_false_checks {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "false_checks.csv") or die "Cannot open file [$!]";
	put_header ("5.2. RESULTADO MALA CONFIGURACION DEL SERVIDOR REMOTO PUES ESO ES FALSO (5.7.1): REINTENTAR", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;

		if($reg =~ m/554 5\.7\.1 IP Blacklisted globally|Client host rejected: cannot find your reverse hostname/) {
			print REP $reg;
			next;	
		}
	
		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";

}

sub get_tls_required {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "tls_required.csv") or die "Cannot open file [$!]";
	put_header ("6. REQUIERE TLS (5.0.0)", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;

		if($reg =~ m/said: 530 Must issue a STARTTLS command first/) {
			print REP $reg;
			next;
		}
	
		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";
}



sub  get_sec_policies {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "sec_policies.csv") or die "Cannot open file [$!]";
	put_header ("7.1. SPAM & BANNED: RESULTADO POLITICAS DE SEGURIDAD (5.7.0)", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;

		if($reg =~ m/Local Policy Violation|Direccion Invalida/) {
			print REP $reg;
			next;
		}
	
		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";
}

sub  get_spam {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "spam.csv") or die "Cannot open file [$!]";
	put_header ("7.2. SPAM & BANNED: DETECTED AS SPAM (5.7.1) & FILTER BY USER (5.3.0)", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";

	foreach my $reg (<RAW>) {
		chomp $reg;

		if($reg =~ m/550 5\.7\.1 Message rejected as spam by Content Filtering|554 5\.7\.1 This message has been blocked because it contains a banned word|553 5\.3\.0 Mensaje rechazado por la politica AntiSpam|Your message has not reached its recipient as it has been quarantined|The email message was detected as spam|\.\.\. Access denied \(in reply to RCPT TO command\)|550 5\.7\.1 Unable to deliver to|said: 554 5\.7\.1 Your message has been rejected by a custom SPAM filter|al no cumplir con nuestras politicas anti-spam|550 5\.7\.1 Requested action not taken: message refused|Recipient address rejected: Unknown recipient|Your message has not reached its recipient as it has been quarantined by our anti-spam system as potential spam|550 5\.7\.1 HC87/) {
			print REP $reg;
			next;
		}
	
		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;
	copy "resto.csv", "raw.csv";
}



sub  get_banned {

    	open(RAW, ">" , "raw.csv") or die "Cannot open file [raw.csv]";
    	select((select(RAW), $|=1)[0]);

	open(REP, ">" , "banned.csv") or die "Cannot open file [$!]";
	put_header ("7.3. SPAM & BANNED: BANNED (5.0.0)", \*REP);
	open(REST, ">" , "resto.csv") or die "Cannot open file [$!]";
	put_header ("8. RESTO (OTROS)", \*RESTO);

	foreach my $reg (<RAW>) {
		chomp $reg;


		if($reg =~ m/571 Message Refused|550 \#5\.1\.0 Address rejected|Recipient address rejected: Access denied|550 Denied by policy|550 Access Denied|said: 550 Envelope blocked - User Entry|554 rejecting banned content|said: 554 DT:SPM|said: 500 5\.0\.0 Service unavailable/) {
			print REP $reg;
			next;
		}
	
		print REST $reg;
	}

	close REST;
	close REP;
	close RAW;

}

sub classify_report_data {

	get_user_unknowns();
	get_host_domain_not_found();
	get_user_disabled();
	get_full_or_over_quota();
	get_relay_denied();
	get_false_checks();
	get_tls_required();
	get_sec_policies();
	get_spam();
	get_banned();

}


sub generate_csv {

	my @reports = ("user_unknowns.csv", "host_domain_not_found.csv", "user_disabled.csv", "full_or_over_quota.csv", "relay_denied.csv", "false_checks.csv", "tls_required.csv", "sec_policies.csv", "spam.csv", "banned.csv", "resto.csv");

	my $report_file= $header_to . "_bounced_" . $start_time2 . "_" . $end_time2 . ".csv";
	open REP, '>>' ,$report_file or die $!;


	foreach my $report (@reports) {
		open(R, "<", $report ) or die "Cannot open file [$!]";
		print REP <R>;
		close R;
	}

	unlink @reports or warn "Problem unlinking @reports: $!";	

}



########################### MAIN #################


my $opt_string = 'f:t:';
getopts( "$opt_string", \%opt );

connect_server;
get_dates;
get_messages;
get_report_data;
classify_report_data;
generate_csv;
disconnect_server;


