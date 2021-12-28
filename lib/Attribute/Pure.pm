use strict;
use warnings;
package Attribute::Pure;

our $VERSION = '0.01';

use Carp ();
use mro ();

# ABSTRACT: Make any perl sub inlineable, not just constant ones

use XSLoader;

XSLoader::load(__PACKAGE__, $VERSION);

sub Attribute::Pure::Attr::MODIFY_CODE_ATTRIBUTES {
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

	return $pkg->next::can ? $pkg->next::method(@attr) : @attr;
}

sub import {
	my $t = caller()//Carp::croak("Can't figure out which package to import into");
	no strict 'refs';
	push @{$t . "::ISA"}, 'Attribute::Pure::Attr';
}

1;

=head1 NAME

Attribute::Pure - make any perl sub inlineable

=head1 SYNOPSIS

	use Attribute::Pure;
	sub square :Pure { shift ** 2; }

=head1 DESCRIPTION

Perl natively allows subroutines satisfying specific constraints to be "inlined" into the calling code.

Such subroutines are known as "L<constant functions|perlsub/"Constant Functions">", and their constraints are:

=over 4

=item * Must have a prototype consisting of an empty string

=item * Must consist of exactly a single constant expression.

=back

In addition to these constant subroutines, perl supports the notion of "constant folding", like many other languages, in which
combinations of constants, operators (such as C<+> and C<*>), and builtin functions (such as C<sqrt> and C<atan2>) can be condensed to a single
constant value as the program is read rather than re-calculating it each time.

This Pure attribute allows for user-defined subroutines to participate in this constant folding. When a marked subroutine's parameters
consist only of constant expressions (or there no parameters at all), the entire subroutine is executed as soon as its parsed, and its
result is placed inline in the surrounding code. As such, a Pure subroutine could be seen as an expansion of the constant subroutine,
in that there is no longer a constrain on the prototype (or even that there is any prototype at all), and that more extensive calculations
can be performed within the sub's body.

=head1 ATTRIBUTES

User-defined pure subroutines are marked using the :Pure or :PureList attribute. Use only one or the other.

A subroutine marked with :Pure produces exactly one result, much like a scalar variable. A subroutine marked with :PureList may produce any
number of results, such as a list.

Unlike constant functions, no constraints are placed on the body of the subroutine: you may perform any actions, calculations, or processes
that you wish, though care must be taken in consideration of the timing of when the subroutine is running in relation to other code. In practice,
you may wish to avoid such a subroutine having external side-effects. Although a subroutine requiring no arguments will appear to function as
if it was a constant subroutine, care must be taken to note that :Pure does not necessarily cause the subroutine to qualify as a constant subroutine,
unless the :Pure subroutine also satisfies those constrains.

A :Pure subroutine can be used to define a constant subroutine (provided, of course, that the inlining is successful).

If pure-call evaluation should encounter a fatal error, the pure-call evaluation is abandoned, and the call is treated as if a non-constant
argument was present.

It is not necessarily possible to reliably determine that a :Pure or :PureList sub is being evaluated as a "pure call". If for some reason you
truly need to know, some options you might look for:

=over 4

=item * Somewhere in the L<caller()|perlfunc/"caller"> stack you will find an 'C<eval { ... }>' frame. It will very likely be the most immediate frame.

=item * Naturally every single one of your arguments are constants and as such have C<SvREADONLY> set.

=item * Said eval frame is likely to be either the bottom-most frame, or on top of a require, do, or (string) eval frame.

=item * If your sub is used by the 'main' code, you might find that C<${^GLOBAL_PHASE} eq "START">.

=item * If your sub is used in the same file, you'll find that exec-time code has not yet run, and only BEGIN blocks up to the call site have.

=back

In addition to the inlining behavior, a subroutine marked :Pure will always run as if it was called in scalar context, regardless of how it was
actually called, and likewise a subroutine marked :PureList will always run as if it was called in list context, regardless of how it was
actually called. In the case that a :PureList subroutine was actually called in scalar context, the result is the number of items in the list.

Like with prototypes, the :Pure and :PureList attributes only work if perl can determine at parsing time which subroutine is being called. As such
it does not work for object or package methods called using method invocation syntax, nor does it work for anonymous subs stored by reference in
a scalar. It also does not work for calls prefixed with the & character, and it does not work on calls made before the sub declaration is in place.
