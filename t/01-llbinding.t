#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Attribute::Pure;

sub double { 2 * shift; }

sub double_all { map { 2 * shift } @_ }

sub positive_integers { 1 .. shift } # context dependant!

ok(Attribute::Pure::_activate_for_sub_scalar(\&double), "Verify scalar setup");

ok(Attribute::Pure::_activate_for_sub_list(\&double_all), "Verify list setup");

done_testing;
