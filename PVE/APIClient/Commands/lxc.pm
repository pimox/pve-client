package PVE::APIClient::Commands::lxc;

use strict;
use warnings;

use PVE::CLIHandler;

use base qw(PVE::CLIHandler);

__PACKAGE__->register_method ({
    name => 'enter',
    path => 'enter',
    method => 'POST',
    description => "Enter container console.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    vmid => {
		description => "The container ID",
		type => 'string',
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	die "implement me";

    }});

__PACKAGE__->register_method ({
    name => 'list',
    path => 'list',
    method => 'GET',
    description => "List containers.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => {
		description => "The remote name.",
		type => 'string',
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	die "implement me";

    }});


our $cmddef = {
    enter => [ __PACKAGE__, 'enter', ['vmid']],
    list => [ __PACKAGE__, 'list', ['remote']],
};

1;
