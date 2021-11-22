#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Attribute::Pure;

sub double :Pure { 2 * shift; }

sub double_all :PureList { map { 2 * shift } @_ }

sub positive_integers :PureList { 1 .. shift } # context dependant!

cmp_ok(double(7), '==', 14, "Pure sub call works");

my @l = double_all(1..5);

is_deeply(\@l, [2, 4, 6, 8, 10], "Pure List sub also works");

my @p = positive_integers(9);

is_deeply(\@p, [1..9], "Second check");

my $z = 7;
cmp_ok(double($z), '==', 14, "Impure call works");

is_deeply([double_all(@l)], [4, 8, 12, 16, 20], "Impure list call works");

$z = &double(8);
cmp_ok($z, '==', 16, "Forced impure call works");

done_testing;
