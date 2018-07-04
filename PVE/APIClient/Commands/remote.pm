package PVE::APIClient::Commands::remote;

use strict;
use warnings;

use PVE::APIClient::Helpers;
use PVE::APIClient::JSONSchema qw(get_standard_option);
use PVE::APIClient::Tools qw(extract_param);
use PVE::APIClient::Config;

use PVE::APIClient::CLIHandler;

use PVE::APIClient::LWP;
use PVE::APIClient::PTY;

use base qw(PVE::APIClient::CLIHandler);

sub read_password {
   return PVE::APIClient::PTY::read_password("Remote password: ")
}

# define as array to keep ordering
my $remote_list_returns_properties = [
    name => get_standard_option('pveclient-remote-name'),
    host => { type => 'string', format => 'address' },
    username => { type => 'string' },
    port => { type => 'integer', optional => 1 },
    fingerprint =>  { type => 'string', optional => 1 },
    ];

__PACKAGE__->register_method ({
    name => 'remote_list',
    path => 'remote_list',
    method => 'GET',
    description => "List remotes from your config file.",
    parameters => {
	additionalProperties => 0,
	properties => {
	    'format' => get_standard_option('pve-output-format'),
	},
    },
    returns => {
	type => 'array',
	items => {
	    type => 'object',
	    properties => { @$remote_list_returns_properties },
	},
    },
    code => sub {
	my ($param) = @_;

	my $format = PVE::APIClient::Tools::extract_param($param, 'format');
	PVE::APIClient::Helpers::set_output_format($format);

	my $config = PVE::APIClient::Config->load();

	my $res = [];
	for my $name (keys %{$config->{ids}}) {
	    my $data = $config->{ids}->{$name};
	    next if $data->{type} ne 'remote';
	    push @$res, $data;
	}

	return $res;
    }});

__PACKAGE__->register_method ({
    name => 'remote_add',
    path => 'remote_add',
    method => 'POST',
    description => "Add a remote to your config file.",
    parameters => PVE::APIClient::RemoteConfig->createSchema(1),
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $remote = $param->{name};

	# Note: we try to keep lock time sort, and lock later when we have all info
	my $config = PVE::APIClient::Config->load();

	die "Remote '$remote' already exists\n"
	    if $config->{ids}->{$remote};

	my $last_fp = 0;

	my $password = $param->{password};
	if (!defined($password)) {
	    $password = PVE::APIClient::PTY::read_password("Remote password: ");
	}

	my $setup = {
	    username                => $param->{username},
	    password                => $password,
	    host                    => $param->{host},
	    port                    => $param->{port} // 8006,
	};

	if ($param->{fingerprint}) {
	    $setup->{cached_fingerprints} = {
		$param->{fingerprint} => 1,
	    };
	} else {
	    $setup->{manual_verification} = 1;
	    $setup->{register_fingerprint_cb} = sub {
		my $fp = shift @_;
		$last_fp = $fp;
	    };
	}

	my $api = PVE::APIClient::LWP->new(%$setup);
	$api->login();

	$param->{fingerprint} = $last_fp if !defined($param->{fingerprint});

	my $plugin = PVE::APIClient::Config->lookup('remote');

	my $code = sub {

	    $config = PVE::APIClient::Config->load(); # reload

	    # check again (file is locked now)
	    die "Remote '$remote' already exists\n"
		if $config->{ids}->{$remote};

	    my $opts = $plugin->check_config($remote, $param, 1, 1);

	    $config->{ids}->{$remote} = $opts;

	    PVE::APIClient::Config->save($config);
	};

	PVE::APIClient::Config->lock_config(undef, $code);

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'remote_set',
    path => 'remote_set',
    method => 'PUT',
    description => "Update a remote configuration.",
    parameters => PVE::APIClient::RemoteConfig->updateSchema(1),
    returns => { type => 'null'},
    code => sub {
	my ($param) = @_;

	my $name = extract_param($param, 'name');
	my $digest = extract_param($param, 'digest');
	my $delete = extract_param($param, 'delete');

	my $code = sub {
	    my $config = PVE::APIClient::Config->load();
	    my $remote = PVE::APIClient::Config->lookup_remote($config, $name);

	    my $plugin = PVE::APIClient::Config->lookup('remote');
	    my $opts = $plugin->check_config($name, $param, 0, 1);

	    foreach my $k (%$opts) {
		$remote->{$k} = $opts->{$k};
	    }

	    if ($delete) {
		my $options = $plugin->private()->{options}->{'remote'};
		foreach my $k (PVE::APIClient::Tools::APIClient::split_list($delete)) {
		    my $d = $options->{$k} ||
			die "no such option '$k'\n";
		    die "unable to delete required option '$k'\n"
			if !$d->{optional};
		    die "unable to delete fixed option '$k'\n"
			if $d->{fixed};
		    delete $remote->{$k};
		}
	    }

	    PVE::APIClient::Config->save($config);
	};

	PVE::APIClient::Config->lock_config(undef, $code);

	return undef;
    }});

__PACKAGE__->register_method ({
    name => 'remote_delete',
    path => 'remote_delete',
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

	my $code = sub {
	    my $config = PVE::APIClient::Config->load();
	    delete $config->{ids}->{$param->{name}};
	    PVE::APIClient::Config->save($config);
	};

	PVE::APIClient::Config->lock_config(undef, $code);

	return undef;
    }});

our $cmddef = {
    add => [ __PACKAGE__, 'remote_add', ['name', 'host', 'username']],
    set => [ __PACKAGE__, 'remote_set', ['name']],
    delete => [ __PACKAGE__, 'remote_delete', ['name']],
    list => [__PACKAGE__, 'remote_list', undef, {}, sub {
	PVE::APIClient::Helpers::print_ordered_result($remote_list_returns_properties, @_);
    }],
};

1;
