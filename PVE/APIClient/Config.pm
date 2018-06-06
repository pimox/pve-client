package PVE::APIClient::Config;

use strict;
use warnings;
use JSON;

use PVE::JSONSchema qw(register_standard_option get_standard_option);
use PVE::SectionConfig;
use PVE::Tools qw(file_get_contents file_set_contents);

use base qw(PVE::SectionConfig);

my $complete_remote_name = sub {

    my $config = PVE::APIClient::Config->load();
    return [keys %{$config->{ids}}];
};

register_standard_option('pveclient-remote-name', {
    description => "The name of the remote.",
    type => 'string',
    pattern => qr(\w+),
    completion => $complete_remote_name,
});


my $defaultData = {
    propertyList => {
	type => {
	    description => "Section type.",
	    optional => 1,
	},
	name => get_standard_option('pveclient-remote-name'),
	host => {
	    description => "The host.",
	    type => 'string', format => 'address',
	    optional => 1,
	},
	username => {
	    description => "The username.",
	    type => 'string',
	    optional => 1,
	},
	password => {
	    description => "The users password.",
	    type => 'string',
	    optional => 1,
	},
	port => {
	    description => "The port.",
	    type => 'integer',
	    optional => 1,
	    default => 8006,
	},
	fingerprint => {
	    description => "Fingerprint.",
	    type => 'string',
	    optional => 1,
	},
	comment => {
	    description => "Description.",
	    type => 'string',
	    optional => 1,
	    maxLength => 4096,
	},
    },
};

sub type {
    return 'remote';
}

sub options {
    return {
	name => { optional => 0 },
	host => { optional => 0 },
	comment => { optional => 1 },
	username => { optional => 0 },
	password => { optional => 1 },
	port => { optional => 1 },
	fingerprint => { optional => 1 },
   };
}

sub private {
    return $defaultData;
}

sub config_filename {
    my ($class) = @_;

    my $home = $ENV{HOME};

    die "environment HOME not set\n" if !defined($home);

    return "$home/.pveclient";
}

sub load {
    my ($class) = @_;

    my $filename = $class->config_filename();

    my $raw = '';

    if (-e $filename) {
	my $filemode = (stat($filename))[2] & 07777;
	if ($filemode != 0600) {
	    die sprintf "wrong permissions on '$filename' %04o (expected 0600)\n", $filemode;
	}

	$raw = file_get_contents($filename);
    }

    return $class->parse_config($filename, $raw);
}

sub save {
    my ($class, $cfg) = @_;

    my $filename = $class->config_filename();
    my $raw = $class->write_config($filename, $cfg);

    file_set_contents($filename, $raw, 0600);
}

sub lookup_remote {
    my ($class, $cfg, $name, $noerr) = @_;

    my $data = $cfg->{ids}->{$name};

    return $data if $noerr || defined($data);

    die "unknown remote \"$name\"\n";
}

sub remote_conn {
    my ($class, $cfg, $remote) = @_;

    my $section = $class->lookup_remote($cfg, $remote);

    my $password = $section->{password};
    if (!defined($password)) {
	$password = PVE::PTY::read_password("Remote password: ")
    }

    my $conn = PVE::APIClient::LWP->new(
	username                => $section->{username},
	password                => $password,
	host                    => $section->{host},
	port                    => $section->{port} // 8006,
	cached_fingerprints     => {
	    $section->{fingerprint} => 1,
	}
    );

    $conn->login;

    return $conn;
}

__PACKAGE__->register();
__PACKAGE__->init();

1;
