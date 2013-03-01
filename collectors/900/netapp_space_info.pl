#!/usr/bin/perl

use strict;
use warnings;

use Net::SNMP qw(:snmp);

my $hostname = 'netapp01';
my %NETAPP_STORAGE;
my $tsdb_server = 'tsdb01.company.com';
my $tsdb_server_port = '4242';
my %VOLUME_TYPES = ( '1' => 'Vol', '2' => 'FlexVol', '3' => 'Aggr');

### NETAPP SNMP VOLUME INFO
# dfTable			1.3.6.1.4.1.789.1.5.4
# dfEntry			1.3.6.1.4.1.789.1.5.4.1
# dfIndex			1.3.6.1.4.1.789.1.5.4.1.1
# dfFileSys			1.3.6.1.4.1.789.1.5.4.1.2
# dfKBytesTotal			1.3.6.1.4.1.789.1.5.4.1.3
# dfKBytesUsed			1.3.6.1.4.1.789.1.5.4.1.4
# dfKBytesAvail			1.3.6.1.4.1.789.1.5.4.1.5
# dfPerCentKBytesCapacity	1.3.6.1.4.1.789.1.5.4.1.6
# dfInodesUsed			1.3.6.1.4.1.789.1.5.4.1.7
# dfInodesFree			1.3.6.1.4.1.789.1.5.4.1.8
# dfPerCentInodeCapacity	1.3.6.1.4.1.789.1.5.4.1.9
# dfMountedOn			1.3.6.1.4.1.789.1.5.4.1.10
# dfMaxFilesAvail		1.3.6.1.4.1.789.1.5.4.1.11
# dfMaxFilesUsed		1.3.6.1.4.1.789.1.5.4.1.12
# dfMaxFilesPossible		1.3.6.1.4.1.789.1.5.4.1.13
# dfHighTotalKBytes		1.3.6.1.4.1.789.1.5.4.1.14
# dfLowTotalKBytes		1.3.6.1.4.1.789.1.5.4.1.15
# dfHighUsedKBytes		1.3.6.1.4.1.789.1.5.4.1.16
# dfLowUsedKBytes		1.3.6.1.4.1.789.1.5.4.1.17
# dfHighAvailKBytes		1.3.6.1.4.1.789.1.5.4.1.18
# dfLowAvailKBytes		1.3.6.1.4.1.789.1.5.4.1.19
# dfStatus			1.3.6.1.4.1.789.1.5.4.1.20
# dfMirrorStatus		1.3.6.1.4.1.789.1.5.4.1.21
# dfPlexCount			1.3.6.1.4.1.789.1.5.4.1.22
# dfType		`	1.3.6.1.4.1.789.1.5.4.1.23
# dfHighSisSharedKBytes		1.3.6.1.4.1.789.1.5.4.1.24
# dfLowSisSharedKBytes		1.3.6.1.4.1.789.1.5.4.1.25
# dfHighSisSavedKBytes		1.3.6.1.4.1.789.1.5.4.1.26
# dfLowSisSavedKBytes		1.3.6.1.4.1.789.1.5.4.1.27
# dfPerCentSaved		1.3.6.1.4.1.789.1.5.4.1.28
# df64TotalKBytes		1.3.6.1.4.1.789.1.5.4.1.29
# df64UsedKBytes		1.3.6.1.4.1.789.1.5.4.1.30
# df64AvailKBytes		1.3.6.1.4.1.789.1.5.4.1.31
# df64SisSharedKBytes		1.3.6.1.4.1.789.1.5.4.1.32
# df64SisSavedKBytes		1.3.6.1.4.1.789.1.5.4.1.33

my ($session, $error) = Net::SNMP->session(
   -version     => 'snmpv2c',
   -nonblocking => 1,
   -hostname    => $hostname,
   -community   => 'public',
   -port        => 161
);

if (!defined($session)) {
   printf("ERROR: %s.\n", $error);
   exit 1;
}

my $netappVolumeTable = '1.3.6.1.4.1.789.1.5.4.1';

my $result = $session->get_bulk_request(
   -callback       => [\&table_cb, {}],
   -maxrepetitions => 10,
   -varbindlist    => [$netappVolumeTable]
);

if (!defined($result)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit 1;
}

snmp_dispatcher();

$session->close;

my $time_ran = time;
foreach my $volume ( sort { ${ $NETAPP_STORAGE{$b} }{'6'} <=> ${ $NETAPP_STORAGE{$a} }{'6'} } keys %NETAPP_STORAGE ) {
  my $volume_name = ${ $NETAPP_STORAGE{$volume} }{'2'} || next; 
  my $volume_size =  ${ $NETAPP_STORAGE{$volume} }{'29'} || next;
  my $volume_used =  ${ $NETAPP_STORAGE{$volume} }{'30'} || next;
  my $volume_type =  $VOLUME_TYPES{ ${ $NETAPP_STORAGE{$volume} }{'23'} } || next;

  my $kbytes_size = qq~netapp.kbytes.size $time_ran $volume_size netapp=$hostname type=$volume_type vol=$volume_name\n~;
  my $kbytes_used = qq~netapp.kbytes.used $time_ran $volume_used netapp=$hostname type=$volume_type vol=$volume_name\n~;

  grep(s/  / /g,$kbytes_size);
  grep(s/  / /g,$kbytes_used);

  print $kbytes_size;
  print $kbytes_used;
  }


exit 0;

sub table_cb {
   my ($session, $table) = @_;

   if (!defined($session->var_bind_list)) {

      printf("ERROR: %s\n", $session->error);

   } else {

      # Loop through each of the OIDs in the response and assign
      # the key/value pairs to the anonymous hash that is passed
      # to the callback.  Make sure that we are still in the table
      # before assigning the key/values.

      my $next;

      foreach my $oid (oid_lex_sort(keys(%{$session->var_bind_list}))) {
         if (!oid_base_match($netappVolumeTable, $oid)) {
            $next = undef;
            last;
         }
         $next = $oid;
         $table->{$oid} = $session->var_bind_list->{$oid};
      }

      # If $next is defined we need to send another request
      # to get more of the table.

      if (defined($next)) {

         $result = $session->get_bulk_request(
            -callback       => [\&table_cb, $table],
            -maxrepetitions => 10,
            -varbindlist    => [$next]
         );

         if (!defined($result)) {
            printf("ERROR: %s\n", $session->error);
         }

      } else {

         # We are no longer in the table, so print the results.

         foreach my $oid (oid_lex_sort(keys(%{$table}))) {
            #printf("%s => %s\n", $oid, $table->{$oid});
            my @oid_bits = split('\.',$oid);
            ${ $NETAPP_STORAGE{$oid_bits[-1]} }{$oid_bits[-2]} = $table->{$oid};
         }

      }
   }
}

