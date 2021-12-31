#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Attribute::Pure;

our $w;

sub double :Pure {
	$w = wantarray;
	2 * shift;
}

sub double_all :PureList {
	$w = wantarray;
	map { 2 * shift } @_
}

sub positive_integers :PureList {
	$w = wantarray;
	2 .. shift
} # context dependant!

my $z;
my @z;

$z = double 7;
BEGIN { ok(defined($w) && !$w, "pure scalar context") }

@z = double_all 1..5;
BEGIN { ok($w, "pure list context") }

$z = double $z;
ok(defined($w) && !$w, "impure scalar context");

@z = double_all 1 .. $z;
ok($w, "impure list context");

$z = double_all 4..7;
BEGIN { ok($w, "Pure list sub stays list context when called in scalar"); }
cmp_ok($z, '==', 4, "Scalarized list constant is the number of items");

@z = double 6;
BEGIN { ok(defined ($w) && !$w, "Pure scalar sub stays scalar context when called in list"); }


$. = 0; # If .. goes scalar it becomes flipflop, and scalar(2 .. shift) -> scalar( ($. == 2) .. shift)
$z = positive_integers 9;
BEGIN { ok($w, "This also stayed in list context"); }
cmp_ok($z, '==', 8, "Scalarized list is the number of items");

$. = 7;
$z = double_all 1 .. $.;
ok($w, "Impure call in scalar context to pure list still runs as list");
cmp_ok($z, '==', 7, "Scalarized impure pure list is still the number of items");

@z = double $z;
ok(defined($w) && !$w, "Impure scalar pure-sub is still called in scalar context inside a list");
is_deeply(\@z, [14], "Sanity exists");

$z = positive_integers($. * 2);
ok($w, "This too stayed in list context and didn't turn into a flipflop");
cmp_ok($z, '==', 13, "And is still the number of items");

# Now for the monkey wrench: &name calling disables all forms of "sub mangling", both 
$z = &positive_integers(8);
ok(defined($w) && !$w, "ampersand bypass suppresses forced context");
ok(!$z, "flip-flop works");

done_testing;
