#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Attribute::Pure;

our $x;

sub double :Pure { 2 * shift; }

sub double_all :PureList { map { 2 * shift } @_ }

sub positive_integers :PureList { 1 .. shift } # context dependant!

sub test_double {
	return double 7;
}

sub test_double_all {
	return double_all 1..5;
}

sub test_positive_integers {
	return positive_integers 9;
}

sub test_impure_double {
	return double $x;
}

sub test_impure_double_all {
	return double_all @ARGV;
}

sub test_impure_positive_integers {
	return positive_integers $_;
}

sub test_forced_impure {
	return &double(7);
}

ok(!Attribute::Pure::contains_impurities(\&test_double), "Verify is pure");
ok(!Attribute::Pure::contains_impurities(\&test_double_all), "Also is pure");
ok(!Attribute::Pure::contains_impurities(\&test_positive_integers), "This too");

ok(Attribute::Pure::contains_impurities(\&test_impure_double), "Verify is not pure");
ok(Attribute::Pure::contains_impurities(\&test_impure_double_all), "Also is not pure");
ok(Attribute::Pure::contains_impurities(\&test_impure_positive_integers), "This too is not pure");

ok(Attribute::Pure::contains_impurities(\&test_forced_impure), "\&name syntax forces impure call");

done_testing;
