#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Attribute::Pure;

sub double :Pure { 2 * shift; }

sub double_all :PureList { map { 2 * shift } @_ }

sub positive_integers :PureList { 1 .. shift } # context dependant!

ok(Attribute::Pure::is_pure(\&double), "Verify is pure");
ok(Attribute::Pure::is_pure(\&double_all), "Also is pure");
ok(Attribute::Pure::is_pure(\&positive_integers), "This too");

done_testing;
