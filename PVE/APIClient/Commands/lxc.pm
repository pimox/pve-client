package PVE::APIClient::Commands::lxc;

use strict;
use warnings;
use JSON;
use File::HomeDir;

use PVE::Tools;
use PVE::CLIHandler;

use base qw(PVE::CLIHandler);

my $load_config = sub {

    my $filename = home() . '/.pveclient';
    my $conf_str = PVE::Tools::file_get_contents($filename);

    my $filemode = (stat($filename))[2] & 07777;
    if ($filemode != 0600) {
	die sprintf "wrong permissions on '$filename' %04o (expected 0600)\n", $filemode;
    }

    return decode_json($conf_str);
};

my $load_remote_config = sub {
    my ($remote) = @_;

    my $conf = $load_config->();

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
	    remote => {
		description => "The name of the remote.",
		type => 'string',
	    },
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
    enter => [ __PACKAGE__, 'enter', ['remote', 'vmid']],
    list => [ __PACKAGE__, 'list', ['remote']],
};

1;
