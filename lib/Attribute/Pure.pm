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
