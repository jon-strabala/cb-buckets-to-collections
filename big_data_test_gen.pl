#!/usr/bin/perl 
use Getopt::Long qw(GetOptions);

# This perl script, 'big_data_test_gen.pl', will generate test JSON data 
# with 80 differt types, for later importing into couchbase.

my $blk = 0;
my $num = 0;
my $help = 0;
GetOptions(
    'blk=i' => \$blk,
    'num=i' => \$num,
    'help' => \$help,
) or die "Usage: $0 --blk # --num #\n";

if ($num == 0 || $help != 0 || $blk < 1) {
    printf stderr "Usage: $0 --blk # --num #\n";
    die "examples:\n\tdata_gen.pl --blk 1 --num 1000000\n\tdata_gen.pl --blk 2 --num 1000000\n";
}


$template = '{"type":"t_TTT_","id":_XXX_,"dummy":"not_set"}';

my $beg = 1 + ($blk-1) * $num;
my $max = $beg + $num - 1;

my $wrk = "";
for ($j=$beg; $j<=$max; $j=$j+1) {
    $wrk = $template;
    my $tn = $j % 80 +1;
    $wrk =~ s/_XXX_/$j/;
    if ($tn < 10) {
        $wrk =~ s/_TTT_/0$tn/;
    } else {
        $wrk =~ s/_TTT_/$tn/;
    }
    printf $wrk . "\n";
}
