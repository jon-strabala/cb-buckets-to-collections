#!/usr/bin/perl

#
# Jon A. Strabala, CustomConvertBucketToCollections generation script.
# Couchbase, Inc.
# Enjoy
#


$bucket         = &promptUser("Enter the bucket (or source) to convert to collections      ","travel-sample");
$userpass       = &promptUser("Enter the username:password to your cluster                 ","admin:jtester");
$clusterip      = &promptUser("Enter the hostname or ip address of your cluster            ","localhost");
$dest_bkt_scope = &promptUser("Enter the destination bucket.scope                          ","mybucket.myscope");
$dest_evtmeta   = &promptUser("Enter the Eventing storage keyspace bucket.scope.collection ","rr100.eventing.metadata");
$workers        = &promptUser("Enter the number of workers (LTE # cores more is faster)    ","8");
$probe          = &promptUser("Probe the bucket (or source) to determine the set of types  ","Y");

if ($probe eq "Y") {
    # only needed for INFER
    $samples        = &promptUser("  samples across the bucket (or source) to find types       ","20000");
    $values         = &promptUser("  maximum estimated # of types in the bucket (or source)    ","30");
}

if ($probe eq "Y") {
    print STDERR "\nScanning $bucket for 'type' property this may take a few seconds\n\n";

    $cmd = "curl -s -u $userpass http://${clusterip}:8093/query/service -d 'statement=INFER `$bucket`._default._default WITH {\"sample_size\": $samples, \"num_sample_values\": $values, \"similarity_metric\": 0.1}' | jq '.results[][].properties.type.samples | .[]' | sort -u ";
    print STDERR "$cmd\n\n";

    open(FI,"$cmd |") || die "error opening infer pipeline";
    while(<FI>) {
	    chomp;
	    $_ =~ s/"//g;
	    push @types, $_;
	    # print STDERR $_ . "\n";
    }
    close FI;
} else {
    $tlist          = &promptUser("Enter the type or set types to convert to collections       ","airline airport");
    @types = split(/\s+/, $tlist);
}

print STDERR "TYPES FOUND: @types\n\n";
print STDERR "Generating Eventing Function: CustomConvertBucketToCollections.json\n\n";

open(FILE, 'CustomConvertBucketToCollections.template') or die "Can't read file 'filename' [$!]\n";  
$template = <FILE>; 
close (FILE);  

#========= comments ============
$accum = "";
foreach ( @types ) {
   $tmp = '//       \\"bucket alias\\", \\"__COLTARG__\\",       \\"__TBKT__.__TSCP__.__COLTARG__\\",     \\"read and write\\"\\r\\n';
   $tmp =~ s/__COLTARG__/$_/g;
   $accum = $accum . $tmp;
}
$template =~ s/__COMMENTS__/$accum/;

#========= javascript ============
$accum = "    if (!doc.type) return;\\r\\n\\r\\n    var type = doc.type;\\r\\n    if (DROP_TYPE) delete doc.type;\\r\\n\\r\\n";
foreach ( @types ) {
   $tmp = "    if (type === '__COLTARG__') {\\r\\n        if (DO_COPY) a___COLTARG__[meta.id] = doc;\\r\\n        if (DO_DELETE) delete a_source[meta.id];\\r\\n    }\\r\\n";
   $tmp =~ s/__COLTARG__/$_/g;
   $accum = $accum . $tmp;
}
$template =~ s/__CODEHERE__/$accum/;

#========= binding aliases ============
$accum = "";
foreach ( @types ) {
   $tmp = ', { "alias": "a___COLTARG__", "bucket_name": "__TBKT__", "scope_name": "__TSCP__", "collection_name": "__COLTARG__", "access": "rw" }';
   $tmp =~ s/__COLTARG__/$_/g;
   $accum = $accum . $tmp;
}
$template =~ s/__ALIASES__/$accum/;

#========= description ============
$cnt = $#types +1;
$template =~ s/__Description__/Convert BUCKET into COLLECTIONS for $cnt types: @types/;

#========= misc subsitutions ============
($tbkt,$tscp) = split(/\./, $dest_bkt_scope);
($ebkt,$escp,$ecol) = split(/\./, $dest_evtmeta);

$template =~ s/__SOURCE__/$bucket/g;
$template =~ s/__EBKT__/$ebkt/g;
$template =~ s/__ESCP__/$escp/g;
$template =~ s/__ECOL__/$ecol/g;
$template =~ s/__TBKT__/$tbkt/g;
$template =~ s/__TSCP__/$tscp/g;
$template =~ s/__WORKERS__/$workers/g;

open(FH, '>', "CustomConvertBucketToCollections.json") or die $!; 
print FH "$template"; 
close(FH);

print STDERR "Generating Keyspace commands: MakeCustomKeyspaces.sh\n\n";
open(FH, '>', "MakeCustomKeyspaces.sh") or die $!; 

($user,$pass) = split(/:/, $userpass);

print FH "\n# SAMPLE: Eventing Storage\n\n";
print FH "couchbase-cli bucket-create -c ${clusterip}:8091 -u $user -p $pass --bucket=$ebkt --bucket-type=couchbase --bucket-eviction-policy fullEviction --bucket-ramsize=100 --bucket-replica=0 --enable-flush=1 --wait\n";
print FH "couchbase-cli collection-manage --create-scope $escp --bucket $ebkt -u $user -p $pass -c ${clusterip}:8091\n";
print FH "couchbase-cli collection-manage --create-collection $escp.$ecol --bucket $ebkt -u $user -p $pass -c ${clusterip}:8091\n";

print FH "\n# SAMPLE: Target bucket.scope.collections\n\n";
print FH "couchbase-cli bucket-create -c ${clusterip}:8091 -u $user -p $pass --bucket=$tbkt --bucket-type=couchbase --bucket-eviction-policy fullEviction --bucket-ramsize=100 --bucket-replica=0 --enable-flush=1 --wait\n";
print FH "couchbase-cli collection-manage --create-scope $tscp --bucket $tbkt -u $user -p $pass -c ${clusterip}:8091\n";
foreach ( @types ) {
    print FH "couchbase-cli collection-manage --create-collection $tscp.$_ --bucket $tbkt -u $user -p $pass -c ${clusterip}:8091\n";
}

print FH "\n# IMPORT THE FUNCTION (must not exist)\n\n";
print FH "couchbase-cli eventing-function-setup -c  ${clusterip}:8091 -u $user -p $pass --import --name CustomConvertBucketToCollections --file CustomConvertBucketToCollections.json\n";

close(FH);


#----------------------------(  promptUser  )-----------------------------#
#                                                                         #
#  FUNCTION:	promptUser                                                #
#                                                                         #
#  PURPOSE:	Prompt the user for some type of input, and return the    #
#		input back to the calling program.                        #
#                                                                         #
#  ARGS:	$promptString - what you want to prompt the user with     #
#		$defaultValue - (optional) a default value for the prompt #

sub promptUser {

   local($promptString,$defaultValue) = @_;

   if ($defaultValue) {
      print STDERR $promptString, "[", $defaultValue, "]: ";
   } else {
      print STDERR $promptString, ": ";
   }

   $| = 1;               # force a flush after our print
   $_ = <STDIN>;         # get the input from STDIN (presumably the keyboard)

   chomp;

   if ("$defaultValue") {
      return $_ ? $_ : $defaultValue;    # return $_ if it has a value
   } else {
      return $_;
   }
}
