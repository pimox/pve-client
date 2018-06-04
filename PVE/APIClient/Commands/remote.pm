package PVE::APIClient::Commands::remote;

use strict;
use warnings;

use PVE::JSONSchema qw(register_standard_option get_standard_option);
use PVE::APIClient::Config;

use PVE::CLIHandler;

use base qw(PVE::CLIHandler);

my $complete_remote_name = sub {

    my $config = PVE::APIClient::Config->new();
    my $known_remotes = $config->remotes;

    return [keys %{$known_remotes}];
};

register_standard_option('pveclient-remote-name', {
    description => "The name of the remote.",
    type => 'string',
    pattern => qr([\w\d\.\-\_]+),
    completion => $complete_remote_name,
});

__PACKAGE__->register_method ({
    name => 'add',
    path => 'add',
    method => 'POST',
    description => "Add a remote to your config file.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    name => get_standard_option('pveclient-remote-name', { completion => sub {} }),
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
	    name => get_standard_option('pveclient-remote-name'),
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
