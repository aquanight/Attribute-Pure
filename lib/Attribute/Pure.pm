use strict;
use warnings;
package Attribute::Pure 0.01;

# ABSTRACT: Make any perl sub inlineable, not just constant ones

use XSLoader;

XSLoader::load(__PACKAGE__, our $VERSION);

sub MODIFY_CODE_ATTRIBUTES {
	my ($pkg, $cv, @attr) = @_;
	
	for (my $ix = 0; $ix < @attr; ) {
		if ($attr[$ix] eq "Pure") {
			splice @attr, $ix, 1;
			_activate_for_sub_scalar($cv);
		}
		elsif ($attr[$ix] eq "PureList") {
			splice @attr, $ix, 1;
			_activate_for_sub_list($cv);
		}
		else {
			++$ix;
		}
	}

	return @attr;
}

sub import {
	my $t = caller()//die("Can't figure out which packaage to import into");
	no strict 'refs';
	push @{$t . "::ISA"}, __PACKAGE__;
}

1;

=head1 NAME

C<Attribute::Pure> - make any perl sub inlineable

=head1 SYNOPSIS

	use Attribute::Pure;
	sub square :Pure { shift ** 2; }

=head1 DESCRIPTION

Perl natively allows subroutines satisifying specific constraints to be "inlined" into the calling code.

Such subroutines are known as "constant functions", descibed under that header under perlsub, and their constraints are:
-> Must have a prototype consisting of an empty string
-> Must consist of exactly a single constant expression.

In addition to these constant subroutines, perl supports the notion of "constant folding", like many other languages, in which
combinations of constants, operators (such as + and *), and builtin functions (such as sqrt and atan2) can be condensed to a single
constant value as the program is read rather than re-calculating it each time.

This Pure attribute allows for user-defined subroutines to participate in this constant folding. When a marked subroutine's parameters
consist only of constant expressions (or there no parameters at all), the entire subroutine is executed as soon as its parsed, and its
result is placed inline in the surrounding code.

=head1 ATTRIBUTES

User-defined subroutines are marked using the :Pure or :PureList attribute. Use only one or the other.

A subroutine marked with :Pure is one that produces exactly one result.
A subroutine marked with :PureList may produce any number of results.

Unlike constant functions, no constaints are placed on the body of the subroutine: you may perform any actions, calculations, or processes
that you wish, though care must be taken in consideration of the timing of when the subroutine is running in relation to other code. In practice,
you may wish to avoid such a subroutine having external side-effects.

In addition to the inlining behavior, a subroutine marked :Pure will always run as if it was called in scalar context, regardless of how it was
actually called, and likewise a subroutine marked :PureList will always run as if it was called in list context, regardless of how it was
actually called. In the case that a :PureList subroutine was actually called in scalar context, the result is the number of items in the list.

Like with prototypes, the :Pure and :PureList attributes only work if perl can determine at parsing time which subroutine is being called. As such
it does not work for object or package methods called using method invocation syntax, nor does it work for anonymous subs stored by reference in
a scalar. It also does not work for calls prefixed with the & character.
