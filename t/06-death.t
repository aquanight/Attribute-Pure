#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Attribute::Pure;

our $lock;

BEGIN { $lock = 0; }
$lock = 1;

my $p;

sub pure_but_not :Pure {
	$p = ${^GLOBAL_PHASE};
	die "No" unless $lock;
	return 2 * shift;
}

my $proc;

ok(eval { $proc = sub { return pure_but_not(14); }; 1; }, "Can compile a sub with a pure call that dies during purity");

is($p, "START", "It tried though");

ok(Attribute::Pure::contains_impurities($proc), "A dead purecall results in an impure call");

is($proc->(), 28, "The call retries at runtime");

done_testing;
