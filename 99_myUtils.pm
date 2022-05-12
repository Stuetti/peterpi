##############################################
# $Id: myUtilsTemplate.pm 21509 2020-03-25 11:20:51Z rudolfkoenig $
#
# Save this file as 99_myUtils.pm, and create your own functions in the new
# file. They are then available in every Perl expression.

package main;

use strict;
use warnings;
use XML::XPath;

sub
myUtils_Initialize($$)
{
  my ($hash) = @_;
}

# Enter you functions below _this_ line.
sub getHilinkSession() {
	my $sesfull = qx(curl -s -X GET http://192.168.8.1/api/webserver/SesTokInfo);
	my $xp = XML::XPath->new( xml => $sesfull );
	my $ses = $xp->find('//response/SesInfo/text()');
	my $tok = $xp->find('//response/TokInfo/text()');
	Log3 "getHilinkSession", 3, "Session: ".$ses;
	Log3 "getHilinkSession", 3, "Token: ".$tok;
	return ($ses, $tok);
}

sub getSmsCount() {
	my ($ses, $tok) = getHilinkSession();
	
	my $smsCountXML = qx(curl -H \"Cookie: SessionID=$ses\" -H \"X-Requested-With: XMLHttpRequest\" -H \"__RequestVerificationToken: $tok\" -H \"Content-Type:text/xml\" \"http://192.168.8.1/api/sms/sms-count\");
	my $smsCount = XML::XPath->new( xml => $smsCountXML );
	my $smsUnread = $smsCount->find('//response/LocalUnread/text()');
	my $smsAll = $smsCount->find('//response/LocalInbox/text()');
	Log3 "getSmsCount", 3, "Total SMS: ".$smsAll;
	Log3 "getSmsCount", 3, "Unread SMS: ".$smsUnread;
	return ($smsUnread);
}

sub readLatestSms() {
	my ($ses, $tok) = getHilinkSession();
	my $dat = "<request><PageIndex>1</PageIndex><ReadCount>1</ReadCount><BoxType>1</BoxType><SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>1</UnreadPreferred></request>";
		
	my $sms = qx(curl -H \"Cookie: SessionID=$ses\" -H \"X-Requested-With: XMLHttpRequest\" -H \"__RequestVerificationToken: $tok\" -H \"Content-Type:text/xml\" --data \"$dat\" \"http://192.168.8.1/api/sms/sms-list\");
	my $smsMessage = XML::XPath->new( xml => $sms );

	my $smsIndex = $smsMessage->find('//response/Messages/Message/Index/text()');
	my $smsContent = $smsMessage->find('//response/Messages/Message/Content/text()');
	$smsContent =~ s/^\s+|\s+$//g ;
	my $smsDate = $smsMessage->find('//response/Messages/Message/Date/text()');
	my $smsPhone = $smsMessage->find('//response/Messages/Message/Phone/text()');
	
	Log3 "readLatestSms", 3, "Nachricht: ".$smsContent." Absender: ".$smsPhone." Datum: ".$smsDate." Index: ".$smsIndex;;
	return ($smsIndex, $smsContent, $smsDate, $smsPhone);
}

sub setReadSms {
	my ($smsIndex) = @_;
	my ($ses, $tok) = getHilinkSession();
	my $dat = "<request><Index>".$smsIndex."</Index></request>";
	my $smsSetRead = qx(curl -H \"Cookie: SessionID=$ses\" -H \"X-Requested-With: XMLHttpRequest\" -H \"__RequestVerificationToken: $tok\" -H \"Content-Type:text/xml\" --data \"$dat\" \"http://192.168.8.1/api/sms/set-read\");
	Log3 "setReadSms", 3, "Return of SMS set read: ".$smsSetRead;
	
	my $response = XML::XPath->new( xml => $smsSetRead );
	my $responseVal = $response->find('//response/text()');
	if ($responseVal ne "ok") {
		Log3 "setReadSms", 1, "Return of SMS set read not ok: ".$smsSetRead;
	}
	#return $smsSetRead;
}

sub deleteSms {
	my ($smsIndex) = @_;
	my ($ses, $tok) = getHilinkSession();
	my $dat = "<request><Index>".$smsIndex."</Index></request>";
	my $smsDelete = qx(curl -H \"Cookie: SessionID=$ses\" -H \"X-Requested-With: XMLHttpRequest\" -H \"__RequestVerificationToken: $tok\" -H \"Content-Type:text/xml\" --data \"$dat\" \"http://192.168.8.1/api/sms/delete-sms\");
	Log3 "deleteSms", 3, "Return of SMS delete: ".$smsDelete;
	
	my $response = XML::XPath->new( xml => $smsDelete );
	my $responseVal = $response->find('//response/text()');
	if (lc $responseVal ne "ok") {
		Log3 "deleteSms", 1, "Return of SMS delete not ok: ".$smsDelete;
	}
	#return $smsDelete;
}

sub getSMS() {
	#https://github.com/kenshaw/hilink/blob/master/client.go
	my $number = "";
	my $allowedNumbers = AttrVal("LastSMS", "allowedNumbers", "+491234567890");
	my @phoneNumbers = split(/\s+/, $allowedNumbers);
	#Log3 "getSMS", 3, "AttrNumbers: ".$allowedNumbers;
	#foreach $number (@phoneNumbers) {
	#	Log3 "getSMS", 3, "Number: ".$number;
	#}
	
	my ($smsUnread) = getSmsCount();

	if (int($smsUnread) == 0) {
		Log3 "getSMS", 3, "Keine ungelesenen SMS";
	}
	if (int($smsUnread) >= 1) {
		Log3 "getSMS", 3, "Anzahl ungelesene SMS: ".$smsUnread;
		#SMS lesen
		my ($smsIndex, $smsContent, $smsDate, $smsPhone) = readLatestSms();
		
		if (grep { $_ eq $smsPhone } @phoneNumbers) {
			#Werte in dummy schreiben
			fhem("setreading LastSMS ".$smsDate." smsContent ".$smsContent);
			fhem("setreading LastSMS ".$smsDate." smsIndex ".$smsIndex);
			fhem("setreading LastSMS ".$smsDate." smsPhone ".$smsPhone);
			# SMS löschen
			deleteSms($smsIndex);
			#Funktionen:
			##phoneNumbers erweitern
			##Status abfragen
			##Fhem restart
			##System restart
			my $cmdWord = "command=";
			
			if ($smsContent eq "getFhemStatus") {
				#Email mit Werten senden
				Log3 "getSMS", 3, "getFhemStatus";
				SYSMON_ShowValuesText('sysmon');
			}
			elsif (substr($smsContent,0,length($cmdWord)) eq $cmdWord) {
				Log3 "getSMS", 3, "Executing FHEM command: ".$smsContent;
				fhem(substr($smsContent,length($cmdWord)+1,length($smsContent)));
			}
			elsif ($smsContent eq "restartFhem") {
				Log3 "getSMS", 3, "Restarting FHEM";
				fhem("shutdown restart");
			}
			elsif ($smsContent eq "restartSystem") {
				Log3 "getSMS", 3, "Restarting SYSTEM";
			}
			else {
				Log3 "getSMS", 3, "Nothing to do";
			}
		}
		else {
			# als gelesen markieren
			# später ggf. als Email senden
			setReadSms($smsIndex);
		}
	}

}

1;
