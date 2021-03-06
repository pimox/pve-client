#!/usr/bin/perl

use strict;
use warnings;
use Storable;

use PVE::RESTHandler;
use PVE::API2;

sub remove_code_refs {
    my ($tree) = @_;

    my $class = ref($tree);
    return if !$class;

    if ($class eq 'ARRAY') {
	foreach my $el (@$tree) {
	    remove_code_refs($el);
	}
    } elsif ($class eq 'HASH') {
	foreach my $k (keys %$tree) {
	    if (my $itemclass = ref($tree->{$k})) {
		if ($itemclass eq 'CODE') {
		    undef $tree->{$k};
		} elsif ($itemclass eq 'Regexp') {
		    $tree->{$k} = "$tree->{$k}"; # return string representation
		} else {
		    remove_code_refs($tree->{$k});
		}
	    }
	}
    }
}

my $root = {
    path => '/',
    text => '',
    children =>  PVE::RESTHandler::api_dump('PVE::API2', undef, 1),
    info => {
	GET =>  PVE::API2->map_method_by_name('index'),
    },
};

remove_code_refs($root);
Storable::store_fd($root, \*STDOUT);

exit(0);
