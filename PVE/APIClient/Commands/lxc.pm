package PVE::APIClient::Commands::lxc;

use strict;
use warnings;

use PVE::Tools;
use PVE::JSONSchema qw(get_standard_option);
use PVE::CLIHandler;

use base qw(PVE::CLIHandler);
use PVE::APIClient::Config;

my $load_remote_config = sub {
    my ($remote) = @_;

    my $conf = PVE::APIClient::Config::load_config();

    my $remote_conf = $conf->{"remote_$remote"} ||
	die "no such remote '$remote'\n";

    foreach my $opt (qw(hostname username password fingerprint)) {
	die "missing option '$opt' (remote '$remote')" if !defined($remote_conf->{$opt});
    }

    return $remote_conf;
};

my $get_remote_connection = sub {
    my ($remote) = @_;

    my $conf = $load_remote_config->($remote);

    return PVE::APIClient::LWP->new(
	username => $conf->{username},
	password => $conf->{password},
	host => $conf->{hostname},
	cached_fingerprints => {
	    $conf->{fingerprint} => 1
	});
};

__PACKAGE__->register_method ({
    name => 'enter',
    path => 'enter',
    method => 'POST',
    description => "Enter container console.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    remote => get_standard_option('pveclient-remote-name'),
	    vmid => {
		description => "The container ID",
		type => 'string',
	    },
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $conn = $get_remote_connection->($param->{remote});
	my $node = 'localhost'; # ??

	my $api_path = "api2/json/nodes/$node/lxc/$param->{vmid}";

	my $res = $conn->get($api_path, {});

	print to_json($res, { pretty => 1, canonical => 1});
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
	    remote => get_standard_option('pveclient-remote-name'),
	},
    },
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	die "implement me";

    }});


our $cmddef = {
    enter => [ __PACKAGE__, 'enter', ['remote', 'vmid']],
    list => [ __PACKAGE__, 'list', ['remote']],
};

1;
