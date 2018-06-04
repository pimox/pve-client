package PVE::APIClient::Commands::remote;

use strict;
use warnings;

use PVE::JSONSchema qw(register_standard_option get_standard_option);
use PVE::APIClient::Config;

use PVE::CLIHandler;

use PVE::APIClient::LWP;
use PVE::PTY ();

use base qw(PVE::CLIHandler);

my $complete_remote_name = sub {

    my $config = PVE::APIClient::Config->new();
    return $config->remote_names;
};

register_standard_option('pveclient-remote-name', {
    description => "The name of the remote.",
    type => 'string',
    pattern => qr(\w+),
    completion => $complete_remote_name,
});

sub read_password {
   return PVE::PTY::read_password("Remote password: ")
}

__PACKAGE__->register_method ({
    name => 'list',
    path => 'list',
    method => 'GET',
    description => "List remotes from your config file.",
    parameters => {
	additionalProperties => 0,
    },
    returns => { type => 'null' },
    code => sub {
	my $config = PVE::APIClient::Config->new();
	my $known_remotes = $config->remote_names;

	printf("%10s %10s %10s %10s %100s\n", "Name", "Host", "Port", "Username", "Fingerprint");
	for my $name (@$known_remotes) {
	    my $remote = $config->lookup_remote($name);
	    printf("%10s %10s %10s %10s %100s\n", $name, $remote->{'host'},
		$remote->{'port'}, $remote->{'username'}, $remote->{'fingerprint'});
	}

	return undef;
    }});

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
		description => "The host.",
		type => 'string',
		format => 'address',
	    },
	    username => {
		description => "The username.",
		type => 'string',
	    },
	    password => {
		description => "The users password",
		type => 'string',
	    },
	    port => {
		description => "The port",
		type => 'integer',
		optional => 1,
		default => 8006,
	    }
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $config = PVE::APIClient::Config->new();
	my $known_remotes = $config->remotes;

	if (exists($known_remotes->{$param->{name}})) {
	    die "Remote \"$param->{name}\" exists, remove it first\n";
	}

	my $last_fp = 0;
	my $api = PVE::APIClient::LWP->new(
	    username                => $param->{username},
	    password                => $param->{password},
	    host                    => $param->{host},
	    port                    => $param->{port} // 8006,
	    manual_verification     => 1,
	    register_fingerprint_cb => sub {
		my $fp = shift @_;
		$last_fp = $fp;
	    },
	);
	$api->login();

	$config->add_remote($param->{name}, $param->{host}, $param->{port} // 8006, 
			    $last_fp, $param->{username}, $param->{password});
	$config->save;

	return undef;
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
    add => [ __PACKAGE__, 'add', ['name', 'host', 'username']],
    remove => [ __PACKAGE__, 'remove', ['name']],
    list => [__PACKAGE__, 'list'],
};

1;
