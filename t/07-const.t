#!/usr/bin/perl

use strict;
use warnings;

use B ();
use B::Deparse ();

use Test::More;

use Attribute::Pure;

sub double :Pure { 2 * shift; }

sub fourteen :prototype() { double(7); }

my $cref = \&fourteen;

ok(!Attribute::Pure::contains_impurities($cref), "Contains no impure calls");

my $cv = B::svref_2object($cref);

ok($cv->CvFLAGS & B::CVf_CONST, "Has the constant flag");


my $testsub = sub { shift() + fourteen; };

my $dp = B::Deparse->new;

my $testcode = $dp->coderef2text($testsub);

ok($testcode !~ /fourteen/, "Reference to fourteen() does not appear in a compiled sub");

done_testing;
