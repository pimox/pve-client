package PVE::APIClient::Commands::remote;

use strict;
use warnings;

use PVE::CLIHandler;

use base qw(PVE::CLIHandler);

__PACKAGE__->register_method ({
    name => 'add',
    path => 'add',
    method => 'POST',
    description => "Add a remote to your config file.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    name => {
		description => "The name of the remote.",
		type => 'string',
	    },
	    host => {
		description => "The host, either host, host:port or https://host:port",
		type => 'string',
	    },
	    username => {
		description => "The username.",	
		type => 'string',
		optional => 1,
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	die "implement me";

    }});

__PACKAGE__->register_method ({
    name => 'remove',
    path => 'remove',
    method => 'DELETE',
    description => "Removes a remote from your config file.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    name => {
		description => "The name of the remote.",
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
    add => [ __PACKAGE__, 'add', ['name', 'host']],
    remove => [ __PACKAGE__, 'remove', ['name']],
};

1;
